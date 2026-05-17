#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../integrations/common/onlymacs-cli.sh
source "$ROOT_DIR/integrations/common/onlymacs-cli.sh"
# shellcheck source=../coordinator-path.sh
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_coordinator_repo "$ROOT_DIR")"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-remote-contract.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export ONLYMACS_STATE_DIR="$TEMP_DIR/state"
export ONLYMACS_JSON_MODE=1
export ONLYMACS_PROGRESS=0

PROJECT_DIR="$TEMP_DIR/project"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
PROJECT_DIR="$(pwd)"

pass_count=0
fail_count=0

record_pass() {
  printf '[remote-contract] PASS %s %s\n' "$1" "$2"
  pass_count=$((pass_count + 1))
}

record_fail() {
  printf '[remote-contract] FAIL %s %s\n' "$1" "$2" >&2
  fail_count=$((fail_count + 1))
}

check() {
  local id="$1"
  local description="$2"
  shift 2
  if "$@"; then
    record_pass "$id" "$description"
  else
    record_fail "$id" "$description"
  fi
}

assert_eq() {
  [[ "${1:-}" == "${2:-}" ]]
}

assert_file() {
  [[ -f "$1" ]]
}

assert_dir() {
  [[ -d "$1" ]]
}

assert_contains() {
  local path="$1"
  local needle="$2"
  rg -q --fixed-strings "$needle" "$path"
}

reset_orchestrated_route_state() {
  unset ONLYMACS_ORCHESTRATION_PROVIDER_ID
  unset ONLYMACS_CHAT_ROUTE_PROVIDER_ID
}

headers_path="$TEMP_DIR/headers.txt"
cat >"$headers_path" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-progress
X-OnlyMacs-Resolved-Model: qwen3.6:35b-a3b-q8_0
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS

content_path="$TEMP_DIR/content.md"
printf '```javascript\nconsole.log("remote ok")\n```\n' >"$content_path"

unset ONLYMACS_RETURNS_DIR
check S01 "default inbox root is project-visible" assert_eq "$(chat_returns_root)" "$PROJECT_DIR/onlymacs/inbox"

ONLYMACS_RETURNS_DIR="$TEMP_DIR/custom-inbox"
check S02 "inbox root override is respected" assert_eq "$(chat_returns_root)" "$TEMP_DIR/custom-inbox"
unset ONLYMACS_RETURNS_DIR

prepare_chat_return_run "remote-first" "Create a JavaScript file named flash.js" "swarm"
run_dir="$ONLYMACS_CURRENT_RETURN_DIR"

check S03 "prepare creates run directory" assert_dir "$run_dir"
check S04 "prepare creates files directory" assert_dir "$run_dir/files"
check S05 "running status is written" assert_eq "$(jq -r '.status' "$run_dir/status.json")" "running"
check S06 "latest pointer starts as running" assert_eq "$(jq -r '.status' "$PROJECT_DIR/onlymacs/inbox/latest.json")" "running"
check S07 "status stores route scope" assert_eq "$(jq -r '.route_scope' "$run_dir/status.json")" "swarm"
check S08 "status stores prompt preview" assert_contains "$run_dir/status.json" "Create a JavaScript file"

printf 'remote progress text' >"$content_path"
write_chat_progress_status "$content_path" "$headers_path" 2 "running"

check S09 "progress stores output bytes" test "$(jq -r '.progress.output_bytes' "$run_dir/status.json")" -gt 0
check S10 "progress stores token estimate" test "$(jq -r '.progress.output_tokens_estimate' "$run_dir/status.json")" -gt 0
check S11 "progress stores heartbeat count" assert_eq "$(jq -r '.progress.heartbeat_count' "$run_dir/status.json")" "2"
check S12 "progress stores provider name" assert_eq "$(jq -r '.provider_name' "$run_dir/status.json")" "Charles Studio"
check S13 "progress stores owner member name" assert_eq "$(jq -r '.owner_member_name' "$run_dir/status.json")" "Charles"
check S14 "progress stores model" assert_eq "$(jq -r '.model' "$run_dir/status.json")" "qwen3.6:35b-a3b-q8_0"
check S15 "progress stores session id" assert_eq "$(jq -r '.session_id' "$run_dir/status.json")" "sess-progress"

: >"$content_path"
warmup_progress_line="$(ONLYMACS_JSON_MODE=0 ONLYMACS_PROGRESS=1 emit_chat_progress "$content_path" "$headers_path" 3 0 2>&1)"
write_chat_progress_status "$content_path" "$headers_path" 3 "running"
check S15A "no-output progress is labeled as model warmup" bash -c '[[ "$1" == *"warming model / waiting for first token"* ]]' _ "$warmup_progress_line"
check S15B "progress status stores first-token wait phase" assert_eq "$(jq -r '.progress.phase' "$run_dir/status.json")" "first_token_wait"
check S15C "progress status explains first-token wait" assert_contains "$run_dir/status.json" "first output token"

printf '```javascript\nconsole.log("remote ok")\n```\n' >"$content_path"
write_chat_return_artifact "$content_path" "$headers_path" "remote-first" "Create a JavaScript file named flash.js"
artifact_path="$run_dir/files/flash.js"

check S16 "completed artifact is saved under files" assert_file "$artifact_path"
check S17 "single code fence is stripped from saved file" assert_eq "$(cat "$artifact_path")" 'console.log("remote ok")'
check S18 "full remote answer is saved" assert_file "$run_dir/RESULT.md"
check S19 "manifest marks completion" assert_eq "$(jq -r '.status' "$run_dir/result.json")" "completed"
check S20 "status marks completion" assert_eq "$(jq -r '.status' "$run_dir/status.json")" "completed"
check S21 "latest pointer references artifact" assert_eq "$(jq -r '.artifact_path' "$PROJECT_DIR/onlymacs/inbox/latest.json")" "$artifact_path"
check S22 "completion status includes local quality-check step" assert_contains "$run_dir/status.json" "review the returned file"
check S23 "javascript artifact validation passes for valid code" assert_eq "$(jq -r '.artifact_validation.status' "$run_dir/status.json")" "passed"

sanitized="$(sanitize_return_filename '../../bad.js')"
check S24 "returned filenames cannot escape inbox" assert_eq "$sanitized" "bad.js"

prepare_chat_return_run "remote-first" "Create a Markdown file named failed.md" "swarm"
failed_dir="$ONLYMACS_CURRENT_RETURN_DIR"
printf 'partial remote output' >"$content_path"
write_chat_failure_artifact "$content_path" "$headers_path" "remote-first" "Create a Markdown file named failed.md" "swarm"

check S25 "failed run with partial output stores partial status" assert_eq "$(jq -r '.status' "$failed_dir/status.json")" "partial"
check S26 "failed run preserves partial output" assert_file "$failed_dir/RESULT.partial.md"
check S27 "failed latest pointer references partial run" assert_eq "$(jq -r '.status' "$PROJECT_DIR/onlymacs/inbox/latest.json")" "partial"

prepare_chat_return_run "remote-first" "Create a JavaScript file named broken.js" "swarm"
broken_dir="$ONLYMACS_CURRENT_RETURN_DIR"
printf '```javascript\nconst broken = [\n```\n' >"$content_path"
write_chat_return_artifact "$content_path" "$headers_path" "remote-first" "Create a JavaScript file named broken.js"

