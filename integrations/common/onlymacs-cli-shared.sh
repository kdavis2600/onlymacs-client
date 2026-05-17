# Shared state, formatting, and path helpers for the OnlyMacs shell wrapper.


BASE_URL="${ONLYMACS_BRIDGE_URL:-http://127.0.0.1:4318}"
ONLYMACS_JSON_MODE=0
ONLYMACS_ASSUME_YES=0
ONLYMACS_TITLE_OVERRIDE=""
ONLYMACS_WATCH_INTERVAL="${ONLYMACS_WATCH_INTERVAL:-2}"
ONLYMACS_WRAPPER_NAME=""
ONLYMACS_TOOL_NAME=""
ONLYMACS_LAST_HTTP_STATUS=""
ONLYMACS_LAST_HTTP_BODY=""
ONLYMACS_LAST_CURL_ERROR=""
ONLYMACS_ACTIVITY_LABEL=""
ONLYMACS_ACTIVITY_INTERPRETATION=""
ONLYMACS_ACTIVITY_ROUTE_SCOPE=""
ONLYMACS_ACTIVITY_MODEL=""
ONLYMACS_INVOCATION_LABEL=""
ONLYMACS_EXECUTION_MODE="${ONLYMACS_EXECUTION_MODE:-auto}"
ONLYMACS_RESOLVED_ARTIFACT_JSON=""
ONLYMACS_RESOLVED_ARTIFACT_SHA=""
ONLYMACS_RESOLVED_SELECTED_PATHS_JSON="[]"
ONLYMACS_RESOLVED_LEASE_ID=""
ONLYMACS_RESOLVED_CONTEXT_REQUEST_ROUND=0

bool_is_true() {
  case "${1:-false}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

default_workspace_id() {
  if [[ -n "${ONLYMACS_WORKSPACE_ID:-}" ]]; then
    echo "$ONLYMACS_WORKSPACE_ID"
  else
    echo "$PWD"
  fi
}

default_thread_id() {
  if [[ -n "${ONLYMACS_THREAD_ID:-}" ]]; then
    echo "$ONLYMACS_THREAD_ID"
  else
    echo "default-thread"
  fi
}

onlymacs_state_dir() {
  if [[ -n "${ONLYMACS_STATE_DIR:-}" ]]; then
    echo "$ONLYMACS_STATE_DIR"
  elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
    echo "${XDG_STATE_HOME}/onlymacs"
  else
    echo "${HOME}/.local/state/onlymacs"
  fi
}

workspace_defaults_path() {
  echo "$(onlymacs_state_dir)/workspace-defaults.json"
}

activity_log_path() {
  echo "$(onlymacs_state_dir)/last-activity.json"
}

file_access_state_dir() {
  echo "$(onlymacs_state_dir)/file-access"
}

file_access_request_path() {
  local request_id="$1"
  echo "$(file_access_state_dir)/request-${request_id}.json"
}

file_access_response_path() {
  local request_id="$1"
  echo "$(file_access_state_dir)/response-${request_id}.json"
}

file_access_claim_path() {
  local request_id="$1"
  echo "$(file_access_state_dir)/claim-${request_id}.json"
}

file_access_manifest_path() {
  local request_id="$1"
  echo "$(file_access_state_dir)/manifest-${request_id}.json"
}

file_access_context_path() {
  local request_id="$1"
  echo "$(file_access_state_dir)/context-${request_id}.txt"
}

clear_resolved_artifact() {
  ONLYMACS_RESOLVED_ARTIFACT_JSON=""
  ONLYMACS_RESOLVED_ARTIFACT_SHA=""
  ONLYMACS_RESOLVED_SELECTED_PATHS_JSON="[]"
  ONLYMACS_RESOLVED_LEASE_ID=""
  ONLYMACS_RESOLVED_CONTEXT_REQUEST_ROUND=0
}

artifact_suffix_for_idempotency() {
  if [[ -n "${ONLYMACS_RESOLVED_ARTIFACT_SHA:-}" ]]; then
    printf '%s' "$ONLYMACS_RESOLVED_ARTIFACT_SHA"
  fi
}

onlymacs_format_invocation() {
  local command_name="${1:-onlymacs}"
  shift || true
  if [[ -n "${ONLYMACS_INVOCATION_TEXT:-}" ]]; then
    printf '%s' "$ONLYMACS_INVOCATION_TEXT"
    return 0
  fi
  printf '%s' "$command_name"
  local arg
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
}

set_activity_context() {
  ONLYMACS_ACTIVITY_LABEL="${1:-}"
  ONLYMACS_ACTIVITY_INTERPRETATION="${2:-}"
  ONLYMACS_ACTIVITY_ROUTE_SCOPE="${3:-}"
  ONLYMACS_ACTIVITY_MODEL="${4:-}"
}

record_current_activity() {
  local outcome="${1:-unknown}"
  local detail="${2:-}"
  local session_id="${3:-}"
  local session_status="${4:-}"
  local state_dir activity_path tmp_file timestamp
  if [[ -z "${ONLYMACS_ACTIVITY_LABEL:-}" ]]; then
    return 0
  fi

  state_dir="$(onlymacs_state_dir)"
  activity_path="$(activity_log_path)"
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  mkdir -p "$state_dir"
  tmp_file="$(mktemp)"
  jq -n \
    --arg recorded_at "$timestamp" \
    --arg wrapper_name "$ONLYMACS_WRAPPER_NAME" \
    --arg tool_name "$ONLYMACS_TOOL_NAME" \
    --arg workspace_id "$(default_workspace_id)" \
    --arg thread_id "$(default_thread_id)" \
    --arg command_label "$ONLYMACS_ACTIVITY_LABEL" \
    --arg interpreted_as "$ONLYMACS_ACTIVITY_INTERPRETATION" \
    --arg route_scope "$ONLYMACS_ACTIVITY_ROUTE_SCOPE" \
    --arg model "$ONLYMACS_ACTIVITY_MODEL" \
    --arg outcome "$outcome" \
    --arg detail "$detail" \
    --arg session_id "$session_id" \
    --arg session_status "$session_status" \
    '{
      recorded_at: $recorded_at,
      wrapper_name: $wrapper_name,
      tool_name: $tool_name,
      workspace_id: $workspace_id,
      thread_id: $thread_id,
      command_label: $command_label,
      interpreted_as: ($interpreted_as | select(length > 0)),
      route_scope: ($route_scope | select(length > 0)),
      model: ($model | select(length > 0)),
      outcome: $outcome,
      detail: ($detail | select(length > 0)),
      session_id: ($session_id | select(length > 0)),
      session_status: ($session_status | select(length > 0))
    }' >"$tmp_file"
  mv "$tmp_file" "$activity_path"
}

