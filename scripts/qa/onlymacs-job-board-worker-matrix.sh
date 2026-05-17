#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../integrations/common/onlymacs-cli.sh
source "$ROOT_DIR/integrations/common/onlymacs-cli.sh"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

export ONLYMACS_STATE_DIR="$TEMP_DIR/state"
export ONLYMACS_RETURNS_DIR="$TEMP_DIR/inbox"
ONLYMACS_WRAPPER_NAME="onlymacs"

pass_count=0

fail() {
  printf '[job-worker] FAIL %s\n' "$1" >&2
  exit 1
}

check() {
  local id="$1" label="$2"
  shift 2
  "$@" || fail "$id $label"
  pass_count=$((pass_count + 1))
  printf '[job-worker] PASS %s %s\n' "$id" "$label"
}

contains_json_string() {
  local json="$1" value="$2"
  jq -e --arg value "$value" 'index($value) != null' <<<"$json" >/dev/null
}

reject() {
  ! "$@"
}

profile64='{"memory_gb":64,"slots_total":2,"models":["qwen2.5-coder:32b","gemma4:31b"]}'
profile128='{"memory_gb":128,"slots_total":4,"models":["qwen2.5-coder:32b"]}'

unset ONLYMACS_CONTEXT_ALLOW_TESTS ONLYMACS_CONTEXT_ALLOW_INSTALL ONLYMACS_JOB_WORKER_PROFILE_JSON
caps="$(onlymacs_job_worker_capabilities_json)"
check S01 "default worker capabilities include coder" contains_json_string "$caps" "coder"
check S02 "default worker capabilities include reviewer" contains_json_string "$caps" "reviewer"
check S03 "default worker capabilities include merge finalizer" contains_json_string "$caps" "merge"
check S04 "default worker capabilities exclude tester without opt-in" bash -c '! jq -e "index(\"tester\") != null" <<<"$1" >/dev/null' _ "$caps"

ONLYMACS_CONTEXT_ALLOW_TESTS=1
caps="$(onlymacs_job_worker_capabilities_json)"
check S05 "test opt-in adds tester capability" contains_json_string "$caps" "tester"

ONLYMACS_CONTEXT_ALLOW_INSTALL=1
caps="$(onlymacs_job_worker_capabilities_json)"
check S06 "install opt-in adds dependency install capability" contains_json_string "$caps" "dependency_install"

ONLYMACS_JOB_WORKER_PROFILE_JSON="$profile64"
caps="$(onlymacs_job_worker_capabilities_json)"
check S07 "64 GB profile adds power tier" contains_json_string "$caps" "power_64gb"
check S08 "coder model profile adds frontend" contains_json_string "$caps" "frontend"
check S09 "multi-slot profile adds parallel worker" contains_json_string "$caps" "parallel_worker"
check S10 "capability list is deduplicated" bash -c '[[ "$(jq -r "length" <<<"$1")" == "$(jq -r "unique | length" <<<"$1")" ]]' _ "$caps"

ONLYMACS_JOB_WORKER_PROFILE_JSON="$profile128"
caps="$(onlymacs_job_worker_capabilities_json)"
check S11 "128 GB profile adds high capacity tier" contains_json_string "$caps" "power_128gb"
check S12 "128 GB profile adds large context" contains_json_string "$caps" "large_context"

check S13 "coding prompt is classified for ticket template" onlymacs_jobs_prompt_looks_like_coding "Build a React dashboard with tests"
check S14 "plain content prompt is not forced into coding template" reject onlymacs_jobs_prompt_looks_like_coding "Write 20 travel flashcards about Buenos Aires"
check S15 "app marketing prompt is not forced into coding template" reject onlymacs_jobs_prompt_looks_like_coding "Write launch notes for the OnlyMacs app"

coding_tickets="$(onlymacs_jobs_default_tickets_json "Build a TypeScript landing page" '[]')"
check S16 "coding template has five pipeline tickets" bash -c '[[ "$(jq -r "length" <<<"$1")" == "5" ]]' _ "$coding_tickets"
check S17 "coding template wires implement after plan" bash -c 'jq -e ".[] | select(.id == \"ticket-implement\") | (.dependencies | index(\"ticket-plan\"))" <<<"$1" >/dev/null' _ "$coding_tickets"
check S18 "coding template wires merge after review and test" bash -c 'jq -e ".[] | select(.id == \"ticket-merge\") | (.dependencies | index(\"ticket-review\")) and (.dependencies | index(\"ticket-test\"))" <<<"$1" >/dev/null' _ "$coding_tickets"
check S19 "coding template creates validator ticket" bash -c 'jq -e ".[] | select(.id == \"ticket-test\" and .kind == \"test\" and .required_capability == \"tester\")" <<<"$1" >/dev/null' _ "$coding_tickets"

custom_validator='[{"command":"npm run build"}]'
custom_tickets="$(onlymacs_jobs_default_tickets_json "Patch this frontend repo" "$custom_validator")"
check S20 "custom validators propagate into test ticket" bash -c 'jq -e ".[] | select(.id == \"ticket-test\") | (.validator_commands | index(\"npm run build\"))" <<<"$1" >/dev/null' _ "$custom_tickets"

content_tickets="$(onlymacs_jobs_default_tickets_json "Write 50 glossary entries" '[]')"
check S21 "content template stays single plan ticket" bash -c '[[ "$(jq -r "length" <<<"$1")" == "1" ]] && jq -e ".[0].kind == \"plan\"" <<<"$1" >/dev/null' _ "$content_tickets"

job_json='{"id":"job 1","invocation":"/onlymacs --go-wide","prompt_preview":"build app","context_policy":{"context_read_mode":"full_project","context_write_mode":"staged"}}'
ticket_json='{"id":"ticket impl","kind":"patch","title":"Implement","target_files":["src/App.tsx"],"dependencies":["ticket-plan"],"required_capability":"coder","validator_commands":["npm run build"]}'
ticket_prompt="$(onlymacs_jobs_ticket_prompt "$job_json" "$ticket_json")"
check S22 "ticket prompt mentions workspace handoff" bash -c '[[ "$1" == *"ONLYMACS_JOB_WORKSPACE_DIR"* ]]' _ "$ticket_prompt"
check S23 "ticket prompt avoids same-model assumptions" bash -c '[[ "$1" == *"Do not assume every Mac uses the same model"* ]]' _ "$ticket_prompt"

workspace="$(onlymacs_jobs_ticket_workspace_dir "$job_json" "$ticket_json")"
check S24 "workspace path sanitizes job and ticket ids" bash -c '[[ "$1" == *"job-1/ticket-impl" ]]' _ "$workspace"

metadata='{"artifacts":["/tmp/result.md"],"ticket_kind":"patch"}'
bundle="$(onlymacs_jobs_artifact_bundle_json "$metadata" "done")"
check S25 "artifact bundle uses stable schema" bash -c 'jq -e ".schema == \"onlymacs.artifact_bundle.v1\" and .files[0].path == \"/tmp/result.md\"" <<<"$1" >/dev/null' _ "$bundle"
check S26 "install command detector blocks npm install" onlymacs_jobs_command_is_install "npm install"
check S27 "install command detector ignores build commands" reject onlymacs_jobs_command_is_install "npm run build"

printf '[job-worker] passed: %s / %s scenarios green\n' "$pass_count" "$pass_count"
