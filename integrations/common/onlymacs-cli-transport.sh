# Chat payload, routing-environment, and streaming transport helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after file-access helpers are loaded.

onlymacs_json_string_array_or_empty() {
  local raw="${1:-[]}"
  jq -c 'if type == "array" then [.[] | strings | gsub("^\\s+|\\s+$"; "") | select(length > 0)] else [] end' <<<"$raw" 2>/dev/null || printf '[]'
}

onlymacs_json_add_unique_string() {
  local raw="${1:-[]}"
  local value="${2:-}"
  raw="$(onlymacs_json_string_array_or_empty "$raw")"
  jq -c --arg value "$value" 'if ($value | length) > 0 then (. + [$value] | unique) else . end' <<<"$raw"
}

onlymacs_json_remove_string() {
  local raw="${1:-[]}"
  local value="${2:-}"
  raw="$(onlymacs_json_string_array_or_empty "$raw")"
  jq -c --arg value "$value" 'map(select(. != $value))' <<<"$raw"
}

onlymacs_json_contains_string() {
  local raw="${1:-[]}"
  local value="${2:-}"
  raw="$(onlymacs_json_string_array_or_empty "$raw")"
  jq -e --arg value "$value" 'index($value) != null' <<<"$raw" >/dev/null 2>&1
}