workspace_default_reusable() {
  case "${1:-}" in
    quick|balanced|wide|go-wide|go_wide|local-first|trusted-only|trusted_only|trusted|offload-max|remote-first|remote-only|remote_only|remote|precise)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_workspace_default_preset() {
  local defaults_path workspace_id
  defaults_path="$(workspace_defaults_path)"
  workspace_id="$(default_workspace_id)"
  if [[ ! -f "$defaults_path" ]]; then
    return 0
  fi
  jq -r --arg workspace "$workspace_id" '.[$workspace].preset // empty' "$defaults_path" 2>/dev/null || true
}

save_workspace_default_preset() {
  local preset="${1:-}"
  local defaults_path workspace_id state_dir tmp_file timestamp
  if ! workspace_default_reusable "$preset"; then
    return 0
  fi
  state_dir="$(onlymacs_state_dir)"
  defaults_path="$(workspace_defaults_path)"
  workspace_id="$(default_workspace_id)"
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  mkdir -p "$state_dir"
  tmp_file="$(mktemp)"
  if [[ -f "$defaults_path" ]] && jq -e . >/dev/null 2>&1 <"$defaults_path"; then
    jq --arg workspace "$workspace_id" --arg preset "$preset" --arg updated_at "$timestamp" \
      '.[$workspace] = ((.[$workspace] // {}) + {preset:$preset, updated_at:$updated_at})' \
      "$defaults_path" >"$tmp_file"
  else
    jq -n --arg workspace "$workspace_id" --arg preset "$preset" --arg updated_at "$timestamp" \
      '{($workspace): {preset:$preset, updated_at:$updated_at}}' >"$tmp_file"
  fi
  mv "$tmp_file" "$defaults_path"
}

derive_title_from_prompt() {
  local prompt="${1:-}"
  prompt="$(printf '%s' "$prompt" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  if [[ -z "$prompt" ]]; then
    echo ""
  elif [[ "${#prompt}" -le 48 ]]; then
    echo "$prompt"
  else
    echo "${prompt:0:45}..."
  fi
}

normalize_model_alias() {
  local requested="${1:-}"
  local lowered
  lowered="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    ""|"best"|"best-available"|"best_available"|"auto"|"balanced"|"wide"|"go-wide"|"go_wide")
      echo ""
      ;;
    "coder")
      echo "${ONLYMACS_CODER_MODEL:-qwen2.5-coder:32b}"
      ;;
    "fast"|"quick")
      echo "${ONLYMACS_FAST_MODEL:-gemma4:26b}"
      ;;
    "precise")
      echo "${ONLYMACS_CODER_MODEL:-qwen2.5-coder:32b}"
      ;;
    "local"|"local-first"|"local_first"|"trusted-only"|"trusted_only"|"trusted"|"offload-max"|"remote-first"|"remote-only"|"remote_only"|"remote")
      echo ""
      ;;
    *)
      echo "$requested"
      ;;
  esac
}

chat_arg_looks_like_route_or_model() {
  local requested="${1:-}"
  local lowered
  lowered="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    ""|"best"|"best-available"|"best_available"|"auto"|"coder"|"fast"|"quick"|"balanced"|"wide"|"go-wide"|"go_wide"|"precise"|"local"|"local-first"|"local_first"|"trusted-only"|"trusted_only"|"trusted"|"offload-max"|"remote-first"|"remote-only"|"remote_only"|"remote")
      return 0
      ;;
  esac
  [[ "$requested" == *:* ]]
}

prefer_remote_for_alias() {
  local requested="${1:-}"
  local lowered
  lowered="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    "remote-first"|"remote-only"|"remote_only"|"remote")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

soft_prefer_remote_for_alias() {
  local requested="${1:-}"
  if prefer_remote_for_alias "$requested"; then
    return 1
  fi
  [[ "$(route_scope_for_alias "$requested")" == "swarm" ]]
}

route_scope_for_alias() {
  local requested="${1:-}"
  local lowered
  lowered="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    "local"|"local-first"|"local_first")
      echo "local_only"
      ;;
    "trusted-only"|"trusted_only"|"trusted"|"offload-max")
      echo "trusted_only"
      ;;
    *)
      echo "swarm"
      ;;
  esac
}

