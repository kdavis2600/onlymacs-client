#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../integrations/common/onlymacs-cli.sh
source "$ROOT_DIR/integrations/common/onlymacs-cli.sh"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-reporting-contract.XXXXXX")"
if [[ "${ONLYMACS_KEEP_REPORTING_CONTRACT_TEMP:-0}" == "1" ]]; then
  printf '[reporting-contract] keeping temp dir: %s\n' "$TEMP_DIR" >&2
else
  trap 'rm -rf "$TEMP_DIR"' EXIT
fi

export ONLYMACS_STATE_DIR="$TEMP_DIR/state"
export ONLYMACS_JSON_MODE=1
export ONLYMACS_PROGRESS=0
ONLYMACS_WRAPPER_NAME="onlymacs-shell.sh"
ONLYMACS_ACTIVITY_LABEL="chat"

PROJECT_DIR="$TEMP_DIR/project"
CAPTURE_DIR="$TEMP_DIR/report-captures"
mkdir -p "$PROJECT_DIR" "$CAPTURE_DIR"
cd "$PROJECT_DIR"
PROJECT_DIR="$(pwd)"

pass_count=0
fail_count=0
REPORT_REQUEST_COUNT=0
REPORT_FAIL_NEXT=0

record_pass() {
  printf '[reporting-contract] PASS %s %s\n' "$1" "$2"
  pass_count=$((pass_count + 1))
}

record_fail() {
  printf '[reporting-contract] FAIL %s %s\n' "$1" "$2" >&2
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

assert_not_file() {
  [[ ! -f "$1" ]]
}

assert_json_true() {
  jq -e "$2" "$1" >/dev/null
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  ! rg -q --fixed-strings "$needle" "$path"
}

report_auto_disabled() {
  ! onlymacs_report_auto_enabled
}

request_json() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  ONLYMACS_LAST_HTTP_STATUS=""
  ONLYMACS_LAST_HTTP_BODY=""
  ONLYMACS_LAST_CURL_ERROR=""

  if [[ "$method" == "POST" && "$path" == "/admin/v1/job-reports" ]]; then
    if [[ "${REPORT_FAIL_NEXT:-0}" == "1" ]]; then
      REPORT_FAIL_NEXT=0
      ONLYMACS_LAST_HTTP_STATUS="500"
      ONLYMACS_LAST_HTTP_BODY='{"error":{"code":"TEST_REPORT_FAILURE","message":"fake coordinator failure"}}'
      return 0
    fi
    REPORT_REQUEST_COUNT=$((REPORT_REQUEST_COUNT + 1))
    printf '%s' "$payload" >"$CAPTURE_DIR/payload-${REPORT_REQUEST_COUNT}.json"
    local run_id status automatic report_id
    run_id="$(jq -r '.run_id // "run-unknown"' <<<"$payload")"
    status="$(jq -r '.status // "unknown"' <<<"$payload")"
    automatic="$(jq -r '.automatic // false' <<<"$payload")"
    report_id="$(printf 'report-%06d' "$REPORT_REQUEST_COUNT")"
    ONLYMACS_LAST_HTTP_STATUS="201"
    ONLYMACS_LAST_HTTP_BODY="$(jq -cn \
      --arg id "$report_id" \
      --arg run_id "$run_id" \
      --arg status "$status" \
      --argjson automatic "$automatic" \
      '{status:"recorded",report:{id:$id,run_id:$run_id,status:$status,automatic:$automatic,source:"onlymacs-cli"}}')"
    return 0
  fi

  ONLYMACS_LAST_HTTP_STATUS="404"
  ONLYMACS_LAST_HTTP_BODY='{"error":{"code":"UNEXPECTED_TEST_REQUEST"}}'
  return 0
}

run_root() {
  printf '%s' "$(chat_returns_root)"
}

