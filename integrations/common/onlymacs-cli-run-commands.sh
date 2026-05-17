# Resume, diagnostics, reporting, and inbox/apply command helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after run status helpers are loaded.

orchestrated_resolve_run_dir() {
  local ref="${1:-latest}"
  local root latest_path inbox

  if [[ -d "$ref" ]]; then
    printf '%s' "$(cd "$ref" && pwd)"
    return 0
  fi

  root="$(chat_returns_root)"
  if [[ "$ref" == "latest" || -z "$ref" ]]; then
    latest_path="${root}/latest.json"
    if [[ ! -f "$latest_path" ]]; then
      printf 'OnlyMacs has no latest inbox run to resume yet.\n' >&2
      return 1
    fi
    inbox="$(jq -r '.inbox // empty' "$latest_path" 2>/dev/null || true)"
    if [[ -n "$inbox" && -d "$inbox" ]]; then
      printf '%s' "$(cd "$inbox" && pwd)"
      return 0
    fi
  fi

  if [[ -d "${root}/${ref}" ]]; then
    printf '%s' "$(cd "${root}/${ref}" && pwd)"
    return 0
  fi

  printf 'OnlyMacs could not find an inbox run for %s.\n' "$ref" >&2
  return 1
}

orchestrated_resume_index_for_plan() {
  local plan_path="${1:-}"
  local resume_step="${2:-}"
  local step_count="${3:-0}"
  local raw_index derived_index

  raw_index="$(jq -r 'if has("resume_step_index") and (.resume_step_index != null) then (.resume_step_index | tostring) else "" end' "$plan_path" 2>/dev/null || true)"
  derived_index=""

  if [[ "$resume_step" =~ ^step-0*([0-9]+)$ ]]; then
    derived_index="$((10#${BASH_REMATCH[1]}))"
  fi

  if [[ -z "$derived_index" || ! "$derived_index" =~ ^[0-9]+$ || "$derived_index" -lt 1 || "$derived_index" -gt "$step_count" ]]; then
    derived_index="$(jq -r --arg id "$resume_step" '(.steps | to_entries[]? | select(.value.id == $id) | .key + 1) // empty' "$plan_path" 2>/dev/null || true)"
  fi

  if [[ -n "$derived_index" && "$derived_index" =~ ^[0-9]+$ && "$derived_index" -ge 1 && "$derived_index" -le "$step_count" ]]; then
    printf '%s' "$derived_index"
    return 0
  fi

  if [[ -n "$raw_index" && "$raw_index" =~ ^[0-9]+$ && "$raw_index" -ge 1 && "$raw_index" -le "$step_count" ]]; then
    printf '%s' "$raw_index"
    return 0
  fi

  return 1
}

run_resume_orchestrated() {
  local ref="${1:-latest}"
  local run_dir plan_path prompt_path prompt model_alias route_scope model step_count resume_step resume_index idx
  local plan_file_path started_at artifacts_json requested_provider_id stored_provider_id stored_provider_route_locked stored_pinned_provider_id failed_resume_provider_id

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  plan_path="${run_dir}/plan.json"
  prompt_path="${run_dir}/prompt.txt"
  if [[ ! -f "$plan_path" ]]; then
    printf 'OnlyMacs can only resume extended inbox runs with a saved plan.json: %s\n' "$run_dir" >&2
    return 1
  fi
  if [[ ! -f "$prompt_path" ]]; then
    printf 'OnlyMacs cannot resume this run because prompt.txt is missing. Re-run the original request to create resumable metadata.\n' >&2
    return 1
  fi

  prompt="$(cat "$prompt_path")"
  model_alias="$(jq -r '.model_alias // "remote-first"' "$plan_path")"
  route_scope="$(jq -r '.route_scope // "swarm"' "$plan_path")"
  if orchestrated_go_wide_enabled "" && ! alias_is_privacy_locked_route "$model_alias"; then
    model_alias="wide"
    route_scope="swarm"
  fi
  started_at="$(jq -r '.created_at // empty' "$plan_path")"
  step_count="$(jq -r '.steps | length' "$plan_path")"
  resume_step="$(jq -r '.resume_step // empty' "$plan_path" 2>/dev/null || true)"
  if [[ -z "$resume_step" ]]; then
    resume_step="$(jq -r '([.steps[]? | select(.status != "completed") | .id] | first // "step-01")' "$plan_path" 2>/dev/null || printf 'step-01')"
  fi
  if ! resume_index="$(orchestrated_resume_index_for_plan "$plan_path" "$resume_step" "$step_count")"; then
    printf 'OnlyMacs cannot resume because plan.json has an invalid resume point: %s.\n' "$resume_step" >&2
    return 1
  fi
  if [[ "$resume_index" -gt "$step_count" ]]; then
    printf 'OnlyMacs run already appears complete: %s\n' "$run_dir"
    return 0
  fi

  ONLYMACS_CURRENT_RETURN_RUN_ID="$(basename "$run_dir")"
  ONLYMACS_CURRENT_RETURN_DIR="$run_dir"
  ONLYMACS_CURRENT_RETURN_STARTED_AT="${started_at:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
  ONLYMACS_CURRENT_RETURN_STARTED_EPOCH="$(date +%s)"
  ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE="$route_scope"
  ONLYMACS_CURRENT_RETURN_MODEL_ALIAS="$model_alias"
  requested_provider_id="${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}"
  stored_provider_id="$(jq -r '[.steps[]? | select(.provider_id != null) | .provider_id] | last // empty' "$plan_path" 2>/dev/null || true)"
  stored_provider_route_locked="$(jq -r '.execution_settings.route_continuity.provider_route_locked // false' "$plan_path" 2>/dev/null || printf 'false')"
  stored_pinned_provider_id="$(jq -r '.execution_settings.route_continuity.pinned_provider_id // empty' "$plan_path" 2>/dev/null || true)"
  if [[ -n "$requested_provider_id" ]]; then
    ONLYMACS_ORCHESTRATION_PROVIDER_ID="$requested_provider_id"
    ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=1
  elif [[ "$stored_provider_route_locked" == "true" && -n "${stored_pinned_provider_id:-}" ]]; then
    ONLYMACS_ORCHESTRATION_PROVIDER_ID="$stored_pinned_provider_id"
    ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=1
  else
    ONLYMACS_ORCHESTRATION_PROVIDER_ID="$stored_provider_id"
    : "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:=0}"
  fi
  ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="[]"
  ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="[]"
  : "${ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT:=0}"
  ONLYMACS_ORCHESTRATION_FAILURE_STATUS=""
  ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE=""
  artifacts_json="$(find "${run_dir}/files" -maxdepth 1 -type f -print 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')"
  ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON="${artifacts_json:-[]}"
  orchestrated_restore_execution_settings "$plan_path"
  if orchestrated_go_wide_enabled "" && [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" != "1" ]]; then
    ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
    orchestrated_apply_go_wide_resume_provider_avoidance "$plan_path" "$model_alias" "$route_scope"
  fi
  orchestrated_backfill_go_wide_resume_settings "$plan_path" "$model_alias" "$route_scope"

  plan_file_path="$(jq -r '.plan_file_path // empty' "$plan_path")"
  if [[ -n "$plan_file_path" && ! -r "$plan_file_path" ]]; then
    printf 'OnlyMacs cannot resume this plan-file run because the original plan file is no longer readable: %s\n' "$plan_file_path" >&2
    return 1
  fi
  if [[ -n "$plan_file_path" ]]; then
    ONLYMACS_PLAN_FILE_PATH="$plan_file_path"
    ONLYMACS_RESOLVED_PLAN_FILE_PATH="$plan_file_path"
    ONLYMACS_PLAN_FILE_CONTENT="$(cat "$plan_file_path")"
    ONLYMACS_PLAN_FILE_STEP_COUNT="$(printf '%s' "$ONLYMACS_PLAN_FILE_CONTENT" | plan_file_step_count_from_content)"
    ONLYMACS_PLAN_USER_PROMPT="$prompt"
    ONLYMACS_EXECUTION_MODE="extended"
  fi

  local detached_recovery_status=0
  orchestrated_recover_detached_batch_from_activity "$run_dir" || detached_recovery_status=$?
  if [[ "$detached_recovery_status" -eq 2 ]]; then
    return 1
  fi

  model="$(normalize_model_alias "$model_alias")"
  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    printf 'OnlyMacs resuming %s from step %s/%s.\n' "$run_dir" "$resume_index" "$step_count"
  fi

  if [[ -z "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" ]] && orchestrated_go_wide_enabled "$model_alias"; then
    local go_wide_ticket_status=0
    orchestrated_execute_go_wide_ticket_board "$run_dir" "$model" "$model_alias" "$route_scope" "$prompt" "$resume_index" "$step_count" || go_wide_ticket_status=$?
    case "$go_wide_ticket_status" in
      0)
        orchestrated_finalize_status "completed" "$prompt" "$model_alias" "$route_scope"
        return 0
        ;;
      2)
        ;;
      3)
        return 0
        ;;
      *)
        orchestrated_finalize_status "${ONLYMACS_ORCHESTRATION_FAILURE_STATUS:-failed}" "$prompt" "$model_alias" "$route_scope"
        return 1
        ;;
    esac
  fi

  for ((idx = resume_index; idx <= step_count; idx++)); do
    if orchestrated_step_is_local_assembly "$prompt" "$idx"; then
      if ! orchestrated_execute_local_assembly_step "$prompt" "$idx" "$step_count"; then
        orchestrated_finalize_status "${ONLYMACS_ORCHESTRATION_FAILURE_STATUS:-failed}" "$prompt" "$model_alias" "$route_scope"
        return 1
      fi
      continue
    fi
    if ! orchestrated_execute_step "$model" "$model_alias" "$route_scope" "$prompt" "$idx" "$step_count"; then
      if [[ -n "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" ]]; then
        return 1
      fi
      orchestrated_finalize_status "${ONLYMACS_ORCHESTRATION_FAILURE_STATUS:-failed}" "$prompt" "$model_alias" "$route_scope"
      return 1
    fi
    if [[ -n "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" ]]; then
      [[ "${ONLYMACS_GO_WIDE_WORKER_COMPLETED:-0}" == "1" ]] && return 0
      return 1
    fi
  done

  orchestrated_finalize_status "completed" "$prompt" "$model_alias" "$route_scope"
}