default_idempotency_key() {
  local model="${1:-}"
  local width="${2:-1}"
  local prompt="${3:-}"
  local title="${4:-}"
  local workspace thread artifact_suffix
  workspace="$(default_workspace_id)"
  thread="$(default_thread_id)"
  artifact_suffix="$(artifact_suffix_for_idempotency)"
  printf '%s' "${workspace}|${thread}|${model}|${width}|${title}|${prompt}|${artifact_suffix}" | shasum -a 256 | awk '{print substr($1,1,24)}'
}

default_file_access_request_id() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  printf '%s' "$(default_workspace_id)|$(default_thread_id)|${model_alias}|${prompt}|$$|$(date +%s)" | shasum -a 256 | awk '{print substr($1,1,20)}'
}

bridge_base_url_is_app_managed_local() {
  case "$BASE_URL" in
    http://127.0.0.1:4318|http://127.0.0.1:4318/*|http://localhost:4318|http://localhost:4318/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

wake_onlymacs_app() {
  if [[ "${ONLYMACS_DISABLE_APP_WAKE:-0}" == "1" ]]; then
    return 1
  fi
  if ! bridge_base_url_is_app_managed_local; then
    return 1
  fi

  local app_path="${ONLYMACS_APP_PATH:-}"
  if [[ -n "$app_path" && -d "$app_path" ]]; then
    /usr/bin/open -g "$app_path" >/dev/null 2>&1 || return 1
    return 0
  fi

  if [[ -d "/Applications/OnlyMacs.app" ]]; then
    /usr/bin/open -g "/Applications/OnlyMacs.app" >/dev/null 2>&1 || return 1
    return 0
  fi
  if [[ -d "${HOME}/Applications/OnlyMacs.app" ]]; then
    /usr/bin/open -g "${HOME}/Applications/OnlyMacs.app" >/dev/null 2>&1 || return 1
    return 0
  fi

  /usr/bin/open -g -a "OnlyMacs" >/dev/null 2>&1
}

wait_for_local_bridge_ready() {
  local deadline_seconds="${ONLYMACS_BRIDGE_STARTUP_WAIT_SECONDS:-45}"
  local waited=0
  local interval=1

  while (( waited < deadline_seconds )); do
    if curl -fsS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
    waited=$((waited + interval))
  done

  return 1
}

request_json() {
  local method="$1"
  local path="$2"
  local payload="${3-}"
  local tmp_file curl_error_file http_code curl_rc

  ONLYMACS_LAST_HTTP_STATUS=""
  ONLYMACS_LAST_HTTP_BODY=""
  ONLYMACS_LAST_CURL_ERROR=""
  tmp_file="$(mktemp)"
  curl_error_file="$(mktemp)"

  if [[ -n "$payload" ]]; then
    if http_code="$(curl -sS -X "$method" -H 'Content-Type: application/json' -d "$payload" -o "$tmp_file" -w '%{http_code}' "${BASE_URL}${path}" 2>"$curl_error_file")"; then
      curl_rc=0
    else
      curl_rc=$?
    fi
  else
    if http_code="$(curl -sS -X "$method" -o "$tmp_file" -w '%{http_code}' "${BASE_URL}${path}" 2>"$curl_error_file")"; then
      curl_rc=0
    else
      curl_rc=$?
    fi
  fi

  if [[ -f "$tmp_file" ]]; then
    ONLYMACS_LAST_HTTP_BODY="$(cat "$tmp_file")"
    rm -f "$tmp_file"
  fi

  if [[ "$curl_rc" -ne 0 ]]; then
    rm -f "$tmp_file" "$curl_error_file"
    if [[ "${ONLYMACS_REQUEST_JSON_RETRYING:-0}" != "1" ]] && bridge_base_url_is_app_managed_local; then
      printf 'OnlyMacs is waking the app-managed bridge on %s...\n' "$BASE_URL" >&2
      if wake_onlymacs_app && wait_for_local_bridge_ready; then
        local retry_rc previous_retry="${ONLYMACS_REQUEST_JSON_RETRYING:-}"
        ONLYMACS_REQUEST_JSON_RETRYING=1
        request_json "$method" "$path" "$payload"
        retry_rc=$?
        if [[ -n "$previous_retry" ]]; then
          ONLYMACS_REQUEST_JSON_RETRYING="$previous_retry"
        else
          unset ONLYMACS_REQUEST_JSON_RETRYING
        fi
        return "$retry_rc"
      fi
    fi
    ONLYMACS_LAST_CURL_ERROR="Unable to reach the local OnlyMacs bridge at ${BASE_URL}. Open the OnlyMacs app and try again."
    return 1
  fi

  rm -f "$curl_error_file"
  ONLYMACS_LAST_HTTP_STATUS="$http_code"
  return 0
}

emit_output() {
  local formatter="$1"
  local body="$2"
  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    printf '%s\n' "$body"
    return 0
  fi
  "$formatter" "$body"
}

pretty_error() {
  local fallback_message="${1:-OnlyMacs request failed.}"
  if [[ -n "$ONLYMACS_LAST_CURL_ERROR" ]]; then
    record_current_activity "failed" "$ONLYMACS_LAST_CURL_ERROR" "" ""
    printf 'OnlyMacs could not connect.\n%s\n' "$ONLYMACS_LAST_CURL_ERROR" >&2
    printf 'Next: open the OnlyMacs app, wait for it to show ready, then run %s check\n' "$ONLYMACS_WRAPPER_NAME" >&2
    return 1
  fi

  if [[ -n "$ONLYMACS_LAST_HTTP_BODY" ]] && jq -e . >/dev/null 2>&1 <<<"$ONLYMACS_LAST_HTTP_BODY"; then
    local code message
    code="$(jq -r '.error.code // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    message="$(jq -r '.error.message // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
    record_current_activity "failed" "${message:-$fallback_message}" "" ""
    printf 'OnlyMacs request failed'
    if [[ -n "$code" ]]; then
      printf ' [%s]' "$code"
    fi
    printf '.\n'
    if [[ -n "$message" ]]; then
      printf '%s\n' "$message" >&2
    else
      printf '%s\n' "$fallback_message" >&2
    fi
  else
    printf '%s\n' "$fallback_message" >&2
    if [[ -n "$ONLYMACS_LAST_HTTP_BODY" ]]; then
      printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY" >&2
    fi
  fi
  return 1
}

require_success() {
  local fallback_message="$1"
  if [[ -z "$ONLYMACS_LAST_HTTP_STATUS" ]]; then
    pretty_error "$fallback_message"
    return 1
  fi
  if [[ "$ONLYMACS_LAST_HTTP_STATUS" =~ ^2 ]]; then
    return 0
  fi
  pretty_error "$fallback_message"
  return 1
}

human_queue_reason() {
  case "${1:-}" in
    premium_cooldown)
      echo "a scarce premium slot was just released, so OnlyMacs is giving it a short cooldown before the same requester grabs it again"
      ;;
    premium_budget)
      echo "this workspace or thread already has enough scarce premium work in flight"
      ;;
    requester_budget)
      echo "this workspace or thread already has enough queued swarms waiting"
      ;;
    member_cap)
      echo "this swarm member already has enough live request slots in flight"
      ;;
    premium_contention)
      echo "a scarce premium slot is busy, so OnlyMacs is waiting for the next premium opening or strong fallback window"
      ;;
    swarm_capacity)
      echo "the swarm does not have enough free slots right now"
      ;;
    workspace_cap)
      echo "this workspace already has as much swarm width as OnlyMacs allows by default"
      ;;
    thread_cap)
      echo "this chat thread already has as much swarm width as OnlyMacs allows by default"
      ;;
    global_cap)
      echo "OnlyMacs is already busy across the local machine"
      ;;
    manual_pause)
      echo "the session is paused"
      ;;
    cancelled)
      echo "the session was cancelled"
      ;;
    model_unavailable)
      echo "the requested model is not available right now"
      ;;
    trust_scope)
      echo "the chosen trust scope does not have a matching open model right now"
      ;;
    requested_width)
      echo "OnlyMacs intentionally admitted a narrower swarm than you asked for"
      ;;
    stale_queue)
      echo "one or more queued swarms has been sitting long enough that it should probably be refreshed"
      ;;
    *)
      echo "${1:-unknown reason}"
      ;;
  esac
}

