#!/usr/bin/env bash

ONLYMACS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-shared.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-routing.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-access.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-transport.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-artifacts.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-execution-state.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-artifact-validation.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-run-status.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-orchestration.sh"

if [[ "${ONLYMACS_ENABLE_CONTENT_PIPELINE_VALIDATORS:-0}" == "1" ]]; then
  ONLYMACS_CONTENT_PIPELINE_VALIDATORS_PATH="${ONLYMACS_CONTENT_PIPELINE_VALIDATORS_PATH:-${ONLYMACS_SCRIPT_DIR}/../content-pipeline/onlymacs-content-pipeline-validation.sh}"
  if [[ -f "$ONLYMACS_CONTENT_PIPELINE_VALIDATORS_PATH" ]]; then
    # shellcheck source=/dev/null
    source "$ONLYMACS_CONTENT_PIPELINE_VALIDATORS_PATH"
  fi
fi

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-run-commands.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-chat-runtime.sh"

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-command-handlers.sh"

onlymacs_cli_main() {
  ONLYMACS_TOOL_NAME="$1"
  ONLYMACS_WRAPPER_NAME="$2"
  shift 2
  ONLYMACS_INVOCATION_LABEL="$(onlymacs_format_invocation "$ONLYMACS_WRAPPER_NAME" "$@")"

  parse_leading_options "$@" || return 1
  if ((${#ONLYMACS_PARSED_ARGS[@]} > 0)); then
    set -- "${ONLYMACS_PARSED_ARGS[@]}"
  else
    set --
  fi
  if [[ -n "${ONLYMACS_FORCE_PRESET:-}" && $# -gt 0 ]] && ! known_action "${1:-}"; then
    case "${ONLYMACS_FORCE_ACTION:-chat}" in
      go)
        if [[ -n "${ONLYMACS_PLAN_FILE_PATH:-}" || "${ONLYMACS_EXECUTION_MODE:-auto}" == "extended" || "${ONLYMACS_EXECUTION_MODE:-auto}" == "overnight" ]]; then
          set -- chat "$ONLYMACS_FORCE_PRESET" "$@"
        else
          set -- go "$ONLYMACS_FORCE_PRESET" "$@"
        fi
        ;;
      *)
        set -- chat "$ONLYMACS_FORCE_PRESET" "$@"
        ;;
    esac
  fi

  local action="${1:-help}"
  shift || true

  if ! known_action "$action"; then
    if resolve_natural_language_command "$action" "$@"; then
      if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf 'OnlyMacs interpreted this as: %s\n' "$ONLYMACS_ROUTER_INTERPRETATION"
        if [[ -n "${ONLYMACS_ROUTER_REASON:-}" ]]; then
          printf 'Why: %s\n' "$ONLYMACS_ROUTER_REASON"
        fi
        printf '\n'
      fi
      set -- "${ONLYMACS_ROUTED_ARGS[@]}"
      action="${1:-help}"
      shift || true
    fi
  fi

  if [[ -n "${ONLYMACS_FORCE_PRESET:-}" ]]; then
    case "$action" in
      chat|plan|start)
        if [[ $# -eq 0 ]] || ! chat_arg_looks_like_route_or_model "${1:-}"; then
          set -- "$ONLYMACS_FORCE_PRESET" "$@"
        fi
        ;;
      go)
        if [[ $# -eq 0 ]] || ! chat_arg_looks_like_route_or_model "${1:-}"; then
          set -- "$ONLYMACS_FORCE_PRESET" "$@"
        fi
        ;;
    esac
  fi

  case "$action" in
    help|"")
      print_help
      ;;
    version)
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        jq -n --arg validator_version "$(onlymacs_validator_version)" '{tool:"OnlyMacs",validator_version:$validator_version}'
      else
        printf 'OnlyMacs\n'
        printf 'Validator: %s\n' "$(onlymacs_validator_version)"
      fi
      ;;
    check|doctor|make-ready)
      run_doctor
      ;;
    status)
      if [[ -n "${1:-}" ]]; then
        local session_ref
        session_ref="$(resolve_session_reference "$1")" || return 1
        set_activity_context "status ${1}" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "" ""
        request_json GET "/admin/v1/swarm/sessions?session_id=${session_ref}" || return 1
        require_success "Could not inspect the swarm session." || return 1
        ONLYMACS_ACTIVITY_MODEL="$(jq -r '.sessions[0].resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        ONLYMACS_ACTIVITY_ROUTE_SCOPE="$(jq -r '.sessions[0].route_scope // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        record_current_activity \
          "observed" \
          "$(jq -r '.sessions[0].selection_explanation // .sessions[0].route_summary // "Inspected the latest swarm status."' <<<"$ONLYMACS_LAST_HTTP_BODY")" \
          "$(jq -r '.sessions[0].id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")" \
          "$(jq -r '.sessions[0].status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        emit_output format_session "$ONLYMACS_LAST_HTTP_BODY"
      else
        set_activity_context "status" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "" ""
        request_json GET "/admin/v1/status" || return 1
        require_success "Could not inspect the local OnlyMacs status." || return 1
        record_current_activity "observed" "$(jq -r '.bridge.status // "unknown"' <<<"$ONLYMACS_LAST_HTTP_BODY")" "" ""
        emit_output format_system_status "$ONLYMACS_LAST_HTTP_BODY"
      fi
      ;;
    runtime)
      request_json GET "/admin/v1/runtime" || return 1
      require_success "Could not read the runtime mode." || return 1
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
      else
        printf 'Runtime\n'
        printf 'Mode: %s\n' "$(jq -r '.mode // "unknown"' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        printf 'Active swarm: %s\n' "$(jq -r '.active_swarm_id // "none"' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      fi
      ;;
    sharing)
      request_json GET "/admin/v1/status" || return 1
      require_success "Could not read sharing state." || return 1
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
      else
        printf 'Sharing\n'
        printf 'State: %s\n' "$(jq -r '.sharing.status // "unknown"' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        printf 'Active swarm: %s\n' "$(jq -r '.bridge.active_swarm_name // .runtime.active_swarm_id // "none"' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        printf 'Providers: %s\n' "$(jq -r '(.providers // []) | length' <<<"$ONLYMACS_LAST_HTTP_BODY")"
        printf 'Models: %s\n' "$(jq -r '(.models // .swarm.models // []) | length' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      fi
      ;;
    swarms)
      request_json GET "/admin/v1/swarms" || return 1
      require_success "Could not list swarms." || return 1
      emit_output format_swarms "$ONLYMACS_LAST_HTTP_BODY"
      ;;
    models)
      request_json GET "/admin/v1/models" || return 1
      require_success "Could not list visible models." || return 1
      emit_output format_models "$ONLYMACS_LAST_HTTP_BODY"
      ;;
    preflight)
      local model route_scope alias
      alias="${1:-}"
      model="$(resolve_model_for_preflight_or_chat "${1:-}")" || return 1
      route_scope="$(route_scope_for_alias "$alias")"
      set_activity_context "preflight ${alias:-best-available}" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "$route_scope" "$model"
      request_json POST "/admin/v1/preflight" "$(jq -n \
        --arg model "$model" \
        --arg route_scope "$route_scope" \
        --argjson prefer_remote "$(prefer_remote_for_alias "$alias" && printf 'true' || printf 'false')" \
        --argjson prefer_remote_soft "$(soft_prefer_remote_for_alias "$alias" && printf 'true' || printf 'false')" \
        '{model:$model,max_providers:1,route_scope:$route_scope,prefer_remote:$prefer_remote,prefer_remote_soft:$prefer_remote_soft}')" || return 1
      require_success "Could not preflight that model." || return 1
      ONLYMACS_ACTIVITY_MODEL="$(jq -r '.resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      record_current_activity "preflighted" "$(jq -r '.selection_explanation // "Checked OnlyMacs availability for this request."' <<<"$ONLYMACS_LAST_HTTP_BODY")" "" ""
      emit_output format_preflight "$ONLYMACS_LAST_HTTP_BODY"
      ;;
    benchmark)
      run_benchmark "$@"
      ;;
    watch-provider)
      run_watch_provider "$@"
      ;;
    plan)
      local model_alias="${1:-best-available}"
      shift || true
      parse_count_and_prompt 1 "$@"
      run_plan "$model_alias" "$ONLYMACS_PARSED_WIDTH" "$ONLYMACS_PARSED_PROMPT" "elastic" "plan $model_alias"
      ;;
    start)
      local model_alias="${1:-best-available}"
      shift || true
      parse_count_and_prompt 1 "$@"
      run_start "$model_alias" "$ONLYMACS_PARSED_WIDTH" "$ONLYMACS_PARSED_PROMPT" "elastic" "start $model_alias"
      ;;
    go)
      local preset="balanced"
      local explicit_preset=0
      local reused_workspace_default=0
      if [[ $# -gt 0 ]]; then
        case "$1" in
          quick|balanced|wide|go-wide|go_wide|local-first|local|trusted-only|trusted_only|trusted|offload-max|remote-first|remote-only|remote_only|remote|precise|best|coder|fast)
            preset="$1"
            if [[ "$preset" == "go-wide" || "$preset" == "go_wide" ]]; then
              preset="wide"
            fi
            if [[ "$preset" == "wide" ]]; then
              ONLYMACS_GO_WIDE_MODE=1
            fi
            explicit_preset=1
            shift
            ;;
        esac
      fi

      if [[ "$explicit_preset" -eq 0 ]]; then
        local workspace_preset
        workspace_preset="$(load_workspace_default_preset)"
        if workspace_default_reusable "$workspace_preset"; then
          preset="$workspace_preset"
          reused_workspace_default=1
        fi
      fi

      local default_width model_alias
      case "$preset" in
        quick)
          default_width=1
          model_alias="fast"
          ;;
        balanced)
          default_width=2
          model_alias="coder"
          ;;
        wide)
          default_width=4
          model_alias="best"
          ;;
        local-first|local)
          default_width=1
          model_alias="local-first"
          ;;
        trusted-only|trusted_only|trusted)
          default_width=1
          model_alias="trusted-only"
          ;;
        offload-max)
          default_width=1
          model_alias="offload-max"
          ;;
        remote-first|remote-only|remote_only|remote)
          default_width=1
          model_alias="remote-first"
          preset="remote-first"
          ;;
        precise)
          default_width=1
          model_alias="coder"
          ;;
        best|coder|fast)
          default_width=1
          model_alias="$preset"
          ;;
        *)
          default_width=2
          model_alias="coder"
          ;;
      esac
      if [[ "${ONLYMACS_GO_WIDE_MODE:-0}" == "1" && "$preset" != "wide" ]]; then
        default_width="$(orchestrated_go_wide_json_lanes "$model_alias")"
      fi
      if [[ "$reused_workspace_default" -eq 1 && "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf 'OnlyMacs reused your workspace default: %s\n\n' "$preset"
      fi
      parse_count_and_prompt "$default_width" "$@"
      run_start "$model_alias" "$ONLYMACS_PARSED_WIDTH" "$ONLYMACS_PARSED_PROMPT" "elastic" "go $preset"
      if [[ "$explicit_preset" -eq 1 ]]; then
        save_workspace_default_preset "$preset"
      fi
      ;;
    watch)
      if [[ -n "${1:-}" && "$1" != "queue" ]]; then
        local session_ref
        session_ref="$(resolve_session_reference "$1")" || return 1
        run_watch "$session_ref"
      else
        run_watch "${1:-}"
      fi
      ;;
    queue)
      set_activity_context "queue" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "" ""
      if [[ -n "${1:-}" ]]; then
        local session_ref
        session_ref="$(resolve_session_reference "$1")" || return 1
        request_json GET "/admin/v1/swarm/queue?session_id=${session_ref}" || return 1
      else
        request_json GET "/admin/v1/swarm/queue" || return 1
      fi
      require_success "Could not read the queue state." || return 1
      record_current_activity "observed" "$(jq -r '.queue_summary.primary_detail // "Inspected queue state."' <<<"$ONLYMACS_LAST_HTTP_BODY")" "" ""
      emit_output format_queue "$ONLYMACS_LAST_HTTP_BODY"
      ;;
    jobs|job|tickets|board)
      run_jobs "$@"
      ;;
    diagnostics)
      run_diagnostics "${1:-latest}"
      ;;
    support-bundle)
      run_support_bundle "${1:-latest}"
      ;;
    report)
      run_report "$@"
      ;;
    inbox)
      run_inbox_summary "${1:-latest}"
      ;;
    open)
      run_open_inbox "${1:-latest}"
      ;;
    apply)
      run_apply_inbox "${1:-latest}" "${2:-}"
      ;;
    pause|resume|cancel|stop)
      local action_name="$action"
      if [[ "$action_name" == "stop" ]]; then
        action_name="cancel"
      fi
      if [[ -z "${1:-}" ]]; then
        printf 'usage: %s %s <session-id|latest|current>\n' "$ONLYMACS_WRAPPER_NAME" "$action" >&2
        return 1
      fi
      local session_ref
      session_ref="$(resolve_session_reference "$1")" || return 1
      set_activity_context "$action ${1}" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "" ""
      request_json POST "/admin/v1/swarm/sessions/${action_name}" "$(jq -n --arg session_id "$session_ref" '{session_id:$session_id}')" || return 1
      require_success "Could not ${action_name} the swarm session." || return 1
      ONLYMACS_ACTIVITY_MODEL="$(jq -r '.session.resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      ONLYMACS_ACTIVITY_ROUTE_SCOPE="$(jq -r '.session.route_scope // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      record_current_activity \
        "${action_name}d" \
        "$(jq -r '.session.selection_explanation // .session.route_summary // "Updated swarm state."' <<<"$ONLYMACS_LAST_HTTP_BODY")" \
        "$(jq -r '.session.id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")" \
        "$(jq -r '.session.status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$ONLYMACS_LAST_HTTP_BODY"
      else
        case "$action_name" in
          pause)
            format_action_result "Paused" "$ONLYMACS_LAST_HTTP_BODY"
            ;;
          resume)
            format_action_result "Resumed" "$ONLYMACS_LAST_HTTP_BODY"
            ;;
          cancel)
            format_action_result "Stopped" "$ONLYMACS_LAST_HTTP_BODY"
            ;;
        esac
      fi
      ;;
    demo)
      set_activity_context "demo" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "swarm" ""
      run_demo
      ;;
    repair)
      run_doctor
      ;;
    resume-run)
      run_resume_orchestrated "${1:-latest}"
      ;;
    chat)
      local model prompt route_scope model_alias payload
      parse_chat_request "$@"
      model_alias="${ONLYMACS_CHAT_MODEL_ALIAS-}"
      prompt="${ONLYMACS_CHAT_PROMPT:-Reply with ONLYMACS_SMOKE_OK exactly.}"
      model="$(normalize_model_alias "$model_alias")"
      route_scope="$(route_scope_for_alias "$model_alias")"
      set_activity_context "chat ${model_alias:-best-available}" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "$route_scope" "$model"
      if ! compile_prompt_with_plan_file "$prompt"; then
        return 1
      fi
      prompt="${ONLYMACS_PLAN_COMPILED_PROMPT:-$prompt}"
      if ! resolve_prompt_with_file_access "$model_alias" "$prompt"; then
        return 1
      fi
      prompt="${ONLYMACS_RESOLVED_PROMPT:-$prompt}"
      if ! confirm_chat_launch "${model_alias:-best-available}" "$prompt"; then
        return 1
      fi
      record_current_activity "running" "Direct OnlyMacs chat is in progress." "" "running"
      if prompt_requests_extended_mode "$prompt"; then
        if ! run_orchestrated_chat "$model" "$model_alias" "$prompt" "$route_scope"; then
          record_current_activity "failed" "OnlyMacs orchestrated chat did not complete cleanly." "" ""
          return 1
        fi
      elif ! run_chat_with_context_loop "$model" "$model_alias" "$prompt" "$route_scope"; then
        record_current_activity "failed" "Direct OnlyMacs chat did not complete." "" ""
        return 1
      fi
      record_current_activity "streamed" "Sent a direct OnlyMacs chat request." "" ""
      ;;
    *)
      printf 'Unknown command: %s\n\n' "$action" >&2
      print_help >&2
      return 1
      ;;
  esac
}
parse_chat_request() {
  local candidate="${1:-}"
  local prompt=""
  local model_alias=""
  if [[ $# -gt 0 ]] && chat_arg_looks_like_route_or_model "$candidate"; then
    model_alias="$candidate"
    shift || true
  fi
  prompt="$*"
  if [[ -z "$prompt" ]]; then
    prompt="Reply with ONLYMACS_SMOKE_OK exactly."
  fi
  ONLYMACS_CHAT_MODEL_ALIAS="$model_alias"
  ONLYMACS_CHAT_PROMPT="$prompt"
}