check S28 "invalid javascript returns completed with warnings" assert_eq "$(jq -r '.status' "$broken_dir/status.json")" "completed_with_warnings"
check S29 "invalid javascript validation failure is recorded" assert_eq "$(jq -r '.artifact_validation.status' "$broken_dir/status.json")" "failed"

bar="$(chat_progress_bar 3)"
check S30 "progress bar is ascii and bounded" bash -c '[[ "$1" == "[===>..............]" ]]' _ "$bar"
activity_body="$(printf 'data: {"choices":[{"delta":{"content":"recovered final body"}}]}\n\ndata: [DONE]\n\n' | base64)"
recovered_path="$TEMP_DIR/recovered.md"
recover_chat_content_from_activity_body "$activity_body" "$recovered_path"
check S31 "coordinator final body can recover streamed content" assert_eq "$(cat "$recovered_path")" "recovered final body"
check S32 "Codex skill tells agents to inspect inbox" assert_contains "$ROOT_DIR/integrations/codex/skills/onlymacs/SKILL.md" "onlymacs/inbox/latest.json"
check S33 "repo ignores returned inbox artifacts" assert_contains "$ROOT_DIR/.gitignore" "onlymacs/inbox/"
if [[ -f "$COORDINATOR_REPO/internal/httpapi/router.go" ]]; then
  check S34 "coordinator stream timeout is no longer a fixed 45 second cap" bash -c '! rg -q "45\\*time\\.Second|45 \\* time\\.Second" "$1/internal/httpapi/router.go"' _ "$COORDINATOR_REPO"
else
  record_pass S34 "coordinator source is not present in this checkout"
fi

marked_content="$TEMP_DIR/marked.md"
marked_output="$TEMP_DIR/marked.js"
printf 'ONLYMACS_PROGRESS step=step-01 status=working\nONLYMACS_ARTIFACT_BEGIN filename=marked.js\nconsole.log("marked ok")\nONLYMACS_ARTIFACT_END\n' >"$marked_content"
extract_marked_artifact_block "$marked_content" "$marked_output"
check S35 "machine artifact markers extract raw file content" assert_eq "$(cat "$marked_output")" 'console.log("marked ok")'

malformed_fence="$TEMP_DIR/malformed-fence.md"
malformed_output="$TEMP_DIR/malformed-fence.js"
printf '```javascript#!/usr/bin/env node\nconsole.log("fence ok")\n```' >"$malformed_fence"
extract_single_fenced_code_block "$malformed_fence" "$malformed_output"
check S36 "malformed opening code fence is stripped from artifact" assert_eq "$(head -1 "$malformed_output")" '#!/usr/bin/env node'

semantic_artifact="$TEMP_DIR/semantic.js"
printf 'const vocabList = [{ vi: "mot" }]; // ... add the remaining 2 entries here\n' >"$semantic_artifact"
validate_return_artifact "$semantic_artifact" "Create a JavaScript file named semantic.js with exactly 3 entries"
check S37 "semantic validation fails placeholders and exact-count drift" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

portuguese_count_artifact="$TEMP_DIR/portuguese-count.js"
printf 'const vocabulary = [{ portuguese: "ola" }, { portuguese: "casa" }, { portuguese: "agua" }];\n' >"$portuguese_count_artifact"
validate_return_artifact "$portuguese_count_artifact" "Create a JavaScript file named portuguese-count.js with exactly 2 entries"
check S38 "semantic validation counts Portuguese exact-count artifacts" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

portuguese_todos_artifact="$TEMP_DIR/portuguese-todos.js"
printf 'const vocabulary = [{ portuguese: "todos", english: "everyone", example: "todos = everyone" }, { portuguese: "casa", english: "house", example: "word: casa, term: casa" }];\n' >"$portuguese_todos_artifact"
validate_return_artifact "$portuguese_todos_artifact" "Create a JavaScript file named portuguese-todos.js with exactly 2 entries"
check S39 "placeholder and count validation ignore Portuguese todos and text labels" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "passed"

bad_shebang_artifact="$TEMP_DIR/bad-shebang.js"
printf '#!/usr/bin/env nodeconst vocabulary = [{ portuguese: "ola" }, { portuguese: "casa" }];\n' >"$bad_shebang_artifact"
validate_return_artifact "$bad_shebang_artifact" "Create a JavaScript file named bad-shebang.js with exactly 2 entries"
check S40 "javascript validation catches shebang line swallowing code" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

pt_count_artifact="$TEMP_DIR/pt-count.js"
printf 'const vocabulary = [{ pt: "ola" }, { pt: "casa" }, { pt: "agua" }];\n' >"$pt_count_artifact"
validate_return_artifact "$pt_count_artifact" "Create a JavaScript file named pt-count.js with exactly 2 entries"
check S41 "semantic validation counts pt exact-count artifacts" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

console_call_artifact="$TEMP_DIR/console-call.js"
printf 'console("hello");\nconst vocabulary = [{ pt: "ola" }, { pt: "casa" }];\n' >"$console_call_artifact"
validate_return_artifact "$console_call_artifact" "Create a JavaScript file named console-call.js with exactly 2 entries"
check S42 "javascript validation catches console object calls" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

external_require_artifact="$TEMP_DIR/external-require.js"
printf 'const stream = require("readable-stream");\nconst vocabulary = [{ pt: "ola" }, { pt: "casa" }];\n' >"$external_require_artifact"
validate_return_artifact "$external_require_artifact" "Create a dependency-free JavaScript file named external-require.js with exactly 2 entries"
check S43 "dependency-free javascript validation rejects external requires" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

ONLYMACS_EXECUTION_MODE=extended
orchestrated_calls=0
orchestrated_second_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  orchestrated_calls=$((orchestrated_calls + 1))
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-orchestrated
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  if [[ "$orchestrated_calls" -eq 1 ]]; then
    cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=tiny.js
const vocabList = [{ vi: "mot", en: "one" }]; // ... add the remaining 2 entries here
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
  else
    orchestrated_second_payload="$payload"
    cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=tiny.js