format_queue_mix() {
  local member_cap="${1:-0}"
  local requester_budget="${2:-0}"
  local stale_queued="${3:-0}"
  local parts=()

  if [[ "$member_cap" -gt 0 ]]; then
    parts+=("${member_cap} member-budget hold")
  fi
  if [[ "$requester_budget" -gt 0 ]]; then
    parts+=("${requester_budget} requester-budget hold")
  fi
  if [[ "$stale_queued" -gt 0 ]]; then
    parts+=("${stale_queued} stale queued")
  fi

  if [[ "${#parts[@]}" -eq 0 ]]; then
    return 1
  fi

  local joined=""
  local part
  for part in "${parts[@]}"; do
    if [[ -n "$joined" ]]; then
      joined="${joined} • "
    fi
    joined="${joined}${part}"
  done
  printf '%s' "$joined"
}

human_route_scope() {
  case "${1:-swarm}" in
    local_only)
      echo "This Mac only"
      ;;
    trusted_only)
      echo "your Macs only"
      ;;
    *)
      echo "swarm"
      ;;
  esac
}

format_saved_tokens() {
  local safe_tokens="${1:-0}"
  if [[ -z "$safe_tokens" || ! "$safe_tokens" =~ ^[0-9]+$ ]]; then
    safe_tokens=0
  fi
  if (( safe_tokens < 10000 )); then
    printf '%s' "$safe_tokens"
  elif (( safe_tokens < 1000000 )); then
    printf '%sK+' "$(( (safe_tokens / 10000) * 10 ))"
  elif (( safe_tokens < 10000000 )); then
    printf '%sM+' "$(( safe_tokens / 1000000 ))"
  elif (( safe_tokens < 1000000000 )); then
    printf '%sM' "$(( safe_tokens / 1000000 ))"
  else
    awk -v n="$safe_tokens" 'BEGIN { printf "%.2fB", n / 1000000000 }'
  fi
}

format_community_boost() {
  local level="${1:-3}"
  local label="${2:-Standard}"
  printf '%s/5 %s' "$level" "$label"
}

clear_if_interactive() {
  if [[ -t 1 ]]; then
    if command -v clear >/dev/null 2>&1; then
      clear >/dev/null 2>&1 || printf '\033[2J\033[H'
    else
      printf '\033[2J\033[H'
    fi
  fi
}

