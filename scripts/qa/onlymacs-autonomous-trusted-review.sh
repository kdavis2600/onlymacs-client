#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${ONLYMACS_APP_PATH:-$ROOT_DIR/dist/OnlyMacs.app}"
APP_BINARY="$APP_PATH/Contents/MacOS/OnlyMacsApp"
BRIDGE_URL="${ONLYMACS_BRIDGE_URL:-http://127.0.0.1:4318}"
QA_REPO="${1:-$ROOT_DIR}"
QA_PROMPT="${2:-review the pipeline docs in this project and tell me what is unclear, inconsistent, or likely to break when generating content}"
QA_POOL_NAME="${ONLYMACS_QA_SWARM_NAME:-Autonomous QA}"
QA_MODEL_ID="${ONLYMACS_QA_MODEL_ID:-qwen2.5-coder:32b}"
QA_TIMEOUT_SECONDS="${ONLYMACS_QA_TIMEOUT_SECONDS:-120}"
STATE_DIR="${ONLYMACS_STATE_DIR:-$HOME/.local/state/onlymacs}"
FILE_ACCESS_DIR="$STATE_DIR/file-access"
AUTOMATION_DIR="$STATE_DIR/automation"
VALIDATION_DIR="${ONLYMACS_VALIDATION_DIR:-$ROOT_DIR/.tmp/validation}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="${ONLYMACS_QA_LOG_PATH:-$VALIDATION_DIR/autonomous-trusted-review-$TIMESTAMP.log}"

mkdir -p "$VALIDATION_DIR" "$FILE_ACCESS_DIR" "$AUTOMATION_DIR"

log() {
  printf '[onlymacs-qa] %s\n' "$*" | tee -a "$LOG_PATH"
}

latest_crash_report() {
  ls -t "$HOME"/Library/Logs/DiagnosticReports/OnlyMacsApp-*.ips 2>/dev/null | head -n 1
}

app_is_running() {
  pgrep -f "$APP_BINARY" >/dev/null 2>&1
}

stop_app_processes() {
  pkill -x "OnlyMacsApp" >/dev/null 2>&1 || true
  pkill -f 'onlymacs-local-bridge' >/dev/null 2>&1 || true
  pkill -f 'onlymacs-coordinator' >/dev/null 2>&1 || true
}

assert_app_alive() {
  if app_is_running; then
    return 0
  fi
  log "OnlyMacs app is no longer running"
  local crash
  crash="$(latest_crash_report || true)"
  if [[ -n "$crash" ]]; then
    log "Latest crash report: $crash"
  fi
  return 1
}

bridge_json() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  if [[ -n "$payload" ]]; then
    curl -sf -X "$method" "$BRIDGE_URL$path" -H 'Content-Type: application/json' -d "$payload"
  else
    curl -sf -X "$method" "$BRIDGE_URL$path"
  fi
}

wait_for_bridge() {
  local start now
  start="$(date +%s)"
  while true; do
    if bridge_json GET "/admin/v1/runtime" >/dev/null 2>&1; then
      return 0
    fi
    now="$(date +%s)"
    if (( now - start > 20 )); then
      return 1
    fi
    sleep 1
  done
}

wait_for_app_start() {
  local start now
  start="$(date +%s)"
  while true; do
    if app_is_running; then
      return 0
    fi
    now="$(date +%s)"
    if (( now - start > 20 )); then
      return 1
    fi
    sleep 1
  done
}

ensure_app_running() {
  log "Relaunching OnlyMacs app for a clean automation run"
  local attempt
  for attempt in 1 2; do
    stop_app_processes
    sleep 1
    open -na "$APP_PATH" --args --onlymacs-automation-mode
    if wait_for_app_start; then
      break
    fi
    if [[ "$attempt" -eq 1 ]]; then
      log "OnlyMacs app did not appear on the first launch attempt; retrying once"
    else
      log "OnlyMacs app never appeared after launch"
      return 1
    fi
  done
  wait_for_bridge || {
    log "Bridge never became ready"
    return 1
  }
  assert_app_alive
}