const vocabList = [
  { vi: "mot", en: "one" },
  { vi: "hai", en: "two" },
  { vi: "ba", en: "three" }
];
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
  fi
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create a JavaScript file named tiny.js with exactly 3 entries" "swarm"
orchestrated_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S44 "orchestrated chat writes plan manifest" assert_file "$orchestrated_dir/plan.json"
check S45 "orchestrated repair retries before warning user" assert_eq "$orchestrated_calls" "2"
check S46 "orchestrated repair prefers same provider" bash -c 'jq -e ".route_provider_id == \"provider-charles\"" <<<"$1" >/dev/null' _ "$orchestrated_second_payload"
check S47 "orchestrated final status completes after repair" assert_eq "$(jq -r '.status' "$orchestrated_dir/status.json")" "completed"
check S48 "orchestrated step records repaired attempt" assert_eq "$(jq -r '.steps[0].attempt' "$orchestrated_dir/plan.json")" "1"
check S49 "orchestrated artifact is clean raw JavaScript" bash -c 'node --check "$1/files/tiny.js" >/dev/null && ! rg -q "ONLYMACS_ARTIFACT" "$1/files/tiny.js" && ! rg -q "\x60\x60\x60" "$1/files/tiny.js"' _ "$orchestrated_dir"
check S50 "latest pointer includes plan path" assert_eq "$(jq -r '.plan_path' "$PROJECT_DIR/onlymacs/inbox/latest.json")" "$orchestrated_dir/plan.json"
check S50A "orchestrated plan saves original prompt path" assert_file "$orchestrated_dir/prompt.txt"
check S50B "orchestrated status exposes prompt path" assert_eq "$(jq -r '.prompt_path' "$orchestrated_dir/status.json")" "$orchestrated_dir/prompt.txt"
check S50C "orchestrated status exposes provider and model" bash -c 'jq -e ".provider_name == \"Charles\" and .model == \"qwen2.5-coder:32b\"" "$1/status.json" >/dev/null' _ "$orchestrated_dir"
check S50D "orchestrated status exposes step progress metadata" bash -c 'jq -e ".progress.steps_total == 1 and .progress.percent_complete == 100" "$1/plan.json" >/dev/null' _ "$orchestrated_dir"
check S50E "orchestrated status includes remote token estimate" test "$(jq -r '.token_accounting.total_remote_tokens_estimate' "$orchestrated_dir/status.json")" -gt 0
check S50E1 "orchestrated status includes local orchestration token estimate" test "$(jq -r '.token_accounting.local_orchestration_tokens_estimate' "$orchestrated_dir/status.json")" -gt 0
check S50E2 "orchestrated status exposes separate timeout policy values" bash -c 'jq -e ".timeout_policy.first_progress_timeout_seconds > 0 and .timeout_policy.idle_timeout_seconds > 0 and .timeout_policy.max_wall_clock_timeout_seconds > 0" "$1/status.json" >/dev/null' _ "$orchestrated_dir"
check S50E3 "orchestrated status includes artifact target metadata" bash -c 'jq -e ".artifact_targets[0].target_path == \"tiny.js\"" "$1/status.json" >/dev/null' _ "$orchestrated_dir"

repair_json_path="$TEMP_DIR/recoverable-json.json"
cat >"$repair_json_path" <<'JSON'
Remote preface
{
  "items": [
    {"id": "one"},
  ],
}
Remote suffix
JSON
repair_json_artifact_if_possible "$repair_json_path" "Return strict JSON."
check S50E4 "recoverable malformed JSON is repaired before model retry" bash -c '[[ "$1" == "repaired" ]] && jq -e ".items[0].id == \"one\"" "$2" >/dev/null' _ "$ONLYMACS_JSON_REPAIR_STATUS" "$repair_json_path"

ONLYMACS_EXECUTION_MODE=extended
json_repair_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  json_repair_calls=$((json_repair_calls + 1))
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-json-repair
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=repaired-plan.json
{
  "items": [
    {"id": "alpha"},
  ],
}
ONLYMACS_ARTIFACT_END
REMOTE
}
reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create a JSON file named repaired-plan.json with an items array" "swarm"
json_repair_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S50E5 "orchestrated JSON repair avoids an unnecessary model repair call" assert_eq "$json_repair_calls" "1"
check S50E6 "orchestrated JSON repair logs diagnostic metadata" assert_contains "$json_repair_dir/events.jsonl" "json_repair_applied"
check S50E7 "orchestrated JSON repair completes with valid JSON" bash -c 'jq -e ".items[0].id == \"alpha\"" "$1/files/repaired-plan.json" >/dev/null' _ "$json_repair_dir"
ONLYMACS_EXECUTION_MODE=auto

ONLYMACS_EXECUTION_MODE=extended
ONLYMACS_PLAN_FILE_PATH="$TEMP_DIR/resume-plan.md"
cat >"$ONLYMACS_PLAN_FILE_PATH" <<'PLAN'
## Step 1 - Already Done
Output: resume-a.md
Target: docs/resume-a.md
Validators: markdown, no-placeholders

## Step 2 - Remaining
Output: resume-b.md
Target: docs/resume-b.md
Depends on: step-01
Assignment Policy: validation-review
PLAN
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$ONLYMACS_PLAN_FILE_PATH"
ONLYMACS_PLAN_FILE_CONTENT="$(cat "$ONLYMACS_PLAN_FILE_PATH")"
ONLYMACS_PLAN_FILE_STEP_COUNT="$(printf '%s' "$ONLYMACS_PLAN_FILE_CONTENT" | plan_file_step_count_from_content)"
ONLYMACS_PLAN_USER_PROMPT="Execute resume plan"
prepare_chat_return_run "remote-first" "Execute resume plan" "swarm"
resume_dir="$ONLYMACS_CURRENT_RETURN_DIR"
ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON="[]"
orchestrated_write_plan "Execute resume plan" "remote-first" "swarm" 2
check S50E8 "plan manifest preserves target paths and validators from plan files" bash -c 'jq -e ".steps[0].target_paths[0] == \"docs/resume-a.md\" and (.steps[0].validators | index(\"markdown\")) and .steps[1].dependencies[0] == \"step-01\" and .steps[1].assignment_policy == \"validation-review\"" "$1/plan.json" >/dev/null' _ "$resume_dir"
mkdir -p "$resume_dir/steps/step-01/files"
printf 'done' >"$resume_dir/steps/step-01/files/resume-a.md"
printf 'done' >"$resume_dir/steps/step-01/RESULT.md"
orchestrated_update_plan_step "step-01" "completed" 0 "$resume_dir/steps/step-01/files/resume-a.md" "$resume_dir/steps/step-01/RESULT.md" "passed" "" "provider-charles" "Charles" "qwen2.5-coder:32b" "running"
resume_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  resume_calls=$((resume_calls + 1))
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-resume
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=resume-b.md
resumed
ONLYMACS_ARTIFACT_END
REMOTE
}
run_resume_orchestrated "$resume_dir"
check S50F "resume-run resumes from saved plan step" assert_eq "$resume_calls" "1"
check S50G "resume-run completes pending step" assert_eq "$(jq -r '.steps[1].status' "$resume_dir/plan.json")" "completed"
check S50H "resume-run writes final resumed artifact" assert_file "$resume_dir/files/resume-b.md"
unset ONLYMACS_ORCHESTRATION_PROVIDER_ID
unset ONLYMACS_CHAT_ROUTE_PROVIDER_ID
unset ONLYMACS_PLAN_FILE_PATH
unset ONLYMACS_RESOLVED_PLAN_FILE_PATH
unset ONLYMACS_PLAN_FILE_CONTENT
unset ONLYMACS_PLAN_FILE_STEP_COUNT
unset ONLYMACS_PLAN_USER_PROMPT
ONLYMACS_EXECUTION_MODE=auto

export ONLYMACS_CAPACITY_RETRY_LIMIT=1
export ONLYMACS_CAPACITY_RETRY_INTERVAL=0
capacity_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  capacity_calls=$((capacity_calls + 1))
  if [[ "$capacity_calls" -eq 1 ]]; then
    : >"$content"
    cat >"$headers" <<'HEADERS'