format_system_status() {
  local body="$1"
  local bridge_status mode swarm_name providers models active_sessions queued_sessions sharing_state
  local tokens_saved downloaded uploaded boost_level boost_label boost_trait
  local active_reservations reservation_cap
  local queue_reason queue_detail queue_action queue_eta
  local queue_member_cap queue_requester_budget queue_stale
  bridge_status="$(jq -r '.bridge.status // "unknown"' <<<"$body")"
  mode="$(jq -r '.runtime.mode // "unknown"' <<<"$body")"
  swarm_name="$(jq -r '.bridge.active_swarm_name // .runtime.active_swarm_id // empty' <<<"$body")"
  providers="$(jq -r '
    if (.swarm.provider_count? // null) != null then
      .swarm.provider_count
    elif (.providers | type) == "array" then
      (.providers | length)
    elif (.members | type) == "array" then
      ([.members[]? | (.provider_total // ((.capabilities // []) | length) // 0)] | add // 0)
    else
      0
    end
  ' <<<"$body")"
  models="$(jq -r '.swarm.model_count // 0' <<<"$body")"
  active_sessions="$(jq -r '.swarm.active_session_count // 0' <<<"$body")"
  queued_sessions="$(jq -r '.swarm.queued_session_count // 0' <<<"$body")"
  sharing_state="$(jq -r '.sharing.status // "idle"' <<<"$body")"
  tokens_saved="$(jq -r '.usage.tokens_saved_estimate // 0' <<<"$body")"
  downloaded="$(jq -r '.usage.downloaded_tokens_estimate // 0' <<<"$body")"
  uploaded="$(jq -r '.usage.uploaded_tokens_estimate // 0' <<<"$body")"
  active_reservations="$(jq -r '.usage.active_reservations // 0' <<<"$body")"
  reservation_cap="$(jq -r '.usage.reservation_cap // 0' <<<"$body")"
  boost_level="$(jq -r '.usage.community_boost.level // 3' <<<"$body")"
  boost_label="$(jq -r '.usage.community_boost.label // "Steady"' <<<"$body")"
  boost_trait="$(jq -r '.usage.community_boost.primary_trait // empty' <<<"$body")"
  queue_reason="$(jq -r '.swarm.queue_summary.primary_reason // empty' <<<"$body")"
  queue_detail="$(jq -r '.swarm.queue_summary.primary_detail // empty' <<<"$body")"
  queue_action="$(jq -r '.swarm.queue_summary.suggested_action // empty' <<<"$body")"
  queue_eta="$(jq -r '.swarm.queue_summary.next_eta_seconds // 0' <<<"$body")"
  queue_member_cap="$(jq -r '.swarm.queue_summary.member_cap_count // 0' <<<"$body")"
  queue_requester_budget="$(jq -r '.swarm.queue_summary.requester_budget_count // 0' <<<"$body")"
  queue_stale="$(jq -r '.swarm.queue_summary.stale_queued_count // 0' <<<"$body")"

  printf 'OnlyMacs for %s\n' "$ONLYMACS_TOOL_NAME"
  printf 'Bridge: %s\n' "$bridge_status"
  printf 'Mode: %s\n' "$mode"
  if [[ -n "$swarm_name" && "$swarm_name" != "null" ]]; then
    printf 'Swarm: %s\n' "$swarm_name"
  else
    printf 'Swarm: none selected\n'
  fi
  printf 'Providers: %s\n' "$providers"
  printf 'Models: %s\n' "$models"
  printf 'Active swarms: %s\n' "$active_sessions"
  printf 'Queued swarms: %s\n' "$queued_sessions"
  if [[ "$queued_sessions" -gt 0 && -n "$queue_reason" ]]; then
    printf 'Queue pressure: %s\n' "$(human_queue_reason "$queue_reason")"
    if [[ -n "$queue_detail" ]]; then
      printf 'Queue detail: %s\n' "$queue_detail"
    fi
    if queue_mix="$(format_queue_mix "$queue_member_cap" "$queue_requester_budget" "$queue_stale")"; then
      printf 'Queue mix: %s\n' "$queue_mix"
    fi
    if [[ "$queue_eta" -gt 0 ]]; then
      printf 'Next queue ETA: %ss\n' "$queue_eta"
    fi
    if [[ -n "$queue_action" ]]; then
      printf 'Suggested action: %s\n' "$queue_action"
    fi
  fi
  printf 'Sharing: %s\n' "$sharing_state"
  printf 'Tokens Saved: %s\n' "$(format_saved_tokens "$tokens_saved")"
  printf 'Downloaded: %s\n' "$(format_saved_tokens "$downloaded")"
  printf 'Uploaded: %s\n' "$(format_saved_tokens "$uploaded")"
  if [[ "$reservation_cap" -gt 0 ]]; then
    printf 'Swarm Budget: %s/%s live reservations\n' "$active_reservations" "$reservation_cap"
  fi
  printf 'Community Boost: %s' "$(format_community_boost "$boost_level" "$boost_label")"
  if [[ -n "$boost_trait" ]]; then
    printf ' (%s)' "$boost_trait"
  fi
  printf '\n'
  local latest_title latest_status latest_model
  latest_title="$(jq -r '.swarm.recent_sessions[0].title // .swarm.recent_sessions[0].id // empty' <<<"$body")"
  latest_status="$(jq -r '.swarm.recent_sessions[0].status // empty' <<<"$body")"
  latest_model="$(jq -r '.swarm.recent_sessions[0].resolved_model // empty' <<<"$body")"
  if [[ -n "$latest_title" ]]; then
    printf 'Latest swarm: %s' "$latest_title"
    if [[ -n "$latest_status" ]]; then
      printf ' (%s' "$latest_status"
      if [[ -n "$latest_model" ]]; then
        printf ', %s' "$latest_model"
      fi
      printf ')'
    fi
    printf '\n'
  fi

  if [[ "$bridge_status" == "ready" && "$providers" -gt 0 && "$models" -gt 0 ]]; then
    printf '\nReady to go.\n'
    printf 'Next: %s demo\n' "$ONLYMACS_WRAPPER_NAME"
  else
    printf '\nNot fully ready yet.\n'
    if [[ -z "$swarm_name" || "$swarm_name" == "null" ]]; then
      printf 'Next: open the OnlyMacs app and create or join a swarm.\n'
    elif [[ "$models" -eq 0 ]]; then
      printf 'Next: publish models from This Mac or wait for a friend to share capacity.\n'
    else
      printf 'Next: run %s doctor for more detail.\n' "$ONLYMACS_WRAPPER_NAME"
    fi
  fi
}

format_models() {
  local body="$1"
  local count
  count="$(jq -r '.models | length' <<<"$body")"
  printf 'Visible models: %s\n' "$count"
  jq -r '.models[]? | "- \(.id) (\(.slots_free)/\(.slots_total) free)"' <<<"$body"
}

format_swarms() {
  local body="$1"
  local count
  count="$(jq -r '.swarms | length' <<<"$body")"
  printf 'Swarms: %s\n' "$count"
  jq -r '.swarms[]? | "- \(.name) [\(.id)] \((.provider_count // .slots_total // 0)) providers, \((.member_count // 0)) members"' <<<"$body"
}

format_preflight() {
  local body="$1"
  local requested resolved available providers selection route_scope
  requested="$(jq -r '.requested_model // empty' <<<"$body")"
  resolved="$(jq -r '.resolved_model // empty' <<<"$body")"
  available="$(jq -r '.available // false' <<<"$body")"
  providers="$(jq -r '.totals.providers // 0' <<<"$body")"
  selection="$(jq -r '.selection_explanation // empty' <<<"$body")"
  route_scope="$(jq -r '.route_scope // "swarm"' <<<"$body")"

  printf 'Preflight\n'
  printf 'Requested: %s\n' "${requested:-best available}"
  printf 'Resolved: %s\n' "${resolved:-none}"
  printf 'Route scope: %s\n' "$(human_route_scope "$route_scope")"
  printf 'Available: %s\n' "$available"
  printf 'Providers able to serve it now: %s\n' "$providers"
  if [[ -n "$selection" ]]; then
    printf 'Why this model: %s\n' "$selection"
  fi
  if [[ "$available" == "true" ]]; then
    printf 'Next: %s start %s 1 "your prompt"\n' "$ONLYMACS_WRAPPER_NAME" "${resolved:-best-available}"
  else
    printf 'Next: %s models\n' "$ONLYMACS_WRAPPER_NAME"
  fi
}

format_plan() {
  local body="$1"
  local title requested resolved requested_agents admitted queued eta reason warnings selection route_scope strategy capability_count
  title="$(jq -r '.title // empty' <<<"$body")"
  requested="$(jq -r '.requested_model // empty' <<<"$body")"
  resolved="$(jq -r '.resolved_model // empty' <<<"$body")"
  route_scope="$(jq -r '.route_scope // "swarm"' <<<"$body")"
  strategy="$(jq -r '.strategy // "single_best"' <<<"$body")"
  requested_agents="$(jq -r '.requested_agents // 0' <<<"$body")"
  admitted="$(jq -r '.admitted_agents // 0' <<<"$body")"
  queued="$(jq -r '.queue_remainder // 0' <<<"$body")"
  eta="$(jq -r '.eta_seconds // 0' <<<"$body")"
  reason="$(jq -r '.queue_reason // empty' <<<"$body")"
  selection="$(jq -r '.selection_explanation // empty' <<<"$body")"
  warnings="$(jq -r '.warnings[]? // empty' <<<"$body")"

  if [[ -n "$title" ]]; then
    printf 'Plan: %s\n' "$title"
  else
    printf 'Plan\n'
  fi
  printf 'Requested model: %s\n' "${requested:-best available}"
  printf 'Resolved model: %s\n' "${resolved:-none}"
  printf 'Route scope: %s\n' "$(human_route_scope "$route_scope")"
  printf 'Strategy: %s\n' "$strategy"
  printf 'Agents: %s requested, %s admitted\n' "$requested_agents" "$admitted"
  capability_count="$(jq -r '.capability_matrix | length // 0' <<<"$body" 2>/dev/null || printf '0')"
  if [[ "$capability_count" -gt 0 ]]; then
    printf 'Capability plan:\n'
    jq -r '.capability_matrix[]? | "  - " + ((.owner_member_name // .provider_name // .provider_id) | tostring) + ": " + (.suggested_role // "worker") + " / " + (.best_model // "model pending") + (if (.memory_gb // 0) > 0 or ((.cpu // "") | length) > 0 then " / " + ((.memory_gb // 0 | tostring) + "GB " + (.cpu // "") | gsub("^0GB $"; "") | gsub("^0GB "; "") | gsub(" $"; "")) else "" end)' <<<"$body"
  fi
  if [[ "$queued" -gt 0 ]]; then
    printf 'Queued: %s waiting because %s' "$queued" "$(human_queue_reason "$reason")"
    if [[ "$eta" -gt 0 ]]; then
      printf ' (rough ETA %ss)' "$eta"
    fi
    printf '.\n'
  fi
  if [[ -n "$warnings" ]]; then
    printf '\nNotes:\n'
    jq -r '.warnings[]? | "- " + .' <<<"$body"
  fi
  if [[ -n "$selection" ]]; then
    printf '\nWhy this model: %s\n' "$selection"
  fi
  printf '\nNext: %s start %s %s "your prompt"\n' "$ONLYMACS_WRAPPER_NAME" "${resolved:-best-available}" "$requested_agents"
}

format_session() {
  local body="$1"
  local session_count
  session_count="$(jq -r '.sessions | length' <<<"$body")"
  if [[ "$session_count" -eq 0 ]]; then
    printf 'No matching swarm session found.\n'
    return 0
  fi

  local title session_id status resolved requested admitted finished queued reason eta route selection saved route_scope warnings
  local checkpoint_status checkpoint_preview checkpoint_error
  title="$(jq -r '.sessions[0].title // empty' <<<"$body")"
  session_id="$(jq -r '.sessions[0].id' <<<"$body")"
  status="$(jq -r '.sessions[0].status' <<<"$body")"
  resolved="$(jq -r '.sessions[0].resolved_model // empty' <<<"$body")"
  route_scope="$(jq -r '.sessions[0].route_scope // "swarm"' <<<"$body")"
  requested="$(jq -r '.sessions[0].requested_agents // 0' <<<"$body")"
  admitted="$(jq -r '.sessions[0].admitted_agents // 0' <<<"$body")"
  finished="$(jq -r '.sessions[0].reservations | length // 0' <<<"$body")"
  queued="$(jq -r '.sessions[0].queue_remainder // 0' <<<"$body")"
  reason="$(jq -r '.sessions[0].queue_reason // empty' <<<"$body")"
  eta="$(jq -r '.sessions[0].eta_seconds // 0' <<<"$body")"
  route="$(jq -r '.sessions[0].route_summary // empty' <<<"$body")"
  selection="$(jq -r '.sessions[0].selection_explanation // empty' <<<"$body")"
  saved="$(jq -r '.sessions[0].saved_tokens_estimate // 0' <<<"$body")"
  warnings="$(jq -r '.sessions[0].warnings[]? // empty' <<<"$body")"
  checkpoint_status="$(jq -r '.sessions[0].checkpoint.status // empty' <<<"$body")"
  checkpoint_preview="$(jq -r '.sessions[0].checkpoint.output_preview // empty' <<<"$body")"
  checkpoint_error="$(jq -r '.sessions[0].checkpoint.last_error // empty' <<<"$body")"

  printf 'Swarm %s' "$session_id"
  if [[ -n "$title" ]]; then
    printf ' - %s' "$title"
  fi
  printf '\n'
  printf 'Status: %s\n' "$status"
  printf 'Model: %s\n' "${resolved:-none}"
  printf 'Route scope: %s\n' "$(human_route_scope "$route_scope")"
  case "$status" in
    completed|failed)
      printf 'Agents: %s requested, %s finished\n' "$requested" "$finished"
      ;;
    *)
      printf 'Agents: %s requested, %s active\n' "$requested" "$admitted"
      ;;
  esac
  case "$status" in
    running)
      if [[ "$queued" -gt 0 ]]; then
        printf 'Queued: %s because %s' "$queued" "$(human_queue_reason "$reason")"
        if [[ "$eta" -gt 0 ]]; then
          printf ' (rough ETA %ss)' "$eta"
        fi
        printf '\n'
      fi
      ;;
    queued)
      printf 'Waiting: %s' "$(human_queue_reason "$reason")"
      if [[ "$eta" -gt 0 ]]; then
        printf ' (rough ETA %ss)' "$eta"
      fi
      printf '\n'
      ;;
    paused)
      printf 'Paused: %s\n' "$(human_queue_reason "$reason")"
      ;;
    cancelled)
      printf 'Stopped: reservations were released.\n'
      ;;
    *)
      if [[ "$queued" -gt 0 ]]; then
        printf 'Queued: %s because %s\n' "$queued" "$(human_queue_reason "$reason")"
      fi
      ;;
  esac

  local providers
  providers="$(jq -r '.sessions[0].reservations[]?.provider_name // empty' <<<"$body" | paste -sd ', ' -)"
  if [[ -n "$providers" ]]; then
    printf 'Providers: %s\n' "$providers"
  fi
  if [[ -n "$route" ]]; then
    printf 'Route: %s\n' "$route"
  fi
  if [[ -n "$selection" ]]; then
    printf 'Why this model: %s\n' "$selection"
  fi
  if [[ -n "$checkpoint_preview" ]]; then
    case "$checkpoint_status" in
      completed)
        printf 'Result:\n%s\n' "$checkpoint_preview"
        ;;
      failed)
        printf 'Failure:\n%s\n' "$checkpoint_preview"
        ;;
      running|resumed)
        printf 'Progress:\n%s\n' "$checkpoint_preview"
        ;;
      *)
        printf 'Checkpoint:\n%s\n' "$checkpoint_preview"
        ;;
    esac
  fi
  if [[ -n "$checkpoint_error" && "$checkpoint_error" != "$checkpoint_preview" ]]; then
    printf 'Error: %s\n' "$checkpoint_error"
  fi
  if [[ -n "$warnings" ]]; then
    printf 'Notes:\n'
    jq -r '.sessions[0].warnings[]? | "- " + .' <<<"$body"
  fi
  if [[ "$saved" -gt 0 ]]; then
    printf 'Saved tokens: %s\n' "$(format_saved_tokens "$saved")"
  fi

  if [[ "$status" == "running" ]]; then
    printf '\nNext: %s watch %s\n' "$ONLYMACS_WRAPPER_NAME" "$session_id"
  elif [[ "$status" == "paused" ]]; then
    printf '\nNext: %s resume %s\n' "$ONLYMACS_WRAPPER_NAME" "$session_id"
  elif [[ "$status" == "queued" ]]; then
    printf '\nNext: %s queue %s\n' "$ONLYMACS_WRAPPER_NAME" "$session_id"
  fi
}

