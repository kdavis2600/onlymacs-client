# Chat run directories, progress status, and run-event helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after artifact validation helpers are loaded.

chat_returns_root() {
  printf '%s' "${ONLYMACS_RETURNS_DIR:-$PWD/onlymacs/inbox}"
}

chat_run_id_from_prompt() {
  local prompt="${1:-}"
  local model_alias="${2:-}"
  printf '%s-%s' \
    "$(date -u +"%Y%m%dT%H%M%SZ")" \
    "$(printf '%s' "$prompt|$model_alias|$$|${RANDOM:-0}" | shasum -a 256 | awk '{print substr($1,1,10)}')"
}

chat_elapsed_seconds() {
  local started_epoch="${ONLYMACS_CURRENT_RETURN_STARTED_EPOCH:-}"
  local now
  if [[ ! "$started_epoch" =~ ^[0-9]+$ ]]; then
    printf '0'
    return 0
  fi
  now="$(date +%s)"
  if [[ ! "$now" =~ ^[0-9]+$ || "$now" -lt "$started_epoch" ]]; then
    printf '0'
    return 0
  fi
  printf '%s' "$((now - started_epoch))"
}

format_chat_elapsed() {
  local elapsed="${1:-0}"
  printf '%02d:%02d' "$((elapsed / 60))" "$((elapsed % 60))"
}

chat_output_bytes() {
  local content_path="${1:-}"
  if [[ -f "$content_path" ]]; then
    wc -c <"$content_path" | tr -d ' '
  else
    printf '0'
  fi
}

chat_estimated_tokens() {
  local bytes="${1:-0}"
  if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
    bytes=0
  fi
  printf '%s' "$(((bytes + 3) / 4))"
}

chat_tokens_per_second() {
  local tokens="${1:-0}"
  local elapsed="${2:-0}"
  if [[ ! "$tokens" =~ ^[0-9]+$ || ! "$elapsed" =~ ^[0-9]+$ || "$elapsed" -le 0 ]]; then
    printf '0.0'
    return 0
  fi
  awk -v tokens="$tokens" -v elapsed="$elapsed" 'BEGIN { printf "%.1f", tokens / elapsed }'
}

chat_progress_phase() {
  local bytes="${1:-0}"
  local status="${2:-running}"
  local reasoning_bytes="${3:-${ONLYMACS_STREAM_REASONING_BYTES:-0}}"
  if [[ "$status" != "running" ]]; then
    printf '%s' "$status"
    return 0
  fi
  if [[ ! "$bytes" =~ ^[0-9]+$ || "$bytes" -le 0 ]]; then
    if [[ "$reasoning_bytes" =~ ^[0-9]+$ && "$reasoning_bytes" -gt 0 ]]; then
      printf 'reasoning_only'
      return 0
    fi
    printf 'first_token_wait'
    return 0
  fi
  printf 'streaming'
}

chat_progress_phase_label() {
  local phase="${1:-streaming}"
  local tps="${2:-0.0}"
  case "$phase" in
    first_token_wait)
      printf 'warming model / waiting for first token'
      ;;
    reasoning_only)
      printf 'reasoning before artifact'
      ;;
    streaming)
      printf '~%s tok/s streaming' "$tps"
      ;;
    *)
      printf '%s' "$phase"
      ;;
  esac
}

chat_progress_phase_detail() {
  local phase="${1:-streaming}"
  case "$phase" in
    first_token_wait)
      printf 'The remote Mac has accepted the request and is warming/loading the selected model or preparing the plan step before the first output token.'
      ;;
    reasoning_only)
      printf 'The remote model is producing reasoning, but no artifact content has been emitted yet.'
      ;;
    streaming)
      printf 'Remote output is streaming.'
      ;;
    *)
      printf '%s' "$phase"
      ;;
  esac
}

chat_plural_suffix() {
  if [[ "${1:-0}" == "1" ]]; then
    printf ''
  else
    printf 's'
  fi
}

chat_progress_bar() {
  local tick="${1:-0}"
  local width=18
  local pos bar i
  if [[ ! "$tick" =~ ^[0-9]+$ ]]; then
    tick=0
  fi
  pos=$((tick % width))
  bar=""
  for ((i = 0; i < width; i++)); do
    if [[ "$i" -lt "$pos" ]]; then
      bar="${bar}="
    elif [[ "$i" -eq "$pos" ]]; then
      bar="${bar}>"
    else
      bar="${bar}."
    fi
  done
  printf '[%s]' "$bar"
}

chat_provider_label() {
  local headers_path="${1:-}"
  local owner provider model
  owner="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
  provider="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
  model="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
  if [[ -n "$owner" ]]; then
    printf '%s' "$owner"
  elif [[ -n "$provider" ]]; then
    printf '%s' "$provider"
  else
    printf 'selected Mac'
  fi
  if [[ -n "$model" ]]; then
    printf ' / %s' "$model"
  fi
}

