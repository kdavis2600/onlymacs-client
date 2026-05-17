# Direct chat return handling, relay recovery, and context-loop helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after run command helpers are loaded.

write_chat_failure_artifact() {
  local content_path="${1:-}"
  local headers_path="${2:-}"
  local model_alias="${3:-}"
  local prompt="${4:-}"
  local route_scope="${5:-swarm}"
  local failure_message="${6:-${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-${ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE:-}}}"
  local next_step="${7:-Run onlymacs status latest or retry the request. If partial_result_path is present, review it before retrying.}"
  local artifact_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}"
  local partial_path status_path now failure_status http_status failure_kind

  [[ -n "$artifact_dir" ]] || return 0
  mkdir -p "$artifact_dir" || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  status_path="${artifact_dir}/status.json"
  if [[ -s "$content_path" ]]; then
    partial_path="${artifact_dir}/RESULT.partial.md"
    cp "$content_path" "$partial_path"
  else
    partial_path=""
  fi
  if [[ -n "$partial_path" ]]; then
    failure_status="partial"
  else
    failure_status="failed"
  fi
  http_status="${ONLYMACS_LAST_CHAT_HTTP_STATUS:-$(onlymacs_chat_http_status "$headers_path")}"
  failure_kind="${ONLYMACS_LAST_CHAT_FAILURE_KIND:-${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}}"
  write_chat_progress_status "$content_path" "$headers_path" 0 "$failure_status"
  jq --arg failed_at "$now" \
    --arg partial_path "$partial_path" \
    --arg failure_status "$failure_status" \
    --arg model_alias "$model_alias" \
    --arg route_scope "$route_scope" \
    --arg http_status "$http_status" \
    --arg failure_kind "$failure_kind" \
    --arg failure_message "$failure_message" \
    --arg next_step "$next_step" \
    --arg prompt_preview "$(printf '%s' "$prompt" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-160)" \
    '. + {
      status: $failure_status,
      failed_at: $failed_at,
      partial: ($partial_path | length > 0),
      model_alias: ($model_alias | if length > 0 then . else null end),
      route_scope: $route_scope,
      prompt_preview: ($prompt_preview | if length > 0 then . else null end),
      partial_result_path: ($partial_path | if length > 0 then . else null end),
      failure: {
        http_status: ($http_status | if length > 0 then . else null end),
        kind: ($failure_kind | if length > 0 then . else null end),
        message: ($failure_message | if length > 0 then . else null end)
      },
      failure_message: ($failure_message | if length > 0 then . else null end),
      next_step: $next_step
    }' "$status_path" >"${status_path}.tmp" && mv "${status_path}.tmp" "$status_path"
  onlymacs_auto_report_public_run "$artifact_dir"
}

chat_failure_safe_for_stream_retry() {
  local content_path="${1:-}"
  local http_status="${2:-}"
  [[ ! -s "$content_path" ]] || return 1
  case "$http_status" in
    400|401|403|404|409)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

direct_chat_failure_message() {
  local model_alias="${1:-}"
  local route_scope="${2:-swarm}"
  local http_status="${3:-}"
  local transport_message="${4:-}"

  case "$http_status" in
    2??)
      if [[ -n "$transport_message" ]]; then
        printf 'OnlyMacs remote chat completed but did not return usable output: %s.' "$transport_message"
      else
        printf 'OnlyMacs remote chat completed but did not return usable output.'
      fi
      ;;
    409)
      if [[ "$route_scope" == "swarm" ]]; then
        printf 'OnlyMacs could not start this remote-first request because no eligible remote Mac is currently available. The swarm may be empty, busy, or missing a Mac with the requested model.'
      else
        printf 'OnlyMacs could not start this request because the selected route has no eligible capacity right now.'
      fi
      ;;
    502|503|504)
      printf 'OnlyMacs could not keep the remote relay open (HTTP %s). This is usually a transient coordinator or provider handoff issue.' "$http_status"
      ;;
    "")
      if [[ -n "$transport_message" ]]; then
        printf 'OnlyMacs could not reach the local bridge or remote relay: %s.' "$transport_message"
      else
        printf 'OnlyMacs could not reach the local bridge or remote relay.'
      fi
      ;;
    *)
      if [[ -n "$transport_message" ]]; then
        printf 'OnlyMacs remote chat failed: %s.' "$transport_message"
      else
        printf 'OnlyMacs remote chat failed with HTTP %s.' "$http_status"
      fi
      ;;
  esac
}

direct_chat_failure_next_step() {
  local model_alias="${1:-}"
  local route_scope="${2:-swarm}"
  local http_status="${3:-}"

  case "$http_status" in
    2??)
      printf 'Retry with a larger max token budget or a different model. If this repeats, use diagnostics on the inbox so the empty-output stream is visible.'
      ;;
    409)
      if [[ "$route_scope" == "swarm" ]]; then
        printf 'Wait until another Mac is visible with an open slot, then retry. For immediate local work, run the same prompt with onlymacs chat local-first.'
      else
        printf 'Retry after capacity frees up, or choose a route with an available provider.'
      fi
      ;;
    502|503|504)
      printf 'Retry the request; if you need the result immediately, use onlymacs chat local-first with the same prompt.'
      ;;
    *)
      printf 'Run onlymacs status latest to inspect the checkpoint, then retry the request when the bridge and coordinator are healthy.'
      ;;
  esac
}