run_diagnostics() {
  local ref="${1:-latest}"
  local run_dir events_path status_path plan_path summary_json total_events last_event capacity_waits bridge_waits validation_failures repairs retries reroutes completed_events stopped_events
  local status_value progress_line provider_name model artifacts_json

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  events_path="${run_dir}/events.jsonl"
  status_path="${run_dir}/status.json"
  plan_path="${run_dir}/plan.json"

  if [[ -f "$events_path" ]]; then
    total_events="$(jq -s 'length' "$events_path" 2>/dev/null || printf '0')"
    last_event="$(jq -s -c 'last // {}' "$events_path" 2>/dev/null || printf '{}')"
    capacity_waits="$(jq -s '[.[] | select(.event == "capacity_wait")] | length' "$events_path" 2>/dev/null || printf '0')"
    bridge_waits="$(jq -s '[.[] | select(.event == "bridge_wait" or .event == "bridge_unavailable")] | length' "$events_path" 2>/dev/null || printf '0')"
    validation_failures="$(jq -s '[.[] | select(.event == "validation_failed")] | length' "$events_path" 2>/dev/null || printf '0')"
    repairs="$(jq -s '[.[] | select(.event == "repair_started")] | length' "$events_path" 2>/dev/null || printf '0')"
    retries="$(jq -s '[.[] | select(.event == "retry_started")] | length' "$events_path" 2>/dev/null || printf '0')"
    reroutes="$(jq -s '[.[] | select(.event == "reroute_started")] | length' "$events_path" 2>/dev/null || printf '0')"
    completed_events="$(jq -s '[.[] | select(.event == "run_completed" or .event == "chat_completed")] | length' "$events_path" 2>/dev/null || printf '0')"
    stopped_events="$(jq -s '[.[] | select(.event == "run_stopped")] | length' "$events_path" 2>/dev/null || printf '0')"
  else
    total_events=0
    last_event='{}'
    capacity_waits=0
    bridge_waits=0
    validation_failures=0
    repairs=0
    retries=0
    reroutes=0
    completed_events=0
    stopped_events=0
  fi

  if [[ -f "$status_path" ]]; then
    status_value="$(jq -r '.status // "unknown"' "$status_path" 2>/dev/null || printf 'unknown')"
    provider_name="$(jq -r '.provider_name // .owner_member_name // empty' "$status_path" 2>/dev/null || true)"
    model="$(jq -r '.model // empty' "$status_path" 2>/dev/null || true)"
    artifacts_json="$(jq -c '(.artifacts // [(.artifact_path // empty)] | map(select(. != null and . != "")))' "$status_path" 2>/dev/null || printf '[]')"
  else
    status_value="unknown"
    provider_name=""
    model=""
    artifacts_json="[]"
  fi

  if [[ -f "$plan_path" ]]; then
    progress_line="$(jq -r '"step \(.progress.step_index // 0)/\(.progress.steps_total // (.steps | length)) · \(.progress.percent_complete // 0)% · \(.progress.phase // "unknown")"' "$plan_path" 2>/dev/null || printf 'unknown')"
  elif [[ -f "$status_path" ]]; then
    progress_line="$(jq -r '(.progress.phase // .status // "unknown")' "$status_path" 2>/dev/null || printf 'unknown')"
  else
    progress_line="unknown"
  fi

  summary_json="$(jq -n \
    --arg run_dir "$run_dir" \
    --arg status "$status_value" \
    --arg progress "$progress_line" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg events_path "$events_path" \
    --argjson total_events "${total_events:-0}" \
    --argjson capacity_waits "${capacity_waits:-0}" \
    --argjson bridge_waits "${bridge_waits:-0}" \
    --argjson validation_failures "${validation_failures:-0}" \
    --argjson repairs "${repairs:-0}" \
    --argjson retries "${retries:-0}" \
    --argjson reroutes "${reroutes:-0}" \
    --argjson completed_events "${completed_events:-0}" \
    --argjson stopped_events "${stopped_events:-0}" \
    --argjson artifacts "$artifacts_json" \
    --argjson last_event "$last_event" \
    '{
      run_dir: $run_dir,
      status: $status,
      progress: $progress,
      provider_name: ($provider_name | if length > 0 then . else null end),
      model: ($model | if length > 0 then . else null end),
      artifacts: $artifacts,
      events: {
        path: $events_path,
        total: $total_events,
        capacity_waits: $capacity_waits,
        bridge_waits: $bridge_waits,
        validation_failures: $validation_failures,
        repairs: $repairs,
        retries: $retries,
        reroutes: $reroutes,
        completions: $completed_events,
        stops: $stopped_events,
        last: $last_event
      }
    }')"

  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    printf '%s\n' "$summary_json"
    return 0
  fi

  printf 'OnlyMacs Diagnostics\n'
  printf 'Run: %s\n' "$run_dir"
  printf 'Status: %s\n' "$status_value"
  printf 'Progress: %s\n' "$progress_line"
  if [[ -n "$provider_name" || -n "$model" ]]; then
    printf 'Provider/model: %s%s%s\n' "$provider_name" "${provider_name:+ / }" "$model"
  fi
  printf 'Events: %s total, %s capacity waits, %s bridge waits, %s validation failures, %s repairs, %s retries, %s reroutes\n' "$total_events" "$capacity_waits" "$bridge_waits" "$validation_failures" "$repairs" "$retries" "$reroutes"
  if [[ "$last_event" != "{}" ]]; then
    printf 'Last event: %s %s %s\n' \
      "$(jq -r '.ts // ""' <<<"$last_event")" \
      "$(jq -r '.event // ""' <<<"$last_event")" \
      "$(jq -r '.message // ""' <<<"$last_event")"
  fi
  if [[ "$(jq -r 'length' <<<"$artifacts_json" 2>/dev/null || printf '0')" -gt 0 ]]; then
    printf 'Saved files:\n'
    jq -r '.[]' <<<"$artifacts_json" | while IFS= read -r artifact; do
      printf '  - %s\n' "$artifact"
    done
  fi
  printf 'Status file: %s\n' "$status_path"
  if [[ -f "$events_path" ]]; then
    printf 'Events file: %s\n' "$events_path"
  fi
}