make_run() {
  local run_id="$1"
  local status="$2"
  local route_scope="${3:-swarm}"
  local run_dir latest_path now
  run_dir="$(run_root)/$run_id"
  mkdir -p "$run_dir/files"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  jq -n \
    --arg run_id "$run_id" \
    --arg status "$status" \
    --arg now "$now" \
    --arg inbox "$run_dir" \
    --arg files_dir "$run_dir/files" \
    --arg route_scope "$route_scope" \
    '{
      run_id: $run_id,
      status: $status,
      created_at: $now,
      updated_at: $now,
      session_id: "sess-report-test",
      swarm_id: "swarm-public",
      swarm_name: "OnlyMacs Public",
      swarm_visibility: "public",
      provider_id: "provider-charles",
      provider_name: "Charles Studio",
      owner_member_name: "Charles",
      model: "qwen-test:latest",
      route_scope: $route_scope,
      prompt_preview: "private raw prompt SECRET_SHOULD_NOT_LEAK /Users/onlymacs-fixture/private/.env",
      inbox: $inbox,
      files_dir: $files_dir,
      progress: {phase: $status, steps_completed: 1, steps_total: 1},
      token_accounting: {total_remote_tokens_estimate: 42},
      next_step: "Inspect local inbox details if needed: /Users/onlymacs-fixture/private/onlymacs/inbox"
    }' >"$run_dir/status.json"
  latest_path="$(run_root)/latest.json"
  jq -n \
    --arg run_id "$run_id" \
    --arg status "$status" \
    --arg now "$now" \
    --arg inbox "$run_dir" \
    --arg status_path "$run_dir/status.json" \
    '{run_id:$run_id,status:$status,updated_at:$now,inbox:$inbox,status_path:$status_path}' >"$latest_path"
  : >"$run_dir/events.jsonl"
  printf '%s' "$run_dir"
}

make_private_run() {
  local run_id="$1"
  local run_dir
  run_dir="$(make_run "$run_id" "completed" "local")"
  jq '.swarm_id = "swarm-private" | .swarm_name = "Private Swarm" | .swarm_visibility = "private"' \
    "$run_dir/status.json" >"$run_dir/status.json.tmp" && mv "$run_dir/status.json.tmp" "$run_dir/status.json"
  printf '%s' "$run_dir"
}

add_event() {
  local run_dir="$1"
  local event="$2"
  local status="${3:-running}"
  local message="${4:-}"
  jq -cn \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg event "$event" \
    --arg status "$status" \
    --arg message "$message" \
    '{
      ts: $ts,
      event: $event,
      status: $status,
      message: ($message | if length > 0 then . else null end),
      provider_id: "provider-charles",
      provider_name: "Charles Studio",
      model: "qwen-test:latest",
      status_path: "/Users/onlymacs-fixture/private/status.json",
      artifact_path: "/Users/onlymacs-fixture/private/files/secret.js",
      raw_result_path: "/Users/onlymacs-fixture/private/RESULT.md"
    }' >>"$run_dir/events.jsonl"
}

add_plan_with_ticket() {
  local run_dir="$1"
  jq -n \
    --arg run_id "$(basename "$run_dir")" \
    '{
      run_id: $run_id,
      status: "completed",
      mode: "extended",
      route_scope: "swarm",
      model_alias: "remote-first",
      execution_settings: {go_wide: {enabled: true, lanes: 2}},
      steps: [{
        id: "step-01",
        title: "Generate test artifact",
        status: "completed",
        batching: {
          batches: [{
            index: 1,
            status: "completed",
            ticket_kind: "generate",
            filename: "secret.js",
            target_files: ["/Users/onlymacs-fixture/private/src/secret.js"],
            validator: "json",
            capability: "translation",
            lease_id: "lease-secret",
            provider_id: "provider-charles",
            provider_name: "Charles Studio",
            model: "qwen-test:latest",
            message: "saved to /Users/onlymacs-fixture/private/src/secret.js"
          }]
        }
      }],
      progress: {phase: "completed", steps_completed: 1, steps_total: 1}
    }' >"$run_dir/plan.json"
  jq --arg plan_path "$run_dir/plan.json" '.plan_path = $plan_path' "$run_dir/status.json" >"$run_dir/status.json.tmp" && mv "$run_dir/status.json.tmp" "$run_dir/status.json"
}

payload_path() {
  printf '%s/payload-%s.json' "$CAPTURE_DIR" "$1"
}