HTTP/1.1 409 Conflict
Content-Type: application/json
HEADERS
    return 22
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-capacity
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=capacity.js
console.log("capacity recovered");
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create a JavaScript file named capacity.js" "swarm"
capacity_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S51 "orchestrated chat waits and retries remote capacity conflicts" assert_eq "$capacity_calls" "2"
check S52 "orchestrated capacity retry can still complete" assert_eq "$(jq -r '.status' "$capacity_dir/status.json")" "completed"
check S53 "http status parser reads final response status" assert_eq "$(onlymacs_chat_http_status "$headers_path")" "200"

export ONLYMACS_CAPACITY_RETRY_LIMIT=0
blocked_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  blocked_calls=$((blocked_calls + 1))
  : >"$content"
  cat >"$headers" <<'HEADERS'
HTTP/1.1 409 Conflict
Content-Type: application/json
HEADERS
  return 22
}

reset_orchestrated_route_state
if run_orchestrated_chat "" "remote-first" "Create a JavaScript file named blocked.js" "swarm"; then
  blocked_rc=0
else
  blocked_rc=$?
fi
blocked_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S54 "orchestrated capacity exhaustion returns failure" test "$blocked_rc" -ne 0
check S55 "orchestrated capacity exhaustion is queued not validation failed" assert_eq "$(jq -r '.status' "$blocked_dir/status.json")" "queued"
check S56 "queued final report includes a resume command" assert_contains "$blocked_dir/status.json" "resume-run"

inline_marker="$TEMP_DIR/inline-marker.md"
inline_output="$TEMP_DIR/inline-marker.js"
printf 'ONLYMACS_ARTIFACT_BEGIN filename=inline.jsconsole.log("inline marker");\nONLYMACS_ARTIFACT_END\n' >"$inline_marker"
extract_marked_artifact_block "$inline_marker" "$inline_output"
check S57 "inline artifact marker starts are tolerated" assert_eq "$(cat "$inline_output")" 'console.log("inline marker");'

inline_json_marker="$TEMP_DIR/inline-json-marker.md"
printf 'ONLYMACS_ARTIFACT_BEGIN filename=inline.json{"ok":true}\nONLYMACS_ARTIFACT_END\n' >"$inline_json_marker"
inline_json_target="$(artifact_target_path_from_content "$inline_json_marker" 2>/dev/null || true)"
check S57A "inline artifact marker target path drops raw JSON body" assert_eq "$(safe_artifact_target_path "$inline_json_target" "inline.json")" "inline.json"
unset ONLYMACS_CAPACITY_RETRY_LIMIT
unset ONLYMACS_CAPACITY_RETRY_INTERVAL

export ONLYMACS_CHUNK_THRESHOLD=5
export ONLYMACS_CHUNK_SIZE=2
chunk_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  chunk_calls=$((chunk_calls + 1))
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-chunked
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  case "$chunk_calls" in
    1)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=chunked-vocab.entries-01.json
