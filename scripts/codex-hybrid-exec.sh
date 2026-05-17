#!/usr/bin/env bash
set -euo pipefail

SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
REAL_CODEX_BIN="${REAL_CODEX_BIN:-$(command -v codex)}"
MLX_PYTHON_BIN="${MLX_PYTHON_BIN:-$HOME/.venvs/onlymacs-mlx/bin/python}"
MLX_MAX_TOKENS="${MLX_MAX_TOKENS:-1200}"
LOCAL_SYSTEM_PROMPT="${LOCAL_SYSTEM_PROMPT:-}"
if [[ -z "$LOCAL_SYSTEM_PROMPT" ]]; then
  LOCAL_SYSTEM_PROMPT="You are a silent autonomous coding worker. Follow the user's instructions exactly. Do not reveal chain-of-thought. Output only the final answer. If a JSON schema is provided, output one JSON value that matches it exactly."
fi

if [[ -z "$REAL_CODEX_BIN" ]]; then
  echo "[ERROR] codex binary not found in PATH" >&2
  exit 1
fi

if [[ "$REAL_CODEX_BIN" == "$SELF_PATH" ]]; then
  echo "[ERROR] REAL_CODEX_BIN resolves to this wrapper; set REAL_CODEX_BIN to the real codex binary" >&2
  exit 1
fi

if [[ "${1:-}" != "exec" ]]; then
  exec "$REAL_CODEX_BIN" "$@"
fi

args=("$@")
model_name=""
has_oss=0
has_skip_git=0
schema_file=""
output_last_message_file=""
json_mode=0
prompt_arg=""
has_reasoning_override=0