ensure_private_swarm() {
  local swarm_id runtime_json
  runtime_json="$(bridge_json GET "/admin/v1/runtime")"
  if jq -e --arg name "$QA_POOL_NAME" '.active_swarm_id != "swarm-public"' >/dev/null 2>&1 <<<"$runtime_json"; then
    log "Runtime already on private swarm $(jq -r '.active_swarm_id' <<<"$runtime_json")"
    return 0
  fi

  swarm_id="$(bridge_json GET "/admin/v1/swarms" | jq -r --arg name "$QA_POOL_NAME" '.swarms[]? | select(.name == $name) | .id' | head -n 1)"
  if [[ -z "$swarm_id" ]]; then
    log "Creating private swarm '$QA_POOL_NAME'"
    swarm_id="$(bridge_json POST "/admin/v1/swarms/create" "{\"name\":\"$QA_POOL_NAME\",\"mode\":\"both\"}" | jq -r '.swarm.id')"
  fi

  log "Switching runtime to swarm $swarm_id"
  bridge_json POST "/admin/v1/runtime" "{\"mode\":\"both\",\"active_swarm_id\":\"$swarm_id\"}" >/dev/null
}

ensure_published_model() {
  local share_json
  share_json="$(bridge_json GET "/admin/v1/share/local")"
  if jq -e --arg model "$QA_MODEL_ID" '.published == true and any(.published_models[]?; .id == $model)' >/dev/null 2>&1 <<<"$share_json"; then
    log "Model $QA_MODEL_ID already published"
    return 0
  fi

  if ! jq -e --arg model "$QA_MODEL_ID" 'any(.discovered_models[]?; .id == $model)' >/dev/null 2>&1 <<<"$share_json"; then
    log "Model $QA_MODEL_ID is not discovered locally"
    return 1
  fi

  log "Publishing local model $QA_MODEL_ID"
  bridge_json POST "/admin/v1/share/publish" "{\"model_ids\":[\"$QA_MODEL_ID\"],\"slots_total\":1}" >/dev/null
}

clear_file_access_state() {
  rm -f "$FILE_ACCESS_DIR"/request-*.json "$FILE_ACCESS_DIR"/response-*.json "$FILE_ACCESS_DIR"/claim-*.json "$FILE_ACCESS_DIR"/manifest-*.json "$FILE_ACCESS_DIR"/context-*.txt 2>/dev/null || true
}

clear_automation_state() {
  rm -f "$AUTOMATION_DIR"/command-*.json "$AUTOMATION_DIR"/receipt-*.json 2>/dev/null || true
}

latest_manifest_path() {
  ls -t "$FILE_ACCESS_DIR"/manifest-*.json 2>/dev/null | head -n 1
}

normalize_review_output() {
  local raw_file="$1"
  local normalized_file="$2"

  python - "$raw_file" "$normalized_file" <<'PY'
import json
import pathlib
import sys

raw_path = pathlib.Path(sys.argv[1])
normalized_path = pathlib.Path(sys.argv[2])
lines = raw_path.read_text().splitlines()

chunks = []
for line in lines:
    if not line.startswith("data: "):
        continue
    payload = line[6:].strip()
    if payload == "[DONE]" or not payload:
        continue
    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        continue
    for choice in data.get("choices", []):
        delta = choice.get("delta") or {}
        content = delta.get("content")
        if content:
            chunks.append(content)

text = "".join(chunks).strip()
if not text:
    text = raw_path.read_text().strip()

normalized_path.write_text(text)
PY
}

