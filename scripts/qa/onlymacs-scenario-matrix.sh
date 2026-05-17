#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/onlymacs-autonomous-trusted-review.sh"

MATRIX_FILE="${ONLYMACS_MATRIX_FILE:-$SCRIPT_DIR/onlymacs-scenario-matrix.json}"
VALIDATION_DIR="${ONLYMACS_VALIDATION_DIR:-$ROOT_DIR/.tmp/validation}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="${ONLYMACS_MATRIX_LOG_PATH:-$VALIDATION_DIR/onlymacs-scenario-matrix-$TIMESTAMP.log}"
SUMMARY_PATH="${ONLYMACS_MATRIX_SUMMARY_PATH:-$VALIDATION_DIR/onlymacs-scenario-matrix-$TIMESTAMP.summary.json}"
RESULTS_PATH="${ONLYMACS_MATRIX_RESULTS_PATH:-$VALIDATION_DIR/onlymacs-scenario-matrix-$TIMESTAMP.results.jsonl}"

mkdir -p "$VALIDATION_DIR"
: >"$LOG_PATH"
: >"$RESULTS_PATH"

log() {
  printf '[onlymacs-matrix] %s\n' "$*" | tee -a "$LOG_PATH"
}

switch_runtime_swarm() {
  local target="$1"
  case "$target" in
    private)
      ensure_private_swarm
      ;;
    public)
      log "Switching runtime to public swarm"
      bridge_json POST "/admin/v1/runtime" '{"mode":"both","active_swarm_id":"swarm-public"}' >/dev/null
      ;;
    *)
      log "Unknown swarm target: $target"
      return 1
      ;;
  esac
}

request_policy_for_scenario() {
  local prompt="$1"
  local route_scope="${2:-swarm}"
  local payload
  payload="$(jq -n --arg prompt "$prompt" --arg route_scope "$route_scope" '{prompt:$prompt, route_scope:$route_scope}')"
  bridge_json POST "/admin/v1/request-policy/classify" "$payload"
}

wait_for_unexpected_approval_absence() {
  local seconds="${1:-4}"
  local deadline=$((SECONDS + seconds))
  while (( SECONDS < deadline )); do
    assert_app_alive || return 1
    if [[ "$(approval_window_exists)" == "1" ]]; then
      log "Approval window appeared unexpectedly"
      return 1
    fi
    sleep 1
  done
}

normalize_output_file() {
  local raw_file="$1"
  local normalized_file="$2"
  normalize_review_output "$raw_file" "$normalized_file"
}