print_direct_chat_failure() {
  local message="${1:-}"
  local next_step="${2:-}"
  local artifact_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}"
  local status_path=""

  [[ "$ONLYMACS_JSON_MODE" -ne 1 ]] || return 0
  if [[ -n "$artifact_dir" ]]; then
    status_path="${artifact_dir}/status.json"
  fi
  printf '\n%s\n' "$message" >&2
  if [[ -n "$artifact_dir" ]]; then
    printf 'Inbox: %s\n' "$artifact_dir" >&2
  fi
  if [[ -n "$status_path" ]]; then
    printf 'Status: %s\n' "$status_path" >&2
  fi
  printf 'Next: %s\n' "$next_step" >&2
}

decode_chat_activity_body() {
  local encoded="${1:-}"
  local out_path="${2:-}"
  [[ -n "$encoded" && -n "$out_path" ]] || return 1
  if printf '%s' "$encoded" | base64 --decode >"$out_path" 2>/dev/null; then
    return 0
  fi
  printf '%s' "$encoded" | base64 -D >"$out_path" 2>/dev/null
}

extract_chat_content_from_raw_body() {
  local raw_path="${1:-}"
  local out_path="${2:-}"
  local line json content
  [[ -s "$raw_path" && -n "$out_path" ]] || return 1
  : >"$out_path"

  if rg -q '^data:' "$raw_path" 2>/dev/null; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" != data:\ * ]]; then
        continue
      fi
      json="${line#data: }"
      if [[ "$json" == "[DONE]" ]]; then
        continue
      fi
      content="$(jq -rj '.choices[]?.delta.content // empty, .choices[]?.message.content // empty' <<<"$json" 2>/dev/null || true)"
      if [[ -n "$content" ]]; then
        printf '%s' "$content" >>"$out_path"
      fi
    done <"$raw_path"
    [[ -s "$out_path" ]]
    return
  fi

  if jq -rj '.choices[]?.delta.content // empty, .choices[]?.message.content // empty' "$raw_path" >"$out_path" 2>/dev/null && [[ -s "$out_path" ]]; then
    return 0
  fi
  if jq -e '.error?' "$raw_path" >/dev/null 2>&1; then
    return 1
  fi
  cp "$raw_path" "$out_path"
  [[ -s "$out_path" ]]
}

recover_chat_content_from_activity_body() {
  local final_body_base64="${1:-}"
  local content_path="${2:-}"
  local raw_path extracted_path
  [[ -n "$final_body_base64" && -n "$content_path" ]] || return 1
  raw_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-activity-body-XXXXXX")"
  extracted_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-activity-content-XXXXXX")"
  if decode_chat_activity_body "$final_body_base64" "$raw_path" && extract_chat_content_from_raw_body "$raw_path" "$extracted_path"; then
    cp "$extracted_path" "$content_path"
    rm -f "$raw_path" "$extracted_path"
    return 0
  fi
  rm -f "$raw_path" "$extracted_path"
  return 1
}

recover_chat_from_relay_activity() {
  local content_path="${1:-}"
  local headers_path="${2:-}"
  local model_alias="${3:-}"
  local prompt="${4:-}"
  local route_scope="${5:-swarm}"
  local session_id activity_status output_preview final_body_base64 partial

  session_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-session-id")"
  [[ -n "$session_id" ]] || return 1
  request_json GET "/admin/v1/relay/activity?session_id=${session_id}" || return 1
  require_success "OnlyMacs could not recover the remote relay activity." || return 1

  activity_status="$(jq -r '.activities[0].status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  output_preview="$(jq -r '.activities[0].output_preview // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  final_body_base64="$(jq -r '.activities[0].final_body_base64 // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  partial="$(jq -r '.activities[0].partial // false' <<<"$ONLYMACS_LAST_HTTP_BODY")"

  if [[ -n "$final_body_base64" && ( "$activity_status" == "completed" || ! -s "$content_path" ) ]]; then
    recover_chat_content_from_activity_body "$final_body_base64" "$content_path" || true
  fi
  if [[ ! -s "$content_path" && -n "$output_preview" ]]; then
    printf '%s\n' "$output_preview" >"$content_path"
  fi

  case "$activity_status" in
    completed)
      if [[ -s "$content_path" ]]; then
        write_chat_return_artifact "$content_path" "$headers_path" "$model_alias" "$prompt"
        return 0
      fi
      ;;
    failed|cancelled)
      if [[ "$partial" == "true" || -s "$content_path" ]]; then
        write_chat_failure_artifact "$content_path" "$headers_path" "$model_alias" "$prompt" "$route_scope"
      fi
      ;;
  esac
  return 1
}