assert_grounded_review_output() {
  local output_file="$1"
  local manifest_path

  manifest_path="$(latest_manifest_path || true)"
  if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
    log "No approved manifest found for review quality assertions"
    return 1
  fi

  python - "$manifest_path" "$output_file" <<'PY'
import json
import re
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
text = Path(sys.argv[2]).read_text()
lower_text = text.lower()
approved = [
    file for file in manifest.get("files", [])
    if file.get("status") in {"ready", "trimmed"} and file.get("relative_path")
]
if not approved:
    raise SystemExit("Approved manifest had no ready/trimmed files")

section_patterns = {
    "Findings": r'^[#\s-]*findings([\s:]|$)',
    "Open Questions": r'^[#\s-]*open questions([\s:]|$)',
    "Referenced Files": r'^[#\s-]*referenced files([\s:]|$)',
}
for label, pattern in section_patterns.items():
    if not re.search(pattern, text, re.IGNORECASE | re.MULTILINE):
        raise SystemExit(f"Grounded review output is missing a {label} section")

evidence_blocks = [
    block.strip()
    for block in re.findall(
        r'(?ims)^evidence[^:\n]*:\s*(?:\n(?:[-*].*(?:\n|$))+|.*?(?=\n[A-Z][A-Za-z ]+:\s|\n### |\Z))',
        text,
    )
]
if not evidence_blocks:
    raise SystemExit("Grounded review output is missing Evidence lines")
if re.search(r'\[P[4-9]\]', text, re.IGNORECASE):
    raise SystemExit("Grounded review output used unsupported severity labels outside P1-P3")
if re.search(r'evidence:\s*(various files|multiple files|the docs|the documents)', text, re.IGNORECASE):
    raise SystemExit("Grounded review output used vague evidence instead of exact approved file paths")
if not any(re.search(r':[0-9]+(?:-[0-9]+)?\s*\(', block) for block in evidence_blocks):
    raise SystemExit("Grounded review output did not include line-aware citations in Evidence blocks")

referenced_paths = {
    file["relative_path"]
    for file in approved
    if file["relative_path"].lower() in lower_text
}
if len(referenced_paths) < 2:
    raise SystemExit(f"Grounded review output referenced only {len(referenced_paths)} approved file path(s)")

if not any(any(quote in block for quote in ['"', '“', '”', "'"]) for block in evidence_blocks):
    raise SystemExit("Grounded review output did not include quoted headings or snippets in Evidence lines")

generic_patterns = [
    "the documents sometimes",
    "the docs sometimes",
    "could be clarified further",
    "might mean different things",
    "broad actions without detailed steps",
    "there are inconsistent uses of terms",
]
for pattern in generic_patterns:
    if pattern in lower_text:
        raise SystemExit(f"Grounded review output used banned generic filler: {pattern}")

high_priority = [
    file["relative_path"]
    for file in approved
    if file.get("category") in {"Master Docs", "Overview", "Source", "Config"}
]
if high_priority and not any(path.lower() in lower_text for path in high_priority):
    raise SystemExit("Grounded review output never referenced a high-priority approved file")

cross_file_candidates = [
    file["relative_path"]
    for file in approved
    if file.get("category") in {"Master Docs", "Overview", "Source", "Config", "Scripts", "Schema"}
]
if len(cross_file_candidates) >= 2:
    saw_cross_file = False
    for block in evidence_blocks:
        referenced_in_line = {
            path for path in cross_file_candidates
            if path.lower() in block.lower()
        }
        if len(referenced_in_line) >= 2:
            saw_cross_file = True
            break
    if not saw_cross_file:
        raise SystemExit("Grounded review output never compared two approved high-priority files in one Evidence line")
PY
}

send_ui_command() {
  local surface="$1"
  local action="$2"
  local section="${3:-}"
  local id created_at command_path receipt_path

  id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  created_at="$(python - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))
PY
)"
  command_path="$AUTOMATION_DIR/command-$id.json"
  receipt_path="$AUTOMATION_DIR/receipt-$id.json"

  python - <<PY
import json
from pathlib import Path
payload = {
  "id": "$id",
  "createdAt": "$created_at",
  "surface": "$surface",
  "action": "$action",
}
if "$section":
    payload["section"] = "$section"
Path("$command_path").write_text(json.dumps(payload, indent=2))
PY

  local start now
  start="$(date +%s)"
  while true; do
    assert_app_alive || return 1
    if [[ -f "$receipt_path" ]]; then
      log "UI command receipt: $(cat "$receipt_path")"
      if [[ "$(jq -r '.status' "$receipt_path")" != "handled" ]]; then
        return 1
      fi
      return 0
    fi
    now="$(date +%s)"
    if (( now - start > QA_TIMEOUT_SECONDS )); then
      log "Timed out waiting for UI command receipt for $surface/$action"
      return 1
    fi
    sleep 1
  done
}

automation_window_names() {
  osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  if not (exists process "OnlyMacsApp") then return ""
  tell process "OnlyMacsApp"
    return (name of every window) as text
  end tell
end tell
APPLESCRIPT
}