emit_chat_progress() {
  local content_path="${1:-}"
  local headers_path="${2:-}"
  local heartbeat_count="${3:-0}"
  local tick="${4:-0}"
  local bytes tokens elapsed tps phase phase_label reasoning_bytes

  if [[ "$ONLYMACS_JSON_MODE" -eq 1 || "${ONLYMACS_PROGRESS:-1}" == "0" ]]; then
    return 0
  fi

  bytes="$(chat_output_bytes "$content_path")"
  reasoning_bytes="${ONLYMACS_STREAM_REASONING_BYTES:-0}"
  tokens="$(chat_estimated_tokens "$bytes")"
  elapsed="$(chat_elapsed_seconds)"
  tps="$(chat_tokens_per_second "$tokens" "$elapsed")"
  phase="$(chat_progress_phase "$bytes" "running" "$reasoning_bytes")"
  phase_label="$(chat_progress_phase_label "$phase" "$tps")"
  printf '\nOnlyMacs progress %s %s elapsed | %s | %s | %s heartbeat%s\n' \
    "$(chat_progress_bar "$tick")" \
    "$(format_chat_elapsed "$elapsed")" \
    "$phase_label" \
    "$(chat_provider_label "$headers_path")" \
    "$heartbeat_count" \
    "$(chat_plural_suffix "$heartbeat_count")" >&2
}

write_chat_progress_status() {
  local content_path="${1:-}"
  local headers_path="${2:-}"
  local heartbeat_count="${3:-0}"
  local status="${4:-running}"
  local artifact_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}"
  local status_path latest_path now bytes tokens elapsed tps phase phase_detail model provider_id provider_name owner_member_name session_id route_scope first_token_marker timeout_policy_json reasoning_bytes

  [[ -n "$artifact_dir" ]] || return 0
  mkdir -p "$artifact_dir/files" || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  bytes="$(chat_output_bytes "$content_path")"
  reasoning_bytes="${ONLYMACS_STREAM_REASONING_BYTES:-0}"
  tokens="$(chat_estimated_tokens "$bytes")"
  elapsed="$(chat_elapsed_seconds)"
  tps="$(chat_tokens_per_second "$tokens" "$elapsed")"
  phase="$(chat_progress_phase "$bytes" "$status" "$reasoning_bytes")"
  phase_detail="$(chat_progress_phase_detail "$phase")"
  session_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-session-id")"
  model="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
  provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
  provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
  owner_member_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
  route_scope="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-route-scope")"
  if [[ -z "$route_scope" ]]; then
    route_scope="${ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE:-swarm}"
  fi
  timeout_policy_json="$(onlymacs_timeout_policy_json)"

  status_path="${artifact_dir}/status.json"
  jq -n \
    --arg status "$status" \
    --arg run_id "$(basename "$artifact_dir")" \
    --arg started_at "${ONLYMACS_CURRENT_RETURN_STARTED_AT:-$now}" \
    --arg updated_at "$now" \
    --arg last_progress_at "$now" \
    --arg session_id "$session_id" \
    --arg model "$model" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg owner_member_name "$owner_member_name" \
    --arg route_scope "$route_scope" \
    --arg inbox "$artifact_dir" \
    --arg files_dir "${artifact_dir}/files" \
    --argjson elapsed_seconds "$elapsed" \
    --argjson output_bytes "$bytes" \
    --argjson output_tokens_estimate "$tokens" \
    --argjson reasoning_bytes "${reasoning_bytes:-0}" \
    --arg tokens_per_second "$tps" \
    --arg phase "$phase" \
    --arg phase_detail "$phase_detail" \
    --argjson heartbeat_count "${heartbeat_count:-0}" \
    --argjson timeout_policy "$timeout_policy_json" \
    '{
      status: $status,
      run_id: $run_id,
      started_at: $started_at,
      updated_at: $updated_at,
      last_progress_at: $last_progress_at,
      session_id: ($session_id | if length > 0 then . else null end),
      model: ($model | if length > 0 then . else null end),
      provider_id: ($provider_id | if length > 0 then . else null end),
      provider_name: ($provider_name | if length > 0 then . else null end),
      owner_member_name: ($owner_member_name | if length > 0 then . else null end),
      route_scope: ($route_scope | if length > 0 then . else null end),
      inbox: $inbox,
      files_dir: $files_dir,
      progress: {
        elapsed_seconds: $elapsed_seconds,
        output_bytes: $output_bytes,
        output_tokens_estimate: $output_tokens_estimate,
        reasoning_bytes: $reasoning_bytes,
        tokens_per_second: ($tokens_per_second | tonumber),
        phase: $phase,
        phase_detail: $phase_detail,
        heartbeat_count: $heartbeat_count
      },
      timeout_policy: $timeout_policy
    }' >"$status_path"

  latest_path="$(dirname "$artifact_dir")/latest.json"
  jq -n \
    --arg run_id "$(basename "$artifact_dir")" \
    --arg status "$status" \
    --arg updated_at "$now" \
    --arg inbox "$artifact_dir" \
    --arg status_path "$status_path" \
    '{run_id:$run_id,status:$status,updated_at:$updated_at,inbox:$inbox,status_path:$status_path}' >"$latest_path"
  onlymacs_log_run_event "chat_${status}" "" "$status" "0" "" "" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "" "$status_path"
  if [[ "$status" == "running" ]]; then
    onlymacs_log_run_event "heartbeat" "" "$status" "$heartbeat_count" "$phase_detail" "" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "" "$status_path"
    case "$phase" in
      first_token_wait)
        onlymacs_log_run_event "model_loading" "" "$status" "$heartbeat_count" "$phase_detail" "" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "" "$status_path"
        ;;
      reasoning_only)
        onlymacs_log_run_event "reasoning_only" "" "$status" "$heartbeat_count" "$phase_detail" "" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "" "$status_path"
        ;;
      streaming)
        first_token_marker="${artifact_dir}/.onlymacs-first-token-event"
        if [[ ! -f "$first_token_marker" ]]; then
          : >"$first_token_marker"
          onlymacs_log_run_event "first_token" "" "$status" "$heartbeat_count" "Remote output started streaming." "" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "" "$status_path"
        fi
        onlymacs_log_run_event "tokens_sample" "" "$status" "$heartbeat_count" "~${tps} tok/s, ${tokens} output tokens estimated." "" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "" "$status_path"
        ;;
    esac
  fi
}