orchestrated_fetch_provider_activity_direct() {
  local provider_id="${1:-}"
  local limit="${2:-8}"
  local runtime_body swarm_id coordinator_url
  [[ -n "$provider_id" ]] || return 1
  [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || limit=8
  runtime_body="$(curl -fsS --max-time 2 "${BASE_URL}/admin/v1/runtime" 2>/dev/null || true)"
  swarm_id="$(jq -r '.active_swarm_id // "swarm-public"' <<<"$runtime_body" 2>/dev/null || printf 'swarm-public')"
  [[ -n "$swarm_id" && "$swarm_id" != "null" ]] || swarm_id="swarm-public"
  coordinator_url="${ONLYMACS_COORDINATOR_URL:-https://onlymacs.ai}"
  curl -fsS --max-time 8 "${coordinator_url%/}/admin/v1/providers/activity?provider_id=${provider_id}&swarm_id=${swarm_id}&limit=${limit}"
}

orchestrated_recover_session_id_from_provider_activity() {
  local provider_id model body picked session_id provider_name owner_member_name status
  provider_id="${ONLYMACS_CHAT_ROUTE_PROVIDER_ID:-${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-${ONLYMACS_LAST_CHAT_PROVIDER_ID:-}}}"
  model="${ONLYMACS_CHAT_ACTIVE_MODEL:-${ONLYMACS_ACTIVE_MODEL:-${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-}}}"
  [[ -n "$provider_id" ]] || return 1
  body="$(orchestrated_fetch_provider_activity_direct "$provider_id" 8)" || return 1
  picked="$(jq -c --arg model "$model" '
    [
      .activities[]?
      | select((.status // "") == "running" or ((.status // "") == "completed" and ((.final_body_base64 // "") | length > 0)))
      | select(($model | length) == 0 or (.resolved_model // "") == $model)
    ]
    | .[0] // empty
  ' <<<"$body" 2>/dev/null || true)"
  [[ -n "$picked" && "$picked" != "null" ]] || return 1
  session_id="$(jq -r '.session_id // empty' <<<"$picked" 2>/dev/null || true)"
  [[ -n "$session_id" ]] || return 1
  provider_name="$(jq -r '.provider_name // empty' <<<"$picked" 2>/dev/null || true)"
  owner_member_name="$(jq -r '.owner_member_name // empty' <<<"$picked" 2>/dev/null || true)"
  model="$(jq -r '.resolved_model // empty' <<<"$picked" 2>/dev/null || true)"
  status="$(jq -r '.status // empty' <<<"$picked" 2>/dev/null || true)"
  ONLYMACS_LAST_CHAT_SESSION_ID="$session_id"
  ONLYMACS_LAST_CHAT_PROVIDER_ID="$provider_id"
  [[ -n "$provider_name" ]] && ONLYMACS_LAST_CHAT_PROVIDER_NAME="$provider_name"
  [[ -n "$owner_member_name" ]] && ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME="$owner_member_name"
  [[ -n "$model" ]] && ONLYMACS_LAST_CHAT_RESOLVED_MODEL="$model"
  ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="remote relay activity ${session_id} is ${status:-recoverable} after the local stream detached"
  printf '%s' "$session_id"
}

orchestrated_stream_content_looks_detached_prefix() {
  local content_path="${1:-}"
  local bytes prefix
  [[ -s "$content_path" ]] || return 1
  bytes="$(wc -c <"$content_path" 2>/dev/null | tr -d '[:space:]')"
  [[ "$bytes" =~ ^[0-9]+$ ]] || return 1
  [[ "$bytes" -le 4096 ]] || return 1
  if rg -q 'ONLYMACS_ARTIFACT_END' "$content_path" 2>/dev/null; then
    return 1
  fi
  if rg -q 'ONLYMACS_ARTIFACT_BEGIN' "$content_path" 2>/dev/null; then
    return 0
  fi
  prefix="$(LC_ALL=C head -c 64 "$content_path" 2>/dev/null | tr -d '\r\n\t ')"
  [[ "$prefix" == ONLY* ]]
}

orchestrated_recover_stream_content_from_activity() {
  local content_path="${1:-}"
  local headers_path="${2:-}"
  local step_id="${3:-step-01}"
  local attempt="${4:-0}"
  local artifact_path="${5:-}"
  local raw_path="${6:-}"
  local session_id activity_status output_preview final_body_base64 partial wait_limit wait_interval waited
  local provider_id provider_name owner_member_name model message

  session_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-session-id")"
  [[ -z "$session_id" ]] && session_id="${ONLYMACS_LAST_CHAT_SESSION_ID:-}"
  if [[ -z "$session_id" ]]; then
    session_id="$(orchestrated_recover_session_id_from_provider_activity || true)"
    if [[ -n "$session_id" ]]; then
      onlymacs_log_run_event "stream_activity_session_recovered" "$step_id" "running" "$attempt" "Recovered relay session ${session_id} from provider activity after a detached stream without response headers." "$artifact_path" "${ONLYMACS_LAST_CHAT_PROVIDER_ID:-}" "${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-${ONLYMACS_LAST_CHAT_PROVIDER_NAME:-}}" "${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-}" "$raw_path" "$(orchestrated_plan_path)"
    fi
  fi
  [[ -n "$session_id" ]] || return 1

  wait_limit="${ONLYMACS_STREAM_ACTIVITY_RECOVERY_WAIT_SECONDS:-60}"
  wait_interval="${ONLYMACS_STREAM_ACTIVITY_RECOVERY_POLL_SECONDS:-5}"
  [[ "$wait_limit" =~ ^[0-9]+$ ]] || wait_limit=60
  [[ "$wait_interval" =~ ^[0-9]+$ && "$wait_interval" -gt 0 ]] || wait_interval=5
  waited=0

  while true; do
    request_json GET "/admin/v1/relay/activity?session_id=${session_id}" || return 1
    require_success "OnlyMacs could not recover the remote relay activity." || return 1

    activity_status="$(jq -r '.activities[0].status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    output_preview="$(jq -r '.activities[0].output_preview // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    final_body_base64="$(jq -r '.activities[0].final_body_base64 // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    partial="$(jq -r '.activities[0].partial // false' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    provider_id="$(jq -r '.activities[0].provider_id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    provider_name="$(jq -r '.activities[0].provider_name // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    owner_member_name="$(jq -r '.activities[0].owner_member_name // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    model="$(jq -r '.activities[0].resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    [[ -n "$provider_id" ]] && ONLYMACS_LAST_CHAT_PROVIDER_ID="$provider_id"
    [[ -n "$provider_name" ]] && ONLYMACS_LAST_CHAT_PROVIDER_NAME="$provider_name"
    [[ -n "$owner_member_name" ]] && ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME="$owner_member_name"
    [[ -n "$model" ]] && ONLYMACS_LAST_CHAT_RESOLVED_MODEL="$model"

    if [[ "$activity_status" == "completed" && -n "$final_body_base64" ]]; then
      if recover_chat_content_from_activity_body "$final_body_base64" "$content_path" && [[ -s "$content_path" ]]; then
        onlymacs_log_run_event "stream_activity_recovered" "$step_id" "running" "$attempt" "Recovered completed relay activity ${session_id} after a transport error." "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$raw_path" "$(orchestrated_plan_path)"
        return 0
      fi
    fi

    if [[ "$activity_status" == "completed" && -n "$output_preview" && ! -s "$content_path" ]]; then
      printf '%s\n' "$output_preview" >"$content_path"
      onlymacs_log_run_event "stream_activity_recovered_preview" "$step_id" "partial" "$attempt" "Recovered relay preview for completed activity ${session_id}, but final body was unavailable." "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$raw_path" "$(orchestrated_plan_path)"
      return 0
    fi

    if [[ "$activity_status" == "running" ]]; then
      if [[ "$waited" -ge "$wait_limit" ]]; then
        message="remote activity ${session_id} is still running after ${waited}s; this run can be resumed without starting duplicate work"
        ONLYMACS_LAST_CHAT_FAILURE_KIND="detached_activity_running"
        ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="$message"
        onlymacs_log_run_event "stream_activity_still_running" "$step_id" "queued" "$attempt" "$message" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$raw_path" "$(orchestrated_plan_path)"
        return 2
      fi
      sleep "$wait_interval"
      waited=$((waited + wait_interval))
      continue
    fi

    if [[ "$activity_status" == "failed" || "$activity_status" == "cancelled" ]]; then
      if [[ "$partial" == "true" && -n "$output_preview" && ! -s "$content_path" ]]; then
        printf '%s\n' "$output_preview" >"$content_path"
      fi
      return 1
    fi

    return 1
  done
}

orchestrated_recover_detached_batch_from_activity() {
  local run_dir="${1:-${ONLYMACS_CURRENT_RETURN_DIR:-}}"
  local status_path plan_path session_id step_id batch_index batch_count batch_status wait_limit wait_interval waited
  local activity_status final_body_base64 output_preview partial provider_id provider_name owner_member_name model
  local batch_artifact_path batch_raw_path content_path body_path batch_dir batch_files_dir

  [[ -n "$run_dir" ]] || return 1
  status_path="${run_dir}/status.json"
  plan_path="${run_dir}/plan.json"
  [[ -f "$status_path" && -f "$plan_path" ]] || return 1

  session_id="$(jq -r '.session_id // empty' "$status_path" 2>/dev/null || true)"
  step_id="$(jq -r '.progress.step_id // empty' "$status_path" 2>/dev/null || true)"
  batch_index="$(jq -r '.progress.batch_index // empty' "$status_path" 2>/dev/null || true)"
  [[ -n "$session_id" && -n "$step_id" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 1

  batch_artifact_path="$(jq -r --arg step_id "$step_id" --argjson batch_index "$batch_index" '
    [.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $batch_index) | .artifact_path // empty] | first // empty
  ' "$plan_path" 2>/dev/null || true)"
  [[ -n "$batch_artifact_path" ]] || return 1
  batch_status="$(jq -r --arg step_id "$step_id" --argjson batch_index "$batch_index" '
    [.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $batch_index) | .status // empty] | first // empty
  ' "$plan_path" 2>/dev/null || true)"
  if [[ -s "$batch_artifact_path" && "$batch_status" =~ ^(completed|reused|recovered|completed_from_partial)$ ]]; then
    return 0
  fi

  batch_count="$(jq -r --arg step_id "$step_id" '.progress.batch_count // ([.steps[]? | select(.id == $step_id) | .batching.batch_count // empty] | first) // 1' "$plan_path" 2>/dev/null || printf '1')"
  [[ "$batch_count" =~ ^[0-9]+$ && "$batch_count" -gt 0 ]] || batch_count=1
  wait_limit="${ONLYMACS_DETACHED_RELAY_WAIT_SECONDS:-900}"
  wait_interval="${ONLYMACS_DETACHED_RELAY_POLL_SECONDS:-10}"
  [[ "$wait_limit" =~ ^[0-9]+$ ]] || wait_limit=900
  [[ "$wait_interval" =~ ^[0-9]+$ && "$wait_interval" -gt 0 ]] || wait_interval=10
  waited=0

  while true; do
    request_json GET "/admin/v1/relay/activity?session_id=${session_id}" || return 1
    require_success "OnlyMacs could not read detached relay activity." || return 1
    activity_status="$(jq -r '.activities[0].status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    final_body_base64="$(jq -r '.activities[0].final_body_base64 // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    output_preview="$(jq -r '.activities[0].output_preview // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    partial="$(jq -r '.activities[0].partial // false' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    provider_id="$(jq -r '.activities[0].provider_id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    provider_name="$(jq -r '.activities[0].provider_name // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    owner_member_name="$(jq -r '.activities[0].owner_member_name // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    model="$(jq -r '.activities[0].resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"

    case "$activity_status" in
      completed)
        break
        ;;
      running)
        if [[ "$waited" -ge "$wait_limit" ]]; then
          printf 'OnlyMacs found detached remote work still running for session %s after %ss. Run resume-run again after it completes; no duplicate batch was started.\n' "$session_id" "$waited" >&2
          return 2
        fi
        if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
          printf '\nOnlyMacs found detached remote work still running for %s batch %s/%s. Waiting %ss before checking again.\n' "$step_id" "$batch_index" "$batch_count" "$wait_interval" >&2
        fi
        sleep "$wait_interval"
        waited=$((waited + wait_interval))
        continue
        ;;
      failed|cancelled)
        if [[ "$partial" == "true" && -n "$output_preview" ]]; then
          batch_dir="$(dirname "$(dirname "$batch_artifact_path")")"
          mkdir -p "$batch_dir" || true
          printf '%s\n' "$output_preview" >"${batch_dir}/RESULT.partial.md"
        fi
        return 1
        ;;
      *)
        return 1
        ;;
    esac
  done

  [[ -n "$final_body_base64" ]] || return 1
  content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-detached-content-XXXXXX")"
  body_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-detached-body-XXXXXX")"
  if ! recover_chat_content_from_activity_body "$final_body_base64" "$content_path"; then
    rm -f "$content_path" "$body_path"
    return 1
  fi

  batch_files_dir="$(dirname "$batch_artifact_path")"
  batch_dir="$(dirname "$batch_files_dir")"
  batch_raw_path="${batch_dir}/RESULT.md"
  mkdir -p "$batch_files_dir" "$batch_dir" || {
    rm -f "$content_path" "$body_path"
    return 1
  }
  cp "$content_path" "$batch_raw_path"
  if ! extract_marked_artifact_block "$content_path" "$body_path" && ! extract_single_fenced_code_block "$content_path" "$body_path"; then
    cp "$content_path" "$body_path"
  fi
  orchestrated_promote_json_batch_artifact "$body_path" "$batch_artifact_path" "$step_id" "$batch_index" "recovered" || true
  rm -f "$content_path" "$body_path"

  orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "recovered" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "Recovered completed detached relay session ${session_id}."
  onlymacs_log_run_event "detached_relay_recovered" "$step_id" "resuming" "0" "Recovered completed detached relay session ${session_id} before starting duplicate work." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$batch_raw_path" "$(orchestrated_plan_path)"
  return 0
}

chat_replay_safe_for_retry() {
  local content_path="${1:-}"
  if [[ -s "$content_path" ]]; then
    return 1
  fi
  if [[ -n "${ONLYMACS_RESOLVED_ARTIFACT_JSON:-}" && "${ONLYMACS_RESOLVED_ARTIFACT_JSON:-}" != "null" ]]; then
    return 1
  fi
  return 0
}

write_chat_return_artifact() {
  local content_path="${1:-}"
  local headers_path="${2:-}"
  local model_alias="${3:-}"
  local prompt="${4:-}"
  local session_id model provider_id provider_name owner_member_name swarm_id route_scope
  local returns_root run_id artifact_dir files_dir filename artifact_path body_path manifest_path status_path result_path latest_path created_at
  local status_value validation_status validation_message next_step target_path artifact_manifest_json timeout_policy_json prompt_tokens output_tokens total_remote_tokens prompt_bytes artifact_kind

  [[ -s "$content_path" ]] || return 0
  session_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-session-id")"
  model="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
  provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
  provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
  owner_member_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
  swarm_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-swarm-id")"
  route_scope="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-route-scope")"
  if [[ -z "$model" ]]; then
    model="$(normalize_model_alias "$model_alias")"
  fi

  returns_root="$(chat_returns_root)"
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  run_id="${ONLYMACS_CURRENT_RETURN_RUN_ID:-}"
  artifact_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}"
  if [[ -z "$run_id" || -z "$artifact_dir" ]]; then
    run_id="$(chat_run_id_from_prompt "$prompt" "${model_alias:-$model}")"
    artifact_dir="${returns_root}/${run_id}"
  fi
  files_dir="${artifact_dir}/files"
  mkdir -p "$files_dir" || return 0

  filename="$(chat_return_filename "$prompt" "$content_path")"
  artifact_path="${files_dir}/${filename}"
  target_path="$(artifact_target_path_from_content "$content_path" 2>/dev/null || true)"
  target_path="$(safe_artifact_target_path "$target_path" "$filename")"
  body_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chat-body-XXXXXX")"
  if ! extract_marked_artifact_block "$content_path" "$body_path" && ! extract_single_fenced_code_block "$content_path" "$body_path"; then
    cp "$content_path" "$body_path"
  fi
  cp "$body_path" "$artifact_path"
  rm -f "$body_path"
  result_path="${artifact_dir}/RESULT.md"
  cp "$content_path" "$result_path"
  repair_json_artifact_if_possible "$artifact_path" "$prompt"
  if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
    onlymacs_log_run_event "json_repair_applied" "" "running" "0" "${ONLYMACS_JSON_REPAIR_MESSAGE:-recovered strict JSON before model retry}" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$result_path" "${artifact_dir}/status.json"
  elif [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "failed" ]]; then
    onlymacs_log_run_event "json_repair_failed" "" "running" "0" "${ONLYMACS_JSON_REPAIR_MESSAGE:-JSON repair failed}" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$result_path" "${artifact_dir}/status.json"
  fi
  validate_return_artifact "$artifact_path" "$prompt"
  validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-skipped}"
  validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
  status_value="completed"
  next_step="Ask your local Codex or Claude session to review the returned file before integrating it into the project."
  if [[ "$validation_status" == "failed" ]]; then
    status_value="completed_with_warnings"
    next_step="The returned file was saved, but local validation failed. Ask your local Codex or Claude session to repair it before integrating it into the project."
  fi

  manifest_path="${artifact_dir}/result.json"
  status_path="${artifact_dir}/status.json"
  latest_path="${returns_root}/latest.json"
  timeout_policy_json="$(onlymacs_timeout_policy_json)"
  prompt_bytes="$(printf '%s' "$prompt" | wc -c | tr -d ' ')"
  prompt_tokens="$(chat_estimated_tokens "$prompt_bytes")"
  output_tokens="$(chat_estimated_tokens "$(chat_output_bytes "$artifact_path")")"
  total_remote_tokens=$((prompt_tokens + output_tokens))
  case "$artifact_path" in
    *.patch|*.diff)
      artifact_kind="patch"
      ;;
    *)
      artifact_kind="file"
      ;;
  esac
  artifact_manifest_json="$(jq -cn \
    --arg path "$artifact_path" \
    --arg filename "$(basename "$artifact_path")" \
    --arg target_path "$target_path" \
    --arg kind "$artifact_kind" \
    '[{path:$path, filename:$filename, target_path:$target_path, kind:$kind}]')"
  jq -n \
    --arg created_at "$created_at" \
    --arg completed_at "$created_at" \
    --arg run_id "$run_id" \
    --arg session_id "$session_id" \
    --arg model "$model" \
    --arg model_alias "$model_alias" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg owner_member_name "$owner_member_name" \
    --arg swarm_id "$swarm_id" \
    --arg route_scope "$route_scope" \
    --arg prompt "$prompt" \
    --arg status_value "$status_value" \
    --arg validation_status "$validation_status" \
    --arg validation_message "$validation_message" \
    --arg artifact "$(basename "$artifact_path")" \
    --arg artifact_path "$artifact_path" \
    --arg target_path "$target_path" \
    --arg result_path "$result_path" \
    --arg status_path "$status_path" \
    --arg inbox "$artifact_dir" \
    --arg files_dir "$files_dir" \
    --argjson artifact_manifest "$artifact_manifest_json" \
    --argjson timeout_policy "$timeout_policy_json" \
    --argjson prompt_tokens "${prompt_tokens:-0}" \
    --argjson output_tokens "${output_tokens:-0}" \
    --argjson total_remote_tokens "${total_remote_tokens:-0}" \
    '{
      run_id: $run_id,
      status: $status_value,
      created_at: $created_at,
      completed_at: $completed_at,
      session_id: $session_id,
      model: $model,
      model_alias: $model_alias,
      provider_id: $provider_id,
      provider_name: $provider_name,
      owner_member_name: $owner_member_name,
      swarm_id: $swarm_id,
      route_scope: $route_scope,
      artifact: $artifact,
      artifact_path: $artifact_path,
      artifacts: [$artifact_path],
      artifact_targets: $artifact_manifest,
      target_path: $target_path,
      result_path: $result_path,
      status_path: $status_path,
      inbox: $inbox,
      files_dir: $files_dir,
      prompt: $prompt,
      artifact_validation: {
        status: $validation_status,
        message: ($validation_message | if length > 0 then . else null end)
      },
      token_accounting: {
        prompt_tokens_estimate: $prompt_tokens,
        output_tokens_estimate: $output_tokens,
        remote_work_tokens_estimate: $total_remote_tokens,
        total_remote_tokens_estimate: $total_remote_tokens,
        estimated_codex_tokens_avoided: $output_tokens,
        method: "rough bytes/4 estimate for saved prompt and artifact"
      },
      timeout_policy: $timeout_policy
    }' >"$manifest_path"
  jq -n \
    --arg status "$status_value" \
    --arg run_id "$run_id" \
    --arg started_at "${ONLYMACS_CURRENT_RETURN_STARTED_AT:-$created_at}" \
    --arg updated_at "$created_at" \
    --arg completed_at "$created_at" \
    --arg session_id "$session_id" \
    --arg model "$model" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg owner_member_name "$owner_member_name" \
    --arg route_scope "$route_scope" \
    --arg inbox "$artifact_dir" \
    --arg artifact_path "$artifact_path" \
    --arg target_path "$target_path" \
    --arg result_path "$result_path" \
    --arg manifest_path "$manifest_path" \
    --arg next_step "$next_step" \
    --arg validation_status "$validation_status" \
    --arg validation_message "$validation_message" \
    --argjson artifact_manifest "$artifact_manifest_json" \
    --argjson timeout_policy "$timeout_policy_json" \
    --argjson prompt_tokens "${prompt_tokens:-0}" \
    --argjson output_tokens "${output_tokens:-0}" \
    --argjson total_remote_tokens "${total_remote_tokens:-0}" \
    '{
      status: $status,
      run_id: $run_id,
      started_at: $started_at,
      updated_at: $updated_at,
      completed_at: $completed_at,
      session_id: ($session_id | if length > 0 then . else null end),
      model: ($model | if length > 0 then . else null end),
      provider_id: ($provider_id | if length > 0 then . else null end),
      provider_name: ($provider_name | if length > 0 then . else null end),
      owner_member_name: ($owner_member_name | if length > 0 then . else null end),
      route_scope: ($route_scope | if length > 0 then . else null end),
      inbox: $inbox,
      artifact_path: $artifact_path,
      artifacts: [$artifact_path],
      artifact_targets: $artifact_manifest,
      target_path: $target_path,
      result_path: $result_path,
      manifest_path: $manifest_path,
      artifact_validation: {
        status: $validation_status,
        message: ($validation_message | if length > 0 then . else null end)
      },
      token_accounting: {
        prompt_tokens_estimate: $prompt_tokens,
        output_tokens_estimate: $output_tokens,
        remote_work_tokens_estimate: $total_remote_tokens,
        total_remote_tokens_estimate: $total_remote_tokens,
        estimated_codex_tokens_avoided: $output_tokens,
        method: "rough bytes/4 estimate for saved prompt and artifact"
      },
      timeout_policy: $timeout_policy,
      next_step: $next_step
    }' >"$status_path"
  jq -n \
    --arg run_id "$run_id" \
    --arg status "$status_value" \
    --arg updated_at "$created_at" \
    --arg inbox "$artifact_dir" \
    --arg artifact_path "$artifact_path" \
    --arg target_path "$target_path" \
    --arg status_path "$status_path" \
    --arg manifest_path "$manifest_path" \
    --argjson artifact_manifest "$artifact_manifest_json" \
    '{run_id:$run_id,status:$status,updated_at:$updated_at,inbox:$inbox,artifact_path:$artifact_path,artifacts:[$artifact_path],artifact_targets:$artifact_manifest,target_path:$target_path,status_path:$status_path,manifest_path:$manifest_path}' >"$latest_path"
  onlymacs_log_run_event "chat_completed" "" "$status_value" "0" "$validation_message" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model" "$result_path" "$status_path"
  onlymacs_auto_report_public_run "$artifact_dir"

  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    printf '\n\nOnlyMacs completed'
    if [[ -n "$owner_member_name" ]]; then
      printf ' on %s' "$owner_member_name"
    elif [[ -n "$provider_name" ]]; then
      printf ' on %s' "$provider_name"
    fi
    if [[ -n "$model" ]]; then
      printf ' using %s' "$model"
    fi
    printf '.\nSaved file: %s\nFull remote answer: %s\nInbox: %s\nStatus: %s\n' "$artifact_path" "$result_path" "$artifact_dir" "$status_path"
    if [[ "$validation_status" == "failed" ]]; then
      printf 'Validation warning: %s\n' "$validation_message"
    fi
    printf 'Next: %s\n' "$next_step"
  fi
}