skip_value=0
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "$skip_value" -eq 1 ]]; then
    skip_value=0
    continue
  fi
  case "${args[$i]}" in
    --model|-m)
      if (( i + 1 < ${#args[@]} )); then
        model_name="${args[$((i + 1))]}"
        skip_value=1
      fi
      ;;
    --oss)
      has_oss=1
      ;;
    --skip-git-repo-check)
      has_skip_git=1
      ;;
    --output-schema)
      if (( i + 1 < ${#args[@]} )); then
        schema_file="${args[$((i + 1))]}"
        skip_value=1
      fi
      ;;
    --output-last-message|-o)
      if (( i + 1 < ${#args[@]} )); then
        output_last_message_file="${args[$((i + 1))]}"
        skip_value=1
      fi
      ;;
    --json)
      json_mode=1
      ;;
    -c|--config)
      if (( i + 1 < ${#args[@]} )); then
        case "${args[$((i + 1))]}" in
          model_reasoning_effort=*|profiles.*.model_reasoning_effort=*)
            has_reasoning_override=1
            ;;
        esac
        skip_value=1
      fi
      ;;
    exec|-C|--cd|--sandbox|--profile)
      if [[ "${args[$i]}" == "-C" || "${args[$i]}" == "--cd" || "${args[$i]}" == "--sandbox" || "${args[$i]}" == "--profile" ]]; then
        skip_value=1
      fi
      ;;
    -*)
      ;;
    *)
      prompt_arg="${args[$i]}"
      ;;
  esac
done

is_local_model=0
local_backend=""
if [[ -n "$model_name" ]]; then
  if ollama show "$model_name" >/dev/null 2>&1; then
    is_local_model=1
    local_backend="ollama"
  elif [[ -x "$MLX_PYTHON_BIN" && ( "$model_name" == */* || "$model_name" == mlx:* ) ]]; then
    is_local_model=1
    local_backend="mlx"
  fi
fi

if [[ "$has_skip_git" -eq 0 ]]; then
  args+=(--skip-git-repo-check)
fi

collect_prompt_text() {
  prompt_text="$prompt_arg"
  if [[ -z "$prompt_text" || "$prompt_text" == "-" ]]; then
    prompt_text="$(cat)"
  fi

  if [[ -n "$schema_file" && -f "$schema_file" ]]; then
    schema_text="$(cat "$schema_file")"
    prompt_text="$prompt_text

STRICT OUTPUT REQUIREMENTS:
- Return only the final response body.
- Do not include markdown fences.
- Do not include explanations before or after the response.
- Do not expose chain-of-thought.
- Follow this JSON schema exactly:
$schema_text"
  fi
}

normalize_structured_response() {
  LOCAL_RESPONSE_TEXT="$1" python3 <<'PY'
import json
import os
import sys

text = os.environ["LOCAL_RESPONSE_TEXT"].strip()

if not text:
    raise SystemExit("Local model returned an empty response")

def candidate_blocks(raw: str):
    yield raw
    if "```" in raw:
        parts = raw.split("```")
        for block in parts[1::2]:
            cleaned = block.strip()
            if "\n" in cleaned:
                cleaned = cleaned.split("\n", 1)[1].strip()
            if cleaned:
                yield cleaned

def balanced_json_snippets(raw: str):
    starts = "{["
    matching = {"{": "}", "[": "]"}
    for i, ch in enumerate(raw):
        if ch not in starts:
            continue
        stack = [matching[ch]]
        for j in range(i + 1, len(raw)):
            cur = raw[j]
            if cur in matching:
                stack.append(matching[cur])
            elif stack and cur == stack[-1]:
                stack.pop()
                if not stack:
                    yield raw[i : j + 1]
                    break

for candidate in candidate_blocks(text):
    try:
        parsed = json.loads(candidate)
    except Exception:
        pass
    else:
        sys.stdout.write(json.dumps(parsed, separators=(",", ":")))
        raise SystemExit(0)

for candidate in balanced_json_snippets(text):
    try:
        parsed = json.loads(candidate)
    except Exception:
        continue
    sys.stdout.write(json.dumps(parsed, separators=(",", ":")))
    raise SystemExit(0)

raise SystemExit(f"Could not extract valid JSON from local model response: {text[:400]}")
PY
}

sanitize_local_response() {
  LOCAL_RESPONSE_TEXT="$1" python3 <<'PY'
import os
import re
import sys

text = os.environ["LOCAL_RESPONSE_TEXT"]
cleaned = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
if "</think>" in cleaned:
    cleaned = cleaned.rsplit("</think>", 1)[-1]
cleaned = cleaned.strip()
sys.stdout.write(cleaned if cleaned else text.strip())
PY
}

run_ollama_local() {
  local base_url
  base_url="${CODEX_OSS_BASE_URL:-${OLLAMA_API_BASE:-http://127.0.0.1:11434}}"
  base_url="${base_url%/}"
  if [[ "$base_url" == */v1 ]]; then
    base_url="${base_url%/v1}"
  fi

  OLLAMA_BASE_URL="$base_url" \
  OLLAMA_MODEL_NAME="$model_name" \
  OLLAMA_PROMPT_TEXT="$prompt_text" \
  python3 <<'PY'
import json
import os
import sys
import urllib.request

base_url = os.environ["OLLAMA_BASE_URL"].rstrip("/")
model = os.environ["OLLAMA_MODEL_NAME"]
prompt = os.environ["OLLAMA_PROMPT_TEXT"]

payload = json.dumps({
    "model": model,
    "prompt": prompt,
    "stream": False,
    "options": {
        "temperature": 0
    }
}).encode("utf-8")

req = urllib.request.Request(
    f"{base_url}/api/generate",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)

with urllib.request.urlopen(req, timeout=3600) as response:
    data = json.loads(response.read().decode("utf-8"))

text = data.get("response", "")
if not isinstance(text, str):
    raise SystemExit("Ollama response missing string 'response' field")

sys.stdout.write(text)
PY
}

run_mlx_local() {
  local mlx_model="$model_name"
  if [[ "$mlx_model" == mlx:* ]]; then
    mlx_model="${mlx_model#mlx:}"
  fi

  printf '%s' "$prompt_text" | \
    "$MLX_PYTHON_BIN" -m mlx_lm generate \
      --model "$mlx_model" \
      --system-prompt "$LOCAL_SYSTEM_PROMPT" \
      --prompt - \
      --max-tokens "$MLX_MAX_TOKENS" \
      --temp 0 \
      --verbose False
}

if [[ "$is_local_model" -eq 1 || "$has_oss" -eq 1 ]]; then
  collect_prompt_text

  if [[ -z "$local_backend" ]]; then
    local_backend="ollama"
  fi

  if [[ "$local_backend" == "mlx" ]]; then
    local_response="$(run_mlx_local)"
  else
    local_response="$(run_ollama_local)"
  fi

  local_response="$(sanitize_local_response "$local_response")"

  if [[ -n "$schema_file" && -f "$schema_file" ]]; then
    local_response="$(normalize_structured_response "$local_response")"
  fi

  if [[ -n "$output_last_message_file" ]]; then
    printf '%s' "$local_response" > "$output_last_message_file"
  fi

  if [[ "$json_mode" -eq 1 ]]; then
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"type":"thread.started","thread_id":"local-%s"}\n' "$(date +%s)"
    printf '{"type":"turn.started"}\n'
    printf '{"type":"turn.completed","usage":{"provider":"%s","model":"%s"},"timestamp":"%s"}\n' "$local_backend" "$model_name" "$timestamp"
  else
    printf '%s\n' "$local_response"
  fi
  exit 0
fi

if [[ "$has_reasoning_override" -eq 0 && "${args[0]:-}" == "exec" ]]; then
  args=(exec -c 'model_reasoning_effort="high"' "${args[@]:1}")
fi

if [[ "${args[0]:-}" == "exec" ]]; then
  temp_home="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-shell-openai.XXXXXX")"
  mkdir -p "$temp_home/.codex"

  if [[ -f "$HOME/.codex/auth.json" ]]; then
    cp "$HOME/.codex/auth.json" "$temp_home/.codex/auth.json"
  fi
  if [[ -f "$HOME/.codex/installation_id" ]]; then
    cp "$HOME/.codex/installation_id" "$temp_home/.codex/installation_id"
  fi

  cleanup() {
    rm -rf "$temp_home"
  }
  trap cleanup EXIT

  exec env \
    HOME="$temp_home" \
    CODEX_HOME="$temp_home/.codex" \
    "$REAL_CODEX_BIN" "${args[@]}"
fi

exec "$REAL_CODEX_BIN" "${args[@]}"
