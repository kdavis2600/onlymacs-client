# Top-level plan/start/demo/watch/benchmark/help command handlers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after direct chat runtime helpers are loaded.

build_swarm_payload() {
  local model_alias="${1:-}"
  local requested_agents="${2:-1}"
  local prompt="${3:-}"
  local scheduling="${4:-elastic}"
  local title="${5:-}"
  local allow_fallback="false"
  local model idempotency max_agents route_scope prefer_remote prefer_remote_soft strategy

  model="$(normalize_model_alias "$model_alias")"
  route_scope="$(route_scope_for_alias "$model_alias")"
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
  case "$(printf '%s' "$model_alias" | tr '[:upper:]' '[:lower:]')" in
    wide|go-wide|go_wide)
      strategy="go_wide"
      ;;
    local|local-first|local_first)
      strategy="local_first"
      ;;
    trusted-only|trusted_only|trusted)
      strategy="trusted_only"
      ;;
    offload-max)
      strategy="offload_max"
      ;;
    remote-first|remote-only|remote_only|remote)
      strategy="remote_first"
      ;;
    *)
      strategy="single_best"
      ;;
  esac
  if [[ -z "$title" ]]; then
    title="$(derive_title_from_prompt "$prompt")"
  fi
  if [[ -z "$title" && -n "$ONLYMACS_TITLE_OVERRIDE" ]]; then
    title="$ONLYMACS_TITLE_OVERRIDE"
  elif [[ -n "$ONLYMACS_TITLE_OVERRIDE" ]]; then
    title="$ONLYMACS_TITLE_OVERRIDE"
  fi

  if [[ -z "$model" ]] || [[ "$model_alias" == "coder" ]]; then
    allow_fallback="true"
  fi

  max_agents="${ONLYMACS_MAX_AGENTS:-$requested_agents}"
  idempotency="${ONLYMACS_IDEMPOTENCY_KEY:-$(default_idempotency_key "$model" "$requested_agents" "$prompt" "$title")}"

  local fallback_json
  if [[ "$allow_fallback" == "true" ]]; then
    fallback_json=true
  else
    fallback_json=false
  fi

  local payload
  payload="$(jq -n \
    --arg title "$title" \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --arg workspace "$(default_workspace_id)" \
    --arg thread "$(default_thread_id)" \
    --arg scheduling "$scheduling" \
    --arg route_scope "$route_scope" \
    --arg strategy "$strategy" \
    --arg idempotency "$idempotency" \
    --argjson requested_agents "$requested_agents" \
    --argjson max_agents "$max_agents" \
    --argjson allow_fallback "$fallback_json" \
    --argjson prefer_remote "$prefer_remote" \
    --argjson prefer_remote_soft "$prefer_remote_soft" \
    '{
      title: $title,
      model: $model,
      route_scope: $route_scope,
      strategy: $strategy,
      prefer_remote: $prefer_remote,
      prefer_remote_soft: $prefer_remote_soft,
      requested_agents: $requested_agents,
      max_agents: $max_agents,
      allow_fallback: $allow_fallback,
      scheduling: $scheduling,
      workspace_id: $workspace,
      thread_id: $thread,
      idempotency_key: $idempotency,
      prompt: $prompt
    }')"
  attach_resolved_artifact_to_payload "$payload"
}

needs_confirmation() {
  local plan_body="$1"
  local requested admitted warnings
  requested="$(jq -r '.requested_agents // 0' <<<"$plan_body")"
  admitted="$(jq -r '.admitted_agents // 0' <<<"$plan_body")"
  warnings="$(jq -r '.warnings[]? // empty' <<<"$plan_body")"
  if plan_has_confirmation_warning "$warnings"; then
    return 0
  fi
  if [[ "$requested" -ge 8 ]]; then
    return 0
  fi
  if [[ "$admitted" -lt "$requested" && "$requested" -gt 1 ]]; then
    return 0
  fi
  return 1
}

plan_has_confirmation_warning() {
  local warnings="${1:-}"
  [[ "$warnings" == *"looks sensitive"* || "$warnings" == *"looks lightweight for a scarce premium"* ]]
}

