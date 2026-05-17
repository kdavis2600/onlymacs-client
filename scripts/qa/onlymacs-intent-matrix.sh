#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MATRIX_FILE="${ONLYMACS_INTENT_MATRIX_FILE:-$ROOT_DIR/scripts/qa/onlymacs-intent-matrix.json}"
RESULTS_FILE="${ONLYMACS_INTENT_MATRIX_RESULTS:-$ROOT_DIR/.tmp/validation/onlymacs-intent-matrix-$(date +%Y%m%d-%H%M%S).jsonl}"

if [[ ! -f "$MATRIX_FILE" ]]; then
  printf '[ERROR] Intent matrix not found: %s\n' "$MATRIX_FILE" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '[ERROR] onlymacs-intent-matrix.sh requires jq.\n' >&2
  exit 2
fi

# shellcheck source=../../integrations/common/onlymacs-cli.sh
source "$ROOT_DIR/integrations/common/onlymacs-cli.sh"

# Keep this harness fully offline. It proves the deterministic fallback resolver.
request_policy_classify() {
  ONLYMACS_REQUEST_POLICY_DECISION=""
  ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES="false"
  ONLYMACS_REQUEST_POLICY_REASONS=""
  ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_NAME=""
  ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_VISIBILITY=""
  ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND=""
  ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET=""
  ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION=""
  ONLYMACS_REQUEST_POLICY_TASK_KIND=""
  ONLYMACS_REQUEST_POLICY_FILE_ACCESS_MODE=""
  ONLYMACS_REQUEST_POLICY_TRUST_TIER=""
  ONLYMACS_REQUEST_POLICY_ALLOW_CONTEXT_REQUESTS="false"
  ONLYMACS_REQUEST_POLICY_MAX_CONTEXT_REQUEST_ROUNDS="0"
  ONLYMACS_REQUEST_POLICY_USER_FACING_WARNING=""
  ONLYMACS_REQUEST_POLICY_SUGGESTED_CONTEXT_PACKS_JSON="[]"
  ONLYMACS_REQUEST_POLICY_SUGGESTED_FILES_JSON="[]"
  return 1
}

TEMP_STATE_DIR="$(mktemp -d)"
export ONLYMACS_STATE_DIR="$TEMP_STATE_DIR"
trap 'rm -rf "$TEMP_STATE_DIR"' EXIT

mkdir -p "$(dirname "$RESULTS_FILE")"
: >"$RESULTS_FILE"

json_array_from_args() {
  jq -cn '$ARGS.positional' --args "$@"
}

expected_args_for_case() {
  local case_json="$1" prompt action alias
  if jq -e 'has("args")' <<<"$case_json" >/dev/null; then
    jq -c '.args' <<<"$case_json"
    return 0
  fi

  prompt="$(jq -r '.prompt' <<<"$case_json")"
  action="$(jq -r '.action // "chat"' <<<"$case_json")"
  alias="$(jq -r '.alias // ""' <<<"$case_json")"

  if [[ "$action" == "chat" ]]; then
    if [[ -n "$alias" ]]; then
      json_array_from_args "chat" "$alias" "$prompt"
    else
      json_array_from_args "chat" "$prompt"
    fi
  else
    json_array_from_args "$action" "$prompt"
  fi
}

reset_intent_state() {
  rm -f "$(workspace_defaults_path)"
  unset ONLYMACS_CONTEXT_READ_MODE ONLYMACS_CONTEXT_WRITE_MODE ONLYMACS_CONTEXT_ALLOW_TESTS ONLYMACS_CONTEXT_ALLOW_INSTALL
  unset ONLYMACS_FORCE_ACTION ONLYMACS_FORCE_PRESET ONLYMACS_PLAN_FILE_PATH ONLYMACS_RESOLVED_PLAN_FILE_PATH
  unset ONLYMACS_REQUEST_POLICY_DECISION ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES ONLYMACS_REQUEST_POLICY_REASONS
  unset ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_NAME ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_VISIBILITY
  unset ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION
  unset ONLYMACS_REQUEST_POLICY_TASK_KIND ONLYMACS_REQUEST_POLICY_FILE_ACCESS_MODE ONLYMACS_REQUEST_POLICY_TRUST_TIER
  unset ONLYMACS_REQUEST_POLICY_ALLOW_CONTEXT_REQUESTS ONLYMACS_REQUEST_POLICY_MAX_CONTEXT_REQUEST_ROUNDS
  unset ONLYMACS_REQUEST_POLICY_USER_FACING_WARNING ONLYMACS_REQUEST_POLICY_SUGGESTED_CONTEXT_PACKS_JSON ONLYMACS_REQUEST_POLICY_SUGGESTED_FILES_JSON
  ONLYMACS_EXECUTION_MODE="auto"
  ONLYMACS_EXECUTION_MODE_EXPLICIT=0
  ONLYMACS_SIMPLE_MODE=0
  ONLYMACS_GO_WIDE_MODE=0
  ONLYMACS_ROUTED_ARGS=()
  ONLYMACS_ROUTER_INTERPRETATION=""
  ONLYMACS_ROUTER_REASON=""
}