last_payload_path() {
  payload_path "$REPORT_REQUEST_COUNT"
}

payload_has_no_sensitive_material() {
  local path="$1"
  assert_not_contains "$path" "SECRET_SHOULD_NOT_LEAK" &&
    assert_not_contains "$path" "/Users/onlymacs-fixture/private" &&
    assert_not_contains "$path" "raw prompt" &&
    assert_not_contains "$path" "RESULT.md" &&
    assert_not_contains "$path" "lease-secret"
}

check S01 "auto reporting defaults to enabled" onlymacs_report_auto_enabled
onlymacs_report_set_auto_enabled false
check S02 "auto reporting can be disabled" report_auto_disabled
onlymacs_report_set_auto_enabled true
check S03 "auto reporting can be re-enabled" onlymacs_report_auto_enabled

completed_dir="$(make_run "run-completed" "completed")"
add_event "$completed_dir" "run_created" "running"
add_event "$completed_dir" "run_completed" "completed"
add_plan_with_ticket "$completed_dir"
onlymacs_auto_report_public_run "$completed_dir"
completed_payload="$(last_payload_path)"

check S04 "completed public run submits an automatic report" assert_eq "$REPORT_REQUEST_COUNT" "1"
check S05 "automatic report marker is written" assert_file "$completed_dir/report-submitted.json"
check S06 "status exposes submitted report id" assert_json_true "$completed_dir/status.json" '.reporting.submitted == true and .report_id == "report-000001"'
check S07 "latest exposes submitted report id" assert_json_true "$(run_root)/latest.json" '.reporting.submitted == true and .report_id == "report-000001"'
check S08 "automatic payload status is completed" assert_json_true "$completed_payload" '.status == "completed" and .automatic == true'
check S09 "automatic invocation is redacted" assert_json_true "$completed_payload" '.invocation == "onlymacs-shell.sh chat [prompt redacted]"'
check S10 "automatic prompt preview is not submitted" assert_json_true "$completed_payload" '.prompt_preview == null'
check S11 "automatic payload omits sensitive prompt and local path material" payload_has_no_sensitive_material "$completed_payload"
check S12 "automatic event summary omits raw first/last event bodies" assert_json_true "$completed_payload" '(.events_summary.first_event == null) and (.events_summary.last_event == null)'
check S13 "automatic tickets keep metadata but drop raw paths, lease ids, and messages" assert_json_true "$completed_payload" '.tickets[0].message_present == true and (.tickets[0].target_files == null) and (.tickets[0].lease_id == null) and (.tickets[0].message == null)'

onlymacs_auto_report_public_run "$completed_dir"
check S14 "automatic report is not submitted twice for the same run" assert_eq "$REPORT_REQUEST_COUNT" "1"

failed_dir="$(make_run "run-failed" "failed")"
jq '.failure_message = "coordinator returned 401" | .failure_class = "coordinator_auth" | .failure = {http_status:"401", kind:"coordinator_auth", message:"coordinator returned 401"}' \
  "$failed_dir/status.json" >"$failed_dir/status.json.tmp" && mv "$failed_dir/status.json.tmp" "$failed_dir/status.json"
add_event "$failed_dir" "run_failed" "failed" "coordinator returned 401"
onlymacs_auto_report_public_run "$failed_dir"
failed_payload="$(last_payload_path)"
check S15 "failed public run submits failure report" assert_json_true "$failed_payload" '.status == "failed" and .metrics.failure_class == "coordinator_auth" and .metrics.failure_message_present == true'

partial_dir="$(make_run "run-partial" "partial")"
jq '.partial = true | .partial_result_path = "/Users/onlymacs-fixture/private/RESULT.partial.md"' \
  "$partial_dir/status.json" >"$partial_dir/status.json.tmp" && mv "$partial_dir/status.json.tmp" "$partial_dir/status.json"
add_event "$partial_dir" "stream_error" "partial" "partial output preserved"
onlymacs_auto_report_public_run "$partial_dir"
partial_payload="$(last_payload_path)"
check S16 "partial public run submits partial report without raw partial path" assert_json_true "$partial_payload" '.status == "partial"'
check S17 "partial report redacts local partial path" payload_has_no_sensitive_material "$partial_payload"