confirm_chat_launch() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local advisories
  advisories="$(launch_advisories_text "$model_alias" "$prompt")"
  if [[ -z "$advisories" || "$ONLYMACS_ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    printf 'OnlyMacs wants confirmation before sending this chat request.\n%sRe-run with --yes to continue unattended.\n' "$advisories" >&2
    return 1
  fi
  printf '%sContinue with this chat request? [y/N] ' "$advisories"
  local answer
  IFS= read -r answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      printf 'Cancelled.\n' >&2
      return 1
      ;;
  esac
}

confirm_plan() {
  local plan_body="$1"
  local requested admitted queued reason warnings
  requested="$(jq -r '.requested_agents // 0' <<<"$plan_body")"
  admitted="$(jq -r '.admitted_agents // 0' <<<"$plan_body")"
  queued="$(jq -r '.queue_remainder // 0' <<<"$plan_body")"
  reason="$(jq -r '.queue_reason // empty' <<<"$plan_body")"
  warnings="$(jq -r '.warnings[]? // empty' <<<"$plan_body")"

  if [[ "$ONLYMACS_ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    if plan_has_confirmation_warning "$warnings"; then
      printf 'OnlyMacs wants confirmation before launching this risky request.\n' >&2
    else
      printf 'OnlyMacs wants confirmation before starting %s requested agents.\n' "$requested" >&2
    fi
    printf 'It would admit %s now' "$admitted" >&2
    if [[ "$queued" -gt 0 ]]; then
      printf ' and queue %s because %s' "$queued" "$(human_queue_reason "$reason")" >&2
    fi
    printf '. Re-run with --yes to continue unattended.\n' >&2
    return 1
  fi

  if plan_has_confirmation_warning "$warnings"; then
    printf 'OnlyMacs flagged this request before launch. '
  fi
  printf 'You asked for %s agents. OnlyMacs would admit %s now' "$requested" "$admitted"
  if [[ "$queued" -gt 0 ]]; then
    printf ' and queue %s because %s' "$queued" "$(human_queue_reason "$reason")"
  fi
  if [[ -n "$warnings" ]]; then
    printf '\n'
    jq -r '.warnings[]? | "- " + .' <<<"$plan_body"
  fi
  printf '. Continue? [y/N] '
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      printf 'Cancelled before launch.\n' >&2
      return 1
      ;;
  esac
}

run_plan() {
  local model_alias="${1:-}"
  local requested_agents="${2:-1}"
  local prompt="${3:-}"
  local scheduling="${4:-elastic}"
  local activity_label="${5:-plan}"
  local payload
  set_activity_context "$activity_label" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "$(route_scope_for_alias "$model_alias")" "$(normalize_model_alias "$model_alias")"
  compile_prompt_with_plan_file "$prompt" || return 1
  prompt="${ONLYMACS_PLAN_COMPILED_PROMPT:-$prompt}"
  resolve_prompt_with_file_access "$model_alias" "$prompt" || return 1
  prompt="${ONLYMACS_RESOLVED_PROMPT:-$prompt}"
  emit_launch_advisories "$model_alias" "$prompt"
  payload="$(build_swarm_payload "$model_alias" "$requested_agents" "$prompt" "$scheduling" "")"

  request_json POST "/admin/v1/swarm/plan" "$payload" || return 1
  require_success "Could not compute a swarm plan." || return 1
  ONLYMACS_ACTIVITY_MODEL="$(jq -r '.resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  record_current_activity "planned" "Planned $(jq -r '.admitted_agents // 0' <<<"$ONLYMACS_LAST_HTTP_BODY") of ${requested_agents} agents." "" ""
  emit_output format_plan "$ONLYMACS_LAST_HTTP_BODY"
}

run_start() {
  local model_alias="${1:-}"
  local requested_agents="${2:-1}"
  local prompt="${3:-}"
  local scheduling="${4:-elastic}"
  local activity_label="${5:-start}"
  local payload plan_body

  set_activity_context "$activity_label" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "$(route_scope_for_alias "$model_alias")" "$(normalize_model_alias "$model_alias")"
  compile_prompt_with_plan_file "$prompt" || return 1
  prompt="${ONLYMACS_PLAN_COMPILED_PROMPT:-$prompt}"
  resolve_prompt_with_file_access "$model_alias" "$prompt" || return 1
  prompt="${ONLYMACS_RESOLVED_PROMPT:-$prompt}"
  emit_launch_advisories "$model_alias" "$prompt"
  payload="$(build_swarm_payload "$model_alias" "$requested_agents" "$prompt" "$scheduling" "")"
  request_json POST "/admin/v1/swarm/plan" "$payload" || return 1
  require_success "Could not compute a swarm plan." || return 1
  plan_body="$ONLYMACS_LAST_HTTP_BODY"

  if needs_confirmation "$plan_body"; then
    emit_output format_plan "$plan_body"
    confirm_plan "$plan_body" || return 1
  fi

  request_json POST "/admin/v1/swarm/start" "$payload" || return 1
  require_success "Could not start the swarm session." || return 1
  ONLYMACS_ACTIVITY_MODEL="$(jq -r '.session.resolved_model // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  record_current_activity \
    "launched" \
    "$(jq -r '.session.selection_explanation // .session.route_summary // "Started a new OnlyMacs swarm."' <<<"$ONLYMACS_LAST_HTTP_BODY")" \
    "$(jq -r '.session.id // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")" \
    "$(jq -r '.session.status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  emit_output format_start "$ONLYMACS_LAST_HTTP_BODY"
}

run_demo() {
  local demo_prompt="Reply with ONLYMACS_DEMO_OK exactly."
  local payload plan_body start_body session_id

  payload="$(build_swarm_payload "best" 1 "$demo_prompt" "elastic" "onlymacs demo")"
  request_json POST "/admin/v1/swarm/plan" "$payload" || return 1
  require_success "Could not plan the demo session." || return 1
  plan_body="$ONLYMACS_LAST_HTTP_BODY"

  local admitted
  admitted="$(jq -r '.admitted_agents // 0' <<<"$plan_body")"
  if [[ "$admitted" -eq 0 ]]; then
    emit_output format_plan "$plan_body"
    printf '\nDemo could not start because OnlyMacs has no free capacity right now.\n' >&2
    return 1
  fi

  request_json POST "/admin/v1/swarm/start" "$payload" || return 1
  require_success "Could not start the demo session." || return 1
  start_body="$ONLYMACS_LAST_HTTP_BODY"
  session_id="$(jq -r '.session.id' <<<"$start_body")"

  request_json POST "/admin/v1/swarm/sessions/cancel" "$(jq -n --arg session_id "$session_id" '{session_id:$session_id}')" || return 1
  require_success "The demo session started, but cleanup failed." || return 1

  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    jq -n --argjson plan "$plan_body" --argjson start "$start_body" --argjson cleanup "$ONLYMACS_LAST_HTTP_BODY" '{plan:$plan,start:$start,cleanup:$cleanup}'
    return 0
  fi

  printf 'OnlyMacs demo passed.\n'
  printf 'It planned and launched a one-agent test session, then cleaned it up.\n'
  printf 'Resolved model: %s\n' "$(jq -r '.session.resolved_model // empty' <<<"$start_body")"
  printf 'Session: %s\n' "$session_id"
  printf 'Next: %s \"review this patch\"\n' "$ONLYMACS_WRAPPER_NAME"
}

format_provider_watch() {
  local body="${1:-}"
  local target="${2:-}"
  local match visible
  match="$(jq -c --arg needle "$target" '
    def lower($v): (($v // "") | tostring | ascii_downcase);
    def matches($v): (lower($v) | contains(lower($needle)));
    [
      .members[]? as $member
      | $member.capabilities[]? as $cap
      | select(matches($cap.provider_id) or matches($cap.provider_name) or matches($cap.owner_member_name) or matches($member.member_name))
      | {
          member_id: ($member.member_id // ""),
          member_name: ($member.member_name // $cap.owner_member_name // $cap.provider_name // ""),
          provider_id: ($cap.provider_id // ""),
          provider_name: ($cap.provider_name // ""),
          status: ($cap.status // $member.status // "unknown"),
          maintenance_state: ($cap.maintenance_state // $member.maintenance_state // ""),
          active_model: ($cap.active_model // $member.active_model // ""),
          best_model: ($cap.best_model // $member.best_model // ""),
          active_sessions: ($cap.active_sessions // 0),
          tokens_per_second: ($cap.recent_uploaded_tokens_per_second // $member.recent_uploaded_tokens_per_second // 0),
          hardware: ($cap.hardware // $member.hardware // null),
          client_build: ($cap.client_build // $member.client_build // null),
          model_count: (($cap.models // []) | length)
        }
    ] | .[0] // empty
  ' <<<"$body" 2>/dev/null || true)"
  if [[ -n "$match" ]]; then
    printf 'Provider watch: %s\n' "$(jq -r '.member_name // .provider_name // .provider_id' <<<"$match")"
    printf 'Provider: %s\n' "$(jq -r '.provider_id // "unknown"' <<<"$match")"
    printf 'Status: %s' "$(jq -r '.status // "unknown"' <<<"$match")"
    if [[ "$(jq -r '.maintenance_state // empty' <<<"$match")" != "" ]]; then
      printf ' (%s)' "$(jq -r '.maintenance_state' <<<"$match")"
    fi
    printf '\n'
    if [[ "$(jq -r '.active_model // empty' <<<"$match")" != "" ]]; then
      printf 'Active model: %s\n' "$(jq -r '.active_model' <<<"$match")"
    fi
    if [[ "$(jq -r '.best_model // empty' <<<"$match")" != "" ]]; then
      printf 'Best model: %s\n' "$(jq -r '.best_model' <<<"$match")"
    fi
    printf 'Active sessions: %s\n' "$(jq -r '.active_sessions // 0' <<<"$match")"
    printf 'Recent speed: %s tok/s\n' "$(jq -r '(.tokens_per_second // 0) | tonumber | if . == 0 then "0.0" else (.*10|round/10|tostring) end' <<<"$match")"
    if [[ "$(jq -r '.hardware.memory_gb // empty' <<<"$match")" != "" || "$(jq -r '.hardware.cpu_brand // empty' <<<"$match")" != "" ]]; then
      printf 'Hardware: %s GB / %s\n' "$(jq -r '.hardware.memory_gb // "unknown"' <<<"$match")" "$(jq -r '.hardware.cpu_brand // "unknown"' <<<"$match")"
    fi
    if [[ "$(jq -r '.client_build.version // empty' <<<"$match")" != "" ]]; then
      printf 'Build: %s (%s)\n' "$(jq -r '.client_build.version // empty' <<<"$match")" "$(jq -r '.client_build.build_number // empty' <<<"$match")"
    fi
    return 0
  fi

  printf 'Waiting for %s to rejoin the current swarm.\n' "$target"
  visible="$(jq -r '[.members[]?.member_name, .providers[]?.owner_member_name, .providers[]?.name] | map(select(. != null and . != "")) | unique | join(", ")' <<<"$body" 2>/dev/null || true)"
  if [[ -n "$visible" ]]; then
    printf 'Visible now: %s\n' "$visible"
  else
    printf 'Visible now: no providers are visible through this bridge.\n'
  fi
}

run_watch_provider() {
  local target="${1:-}"
  local follow=0
  if [[ "$target" == "--follow" || "$target" == "-f" ]]; then
    follow=1
    shift || true
    target="${1:-}"
  fi
  if [[ -z "$target" ]]; then
    printf 'usage: %s watch-provider <provider-id|member-name> [--follow]\n' "$ONLYMACS_WRAPPER_NAME" >&2
    return 1
  fi
  while true; do
    request_json GET "/admin/v1/status" || return 1
    require_success "Could not inspect the local OnlyMacs status." || return 1
    if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
      jq --arg needle "$target" '
        def lower($v): (($v // "") | tostring | ascii_downcase);
        def matches($v): (lower($v) | contains(lower($needle)));
        {target:$needle, matches:[
          .members[]? as $member
          | $member.capabilities[]? as $cap
          | select(matches($cap.provider_id) or matches($cap.provider_name) or matches($cap.owner_member_name) or matches($member.member_name))
          | {member:$member.member_name, provider_id:$cap.provider_id, provider_name:$cap.provider_name, status:($cap.status // $member.status), active_model:($cap.active_model // $member.active_model), best_model:($cap.best_model // $member.best_model), hardware:($cap.hardware // $member.hardware), client_build:($cap.client_build // $member.client_build)}
        ]}
      ' <<<"$ONLYMACS_LAST_HTTP_BODY"
    else
      clear_if_interactive
      format_provider_watch "$ONLYMACS_LAST_HTTP_BODY" "$target"
    fi
    if [[ "$follow" -ne 1 ]]; then
      return 0
    fi
    sleep "$ONLYMACS_WATCH_INTERVAL"
  done
}

onlymacs_benchmark_preflight_report() {
  local body="${1:-}"
  local route_scope="${2:-swarm}"
  local alias="${3:-remote-first}"
  local prompt="${4:-}"
  jq -c --arg route_scope "$route_scope" --arg alias "$alias" --arg prompt "$prompt" '
    def score_model($id):
      ($id | ascii_downcase) as $m
      | (if ($m | contains("gpt-oss:120b")) then 5200
         elif (($m | contains("deepseek")) and ($m | contains("70b"))) then 4800
         elif (($m | contains("qwen3.6")) and ($m | contains("q8"))) then 4300
         elif (($m | contains("qwen3.6")) and ($m | contains("q4"))) then 3100
         elif ($m | contains("qwen2.5-coder:32b")) then 2600
         elif ($m | contains("codestral:22b")) then 2100
         elif (($m | contains("gemma4")) and ($m | contains("31b"))) then 1900
         elif (($m | contains("gemma")) and ($m | contains("27b"))) then 1700
         elif ($m | contains("14b")) then 1000
         else 500 end);
    (.identity.member_id // "") as $local
    | [
        .members[]? as $member
        | select(if $route_scope == "local_only" then ($member.member_id == $local) elif ($alias == "remote-first" or $alias == "remote-only" or $alias == "remote") and ($local | length) > 0 then ($member.member_id != $local) else true end)
        | $member.capabilities[]? as $cap
        | select((($cap.status // $member.status // "available") != "unavailable") and (($cap.maintenance_state // $member.maintenance_state // "") == ""))
        | (($cap.slots.free // $cap.slots_free // 1) | tonumber? // 1) as $free
        | select($free > 0)
        | $cap.models[]? as $model
        | (($model.slots_free // $free) | tonumber? // $free) as $model_free
        | select($model_free > 0)
        | (($cap.recent_uploaded_tokens_per_second // $member.recent_uploaded_tokens_per_second // 0) | tonumber? // 0) as $tps
        | {
            member_name: ($member.member_name // $cap.owner_member_name // $cap.provider_name // ""),
            provider_id: ($cap.provider_id // ""),
            provider_name: ($cap.provider_name // ""),
            model: ($model.id // $model.name // ""),
            hardware: ($cap.hardware // $member.hardware // null),
            recent_tokens_per_second: $tps,
            free_slots: $model_free,
            benchmark_metrics: {
              first_artifact_latency_seconds: null,
              schema_valid: null,
              repair_count: null,
              duplicate_rate: null,
              quality_warning_count: null
            },
            score: ((score_model($model.id // $model.name // "")) + ($model_free * 100) + (($tps * 4) | floor))
          }
      ] | sort_by(.score) | reverse | {
        created_at: (now | todateiso8601),
        mode: "preflight",
        route_alias: $alias,
        route_scope: $route_scope,
        prompt_summary: ($prompt | gsub("[\\r\\n\\t]+"; " ") | .[:180]),
        candidates: .,
        recommended: (.[0] // null),
        note: "Scores are preflight heuristics from current coordinator status. Pass --live to run tiny representative probes against the top candidates."
      }
  ' <<<"$body"
}

onlymacs_benchmark_probe_prompt() {
  local prompt="${1:-}"
  cat <<EOF
OnlyMacs model benchmark probe.

Representative task:
${prompt}

Return exactly 5 compact JSON objects in one strict JSON array. Each object must include id, term, english, qualityNote, and usage fields. Use unique terms. Do not include markdown or prose outside the artifact markers.

ONLYMACS_ARTIFACT_BEGIN filename=onlymacs-benchmark-probe.json
[
  {"id":"probe-001","term":"example one","english":"example one","qualityNote":"clear","usage":"Use example one naturally."}
]
ONLYMACS_ARTIFACT_END
EOF
}

onlymacs_benchmark_validate_probe_body() {
  local body_path="${1:-}"
  local repair_count=0 schema_valid=false duplicate_rate=1 quality_warning_count=0 item_count=0
  [[ -f "$body_path" ]] || {
    jq -cn '{schema_valid:false, repair_count:0, duplicate_rate:1, quality_warning_count:1, item_count:0}'
    return 0
  }
  repair_json_artifact_if_possible "$body_path" "Return exactly 5 JSON objects."
  if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
    repair_count=1
  fi
  if jq -e 'type == "array" and length == 5 and all(.[]; type == "object" and has("id") and has("term") and has("english"))' "$body_path" >/dev/null 2>&1; then
    schema_valid=true
  fi
  item_count="$(jq -r 'if type == "array" then length else 0 end' "$body_path" 2>/dev/null || printf '0')"
  duplicate_rate="$(jq -r '
    if type != "array" then 1
    else
      ([.[]? | (.term // .word // .text // .id // empty) | tostring | ascii_downcase] | map(select(length > 0))) as $terms
      | if ($terms | length) == 0 then 1
        else ((($terms | length) - ($terms | unique | length)) / ($terms | length))
        end
    end
  ' "$body_path" 2>/dev/null || printf '1')"
  if rg -i '\b(todo|placeholder|lorem|fixme|example only)\b' "$body_path" >/dev/null 2>&1; then
    quality_warning_count=1
  fi
  jq -cn \
    --argjson schema_valid "$schema_valid" \
    --argjson repair_count "$repair_count" \
    --argjson duplicate_rate "$duplicate_rate" \
    --argjson quality_warning_count "$quality_warning_count" \
    --argjson item_count "${item_count:-0}" \
    '{schema_valid:$schema_valid, repair_count:$repair_count, duplicate_rate:$duplicate_rate, quality_warning_count:$quality_warning_count, item_count:$item_count}'
}

onlymacs_benchmark_with_live_probes() {
  local report_json="${1:-}"
  local route_scope="${2:-swarm}"
  local alias="${3:-remote-first}"
  local prompt="${4:-}"
  local probe_limit="${ONLYMACS_BENCHMARK_PROBE_LIMIT:-2}"
  local probes_json="[]" candidate provider_id model probe_prompt content_path headers_path body_path started ended elapsed success failure_class metrics_json result_json score

  [[ "$probe_limit" =~ ^[0-9]+$ && "$probe_limit" -gt 0 ]] || probe_limit=2
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    provider_id="$(jq -r '.provider_id // empty' <<<"$candidate")"
    model="$(jq -r '.model // empty' <<<"$candidate")"
    [[ -n "$model" ]] || continue
    content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-benchmark-content-XXXXXX")"
    headers_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-benchmark-headers-XXXXXX")"
    body_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-benchmark-body-XXXXXX")"
    probe_prompt="$(onlymacs_benchmark_probe_prompt "$prompt")"
    ONLYMACS_CHAT_MAX_TOKENS="${ONLYMACS_BENCHMARK_MAX_TOKENS:-900}"
    ONLYMACS_CHAT_ROUTE_PROVIDER_ID="$provider_id"
    started="$(date +%s)"
    success=false
    failure_class=""
    if stream_chat_payload_capture "$(build_chat_payload "$model" "$probe_prompt" "$route_scope" "$alias")" "$content_path" "$headers_path"; then
      success=true
      if ! extract_marked_artifact_block "$content_path" "$body_path" && ! extract_single_fenced_code_block "$content_path" "$body_path"; then
        cp "$content_path" "$body_path"
      fi
    else
      failure_class="$(onlymacs_classify_failure "${ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE:-benchmark probe failed}" "$(onlymacs_chat_http_status "$headers_path")" "${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}")"
      if [[ -s "$content_path" ]]; then
        if ! extract_marked_artifact_block "$content_path" "$body_path" && ! extract_single_fenced_code_block "$content_path" "$body_path"; then
          cp "$content_path" "$body_path"
        fi
      fi
    fi
    ended="$(date +%s)"
    elapsed=$((ended - started))
    metrics_json="$(onlymacs_benchmark_validate_probe_body "$body_path")"
    score="$(jq -nr \
      --argjson base "$(jq -r '.score // 0' <<<"$candidate")" \
      --argjson elapsed "$elapsed" \
      --argjson success "$success" \
      --arg failure_class "$failure_class" \
      --argjson metrics "$metrics_json" \
      '$base
       - ($elapsed * 20)
       - (($metrics.repair_count // 0) * 250)
       - (($metrics.duplicate_rate // 1) * 2000)
       - (($metrics.quality_warning_count // 0) * 150)
       - (if ($metrics.schema_valid // false) then 0 else 2500 end)
       - (if $success then 0 else 3000 end)
       - (if ($failure_class | length) > 0 then 500 else 0 end)')"
    result_json="$(jq -cn \
      --argjson candidate "$candidate" \
      --argjson success "$success" \
      --arg failure_class "$failure_class" \
      --argjson elapsed "$elapsed" \
      --argjson metrics "$metrics_json" \
      --argjson live_score "$score" \
      '$candidate + {
        live_probe: {
          success: $success,
          failure_class: ($failure_class | if length > 0 then . else null end),
          first_artifact_latency_seconds: $elapsed,
          schema_valid: $metrics.schema_valid,
          repair_count: $metrics.repair_count,
          duplicate_rate: $metrics.duplicate_rate,
          quality_warning_count: $metrics.quality_warning_count,
          item_count: $metrics.item_count,
          live_score: $live_score
        },
        benchmark_metrics: ($metrics + {first_artifact_latency_seconds: $elapsed}),
        score: $live_score
      }')"
    probes_json="$(jq -c --argjson item "$result_json" '. + [$item]' <<<"$probes_json")"
    rm -f "$content_path" "$headers_path" "$body_path"
    unset ONLYMACS_CHAT_MAX_TOKENS ONLYMACS_CHAT_ROUTE_PROVIDER_ID
  done < <(jq -c --argjson limit "$probe_limit" '.candidates[:$limit][]?' <<<"$report_json")

  jq -c --argjson probes "$probes_json" '
    .mode = "live_preflight"
    | .live_probe_count = ($probes | length)
    | .live_probes = $probes
    | .recommended = (($probes | sort_by(.score) | reverse | .[0]) // .recommended)
    | .note = "Live benchmark probes ran tiny representative JSON batches and scored latency, schema validity, repair count, duplicate rate, quality warnings, and route availability."
  ' <<<"$report_json"
}

run_benchmark() {
  local model_alias="${1:-remote-first}"
  local prompt route_scope body report_path report_json live=0
  if [[ "$model_alias" == "--live" ]]; then
    live=1
    shift || true
    model_alias="${1:-remote-first}"
  fi
  if [[ -n "$model_alias" ]] && ! chat_arg_looks_like_route_or_model "$model_alias"; then
    prompt="$*"
    model_alias="remote-first"
  else
    shift || true
    prompt="$*"
  fi
  if [[ -z "$prompt" ]]; then
    prompt="Return exactly 5 strict JSON objects for a representative OnlyMacs artifact benchmark."
  fi
  route_scope="$(route_scope_for_alias "$model_alias")"
  request_json GET "/admin/v1/status" || return 1
  require_success "Could not inspect the local OnlyMacs status for benchmarking." || return 1
  body="$ONLYMACS_LAST_HTTP_BODY"
  report_json="$(onlymacs_benchmark_preflight_report "$body" "$route_scope" "$model_alias" "$prompt")"
  if [[ "$live" -eq 1 || "${ONLYMACS_BENCHMARK_LIVE:-0}" == "1" ]]; then
    report_json="$(onlymacs_benchmark_with_live_probes "$report_json" "$route_scope" "$model_alias" "$prompt")"
  fi
  mkdir -p "${PWD}/onlymacs/benchmarks" 2>/dev/null || true
  report_path="${PWD}/onlymacs/benchmarks/$(date -u +"%Y%m%dT%H%M%SZ")-benchmark.json"
  printf '%s\n' "$report_json" >"$report_path" 2>/dev/null || true
  if [[ "$ONLYMACS_JSON_MODE" -eq 1 ]]; then
    printf '%s\n' "$report_json"
    return 0
  fi
  printf 'OnlyMacs benchmark preflight\n'
  printf 'Route: %s (%s)\n' "$model_alias" "$(human_route_scope "$route_scope")"
  if [[ "$(jq -r '.candidates | length' <<<"$report_json")" == "0" ]]; then
    printf 'No eligible providers/models are available right now.\n'
    printf 'Next: %s watch-provider <member-name>\n' "$ONLYMACS_WRAPPER_NAME"
    return 1
  fi
  printf 'Recommended: %s / %s / score %s\n' "$(jq -r '.recommended.member_name // "unknown"' <<<"$report_json")" "$(jq -r '.recommended.model // "unknown"' <<<"$report_json")" "$(jq -r '.recommended.score // 0' <<<"$report_json")"
  printf 'Top candidates:\n'
  jq -r '.candidates[:6][] | "- \(.member_name) / \(.model) / score \(.score) / \(.recent_tokens_per_second) tok/s / \(.free_slots) free"' <<<"$report_json"
  printf 'Report: %s\n' "$report_path"
}

# shellcheck source=/dev/null
source "${ONLYMACS_SCRIPT_DIR}/onlymacs-cli-jobs.sh"
run_watch() {
  local target="${1:-}"
  local path formatter
  if [[ "$target" == "queue" ]]; then
    path="/admin/v1/swarm/queue"
    formatter="format_queue"
  elif [[ -n "$target" ]]; then
    path="/admin/v1/swarm/sessions?session_id=${target}"
    formatter="format_session"
  else
    path="/admin/v1/status"
    formatter="format_system_status"
  fi

  while true; do
    request_json GET "$path" || return 1
    require_success "Could not fetch watch state." || return 1
    clear_if_interactive
    emit_output "$formatter" "$ONLYMACS_LAST_HTTP_BODY"

    if [[ -n "$target" && "$target" != "queue" ]]; then
      local terminal_status
      terminal_status="$(jq -r '.sessions[0].status // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
      case "$terminal_status" in
        cancelled|completed|failed)
          return 0
          ;;
      esac
    fi

    sleep "$ONLYMACS_WATCH_INTERVAL"
  done
}

run_doctor() {
  set_activity_context "check" "${ONLYMACS_ROUTER_INTERPRETATION:-}" "" ""
  request_json GET "/admin/v1/status" || return 1
  require_success "Could not inspect the local OnlyMacs status." || return 1
  record_current_activity "checked" "$(jq -r '.bridge.status // "unknown"' <<<"$ONLYMACS_LAST_HTTP_BODY")" "" ""
  emit_output format_doctor "$ONLYMACS_LAST_HTTP_BODY"
}

parse_count_and_prompt() {
  local default_count="$1"
  shift
  local width="$default_count"
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    width="$1"
    shift
  fi
  ONLYMACS_PARSED_WIDTH="$width"
  ONLYMACS_PARSED_PROMPT="$*"
}

print_help() {
  cat <<EOF
   ____        __        __  ___
  / __ \____  / /_  __  /  |/  /___ __________
 / / / / __ \/ / / / / / /|_/ / __ \`/ ___/ ___/
/ /_/ / / / / / /_/ / / /  / / /_/ / /__(__  )
\____/_/ /_/_/\__, / /_/  /_/\__,_/\___/____/
             /____/

OnlyMacs for ${ONLYMACS_TOOL_NAME}

Run AI work on your Mac swarm. The default form is intentionally short:

  ${ONLYMACS_WRAPPER_NAME} "your task"

Default behavior:
  prompt-only work prefers another Mac when one is available.
  file-bound or sensitive work is stopped, kept local, or routed through approval.
  large work is upgraded into an extended planned run unless you pass --simple.

Friendly commands:
  ${ONLYMACS_WRAPPER_NAME} check
  ${ONLYMACS_WRAPPER_NAME} demo
  ${ONLYMACS_WRAPPER_NAME} go [quick|balanced|wide|local-first|trusted-only|offload-max|remote-first|precise] [agents] "prompt"
  ${ONLYMACS_WRAPPER_NAME} watch [session-id|latest|current|queue]
  ${ONLYMACS_WRAPPER_NAME} pause <session-id|latest|current>
  ${ONLYMACS_WRAPPER_NAME} resume <session-id|latest|current>
  ${ONLYMACS_WRAPPER_NAME} resume-run [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} diagnostics [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} support-bundle [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} report [latest|run-id|inbox-path] [--report "markdown"]
  ${ONLYMACS_WRAPPER_NAME} report status|enable|disable
  ${ONLYMACS_WRAPPER_NAME} inbox [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} open [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} apply [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} stop <session-id|latest|current>
  ${ONLYMACS_WRAPPER_NAME} "do a code review on my project"

Direct commands:
  ${ONLYMACS_WRAPPER_NAME} status [session-id|latest|current]
  ${ONLYMACS_WRAPPER_NAME} runtime
  ${ONLYMACS_WRAPPER_NAME} swarms
  ${ONLYMACS_WRAPPER_NAME} models
  ${ONLYMACS_WRAPPER_NAME} preflight [exact-model|alias]
  ${ONLYMACS_WRAPPER_NAME} benchmark [--live] [remote-first|local-first|trusted-only] ["representative prompt"]
  ${ONLYMACS_WRAPPER_NAME} watch-provider <provider-id|member-name> [--follow]
  ${ONLYMACS_WRAPPER_NAME} jobs list|create|claim|work|complete|fail|finalize
  ${ONLYMACS_WRAPPER_NAME} plan [exact-model|alias|best-available] [agents] [prompt]
  ${ONLYMACS_WRAPPER_NAME} start [exact-model|alias|best-available] [agents] [prompt]
  ${ONLYMACS_WRAPPER_NAME} queue [session-id|latest|current]
  ${ONLYMACS_WRAPPER_NAME} cancel <session-id|latest|current>
  ${ONLYMACS_WRAPPER_NAME} resume-run [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} diagnostics [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} support-bundle [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} report [latest|run-id|inbox-path] [--report "markdown"]
  ${ONLYMACS_WRAPPER_NAME} report status|enable|disable
  ${ONLYMACS_WRAPPER_NAME} inbox [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} open [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} apply [latest|run-id|inbox-path]
  ${ONLYMACS_WRAPPER_NAME} repair
  ${ONLYMACS_WRAPPER_NAME} chat [best|local-first|trusted-only|offload-max|remote-first|exact-model] [prompt]

Flags:
  --json       return raw JSON instead of human-readable output
  --yes        skip launch confirmation when OnlyMacs clamps a wide request
  --extended   plan, checkpoint, validate, and repair longer artifact jobs
  --overnight  extended mode with a larger output and retry budget
  --go-wide[=N|max] use the reusable ticket board for fast extended JSON jobs; N runs 1-8 worker lanes, max caps at 8
  --go-wide-lanes N set ticket-board worker lanes from 1-8 without changing the wide preset spelling
  --context-read MODE set context-aware read policy hint: manual, packs, full-project, or git
  --context-write MODE set context-aware write policy hint: inbox, staged, direct, or read-only
  --allow-tests allow worker/test tickets to execute validation commands when the swarm policy allows it
  --allow-installs allow dependency-install tickets when the swarm policy allows it
  jobs work --watch keeps a worker loop alive until interrupted; --slots N lets a Mac claim up to N ready tickets per polling pass
  --remote-first prefer another Mac for this request
  --local-first  keep this on This Mac when a route is needed
  --trusted-only constrain repo/file-aware work to trusted private Macs
  --plan FILE  run an extended job from a Markdown plan file
  --plan:FILE  shorthand for --plan FILE
  --simple     force one normal request; disables auto-planning
  --title TXT  set a friendly session title
  --interval N change watch refresh interval in seconds

Reporting:
  Public swarm runs auto-submit bounded feedback by default: invocation, outcome,
  provider/model metadata, event counts, and a short report. Full prompts,
  RESULT.md, artifacts, and raw local paths are not sent.
  Disable: ${ONLYMACS_WRAPPER_NAME} report disable
  Re-enable: ${ONLYMACS_WRAPPER_NAME} report enable
  One run: ${ONLYMACS_WRAPPER_NAME} report latest --report "What worked / what broke"

Model aliases:
  best-available | best
  coder
  fast
  local-first
  trusted-only
  offload-max
  remote-first
  precise

Examples:
  ${ONLYMACS_WRAPPER_NAME} check
  ${ONLYMACS_WRAPPER_NAME} "turn this spec into a focused implementation checklist"
  ${ONLYMACS_WRAPPER_NAME} "review this refactor"
  ${ONLYMACS_WRAPPER_NAME} go wide 6 "split this bug hunt into parallel tracks"
  ${ONLYMACS_WRAPPER_NAME} go local-first "review this private auth flow without leaving this Mac"
  ${ONLYMACS_WRAPPER_NAME} go trusted-only "use my Macs only for this repo review"
  ${ONLYMACS_WRAPPER_NAME} go offload-max "debug this failing test without burning paid tokens"
  ${ONLYMACS_WRAPPER_NAME} go remote-first "force this through another Mac first"
  ${ONLYMACS_WRAPPER_NAME} chat "reply with ONLYMACS_SMOKE_OK exactly"
  ${ONLYMACS_WRAPPER_NAME} benchmark remote-first "return 5 strict JSON objects"
  ${ONLYMACS_WRAPPER_NAME} jobs create "build this landing page with go-wide coding tickets"
  ${ONLYMACS_WRAPPER_NAME} jobs create --tickets tickets.json "build this landing page with go-wide tickets"
  ${ONLYMACS_WRAPPER_NAME} jobs claim job-000001 --capability frontend --max 2
  ${ONLYMACS_WRAPPER_NAME} jobs work --watch --slots 2 --capability frontend --allow-tests
  ${ONLYMACS_WRAPPER_NAME} watch-provider StudioHost --follow
  ${ONLYMACS_WRAPPER_NAME} chat trusted-only "review this private repo on my Macs only"
  ${ONLYMACS_WRAPPER_NAME} plan coder 3 "design the migration plan"
  ${ONLYMACS_WRAPPER_NAME} --yes start best-available 8 "fan out a test audit"
  ${ONLYMACS_WRAPPER_NAME} --plan:project-plan.md --yes chat "execute this plan"
  ${ONLYMACS_WRAPPER_NAME} --go-wide=4 --plan:project-plan.md --yes chat "execute this plan on four Macs"
  ${ONLYMACS_WRAPPER_NAME} --go-wide=max "use every ticket-board lane available for this audit"
  ${ONLYMACS_WRAPPER_NAME} resume-run latest
  ${ONLYMACS_WRAPPER_NAME} diagnostics latest
  ${ONLYMACS_WRAPPER_NAME} support-bundle latest
  ${ONLYMACS_WRAPPER_NAME} report latest --report "Quality was good; one provider retry added 40s."
  ${ONLYMACS_WRAPPER_NAME} inbox latest
  ${ONLYMACS_WRAPPER_NAME} apply latest
  ${ONLYMACS_WRAPPER_NAME} status latest
  ${ONLYMACS_WRAPPER_NAME} sharing
  ${ONLYMACS_WRAPPER_NAME} version
  ${ONLYMACS_WRAPPER_NAME} watch current
  ${ONLYMACS_WRAPPER_NAME} watch queue
  ${ONLYMACS_WRAPPER_NAME} "what is my latest swarm doing"

Default swarm behavior:
  plain ${ONLYMACS_WRAPPER_NAME} and plain chat requests prefer another Mac when available.
  Use local-first or trusted-only when you want to constrain where the work can run.
EOF
}