orchestrated_visible_route_provider_ids_json() {
  local active_model="${1:-}"
  local route_scope="${2:-swarm}"
  local body
  if [[ "$route_scope" == "local_only" ]]; then
    printf '[]'
    return 0
  fi
  body="$(onlymacs_fetch_admin_status)" || {
    printf '[]'
    return 1
  }
  jq -c --arg active_model "$active_model" '
    def provider_id: (.provider_id // .id // "");
    def provider_status: ((.status // "available") | ascii_downcase);
    def model_id: (.id // .name // "");
    def supports_model:
      ($active_model | length) == 0
      or any((.models // [])[]?; model_id == $active_model);
    [
      (.members[]?.capabilities[]?),
      (.providers[]?)
    ]
    | map(
        select(provider_id != "")
        | select(provider_status == "available")
        | select(supports_model)
        | provider_id
      )
    | unique
  ' <<<"$body" 2>/dev/null || printf '[]'
}

orchestrated_sanitize_go_wide_route_env() {
  local route_scope="${1:-swarm}"
  local active_model="${2:-}"
  local visible_json exclude_json excluded_count remaining_count
  orchestrated_go_wide_enabled "" || return 0
  [[ "${ONLYMACS_GO_WIDE_JOB_BOARD_WORKER:-0}" == "1" || "${ONLYMACS_GO_WIDE_ROUTE_LIST_SANITIZE:-0}" == "1" ]] || return 0
  [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" != "1" ]] || return 0
  [[ "$route_scope" != "local_only" ]] || return 0
  exclude_json="$(onlymacs_json_string_array_or_empty "${ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON:-[]}")"
  excluded_count="$(jq -r 'length' <<<"$exclude_json" 2>/dev/null || printf '0')"
  [[ "$excluded_count" =~ ^[0-9]+$ && "$excluded_count" -gt 0 ]] || return 0
  visible_json="$(orchestrated_visible_route_provider_ids_json "$active_model" "$route_scope" || printf '[]')"
  [[ "$(jq -r 'length' <<<"$visible_json" 2>/dev/null || printf '0')" -gt 0 ]] || return 0
  remaining_count="$(jq -r --argjson visible "$visible_json" --argjson excluded "$exclude_json" '
    [$visible[] | select(($excluded | index(.)) | not)] | length
  ' <<<"{}" 2>/dev/null || printf '0')"
  if [[ "$remaining_count" == "0" ]]; then
    ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON="[]"
    ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="[]"
    ONLYMACS_GO_WIDE_ROUTE_LISTS_SANITIZED=1
  fi
}

shape_prompt_for_resolved_artifact() {
  local prompt="${1:-}"
  local request_intent export_mode require_cross_file allow_context_requests

  if [[ -z "${ONLYMACS_RESOLVED_ARTIFACT_JSON:-}" ]]; then
    printf '%s' "$prompt"
    return 0
  fi

  request_intent="$(jq -r '.manifest.request_intent // .manifest.requestIntent // empty' <<<"$ONLYMACS_RESOLVED_ARTIFACT_JSON" 2>/dev/null || true)"
  export_mode="$(jq -r '.export_mode // .manifest.export_mode // .manifest.exportMode // empty' <<<"$ONLYMACS_RESOLVED_ARTIFACT_JSON" 2>/dev/null || true)"
  allow_context_requests="$(jq -r '.manifest.permissions.allow_context_requests // .manifest.permissions.allowContextRequests // false' <<<"$ONLYMACS_RESOLVED_ARTIFACT_JSON" 2>/dev/null || printf 'false')"
  require_cross_file="$(jq -r '
        [
      .manifest.files[]?
      | select((.status == "ready" or .status == "trimmed") and (
          (.review_priority // .reviewPriority // 0) >= 200
          or (.category // "") == "Master Docs"
          or (.category // "") == "Overview"
          or (.category // "") == "Source"
          or (.category // "") == "Config"
          or (.category // "") == "Scripts"
          or (.category // "") == "Schema"
        ))
    ] | length >= 2
  ' <<<"$ONLYMACS_RESOLVED_ARTIFACT_JSON" 2>/dev/null || printf 'false')"

  if [[ "$request_intent" == "grounded_code_review" ]]; then
    cat <<EOF
$prompt

Return a grounded code review with these sections in order:
Findings
Missing Tests
$([[ "$allow_context_requests" == "true" ]] && printf 'Context Requests\n')
Referenced Files

Return at most 3 findings total. Under Findings, use only [P1], [P2], or [P3] severity labels and do not invent P4 or higher. Prioritize behavioral bugs, regressions, risky assumptions, and missing tests over style-only feedback. For every finding, use this shape:
[P1] Short title
Evidence: exact/approved/path.ext:12-18 ("Quoted heading or snippet")
Impact: one concise sentence

For every Missing Tests item that is justified by the approved files, use this shape:
- Missing test short title
  Evidence: exact/approved/path.ext:12-18 ("Quoted heading or snippet")
  Why: one concise sentence

Weight stronger evidence first: Source, then Config, then Overview, then supporting docs. Do not use vague evidence like directory names or "various files". Do not critique OnlyMacs route labels, export metadata, or the review instructions themselves. Avoid generic filler and say plainly if the approved files are insufficient.
If Findings is "None.", Missing Tests still need Evidence lines when the gap is grounded in the approved files.
Always include every required section, even when there is nothing to add. Write "None." instead of omitting a required section.
$([[ "$require_cross_file" == "true" ]] && printf 'Include at least one finding that compares two approved files and calls out a contradiction, mismatch, or handoff gap between them.\n')
$([[ "$allow_context_requests" == "true" ]] && printf 'Use Context Requests only when more approved files are required. For each item, use this exact shape:\n- Need: short request\n  Why: one concise sentence\n  Suggested files: exact filenames or file types\nWrite "None." under Context Requests when the current bundle is sufficient.\n')
EOF
    return 0
  fi

  if [[ "$request_intent" == "grounded_generation" ]]; then
    cat <<EOF
$prompt

Return a grounded generation plan with these sections in order:
Proposed Output
Open Questions
$([[ "$allow_context_requests" == "true" ]] && printf 'Context Requests\n')
Referenced Files

Return at most 5 proposed outputs total. For every proposed output, use this shape:
Target: path/to/output.ext
Proposal: one concise sentence describing what to create
Evidence: exact/approved/path.ext:12-18 ("Quoted heading or snippet")

Weight schema, examples, and high-priority workflow docs above supporting files. Do not use vague evidence like directory names or "various files". Do not claim any file has already been created or saved. Say plainly under Open Questions if the approved files are insufficient.
Always include every required section, even when there is nothing to add. Write "None." instead of omitting a required section.
$([[ "$allow_context_requests" == "true" ]] && printf 'Use Context Requests only when more approved files are required. For each item, use this exact shape:\n- Need: short request\n  Why: one concise sentence\n  Suggested files: exact filenames or file types\nWrite "None." under Context Requests when the current bundle is sufficient.\n')
EOF
    return 0
  fi

  if [[ "$request_intent" == "grounded_transform" ]]; then
    cat <<EOF
$prompt

Return a grounded transform plan with these sections in order:
Proposed Changes
Open Questions
$([[ "$allow_context_requests" == "true" ]] && printf 'Context Requests\n')
Referenced Files

Return at most 5 proposed changes total. For every proposed change, use this shape:
Target: path/to/file.ext
Change: one concise sentence describing the edit
Evidence: exact/approved/path.ext:12-18 ("Quoted heading or snippet")

Prefer high-confidence changes that clearly follow from the approved schema, examples, source files, or docs. Do not use vague evidence like directory names or "various files". Do not claim any patch has already been applied. Say plainly under Open Questions if the approved files are insufficient.
Always include every required section, even when there is nothing to add. Write "None." instead of omitting a required section.
$([[ "$allow_context_requests" == "true" ]] && printf 'Use Context Requests only when more approved files are required. For each item, use this exact shape:\n- Need: short request\n  Why: one concise sentence\n  Suggested files: exact filenames or file types\nWrite "None." under Context Requests when the current bundle is sufficient.\n')
EOF
    return 0
  fi

  if [[ "$request_intent" == "grounded_review" || "$export_mode" == "trusted_review_full" ]]; then
    cat <<EOF
$prompt

Return a grounded review with these sections in order:
Findings
Open Questions
$([[ "$allow_context_requests" == "true" ]] && printf 'Context Requests\n')
Referenced Files

Return at most 3 findings total. Prefer contradictions, handoff mismatches, or state drift across approved files over single-file wording nits. Under Findings, use only [P1], [P2], or [P3] severity labels and do not invent P4 or higher. For every finding, use this shape:
[P1] Short title
Evidence: exact/approved/path.md:12-18 ("Quoted heading or snippet")
Impact: one concise sentence

When you genuinely need more context, use this exact Open Questions shape:
- Short question
  Evidence: exact/approved/path.md:12-18 ("Quoted heading or snippet")
  Why: one concise sentence

If there are no open questions, write "None." under Open Questions.

Weight stronger evidence first: Master Docs, then Overview, then Source, then Config, then Scripts, then Schema, then supporting docs. Do not use vague evidence like directory names or "various files". Do not critique OnlyMacs route labels, export metadata, or the review instructions themselves. Avoid generic filler and say plainly if the approved files are insufficient.
Always include every required section, even when there is nothing to add. Write "None." instead of omitting a required section.
$([[ "$require_cross_file" == "true" ]] && printf 'Include at least one finding that compares two approved files and calls out a contradiction, mismatch, or handoff gap between them.\n')
$([[ "$allow_context_requests" == "true" ]] && printf 'Use Context Requests only when more approved files are required. For each item, use this exact shape:\n- Need: short request\n  Why: one concise sentence\n  Suggested files: exact filenames or file types\nWrite "None." under Context Requests when the current bundle is sufficient.\n')
EOF
    return 0
  fi

  printf '%s' "$prompt"
}

build_chat_payload() {
  local model="${1:-}"
  local prompt="${2:-}"
  local route_scope="${3:-swarm}"
  local model_alias="${4:-}"
  local payload shaped_prompt lowered_shaped_prompt prefer_remote prefer_remote_soft route_provider_id max_tokens avoid_provider_ids_json exclude_provider_ids_json disable_reasoning_controls

  shaped_prompt="$(shape_prompt_for_resolved_artifact "$prompt")"
  lowered_shaped_prompt="$(printf '%s' "$shaped_prompt" | tr '[:upper:]' '[:lower:]')"
  if string_has_any "$lowered_shaped_prompt" "onlymacs_artifact_begin" "machine artifact" "do not emit hidden reasoning" \
    && ! string_has_any "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" "qwen2.5-coder" "codestral"; then
    disable_reasoning_controls=true
  else
    disable_reasoning_controls=false
  fi
  if prefer_remote_for_alias "$model_alias"; then
    prefer_remote=true
  else
    prefer_remote=false
  fi
  if soft_prefer_remote_for_alias "$model_alias"; then
    prefer_remote_soft=true
  else
    prefer_remote_soft=false
  fi
  route_provider_id="${ONLYMACS_CHAT_ROUTE_PROVIDER_ID:-}"
  if [[ -n "$route_provider_id" && "$route_scope" == "swarm" ]]; then
    if [[ "${ONLYMACS_CHAT_ROUTE_PROVIDER_IS_LOCAL:-0}" == "1" ]]; then
      prefer_remote=false
    else
      prefer_remote=true
    fi
    prefer_remote_soft=false
  fi
  avoid_provider_ids_json="$(onlymacs_json_string_array_or_empty "${ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON:-[]}")"
  exclude_provider_ids_json="$(onlymacs_json_string_array_or_empty "${ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON:-[]}")"
  max_tokens="${ONLYMACS_CHAT_MAX_TOKENS:-0}"
  if [[ ! "$max_tokens" =~ ^[0-9]+$ ]]; then
    max_tokens=0
  fi

  payload="$(jq -n \
    --arg model "$model" \
    --arg prompt "$shaped_prompt" \
    --arg route_scope "$route_scope" \
    --arg route_provider_id "$route_provider_id" \
    --argjson avoid_provider_ids "$avoid_provider_ids_json" \
    --argjson exclude_provider_ids "$exclude_provider_ids_json" \
    --argjson max_tokens "$max_tokens" \
    --argjson prefer_remote "$prefer_remote" \
    --argjson prefer_remote_soft "$prefer_remote_soft" \
    --argjson disable_reasoning_controls "$disable_reasoning_controls" \
    '{
      model: $model,
      stream: true,
      route_scope: $route_scope,
      prefer_remote: $prefer_remote,
      prefer_remote_soft: $prefer_remote_soft,
      messages: [{role:"user", content:$prompt}]
    }
    + (if ($route_provider_id | length) > 0 then {route_provider_id: $route_provider_id} else {} end)
    + (if ($avoid_provider_ids | length) > 0 then {avoid_provider_ids: $avoid_provider_ids} else {} end)
    + (if ($exclude_provider_ids | length) > 0 then {exclude_provider_ids: $exclude_provider_ids} else {} end)
    + (if $disable_reasoning_controls then {think: false, reasoning_effort: "low"} else {} end)
    + (if $max_tokens > 0 then {max_tokens: $max_tokens} else {} end)')"
  attach_resolved_artifact_to_payload "$payload"
}

stream_chat_payload_capture() {
  local payload="${1:-}"
  local content_path="${2:-}"
  local headers_path="${3:-}"
  local line json content reasoning now reasoning_bytes
  local progress_interval progress_next progress_tick heartbeat_count
  local preview_limit printed_bytes preview_notice_sent remaining
  local first_progress_timeout idle_timeout max_wall_timeout timeout_policy_json
  local stream_state_dir timeout_reason_path start_epoch_path first_token_path last_content_epoch_path stream_fifo_path curl_stderr_path
  local curl_args=(-fsS -N -H 'Content-Type: application/json' -d "$payload")
  local curl_pid watchdog_pid curl_status timeout_kind http_status failure_line

  progress_interval="${ONLYMACS_PROGRESS_INTERVAL:-30}"
  if [[ ! "$progress_interval" =~ ^[0-9]+$ ]]; then
    progress_interval=30
  fi
  progress_next=$((SECONDS + progress_interval))
  progress_tick=0
  heartbeat_count=0
  reasoning_bytes=0
  ONLYMACS_STREAM_REASONING_BYTES=0
  preview_limit="${ONLYMACS_STREAM_PREVIEW_LIMIT:-12000}"
  if [[ ! "$preview_limit" =~ ^[0-9]+$ ]]; then
    preview_limit=12000
  fi
  timeout_policy_json="$(onlymacs_timeout_policy_json)"
  first_progress_timeout="$(jq -r '.first_progress_timeout_seconds // 120' <<<"$timeout_policy_json" 2>/dev/null || printf '120')"
  idle_timeout="$(jq -r '.idle_timeout_seconds // 120' <<<"$timeout_policy_json" 2>/dev/null || printf '120')"
  max_wall_timeout="$(jq -r '.max_wall_clock_timeout_seconds // 7200' <<<"$timeout_policy_json" 2>/dev/null || printf '7200')"
  [[ "$first_progress_timeout" =~ ^[0-9]+$ ]] || first_progress_timeout=120
  [[ "$idle_timeout" =~ ^[0-9]+$ ]] || idle_timeout=120
  [[ "$max_wall_timeout" =~ ^[0-9]+$ ]] || max_wall_timeout=7200
  printed_bytes=0
  preview_notice_sent=0
  ONLYMACS_STREAM_CAPTURE_FAILURE_KIND=""
  ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE=""

  : >"$content_path"
  if [[ -n "$headers_path" ]]; then
    : >"$headers_path"
    curl_args+=(-D "$headers_path")
  fi

  stream_state_dir="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-stream-state-XXXXXX")" || return 1
  timeout_reason_path="${stream_state_dir}/timeout_reason"
  start_epoch_path="${stream_state_dir}/start_epoch"
  first_token_path="${stream_state_dir}/first_token"
  last_content_epoch_path="${stream_state_dir}/last_content_epoch"
  stream_fifo_path="${stream_state_dir}/stream.fifo"
  curl_stderr_path="${stream_state_dir}/curl.stderr"
  date +%s >"$start_epoch_path"
  printf '0\n' >"$last_content_epoch_path"
  mkfifo "$stream_fifo_path" || {
    rm -rf "$stream_state_dir"
    return 1
  }

  curl "${curl_args[@]}" "${BASE_URL}/v1/chat/completions" >"$stream_fifo_path" 2>"$curl_stderr_path" &
  curl_pid="$!"
  (
    local now_epoch start_epoch last_content_epoch
    while kill -0 "$curl_pid" 2>/dev/null; do
      now_epoch="$(date +%s)"
      start_epoch="$(cat "$start_epoch_path" 2>/dev/null || printf '%s' "$now_epoch")"
      if [[ "$max_wall_timeout" -gt 0 ]] && (( now_epoch - start_epoch >= max_wall_timeout )); then
        printf 'max_wall_timeout\n' >"$timeout_reason_path"
        kill "$curl_pid" 2>/dev/null || true
        break
      fi
      if [[ -f "$first_token_path" ]]; then
        last_content_epoch="$(cat "$last_content_epoch_path" 2>/dev/null || printf '%s' "$start_epoch")"
        if [[ "$idle_timeout" -gt 0 ]] && (( now_epoch - last_content_epoch >= idle_timeout )); then
          printf 'idle_timeout\n' >"$timeout_reason_path"
          kill "$curl_pid" 2>/dev/null || true
          break
        fi
      elif [[ "$first_progress_timeout" -gt 0 ]] && (( now_epoch - start_epoch >= first_progress_timeout )); then
        printf 'first_progress_timeout\n' >"$timeout_reason_path"
        kill "$curl_pid" 2>/dev/null || true
        break
      fi
      sleep 1
    done
  ) &
  watchdog_pid="$!"

  exec 3<"$stream_fifo_path"
  while IFS= read -r line <&3 || [[ -n "$line" ]]; do
      if [[ "$progress_interval" -gt 0 && "$SECONDS" -ge "$progress_next" ]]; then
        emit_chat_progress "$content_path" "$headers_path" "$heartbeat_count" "$progress_tick"
        write_chat_progress_status "$content_path" "$headers_path" "$heartbeat_count" "running"
        progress_tick=$((progress_tick + 1))
        progress_next=$((SECONDS + progress_interval))
      fi
      if [[ "$line" == data:\ * ]]; then
        json="${line#data: }"
        if [[ "$json" == "[DONE]" ]]; then
          continue
        fi
        content="$(jq -rj '.choices[]?.delta.content // empty, .choices[]?.message.content // empty' <<<"$json" 2>/dev/null || true)"
        reasoning="$(jq -rj '.choices[]?.delta.reasoning // empty, .choices[]?.message.reasoning // empty' <<<"$json" 2>/dev/null || true)"
        if [[ -n "$content" ]]; then
          now="$(date +%s)"
          printf '%s' "$content" >>"$content_path"
          : >"$first_token_path"
          printf '%s\n' "$now" >"$last_content_epoch_path"
          if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
            if [[ "$preview_limit" -eq 0 || "$printed_bytes" -lt "$preview_limit" ]]; then
              if [[ "$preview_limit" -eq 0 ]]; then
                printf '%s' "$content"
              else
                remaining=$((preview_limit - printed_bytes))
                printf '%s' "${content:0:remaining}"
              fi
            fi
            printed_bytes=$((printed_bytes + ${#content}))
            if [[ "$preview_limit" -gt 0 && "$printed_bytes" -gt "$preview_limit" && "$preview_notice_sent" -eq 0 ]]; then
              preview_notice_sent=1
              printf '\n\nOnlyMacs output is large, so the terminal is showing a preview. The complete answer will be saved in the run inbox.\n' >&2
            fi
          else
            printf '%s' "$content"
          fi
        elif [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
          printf '%s\n' "$line"
        elif [[ -n "$reasoning" ]]; then
          reasoning_bytes=$((reasoning_bytes + ${#reasoning}))
          ONLYMACS_STREAM_REASONING_BYTES="$reasoning_bytes"
        fi
      elif [[ "$line" == :* ]]; then
        heartbeat_count=$((heartbeat_count + 1))
        if [[ "$progress_interval" -gt 0 && "$SECONDS" -ge "$progress_next" ]]; then
          emit_chat_progress "$content_path" "$headers_path" "$heartbeat_count" "$progress_tick"
          write_chat_progress_status "$content_path" "$headers_path" "$heartbeat_count" "running"
          progress_tick=$((progress_tick + 1))
          progress_next=$((SECONDS + progress_interval))
        fi
      elif [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
        printf '%s\n' "$line"
      fi
    done

  exec 3<&-
  wait "$curl_pid"
  curl_status=$?
  http_status=""
  if [[ -n "$headers_path" ]]; then
    http_status="$(onlymacs_chat_http_status "$headers_path")"
  fi
  ONLYMACS_LAST_CHAT_HTTP_STATUS="$http_status"
  if [[ -n "$watchdog_pid" ]]; then
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  if [[ -s "$timeout_reason_path" ]]; then
    timeout_kind="$(head -n 1 "$timeout_reason_path" | tr -d '\r')"
    if [[ "$timeout_kind" == "first_progress_timeout" && "${reasoning_bytes:-0}" -gt 0 && ! -s "$content_path" ]]; then
      timeout_kind="reasoning_only_timeout"
    fi
    ONLYMACS_STREAM_CAPTURE_FAILURE_KIND="$timeout_kind"
    case "$timeout_kind" in
      first_progress_timeout)
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream timed out waiting for the first output token after ${first_progress_timeout}s"
        ;;
      reasoning_only_timeout)
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream spent ${first_progress_timeout}s producing reasoning but no artifact output"
        ;;
      idle_timeout)
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream went idle for ${idle_timeout}s after output had started"
        ;;
      max_wall_timeout)
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream exceeded the ${max_wall_timeout}s wall-clock limit"
        ;;
      *)
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream timed out"
        ;;
    esac
  fi
  if [[ "$curl_status" -ne 0 ]]; then
    if [[ -z "${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}" ]]; then
      if [[ -n "$http_status" ]]; then
        ONLYMACS_STREAM_CAPTURE_FAILURE_KIND="http_${http_status}"
      elif [[ "$curl_status" == "28" ]]; then
        ONLYMACS_STREAM_CAPTURE_FAILURE_KIND="curl_timeout"
      else
        ONLYMACS_STREAM_CAPTURE_FAILURE_KIND="transport_error"
      fi
    fi
    if [[ -z "${ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE:-}" ]]; then
      if [[ "$http_status" == "409" ]]; then
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote capacity unavailable (HTTP 409)"
      elif [[ "$http_status" =~ ^5[0-9][0-9]$ ]]; then
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="coordinator or remote relay returned HTTP ${http_status}"
      elif [[ -n "$http_status" ]]; then
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream failed with HTTP ${http_status}"
      elif [[ -s "$curl_stderr_path" ]]; then
        failure_line="$(tr '\n' ' ' <"$curl_stderr_path" | sed -E 's/^curl: \([0-9]+\) //; s/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-240)"
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="${failure_line:-remote stream failed before a response was received}"
      else
        ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE="remote stream failed before a response was received"
      fi
    fi
    ONLYMACS_LAST_CHAT_FAILURE_KIND="$ONLYMACS_STREAM_CAPTURE_FAILURE_KIND"
    ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="$ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE"
    if [[ -s "$content_path" ]]; then
      ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT=1
    else
      ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT=0
    fi
  fi
  rm -rf "$stream_state_dir"
  return "$curl_status"
}

onlymacs_chat_header_value() {
  local headers_path="${1:-}"
  local key="${2:-}"
  [[ -f "$headers_path" ]] || return 0
  awk -v key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')" '
    index($0, ":") > 0 {
      header = substr($0, 1, index($0, ":") - 1)
      value = substr($0, index($0, ":") + 1)
      gsub(/^[ \t]+|[ \t\r]+$/, "", value)
      if (tolower(header) == key) print value
    }
  ' "$headers_path" | tail -n 1
}

onlymacs_chat_http_status() {
  local headers_path="${1:-}"
  [[ -f "$headers_path" ]] || return 0
  awk '
    /^HTTP\// {
      status = $2
    }
    END {
      if (status != "") print status
    }
  ' "$headers_path"
}

onlymacs_capture_last_chat_headers() {
  local headers_path="${1:-}"
  [[ -f "$headers_path" ]] || return 0
  ONLYMACS_LAST_CHAT_SESSION_ID="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-session-id")"
  ONLYMACS_LAST_CHAT_PROVIDER_ID="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
  ONLYMACS_LAST_CHAT_PROVIDER_NAME="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
  ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
  ONLYMACS_LAST_CHAT_RESOLVED_MODEL="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
}