[
  {"vietnamese":"mot","english":"one","partOfSpeech":"number","pronunciation":"mot","difficulty":"easy","topic":"numbers","example":"Mot con meo."},
  {"vietnamese":"hai","english":"two","partOfSpeech":"number","pronunciation":"hai","difficulty":"easy","topic":"numbers","example":"Hai con cho."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    2)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=chunked-vocab.entries-02.json
[
  {"vietnamese":"ba","english":"three","partOfSpeech":"number","pronunciation":"ba","difficulty":"easy","topic":"numbers","example":"Ba cai ban."},
  {"vietnamese":"bon","english":"four","partOfSpeech":"number","pronunciation":"bon","difficulty":"easy","topic":"numbers","example":"Bon nguoi ban."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    *)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=chunked-vocab.entries-03.json
[
  {"vietnamese":"nam","english":"five","partOfSpeech":"number","pronunciation":"nam","difficulty":"easy","topic":"numbers","example":"Nam quyen sach."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
  esac
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create one self-contained dependency-free Node.js file named chunked-vocab.js with exactly 5 vocabulary entries. Include flashcards and a quiz." "swarm"
chunked_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S58 "large exact-count jobs split into remote data chunks plus local assembly" assert_eq "$(jq -r '.steps | length' "$chunked_dir/plan.json")" "4"
check S59 "chunked exact-count job only calls remote for data chunks" assert_eq "$chunk_calls" "3"
check S60 "chunked final artifact completes" assert_eq "$(jq -r '.status' "$chunked_dir/status.json")" "completed"
check S61 "chunked final artifact is the named JavaScript file" assert_file "$chunked_dir/files/chunked-vocab.js"
check S62 "chunked final artifact validates as JavaScript" bash -c 'node --check "$1/files/chunked-vocab.js" >/dev/null' _ "$chunked_dir"
check S63 "chunked final artifact preserves exact entry count" assert_eq "$(artifact_semantic_entry_count "$chunked_dir/files/chunked-vocab.js")" "5"

export ONLYMACS_CHUNK_THRESHOLD=5
export ONLYMACS_CHUNK_SIZE=5
stream_retry_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  stream_retry_calls=$((stream_retry_calls + 1))
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-stream-retry
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  if [[ "$stream_retry_calls" -eq 1 ]]; then
    printf 'ONLYMACS_ARTIFACT_BEGIN filename=retry-vocab.entries-01.json\n[{"vietnamese":"mot"' >"$content"
    return 18
  fi
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=retry-vocab.entries-01.json
[
  {"vietnamese":"mot","english":"one","partOfSpeech":"number","pronunciation":"mot","difficulty":"easy","topic":"numbers","example":"Mot con meo."},
  {"vietnamese":"hai","english":"two","partOfSpeech":"number","pronunciation":"hai","difficulty":"easy","topic":"numbers","example":"Hai con cho."},
  {"vietnamese":"ba","english":"three","partOfSpeech":"number","pronunciation":"ba","difficulty":"easy","topic":"numbers","example":"Ba cai ban."},
  {"vietnamese":"bon","english":"four","partOfSpeech":"number","pronunciation":"bon","difficulty":"easy","topic":"numbers","example":"Bon nguoi ban."},
  {"vietnamese":"nam","english":"five","partOfSpeech":"number","pronunciation":"nam","difficulty":"easy","topic":"numbers","example":"Nam quyen sach."}
]
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create one self-contained dependency-free Node.js file named retry-vocab.js with exactly 5 vocabulary entries. Include flashcards and a quiz." "swarm"
retry_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S64 "chunked stream failures retry the same step when replay is safe" assert_eq "$stream_retry_calls" "2"
check S65 "chunked stream retry completes final artifact" assert_eq "$(jq -r '.status' "$retry_dir/status.json")" "completed"
check S66 "chunked stream retry records the retry attempt" assert_eq "$(jq -r '.steps[0].attempt' "$retry_dir/plan.json")" "1"

extra_chunk="$TEMP_DIR/extra-chunk.json"
cat >"$extra_chunk" <<'JSON'
[
  {"vietnamese":"mot","english":"one","partOfSpeech":"number","pronunciation":"mot","difficulty":"easy","topic":"numbers","example":"Mot con meo."},
  {"vietnamese":"hai","english":"two","partOfSpeech":"number","pronunciation":"hai","difficulty":"easy","topic":"numbers","example":"Hai con cho."},
  {"vietnamese":"ba","english":"three","partOfSpeech":"number","pronunciation":"ba","difficulty":"easy","topic":"numbers","example":"Ba cai ban."}
]
JSON
orchestrated_normalize_chunk_artifact "$extra_chunk" "Validation for this step: exactly 2 entries/items"
check S67 "chunked JSON over-count is normalized deterministically" assert_eq "$(artifact_semantic_entry_count "$extra_chunk")" "2"
unset ONLYMACS_CHUNK_THRESHOLD
unset ONLYMACS_CHUNK_SIZE

ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON='["provider-old"]'
ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON='["provider-bad"]'
route_list_payload="$(build_chat_payload "" "Say hi." "swarm" "remote-first")"
check S68 "chat payload can carry orchestrator avoid provider IDs" bash -c 'jq -e ".avoid_provider_ids | index(\"provider-old\")" <<<"$1" >/dev/null' _ "$route_list_payload"
check S69 "chat payload can carry orchestrator exclude provider IDs" bash -c 'jq -e ".exclude_provider_ids | index(\"provider-bad\")" <<<"$1" >/dev/null' _ "$route_list_payload"
unset ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON
unset ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON

export ONLYMACS_CHUNK_THRESHOLD=5
export ONLYMACS_CHUNK_SIZE=5
stream_reroute_calls=0
stream_reroute_second_payload=""
stream_reroute_third_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  stream_reroute_calls=$((stream_reroute_calls + 1))
  if [[ "$stream_reroute_calls" -eq 2 ]]; then
    stream_reroute_second_payload="$payload"
  elif [[ "$stream_reroute_calls" -eq 3 ]]; then
    stream_reroute_third_payload="$payload"
  fi
  if [[ "$stream_reroute_calls" -le 2 ]]; then
    cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-reroute-a
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-a
X-OnlyMacs-Provider-Name: Provider A
X-OnlyMacs-Owner-Member-Name: Alpha
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
    printf 'ONLYMACS_ARTIFACT_BEGIN filename=reroute-vocab.entries-01.json\n[{"vietnamese":"mot"' >"$content"
    return 18
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-reroute-b
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-b
X-OnlyMacs-Provider-Name: Provider B
X-OnlyMacs-Owner-Member-Name: Bravo
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=reroute-vocab.entries-01.json
[
  {"vietnamese":"mot","english":"one","partOfSpeech":"number","pronunciation":"mot","difficulty":"easy","topic":"numbers","example":"Mot con meo."},
  {"vietnamese":"hai","english":"two","partOfSpeech":"number","pronunciation":"hai","difficulty":"easy","topic":"numbers","example":"Hai con cho."},
  {"vietnamese":"ba","english":"three","partOfSpeech":"number","pronunciation":"ba","difficulty":"easy","topic":"numbers","example":"Ba cai ban."},
  {"vietnamese":"bon","english":"four","partOfSpeech":"number","pronunciation":"bon","difficulty":"easy","topic":"numbers","example":"Bon nguoi ban."},
  {"vietnamese":"nam","english":"five","partOfSpeech":"number","pronunciation":"nam","difficulty":"easy","topic":"numbers","example":"Nam quyen sach."}
]
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create one self-contained dependency-free Node.js file named reroute-vocab.js with exactly 5 vocabulary entries. Include flashcards and a quiz." "swarm"
stream_reroute_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S70 "stream failure retries the same failed provider once" bash -c 'jq -e ".route_provider_id == \"provider-a\"" <<<"$1" >/dev/null' _ "$stream_reroute_second_payload"
check S71 "second stream failure reroutes with failed provider avoided" bash -c 'jq -e "(.avoid_provider_ids | index(\"provider-a\")) and (.route_provider_id == null)" <<<"$1" >/dev/null' _ "$stream_reroute_third_payload"
check S72 "stream reroute completes final artifact" assert_eq "$(jq -r '.status' "$stream_reroute_dir/status.json")" "completed"
unset ONLYMACS_CHUNK_THRESHOLD
unset ONLYMACS_CHUNK_SIZE

validation_reroute_calls=0
validation_reroute_fourth_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  validation_reroute_calls=$((validation_reroute_calls + 1))
  if [[ "$validation_reroute_calls" -eq 4 ]]; then
    validation_reroute_fourth_payload="$payload"
  fi
  if [[ "$validation_reroute_calls" -le 3 ]]; then
    cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-validation-a
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-a
X-OnlyMacs-Provider-Name: Provider A
X-OnlyMacs-Owner-Member-Name: Alpha
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
    cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=reroute-validation.js
const vocabList = [{ vi: "mot", en: "one" }]; // ... add the remaining 2 entries here
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
    return 0
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-validation-b
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-b
X-OnlyMacs-Provider-Name: Provider B
X-OnlyMacs-Owner-Member-Name: Bravo
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=reroute-validation.js
const vocabList = [
  { vi: "mot", en: "one" },
  { vi: "hai", en: "two" },
  { vi: "ba", en: "three" }
];
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create a JavaScript file named reroute-validation.js with exactly 3 entries" "swarm"
validation_reroute_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S73 "validation churn on one provider reroutes before surfacing failure" bash -c 'jq -e "(.exclude_provider_ids | index(\"provider-a\")) and (.route_provider_id == null)" <<<"$1" >/dev/null' _ "$validation_reroute_fourth_payload"
check S74 "validation reroute can still complete" assert_eq "$(jq -r '.status' "$validation_reroute_dir/status.json")" "completed"

validation_churn_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  validation_churn_calls=$((validation_churn_calls + 1))
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-validation-churn
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-a
X-OnlyMacs-Provider-Name: Provider A
X-OnlyMacs-Owner-Member-Name: Alpha
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=validation-churn.js
const vocabList = [{ vi: "mot", en: "one" }]; // ... add the remaining 2 entries here
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
if run_orchestrated_chat "" "remote-first" "Create a JavaScript file named validation-churn.js with exactly 3 entries" "swarm"; then
  validation_churn_rc=0
else
  validation_churn_rc=$?
fi
validation_churn_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S75 "validation churn returns failure after bounded repair and reroute attempts" test "$validation_churn_rc" -ne 0
check S76 "validation churn is reported distinctly" assert_eq "$(jq -r '.status' "$validation_churn_dir/status.json")" "churn"

validation_reroute_capacity_calls=0
validation_reroute_capacity_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  validation_reroute_capacity_calls=$((validation_reroute_capacity_calls + 1))
  if [[ "$validation_reroute_capacity_calls" -ge 4 ]]; then
    validation_reroute_capacity_payload="$payload"
    cat >"$headers" <<'HEADERS'
HTTP/1.1 409 Conflict
Content-Type: application/json
HEADERS
    cat >"$content" <<'REMOTE'
{"error":{"code":"NO_CAPACITY","message":"no eligible provider"}}
REMOTE
    return 1
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-validation-reroute-capacity
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-a
X-OnlyMacs-Provider-Name: Provider A
X-OnlyMacs-Owner-Member-Name: Alpha
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=validation-reroute-capacity.js
const vocabList = [{ vi: "mot", en: "one" }]; // ... add the remaining 2 entries here
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
if run_orchestrated_chat "" "remote-first" "Create a JavaScript file named validation-reroute-capacity.js with exactly 3 entries" "swarm"; then
  validation_reroute_capacity_rc=0
else
  validation_reroute_capacity_rc=$?
fi
validation_reroute_capacity_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S77 "validation reroute capacity exhaustion fails fast" test "$validation_reroute_capacity_rc" -ne 0
check S78 "validation reroute capacity exhaustion is churn not capacity wait" assert_eq "$(jq -r '.status' "$validation_reroute_capacity_dir/status.json")" "churn"
check S79 "validation reroute capacity payload excludes failed provider" bash -c 'jq -e "(.exclude_provider_ids | index(\"provider-a\"))" <<<"$1" >/dev/null' _ "$validation_reroute_capacity_payload"
check S80 "validation reroute capacity stops after the first exhausted reroute" assert_eq "$validation_reroute_capacity_calls" "4"

empty_repair_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  empty_repair_calls=$((empty_repair_calls + 1))
  if [[ "$empty_repair_calls" -ge 4 ]]; then
    cat >"$headers" <<'HEADERS'
HTTP/1.1 409 Conflict
Content-Type: application/json
HEADERS
    : >"$content"
    return 1
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-empty-repair
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-a
X-OnlyMacs-Provider-Name: Provider A
X-OnlyMacs-Owner-Member-Name: Alpha
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  if [[ "$empty_repair_calls" -eq 1 ]]; then
    cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=empty-repair.js
const vocabList = [{ vi: "mot", en: "one" }]; // ... add the remaining 2 entries here
console.log(vocabList.length);
ONLYMACS_ARTIFACT_END
REMOTE
  else
    : >"$content"
  fi
}

reset_orchestrated_route_state
if run_orchestrated_chat "" "remote-first" "Create a JavaScript file named empty-repair.js with exactly 3 entries" "swarm"; then
  empty_repair_rc=0
else
  empty_repair_rc=$?
fi
empty_repair_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S80A "empty repair attempts do not erase prior failed artifact" bash -c '[[ "$1" -ne 0 && -s "$2/steps/step-01/files/empty-repair.js" ]] && rg -q "mot" "$2/steps/step-01/files/empty-repair.js"' _ "$empty_repair_rc" "$empty_repair_dir"
check S80B "empty repair attempts keep prior raw remote answer" bash -c '[[ -s "$1/steps/step-01/RESULT.md" ]] && rg -q "mot" "$1/steps/step-01/RESULT.md"' _ "$empty_repair_dir"

export ONLYMACS_JSON_BATCH_THRESHOLD=3
export ONLYMACS_JSON_BATCH_SIZE=2
ONLYMACS_EXECUTION_MODE=extended
ONLYMACS_PLAN_FILE_PATH="$TEMP_DIR/json-plan.md"
cat >"$ONLYMACS_PLAN_FILE_PATH" <<'PLAN'
# JSON Batch Test Plan

Schema expectations:
- Items must include id and text.

## Step 1 - Items
Output: items.json

Create exactly 5 item objects total. Each item must include id and text.
PLAN
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$ONLYMACS_PLAN_FILE_PATH"
ONLYMACS_PLAN_FILE_CONTENT="$(cat "$ONLYMACS_PLAN_FILE_PATH")"
ONLYMACS_PLAN_FILE_STEP_COUNT=1
ONLYMACS_PLAN_USER_PROMPT="Execute JSON batch plan"
json_batch_calls=0
json_batch_first_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  json_batch_calls=$((json_batch_calls + 1))
  if [[ "$json_batch_calls" -eq 1 ]]; then
    json_batch_first_payload="$payload"
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-json-batch
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  case "$json_batch_calls" in
    1)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=items.batch-01.json
[{"id":"item-01","text":"one"},{"id":"item-02","text":"two"}]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    2)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=items.batch-02.json
[{"id":"item-03","text":"three"},{"id":"item-04","text":"four"}]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    *)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=items.batch-03.json
[{"id":"item-05","text":"five"}]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
  esac
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Execute JSON batch plan" "swarm"
json_batch_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S80C "plan-file exact-count JSON is batched before assembly" assert_eq "$json_batch_calls" "3"
check S80D "JSON batch prompt asks for arrays not one large object" bash -c 'prompt="$(jq -r ".messages[0].content" <<<"$1")"; [[ "$prompt" == *"batch 1 of 3"* && "$prompt" == *"strict JSON array"* ]]' _ "$json_batch_first_payload"
check S80E "JSON batches assemble into one validated artifact" bash -c '[[ "$(jq -r "length" "$1/files/items.json")" == "5" && "$(jq -r ".status" "$1/status.json")" == "completed" ]]' _ "$json_batch_dir"
check S80H "JSON batch prompt carries plan-level schema context" bash -c 'prompt="$(jq -r ".messages[0].content" <<<"$1")"; [[ "$prompt" == *"Schema expectations:"* && "$prompt" == *"Items must include id and text"* ]]' _ "$json_batch_first_payload"
unset ONLYMACS_JSON_BATCH_THRESHOLD
unset ONLYMACS_JSON_BATCH_SIZE
unset ONLYMACS_PLAN_FILE_PATH
unset ONLYMACS_RESOLVED_PLAN_FILE_PATH
unset ONLYMACS_PLAN_FILE_CONTENT
unset ONLYMACS_PLAN_FILE_STEP_COUNT
unset ONLYMACS_PLAN_USER_PROMPT
ONLYMACS_EXECUTION_MODE=auto