extract_context_request_summary_from_content() {
  local content_path="${1:-}"
  awk '
    BEGIN {in_section = 0}
    /^Context Requests[[:space:]]*$/ {in_section = 1; next}
    in_section && /^[A-Z][A-Za-z ]+[[:space:]]*$/ {exit}
    in_section {print}
  ' "$content_path" | sed '/^[[:space:]]*$/d'
}

run_chat_with_context_loop() {
  local model="${1:-}"
  local model_alias="${2:-}"
  local prompt="${3:-}"
  local route_scope="${4:-swarm}"
  local payload content_path headers_path context_request_summary current_round max_rounds allow_context_requests status_body stream_retry_count
  local http_status failure_message failure_kind user_failure_message next_step

  current_round=0
  stream_retry_count=0
  prepare_chat_return_run "$model_alias" "$prompt" "$route_scope"

  while true; do
    payload="$(build_chat_payload "$model" "$prompt" "$route_scope" "$model_alias")"
    content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chat-content-XXXXXX")"
    headers_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chat-headers-XXXXXX")"
    if ! stream_chat_payload_capture "$payload" "$content_path" "$headers_path"; then
      http_status="$(onlymacs_chat_http_status "$headers_path")"
      failure_kind="${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}}"
      failure_message="${ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE:-${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-}}"
      ONLYMACS_LAST_CHAT_HTTP_STATUS="$http_status"
      ONLYMACS_LAST_CHAT_FAILURE_KIND="$failure_kind"
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="$failure_message"
      onlymacs_capture_last_chat_headers "$headers_path"
      if recover_chat_from_relay_activity "$content_path" "$headers_path" "$model_alias" "$prompt" "$route_scope"; then
        rm -f "$content_path"
        rm -f "$headers_path"
        break
      fi
      if [[ "$stream_retry_count" -lt 1 ]] && chat_failure_safe_for_stream_retry "$content_path" "$http_status" && chat_replay_safe_for_retry "$content_path"; then
        stream_retry_count=$((stream_retry_count + 1))
        if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
          printf '\nOnlyMacs lost the remote stream before any output arrived. Retrying once because this prompt is safe to replay.\n' >&2
        fi
        write_chat_status_file "${ONLYMACS_CURRENT_RETURN_DIR:-}" "retrying" "$model_alias" "$route_scope" "$prompt"
        rm -f "$content_path" "$headers_path"
        continue
      fi
      user_failure_message="$(direct_chat_failure_message "$model_alias" "$route_scope" "$http_status" "$failure_message")"
      next_step="$(direct_chat_failure_next_step "$model_alias" "$route_scope" "$http_status")"
      write_chat_failure_artifact "$content_path" "$headers_path" "$model_alias" "$prompt" "$route_scope" "$user_failure_message" "$next_step"
      print_direct_chat_failure "$user_failure_message" "$next_step"
      rm -f "$content_path"
      rm -f "$headers_path"
      return 1
    fi

    if [[ ! -s "$content_path" ]]; then
      http_status="$(onlymacs_chat_http_status "$headers_path")"
      [[ -n "$http_status" ]] || http_status="200"
      if [[ "${ONLYMACS_STREAM_REASONING_BYTES:-0}" =~ ^[0-9]+$ && "${ONLYMACS_STREAM_REASONING_BYTES:-0}" -gt 0 ]]; then
        failure_kind="reasoning_only_completed"
        failure_message="the model produced reasoning bytes but no final answer text before the stream ended"
      else
        failure_kind="empty_output"
        failure_message="the stream ended without generated answer text"
      fi
      ONLYMACS_LAST_CHAT_HTTP_STATUS="$http_status"
      ONLYMACS_LAST_CHAT_FAILURE_KIND="$failure_kind"
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="$failure_message"
      onlymacs_capture_last_chat_headers "$headers_path"
      user_failure_message="$(direct_chat_failure_message "$model_alias" "$route_scope" "$http_status" "$failure_message")"
      next_step="$(direct_chat_failure_next_step "$model_alias" "$route_scope" "$http_status")"
      write_chat_failure_artifact "$content_path" "$headers_path" "$model_alias" "$prompt" "$route_scope" "$user_failure_message" "$next_step"
      print_direct_chat_failure "$user_failure_message" "$next_step"
      rm -f "$content_path" "$headers_path"
      return 1
    fi

    allow_context_requests="$(jq -r '.manifest.permissions.allow_context_requests // .manifest.permissions.allowContextRequests // false' <<<"${ONLYMACS_RESOLVED_ARTIFACT_JSON:-null}" 2>/dev/null || printf 'false')"
    max_rounds="$(jq -r '.manifest.permissions.max_context_request_rounds // .manifest.permissions.maxContextRequestRounds // 0' <<<"${ONLYMACS_RESOLVED_ARTIFACT_JSON:-null}" 2>/dev/null || printf '0')"
    context_request_summary="$(extract_context_request_summary_from_content "$content_path")"

    if [[ "$allow_context_requests" != "true" || -z "$context_request_summary" || "$context_request_summary" == "None." ]]; then
      write_chat_return_artifact "$content_path" "$headers_path" "$model_alias" "$prompt"
      rm -f "$content_path" "$headers_path"
      break
    fi
    if (( current_round >= max_rounds )); then
      write_chat_return_artifact "$content_path" "$headers_path" "$model_alias" "$prompt"
      rm -f "$content_path" "$headers_path"
      break
    fi
    rm -f "$content_path" "$headers_path"

    current_round=$((current_round + 1))
    ONLYMACS_RESOLVED_CONTEXT_REQUEST_ROUND="$current_round"
    request_json GET "/admin/v1/status" || return 1
    require_success "OnlyMacs could not re-open file approval for the requested extra context." || return 1
    status_body="$ONLYMACS_LAST_HTTP_BODY"
    if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
      printf '\nOnlyMacs needs a bit more approved context before it can finish this request.\n\n'
    fi
    if ! run_file_access_flow "$model_alias" "$prompt" "$status_body" "$context_request_summary" "$current_round"; then
      write_chat_failure_artifact "$content_path" "$headers_path" "$model_alias" "$prompt" "$route_scope"
      return 1
    fi
  done

  return 0
}