write_chat_status_file() {
  local artifact_dir="${1:-}"
  local status="${2:-running}"
  local model_alias="${3:-}"
  local route_scope="${4:-swarm}"
  local prompt="${5:-}"
  local status_path latest_path now timeout_policy_json

  [[ -n "$artifact_dir" ]] || return 0
  mkdir -p "$artifact_dir/files" || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  timeout_policy_json="$(onlymacs_timeout_policy_json)"
  status_path="${artifact_dir}/status.json"
  jq -n \
    --arg status "$status" \
    --arg updated_at "$now" \
    --arg started_at "${ONLYMACS_CURRENT_RETURN_STARTED_AT:-$now}" \
    --arg run_id "$(basename "$artifact_dir")" \
    --arg model_alias "$model_alias" \
    --arg route_scope "$route_scope" \
    --arg prompt_preview "$(printf '%s' "$prompt" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-160)" \
    --arg inbox "$artifact_dir" \
    --arg files_dir "${artifact_dir}/files" \
    --argjson timeout_policy "$timeout_policy_json" \
    '{
      status: $status,
      run_id: $run_id,
      started_at: $started_at,
      updated_at: $updated_at,
      model_alias: ($model_alias | if length > 0 then . else null end),
      route_scope: $route_scope,
      prompt_preview: ($prompt_preview | if length > 0 then . else null end),
      inbox: $inbox,
      files_dir: $files_dir,
      timeout_policy: $timeout_policy
    }' >"$status_path"

  latest_path="$(dirname "$artifact_dir")/latest.json"
  jq -n \
    --arg run_id "$(basename "$artifact_dir")" \
    --arg status "$status" \
    --arg updated_at "$now" \
    --arg inbox "$artifact_dir" \
    --arg status_path "$status_path" \
    '{run_id:$run_id,status:$status,updated_at:$updated_at,inbox:$inbox,status_path:$status_path}' >"$latest_path"
  onlymacs_log_run_event "chat_${status}" "" "$status" "0" "" "" "" "" "" "" "$status_path"
}

prepare_chat_return_run() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local route_scope="${3:-swarm}"
  local returns_root run_id artifact_dir started_at

  returns_root="$(chat_returns_root)"
  run_id="$(chat_run_id_from_prompt "$prompt" "$model_alias")"
  artifact_dir="${returns_root}/${run_id}"
  started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "${artifact_dir}/files" || return 0

  ONLYMACS_CURRENT_RETURN_RUN_ID="$run_id"
  ONLYMACS_CURRENT_RETURN_DIR="$artifact_dir"
  ONLYMACS_CURRENT_RETURN_STARTED_AT="$started_at"
  ONLYMACS_CURRENT_RETURN_STARTED_EPOCH="$(date +%s)"
  ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE="$route_scope"
  ONLYMACS_CURRENT_RETURN_MODEL_ALIAS="$model_alias"
  write_chat_status_file "$artifact_dir" "running" "$model_alias" "$route_scope" "$prompt"
  write_run_file_access_manifest "$artifact_dir"
  onlymacs_log_run_event "run_created" "" "running" "0" "OnlyMacs created an inbox run." "" "" "" "" "" "${artifact_dir}/status.json"

  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    printf 'OnlyMacs started'
    if [[ -n "$model_alias" ]]; then
      printf ' (%s)' "$model_alias"
    fi
    printf '.\nInbox: %s\n\n' "$artifact_dir"
  fi
}