export ONLYMACS_ASSUME_BRIDGE_AVAILABLE=1
export ONLYMACS_BRIDGE_RETRY_LIMIT=2
bridge_retry_calls=0
stream_chat_payload_capture() {
  local _payload="$1"
  local content="$2"
  local headers="$3"
  bridge_retry_calls=$((bridge_retry_calls + 1))
  if [[ "$bridge_retry_calls" -eq 1 ]]; then
    : >"$headers"
    : >"$content"
    return 7
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-bridge-retry
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=bridge-retry.js
console.log("bridge recovered");
ONLYMACS_ARTIFACT_END
REMOTE
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create a JavaScript file named bridge-retry.js" "swarm"
bridge_retry_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S80F "local bridge outage retries after health recovery" assert_eq "$bridge_retry_calls" "2"
check S80G "local bridge retry completes without consuming the job" assert_eq "$(jq -r '.status' "$bridge_retry_dir/status.json")" "completed"
unset ONLYMACS_ASSUME_BRIDGE_AVAILABLE
unset ONLYMACS_BRIDGE_RETRY_LIMIT

lemma_duplicate_artifact="$TEMP_DIR/lemma-dupes.json"
cat >"$lemma_duplicate_artifact" <<'JSON'
[
  {"lemma":"hola","translation":"hello"},
  {"lemma":"hola","translation":"hi"}
]
JSON
validate_return_artifact "$lemma_duplicate_artifact" "Create unique items with no duplicate lemmas."
check S81 "JSON validation catches duplicate lemma terms when uniqueness is requested" assert_eq "$ONLYMACS_RETURN_VALIDATION_STATUS" "failed"

export ONLYMACS_JSON_BATCH_THRESHOLD=2
export ONLYMACS_JSON_BATCH_SIZE=2
ONLYMACS_EXECUTION_MODE=extended
ONLYMACS_PLAN_FILE_PATH="$TEMP_DIR/json-unique-plan.md"
cat >"$ONLYMACS_PLAN_FILE_PATH" <<'PLAN'
## Step 1 - Unique Items
Output: unique-items.json

Create exactly 4 item objects total. Keep every lemma unique. Each item must include id, lemma, and translation.
PLAN
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$ONLYMACS_PLAN_FILE_PATH"
ONLYMACS_PLAN_FILE_CONTENT="$(cat "$ONLYMACS_PLAN_FILE_PATH")"
ONLYMACS_PLAN_FILE_STEP_COUNT=1
ONLYMACS_PLAN_USER_PROMPT="Execute unique JSON batch plan"
json_unique_batch_calls=0
json_unique_batch_second_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  json_unique_batch_calls=$((json_unique_batch_calls + 1))
  if [[ "$json_unique_batch_calls" -eq 2 ]]; then
    json_unique_batch_second_payload="$payload"
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-json-unique-batch
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  case "$json_unique_batch_calls" in
    1)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=unique-items.batch-01.json