assert_no_automation_windows() {
  local names
  names="$(automation_window_names || true)"
  if [[ "$names" == *"OnlyMacs Popup"* ]] || [[ "$names" == *"OnlyMacs Automation Control Center"* ]]; then
    log "Automation windows still visible: $names"
    return 1
  fi
}

verify_ui_surface_control() {
  log "Verifying app-owned popup/control-center automation hooks"
  send_ui_command popup open models
  assert_app_alive
  send_ui_command popup close
  assert_app_alive
  assert_no_automation_windows
  send_ui_command control_center open sharing
  assert_app_alive
  send_ui_command control_center close
  assert_app_alive
  assert_no_automation_windows
}

approval_window_exists() {
  osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
  if not (exists process "OnlyMacsApp") then return "0"
  tell process "OnlyMacsApp"
    if exists window "OnlyMacs File Approval" then
      return "1"
    end if
  end tell
end tell
return "0"
APPLESCRIPT
}

latest_pending_request_id() {
  python - "$FILE_ACCESS_DIR" <<'PY'
from pathlib import Path
import json
import sys

base = Path(sys.argv[1])
latest = None
latest_created = ""
for path in base.glob("request-*.json"):
    rid = path.stem.replace("request-", "")
    if (base / f"response-{rid}.json").exists():
        continue
    try:
        payload = json.loads(path.read_text())
    except Exception:
        continue
    created = payload.get("created_at") or payload.get("createdAt") or ""
    if latest is None or created > latest_created:
        latest = rid
        latest_created = created

print(latest or "")
PY
}

pending_request_claimed() {
  local request_id
  request_id="$(latest_pending_request_id)"
  if [[ -z "$request_id" ]]; then
    return 1
  fi
  [[ -f "$FILE_ACCESS_DIR/claim-$request_id.json" ]]
}

wait_for_approval_and_press() {
  local start now request_id
  start="$(date +%s)"
  while true; do
    assert_app_alive || return 1
    request_id="$(latest_pending_request_id)"
    if [[ "$(approval_window_exists)" == "1" && -n "$request_id" ]]; then
      log "Approval window detected; approving selected files through app-owned automation"
      send_ui_command file_approval approve
      return 0
    fi
    if [[ -n "$request_id" ]] && pending_request_claimed; then
      log "Pending file request was claimed by the app; approving through app-owned automation"
      send_ui_command file_approval approve
      return 0
    fi
    now="$(date +%s)"
    if (( now - start > QA_TIMEOUT_SECONDS )); then
      log "Timed out waiting for approval window"
      return 1
    fi
    sleep 1
  done
}

run_trusted_review() {
  local output_file normalized_output pid start now
  output_file="$(mktemp)"
  normalized_output="$(mktemp)"
  log "Starting trusted review from $QA_REPO"
  (
    cd "$QA_REPO"
    ~/.local/bin/onlymacs-shell "$QA_PROMPT"
  ) >"$output_file" 2>&1 &
  pid=$!

  wait_for_approval_and_press || {
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    cat "$output_file" | tee -a "$LOG_PATH"
    rm -f "$output_file"
    return 1
  }

  start="$(date +%s)"
  while kill -0 "$pid" >/dev/null 2>&1; do
    assert_app_alive || {
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      cat "$output_file" | tee -a "$LOG_PATH"
      rm -f "$output_file"
      return 1
    }
    now="$(date +%s)"
    if (( now - start > QA_TIMEOUT_SECONDS )); then
      log "Timed out waiting for launcher completion"
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      cat "$output_file" | tee -a "$LOG_PATH"
      rm -f "$output_file"
      return 1
    fi
    sleep 1
  done

  wait "$pid" || true
  cat "$output_file" | tee -a "$LOG_PATH"
  normalize_review_output "$output_file" "$normalized_output"
  log "Normalized grounded review output:"
  cat "$normalized_output" | tee -a "$LOG_PATH"
  assert_grounded_review_output "$normalized_output"
  rm -f "$output_file"
  rm -f "$normalized_output"
  assert_no_automation_windows
}

main() {
  log "Autonomous trusted review QA started"
  clear_file_access_state
  clear_automation_state
  ensure_app_running
  ensure_private_swarm
  ensure_published_model
  verify_ui_surface_control
  run_trusted_review
  log "Autonomous trusted review QA finished; log saved to $LOG_PATH"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