run_support_bundle() {
  local ref="${1:-latest}"
  local run_dir events_path status_path plan_path health_path bundle_path now events_json status_json plan_summary_json health_json

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  events_path="${run_dir}/events.jsonl"
  status_path="${run_dir}/status.json"
  plan_path="${run_dir}/plan.json"
  health_path="$(onlymacs_provider_health_path)"
  bundle_path="${run_dir}/support-bundle.json"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ -f "$events_path" ]]; then
    events_json="$(jq -s '[.[] | {
      ts,
      event,
      step_id,
      status,
      attempt,
      message,
      provider_id,
      provider_name,
      model,
      progress
    }]' "$events_path" 2>/dev/null || printf '[]')"
  else
    events_json="[]"
  fi
  if [[ -f "$status_path" ]]; then
    status_json="$(jq 'del(.prompt_preview)' "$status_path" 2>/dev/null || printf '{}')"
  else
    status_json="{}"
  fi
  if [[ -f "$plan_path" ]]; then
    plan_summary_json="$(jq '{
      run_id,
      status,
      mode,
      model_alias,
      route_scope,
      created_at,
      updated_at,
      validator_version,
      execution_settings,
      schema_contract,
      timeout_policy,
      resume_step,
      resume_step_index,
      progress,
      steps: [.steps[]? | {
        id,
        title,
        status,
        attempt,
        expected_outputs,
        target_paths,
        provider_id,
        provider_name,
        model,
        validation,
        schema_contract,
        batching
      }]
    }' "$plan_path" 2>/dev/null || printf '{}')"
  else
    plan_summary_json="{}"
  fi
  if [[ -f "$health_path" ]]; then
    health_json="$(jq '.' "$health_path" 2>/dev/null || printf '{}')"
  else
    health_json="{}"
  fi

  jq -n \
    --arg generated_at "$now" \
    --arg run_dir "$run_dir" \
    --arg status_path "$status_path" \
    --arg plan_path "$plan_path" \
    --arg events_path "$events_path" \
    --arg health_path "$health_path" \
    --argjson status "$status_json" \
    --argjson plan "$plan_summary_json" \
    --argjson events "$events_json" \
    --argjson provider_health "$health_json" \
    '{
      generated_at: $generated_at,
      privacy: "OnlyMacs support bundle excludes prompt.txt, raw RESULTS, raw artifacts, and prompt previews.",
      run_dir: $run_dir,
      source_paths: {
        status: $status_path,
        plan: $plan_path,
        events: $events_path,
        provider_health: $health_path
      },
      status: $status,
      plan_summary: $plan,
      events: $events,
      provider_health: $provider_health
    }' >"$bundle_path"

  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    jq -n --arg bundle "$bundle_path" --arg run_dir "$run_dir" '{bundle_path:$bundle,run_dir:$run_dir}'
    return 0
  fi
  printf 'OnlyMacs support bundle created: %s\n' "$bundle_path"
  printf 'It excludes prompt.txt, raw RESULT files, and saved artifacts.\n'
}

onlymacs_report_config_path() {
  printf '%s/reporting.json' "$(onlymacs_state_dir)"
}

onlymacs_report_set_auto_enabled() {
  local enabled="${1:-true}"
  local state_dir config_path tmp_file now enabled_json
  case "$enabled" in
    1|true|TRUE|yes|YES|on|ON)
      enabled_json=true
      ;;
    *)
      enabled_json=false
      ;;
  esac
  state_dir="$(onlymacs_state_dir)"
  config_path="$(onlymacs_report_config_path)"
  tmp_file="$(mktemp)"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$state_dir" || return 1
  jq -n --arg updated_at "$now" --argjson enabled "$enabled_json" \
    '{auto_public_feedback:$enabled, updated_at:$updated_at}' >"$tmp_file"
  mv "$tmp_file" "$config_path"
}

onlymacs_report_auto_enabled() {
  local config_path configured
  case "${ONLYMACS_AUTO_REPORT:-}" in
    0|false|FALSE|no|NO|off|OFF)
      return 1
      ;;
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
  esac
  config_path="$(onlymacs_report_config_path)"
  if [[ -f "$config_path" ]]; then
    configured="$(jq -r 'if has("auto_public_feedback") then .auto_public_feedback else true end' "$config_path" 2>/dev/null || printf 'true')"
    [[ "$configured" == "true" ]]
    return $?
  fi
  return 0
}