queued_dir="$(make_run "run-queued" "queued")"
jq '.resume_command = "onlymacs resume-run /Users/onlymacs-fixture/private/onlymacs/inbox/run-queued"' \
  "$queued_dir/status.json" >"$queued_dir/status.json.tmp" && mv "$queued_dir/status.json.tmp" "$queued_dir/status.json"
add_event "$queued_dir" "capacity_wait" "queued" "waiting for provider capacity"
onlymacs_auto_report_public_run "$queued_dir"
queued_payload="$(last_payload_path)"
check S18 "queued public run reports capacity wait count" assert_json_true "$queued_payload" '.status == "queued" and .metrics.event_counts.capacity_wait == 1'
check S19 "queued automatic report redacts raw resume command" payload_has_no_sensitive_material "$queued_payload"
check S20 "queued automatic resume field is generic" assert_json_true "$queued_payload" '.resume_restart_issues | contains("saved locally")'

churn_dir="$(make_run "run-churn" "churn")"
add_event "$churn_dir" "validation_failed" "running" "schema mismatch"
add_event "$churn_dir" "repair_started" "running" "repairing"
add_event "$churn_dir" "reroute_started" "running" "provider reroute"
add_event "$churn_dir" "run_failed" "churn" "bounded repair failed"
onlymacs_auto_report_public_run "$churn_dir"
churn_payload="$(last_payload_path)"
check S21 "churn report preserves validation/repair/reroute counters" assert_json_true "$churn_payload" '.status == "churn" and .metrics.event_counts.validation_failed == 1 and .metrics.event_counts.repair_started == 1 and .metrics.event_counts.reroute_started == 1'
check S22 "churn feedback summarizes what broke" assert_json_true "$churn_payload" '(.what_broke | contains("validation failure")) and (.what_broke | contains("repair")) and (.what_broke | contains("reroute"))'

onlymacs_report_set_auto_enabled false
disabled_dir="$(make_run "run-disabled" "completed")"
onlymacs_auto_report_public_run "$disabled_dir"
check S23 "disabled auto reporting does not submit" assert_eq "$REPORT_REQUEST_COUNT" "5"
check S24 "disabled auto reporting does not write marker" assert_not_file "$disabled_dir/report-submitted.json"
onlymacs_report_set_auto_enabled true

private_dir="$(make_private_run "run-private")"
onlymacs_auto_report_public_run "$private_dir"
check S25 "private/local run is not automatically reported" assert_eq "$REPORT_REQUEST_COUNT" "5"

manual_dir="$(make_run "run-manual" "completed")"
run_report "$manual_dir" --report "Manual coordinator note" --quiet
manual_payload="$(last_payload_path)"
check S26 "manual report submits with automatic false" assert_json_true "$manual_payload" '.automatic == false and .report_markdown == "Manual coordinator note"'
check S27 "manual report does not create automatic marker" assert_not_file "$manual_dir/report-submitted.json"
check S28 "manual report still records report id in status" assert_json_true "$manual_dir/status.json" '.reporting.submitted == true and .reporting.automatic == false and .report_id == "report-000006"'

failing_dir="$(make_run "run-report-submit-fails" "completed")"
REPORT_FAIL_NEXT=1
if onlymacs_submit_report "$failing_dir" "" "true" "true"; then
  record_fail S29 "failed coordinator report submission returns non-zero"
else
  record_pass S29 "failed coordinator report submission returns non-zero"
fi
check S30 "failed coordinator report submission does not write marker" assert_not_file "$failing_dir/report-submitted.json"
check S31 "failed coordinator report submission does not mark status submitted" assert_json_true "$failing_dir/status.json" '(.reporting.submitted // false) == false'

if [[ "$fail_count" -gt 0 ]]; then
  printf '[reporting-contract] failed: %s failure(s), %s pass(es)\n' "$fail_count" "$pass_count" >&2
  exit 1
fi

printf '[reporting-contract] passed: %s / %s scenarios green\n' "$pass_count" "$pass_count"