resolve_session_reference() {
  local requested="${1:-}"
  case "$requested" in
    "" )
      printf '%s\n' ""
      return 0
      ;;
    latest|current)
      request_json GET "/admin/v1/swarm/sessions" || return 1
      require_success "Could not list swarm sessions." || return 1
      local session_id
      if [[ "$requested" == "current" ]]; then
        session_id="$(jq -r --arg workspace "$(default_workspace_id)" --arg thread "$(default_thread_id)" '
          [ .sessions[]
            | select((.workspace_id // "") == $workspace and (.thread_id // "") == $thread)
          ][-1].id // empty
        ' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      else
        session_id="$(jq -r '.sessions[-1].id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      fi
      if [[ -z "$session_id" ]]; then
        printf 'OnlyMacs could not find a %s swarm session yet.\n' "$requested" >&2
        printf 'Next: %s "review this patch"\n' "$ONLYMACS_WRAPPER_NAME" >&2
        return 1
      fi
      printf '%s\n' "$session_id"
      return 0
      ;;
    *)
      printf '%s\n' "$requested"
      return 0
      ;;
  esac
}

format_queue() {
  local body="$1"
  local queued active queue_reason queue_detail queue_action next_eta
  local queue_member_cap queue_requester_budget queue_stale
  queued="$(jq -r '.queued_session_count // 0' <<<"$body")"
  active="$(jq -r '.active_session_count // 0' <<<"$body")"
  queue_reason="$(jq -r '.queue_summary.primary_reason // empty' <<<"$body")"
  queue_detail="$(jq -r '.queue_summary.primary_detail // empty' <<<"$body")"
  queue_action="$(jq -r '.queue_summary.suggested_action // empty' <<<"$body")"
  next_eta="$(jq -r '.queue_summary.next_eta_seconds // 0' <<<"$body")"
  queue_member_cap="$(jq -r '.queue_summary.member_cap_count // 0' <<<"$body")"
  queue_requester_budget="$(jq -r '.queue_summary.requester_budget_count // 0' <<<"$body")"
  queue_stale="$(jq -r '.queue_summary.stale_queued_count // 0' <<<"$body")"
  printf 'Queue\n'
  printf 'Queued sessions: %s\n' "$queued"
  printf 'Active sessions: %s\n' "$active"
  if [[ "$queued" -gt 0 && -n "$queue_reason" ]]; then
    printf 'Primary pressure: %s\n' "$(human_queue_reason "$queue_reason")"
    if [[ -n "$queue_detail" ]]; then
      printf 'Detail: %s\n' "$queue_detail"
    fi
    if queue_mix="$(format_queue_mix "$queue_member_cap" "$queue_requester_budget" "$queue_stale")"; then
      printf 'Queue mix: %s\n' "$queue_mix"
    fi
    if [[ "$next_eta" -gt 0 ]]; then
      printf 'Next ETA: %ss\n' "$next_eta"
    fi
    if [[ -n "$queue_action" ]]; then
      printf 'Suggested action: %s\n' "$queue_action"
    fi
  fi
  if [[ "$queued" -gt 0 ]]; then
    jq -r '.sessions[]? | "- \(.id): \((.title // "untitled")) waiting because " + (.queue_reason // "unknown") + (if (.eta_seconds // 0) > 0 then " (ETA " + ((.eta_seconds|tostring)) + "s)" else "" end)' <<<"$body" |
      while IFS= read -r line; do
        local raw_reason
        raw_reason="$(printf '%s' "$line" | sed -E 's/.* waiting because ([^ ]+).*/\1/')"
        if [[ "$raw_reason" != "$line" ]]; then
          printf '%s\n' "${line/$raw_reason/$(human_queue_reason "$raw_reason")}"
        else
          printf '%s\n' "$line"
        fi
      done
  else
    printf 'Nothing is waiting right now.\n'
  fi
}