write_run_file_access_manifest() {
  local artifact_dir="${1:-}"
  local manifest_path
  [[ -n "$artifact_dir" && -n "${ONLYMACS_RESOLVED_ARTIFACT_JSON:-}" ]] || return 0
  manifest_path="${artifact_dir}/file-access-manifest.json"
  jq '.manifest // empty' <<<"$ONLYMACS_RESOLVED_ARTIFACT_JSON" >"$manifest_path" 2>/dev/null || rm -f "$manifest_path"
}

onlymacs_run_events_path() {
  [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" ]] || return 1
  printf '%s/events.jsonl' "$ONLYMACS_CURRENT_RETURN_DIR"
}

onlymacs_progress_for_events_json() {
  local plan_path
  plan_path="$(orchestrated_plan_path)"
  if [[ -f "$plan_path" ]]; then
    jq -c '.progress // {}' "$plan_path" 2>/dev/null || printf '{}'
    return 0
  fi
  if [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" && -f "${ONLYMACS_CURRENT_RETURN_DIR}/status.json" ]]; then
    jq -c '.progress // {}' "${ONLYMACS_CURRENT_RETURN_DIR}/status.json" 2>/dev/null || printf '{}'
    return 0
  fi
  printf '{}'
}

onlymacs_event_name_for_step_status() {
  case "${1:-running}" in
    planned)
      printf 'plan_created'
      ;;
    waiting_for_capacity)
      printf 'capacity_wait'
      ;;
    waiting_for_bridge)
      printf 'bridge_unavailable'
      ;;
    running)
      printf 'step_started'
      ;;
    repairing)
      printf 'repair_started'
      ;;
    retrying)
      printf 'retry_started'
      ;;
    rerouting)
      printf 'reroute_started'
      ;;
    assembling)
      printf 'assembly_started'
      ;;
    completed)
      printf 'step_completed'
      ;;
    failed_validation)
      printf 'validation_failed'
      ;;
    churn)
      printf 'repair_churn'
      ;;
    failed|blocked|queued|partial)
      printf 'step_%s' "${1:-failed}"
      ;;
    *)
      printf 'step_update'
      ;;
  esac
}

onlymacs_log_run_event() {
  local event="${1:-event}"
  local step_id="${2:-}"
  local status="${3:-}"
  local attempt="${4:-0}"
  local message="${5:-}"
  local artifact_path="${6:-}"
  local provider_id="${7:-}"
  local provider_name="${8:-}"
  local model="${9:-}"
  local raw_path="${10:-}"
  local status_path="${11:-}"
  local events_path now progress_json

  [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" ]] || return 0
  events_path="$(onlymacs_run_events_path)" || return 0
  mkdir -p "$(dirname "$events_path")" || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  progress_json="$(onlymacs_progress_for_events_json)"

  jq -cn \
    --arg ts "$now" \
    --arg run_id "${ONLYMACS_CURRENT_RETURN_RUN_ID:-$(basename "${ONLYMACS_CURRENT_RETURN_DIR:-}")}" \
    --arg event "$event" \
    --arg step_id "$step_id" \
    --arg status "$status" \
    --argjson attempt "${attempt:-0}" \
    --arg message "$(printf '%s' "$message" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-500)" \
    --arg artifact_path "$artifact_path" \
    --arg raw_result_path "$raw_path" \
    --arg status_path "$status_path" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --argjson progress "$progress_json" \
    '{
      ts: $ts,
      run_id: $run_id,
      event: $event,
      step_id: ($step_id | if length > 0 then . else null end),
      status: ($status | if length > 0 then . else null end),
      attempt: $attempt,
      message: ($message | if length > 0 then . else null end),
      artifact_path: ($artifact_path | if length > 0 then . else null end),
      raw_result_path: ($raw_result_path | if length > 0 then . else null end),
      status_path: ($status_path | if length > 0 then . else null end),
      provider_id: ($provider_id | if length > 0 then . else null end),
      provider_name: ($provider_name | if length > 0 then . else null end),
      model: ($model | if length > 0 then . else null end),
      progress: $progress
    }' >>"$events_path" 2>/dev/null || true
}