record_result() {
  local id="$1" ok="$2" prompt="$3" expected_interpretation="$4" actual_interpretation="$5" expected_args_json="$6" actual_args_json="$7" message="$8"
  jq -cn \
    --arg id "$id" \
    --arg prompt "$prompt" \
    --arg expected_interpretation "$expected_interpretation" \
    --arg actual_interpretation "$actual_interpretation" \
    --arg context_read "${ONLYMACS_CONTEXT_READ_MODE:-}" \
    --arg context_write "${ONLYMACS_CONTEXT_WRITE_MODE:-}" \
    --arg allow_tests "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" \
    --arg execution_mode "${ONLYMACS_EXECUTION_MODE:-auto}" \
    --arg message "$message" \
    --argjson ok "$ok" \
    --argjson expected_args "$expected_args_json" \
    --argjson actual_args "$actual_args_json" \
    '{id:$id, ok:$ok, prompt:$prompt, expected_interpretation:$expected_interpretation, actual_interpretation:$actual_interpretation, expected_args:$expected_args, actual_args:$actual_args, context_read:$context_read, context_write:$context_write, allow_tests:$allow_tests, execution_mode:$execution_mode, message:$message}' \
    >>"$RESULTS_FILE"
}

checked=0
failures=0

while IFS= read -r case_json; do
  checked=$((checked + 1))

  id="$(jq -r '.id' <<<"$case_json")"
  prompt="$(jq -r '.prompt' <<<"$case_json")"
  expected_interpretation="$(jq -r '.interpretation' <<<"$case_json")"
  expected_args_json="$(expected_args_for_case "$case_json")"
  expected_context_read="$(jq -r '.context_read // "__UNSPECIFIED__"' <<<"$case_json")"
  expected_context_write="$(jq -r '.context_write // "__UNSPECIFIED__"' <<<"$case_json")"
  expected_allow_tests="$(jq -r '.allow_tests // "__UNSPECIFIED__"' <<<"$case_json")"
  expected_execution="$(jq -r '.execution // "__UNSPECIFIED__"' <<<"$case_json")"
  expected_reason_contains="$(jq -r '.reason_contains // "__UNSPECIFIED__"' <<<"$case_json")"

  reset_intent_state
  message=""
  if ! resolve_natural_language_command "$prompt"; then
    actual_args_json="[]"
    message="resolver returned false"
  else
    actual_args_json="$(json_array_from_args "${ONLYMACS_ROUTED_ARGS[@]}")"
    if [[ "${ONLYMACS_ROUTER_INTERPRETATION:-}" != "$expected_interpretation" ]]; then
      message="expected interpretation '$expected_interpretation', got '${ONLYMACS_ROUTER_INTERPRETATION:-}'"
    elif [[ "$actual_args_json" != "$expected_args_json" ]]; then
      message="expected args $expected_args_json, got $actual_args_json"
    elif [[ "$expected_context_read" != "__UNSPECIFIED__" && "${ONLYMACS_CONTEXT_READ_MODE:-}" != "$expected_context_read" ]]; then
      message="expected context_read '$expected_context_read', got '${ONLYMACS_CONTEXT_READ_MODE:-}'"
    elif [[ "$expected_context_write" != "__UNSPECIFIED__" && "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "$expected_context_write" ]]; then
      message="expected context_write '$expected_context_write', got '${ONLYMACS_CONTEXT_WRITE_MODE:-}'"
    elif [[ "$expected_allow_tests" != "__UNSPECIFIED__" && "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" != "$expected_allow_tests" ]]; then
      message="expected allow_tests '$expected_allow_tests', got '${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}'"
    elif [[ "$expected_execution" != "__UNSPECIFIED__" && "${ONLYMACS_EXECUTION_MODE:-auto}" != "$expected_execution" ]]; then
      message="expected execution '$expected_execution', got '${ONLYMACS_EXECUTION_MODE:-auto}'"
    elif [[ "$expected_reason_contains" != "__UNSPECIFIED__" && "${ONLYMACS_ROUTER_REASON:-}" != *"$expected_reason_contains"* ]]; then
      message="expected reason containing '$expected_reason_contains', got '${ONLYMACS_ROUTER_REASON:-}'"
    fi
  fi

  if [[ -n "$message" ]]; then
    failures=$((failures + 1))
    printf 'FAIL %s: %s\n' "$id" "$message"
    record_result "$id" false "$prompt" "$expected_interpretation" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "$expected_args_json" "$actual_args_json" "$message"
  else
    printf 'PASS %s\n' "$id"
    record_result "$id" true "$prompt" "$expected_interpretation" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "$expected_args_json" "$actual_args_json" ""
  fi
done < <(jq -c '.[]' "$MATRIX_FILE")

printf 'checked=%d failures=%d\n' "$checked" "$failures"
printf 'results=%s\n' "$RESULTS_FILE"

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