format_start() {
  local body="$1"
  local session_id duplicate title status
  session_id="$(jq -r '.session.id' <<<"$body")"
  duplicate="$(jq -r '.duplicate // false' <<<"$body")"
  title="$(jq -r '.session.title // empty' <<<"$body")"
  status="$(jq -r '.session.status // empty' <<<"$body")"

  if [[ "$duplicate" == "true" ]]; then
    printf 'Reused existing swarm session %s' "$session_id"
  else
    printf 'Started swarm session %s' "$session_id"
  fi
  if [[ -n "$title" ]]; then
    printf ' - %s' "$title"
  fi
  printf '\n'

  format_session "$(jq '{sessions:[.session]}' <<<"$body")"
}

format_action_result() {
  local action_label="$1"
  local body="$2"
  local session_id title
  session_id="$(jq -r '.session.id' <<<"$body")"
  title="$(jq -r '.session.title // empty' <<<"$body")"
  printf '%s swarm session %s' "$action_label" "$session_id"
  if [[ -n "$title" ]]; then
    printf ' - %s' "$title"
  fi
  printf '\n'
  format_session "$(jq '{sessions:[.session]}' <<<"$body")"
}

format_doctor() {
  local body="$1"
  format_system_status "$body"
  printf '\nInstall path: %s\n' "$ONLYMACS_WRAPPER_NAME"
  printf 'Friendly commands: check, demo, go, chat, watch, pause, resume, stop\n'
}