[{"id":"item-01","lemma":"hola","translation":"hello"},{"id":"item-02","lemma":"gracias","translation":"thanks"}]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    2)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=unique-items.batch-02.json
[{"id":"item-03","lemma":"gracias","translation":"thanks again"},{"id":"item-04","lemma":"cafe","translation":"coffee"}]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    *)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=unique-items.batch-02.json
[{"id":"item-03","lemma":"cafe","translation":"coffee"},{"id":"item-04","lemma":"agua","translation":"water"}]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
  esac
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Execute unique JSON batch plan" "swarm"
json_unique_batch_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S82 "JSON batch prompt carries earlier accepted terms for uniqueness" bash -c 'prompt="$(jq -r ".messages[0].content" <<<"$1")"; [[ "$prompt" == *"Earlier accepted terms"* && "$prompt" == *"hola"* && "$prompt" == *"gracias"* ]]' _ "$json_unique_batch_second_payload"
check S83 "JSON batch uniqueness repair retries duplicate batch" assert_eq "$json_unique_batch_calls" "3"
check S84 "JSON batch uniqueness repair completes final artifact" assert_eq "$(jq -r '.status' "$json_unique_batch_dir/status.json")" "completed"
check S85 "JSON batch uniqueness leaves no assembled duplicate terms" assert_eq "$(artifact_duplicate_vocabulary_terms "$json_unique_batch_dir/files/unique-items.json")" ""
unset ONLYMACS_JSON_BATCH_THRESHOLD
unset ONLYMACS_JSON_BATCH_SIZE
unset ONLYMACS_PLAN_FILE_PATH
unset ONLYMACS_RESOLVED_PLAN_FILE_PATH
unset ONLYMACS_PLAN_FILE_CONTENT
unset ONLYMACS_PLAN_FILE_STEP_COUNT
unset ONLYMACS_PLAN_USER_PROMPT
ONLYMACS_EXECUTION_MODE=auto

export ONLYMACS_CHUNK_THRESHOLD=5
export ONLYMACS_CHUNK_SIZE=2
duplicate_chunk_calls=0
duplicate_chunk_repair_payload=""
stream_chat_payload_capture() {
  local payload="$1"
  local content="$2"
  local headers="$3"
  duplicate_chunk_calls=$((duplicate_chunk_calls + 1))
  if [[ "$duplicate_chunk_calls" -eq 3 ]]; then
    duplicate_chunk_repair_payload="$payload"
  fi
  cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-duplicate-chunk
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles Studio
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
  case "$duplicate_chunk_calls" in
    1)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=duplicate-vocab.entries-01.json