resolve_scenario_repo() {
  local repo="$1"
  case "$repo" in
    __ROOT__)
      printf '%s\n' "$ROOT_DIR"
      ;;
    __ROOT__/*)
      printf '%s/%s\n' "$ROOT_DIR" "${repo#__ROOT__/}"
      ;;
    __EXTERNAL_REPO__)
      printf '%s\n' "${ONLYMACS_SCENARIO_EXTERNAL_REPO:-$ROOT_DIR/scripts/qa/fixtures/content-mini-pipeline}"
      ;;
    *)
      printf '%s\n' "$repo"
      ;;
  esac
}

assert_contract_output() {
  local contract="$1"
  local normalized_output="$2"
  local manifest_path
  manifest_path="$(latest_manifest_path || true)"

  python - "$contract" "$normalized_output" "$manifest_path" <<'PY'
import json
import re
import sys
from pathlib import Path

contract = sys.argv[1]
output_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3]) if sys.argv[3] else None
text = output_path.read_text()
lower_text = text.lower()
manifest = {}
approved = []
if manifest_path and manifest_path.exists():
    manifest = json.loads(manifest_path.read_text())
    approved = [
        file for file in manifest.get("files", [])
        if file.get("status") in {"ready", "trimmed"} and file.get("relative_path")
    ]

def require_section(name: str):
    pattern = rf'^[>\s#*\-`_]*\**{re.escape(name)}\**([\s:]*|$)'
    if not re.search(pattern, text, re.IGNORECASE | re.MULTILINE):
        raise SystemExit(f"Missing required section: {name}")

def section_body(name: str) -> str:
    pattern = rf'(?ims)^[>\s#*\-`_]*\**{re.escape(name)}\**([\s:]*|$)\s*(.*?)(?=^[>\s#*\-`_]*\**[A-Z][A-Za-z ]+\**([\s:]*|$)|\Z)'
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        return ""
    return match.group(2).strip()

def section_is_none(name: str) -> bool:
    pattern = rf'(?ims)^[>\s#*\-`_]*\**{re.escape(name)}\**([\s:]*|$)\s*none\.\s*(?=^[>\s#*\-`_]*\**[A-Z][A-Za-z ]+\**([\s:]*|$)|\Z)'
    return re.search(pattern, text, re.MULTILINE) is not None

def has_label(name: str) -> bool:
    pattern = rf'(?im)^[>\s#*\-`_]*(?:[-*]|\d+\.)?\s*\**{re.escape(name)}\**\s*:'
    return re.search(pattern, text) is not None

def require_line_cited_evidence():
    blocks = [
        line.strip()
        for line in text.splitlines()
        if re.match(r'^\s*[-*]?\s*\**evidence\**\b', line, re.IGNORECASE)
    ]
    cited_blocks = [
        block for block in blocks
        if re.search(r':[0-9]+(?:-[0-9]+)?\s*\(', block)
    ]
    if not cited_blocks:
        blocks = [
            block.strip()
            for block in re.findall(
                r'(?ims)^\s*[-*]?\s*\**evidence\**[^:\n]*:\s*(?:\n(?:[-*].*(?:\n|$))+|.*?(?=\n[A-Z][A-Za-z ]+:\s|\n### |\Z))',
                text,
            )
        ]
        cited_blocks = [
            block for block in blocks
            if re.search(r':[0-9]+(?:-[0-9]+)?\s*\(', block)
        ]
    if not blocks:
        raise SystemExit("Missing Evidence lines")
    if not cited_blocks:
        raise SystemExit("Evidence lines do not include line-aware citations")
    return cited_blocks

def require_file_references(min_count: int = 1):
    if not approved:
        raise SystemExit("No approved files were recorded for grounded output assertions")
    referenced = {
        file["relative_path"]
        for file in approved
        if file["relative_path"].lower() in lower_text
    }
    if len(referenced) < min_count:
        raise SystemExit(f"Output referenced only {len(referenced)} approved file(s)")
    return referenced

if contract == "prompt_only":
    if not text.strip():
        raise SystemExit("Prompt-only scenario returned empty output")
    if "OnlyMacs stopped this request." in text:
        raise SystemExit("Prompt-only scenario unexpectedly blocked")
    sys.exit(0)

if contract == "blocked_public":
    blocked_markers = [
        "open swarms cannot access your local files or repo",
        "is an open swarm, and open swarms cannot access your local files or repo",
        "switch to a private swarm",
    ]
    if not any(marker in lower_text for marker in blocked_markers):
        raise SystemExit("Blocked-public scenario did not explain the public-swarm restriction")
    sys.exit(0)

if contract == "local_only_recommended":
    local_only_markers = [
        "recommends keeping it on this mac",
        "keeping it on this mac",
        "local-first",
        "looks sensitive",
    ]
    if not text.strip():
        raise SystemExit("Local-only recommendation scenario returned empty output")
    if not any(marker in lower_text for marker in local_only_markers):
        raise SystemExit("Local-only recommendation scenario did not explain the local-only recommendation")
    sys.exit(0)

if contract == "grounded_review":
    for name in ("Findings", "Open Questions", "Referenced Files"):
        require_section(name)
    blocks = []
    if not section_is_none("Findings"):
        blocks = require_line_cited_evidence()
        if re.search(r'\[P[4-9]\]', text, re.IGNORECASE):
            raise SystemExit("Grounded review used unsupported severity labels")
        if re.search(r'evidence:\s*(various files|multiple files|the docs|the documents)', text, re.IGNORECASE):
            raise SystemExit("Grounded review used vague evidence")
    require_file_references(2)
    high_priority = [
        f["relative_path"]
        for f in approved
        if f.get("category") in {"Master Docs", "Overview", "Source", "Config"}
    ]
    if high_priority and not any(path.lower() in lower_text for path in high_priority):
        raise SystemExit("Grounded review never referenced a high-priority approved file")
    if blocks and not any(any(q in block for q in ['"', '“', '”', "'"]) for block in blocks):
        raise SystemExit("Grounded review did not quote headings or snippets in Evidence lines")
    sys.exit(0)

if contract == "grounded_code_review":
    for name in ("Findings", "Missing Tests", "Referenced Files"):
        require_section(name)
    require_line_cited_evidence()
    require_file_references(2)
    source_or_config = [
        f["relative_path"]
        for f in approved
        if f.get("category") in {"Source", "Config"}
    ]
    if source_or_config and not any(path.lower() in lower_text for path in source_or_config):
        raise SystemExit("Grounded code review never referenced Source or Config files")
    if re.search(r'\b(clean up|looks nicer|readability only)\b', lower_text):
        raise SystemExit("Grounded code review drifted into style-only filler")
    sys.exit(0)

if contract == "grounded_generation":
    for name in ("Proposed Output", "Open Questions", "Referenced Files"):
        require_section(name)
    if not section_is_none("Proposed Output"):
        require_line_cited_evidence()
    require_file_references(2)
    if not has_label("Target") or not has_label("Proposal"):
        if not section_is_none("Proposed Output"):
            raise SystemExit("Grounded generation output is missing Target/Proposal structure")
    if re.search(r'\b(created|saved|wrote|already generated)\b', lower_text):
        raise SystemExit("Grounded generation claimed files were already created")
    sys.exit(0)

if contract == "grounded_transform":
    for name in ("Proposed Changes", "Open Questions", "Referenced Files"):
        require_section(name)
    if not section_is_none("Proposed Changes"):
        require_line_cited_evidence()
    require_file_references(1)
    if not has_label("Target") or not has_label("Change"):
        if not section_is_none("Proposed Changes"):
            raise SystemExit("Grounded transform output is missing Target/Change structure")
    if re.search(r'\b(applied|patched|updated the file)\b', lower_text):
        raise SystemExit("Grounded transform claimed a patch was already applied")
    sys.exit(0)

raise SystemExit(f"Unknown contract: {contract}")
PY
}

append_result() {
  local scenario_id="$1"
  local status="$2"
  local detail="$3"
  jq -cn \
    --arg id "$scenario_id" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{id:$id,status:$status,detail:$detail}' >>"$RESULTS_PATH"
}

run_policy_scenario() {
  local scenario_json="$1"
  local id prompt route_scope expected_decision expected_command active_swarm_visibility response decision suggested_command
  id="$(jq -r '.id' <<<"$scenario_json")"
  prompt="$(jq -r '.prompt' <<<"$scenario_json")"
  route_scope="$(jq -r '.route_scope // "swarm"' <<<"$scenario_json")"
  expected_decision="$(jq -r '.expected_decision' <<<"$scenario_json")"
  expected_command="$(jq -r '.expected_command // empty' <<<"$scenario_json")"
  active_swarm_visibility="$(jq -r '.active_swarm_visibility // "public"' <<<"$scenario_json")"

  case "$active_swarm_visibility" in
    private) switch_runtime_swarm private ;;
    public) switch_runtime_swarm public ;;
  esac

  response="$(request_policy_for_scenario "$prompt" "$route_scope")"
  decision="$(jq -r '.decision' <<<"$response")"
  suggested_command="$(jq -r '.routing.suggested_command // empty' <<<"$response")"
  if [[ "$decision" != "$expected_decision" ]]; then
    append_result "$id" failed "expected decision $expected_decision, got $decision"
    return 1
  fi
  if [[ -n "$expected_command" && "$suggested_command" != "$expected_command" ]]; then
    append_result "$id" failed "expected command $expected_command, got $suggested_command"
    return 1
  fi
  append_result "$id" passed "policy decision $decision"
}

run_live_scenario() {
  local scenario_json="$1"
  local id prompt repo swarm expected_decision expected_route expect_approval expected_contract expected_command raw_output normalized_output pid start now route_line policy_response decision suggested_command done_seen_at
  local scenario_raw_output scenario_normalized_output
  id="$(jq -r '.id' <<<"$scenario_json")"
  prompt="$(jq -r '.prompt' <<<"$scenario_json")"
  repo="$(resolve_scenario_repo "$(jq -r '.repo' <<<"$scenario_json")")"
  swarm="$(jq -r '.swarm' <<<"$scenario_json")"
  expected_decision="$(jq -r '.expected_decision' <<<"$scenario_json")"
  expected_route="$(jq -r '.expected_route_contains // empty' <<<"$scenario_json")"
  expect_approval="$(jq -r '.expect_approval' <<<"$scenario_json")"
  expected_contract="$(jq -r '.expected_contract' <<<"$scenario_json")"
  expected_command="$(jq -r '.expected_command // empty' <<<"$scenario_json")"

  clear_file_access_state
  clear_automation_state
  case "$swarm" in
    private) switch_runtime_swarm private ;;
    public) switch_runtime_swarm public ;;
  esac

  policy_response="$(request_policy_for_scenario "$prompt" "swarm")"
  decision="$(jq -r '.decision' <<<"$policy_response")"
  suggested_command="$(jq -r '.routing.suggested_command // empty' <<<"$policy_response")"
  if [[ "$decision" != "$expected_decision" ]]; then
    append_result "$id" failed "preflight expected decision $expected_decision, got $decision"
    return 1
  fi
  if [[ -n "$expected_command" && "$suggested_command" != "$expected_command" ]]; then
    append_result "$id" failed "preflight expected command $expected_command, got $suggested_command"
    return 1
  fi

  raw_output="$(mktemp)"
  normalized_output="$(mktemp)"
  scenario_raw_output="$VALIDATION_DIR/onlymacs-scenario-$TIMESTAMP-$id.raw.log"
  scenario_normalized_output="$VALIDATION_DIR/onlymacs-scenario-$TIMESTAMP-$id.normalized.txt"
  log "Running scenario $id"
  (
    cd "$repo"
    ~/.local/bin/onlymacs-shell "$prompt"
  ) >"$raw_output" 2>&1 &
  pid=$!

  if [[ "$expect_approval" == "true" ]]; then
    wait_for_approval_and_press || {
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      append_result "$id" failed "approval flow did not complete"
      cat "$raw_output" >>"$LOG_PATH"
      cp "$raw_output" "$scenario_raw_output"
      rm -f "$raw_output" "$normalized_output"
      return 1
    }
  else
    wait_for_unexpected_approval_absence 4 || {
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      append_result "$id" failed "approval window appeared unexpectedly"
      cat "$raw_output" >>"$LOG_PATH"
      cp "$raw_output" "$scenario_raw_output"
      rm -f "$raw_output" "$normalized_output"
      return 1
    }
  fi

  start="$(date +%s)"
  done_seen_at=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    assert_app_alive || {
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      append_result "$id" failed "OnlyMacs app died during scenario"
      cat "$raw_output" >>"$LOG_PATH"
      cp "$raw_output" "$scenario_raw_output"
      rm -f "$raw_output" "$normalized_output"
      return 1
    }
    now="$(date +%s)"
    if grep -Fq 'data: [DONE]' "$raw_output"; then
      if (( done_seen_at == 0 )); then
        done_seen_at="$now"
      elif (( now - done_seen_at > 5 )); then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
        break
      fi
    fi
    if (( now - start > QA_TIMEOUT_SECONDS )); then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      append_result "$id" failed "launcher timed out"
      cat "$raw_output" >>"$LOG_PATH"
      cp "$raw_output" "$scenario_raw_output"
      rm -f "$raw_output" "$normalized_output"
      return 1
    fi
    sleep 1
  done

  wait "$pid" || true
  cat "$raw_output" >>"$LOG_PATH"
  normalize_output_file "$raw_output" "$normalized_output"
  cp "$raw_output" "$scenario_raw_output"
  cp "$normalized_output" "$scenario_normalized_output"

  if [[ -n "$expected_route" ]] && ! grep -Fq "$expected_route" "$raw_output"; then
    append_result "$id" failed "route output missing '$expected_route' ($scenario_raw_output)"
    rm -f "$raw_output" "$normalized_output"
    return 1
  fi

  if ! assert_contract_output "$expected_contract" "$normalized_output"; then
    append_result "$id" failed "contract assertion failed ($scenario_normalized_output)"
    rm -f "$raw_output" "$normalized_output"
    return 1
  fi

  if [[ "$expect_approval" == "true" ]]; then
    local manifest_path request_intent
    manifest_path="$(latest_manifest_path || true)"
    request_intent="$(jq -r '.request_intent // empty' "$manifest_path" 2>/dev/null || true)"
    if [[ -n "$request_intent" ]]; then
      append_result "$id" passed "manifest request intent $request_intent"
    else
      append_result "$id" passed "scenario completed"
    fi
  else
    append_result "$id" passed "scenario completed"
  fi

  rm -f "$raw_output" "$normalized_output"
  assert_no_automation_windows
}

run_policy_corpus_meta() {
  log "Running 100-case request policy corpus"
  (
    cd "$ROOT_DIR/apps/local-bridge"
    go test ./... -run 'TestRequestPolicyCorpus|TestRequestPolicyRoutingSuggestions|TestRequestPolicyHandlerUsesRuntimeSwarmVisibility'
  ) | tee -a "$LOG_PATH"
}

write_summary() {
  python - "$RESULTS_PATH" "$SUMMARY_PATH" <<'PY'
import json
import sys
from pathlib import Path

results_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
rows = [json.loads(line) for line in results_path.read_text().splitlines() if line.strip()]
summary = {
    "total": len(rows),
    "passed": sum(1 for row in rows if row["status"] == "passed"),
    "failed": sum(1 for row in rows if row["status"] == "failed"),
    "scenarios": rows,
}
summary_path.write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY
}

main() {
  local scenario_count filter
  filter="${ONLYMACS_SCENARIO_FILTER:-}"
  if [[ -n "$filter" ]]; then
    scenario_count="$(jq --arg filter "$filter" '[.[] | select(.id | test($filter))] | length' "$MATRIX_FILE")"
  else
    scenario_count="$(jq 'length' "$MATRIX_FILE")"
  fi
  log "Scenario matrix started with $scenario_count scenarios"
  ensure_app_running
  ensure_private_swarm
  ensure_published_model
  verify_ui_surface_control
  run_policy_corpus_meta

  if [[ -n "$filter" ]]; then
    jq -c --arg filter "$filter" '.[] | select(.id | test($filter))' "$MATRIX_FILE"
  else
    jq -c '.[]' "$MATRIX_FILE"
  fi | while IFS= read -r scenario; do
    local id mode
    id="$(jq -r '.id' <<<"$scenario")"
    mode="$(jq -r '.mode' <<<"$scenario")"
    log "Scenario $id ($mode)"
    case "$mode" in
      policy)
        run_policy_scenario "$scenario"
        ;;
      live)
        run_live_scenario "$scenario"
        ;;
      *)
        append_result "$id" failed "unknown scenario mode $mode"
        return 1
        ;;
    esac
  done

  log "Scenario matrix finished; writing summary"
  write_summary | tee -a "$LOG_PATH"
  log "Scenario matrix log saved to $LOG_PATH"
}

main "$@"