onlymacs_report_events_summary_json() {
  local events_path="${1:-}"
  if [[ -f "$events_path" ]]; then
    jq -s '{
      total: length,
      counts: (reduce .[] as $event ({}; .[($event.event // "unknown")] += 1)),
      providers: ([.[]?.provider_name // empty | select(length > 0)] | unique),
      models: ([.[]?.model // empty | select(length > 0)] | unique),
      worker_members: ([.[]? | select(((.provider_id // "") + (.provider_name // "")) | length > 0) | {
        provider_id: (.provider_id // null),
        provider_name: (.provider_name // null),
        member_name: (.provider_name // null),
        model: (.model // null)
      }] | unique_by((.provider_id // "") + "|" + (.provider_name // "") + "|" + (.model // "")))
    }' "$events_path" 2>/dev/null || printf '{}'
  else
    printf '{}'
  fi
}

onlymacs_report_plan_summary_json() {
  local plan_path="${1:-}"
  if [[ -f "$plan_path" ]]; then
    jq '{
      run_id,
      status,
      mode,
      model_alias,
      route_scope,
      created_at,
      updated_at,
      prompt_preview,
      progress,
      steps: {
        completed: ([.steps[]? | select(.status == "completed")] | length),
        total: (.steps | length),
        resume_step: (.resume_step // null),
        resume_step_index: (.resume_step_index // null)
      },
      execution_settings: {
        go_wide: (.execution_settings.go_wide // null),
        route_scope: (.execution_settings.route_scope // null),
        context_policy: (.execution_settings.context_policy // null),
        validator_version: (.execution_settings.validator_version // .validator_version // null)
      }
    }' "$plan_path" 2>/dev/null || printf '{}'
  else
    printf '{}'
  fi
}

onlymacs_report_tickets_json() {
  local plan_path="${1:-}"
  if [[ -f "$plan_path" ]]; then
    jq '[
      .steps[]? as $step
      | ($step.batching.batches // [])[]?
      | {
          id: ((($step.id // "step") + "-ticket-" + ((.index // 0) | tostring))),
          step_id: ($step.id // null),
          index: (.index // null),
          title: ("Batch " + ((.index // 0) | tostring) + (if (.count // 0) > 0 then " · " + ((.count // 0) | tostring) + " item(s)" else "" end)),
          kind: (.ticket_kind // "generate"),
          status: (.status // "pending"),
          filename: (.filename // null),
          target_files: ((.target_files // .target_paths // .metadata.target_paths // []) | if type == "array" then . else [.] end | map(select(. != null and . != ""))),
          validator: (.validator // .metadata.validator // null),
          capability: (.capability // .metadata.capability // .role // null),
          dependencies: ((.dependencies // .metadata.dependencies // []) | if type == "array" then . else [.] end | map(select(. != null and . != ""))),
          lock_group: (.lock_group // .metadata.lock_group // .filename // null),
          context_read_mode: (.context_read_mode // .metadata.context_read_mode // $step.context_read_mode // $step.metadata.context_read_mode // null),
          context_write_mode: (.context_write_mode // .metadata.context_write_mode // $step.context_write_mode // $step.metadata.context_write_mode // null),
          start_item: (.start_item // null),
          end_item: (.end_item // null),
          count: (.count // null),
          provider_id: (.provider_id // null),
          provider_name: (.provider_name // null),
          member_name: (.provider_name // null),
          model: (.model // null),
          lease_id: (.lease_id // null),
          leased_at: (.leased_at // null),
          started_at: (.started_at // null),
          completed_at: (.completed_at // null),
          failed_at: (.failed_at // null),
          updated_at: (.updated_at // null),
          duration_seconds: (.duration_seconds // null),
          wait_seconds: (.wait_seconds // null),
          input_tokens_estimate: (.input_tokens_estimate // null),
          output_bytes: (.output_bytes // null),
          output_tokens_estimate: (.output_tokens_estimate // null),
          message: (.message // .deferred_validation_message // null)
        }
    ][0:200]' "$plan_path" 2>/dev/null || printf '[]'
  else
    printf '[]'
  fi
}

onlymacs_report_status_json() {
  local status_path="${1:-}"
  if [[ -f "$status_path" ]]; then
    jq 'del(.prompt)' "$status_path" 2>/dev/null || printf '{}'
  else
    printf '{}'
  fi
}

onlymacs_report_metrics_json() {
  local status_json="${1:-}"
  local plan_json="${2:-}"
  local events_json="${3:-}"
  [[ -n "$status_json" ]] || status_json="{}"
  [[ -n "$plan_json" ]] || plan_json="{}"
  [[ -n "$events_json" ]] || events_json="{}"
  jq -cn \
    --argjson status "$status_json" \
    --argjson plan "$plan_json" \
    --argjson events "$events_json" \
    '{
      outcome: ($status.status // $plan.status // "unknown"),
      token_accounting: ($status.token_accounting // null),
      progress: ($status.progress // $plan.progress // null),
      steps: ($status.steps // $plan.steps // null),
      artifact_validation: ($status.artifact_validation // null),
      artifacts_count: (($status.artifacts // []) | length),
      failure_class: ($status.failure_class // null),
      failure_message_present: (($status.failure_message // "") | length > 0),
      event_total: ($events.total // 0),
      event_counts: ($events.counts // {})
    }'
}

onlymacs_report_feedback_json() {
  local status_json="${1:-}"
  local plan_json="${2:-}"
  local events_json="${3:-}"
  local summary="${4:-}"
  [[ -n "$status_json" ]] || status_json="{}"
  [[ -n "$plan_json" ]] || plan_json="{}"
  [[ -n "$events_json" ]] || events_json="{}"
  jq -cn \
    --argjson status "$status_json" \
    --argjson plan "$plan_json" \
    --argjson events "$events_json" \
    --arg summary "$summary" \
    '
      def n($v): ($v // 0 | tonumber? // 0);
      def plural($n; $word): "\($n) \($word)" + (if $n == 1 then "" else "s" end);
      ($status.status // $plan.status // "unknown") as $outcome |
      ($status.provider_name // $status.owner_member_name // (($events.providers // [])[0]) // "unknown provider") as $provider |
      ($status.model // (($events.models // [])[0]) // "unknown model") as $model |
      n($events.total) as $event_total |
      n($events.counts.validation_failed) as $validation_failures |
      n($events.counts.repair_started) as $repairs |
      n($events.counts.retry_started) as $retries |
      n($events.counts.reroute_started) as $reroutes |
      n($events.counts.capacity_wait) as $capacity_waits |
      (n($events.counts.bridge_wait) + n($events.counts.bridge_unavailable)) as $bridge_waits |
      ([
        if $validation_failures > 0 then plural($validation_failures; "validation failure") else empty end,
        if $repairs > 0 then plural($repairs; "repair") else empty end,
        if $retries > 0 then plural($retries; "retry") else empty end,
        if $reroutes > 0 then plural($reroutes; "reroute") else empty end,
        if $capacity_waits > 0 then plural($capacity_waits; "capacity wait") else empty end,
        if $bridge_waits > 0 then plural($bridge_waits; "bridge wait") else empty end
      ]) as $breakdowns |
      {
        what_worked: (if ($outcome | test("completed|success|ok"; "i")) then
          "Run completed on \($provider) using \($model); OnlyMacs captured \($event_total) orchestration event(s)."
        else
          "OnlyMacs captured the run status, provider/model metadata, and \($event_total) orchestration event(s) for post-run inspection."
        end),
        what_broke: (if ($breakdowns | length) > 0 then $breakdowns | join("; ") else "No major breakage was reported by automatic counters." end),
        quality_notes: "\($validation_failures) validation failure(s), \($repairs) repair(s), \($retries) retry attempt(s), \($reroutes) reroute(s).",
        throughput_notes: "\($event_total) total event(s), \($capacity_waits) capacity wait(s), and \($bridge_waits) bridge wait/unavailable event(s).",
        upstream_model_issues: (if $validation_failures > 0 then
          "Potential model-output issue: validation failed \($validation_failures) time(s). Inspect report artifacts locally if quality matters."
        else
          "No upstream model issue was explicitly reported."
        end),
        downstream_validation_or_repair_issues: (if ($validation_failures + $repairs) > 0 then
          "Downstream validation/repair engaged: \($validation_failures) validation failure(s), \($repairs) repair(s)."
        else
          "No downstream validation or repair issue was reported."
        end),
        resume_restart_issues: ($status.resume_command // $status.next_step // "No resume/restart issue was reported."),
        suggested_improvements: (if ($capacity_waits + $bridge_waits + $retries + $reroutes) > 0 then
          "Review capacity, ticket distribution, transport stability, and model/provider fallback behavior for this run."
        else
          "No immediate coordinator improvement was suggested by the automatic report."
        end)
      }
    '
}

onlymacs_report_summary_line() {
  local status_json="${1:-}"
  local plan_json="${2:-}"
  local events_json="${3:-}"
  [[ -n "$status_json" ]] || status_json="{}"
  [[ -n "$plan_json" ]] || plan_json="{}"
  [[ -n "$events_json" ]] || events_json="{}"
  jq -rn \
    --argjson status "$status_json" \
    --argjson plan "$plan_json" \
    --argjson events "$events_json" \
    '
      ($status.status // $plan.status // "unknown") as $outcome |
      ($status.provider_name // $status.owner_member_name // (($events.providers // [])[0]) // "unknown provider") as $provider |
      ($status.model // (($events.models // [])[0]) // "unknown model") as $model |
      (($status.steps.completed // $plan.steps.completed // null) | tostring) as $completed |
      (($status.steps.total // $plan.steps.total // null) | tostring) as $total |
      "Outcome: \($outcome); provider/model: \($provider) / \($model)" +
      (if $completed != "null" and $total != "null" then "; steps: \($completed)/\($total)" else "" end) +
      "; events: \(($events.total // 0))"
    '
}

onlymacs_report_invocation_label() {
  local automatic="${1:-false}"
  local label
  if [[ "$automatic" == "true" || "$automatic" == "1" ]]; then
    label="${ONLYMACS_ACTIVITY_LABEL:-run}"
    printf '%s %s [prompt redacted]' "${ONLYMACS_WRAPPER_NAME:-onlymacs}" "$label"
    return 0
  fi
  printf '%s' "${ONLYMACS_INVOCATION_LABEL:-}"
}

onlymacs_generate_report_markdown() {
  local run_dir="${1:-}"
  local status_json="${2:-}"
  local plan_json="${3:-}"
  local events_json="${4:-}"
  local automatic="${5:-false}"
  local summary outcome provider model route_scope event_total validation_failures repairs retries reroutes capacity_waits bridge_waits invocation_label feedback_json run_label resume_line
  [[ -n "$status_json" ]] || status_json="{}"
  [[ -n "$plan_json" ]] || plan_json="{}"
  [[ -n "$events_json" ]] || events_json="{}"
  summary="$(onlymacs_report_summary_line "$status_json" "$plan_json" "$events_json")"
  feedback_json="$(onlymacs_report_feedback_json "$status_json" "$plan_json" "$events_json" "$summary")"
  outcome="$(jq -r '.status // "unknown"' <<<"$status_json" 2>/dev/null || printf 'unknown')"
  provider="$(jq -r '.provider_name // .owner_member_name // empty' <<<"$status_json" 2>/dev/null || true)"
  model="$(jq -r '.model // empty' <<<"$status_json" 2>/dev/null || true)"
  route_scope="$(jq -r '.route_scope // empty' <<<"$status_json" 2>/dev/null || true)"
  event_total="$(jq -r '.total // 0' <<<"$events_json" 2>/dev/null || printf '0')"
  validation_failures="$(jq -r '.counts.validation_failed // 0' <<<"$events_json" 2>/dev/null || printf '0')"
  repairs="$(jq -r '.counts.repair_started // 0' <<<"$events_json" 2>/dev/null || printf '0')"
  retries="$(jq -r '.counts.retry_started // 0' <<<"$events_json" 2>/dev/null || printf '0')"
  reroutes="$(jq -r '.counts.reroute_started // 0' <<<"$events_json" 2>/dev/null || printf '0')"
  capacity_waits="$(jq -r '.counts.capacity_wait // 0' <<<"$events_json" 2>/dev/null || printf '0')"
  bridge_waits="$(jq -r '(.counts.bridge_wait // 0) + (.counts.bridge_unavailable // 0)' <<<"$events_json" 2>/dev/null || printf '0')"
  invocation_label="$(onlymacs_report_invocation_label "$automatic")"
  if [[ "$automatic" == "true" || "$automatic" == "1" ]]; then
    run_label="$(basename "$run_dir")"
    if jq -e '(.resume_command // .next_step // "") | length > 0' <<<"$status_json" >/dev/null 2>&1; then
      resume_line="Resume or restart guidance is saved locally in the inbox status."
    else
      resume_line="not needed or not reported"
    fi
    feedback_json="$(jq -c '.resume_restart_issues = "Resume or restart guidance is saved locally in the inbox status when needed."' <<<"$feedback_json")"
  else
    run_label="$run_dir"
    resume_line="$(jq -r '.resume_command // .next_step // "not needed or not reported"' <<<"$status_json" 2>/dev/null || printf 'not reported')"
  fi

  printf '# OnlyMacs Public Swarm Feedback\n\n'
  printf -- '- Summary: %s\n' "$summary"
  printf -- '- Invocation: %s\n' "${invocation_label:-unknown}"
  printf -- '- Run: %s\n' "$run_label"
  printf -- '- Outcome: %s\n' "$outcome"
  printf -- '- Route/provider/model: %s / %s / %s\n' "${route_scope:-unknown}" "${provider:-unknown}" "${model:-unknown}"
  printf -- '- Throughput and downtime signals: %s events, %s capacity waits, %s bridge waits.\n' "$event_total" "$capacity_waits" "$bridge_waits"
  printf -- '- Quality control signals: %s validation failures, %s repairs, %s retries, %s reroutes.\n' "$validation_failures" "$repairs" "$retries" "$reroutes"
  printf -- '- Upstream issues: inferred from OnlyMacs event counts and provider metadata; no raw artifacts or full prompts are included.\n'
  printf -- '- Downstream issues: local handoff should inspect saved artifacts before applying them.\n'
  printf -- '- Resume/restart: %s\n' "$resume_line"
  printf '\n## what_worked\n%s\n' "$(jq -r '.what_worked // "Not reported."' <<<"$feedback_json")"
  printf '\n## what_broke\n%s\n' "$(jq -r '.what_broke // "Not reported."' <<<"$feedback_json")"
  printf '\n## quality_notes\n%s\n' "$(jq -r '.quality_notes // "Not reported."' <<<"$feedback_json")"
  printf '\n## throughput_notes\n%s\n' "$(jq -r '.throughput_notes // "Not reported."' <<<"$feedback_json")"
  printf '\n## upstream_model_issues\n%s\n' "$(jq -r '.upstream_model_issues // "Not reported."' <<<"$feedback_json")"
  printf '\n## downstream_validation_or_repair_issues\n%s\n' "$(jq -r '.downstream_validation_or_repair_issues // "Not reported."' <<<"$feedback_json")"
  printf '\n## resume_restart_issues\n%s\n' "$(jq -r '.resume_restart_issues // "Not reported."' <<<"$feedback_json")"
  printf '\n## suggested_improvements\n%s\n' "$(jq -r '.suggested_improvements // "Not reported."' <<<"$feedback_json")"
}

onlymacs_run_is_public_reportable() {
  local run_dir="${1:-}"
  local status_path="${run_dir}/status.json"
  local plan_path="${run_dir}/plan.json"
  local swarm_id swarm_visibility route_scope runtime_body active_swarm
  [[ -d "$run_dir" ]] || return 1
  swarm_id="$(jq -r '.swarm_id // empty' "$status_path" 2>/dev/null || true)"
  swarm_visibility="$(jq -r '.swarm_visibility // .visibility // empty' "$status_path" 2>/dev/null || true)"
  route_scope="$(jq -r '.route_scope // empty' "$status_path" 2>/dev/null || true)"
  if [[ -z "$route_scope" && -f "$plan_path" ]]; then
    route_scope="$(jq -r '.route_scope // empty' "$plan_path" 2>/dev/null || true)"
  fi
  if [[ "$swarm_id" == "swarm-public" || "$swarm_visibility" == "public" ]]; then
    return 0
  fi
  [[ -z "$route_scope" || "$route_scope" == "swarm" ]] || return 1
  runtime_body="$(curl -fsS --max-time 2 "${BASE_URL}/admin/v1/runtime" 2>/dev/null || true)"
  active_swarm="$(jq -r '.active_swarm_id // empty' <<<"$runtime_body" 2>/dev/null || true)"
  [[ "$active_swarm" == "swarm-public" ]]
}

onlymacs_build_report_payload() {
  local ref="${1:-latest}"
  local report_markdown="${2:-}"
  local automatic="${3:-false}"
  local run_dir status_path plan_path events_path status_json plan_json tickets_json events_json metrics_json feedback_json summary automatic_json invocation_label

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  status_path="${run_dir}/status.json"
  plan_path="${run_dir}/plan.json"
  events_path="${run_dir}/events.jsonl"
  status_json="$(onlymacs_report_status_json "$status_path")"
  plan_json="$(onlymacs_report_plan_summary_json "$plan_path")"
  tickets_json="$(onlymacs_report_tickets_json "$plan_path")"
  events_json="$(onlymacs_report_events_summary_json "$events_path")"
  metrics_json="$(onlymacs_report_metrics_json "$status_json" "$plan_json" "$events_json")"
  summary="$(onlymacs_report_summary_line "$status_json" "$plan_json" "$events_json")"
  feedback_json="$(onlymacs_report_feedback_json "$status_json" "$plan_json" "$events_json" "$summary")"
  if [[ "$automatic" == "true" || "$automatic" == "1" ]]; then
    automatic_json=true
    tickets_json="$(onlymacs_sanitized_auto_tickets_json "$tickets_json")"
    feedback_json="$(jq -c '.resume_restart_issues = "Resume or restart guidance is saved locally in the inbox status when needed."' <<<"$feedback_json")"
  else
    automatic_json=false
  fi
  invocation_label="$(onlymacs_report_invocation_label "$automatic")"
  if [[ -z "$report_markdown" ]]; then
    report_markdown="$(onlymacs_generate_report_markdown "$run_dir" "$status_json" "$plan_json" "$events_json" "$automatic")"
  fi

  jq -cn \
    --arg run_dir "$run_dir" \
    --arg invocation "$invocation_label" \
    --arg report_markdown "$report_markdown" \
    --arg summary "$summary" \
    --argjson automatic "$automatic_json" \
    --argjson status "$status_json" \
    --argjson plan "$plan_json" \
    --argjson tickets "$tickets_json" \
    --argjson metrics "$metrics_json" \
    --argjson events "$events_json" \
    --argjson feedback "$feedback_json" \
    '{
      run_id: ($status.run_id // $plan.run_id // ($run_dir | split("/")[-1])),
      session_id: ($status.session_id // null),
      swarm_id: ($status.swarm_id // null),
      swarm_name: ($status.swarm_name // null),
      swarm_visibility: ($status.swarm_visibility // null),
      provider_id: ($status.provider_id // null),
      provider_name: ($status.provider_name // null),
      owner_member_name: ($status.owner_member_name // null),
      route_scope: ($status.route_scope // $plan.route_scope // null),
      model_alias: ($status.model_alias // $plan.model_alias // null),
      model: ($status.model // null),
      status: ($status.status // $plan.status // null),
      invocation: ($invocation | if length > 0 then . else null end),
      prompt_preview: (if $automatic then null else ($status.prompt_preview // $plan.prompt_preview // null) end),
      summary: $summary,
      report_markdown: $report_markdown,
      worker_members: ($events.worker_members // []),
      tickets: $tickets,
      metadata: {
        mode: ($plan.mode // null),
        execution_settings: ($plan.execution_settings // null),
        progress: ($status.progress // $plan.progress // null),
        created_at: ($plan.created_at // null),
        updated_at: ($status.updated_at // $plan.updated_at // null)
      },
      what_worked: $feedback.what_worked,
      what_broke: $feedback.what_broke,
      quality_notes: $feedback.quality_notes,
      throughput_notes: $feedback.throughput_notes,
      upstream_model_issues: $feedback.upstream_model_issues,
      downstream_validation_or_repair_issues: $feedback.downstream_validation_or_repair_issues,
      resume_restart_issues: $feedback.resume_restart_issues,
      suggested_improvements: $feedback.suggested_improvements,
      source: "onlymacs-cli",
      automatic: $automatic,
      metrics: $metrics,
      events_summary: $events
    }'
}

onlymacs_sanitized_auto_tickets_json() {
  local tickets_json="${1:-[]}"
  [[ -n "$tickets_json" ]] || tickets_json="[]"
  jq -cn --argjson tickets "$tickets_json" '[
    $tickets[]? | {
      id,
      step_id,
      index,
      title,
      kind,
      status,
      filename,
      validator,
      capability,
      provider_id,
      provider_name,
      member_name,
      model,
      duration_seconds,
      wait_seconds,
      input_tokens_estimate,
      output_bytes,
      output_tokens_estimate,
      message_present: (((.message // "") | length) > 0)
    }
  ]'
}

onlymacs_record_report_submission() {
  local run_dir="${1:-}"
  local response_json="${2:-}"
  local submitted_at="${3:-}"
  local automatic="${4:-false}"
  local marker_path="${5:-}"
  local status_path latest_path report_id coordinator_status automatic_json reporting_json

  [[ -n "$run_dir" && -d "$run_dir" ]] || return 0
  [[ -n "$submitted_at" ]] || submitted_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [[ -z "$response_json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$response_json"; then
    response_json="{}"
  fi
  report_id="$(jq -r '.report.id // .id // empty' <<<"$response_json" 2>/dev/null || true)"
  coordinator_status="$(jq -r '.status // empty' <<<"$response_json" 2>/dev/null || true)"
  if [[ "$automatic" == "true" || "$automatic" == "1" ]]; then
    automatic_json=true
  else
    automatic_json=false
  fi
  reporting_json="$(jq -cn \
    --arg submitted_at "$submitted_at" \
    --arg report_id "$report_id" \
    --arg coordinator_status "$coordinator_status" \
    --arg marker_path "$marker_path" \
    --argjson automatic "$automatic_json" \
    '{
      submitted: true,
      automatic: $automatic,
      submitted_at: $submitted_at,
      report_id: ($report_id | if length > 0 then . else null end),
      coordinator_status: ($coordinator_status | if length > 0 then . else null end),
      marker_path: ($marker_path | if length > 0 then . else null end)
    }')"

  status_path="${run_dir}/status.json"
  if [[ -f "$status_path" ]]; then
    jq --argjson reporting "$reporting_json" \
      '.reporting = $reporting
       | .report_submitted = true
       | .report_submitted_at = $reporting.submitted_at
       | .report_id = $reporting.report_id' "$status_path" >"${status_path}.tmp" \
      && mv "${status_path}.tmp" "$status_path"
  fi

  latest_path="$(dirname "$run_dir")/latest.json"
  if [[ -f "$latest_path" ]]; then
    local latest_inbox
    latest_inbox="$(jq -r '.inbox // empty' "$latest_path" 2>/dev/null || true)"
    if [[ "$latest_inbox" == "$run_dir" ]]; then
      jq --argjson reporting "$reporting_json" \
        '.reporting = $reporting
         | .report_submitted = true
         | .report_submitted_at = $reporting.submitted_at
         | .report_id = $reporting.report_id' "$latest_path" >"${latest_path}.tmp" \
        && mv "${latest_path}.tmp" "$latest_path"
    fi
  fi
}

onlymacs_submit_report() {
  local ref="${1:-latest}"
  local report_markdown="${2:-}"
  local automatic="${3:-false}"
  local quiet="${4:-false}"
  local run_dir marker_path payload submitted_at response_json

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  if [[ "$automatic" == "true" || "$automatic" == "1" ]]; then
    marker_path="${run_dir}/report-submitted.json"
    if [[ -f "$marker_path" ]]; then
      submitted_at="$(jq -r '.submitted_at // empty' "$marker_path" 2>/dev/null || true)"
      response_json="$(jq -c '.response // {}' "$marker_path" 2>/dev/null || printf '{}')"
      onlymacs_record_report_submission "$run_dir" "$response_json" "$submitted_at" "$automatic" "$marker_path"
      return 0
    fi
  fi
  payload="$(onlymacs_build_report_payload "$run_dir" "$report_markdown" "$automatic")" || return 1
  if ! request_json POST "/admin/v1/job-reports" "$payload"; then
    [[ "$quiet" == "true" ]] && return 1
    pretty_error "Could not submit the OnlyMacs report." || true
    return 1
  fi
  if [[ ! "$ONLYMACS_LAST_HTTP_STATUS" =~ ^2 ]]; then
    [[ "$quiet" == "true" ]] && return 1
    pretty_error "Could not submit the OnlyMacs report." || true
    return 1
  fi

  submitted_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if jq -e . >/dev/null 2>&1 <<<"$ONLYMACS_LAST_HTTP_BODY"; then
    response_json="$ONLYMACS_LAST_HTTP_BODY"
  else
    response_json="{}"
  fi
  if [[ -n "${marker_path:-}" ]]; then
    jq -n --arg submitted_at "$submitted_at" --arg run_dir "$run_dir" --argjson response "$response_json" \
      '{submitted_at:$submitted_at, run_dir:$run_dir, response:$response}' >"$marker_path" 2>/dev/null || true
  fi
  onlymacs_record_report_submission "$run_dir" "$response_json" "$submitted_at" "$automatic" "${marker_path:-}"
  if [[ "$quiet" != "true" && "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    printf 'OnlyMacs report submitted: %s\n' "$(jq -r '.report.id // "recorded"' <<<"$ONLYMACS_LAST_HTTP_BODY" 2>/dev/null || printf 'recorded')"
  elif [[ "$quiet" != "true" ]]; then
    printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
  fi
}

onlymacs_auto_report_public_run() {
  local run_dir="${1:-${ONLYMACS_CURRENT_RETURN_DIR:-}}"
  [[ -n "$run_dir" && -d "$run_dir" ]] || return 0
  [[ "${ONLYMACS_REPORT_AUTO_SUBMITTING:-0}" != "1" ]] || return 0
  onlymacs_report_auto_enabled || return 0
  onlymacs_run_is_public_reportable "$run_dir" || return 0
  local previous="${ONLYMACS_REPORT_AUTO_SUBMITTING:-}"
  ONLYMACS_REPORT_AUTO_SUBMITTING=1
  onlymacs_submit_report "$run_dir" "" "true" "true" || true
  if [[ -n "$previous" ]]; then
    ONLYMACS_REPORT_AUTO_SUBMITTING="$previous"
  else
    unset ONLYMACS_REPORT_AUTO_SUBMITTING
  fi
}

run_report() {
  local ref="${1:-latest}"
  local report_markdown="" report_file="" automatic=false quiet=false

  case "$ref" in
    status)
      if onlymacs_report_auto_enabled; then
        printf 'OnlyMacs public swarm auto-feedback: enabled\n'
      else
        printf 'OnlyMacs public swarm auto-feedback: disabled\n'
      fi
      printf 'Config: %s\n' "$(onlymacs_report_config_path)"
      return 0
      ;;
    enable|--enable-auto)
      onlymacs_report_set_auto_enabled true
      printf 'OnlyMacs public swarm auto-feedback enabled.\n'
      return 0
      ;;
    disable|--disable-auto)
      onlymacs_report_set_auto_enabled false
      printf 'OnlyMacs public swarm auto-feedback disabled.\n'
      return 0
      ;;
  esac

  if [[ "$ref" == --* ]]; then
    ref="latest"
  else
    shift || true
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --report=*)
        report_markdown="${1#--report=}"
        shift
        ;;
      --report)
        report_markdown="${2:-}"
        shift 2
        ;;
      --report-file=*)
        report_file="${1#--report-file=}"
        shift
        ;;
      --report-file)
        report_file="${2:-}"
        shift 2
        ;;
      --auto)
        automatic=true
        shift
        ;;
      --quiet)
        quiet=true
        shift
        ;;
      --disable-auto)
        onlymacs_report_set_auto_enabled false
        printf 'OnlyMacs public swarm auto-feedback disabled.\n'
        return 0
        ;;
      --enable-auto)
        onlymacs_report_set_auto_enabled true
        printf 'OnlyMacs public swarm auto-feedback enabled.\n'
        return 0
        ;;
      *)
        if [[ -z "$report_markdown" ]]; then
          report_markdown="$1"
          shift
        else
          report_markdown="${report_markdown} $1"
          shift
        fi
        ;;
    esac
  done
  if [[ -n "$report_file" ]]; then
    if [[ ! -r "$report_file" ]]; then
      printf 'OnlyMacs could not read report file: %s\n' "$report_file" >&2
      return 1
    fi
    report_markdown="$(<"$report_file")"
  fi

  onlymacs_submit_report "$ref" "$report_markdown" "$automatic" "$quiet"
}

run_inbox_summary() {
  local ref="${1:-latest}"
  local run_dir status_path plan_path result_path artifacts_json status_value progress_line provider_name model resume_command

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  status_path="${run_dir}/status.json"
  plan_path="${run_dir}/plan.json"
  result_path="${run_dir}/RESULT.md"
  if [[ -f "$status_path" ]]; then
    status_value="$(jq -r '.status // "unknown"' "$status_path" 2>/dev/null || printf 'unknown')"
    provider_name="$(jq -r '.provider_name // .owner_member_name // empty' "$status_path" 2>/dev/null || true)"
    model="$(jq -r '.model // empty' "$status_path" 2>/dev/null || true)"
    resume_command="$(jq -r '.resume_command // empty' "$status_path" 2>/dev/null || true)"
    artifacts_json="$(jq -c '(.artifacts // [(.artifact_path // empty)] | map(select(. != null and . != "")))' "$status_path" 2>/dev/null || printf '[]')"
  else
    status_value="unknown"
    provider_name=""
    model=""
    resume_command=""
    artifacts_json="$(find "${run_dir}/files" -maxdepth 1 -type f -print 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')"
  fi
  if [[ -f "$plan_path" ]]; then
    progress_line="$(jq -r '"step \(.progress.step_index // 0)/\(.progress.steps_total // (.steps | length)) · \(.progress.percent_complete // 0)% · \(.progress.phase // "unknown")"' "$plan_path" 2>/dev/null || printf 'unknown')"
  else
    progress_line="$status_value"
  fi

  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    jq -n \
      --arg run_dir "$run_dir" \
      --arg status "$status_value" \
      --arg progress "$progress_line" \
      --arg status_path "$status_path" \
      --arg plan_path "$plan_path" \
      --arg result_path "$result_path" \
      --arg provider_name "$provider_name" \
      --arg model "$model" \
      --arg resume_command "$resume_command" \
      --argjson artifacts "$artifacts_json" \
      '{run_dir:$run_dir,status:$status,progress:$progress,status_path:$status_path,plan_path:(if ($plan_path | length) > 0 then $plan_path else null end),result_path:(if ($result_path | length) > 0 then $result_path else null end),provider_name:($provider_name | if length > 0 then . else null end),model:($model | if length > 0 then . else null end),artifacts:$artifacts,resume_command:($resume_command | if length > 0 then . else null end)}'
    return 0
  fi

  printf 'OnlyMacs Inbox\n'
  printf 'Run: %s\n' "$run_dir"
  printf 'Status: %s\n' "$status_value"
  printf 'Progress: %s\n' "$progress_line"
  if [[ -n "$provider_name" || -n "$model" ]]; then
    printf 'Provider/model: %s%s%s\n' "$provider_name" "${provider_name:+ / }" "$model"
  fi
  if [[ "$(jq -r 'length' <<<"$artifacts_json" 2>/dev/null || printf '0')" -gt 0 ]]; then
    printf 'Saved files:\n'
    jq -r '.[]' <<<"$artifacts_json" | while IFS= read -r artifact; do
      printf '  - %s\n' "$artifact"
    done
  else
    printf 'Saved files: none yet\n'
  fi
  [[ -f "$result_path" ]] && printf 'Full remote answer: %s\n' "$result_path"
  [[ -f "$plan_path" ]] && printf 'Plan: %s\n' "$plan_path"
  [[ -f "$status_path" ]] && printf 'Status file: %s\n' "$status_path"
  [[ -n "$resume_command" ]] && printf 'Resume: %s\n' "$resume_command"
}

run_open_inbox() {
  local ref="${1:-latest}"
  local run_dir
  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    jq -n --arg run_dir "$run_dir" '{run_dir:$run_dir, opened:false}'
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    open "$run_dir" >/dev/null 2>&1 || true
  fi
  printf 'Opened inbox: %s\n' "$run_dir"
}

run_apply_inbox() {
  local ref="${1:-latest}"
  local target_dir="$PWD"
  local dry_run=1
  local run_dir status_path targets_json artifact target target_path kind duplicate_targets conflict_count copied_count patch_count validation_log
  if [[ "$ref" == "--dry-run" ]]; then
    dry_run=1
    ref="${2:-latest}"
  fi
  if [[ "${2:-}" == "--dry-run" ]]; then
    dry_run=1
  fi
  if [[ "$ONLYMACS_ASSUME_YES" -eq 1 ]]; then
    dry_run=0
  fi

  run_dir="$(orchestrated_resolve_run_dir "$ref")" || return 1
  status_path="${run_dir}/status.json"
  if [[ -f "$status_path" ]]; then
    targets_json="$(jq -c '
      if (.artifact_targets // [] | length) > 0 then
        .artifact_targets
      else
        (.artifacts // [(.artifact_path // empty)] | map(select(. != null and . != "")) | map({
          path: .,
          target_path: (. | split("/")[-1]),
          kind: (if test("\\.(patch|diff)$") then "patch" else "file" end)
        }))
      end
    ' "$status_path" 2>/dev/null || printf '[]')"
  else
    targets_json="$(find "${run_dir}/files" -maxdepth 1 -type f -print 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0) | {path: ., target_path: (. | split("/")[-1]), kind: (if test("\\.(patch|diff)$") then "patch" else "file" end)})')"
  fi
  if [[ "$(jq -r 'length' <<<"$targets_json" 2>/dev/null || printf '0')" -eq 0 ]]; then
    printf 'OnlyMacs found no saved artifacts to apply in %s.\n' "$run_dir" >&2
    return 1
  fi
  duplicate_targets="$(jq -r '[.[].target_path // empty | select(length > 0)] | group_by(.)[]? | select(length > 1) | .[0]' <<<"$targets_json" 2>/dev/null || true)"
  if [[ -n "$duplicate_targets" ]]; then
    printf 'OnlyMacs found duplicate target paths in this inbox run and will not apply automatically:\n%s\n' "$duplicate_targets" >&2
    return 1
  fi

  conflict_count=0
  copied_count=0
  patch_count=0
  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    if [[ "$dry_run" -eq 1 ]]; then
      printf 'OnlyMacs apply preview for %s\n' "$run_dir"
    else
      printf 'OnlyMacs applying artifacts from %s\n' "$run_dir"
    fi
  fi
  while IFS=$'\t' read -r artifact target_path kind; do
    [[ -f "$artifact" ]] || continue
    target_path="$(safe_artifact_target_path "$target_path" "$artifact")"
    target="${target_dir}/${target_path}"
    if [[ "$kind" != "patch" && "$artifact" == *.json ]] && artifact_is_bundle_json "$artifact"; then
      validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-bundle-apply-XXXXXX")"
      if ! validate_artifact_bundle_json "$artifact" >"$validation_log" 2>&1; then
        conflict_count=$((conflict_count + 1))
        printf 'Conflict: invalid artifact bundle %s: %s\n' "$artifact" "$(cat "$validation_log")" >&2
        rm -f "$validation_log"
        continue
      fi
      rm -f "$validation_log"
      while IFS=$'\t' read -r bundle_target_path content_b64; do
        [[ -n "$bundle_target_path" && -n "$content_b64" ]] || continue
        target_path="$(safe_artifact_target_path "$bundle_target_path" "$artifact")"
        target="${target_dir}/${target_path}"
        validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-bundle-file-XXXXXX")"
        if ! decode_chat_activity_body "$content_b64" "$validation_log"; then
          conflict_count=$((conflict_count + 1))
          printf 'Conflict: could not decode bundled file for %s\n' "$target_path" >&2
          rm -f "$validation_log"
          continue
        fi
        if [[ -e "$target" ]] && ! cmp -s "$validation_log" "$target"; then
          conflict_count=$((conflict_count + 1))
          printf 'Conflict: %s already exists and differs from bundled file %s\n' "$target" "$artifact" >&2
          rm -f "$validation_log"
          continue
        fi
        if [[ "$dry_run" -eq 1 ]]; then
          printf 'Would apply bundled file: %s -> %s\n' "$artifact" "$target"
        else
          mkdir -p "$(dirname "$target")"
          cp "$validation_log" "$target"
          copied_count=$((copied_count + 1))
          printf 'Applied bundled file: %s\n' "$target"
        fi
        rm -f "$validation_log"
      done < <(jq -r '(.files // [])[]? | [(.path // .target_path // .filename // empty), ((.content // .source // .body // "") | tostring | @base64)] | @tsv' "$artifact" 2>/dev/null)
      while IFS=$'\t' read -r bundle_target_path patch_b64; do
        [[ -n "$bundle_target_path" && -n "$patch_b64" ]] || continue
        target_path="$(safe_artifact_target_path "$bundle_target_path" "$artifact")"
        validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-bundle-patch-XXXXXX")"
        if ! decode_chat_activity_body "$patch_b64" "$validation_log"; then
          conflict_count=$((conflict_count + 1))
          printf 'Conflict: could not decode bundled patch for %s\n' "$target_path" >&2
          rm -f "$validation_log"
          continue
        fi
        if ! patch_file_paths_are_safe "$validation_log"; then
          conflict_count=$((conflict_count + 1))
          printf 'Conflict: bundled patch for %s touches an unsafe path\n' "$target_path" >&2
          rm -f "$validation_log"
          continue
        fi
        if [[ "$dry_run" -eq 1 ]]; then
          if git -C "$target_dir" apply --check "$validation_log" >/dev/null 2>&1; then
            printf 'Would apply bundled patch: %s -> %s\n' "$artifact" "$target_path"
          else
            conflict_count=$((conflict_count + 1))
            printf 'Conflict: bundled patch does not apply cleanly for %s\n' "$target_path" >&2
          fi
        else
          if git -C "$target_dir" apply --check "$validation_log" >/dev/null 2>&1; then
            git -C "$target_dir" apply "$validation_log"
            patch_count=$((patch_count + 1))
            printf 'Applied bundled patch: %s\n' "$target_path"
          else
            conflict_count=$((conflict_count + 1))
            printf 'Conflict: bundled patch does not apply cleanly for %s\n' "$target_path" >&2
          fi
        fi
        rm -f "$validation_log"
      done < <(jq -r '(.patches // [])[]? | [(.path // .target_path // .filename // empty), ((.patch // .content // "") | tostring | @base64)] | @tsv' "$artifact" 2>/dev/null)
      continue
    fi
    if [[ "$kind" == "patch" || "$artifact" == *.patch || "$artifact" == *.diff ]]; then
      if ! patch_file_paths_are_safe "$artifact"; then
        conflict_count=$((conflict_count + 1))
        printf 'Conflict: patch touches an unsafe path: %s\n' "$artifact" >&2
        continue
      fi
      if [[ "$dry_run" -eq 1 ]]; then
        printf 'Would check patch: git apply --check %s\n' "$artifact"
      else
        if git -C "$target_dir" apply --check "$artifact" >/dev/null 2>&1; then
          git -C "$target_dir" apply "$artifact"
          patch_count=$((patch_count + 1))
          printf 'Applied patch: %s\n' "$artifact"
        else
          conflict_count=$((conflict_count + 1))
          printf 'Conflict: patch does not apply cleanly: %s\n' "$artifact" >&2
        fi
      fi
      continue
    fi
    if [[ -e "$target" ]] && ! cmp -s "$artifact" "$target"; then
      conflict_count=$((conflict_count + 1))
      printf 'Conflict: %s already exists and differs from %s\n' "$target" "$artifact" >&2
      continue
    fi
    if [[ "$dry_run" -eq 1 ]]; then
      printf 'Would apply: %s -> %s\n' "$artifact" "$target"
    else
      mkdir -p "$(dirname "$target")"
      cp "$artifact" "$target"
      copied_count=$((copied_count + 1))
      printf 'Applied: %s\n' "$target"
    fi
  done < <(jq -r '.[] | [.path, (.target_path // (.path | split("/")[-1])), (.kind // "file")] | @tsv' <<<"$targets_json")

  if [[ "$conflict_count" -gt 0 ]]; then
    printf 'OnlyMacs did not overwrite conflicting files. Rename, move, or review them manually first.\n' >&2
    return 1
  fi
  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Preview only. Re-run with --yes to copy non-conflicting artifacts into %s.\n' "$target_dir"
  else
    printf 'Applied %s artifact%s and %s patch%s into %s.\n' "$copied_count" "$(chat_plural_suffix "$copied_count")" "$patch_count" "$(chat_plural_suffix "$patch_count")" "$target_dir"
  fi
}