[
  {"vietnamese":"mot","english":"one","partOfSpeech":"number","pronunciation":"mot","difficulty":"easy","topic":"numbers","example":"Mot con meo."},
  {"vietnamese":"hai","english":"two","partOfSpeech":"number","pronunciation":"hai","difficulty":"easy","topic":"numbers","example":"Hai con cho."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    2)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=duplicate-vocab.entries-02.json
[
  {"vietnamese":"hai","english":"two again","partOfSpeech":"number","pronunciation":"hai","difficulty":"easy","topic":"numbers","example":"Hai nguoi ban."},
  {"vietnamese":"ba","english":"three","partOfSpeech":"number","pronunciation":"ba","difficulty":"easy","topic":"numbers","example":"Ba cai ban."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    3)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=duplicate-vocab.entries-02.json
[
  {"vietnamese":"ba","english":"three","partOfSpeech":"number","pronunciation":"ba","difficulty":"easy","topic":"numbers","example":"Ba cai ban."},
  {"vietnamese":"bon","english":"four","partOfSpeech":"number","pronunciation":"bon","difficulty":"easy","topic":"numbers","example":"Bon nguoi ban."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
    *)
      cat >"$content" <<'REMOTE'
ONLYMACS_ARTIFACT_BEGIN filename=duplicate-vocab.entries-03.json
[
  {"vietnamese":"nam","english":"five","partOfSpeech":"number","pronunciation":"nam","difficulty":"easy","topic":"numbers","example":"Nam quyen sach."}
]
ONLYMACS_ARTIFACT_END
REMOTE
      ;;
  esac
}

reset_orchestrated_route_state
run_orchestrated_chat "" "remote-first" "Create one self-contained dependency-free Node.js file named duplicate-vocab.js with exactly 5 vocabulary entries. Include flashcards and a quiz." "swarm"
duplicate_chunk_dir="$ONLYMACS_CURRENT_RETURN_DIR"
check S86 "chunk validation repairs duplicate terms from earlier chunks" assert_eq "$duplicate_chunk_calls" "4"
check S87 "chunk repair prompt carries earlier accepted terms" bash -c 'prompt="$(jq -r ".messages[0].content" <<<"$1")"; [[ "$prompt" == *"Already accepted Vietnamese terms"* && "$prompt" == *"mot"* && "$prompt" == *"hai"* ]]' _ "$duplicate_chunk_repair_payload"
check S88 "chunk duplicate repair completes final artifact" assert_eq "$(jq -r '.status' "$duplicate_chunk_dir/status.json")" "completed"
check S89 "chunk duplicate repair leaves no assembled duplicate terms" assert_eq "$(artifact_duplicate_vocabulary_terms "$duplicate_chunk_dir/steps/step-04/entries.json")" ""
unset ONLYMACS_CHUNK_THRESHOLD
unset ONLYMACS_CHUNK_SIZE

apply_dir="$PROJECT_DIR/onlymacs/inbox/apply-targets"
mkdir -p "$apply_dir/files"
printf 'console.log("apply target");\n' >"$apply_dir/files/apply-file.js"
jq -n \
  --arg artifact "$apply_dir/files/apply-file.js" \
  '{status:"completed", artifact_targets:[{path:$artifact,target_path:"src/generated/apply-file.js",kind:"file"}]}' >"$apply_dir/status.json"
apply_preview="$(run_apply_inbox "$apply_dir" 2>&1)"
check S90 "apply preview uses manifest target paths, not only basenames" bash -c '[[ "$1" == *"src/generated/apply-file.js"* ]]' _ "$apply_preview"
check S91 "safe artifact target rejects parent traversal" assert_eq "$(safe_artifact_target_path '../escape.js' "$apply_dir/files/apply-file.js")" "apply-file.js"

duplicate_apply_dir="$PROJECT_DIR/onlymacs/inbox/apply-duplicates"
mkdir -p "$duplicate_apply_dir/files"
printf 'one' >"$duplicate_apply_dir/files/one.js"
printf 'two' >"$duplicate_apply_dir/files/two.js"
jq -n \
  --arg one "$duplicate_apply_dir/files/one.js" \
  --arg two "$duplicate_apply_dir/files/two.js" \
  '{status:"completed", artifact_targets:[{path:$one,target_path:"src/index.js",kind:"file"},{path:$two,target_path:"src/index.js",kind:"file"}]}' >"$duplicate_apply_dir/status.json"
if run_apply_inbox "$duplicate_apply_dir" >/tmp/onlymacs-duplicate-apply.out 2>&1; then
  duplicate_apply_rc=0
else
  duplicate_apply_rc=$?
fi
check S92 "apply refuses duplicate target paths" test "$duplicate_apply_rc" -ne 0
check S93 "apply duplicate warning names the conflicting target" assert_contains /tmp/onlymacs-duplicate-apply.out "src/index.js"
rm -f /tmp/onlymacs-duplicate-apply.out

patch_apply_dir="$PROJECT_DIR/onlymacs/inbox/apply-patch"
mkdir -p "$patch_apply_dir/files"
printf 'diff --git a/patch-target.txt b/patch-target.txt\nnew file mode 100644\nindex 0000000..2e65efe\n--- /dev/null\n+++ b/patch-target.txt\n@@ -0,0 +1 @@\n+patched\n' >"$patch_apply_dir/files/change.patch"
jq -n \
  --arg artifact "$patch_apply_dir/files/change.patch" \
  '{status:"completed", artifact_targets:[{path:$artifact,target_path:"change.patch",kind:"patch"}]}' >"$patch_apply_dir/status.json"
patch_preview="$(run_apply_inbox "$patch_apply_dir" 2>&1)"
check S94 "apply supports patch artifacts with git apply preview" bash -c '[[ "$1" == *"git apply --check"* ]]' _ "$patch_preview"

bundle_apply_dir="$PROJECT_DIR/onlymacs/inbox/apply-bundle"
mkdir -p "$bundle_apply_dir/files"
cat >"$bundle_apply_dir/files/bundle.json" <<'BUNDLE'
{
  "schema": "onlymacs.artifact_bundle.v1",
  "files": [
    {"path": "src/bundle-file.js", "content": "console.log(\"bundle file\");\n"}
  ],
  "patches": [
    {
      "path": "bundle-patch.txt",
      "patch": "diff --git a/bundle-patch.txt b/bundle-patch.txt\nnew file mode 100644\nindex 0000000..d95f3ad\n--- /dev/null\n+++ b/bundle-patch.txt\n@@ -0,0 +1 @@\n+bundled patch\n"
    }
  ],
  "commands": [{"command": "npm run build"}],
  "validators": [{"kind": "build", "command": "npm run build"}]
}
BUNDLE
jq -n \
  --arg artifact "$bundle_apply_dir/files/bundle.json" \
  '{status:"completed", artifact_targets:[{path:$artifact,target_path:"bundle.json",kind:"file"}]}' >"$bundle_apply_dir/status.json"
bundle_preview="$(run_apply_inbox "$bundle_apply_dir" 2>&1)"
check S95 "apply previews artifact bundle files" bash -c '[[ "$1" == *"Would apply bundled file"* && "$1" == *"src/bundle-file.js"* ]]' _ "$bundle_preview"
check S96 "apply previews artifact bundle patches" bash -c '[[ "$1" == *"Would apply bundled patch"* && "$1" == *"bundle-patch.txt"* ]]' _ "$bundle_preview"

unsafe_bundle_dir="$PROJECT_DIR/onlymacs/inbox/apply-unsafe-bundle"
mkdir -p "$unsafe_bundle_dir/files"
cat >"$unsafe_bundle_dir/files/bundle.json" <<'BUNDLE'
{
  "schema": "onlymacs.artifact_bundle.v1",
  "files": [
    {"path": "src/unsafe.js", "content": "console.log(\"unsafe\");\n"}
  ],
  "commands": ["sudo rm -rf /"],
  "validators": []
}
BUNDLE
jq -n \
  --arg artifact "$unsafe_bundle_dir/files/bundle.json" \
  '{status:"completed", artifact_targets:[{path:$artifact,target_path:"bundle.json",kind:"file"}]}' >"$unsafe_bundle_dir/status.json"
if run_apply_inbox "$unsafe_bundle_dir" >/tmp/onlymacs-unsafe-bundle.out 2>&1; then
  unsafe_bundle_rc=0
else
  unsafe_bundle_rc=$?
fi
check S97 "apply rejects unsafe artifact bundle commands" test "$unsafe_bundle_rc" -ne 0
check S98 "unsafe bundle warning explains command metadata" assert_contains /tmp/onlymacs-unsafe-bundle.out "unsafe command metadata"
rm -f /tmp/onlymacs-unsafe-bundle.out

unsafe_patch_bundle_dir="$PROJECT_DIR/onlymacs/inbox/apply-unsafe-bundle-patch"
mkdir -p "$unsafe_patch_bundle_dir/files"
cat >"$unsafe_patch_bundle_dir/files/bundle.json" <<'BUNDLE'
{
  "schema": "onlymacs.artifact_bundle.v1",
  "files": [],
  "patches": [
    {
      "path": "change.patch",
      "patch": "diff --git a/../escape.txt b/../escape.txt\nnew file mode 100644\nindex 0000000..1269488\n--- /dev/null\n+++ b/../escape.txt\n@@ -0,0 +1 @@\n+escape\n"
    }
  ],
  "commands": [],
  "validators": []
}
BUNDLE
jq -n \
  --arg artifact "$unsafe_patch_bundle_dir/files/bundle.json" \
  '{status:"completed", artifact_targets:[{path:$artifact,target_path:"bundle.json",kind:"file"}]}' >"$unsafe_patch_bundle_dir/status.json"
if run_apply_inbox "$unsafe_patch_bundle_dir" >/tmp/onlymacs-unsafe-bundle-patch.out 2>&1; then
  unsafe_bundle_patch_rc=0
else
  unsafe_bundle_patch_rc=$?
fi
check S99 "apply rejects bundled patches with unsafe paths" test "$unsafe_bundle_patch_rc" -ne 0
check S100 "unsafe bundled patch warning names unsafe path" assert_contains /tmp/onlymacs-unsafe-bundle-patch.out "unsafe path"
rm -f /tmp/onlymacs-unsafe-bundle-patch.out

if [[ "$fail_count" -gt 0 ]]; then
  printf '[remote-contract] failed: %d / %d scenarios failed\n' "$fail_count" "$((pass_count + fail_count))" >&2
  exit 1
fi

printf '[remote-contract] passed: %d / %d scenarios green\n' "$pass_count" "$((pass_count + fail_count))"
