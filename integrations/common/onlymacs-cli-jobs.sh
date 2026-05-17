# Job-board CLI commands and worker loop for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after shared CLI helpers are loaded.

onlymacs_job_worker_capabilities_json() {
  local caps=("$@")
  local raw item profile_json derived_json
  if [[ "${#caps[@]}" -eq 0 && -n "${ONLYMACS_JOB_WORKER_CAPABILITIES:-}" ]]; then
    IFS=',' read -r -a caps <<<"$ONLYMACS_JOB_WORKER_CAPABILITIES"
  fi
  if [[ "${#caps[@]}" -eq 0 ]]; then
    caps=(planner coder frontend backend patch merge reviewer content fast_draft high_accuracy canvas_render browser_render webgl_canvas)
    if bool_is_true "${ONLYMACS_CONTEXT_ALLOW_TESTS:-false}"; then
      caps+=(tester validator)
    fi
    if bool_is_true "${ONLYMACS_CONTEXT_ALLOW_INSTALL:-false}"; then
      caps+=(dependency_install)
    fi
  fi
  profile_json="${ONLYMACS_JOB_WORKER_PROFILE_JSON:-}"
  if [[ -n "$profile_json" && "$profile_json" != "null" ]]; then
    derived_json="$(jq -r '
      def cap($v): $v;
      ([.models[]? | ascii_downcase] | join(" ")) as $models
      | (.memory_gb // 0) as $ram
      | [
          (if $ram >= 128 then ["power_128gb","large_context","high_accuracy"] elif $ram >= 64 then ["power_64gb","large_context"] elif $ram >= 32 then ["light_32gb"] else [] end),
          (if ($models | test("qwen2\\.5-coder|coder")) then ["coder","frontend","backend","patch","reviewer"] else [] end),
          (if ($models | test("gemma|qwen3")) then ["content","reviewer","fast_draft"] else [] end),
          (if ((.slots_total // 0) >= 2) then ["parallel_worker"] else [] end)
        ] | flatten[]?' <<<"$profile_json" 2>/dev/null || true)"
  else
    derived_json=""
  fi
  {
    for item in "${caps[@]}"; do
      raw="${item//,/ }"
      printf '%s\n' "$raw" | tr ' ' '\n'
    done
    printf '%s\n' "$derived_json"
  } | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/-/_/g' | awk 'NF && !seen[$0]++' | jq -R -s 'split("\n") | map(select(length > 0))'
}

onlymacs_job_worker_profile_json() {
  local status_json model_alias="${1:-local-first}" bridge_url="${BASE_URL:-http://127.0.0.1:4318}"
  status_json="$(curl -fsS --max-time 3 "${bridge_url}/admin/v1/status" 2>/dev/null || true)"
  if [[ -z "$status_json" ]]; then
    jq -n --arg model "$(normalize_model_alias "$model_alias")" '{model:$model, models:[]}'
    return 0
  fi
  jq -c --arg model "$(normalize_model_alias "$model_alias")" '
    (.identity.provider_id // .sharing.provider_id // "") as $provider_id
    | ((.providers // []) | map(select(.id == $provider_id)) | .[0] // (.providers[0] // {})) as $provider
    | {
        member_id: (.identity.member_id // $provider.owner_member_id // ""),
        member_name: (.identity.member_name // $provider.owner_member_name // ""),
        provider_id: (.identity.provider_id // .sharing.provider_id // $provider.id // ""),
        provider_name: (.identity.provider_name // .sharing.provider_name // $provider.name // ""),
        model: $model,
        memory_gb: ($provider.hardware.memory_gb // 0),
        cpu_brand: ($provider.hardware.cpu_brand // ""),
        slots_free: (.sharing.slots.free // $provider.slots.free // 0),
        slots_total: (.sharing.slots.total // $provider.slots.total // 0),
        models: ([($provider.models[]?.id // empty), (.sharing.published_models[]?.id // empty), (.models[]?.id // empty)] | unique),
        client_build: (.sharing.client_build // $provider.client_build // null)
      }' <<<"$status_json" 2>/dev/null || jq -n --arg model "$(normalize_model_alias "$model_alias")" '{model:$model, models:[]}'
}

onlymacs_jobs_claim_tickets() {
  local job_id="${1:-}" max_tickets="${2:-1}" capabilities_json="${3:-[]}" prefer_kind="${4:-}" lease_seconds="${5:-600}" model_alias="${6:-local-first}"
  local model claim_payload count profile_json worker_memory_gb worker_slots_free worker_slots_total
  [[ -n "$job_id" ]] || return 1
  [[ "$max_tickets" =~ ^[0-9]+$ && "$max_tickets" -gt 0 ]] || max_tickets=1
  [[ "$lease_seconds" =~ ^[0-9]+$ && "$lease_seconds" -gt 0 ]] || lease_seconds=600
  model="$(normalize_model_alias "$model_alias")"
  profile_json="${ONLYMACS_JOB_WORKER_PROFILE_JSON:-}"
  if [[ -z "$profile_json" || "$profile_json" == "null" ]]; then
    profile_json="$(onlymacs_job_worker_profile_json "$model_alias")"
    ONLYMACS_JOB_WORKER_PROFILE_JSON="$profile_json"
  fi
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$profile_json"; then
    profile_json="$(jq -n --arg model "$model" '{model:$model, models:[]}')"
    ONLYMACS_JOB_WORKER_PROFILE_JSON="$profile_json"
  fi
  worker_memory_gb="$(jq -r '(.memory_gb // 0) | if type == "number" then . else (tonumber? // 0) end' <<<"$profile_json" 2>/dev/null || printf '0')"
  worker_slots_free="$(jq -r '(.slots_free // 0) | if type == "number" then . else (tonumber? // 0) end' <<<"$profile_json" 2>/dev/null || printf '0')"
  worker_slots_total="$(jq -r '(.slots_total // 0) | if type == "number" then . else (tonumber? // 0) end' <<<"$profile_json" 2>/dev/null || printf '0')"
  claim_payload="$(jq -n \
    --arg member_id "$(jq -r '.member_id // empty' <<<"$profile_json" 2>/dev/null)" \
    --arg member_name "$(jq -r '.member_name // empty' <<<"$profile_json" 2>/dev/null)" \
    --arg provider_id "$(jq -r '.provider_id // empty' <<<"$profile_json" 2>/dev/null)" \
    --arg provider_name "$(jq -r '.provider_name // empty' <<<"$profile_json" 2>/dev/null)" \
    --argjson max_tickets "$max_tickets" \
    --argjson lease_seconds "$lease_seconds" \
    --arg prefer_kind "$prefer_kind" \
    --arg model "$model" \
    --argjson capabilities "$capabilities_json" \
    --argjson worker_memory_gb "$worker_memory_gb" \
    --argjson worker_slots_free "$worker_slots_free" \
    --argjson worker_slots_total "$worker_slots_total" \
    --argjson allow_tests "$(bool_is_true "${ONLYMACS_CONTEXT_ALLOW_TESTS:-false}" && printf 'true' || printf 'false')" \
    --argjson allow_installs "$(bool_is_true "${ONLYMACS_CONTEXT_ALLOW_INSTALL:-false}" && printf 'true' || printf 'false')" \
    '{member_id:(if ($member_id | length) > 0 then $member_id else null end), member_name:(if ($member_name | length) > 0 then $member_name else null end), provider_id:(if ($provider_id | length) > 0 then $provider_id else null end), provider_name:(if ($provider_name | length) > 0 then $provider_name else null end), max_tickets:$max_tickets, lease_seconds:$lease_seconds, prefer_kind:(if ($prefer_kind | length) > 0 then $prefer_kind else null end), model:(if ($model | length) > 0 then $model else null end), capabilities:$capabilities, worker_memory_gb:$worker_memory_gb, worker_slots_free:$worker_slots_free, worker_slots_total:$worker_slots_total, allow_test_execution:$allow_tests, allow_dependency_install:$allow_installs}')"
  request_json POST "/admin/v1/jobs/${job_id}/tickets/claim" "$claim_payload" || return 1
  require_success "Could not claim OnlyMacs job tickets." || return 1
  ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON="$ONLYMACS_LAST_HTTP_BODY"
  count="$(jq -r '(.tickets // []) | length' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON" 2>/dev/null || printf '0')"
  [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || return 2
  return 0
}

onlymacs_jobs_claim_available() {
  local job_id="${1:-}" swarm_id="${2:-}" max_tickets="${3:-1}" capabilities_json="${4:-[]}" prefer_kind="${5:-}" lease_seconds="${6:-600}" model_alias="${7:-local-first}"
  local query status job rc
  ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON=""
  if [[ -n "$job_id" ]]; then
    rc=0
    onlymacs_jobs_claim_tickets "$job_id" "$max_tickets" "$capabilities_json" "$prefer_kind" "$lease_seconds" "$model_alias" || rc=$?
    return "$rc"
  fi
  for status in running queued; do
    query="?limit=50&status=${status}"
    [[ -n "$swarm_id" ]] && query="${query}&swarm_id=${swarm_id}"
    request_json GET "/admin/v1/jobs${query}" || return 1
    require_success "Could not list OnlyMacs jobs for worker claims." || return 1
    while IFS= read -r job; do
      [[ -n "$job" ]] || continue
      rc=0
      onlymacs_jobs_claim_tickets "$job" "$max_tickets" "$capabilities_json" "$prefer_kind" "$lease_seconds" "$model_alias" || rc=$?
      case "$rc" in
        0) return 0 ;;
        2) ;;
        *) return "$rc" ;;
      esac
    done < <(jq -r '.jobs[]?.id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")
  done
  return 2
}

onlymacs_jobs_ticket_prompt() {
  local job_json="${1:-}" ticket_json="${2:-}"
  [[ -n "$job_json" ]] || job_json='{}'
  [[ -n "$ticket_json" ]] || ticket_json='{}'
  jq -nr --argjson job "$job_json" --argjson ticket "$ticket_json" '
    def arr($v): (($v // []) | if type == "array" then map(tostring) else [] end);
    "You are executing one OnlyMacs swarm job-board ticket.\n\n" +
    "Original OnlyMacs invocation:\n" + (($job.invocation // "") | tostring) + "\n\n" +
    "Original task summary:\n" + (($job.prompt_preview // "") | tostring) + "\n\n" +
    "Ticket:\n" +
    "- id: " + (($ticket.id // "") | tostring) + "\n" +
    "- kind: " + (($ticket.kind // "") | tostring) + "\n" +
    "- title: " + (($ticket.title // "") | tostring) + "\n" +
    "- target_files: " + (arr($ticket.target_files) | join(", ")) + "\n" +
    "- dependencies: " + (arr($ticket.dependencies) | join(", ")) + "\n" +
    "- required_capability: " + (($ticket.required_capability // "") | tostring) + "\n" +
    "- context_read_mode: " + (($ticket.context_read_mode // $job.context_policy.context_read_mode // "") | tostring) + "\n" +
    "- context_write_mode: " + (($ticket.context_write_mode // $job.context_policy.context_write_mode // "") | tostring) + "\n" +
    "- validators: " + (([($ticket.validator_command // "")] + arr($ticket.validator_commands)) | map(select(length > 0)) | join(" ; ")) + "\n\n" +
    "Workspace handoff: staged worker files should live under ONLYMACS_JOB_WORKSPACE_DIR when a worker has direct filesystem access; otherwise return an artifact bundle for the finalizer.\n\n" +
    "Work only this ticket. If files or patches are needed, return them as an onlymacs.artifact_bundle.v1 structure or with ONLYMACS_ARTIFACT_BEGIN / ONLYMACS_ARTIFACT_END blocks. Include target paths, commands you expect the finalizer to run, and concise notes. Do not assume every Mac uses the same model; optimize for a clean handoff to merge/review/test tickets."
  '
}

onlymacs_jobs_ticket_validator_commands_json() {
  local ticket_json="${1:-}"
  [[ -n "$ticket_json" ]] || ticket_json='{}'
  jq -c '[.validator_command? // empty] + (.validator_commands // []) | map(tostring | select(length > 0))' <<<"$ticket_json"
}

onlymacs_jobs_prompt_looks_like_coding() {
  local prompt
  prompt="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$prompt" =~ (code|coding|website|landing|react|next\.js|typescript|javascript|three|webgl|canvas|css|html|api|backend|frontend|repo|repository|patch|refactor|bug|test|build|component|cms|dashboard) ]]
}

onlymacs_jobs_default_tickets_json() {
  local prompt="${1:-}" validators_json="${2:-[]}" validator_commands_json
  validator_commands_json="$(jq -c '[.[]?.command // empty] | map(select(length > 0))' <<<"$validators_json" 2>/dev/null || printf '[]')"
  if onlymacs_jobs_prompt_looks_like_coding "$prompt"; then
    jq -n --argjson validators "$validator_commands_json" '[
      {
        id: "ticket-plan",
        kind: "plan",
        title: "Plan file ownership and dependencies",
        required_capability: "planner",
        context_write_mode: "read_only"
      },
      {
        id: "ticket-implement",
        kind: "patch",
        title: "Implement staged coding changes",
        dependencies: ["ticket-plan"],
        required_capability: "coder",
        context_write_mode: "staged"
      },
      {
        id: "ticket-review",
        kind: "review",
        title: "Review implementation for correctness and integration risk",
        dependencies: ["ticket-implement"],
        required_capability: "reviewer",
        context_write_mode: "read_only"
      },
      {
        id: "ticket-test",
        kind: "test",
        title: "Run validators and smoke checks",
        dependencies: ["ticket-implement"],
        required_capability: "tester",
        validator_commands: (if ($validators | length) > 0 then $validators else ["html-css-js-smoke"] end),
        context_write_mode: "read_only"
      },
      {
        id: "ticket-merge",
        kind: "merge",
        title: "Assemble final patch and handoff",
        dependencies: ["ticket-review", "ticket-test"],
        required_capability: "merge",
        context_write_mode: "staged"
      }
    ]'
  else
    jq -n '[{"kind":"plan","title":"Plan work","required_capability":"planner"}]'
  fi
}

onlymacs_jobs_command_is_install() {
  case "${1:-}" in
    npm\ install*|pnpm\ install*|yarn\ add*|yarn\ install*|brew\ install*|pip\ install*|pip3\ install*|uv\ add*|uv\ pip\ install*|bundle\ install*|gem\ install*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

onlymacs_jobs_validator_command_allowed() {
  local command
  command="$(printf '%s' "${1:-}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  if bool_is_true "${ONLYMACS_ALLOW_ARBITRARY_VALIDATORS:-false}"; then
    return 0
  fi
  case "$command" in
    *[\;\&\|\`\$\<\>]*)
      return 1
      ;;
    true|false|html-css-js-smoke|canvas-webgl-render-smoke|threejs-canvas-nonblank-smoke)
      return 0
      ;;
    npm\ test*|npm\ run\ test*|npm\ run\ build*|pnpm\ test*|pnpm\ run\ test*|pnpm\ run\ build*|yarn\ test*|yarn\ build*|go\ test*|swift\ test*|pytest*|python\ -m\ pytest*|python3\ -m\ pytest*|make\ test*|make\ test-public*|cargo\ test*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

onlymacs_jobs_run_validator_commands() {
  local commands_json="${1:-[]}" command script script_dir results_json failures output status exit_code start completed started_epoch duration item
  local commands=()
  while IFS= read -r command; do
    [[ -n "$command" ]] && commands+=("$command")
  done < <(jq -r '.[]' <<<"$commands_json" 2>/dev/null)
  script="${ONLYMACS_CODING_VALIDATOR_SCRIPT:-${ONLYMACS_SCRIPT_DIR}/../../scripts/qa/onlymacs-coding-validator.sh}"
  script_dir="$(cd "$(dirname "$script")" 2>/dev/null && pwd || dirname "$script")"
  script="${script_dir}/$(basename "$script")"
  if [[ "${#commands[@]}" -eq 0 ]]; then
    commands=("$script --run --json")
  fi
  results_json="[]"
  failures=0
  for command in "${commands[@]}"; do
    [[ -n "$command" ]] || continue
    start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    started_epoch="$(date +%s)"
    if onlymacs_jobs_command_is_install "$command" && ! bool_is_true "${ONLYMACS_CONTEXT_ALLOW_INSTALL:-false}"; then
      output="blocked dependency install command without --allow-installs: ${command}"
      status="failed"
      exit_code=1
    elif ! onlymacs_jobs_validator_command_allowed "$command"; then
      output="blocked validator command outside the safe validator allowlist: ${command}"
      status="failed"
      exit_code=1
    elif [[ "$command" == "html-css-js-smoke" || "$command" == "canvas-webgl-render-smoke" || "$command" == "threejs-canvas-nonblank-smoke" ]]; then
      if output="$(ONLYMACS_ALLOW_VALIDATOR_INSTALLS="${ONLYMACS_CONTEXT_ALLOW_INSTALL:-0}" "$script" --run --json 2>&1)"; then
        status="passed"
        exit_code=0
      else
        status="failed"
        exit_code=1
      fi
    else
      if output="$(bash -lc "$command" 2>&1)"; then
        status="passed"
        exit_code=0
      else
        status="failed"
        exit_code=$?
      fi
    fi
    [[ "$status" == "passed" ]] || failures=$((failures + 1))
    completed="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    duration=$(( $(date +%s) - started_epoch ))
    item="$(jq -n \
      --arg command "$command" \
      --arg kind "validator" \
      --arg status "$status" \
      --arg message "$(printf '%s' "$output" | tail -20 | sed -E 's/[[:space:]]+/ /g' | cut -c 1-1200)" \
      --arg started_at "$start" \
      --arg completed_at "$completed" \
      --argjson exit_code "$exit_code" \
      --argjson duration "$duration" \
      '{command:$command,kind:$kind,status:$status,message:$message,started_at:$started_at,completed_at:$completed_at,exit_code:$exit_code,duration_seconds:$duration}')"
    results_json="$(jq -c --argjson item "$item" '. + [$item]' <<<"$results_json")"
  done
  ONLYMACS_JOB_WORKER_VALIDATION_JSON="$results_json"
  ONLYMACS_JOB_WORKER_VALIDATION_MESSAGE="$(jq -r '[.[] | select(.status != "passed") | .message] | join("; ")' <<<"$results_json" | cut -c 1-1200)"
  [[ "$failures" -eq 0 ]]
}

onlymacs_jobs_run_metadata_json() {
  local run_dir="${1:-}" ticket_json="${2:-}" status_path artifacts_json
  [[ -n "$ticket_json" ]] || ticket_json='{}'
  status_path="${run_dir}/status.json"
  if [[ -n "$run_dir" && -f "$status_path" ]]; then
    jq -c --arg inbox "$run_dir" --argjson ticket "$ticket_json" '
      {
        executor: "onlymacs-cli jobs work",
        inbox: $inbox,
        status_path: ($inbox + "/status.json"),
        run_id: (.run_id // null),
        status: (.status // null),
        provider_id: (.provider_id // null),
        provider_name: (.provider_name // null),
        model: (.model // null),
        artifacts: ((.artifacts // []) + ([.artifact_path // empty] | map(select(length > 0))) | unique),
        ticket_kind: ($ticket.kind // null),
        target_files: ($ticket.target_files // [])
      }' "$status_path"
    return 0
  fi
  artifacts_json='[]'
  jq -n --arg inbox "$run_dir" --argjson artifacts "$artifacts_json" --argjson ticket "$ticket_json" '{executor:"onlymacs-cli jobs work", inbox:(if ($inbox | length) > 0 then $inbox else null end), artifacts:$artifacts, ticket_kind:($ticket.kind // null), target_files:($ticket.target_files // [])}'
}

onlymacs_jobs_ticket_workspace_dir() {
  local job_json="${1:-}" ticket_json="${2:-}" job_id ticket_id root
  [[ -n "$job_json" ]] || job_json='{}'
  [[ -n "$ticket_json" ]] || ticket_json='{}'
  job_id="$(jq -r '.id // .job_id // "job-local"' <<<"$job_json" 2>/dev/null | sed -E 's/[^A-Za-z0-9._-]+/-/g')"
  ticket_id="$(jq -r '.id // "ticket-local"' <<<"$ticket_json" 2>/dev/null | sed -E 's/[^A-Za-z0-9._-]+/-/g')"
  root="${ONLYMACS_JOB_WORKSPACE_ROOT:-$PWD/onlymacs/workspaces}"
  printf '%s/%s/%s' "$root" "$job_id" "$ticket_id"
}

onlymacs_jobs_result_output_bytes() {
  local run_dir="${1:-}" bytes=0 file size
  if [[ -n "$run_dir" && -s "${run_dir}/RESULT.md" ]]; then
    wc -c <"${run_dir}/RESULT.md" | tr -d '[:space:]'
    return 0
  fi
  if [[ -n "$run_dir" && -d "${run_dir}/files" ]]; then
    while IFS= read -r file; do
      size="$(wc -c <"$file" 2>/dev/null | tr -d '[:space:]' || printf '0')"
      [[ "$size" =~ ^[0-9]+$ ]] || size=0
      bytes=$((bytes + size))
    done < <(find "${run_dir}/files" -maxdepth 1 -type f 2>/dev/null)
  fi
  printf '%s' "$bytes"
}

onlymacs_jobs_artifact_bundle_json() {
  local metadata_json="${1:-}" message="${2:-}"
  [[ -n "$metadata_json" ]] || metadata_json='{}'
  jq -n --arg schema "onlymacs.artifact_bundle.v1" --arg message "$message" --argjson metadata "$metadata_json" '
    {
      schema: $schema,
      files: (($metadata.artifacts // []) | map({path:.})),
      notes: ($message | if length > 0 then . else null end),
      metadata: $metadata
    }'
}

onlymacs_jobs_update_ticket() {
  local action="${1:-}" job_id="${2:-}" ticket_id="${3:-}" lease_id="${4:-}" message="${5:-}" metadata_json="${6:-}" artifact_bundle_json="${7:-}" validation_json="${8:-[]}" output_bytes="${9:-0}" create_repair="${10:-false}"
  local output_tokens payload
  [[ -n "$metadata_json" ]] || metadata_json='{}'
  [[ -n "$artifact_bundle_json" ]] || artifact_bundle_json='{}'
  [[ -n "$action" && -n "$job_id" && -n "$ticket_id" ]] || return 1
  [[ "$output_bytes" =~ ^[0-9]+$ ]] || output_bytes=0
  output_tokens=$(((output_bytes + 3) / 4))
  payload="$(jq -n \
    --arg lease_id "$lease_id" \
    --arg message "$message" \
    --argjson metadata "$metadata_json" \
    --argjson artifact_bundle "$artifact_bundle_json" \
    --argjson validation_results "$validation_json" \
    --argjson output_bytes "$output_bytes" \
    --argjson output_tokens "$output_tokens" \
    --argjson create_repair "$create_repair" \
    '{lease_id:(if ($lease_id | length) > 0 then $lease_id else null end), message:(if ($message | length) > 0 then $message else null end), metadata:$metadata, artifact_bundle:$artifact_bundle, validation_results:$validation_results, output_bytes:$output_bytes, output_tokens_estimate:$output_tokens, create_repair_ticket:$create_repair, repair_message:$message}')"
  request_json POST "/admin/v1/jobs/${job_id}/tickets/${ticket_id}/${action}" "$payload" || return 1
  require_success "Could not ${action} OnlyMacs job ticket." || return 1
}

onlymacs_jobs_heartbeat_loop() {
  local job_id="${1:-}" ticket_id="${2:-}" lease_id="${3:-}" lease_seconds="${4:-600}" interval="${5:-30}" payload
  [[ "$interval" =~ ^[0-9]+$ && "$interval" -gt 0 ]] || interval=30
  [[ "$lease_seconds" =~ ^[0-9]+$ && "$lease_seconds" -gt 0 ]] || lease_seconds=600
  payload="$(jq -n --arg lease_id "$lease_id" --argjson lease_seconds "$lease_seconds" '{lease_id:$lease_id, lease_seconds:$lease_seconds}')"
  while true; do
    sleep "$interval"
    request_json POST "/admin/v1/jobs/${job_id}/tickets/${ticket_id}/heartbeat" "$payload" >/dev/null 2>&1 || true
  done
}

onlymacs_jobs_execute_model_ticket() {
  local job_json="${1:-}" ticket_json="${2:-}" prompt model_alias route_scope run_dir metadata_json artifact_bundle_json output_bytes rc workspace_dir
  local previous_go_wide="${ONLYMACS_GO_WIDE_MODE:-0}" previous_execution_mode="${ONLYMACS_EXECUTION_MODE:-auto}"
  [[ -n "$job_json" ]] || job_json='{}'
  [[ -n "$ticket_json" ]] || ticket_json='{}'
  prompt="$(onlymacs_jobs_ticket_prompt "$job_json" "$ticket_json")"
  model_alias="${ONLYMACS_JOB_WORKER_MODEL_ALIAS:-local-first}"
  route_scope="$(route_scope_for_alias "$model_alias")"
  workspace_dir="$(onlymacs_jobs_ticket_workspace_dir "$job_json" "$ticket_json")"
  mkdir -p "$workspace_dir" 2>/dev/null || true
  export ONLYMACS_JOB_WORKSPACE_DIR="$workspace_dir"
  ONLYMACS_GO_WIDE_MODE=0
  ONLYMACS_EXECUTION_MODE="${ONLYMACS_JOB_WORKER_EXECUTION_MODE:-extended}"
  rc=0
  run_orchestrated_chat "" "$model_alias" "$prompt" "$route_scope" || rc=$?
  ONLYMACS_GO_WIDE_MODE="$previous_go_wide"
  ONLYMACS_EXECUTION_MODE="$previous_execution_mode"
  run_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}"
  metadata_json="$(onlymacs_jobs_run_metadata_json "$run_dir" "$ticket_json" | jq -c --arg workspace "$workspace_dir" '. + {workspace_dir:$workspace}')"
  output_bytes="$(onlymacs_jobs_result_output_bytes "$run_dir")"
  if [[ "$rc" -eq 0 ]]; then
    ONLYMACS_JOB_WORKER_METADATA_JSON="$metadata_json"
    ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON="$(onlymacs_jobs_artifact_bundle_json "$metadata_json" "completed by OnlyMacs worker")"
    ONLYMACS_JOB_WORKER_OUTPUT_BYTES="$output_bytes"
    ONLYMACS_JOB_WORKER_MESSAGE="completed by OnlyMacs worker"
    return 0
  fi
  artifact_bundle_json="$(onlymacs_jobs_artifact_bundle_json "$metadata_json" "OnlyMacs worker failed; see inbox metadata")"
  ONLYMACS_JOB_WORKER_METADATA_JSON="$metadata_json"
  ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON="$artifact_bundle_json"
  ONLYMACS_JOB_WORKER_OUTPUT_BYTES="$output_bytes"
  ONLYMACS_JOB_WORKER_MESSAGE="OnlyMacs worker failed; see inbox metadata"
  return "$rc"
}

onlymacs_jobs_execute_ticket() {
  local job_json="${1:-}" ticket_json="${2:-}" kind commands_json
  [[ -n "$job_json" ]] || job_json='{}'
  [[ -n "$ticket_json" ]] || ticket_json='{}'
  kind="$(jq -r '.kind // "generate"' <<<"$ticket_json")"
  ONLYMACS_JOB_WORKER_METADATA_JSON="{}"
  ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON="{}"
  ONLYMACS_JOB_WORKER_VALIDATION_JSON="[]"
  ONLYMACS_JOB_WORKER_OUTPUT_BYTES="0"
  ONLYMACS_JOB_WORKER_MESSAGE=""
  case "$kind" in
    test|validator)
      if ! bool_is_true "${ONLYMACS_CONTEXT_ALLOW_TESTS:-false}"; then
        ONLYMACS_JOB_WORKER_MESSAGE="worker skipped ${kind} ticket because --allow-tests was not enabled"
        return 12
      fi
      commands_json="$(onlymacs_jobs_ticket_validator_commands_json "$ticket_json")"
      if onlymacs_jobs_run_validator_commands "$commands_json"; then
        ONLYMACS_JOB_WORKER_METADATA_JSON="$(jq -n --argjson results "$ONLYMACS_JOB_WORKER_VALIDATION_JSON" --argjson ticket "$ticket_json" '{executor:"onlymacs-cli jobs work", validation_results:$results, ticket_kind:($ticket.kind // null), target_files:($ticket.target_files // [])}')"
        ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON="$(onlymacs_jobs_artifact_bundle_json "$ONLYMACS_JOB_WORKER_METADATA_JSON" "validation passed")"
        ONLYMACS_JOB_WORKER_MESSAGE="validation passed"
        return 0
      fi
      ONLYMACS_JOB_WORKER_METADATA_JSON="$(jq -n --argjson results "$ONLYMACS_JOB_WORKER_VALIDATION_JSON" --argjson ticket "$ticket_json" '{executor:"onlymacs-cli jobs work", validation_results:$results, ticket_kind:($ticket.kind // null), target_files:($ticket.target_files // [])}')"
      ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON="$(onlymacs_jobs_artifact_bundle_json "$ONLYMACS_JOB_WORKER_METADATA_JSON" "${ONLYMACS_JOB_WORKER_VALIDATION_MESSAGE:-validation failed}")"
      ONLYMACS_JOB_WORKER_MESSAGE="${ONLYMACS_JOB_WORKER_VALIDATION_MESSAGE:-validation failed}"
      return 1
      ;;
    *)
      onlymacs_jobs_execute_model_ticket "$job_json" "$ticket_json"
      ;;
  esac
}

onlymacs_jobs_work_loop() {
  local job_id="" swarm_id="" max_tickets=1 idle_timeout=300 poll_seconds=5 lease_seconds=600 heartbeat_seconds=30 once=0 max_completed=0 prefer_kind="" no_execute=0
  local capabilities=() capabilities_json idle_started processed=0 claim_rc ticket_count job_json ticket_json ticket_id lease_id kind heartbeat_pid execute_rc repair_on_failure
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --job|--job-id)
        job_id="${2:-}"
        shift 2
        ;;
      --job=*|--job-id=*)
        job_id="${1#*=}"
        shift
        ;;
      --swarm|--swarm-id)
        swarm_id="${2:-}"
        shift 2
        ;;
      --swarm=*|--swarm-id=*)
        swarm_id="${1#*=}"
        shift
        ;;
      --capability|--cap)
        capabilities+=("${2:-}")
        shift 2
        ;;
      --capability=*|--cap=*)
        capabilities+=("${1#*=}")
        shift
        ;;
      --kind)
        prefer_kind="${2:-}"
        shift 2
        ;;
      --kind=*)
        prefer_kind="${1#*=}"
        shift
        ;;
      --max|--max-tickets)
        max_tickets="${2:-1}"
        shift 2
        ;;
      --max=*|--max-tickets=*)
        max_tickets="${1#*=}"
        shift
        ;;
      --slots|--lanes)
        max_tickets="${2:-1}"
        shift 2
        ;;
      --slots=*|--lanes=*)
        max_tickets="${1#*=}"
        shift
        ;;
      --max-completed)
        max_completed="${2:-0}"
        shift 2
        ;;
      --max-completed=*)
        max_completed="${1#*=}"
        shift
        ;;
      --idle-timeout)
        idle_timeout="${2:-300}"
        shift 2
        ;;
      --idle-timeout=*)
        idle_timeout="${1#*=}"
        shift
        ;;
      --poll)
        poll_seconds="${2:-5}"
        shift 2
        ;;
      --poll=*)
        poll_seconds="${1#*=}"
        shift
        ;;
      --watch)
        idle_timeout=0
        shift
        ;;
      --lease-seconds)
        lease_seconds="${2:-600}"
        shift 2
        ;;
      --lease-seconds=*)
        lease_seconds="${1#*=}"
        shift
        ;;
      --heartbeat-seconds)
        heartbeat_seconds="${2:-30}"
        shift 2
        ;;
      --heartbeat-seconds=*)
        heartbeat_seconds="${1#*=}"
        shift
        ;;
      --model|--model-alias)
        ONLYMACS_JOB_WORKER_MODEL_ALIAS="${2:-local-first}"
        shift 2
        ;;
      --model=*|--model-alias=*)
        ONLYMACS_JOB_WORKER_MODEL_ALIAS="${1#*=}"
        shift
        ;;
      --allow-tests)
        ONLYMACS_CONTEXT_ALLOW_TESTS=1
        shift
        ;;
      --allow-installs|--allow-install|--allow-dependency-install)
        ONLYMACS_CONTEXT_ALLOW_INSTALL=1
        shift
        ;;
      --once)
        once=1
        shift
        ;;
      --no-execute|--claim-only)
        no_execute=1
        shift
        ;;
      *)
        if [[ -z "$job_id" && "$1" == job-* ]]; then
          job_id="$1"
        fi
        shift
        ;;
    esac
  done
  [[ "$max_tickets" =~ ^[0-9]+$ && "$max_tickets" -gt 0 ]] || max_tickets=1
  [[ "$max_tickets" -le 8 ]] || max_tickets=8
  [[ "$idle_timeout" =~ ^[0-9]+$ ]] || idle_timeout=300
  [[ "$poll_seconds" =~ ^[0-9]+$ && "$poll_seconds" -gt 0 ]] || poll_seconds=5
  [[ "$max_completed" =~ ^[0-9]+$ ]] || max_completed=0
  : "${ONLYMACS_JOB_WORKER_MODEL_ALIAS:=local-first}"
  ONLYMACS_JOB_WORKER_PROFILE_JSON="$(onlymacs_job_worker_profile_json "$ONLYMACS_JOB_WORKER_MODEL_ALIAS")"
  if [[ "${#capabilities[@]}" -gt 0 ]]; then
    capabilities_json="$(onlymacs_job_worker_capabilities_json "${capabilities[@]}")"
  else
    capabilities_json="$(onlymacs_job_worker_capabilities_json)"
  fi
  idle_started="$(date +%s)"
  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    printf 'OnlyMacs job worker started'
    [[ -n "$job_id" ]] && printf ' for %s' "$job_id"
    printf ' (model %s, claim up to %s ticket(s)%s).\n' "$ONLYMACS_JOB_WORKER_MODEL_ALIAS" "$max_tickets" "$([[ "$idle_timeout" -eq 0 ]] && printf ', watching continuously' || printf '')"
  fi
  while true; do
    claim_rc=0
    onlymacs_jobs_claim_available "$job_id" "$swarm_id" "$max_tickets" "$capabilities_json" "$prefer_kind" "$lease_seconds" "$ONLYMACS_JOB_WORKER_MODEL_ALIAS" || claim_rc=$?
    if [[ "$claim_rc" -eq 2 ]]; then
      if [[ "$once" -eq 1 ]]; then
        [[ "$ONLYMACS_JSON_MODE" -eq 1 ]] && printf '{"status":"idle","tickets_completed":%s}\n' "$processed" || printf 'No claimable OnlyMacs job tickets are available.\n'
        return 0
      fi
      if [[ "$idle_timeout" -gt 0 && $(( $(date +%s) - idle_started )) -ge "$idle_timeout" ]]; then
        [[ "$ONLYMACS_JSON_MODE" -eq 1 ]] && printf '{"status":"idle_timeout","tickets_completed":%s}\n' "$processed" || printf 'OnlyMacs job worker exiting after %ss idle.\n' "$idle_timeout"
        return 0
      fi
      sleep "$poll_seconds"
      continue
    fi
    [[ "$claim_rc" -eq 0 ]] || return "$claim_rc"
    idle_started="$(date +%s)"
    ticket_count="$(jq -r '(.tickets // []) | length' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")"
    job_json="$(jq -c '.job // {}' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")"
    for ((idx = 0; idx < ticket_count; idx++)); do
      ticket_json="$(jq -c --argjson idx "$idx" '.tickets[$idx]' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")"
      ticket_id="$(jq -r '.id // empty' <<<"$ticket_json")"
      lease_id="$(jq -r '.lease_id // empty' <<<"$ticket_json")"
      kind="$(jq -r '.kind // "generate"' <<<"$ticket_json")"
      [[ -n "$ticket_id" ]] || continue
      if [[ "$no_execute" -eq 1 ]]; then
        printf 'Claimed %s (%s) lease %s\n' "$ticket_id" "$kind" "$lease_id"
        continue
      fi
      heartbeat_pid=""
      onlymacs_jobs_heartbeat_loop "$(jq -r '.job_id // .job.id // empty' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")" "$ticket_id" "$lease_id" "$lease_seconds" "$heartbeat_seconds" &
      heartbeat_pid=$!
      execute_rc=0
      onlymacs_jobs_execute_ticket "$job_json" "$ticket_json" || execute_rc=$?
      if [[ -n "$heartbeat_pid" ]]; then
        kill "$heartbeat_pid" >/dev/null 2>&1 || true
        wait "$heartbeat_pid" 2>/dev/null || true
      fi
      if [[ "$execute_rc" -eq 12 ]]; then
        onlymacs_jobs_update_ticket "requeue" "$(jq -r '.job_id // empty' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")" "$ticket_id" "$lease_id" "$ONLYMACS_JOB_WORKER_MESSAGE" "{}" "{}" "[]" "0" "false" || return 1
        continue
      fi
      if [[ "$execute_rc" -eq 0 ]]; then
        onlymacs_jobs_update_ticket "complete" "$(jq -r '.job_id // empty' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")" "$ticket_id" "$lease_id" "$ONLYMACS_JOB_WORKER_MESSAGE" "$ONLYMACS_JOB_WORKER_METADATA_JSON" "$ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON" "$ONLYMACS_JOB_WORKER_VALIDATION_JSON" "$ONLYMACS_JOB_WORKER_OUTPUT_BYTES" "false" || return 1
        processed=$((processed + 1))
      else
        repair_on_failure="${ONLYMACS_JOB_WORKER_REPAIR_ON_FAILURE:-1}"
        onlymacs_jobs_update_ticket "fail" "$(jq -r '.job_id // empty' <<<"$ONLYMACS_JOB_WORKER_LAST_CLAIM_JSON")" "$ticket_id" "$lease_id" "$ONLYMACS_JOB_WORKER_MESSAGE" "$ONLYMACS_JOB_WORKER_METADATA_JSON" "$ONLYMACS_JOB_WORKER_ARTIFACT_BUNDLE_JSON" "$ONLYMACS_JOB_WORKER_VALIDATION_JSON" "$ONLYMACS_JOB_WORKER_OUTPUT_BYTES" "$(bool_is_true "$repair_on_failure" && printf true || printf false)" || return 1
      fi
      if [[ "$max_completed" -gt 0 && "$processed" -ge "$max_completed" ]]; then
        [[ "$ONLYMACS_JSON_MODE" -eq 1 ]] && printf '{"status":"completed_limit","tickets_completed":%s}\n' "$processed" || printf 'OnlyMacs job worker completed %s ticket(s).\n' "$processed"
        return 0
      fi
    done
    [[ "$once" -eq 0 ]] || return 0
  done
}

run_jobs() {
  local subcommand="${1:-list}"
  shift || true
  case "$subcommand" in
    list|"")
      local swarm_id="" status="" limit="25" query
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --swarm|--swarm-id)
            swarm_id="${2:-}"
            shift 2
            ;;
          --swarm=*|--swarm-id=*)
            swarm_id="${1#*=}"
            shift
            ;;
          --status)
            status="${2:-}"
            shift 2
            ;;
          --status=*)
            status="${1#*=}"
            shift
            ;;
          --limit)
            limit="${2:-25}"
            shift 2
            ;;
          --limit=*)
            limit="${1#*=}"
            shift
            ;;
          *)
            shift
            ;;
        esac
      done
      query="?limit=${limit}"
      [[ -n "$swarm_id" ]] && query="${query}&swarm_id=${swarm_id}"
      [[ -n "$status" ]] && query="${query}&status=${status}"
      request_json GET "/admin/v1/jobs${query}" || return 1
      require_success "Could not list OnlyMacs jobs." || return 1
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
      else
        printf 'OnlyMacs Jobs\n'
        jq -r '.jobs[]? | "- \(.id) · \(.status) · \(.swarm_name // .swarm_id) · tickets \((.ticket_summary.total // 0)) · \(.prompt_preview // .invocation // "untitled")"' <<<"$ONLYMACS_LAST_HTTP_BODY"
      fi
      ;;
    create)
      local swarm_id="" prompt="" invocation="${ONLYMACS_INVOCATION_LABEL:-onlymacs jobs create}" ticket_file="" validators_file=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --swarm|--swarm-id)
            swarm_id="${2:-}"
            shift 2
            ;;
          --swarm=*|--swarm-id=*)
            swarm_id="${1#*=}"
            shift
            ;;
          --prompt)
            prompt="${2:-}"
            shift 2
            ;;
          --prompt=*)
            prompt="${1#*=}"
            shift
            ;;
          --invocation)
            invocation="${2:-}"
            shift 2
            ;;
          --invocation=*)
            invocation="${1#*=}"
            shift
            ;;
          --tickets|--ticket-file)
            ticket_file="${2:-}"
            shift 2
            ;;
          --tickets=*|--ticket-file=*)
            ticket_file="${1#*=}"
            shift
            ;;
          --validators|--validator-file)
            validators_file="${2:-}"
            shift 2
            ;;
          --validators=*|--validator-file=*)
            validators_file="${1#*=}"
            shift
            ;;
          *)
            prompt="${prompt}${prompt:+ }$1"
            shift
            ;;
        esac
      done
      local tickets_json validators_json payload
      if [[ -n "$ticket_file" ]]; then
        [[ -r "$ticket_file" ]] || { printf 'OnlyMacs cannot read ticket file: %s\n' "$ticket_file" >&2; return 1; }
        tickets_json="$(jq -c 'if type == "array" then . else .tickets end' "$ticket_file")"
      fi
      if [[ -n "$validators_file" ]]; then
        [[ -r "$validators_file" ]] || { printf 'OnlyMacs cannot read validator file: %s\n' "$validators_file" >&2; return 1; }
        validators_json="$(jq -c 'if type == "array" then . else .validators end' "$validators_file")"
      else
        validators_json='[]'
      fi
      if [[ -z "${tickets_json:-}" || "$tickets_json" == "null" ]]; then
        tickets_json="$(onlymacs_jobs_default_tickets_json "$prompt" "$validators_json")"
      fi
      payload="$(jq -n \
        --arg swarm_id "$swarm_id" \
        --arg invocation "$invocation" \
        --arg prompt_preview "$prompt" \
        --argjson tickets "$tickets_json" \
        --argjson validators "$validators_json" \
        '{swarm_id:(if ($swarm_id | length) > 0 then $swarm_id else null end), invocation:$invocation, prompt_preview:$prompt_preview, tickets:$tickets, validators:$validators}')"
      request_json POST "/admin/v1/jobs" "$payload" || return 1
      require_success "Could not create OnlyMacs job." || return 1
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
      else
        printf 'Created job %s\n' "$(jq -r '.job.id' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        printf 'Tickets: %s\n' "$(jq -r '.job.ticket_summary.total // (.job.tickets | length)' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      fi
      ;;
    claim)
      local job_id="${1:-}" max_tickets=1 capabilities=() prefer_kind=""
      [[ -n "$job_id" ]] || { printf 'usage: %s jobs claim <job-id> [--capability frontend] [--max 2]\n' "$ONLYMACS_WRAPPER_NAME" >&2; return 1; }
      shift || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --capability|--cap)
            capabilities+=("${2:-}")
            shift 2
            ;;
          --capability=*|--cap=*)
            capabilities+=("${1#*=}")
            shift
            ;;
          --max|--max-tickets)
            max_tickets="${2:-1}"
            shift 2
            ;;
          --max=*|--max-tickets=*)
            max_tickets="${1#*=}"
            shift
            ;;
          --kind)
            prefer_kind="${2:-}"
            shift 2
            ;;
          --kind=*)
            prefer_kind="${1#*=}"
            shift
            ;;
          *)
            shift
            ;;
        esac
      done
      if ! [[ "$max_tickets" =~ ^[0-9]+$ ]]; then
        printf 'OnlyMacs jobs claim --max must be a number.\n' >&2
        return 1
      fi
      ONLYMACS_JOB_WORKER_PROFILE_JSON="$(onlymacs_job_worker_profile_json "${ONLYMACS_JOB_WORKER_MODEL_ALIAS:-local-first}")"
      local caps_json claim_rc
      caps_json="$(onlymacs_job_worker_capabilities_json "${capabilities[@]}")"
      claim_rc=0
      onlymacs_jobs_claim_tickets "$job_id" "$max_tickets" "$caps_json" "$prefer_kind" 600 "${ONLYMACS_JOB_WORKER_MODEL_ALIAS:-local-first}" || claim_rc=$?
      if [[ "$claim_rc" -eq 2 ]]; then
        printf 'No claimable OnlyMacs job tickets are available.\n'
        return 0
      fi
      [[ "$claim_rc" -eq 0 ]] || return "$claim_rc"
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
      else
        jq -r '"Claimed \((.tickets // []) | length) ticket(s) for \(.job_id)"' <<<"$ONLYMACS_LAST_HTTP_BODY"
        jq -r '.tickets[]? | "- \(.id) · \(.kind) · \(.title) · lease \(.lease_id)"' <<<"$ONLYMACS_LAST_HTTP_BODY"
      fi
      ;;
    work|worker)
      onlymacs_jobs_work_loop "$@"
      ;;
    complete|fail|requeue|heartbeat)
      local job_id="${1:-}" ticket_id="${2:-}" message="" lease_id=""
      [[ -n "$job_id" && -n "$ticket_id" ]] || { printf 'usage: %s jobs %s <job-id> <ticket-id> [--message text]\n' "$ONLYMACS_WRAPPER_NAME" "$subcommand" >&2; return 1; }
      shift 2 || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --message)
            message="${2:-}"
            shift 2
            ;;
          --message=*)
            message="${1#*=}"
            shift
            ;;
          --lease)
            lease_id="${2:-}"
            shift 2
            ;;
          --lease=*)
            lease_id="${1#*=}"
            shift
            ;;
          *)
            shift
            ;;
        esac
      done
      request_json POST "/admin/v1/jobs/${job_id}/tickets/${ticket_id}/${subcommand}" "$(jq -n --arg message "$message" --arg lease_id "$lease_id" '{message:(if ($message | length) > 0 then $message else null end), lease_id:(if ($lease_id | length) > 0 then $lease_id else null end), create_repair_ticket:false}')" || return 1
      require_success "Could not update OnlyMacs job ticket." || return 1
      [[ "$ONLYMACS_JSON_MODE" -eq 1 ]] && printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY" || printf 'Updated %s ticket %s on job %s\n' "$subcommand" "$ticket_id" "$job_id"
      ;;
    finalize)
      local job_id="${1:-}" create_merge=true validator_commands=()
      [[ -n "$job_id" ]] || { printf 'usage: %s jobs finalize <job-id> [--validator \"npm run build\"]\n' "$ONLYMACS_WRAPPER_NAME" >&2; return 1; }
      shift || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --validator)
            validator_commands+=("${2:-}")
            shift 2
            ;;
          --validator=*)
            validator_commands+=("${1#*=}")
            shift
            ;;
          --no-merge-ticket)
            create_merge=false
            shift
            ;;
          *)
            shift
            ;;
        esac
      done
      local validators_json
      validators_json="$(printf '%s\n' "${validator_commands[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')"
      request_json POST "/admin/v1/jobs/${job_id}/finalize" "$(jq -n --argjson validators "$validators_json" --argjson create_merge "$([[ "$create_merge" == "true" ]] && printf true || printf false)" '{validator_commands:$validators, create_merge_ticket:$create_merge}')" || return 1
      require_success "Could not finalize OnlyMacs job." || return 1
      [[ "$ONLYMACS_JSON_MODE" -eq 1 ]] && printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY" || jq -r '"Finalizer: \(.job.finalizer.status // "unknown") · \(.job.finalizer.message // "")"' <<<"$ONLYMACS_LAST_HTTP_BODY"
      ;;
    *)
      printf 'usage: %s jobs list|create|claim|work|complete|fail|requeue|heartbeat|finalize\n' "$ONLYMACS_WRAPPER_NAME" >&2
      return 1
      ;;
  esac
}
