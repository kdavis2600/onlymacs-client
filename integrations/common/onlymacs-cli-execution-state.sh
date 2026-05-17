# Execution policy, batch checkpoint, failure classification, and provider health helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after artifact helpers are loaded.

onlymacs_validator_version() {
  printf '2026-04-30.1'
}

onlymacs_model_is_large_or_cold() {
  local model
  model="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$model" \
    "q8_0" \
    "qwen2.5-coder:32b" \
    "qwen3.6:35b" \
    "gemma4:31b" \
    "70b" \
    "72b" \
    "90b" \
    "120b" \
    "180b" \
    "405b" \
    "671b" \
    "deepseek-r1" \
    "gpt-oss:120b"
}

onlymacs_prompt_is_large_structured() {
  local prompt="${1:-}"
  local filename="${2:-}"
  local lowered expected_count
  lowered="$(printf '%s\n%s' "$filename" "$prompt" | tr '[:upper:]' '[:lower:]')"
  expected_count="$(prompt_exact_count_requirement "$prompt" || true)"
  if [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge 40 ]]; then
    return 0
  fi
  string_has_any "$lowered" \
    "plan file" \
    "checkpoint" \
    "batch" \
    "exactly" \
    "validate" \
    "schema" \
    "json" \
    "artifact" \
    "pipeline" \
    "go-wide" \
    "multi-step"
}

onlymacs_timeout_class() {
  local model="${1:-}"
  local prompt="${2:-}"
  local filename="${3:-}"
  if onlymacs_model_is_large_or_cold "$model"; then
    printf 'large_or_cold_model'
  elif onlymacs_prompt_is_large_structured "$prompt" "$filename"; then
    printf 'large_structured_job'
  else
    printf 'standard'
  fi
}

onlymacs_timeout_policy_json() {
  local model="${1:-${ONLYMACS_ACTIVE_MODEL:-${ONLYMACS_CHAT_ACTIVE_MODEL:-}}}"
  local prompt="${2:-}"
  local filename="${3:-}"
  local first_progress idle max_wall heartbeat preview timeout_class adaptive
  local default_first default_idle default_max

  timeout_class="$(onlymacs_timeout_class "$model" "$prompt" "$filename")"
  adaptive=true
  case "$timeout_class" in
    large_or_cold_model)
      default_first=420
      default_idle=600
      default_max=10800
      ;;
    large_structured_job)
      default_first=300
      default_idle=420
      default_max=10800
      ;;
    *)
      default_first=120
      default_idle=120
      default_max=7200
      ;;
  esac

  first_progress="${ONLYMACS_FIRST_PROGRESS_TIMEOUT_SECONDS:-$default_first}"
  idle="${ONLYMACS_IDLE_TIMEOUT_SECONDS:-$default_idle}"
  max_wall="${ONLYMACS_MAX_WALL_CLOCK_TIMEOUT_SECONDS:-$default_max}"
  heartbeat="${ONLYMACS_PROGRESS_INTERVAL:-30}"
  preview="${ONLYMACS_TERMINAL_PREVIEW_BYTES:-12000}"
  [[ "$first_progress" =~ ^[0-9]+$ ]] || first_progress="$default_first"
  [[ "$idle" =~ ^[0-9]+$ ]] || idle="$default_idle"
  [[ "$max_wall" =~ ^[0-9]+$ ]] || max_wall="$default_max"
  [[ "$heartbeat" =~ ^[0-9]+$ ]] || heartbeat=30
  [[ "$preview" =~ ^[0-9]+$ ]] || preview=12000
  jq -cn \
    --arg timeout_class "$timeout_class" \
    --argjson adaptive "$adaptive" \
    --argjson first_progress "$first_progress" \
    --argjson idle "$idle" \
    --argjson max_wall "$max_wall" \
    --argjson heartbeat "$heartbeat" \
    --argjson preview "$preview" \
    '{
      adaptive: $adaptive,
      class: $timeout_class,
      first_progress_timeout_seconds: $first_progress,
      idle_timeout_seconds: $idle,
      max_wall_clock_timeout_seconds: $max_wall,
      provider_heartbeat_seconds: $heartbeat,
      terminal_preview_limit_bytes: $preview
    }'
}

onlymacs_apply_timeout_policy_json() {
  local policy_json="${1:-}"
  local value
  [[ -n "$policy_json" ]] || policy_json="{}"
  value="$(jq -r '.first_progress_timeout_seconds // empty' <<<"$policy_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_FIRST_PROGRESS_TIMEOUT_SECONDS="$value"
  value="$(jq -r '.idle_timeout_seconds // empty' <<<"$policy_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_IDLE_TIMEOUT_SECONDS="$value"
  value="$(jq -r '.max_wall_clock_timeout_seconds // empty' <<<"$policy_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_MAX_WALL_CLOCK_TIMEOUT_SECONDS="$value"
  value="$(jq -r '.provider_heartbeat_seconds // empty' <<<"$policy_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_PROGRESS_INTERVAL="$value"
  value="$(jq -r '.terminal_preview_limit_bytes // empty' <<<"$policy_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_TERMINAL_PREVIEW_BYTES="$value"
}

onlymacs_schema_contract_json() {
  local prompt="${1:-}"
  local filename="${2:-}"
  local lowered expected_count contract_kind required_fields
  lowered="$(printf '%s\n%s' "$filename" "$prompt" | tr '[:upper:]' '[:lower:]')"
  expected_count="$(prompt_exact_count_requirement "$prompt" || true)"
  contract_kind="generic_artifact"
  required_fields="[]"
  if string_has_any "$lowered" \
    "cards-source" \
    "source-card" \
    "source cards" \
    "lean card source schema" \
    "lean source card"; then
    contract_kind="source_card_items"
    required_fields='["id","setId","teachingOrder","lemma","display","english","pos","stage","register","topic","topicTags","cityTags","grammarNote","dialectNote","example","example_en","usage"]'
  else
    case "$lowered" in
    *vocab*|*vocabulary*)
      contract_kind="vocab_items"
      required_fields='["id","setId","lemma","display","translationsByLocale","pos","stage","register","grammar","supportedPromptModes","defaultPromptMode","source"]'
      ;;
    *sentences*|*sentence*)
      contract_kind="sentence_items"
      required_fields='["id","setId","text","translationsByLocale","register","scenarioTags","cityContextTags","translationMode","supportedPromptModes","defaultPromptMode","segmentation","frequencyBand","patternType","teachingOrder","source","highlights","usage"]'
      ;;
    *lessons*|*lesson*)
      contract_kind="lesson_items"
      required_fields='["id","setId","level","titlesByLocale","scenario","grammarFocus","notes","contentBlocks","quiz"]'
      ;;
    *setdefinitions*|*"set definitions"*)
      contract_kind="set_definitions"
      required_fields='["modules"]'
      ;;
    *.json*|*json*)
      contract_kind="generic_json"
      ;;
    *.js*|*javascript*|*node.js*)
      contract_kind="javascript_artifact"
      ;;
    esac
  fi
  if [[ ! "$expected_count" =~ ^[0-9]+$ ]]; then
    expected_count=0
  fi
  jq -cn \
    --arg kind "$contract_kind" \
    --arg filename "$filename" \
    --argjson expected_count "$expected_count" \
    --argjson required_fields "$required_fields" \
    '{
      version: 1,
      kind: $kind,
      filename: ($filename | if length > 0 then . else null end),
      expected_count: (if $expected_count > 0 then $expected_count else null end),
      required_fields: $required_fields,
      artifact_format: "ONLYMACS_ARTIFACT_BEGIN/END markers; no markdown fences required"
    }'
}

onlymacs_execution_settings_json() {
  local prompt="${1:-}"
  local model_alias="${2:-}"
  local route_scope="${3:-swarm}"
  local step_count="${4:-1}"
  local timeout_policy_json now json_batch_size json_batch_threshold chunk_size chunk_threshold repair_limit max_tokens preview progress_interval provider_route_locked
  local go_wide_enabled go_wide_json_lanes go_wide_shadow_review_mode
  local context_allow_tests context_allow_install
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  timeout_policy_json="$(onlymacs_timeout_policy_json "$(normalize_model_alias "$model_alias")" "$prompt" "$(filename_from_prompt "$prompt" || true)")"
  json_batch_size="$(orchestrated_json_batch_size)"
  json_batch_threshold="$(orchestrated_json_batch_threshold)"
  chunk_size="$(orchestrated_chunk_size)"
  chunk_threshold="$(orchestrated_chunk_threshold)"
  repair_limit="$(orchestrated_repair_limit)"
  max_tokens="$(orchestrated_max_tokens)"
  progress_interval="${ONLYMACS_PROGRESS_INTERVAL:-30}"
  preview="${ONLYMACS_TERMINAL_PREVIEW_BYTES:-12000}"
  [[ "$progress_interval" =~ ^[0-9]+$ ]] || progress_interval=30
  [[ "$preview" =~ ^[0-9]+$ ]] || preview=12000
  if [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" == "1" && -n "${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}" ]]; then
    provider_route_locked=true
  else
    provider_route_locked=false
  fi
  if orchestrated_go_wide_enabled "$model_alias"; then
    go_wide_enabled=true
  else
    go_wide_enabled=false
  fi
  go_wide_json_lanes="$(orchestrated_go_wide_json_lanes "$model_alias")"
  go_wide_shadow_review_mode="$(orchestrated_go_wide_shadow_review_mode "$model_alias")"
  if [[ "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" == "1" ]]; then
    context_allow_tests=true
  else
    context_allow_tests=false
  fi
  if [[ "${ONLYMACS_CONTEXT_ALLOW_INSTALL:-0}" == "1" ]]; then
    context_allow_install=true
  else
    context_allow_install=false
  fi
  jq -cn \
    --arg created_at "$now" \
    --arg execution_mode "${ONLYMACS_EXECUTION_MODE:-auto}" \
    --arg model_alias "$model_alias" \
    --arg route_scope "$route_scope" \
    --arg go_wide_shadow_review_mode "$go_wide_shadow_review_mode" \
    --arg context_read_mode "${ONLYMACS_CONTEXT_READ_MODE:-auto}" \
    --arg context_write_mode "${ONLYMACS_CONTEXT_WRITE_MODE:-auto}" \
    --arg validator_version "$(onlymacs_validator_version)" \
    --argjson step_count "${step_count:-1}" \
    --argjson json_batch_size "$json_batch_size" \
    --argjson json_batch_threshold "$json_batch_threshold" \
    --argjson chunk_size "$chunk_size" \
    --argjson chunk_threshold "$chunk_threshold" \
    --argjson repair_limit "$repair_limit" \
    --argjson max_tokens "$max_tokens" \
    --argjson progress_interval "$progress_interval" \
    --argjson terminal_preview_limit "$preview" \
    --argjson timeout_policy "$timeout_policy_json" \
    --argjson provider_route_locked "$provider_route_locked" \
    --argjson go_wide_enabled "$go_wide_enabled" \
    --argjson go_wide_json_lanes "$go_wide_json_lanes" \
    --argjson context_allow_tests "$context_allow_tests" \
    --argjson context_allow_install "$context_allow_install" \
    --arg pinned_provider_id "${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}" \
    '{
      version: 1,
      created_at: $created_at,
      execution_mode: $execution_mode,
      model_alias: ($model_alias | if length > 0 then . else null end),
      route_scope: $route_scope,
      step_count: $step_count,
      json_batch_size: $json_batch_size,
      json_batch_threshold: $json_batch_threshold,
      chunk_size: $chunk_size,
      chunk_threshold: $chunk_threshold,
      repair_limit: $repair_limit,
      max_tokens: $max_tokens,
      progress_interval_seconds: $progress_interval,
      terminal_preview_limit_bytes: $terminal_preview_limit,
      timeout_policy: $timeout_policy,
      validator_version: $validator_version,
      retry_policy: {
        classify_failures: true,
        repair_before_warning: true,
        retry_transport_once_when_replay_safe: true,
        reroute_after_provider_specific_failure: true,
        pipeline_local_review_for_go_wide: $go_wide_enabled
      },
      route_continuity: {
        prefer_same_provider_for_followups: (($go_wide_enabled | not) or $provider_route_locked),
        allow_fallback_if_provider_disappears: ($provider_route_locked | not),
        provider_route_locked: $provider_route_locked,
        pinned_provider_id: ($pinned_provider_id | if length > 0 then . else null end)
      },
      go_wide: {
        enabled: $go_wide_enabled,
        json_batch_lanes: $go_wide_json_lanes,
        provider_affinity: (if $go_wide_enabled then "relaxed_between_batches" else "sticky_provider" end),
        local_shadow_review: (if $go_wide_enabled then $go_wide_shadow_review_mode else "sync" end),
        scheduling: (if $go_wide_enabled then "remote_generation_with_async_local_review_sidecar" else "serial" end)
      },
      context_policy: {
        read_mode: $context_read_mode,
        write_mode: $context_write_mode,
        allow_tests: $context_allow_tests,
        allow_dependency_install: $context_allow_install,
        ticket_locks_required: true,
        return_artifacts: true,
        apply_default: (if $context_write_mode == "direct_write" then "direct_write_opt_in" elif $context_write_mode == "staged_apply" then "staged_apply" else "inbox" end)
      },
      artifact_policy: {
        machine_markers_required: true,
        preserve_partial_output: true,
        save_large_outputs_as_artifacts_first: true
      }
    }'
}

orchestrated_restore_execution_settings() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local settings_json validator_version current_version stored_version
  [[ -f "$plan_path" ]] || return 0
  settings_json="$(jq -c '.execution_settings // {}' "$plan_path" 2>/dev/null || printf '{}')"
  [[ "$settings_json" != "{}" ]] || return 0

  ONLYMACS_EXECUTION_MODE="$(jq -r '.execution_mode // env.ONLYMACS_EXECUTION_MODE // "auto"' <<<"$settings_json" 2>/dev/null || printf 'auto')"
  validator_version="$(jq -r '.validator_version // empty' <<<"$settings_json" 2>/dev/null || true)"
  stored_version="$validator_version"
  current_version="$(onlymacs_validator_version)"
  if [[ -n "$stored_version" && "$stored_version" != "$current_version" ]]; then
    onlymacs_log_run_event "validator_version_changed" "" "running" "0" "Run was created with validator ${stored_version}; current validator is ${current_version}." "" "" "" "" "" "$plan_path"
  fi

  local value
  value="$(jq -r '.json_batch_size // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_JSON_BATCH_SIZE="$value"
  value="$(jq -r '.json_batch_threshold // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_JSON_BATCH_THRESHOLD="$value"
  value="$(jq -r '.chunk_size // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_CHUNK_SIZE="$value"
  value="$(jq -r '.chunk_threshold // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_CHUNK_THRESHOLD="$value"
  value="$(jq -r '.max_tokens // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && ONLYMACS_ORCHESTRATED_MAX_TOKENS="$value"
  value="$(jq -r '.go_wide.enabled // empty' <<<"$settings_json" 2>/dev/null || true)"
  if [[ "$value" == "true" ]]; then
    ONLYMACS_GO_WIDE_MODE=1
  fi
  value="$(jq -r '.go_wide.json_batch_lanes // empty' <<<"$settings_json" 2>/dev/null || true)"
  if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 && -z "${ONLYMACS_GO_WIDE_JSON_LANES:-}" ]]; then
    ONLYMACS_GO_WIDE_JSON_LANES="$value"
  fi
  value="$(jq -r '.go_wide.local_shadow_review // empty' <<<"$settings_json" 2>/dev/null || true)"
  if [[ "$value" == "sync" || "$value" == "async" || "$value" == "off" ]]; then
    ONLYMACS_GO_WIDE_SHADOW_REVIEW_MODE="$value"
  fi
  value="$(jq -r '.context_policy.read_mode // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ -n "$value" && "$value" != "auto" && -z "${ONLYMACS_CONTEXT_READ_MODE:-}" ]] && ONLYMACS_CONTEXT_READ_MODE="$value"
  value="$(jq -r '.context_policy.write_mode // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ -n "$value" && "$value" != "auto" && -z "${ONLYMACS_CONTEXT_WRITE_MODE:-}" ]] && ONLYMACS_CONTEXT_WRITE_MODE="$value"
  value="$(jq -r '.context_policy.allow_tests // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" == "true" && -z "${ONLYMACS_CONTEXT_ALLOW_TESTS:-}" ]] && ONLYMACS_CONTEXT_ALLOW_TESTS=1
  value="$(jq -r '.context_policy.allow_dependency_install // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ "$value" == "true" && -z "${ONLYMACS_CONTEXT_ALLOW_INSTALL:-}" ]] && ONLYMACS_CONTEXT_ALLOW_INSTALL=1
  value="$(jq -c '.timeout_policy // empty' <<<"$settings_json" 2>/dev/null || true)"
  [[ -n "$value" && "$value" != "null" ]] && onlymacs_apply_timeout_policy_json "$value"
  value="$(jq -r '.route_continuity.provider_route_locked // empty' <<<"$settings_json" 2>/dev/null || true)"
  if [[ "$value" == "true" ]]; then
    value="$(jq -r '.route_continuity.pinned_provider_id // empty' <<<"$settings_json" 2>/dev/null || true)"
    if orchestrated_go_wide_enabled ""; then
      ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=0
      ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
      if [[ -n "$value" && "$value" != "null" ]]; then
        onlymacs_log_run_event "go_wide_route_unlocked" "" "running" "0" "OnlyMacs --go-wide relaxed persisted provider pinning so later batches can use any eligible free Mac." "" "$value" "" "" "" "$plan_path"
      fi
    else
      ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=1
      if [[ -z "${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}" && -n "$value" && "$value" != "null" ]]; then
        ONLYMACS_ORCHESTRATION_PROVIDER_ID="$value"
      fi
    fi
  fi
  onlymacs_log_run_event "execution_settings_restored" "" "running" "0" "OnlyMacs restored persisted execution settings for resume." "" "" "" "" "" "$plan_path"
}

orchestrated_backfill_go_wide_resume_settings() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local model_alias="${2:-wide}"
  local route_scope="${3:-swarm}"
  local go_wide_json_lanes go_wide_shadow_review_mode provider_route_locked updated_at tmp_path
  [[ -f "$plan_path" ]] || return 0
  orchestrated_go_wide_enabled "$model_alias" || return 0

  go_wide_json_lanes="$(orchestrated_go_wide_json_lanes "$model_alias")"
  go_wide_shadow_review_mode="$(orchestrated_go_wide_shadow_review_mode "$model_alias")"
  if [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" == "1" && -n "${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}" ]]; then
    provider_route_locked=true
  else
    provider_route_locked=false
  fi
  updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp_path="$(mktemp "${plan_path}.tmp.XXXXXX")" || return 1

  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg updated_at "$updated_at" \
    --arg model_alias "wide" \
    --arg route_scope "${route_scope:-swarm}" \
    --arg go_wide_shadow_review_mode "$go_wide_shadow_review_mode" \
    --argjson go_wide_json_lanes "$go_wide_json_lanes" \
    --argjson provider_route_locked "$provider_route_locked" \
    --arg pinned_provider_id "${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}" \
    '
      .model_alias = $model_alias
      | .route_scope = $route_scope
      | .updated_at = $updated_at
      | .execution_settings = (.execution_settings // {})
      | .execution_settings.model_alias = $model_alias
      | .execution_settings.route_scope = $route_scope
      | .execution_settings.retry_policy = (.execution_settings.retry_policy // {})
      | .execution_settings.retry_policy.pipeline_local_review_for_go_wide = true
      | .execution_settings.route_continuity = (.execution_settings.route_continuity // {})
      | .execution_settings.route_continuity.prefer_same_provider_for_followups = ($provider_route_locked)
      | .execution_settings.route_continuity.allow_fallback_if_provider_disappears = ($provider_route_locked | not)
      | .execution_settings.route_continuity.provider_route_locked = $provider_route_locked
      | .execution_settings.route_continuity.pinned_provider_id = (
          if $provider_route_locked and ($pinned_provider_id | length > 0) then $pinned_provider_id else null end
        )
      | .execution_settings.go_wide = {
          enabled: true,
          json_batch_lanes: $go_wide_json_lanes,
          provider_affinity: (if $provider_route_locked then "locked_provider" else "relaxed_between_batches" end),
          local_shadow_review: $go_wide_shadow_review_mode,
          scheduling: "remote_generation_with_async_local_review_sidecar"
        }
    ' "$plan_path" >"$tmp_path" && mv "$tmp_path" "$plan_path"
  local jq_status=$?
  [[ "$jq_status" -eq 0 ]] || rm -f "$tmp_path"
  orchestrated_release_plan_lock "$plan_path"
  [[ "$jq_status" -eq 0 ]] || return "$jq_status"
  onlymacs_log_run_event "go_wide_resume_settings_backfilled" "" "running" "0" "OnlyMacs updated this resumed plan with durable --go-wide scheduling settings." "" "" "" "" "" "$plan_path"
}

orchestrated_resume_failed_provider_id() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  [[ -f "$plan_path" ]] || return 1
  jq -r '
    [
      .steps[]?.batching.batches[]?
      | (.status // "") as $status
      | (.message // "") as $message
      | select(
          ($status == "partial")
          or ($status == "queued")
          or (
            (["churn", "failed"] | index($status))
            and ($message | test("stream|transport|timeout|timed out|http 5|504|502|503|bridge|capacity|unavailable|context deadline|connection|empty reply|eof|detached"; "i"))
            and (($message | test("validation|schema|duplicate|source-card|lean source|usage note"; "i")) | not)
          )
        )
      | (.provider_id // empty)
    ]
    | last // empty
  ' "$plan_path" 2>/dev/null
}

orchestrated_go_wide_has_alternate_resume_provider() {
  local failed_provider_id="${1:-}"
  local route_scope="${2:-swarm}"
  local model="${3:-}"
  local body
  [[ -n "$failed_provider_id" ]] || return 1
  body="$(onlymacs_fetch_admin_status)" || return 1
  jq -e \
    --arg failed_provider_id "$failed_provider_id" \
    --arg route_scope "$route_scope" \
    --arg model "$model" '
      def provider_id: (.provider_id // .id // "");
      def provider_status: ((.status // "available") | ascii_downcase);
      def provider_free_slots: ((.slots.free // .slots_free // 0) | tonumber? // 0);
      def model_free_slots: ((.slots_free // .slots.total // 1) | tonumber? // 1);
      def supports_model:
        ($model | length) == 0
        or any(.models[]?; ((.id // .name // "") == $model) and (model_free_slots > 0));
      [
        (.members[]?.capabilities[]?),
        (.providers[]?)
      ]
      | map(
          select(provider_id != "" and provider_id != $failed_provider_id)
          | select(provider_status == "available")
          | select(provider_free_slots > 0)
          | select(supports_model)
        )
      | length > 0
    ' <<<"$body" >/dev/null 2>&1
}

orchestrated_apply_go_wide_resume_provider_avoidance() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local model_alias="${2:-wide}"
  local route_scope="${3:-swarm}"
  local failed_resume_provider_id resume_model
  failed_resume_provider_id="$(orchestrated_resume_failed_provider_id "$plan_path" || true)"
  [[ -n "$failed_resume_provider_id" ]] || return 0

  ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="$(onlymacs_json_add_unique_string "${ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON:-[]}" "$failed_resume_provider_id")"
  resume_model="${ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE:-$(normalize_model_alias "$model_alias")}"
  if orchestrated_go_wide_has_alternate_resume_provider "$failed_resume_provider_id" "$route_scope" "$resume_model"; then
    ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="$(onlymacs_json_add_unique_string "${ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON:-[]}" "$failed_resume_provider_id")"
    onlymacs_log_run_event "go_wide_resume_excluding_failed_provider" "" "running" "0" "OnlyMacs --go-wide is resuming this failed micro-batch on another eligible Mac before retrying the provider that just dropped the stream." "" "$failed_resume_provider_id" "" "" "" "$plan_path"
  else
    onlymacs_log_run_event "go_wide_resume_avoiding_failed_provider" "" "running" "0" "OnlyMacs --go-wide is avoiding the failed provider as a preference, but it stayed eligible because no alternate provider is currently visible for this route/model." "" "$failed_resume_provider_id" "" "" "" "$plan_path"
  fi
}

orchestrated_stored_json_batch_size() {
  local step_id="${1:-}"
  local filename="${2:-}"
  local plan_path="${3:-$(orchestrated_plan_path)}"
  local stored
  [[ -f "$plan_path" && -n "$step_id" ]] || return 1
  stored="$(jq -r --arg step_id "$step_id" --arg filename "$filename" '
    (.steps[]? | select(.id == $step_id) | .batching // {}) as $batching
    | if (($batching.filename // "") == $filename or ($batching.filename // "") == "") then ($batching.batch_size // empty) else empty end
  ' "$plan_path" 2>/dev/null || true)"
  [[ "$stored" =~ ^[0-9]+$ && "$stored" -gt 0 ]] || return 1
  printf '%s' "$stored"
}

orchestrated_record_json_batch_policy() {
  local step_id="${1:-}"
  local filename="${2:-}"
  local expected_count="${3:-0}"
  local batch_size="${4:-1}"
  local batch_count="${5:-1}"
  local validation_prompt="${6:-}"
  local plan_path now threshold contract_json batches_json items_per_set go_wide_batch_group_size
  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" && -n "$step_id" ]] || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  threshold="$(orchestrated_json_batch_threshold)"
  contract_json="$(onlymacs_schema_contract_json "$validation_prompt" "$filename")"
  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  if [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 && "$batch_size" =~ ^[0-9]+$ && "$batch_size" -gt 0 ]]; then
    go_wide_batch_group_size=$(((items_per_set + batch_size - 1) / batch_size))
  else
    items_per_set=0
    go_wide_batch_group_size=1
  fi
  [[ "$go_wide_batch_group_size" -gt 0 ]] || go_wide_batch_group_size=1
  batches_json="$(jq -cn \
    --arg filename "$filename" \
    --argjson batch_size "$batch_size" \
    --argjson expected_count "$expected_count" \
    --argjson batch_count "$batch_count" \
    '[range(1; ($batch_count + 1)) as $i | {
      index: $i,
      filename: (($filename | sub("\\.json$"; "")) + ".batch-" + ($i | tostring | if length == 1 then "0" + . else . end) + ".json"),
      start_item: ((($i - 1) * $batch_size) + 1),
      end_item: (if (($i * $batch_size) > $expected_count) then $expected_count else ($i * $batch_size) end),
      count: ((if (($i * $batch_size) > $expected_count) then $expected_count else ($i * $batch_size) end) - ((($i - 1) * $batch_size) + 1) + 1),
      status: "pending"
    }]')"
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg filename "$filename" \
    --arg updated_at "$now" \
    --arg validator_version "$(onlymacs_validator_version)" \
    --argjson expected_count "$expected_count" \
    --argjson batch_size "$batch_size" \
	    --argjson batch_count "$batch_count" \
	    --argjson threshold "$threshold" \
	    --argjson items_per_set "$items_per_set" \
	    --argjson go_wide_batch_group_size "$go_wide_batch_group_size" \
	    --argjson contract "$contract_json" \
    --argjson batches "$batches_json" \
    '.steps = (.steps | map(if .id == $step_id then
      . + {
        batching: {
          type: "json_array",
          filename: $filename,
          expected_count: $expected_count,
          batch_size: $batch_size,
          batch_count: $batch_count,
	          threshold: $threshold,
	          item_range_strategy: "sequential_micro_batches",
	          validator_version: $validator_version,
	          ticket_board: {
	            fresh_ticket_group_strategy: (if $go_wide_batch_group_size > 1 then "stripe_across_item_sets" else "sequential" end),
	            items_per_set: (if $items_per_set > 0 then $items_per_set else null end),
	            batch_group_size: $go_wide_batch_group_size
	          },
	          schema_contract: $contract,
          batches: (((.batching.batches // []) | if length == $batch_count then . else $batches end))
        }
      }
    else . end))
    | .updated_at = $updated_at' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
}

orchestrated_json_batch_status_is_accepted() {
  case "${1:-}" in
    completed|reused|recovered|completed_from_partial)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

orchestrated_json_batch_current_status() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-}"
  local batch_index="${3:-0}"
  [[ -f "$plan_path" && -n "$step_id" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 0
  jq -r --arg step_id "$step_id" --argjson batch_index "$batch_index" '
    [.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $batch_index) | .status // empty] | first // empty
  ' "$plan_path" 2>/dev/null || true
}

orchestrated_json_batch_accepted_snapshot_path() {
  local artifact_path="${1:-}"
  [[ -n "$artifact_path" ]] || return 1
  printf '%s.accepted' "$artifact_path"
}

orchestrated_json_artifact_parses() {
  local artifact_path="${1:-}"
  [[ -s "$artifact_path" ]] || return 1
  if [[ "$artifact_path" == *.json || "$artifact_path" == *.json.accepted ]]; then
    command -v jq >/dev/null 2>&1 || return 1
    jq -e . "$artifact_path" >/dev/null 2>&1
    return $?
  fi
  return 0
}

orchestrated_restore_accepted_json_batch_artifact_if_possible() {
  local step_id="${1:-}"
  local batch_index="${2:-0}"
  local artifact_path="${3:-}"
  local plan_path status snapshot_path
  plan_path="$(orchestrated_plan_path)"
  [[ -n "$artifact_path" ]] || return 1
  status="$(orchestrated_json_batch_current_status "$plan_path" "$step_id" "$batch_index")"
  orchestrated_json_batch_status_is_accepted "$status" || return 1
  snapshot_path="$(orchestrated_json_batch_accepted_snapshot_path "$artifact_path")" || return 1
  if orchestrated_json_artifact_parses "$artifact_path"; then
    if [[ ! -s "$snapshot_path" ]]; then
      mkdir -p "$(dirname "$snapshot_path")" || return 1
      cp "$artifact_path" "$snapshot_path"
    fi
    return 0
  fi
  if orchestrated_json_artifact_parses "$snapshot_path"; then
    mkdir -p "$(dirname "$artifact_path")" || return 1
    cp "$snapshot_path" "$artifact_path"
    return 0
  fi
  return 1
}

orchestrated_go_wide_worker_lease_matches() {
  local step_id="${1:-}"
  local batch_index="${2:-0}"
  local expected_lease="${ONLYMACS_GO_WIDE_WORKER_LEASE_ID:-}"
  local plan_path current_lease
  [[ -n "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" ]] || return 0
  [[ -n "$expected_lease" ]] || return 0
  [[ "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 0
  if [[ "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" =~ ^[0-9]+$ && "$ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX" -ne "$batch_index" ]]; then
    return 1
  fi
  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" ]] || return 0
  current_lease="$(jq -r --arg step_id "$step_id" --argjson batch_index "$batch_index" '
    [.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $batch_index) | .lease_id // empty] | first // empty
  ' "$plan_path" 2>/dev/null || true)"
  [[ -z "$current_lease" || "$current_lease" == "$expected_lease" ]]
}

orchestrated_log_stale_go_wide_worker_ignored() {
  local step_id="${1:-step-01}"
  local batch_index="${2:-0}"
  local message="${3:-stale go-wide worker lease did not match the ticket board lease}"
  onlymacs_log_run_event "go_wide_stale_worker_ignored" "$step_id" "running" "0" "Ignored stale worker update for batch ${batch_index}: ${message}" "" "" "This Mac" "" "" "$(orchestrated_plan_path)"
}

orchestrated_json_batch_can_write_checkpoint() {
  local step_id="${1:-}"
  local batch_index="${2:-0}"
  local artifact_path="${3:-}"
  local status
  if ! orchestrated_go_wide_worker_lease_matches "$step_id" "$batch_index"; then
    orchestrated_log_stale_go_wide_worker_ignored "$step_id" "$batch_index" "checkpoint write skipped because the worker lease was superseded"
    return 1
  fi
  status="$(orchestrated_json_batch_current_status "$(orchestrated_plan_path)" "$step_id" "$batch_index")"
  if orchestrated_json_batch_status_is_accepted "$status"; then
    orchestrated_restore_accepted_json_batch_artifact_if_possible "$step_id" "$batch_index" "$artifact_path" || true
    return 1
  fi
  return 0
}

orchestrated_promote_json_batch_artifact() {
  local source_path="${1:-}"
  local target_path="${2:-}"
  local step_id="${3:-}"
  local batch_index="${4:-0}"
  local status="${5:-completed}"
  local plan_path current_status snapshot_path
  [[ -n "$source_path" && -n "$target_path" && -s "$source_path" ]] || return 1
  if ! orchestrated_go_wide_worker_lease_matches "$step_id" "$batch_index"; then
    orchestrated_log_stale_go_wide_worker_ignored "$step_id" "$batch_index" "accepted artifact promotion skipped because the worker lease was superseded"
    return 1
  fi
  plan_path="$(orchestrated_plan_path)"
  current_status="$(orchestrated_json_batch_current_status "$plan_path" "$step_id" "$batch_index")"
  snapshot_path="$(orchestrated_json_batch_accepted_snapshot_path "$target_path")" || return 1
  if orchestrated_json_batch_status_is_accepted "$current_status"; then
    if orchestrated_restore_accepted_json_batch_artifact_if_possible "$step_id" "$batch_index" "$target_path"; then
      return 0
    fi
    orchestrated_json_batch_status_is_accepted "$status" || return 0
  fi
  mkdir -p "$(dirname "$target_path")" "$(dirname "$snapshot_path")" || return 1
  if [[ "$source_path" != "$target_path" ]]; then
    cp "$source_path" "$target_path"
  fi
  if orchestrated_json_batch_status_is_accepted "$status"; then
    if orchestrated_json_artifact_parses "$target_path"; then
      cp "$target_path" "$snapshot_path"
    elif orchestrated_json_artifact_parses "$source_path"; then
      cp "$source_path" "$snapshot_path"
    fi
  fi
  return 0
}

orchestrated_record_go_wide_lane_metric() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-step-01}"
  local provider_id="${3:-}"
  local model="${4:-}"
  local duration_seconds="${5:-0}"
  local outcome="${6:-success}"
  local now
  [[ -f "$plan_path" ]] || return 0
  [[ "$duration_seconds" =~ ^[0-9]+$ ]] || duration_seconds=0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg provider_id "$provider_id" \
    --arg model "$model" \
    --arg outcome "$outcome" \
    --arg updated_at "$now" \
    --argjson duration "$duration_seconds" \
    '
      .steps = (.steps | map(if .id == $step_id then
        . + {
          batching: ((.batching // {}) + {
            ticket_board: ((.batching.ticket_board // {}) + {
              metrics: ((.batching.ticket_board.metrics // {}) as $m | $m + {
                worker_seconds: (($m.worker_seconds // 0) + $duration),
                completed_tickets: (($m.completed_tickets // 0) + (if $outcome == "success" then 1 else 0 end)),
                failed_tickets: (($m.failed_tickets // 0) + (if $outcome == "success" then 0 else 1 end)),
                provider_seconds: (($m.provider_seconds // {}) + (if ($provider_id | length) > 0 then {
                  ($provider_id): (((($m.provider_seconds // {})[$provider_id]) // 0) + $duration)
                } else {} end)),
                model_seconds: (($m.model_seconds // {}) + (if ($model | length) > 0 then {
                  ($model): (((($m.model_seconds // {})[$model]) // 0) + $duration)
                } else {} end)),
                last_worker_outcome: $outcome,
                updated_at: $updated_at
              })
            })
          })
        }
      else . end))
      | .updated_at = $updated_at
    ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
}

orchestrated_record_go_wide_idle_metric() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-step-01}"
  local reason="${3:-poll}"
  local seconds="${4:-0}"
  local lanes="${5:-0}"
  local active="${6:-0}"
  local idle_lanes now
  [[ -f "$plan_path" ]] || return 0
  [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=0
  [[ "$lanes" =~ ^[0-9]+$ ]] || lanes=0
  [[ "$active" =~ ^[0-9]+$ ]] || active=0
  idle_lanes=$((lanes - active))
  [[ "$idle_lanes" -lt 0 ]] && idle_lanes=0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg reason "$reason" \
    --arg updated_at "$now" \
    --argjson seconds "$seconds" \
    --argjson idle_lanes "$idle_lanes" \
    '
      .steps = (.steps | map(if .id == $step_id then
        . + {
          batching: ((.batching // {}) + {
            ticket_board: ((.batching.ticket_board // {}) + {
              metrics: ((.batching.ticket_board.metrics // {}) as $m | $m + {
                idle_seconds: (($m.idle_seconds // 0) + $seconds),
                idle_lane_seconds: (($m.idle_lane_seconds // 0) + ($seconds * $idle_lanes)),
                idle_reasons: (($m.idle_reasons // {}) + {
                  ($reason): (((($m.idle_reasons // {})[$reason]) // 0) + $seconds)
                }),
                updated_at: $updated_at
              })
            })
          })
        }
      else . end))
      | .updated_at = $updated_at
    ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
}

orchestrated_mark_go_wide_finalizer() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-step-01}"
  local state="${3:-started}"
  local now
  [[ -f "$plan_path" ]] || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg state "$state" \
    --arg pid "$$" \
    --arg updated_at "$now" \
    '
      .steps = (.steps | map(if .id == $step_id then
        . + {
          batching: ((.batching // {}) + {
            ticket_board: ((.batching.ticket_board // {}) + {
              finalizer_state: $state,
              finalizer_pid: $pid,
              finalizer_updated_at: $updated_at
            })
          })
        }
      else . end))
      | .updated_at = $updated_at
    ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
}

orchestrated_update_json_batch_status() {
  local step_id="${1:-}"
  local batch_index="${2:-0}"
  local batch_count="${3:-0}"
  local status="${4:-running}"
  local artifact_path="${5:-}"
  local provider_id="${6:-}"
  local provider_name="${7:-}"
  local model="${8:-}"
  local message="${9:-}"
  local plan_path now now_epoch completed_batches step_index steps_total completed_steps base_percent step_weight batch_percent total_percent phase_detail
  local output_bytes output_tokens input_tokens prompt_tokens
  local target_status target_accepted new_accepted
  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" && -n "$step_id" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 0
  if ! orchestrated_go_wide_worker_lease_matches "$step_id" "$batch_index"; then
    orchestrated_log_stale_go_wide_worker_ignored "$step_id" "$batch_index" "status ${status} skipped because the worker lease was superseded"
    return 0
  fi
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now_epoch="$(date +%s)"
  step_index="${step_id#step-}"
  [[ "$step_index" =~ ^[0-9]+$ ]] && step_index=$((10#$step_index)) || step_index=1
  steps_total="$(jq -r '.steps | length' "$plan_path" 2>/dev/null || printf '1')"
  completed_steps="$(jq -r '[.steps[]? | select(.status == "completed")] | length' "$plan_path" 2>/dev/null || printf '0')"
  completed_batches="$(jq -r --arg step_id "$step_id" '[.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.status == "completed" or .status == "reused" or .status == "recovered" or .status == "completed_from_partial")] | length' "$plan_path" 2>/dev/null || printf '0')"
  target_status="$(jq -r --arg step_id "$step_id" --argjson batch_index "$batch_index" '[.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $batch_index) | .status // empty] | first // empty' "$plan_path" 2>/dev/null || true)"
  target_accepted=0
  new_accepted=0
  if orchestrated_json_batch_status_is_accepted "$target_status"; then
    target_accepted=1
  fi
  if orchestrated_json_batch_status_is_accepted "$status"; then
    new_accepted=1
  fi
  if [[ "$target_accepted" -eq 1 && "$new_accepted" -eq 0 ]]; then
    return 0
  fi
  if [[ "$new_accepted" -eq 1 && "$target_accepted" -eq 0 ]]; then
    completed_batches=$((completed_batches + 1))
  fi
  [[ "$steps_total" =~ ^[0-9]+$ && "$steps_total" -gt 0 ]] || steps_total=1
  [[ "$batch_count" =~ ^[0-9]+$ && "$batch_count" -gt 0 ]] || batch_count=1
  base_percent=$(((completed_steps * 100) / steps_total))
  step_weight=$((100 / steps_total))
  [[ "$step_weight" -gt 0 ]] || step_weight=1
  batch_percent=$(((completed_batches * 100) / batch_count))
  [[ "$batch_percent" -gt 100 ]] && batch_percent=100
  total_percent=$((base_percent + ((step_weight * batch_percent) / 100)))
  [[ "$total_percent" -gt 99 && "$completed_steps" -lt "$steps_total" ]] && total_percent=99
  phase_detail="${message:-batch ${batch_index}/${batch_count}: ${status}}"
  output_bytes="$(chat_output_bytes "$artifact_path")"
  output_tokens="$(chat_estimated_tokens "$output_bytes")"
  input_tokens="${ONLYMACS_CURRENT_BATCH_INPUT_TOKENS_ESTIMATE:-0}"
  if [[ ! "$input_tokens" =~ ^[0-9]+$ || "$input_tokens" -le 0 ]]; then
    prompt_tokens="$(orchestrated_token_estimate_for_path "$(orchestrated_prompt_path)")"
    [[ "$prompt_tokens" =~ ^[0-9]+$ ]] || prompt_tokens=0
    if [[ "$prompt_tokens" -gt 0 && "$batch_count" -gt 0 ]]; then
      input_tokens=$(((prompt_tokens + batch_count - 1) / batch_count))
    else
      input_tokens=0
    fi
  fi
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg status "$status" \
    --arg artifact_path "$artifact_path" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg message "$message" \
    --arg updated_at "$now" \
    --arg phase_detail "$phase_detail" \
    --argjson batch_index "$batch_index" \
    --argjson batch_count "$batch_count" \
    --argjson completed_batches "$completed_batches" \
    --argjson batch_percent "$batch_percent" \
    --argjson total_percent "$total_percent" \
    --argjson now_epoch "$now_epoch" \
    --argjson output_bytes "$output_bytes" \
    --argjson output_tokens "$output_tokens" \
    --argjson input_tokens "$input_tokens" \
    'def accepted($s): ["completed","reused","recovered","completed_from_partial"] | index($s);
    def active($s): ["started","running","repairing","waiting_for_transport"] | index($s);
    def failed($s): ["failed","failed_validation","needs_local_salvage","churn"] | index($s);
    . as $plan
    | ((.created_at // $updated_at) | fromdateiso8601? // $now_epoch) as $created_epoch
    | (if $completed_batches > 0 and $batch_count > $completed_batches then (((($now_epoch - $created_epoch) / $completed_batches) * ($batch_count - $completed_batches)) | floor) else null end) as $batch_eta
    | .steps = (.steps | map(if .id == $step_id then
      . + {
        batching: ((.batching // {}) + {
          current_batch_index: $batch_index,
          completed_count: $completed_batches,
          estimated_remaining_seconds: $batch_eta,
          batches: ((.batching.batches // []) | map(if .index == $batch_index then
            . as $ticket
            | ($ticket.leased_at // null) as $leased_at
            | ($ticket.started_at // (if active($status) or accepted($status) or failed($status) then $updated_at else null end)) as $started_at
            | (if accepted($status) then $updated_at else ($ticket.completed_at // null) end) as $completed_at
            | (if failed($status) then $updated_at else ($ticket.failed_at // null) end) as $failed_at
            | ($completed_at // $failed_at) as $ended_at
            | . + {
              status: $status,
              updated_at: $updated_at,
              started_at: $started_at,
              completed_at: $completed_at,
              failed_at: $failed_at,
              wait_seconds: (if ($ticket.wait_seconds // 0) > 0 then $ticket.wait_seconds elif ($leased_at != null and $started_at != null) then (((($started_at | fromdateiso8601? // $now_epoch) - ($leased_at | fromdateiso8601? // $now_epoch)) | floor) | if . > 0 then . else null end) else null end),
              duration_seconds: (if ($ended_at != null and $started_at != null) then (((($ended_at | fromdateiso8601? // $now_epoch) - ($started_at | fromdateiso8601? // $now_epoch)) | floor) | if . > 0 then . else null end) else ($ticket.duration_seconds // null) end),
              input_tokens_estimate: (if $input_tokens > 0 then $input_tokens else ($ticket.input_tokens_estimate // null) end),
              output_bytes: (if $output_bytes > 0 then $output_bytes else ($ticket.output_bytes // null) end),
              output_tokens_estimate: (if $output_tokens > 0 then $output_tokens else ($ticket.output_tokens_estimate // null) end),
              artifact_path: ($artifact_path | if length > 0 then . else null end),
              provider_id: ($provider_id | if length > 0 then . else null end),
              provider_name: ($provider_name | if length > 0 then . else null end),
              model: ($model | if length > 0 then . else null end),
              message: ($message | if length > 0 then . else null end)
            }
          else . end))
        })
      }
    else . end))
    | .updated_at = $updated_at
    | .progress = ((.progress // {}) + {
      phase: ("batch_" + $status),
      step_id: $step_id,
      step_index: ((($step_id | capture("step-(?<n>[0-9]+)").n) | tonumber) // 1),
      steps_total: (.steps | length),
      batch_index: $batch_index,
      batch_count: $batch_count,
      batch_percent_complete: $batch_percent,
      percent_complete: $total_percent,
      estimated_remaining_seconds: $batch_eta,
      detail: $phase_detail,
      updated_at: $updated_at
    })' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
  orchestrated_sync_running_status "running"
  if [[ "$status" == "reused" && "$batch_index" -ne 1 && "$batch_index" -ne "$batch_count" && $((batch_index % 25)) -ne 0 ]]; then
    return 0
  fi
  orchestrated_emit_plan_progress "$plan_path" "$status"
}

orchestrated_mark_go_wide_repair_ticket() {
  local step_id="${1:-}"
  local batch_index="${2:-0}"
  local validation_message="${3:-}"
  local artifact_path="${4:-}"
  local raw_path="${5:-}"
  local plan_path now
  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" && -n "$step_id" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 0
  if ! orchestrated_go_wide_worker_lease_matches "$step_id" "$batch_index"; then
    orchestrated_log_stale_go_wide_worker_ignored "$step_id" "$batch_index" "repair ticket update skipped because the worker lease was superseded"
    return 0
  fi
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --argjson batch_index "$batch_index" \
    --arg validation_message "$validation_message" \
    --arg artifact_path "$artifact_path" \
    --arg raw_path "$raw_path" \
    --arg updated_at "$now" \
    '
      .steps = (.steps | map(if .id == $step_id then
        . + {
          batching: ((.batching // {}) + {
            batches: ((.batching.batches // []) | map(if .index == $batch_index then
              . + {
                ticket_kind: "repair",
                deferred_validation_message: $validation_message,
                deferred_attempt_artifact_path: ($artifact_path | if length > 0 then . else null end),
                deferred_attempt_raw_path: ($raw_path | if length > 0 then . else null end),
                deferred_at: $updated_at
              }
            else . end))
          })
        }
      else . end))
      | .updated_at = $updated_at
    ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
}

orchestrated_mark_go_wide_retry_ticket() {
  local step_id="${1:-}"
  local batch_index="${2:-0}"
  local retry_message="${3:-}"
  local artifact_path="${4:-}"
  local raw_path="${5:-}"
  local provider_id="${6:-}"
  local provider_name="${7:-}"
  local model="${8:-}"
  local retry_after_seconds="${9:-0}"
  local ticket_kind="${10:-generate}"
  local plan_path now now_epoch retry_after_epoch
  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" && -n "$step_id" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 0
  if ! orchestrated_go_wide_worker_lease_matches "$step_id" "$batch_index"; then
    orchestrated_log_stale_go_wide_worker_ignored "$step_id" "$batch_index" "retry ticket update skipped because the worker lease was superseded"
    return 0
  fi
  [[ "$ticket_kind" == "repair" ]] || ticket_kind="generate"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now_epoch="$(date +%s)"
  [[ "$retry_after_seconds" =~ ^[0-9]+$ ]] || retry_after_seconds=0
  retry_after_epoch=0
  if [[ "$retry_after_seconds" -gt 0 ]]; then
    retry_after_epoch=$((now_epoch + retry_after_seconds))
  fi
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --argjson batch_index "$batch_index" \
    --arg retry_message "$retry_message" \
    --arg artifact_path "$artifact_path" \
    --arg raw_path "$raw_path" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg ticket_kind "$ticket_kind" \
    --arg updated_at "$now" \
    --argjson retry_after_epoch "$retry_after_epoch" \
    '
      .steps = (.steps | map(if .id == $step_id then
        . + {
          batching: ((.batching // {}) + {
            batches: ((.batching.batches // []) | map(if .index == $batch_index then
              . + {
                status: "retry_queued",
                ticket_kind: $ticket_kind,
                deferred_validation_message: $retry_message,
                deferred_attempt_artifact_path: ($artifact_path | if length > 0 then . else null end),
                deferred_attempt_raw_path: ($raw_path | if length > 0 then . else null end),
                deferred_at: $updated_at,
                updated_at: $updated_at,
                provider_id: ($provider_id | if length > 0 then . else null end),
                provider_name: ($provider_name | if length > 0 then . else null end),
                model: ($model | if length > 0 then . else null end),
                retry_after_epoch: (if $retry_after_epoch > 0 then $retry_after_epoch else null end),
                message: ("Go-wide deferred batch " + (.index | tostring) + " for later transport retry: " + $retry_message)
              }
            else . end))
          })
        }
      else . end))
      | .updated_at = $updated_at
    ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
}

onlymacs_classify_failure() {
  local message="${1:-${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-}}"
  local http_status="${2:-${ONLYMACS_LAST_CHAT_HTTP_STATUS:-}}"
  local kind="${3:-${ONLYMACS_LAST_CHAT_FAILURE_KIND:-${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}}}"
  local lowered
  lowered="$(printf '%s %s' "$kind" "$message" | tr '[:upper:]' '[:lower:]')"
  case "$kind" in
    first_progress_timeout)
      printf 'first_token_timeout'
      return 0
      ;;
    reasoning_only_timeout)
      printf 'reasoning_only_timeout'
      return 0
      ;;
    idle_timeout)
      printf 'idle_timeout'
      return 0
      ;;
    max_wall_timeout)
      printf 'wall_clock_timeout'
      return 0
      ;;
    detached_activity_running)
      printf 'activity_still_running'
      return 0
      ;;
  esac
  if [[ "$http_status" == "409" ]]; then
    printf 'capacity_blocked'
  elif string_has_any "$lowered" "installing model" "downloading model" "download in progress" "maintenance"; then
    printf 'provider_maintenance'
  elif string_has_any "$lowered" "bridge" "127.0.0.1" "connection refused" "could not reach"; then
    printf 'bridge_unavailable'
  elif string_has_any "$lowered" "reasoning but no artifact" "reasoning_only"; then
    printf 'reasoning_only_timeout'
  elif string_has_any "$lowered" "first token" "first output token" "model-loading" "model loading"; then
    printf 'first_token_timeout'
  elif string_has_any "$lowered" "idle_timeout" "went idle"; then
    printf 'idle_timeout'
  elif string_has_any "$lowered" "wall-clock" "wall clock" "max_wall"; then
    printf 'wall_clock_timeout'
  elif string_has_any "$lowered" "malformed" "json parse" "not valid json" "not a json" "artifact was not"; then
    printf 'malformed_artifact'
  elif string_has_any "$lowered" "validation" "did not validate" "schema" "duplicate"; then
    printf 'validation_failed'
  elif string_has_any "$lowered" "provider" "remote mac" "unavailable" "disappeared"; then
    printf 'provider_unavailable'
  elif string_has_any "$lowered" "partial" "stream" "curl" "transport"; then
    printf 'transport_drop'
  else
    printf 'unknown'
  fi
}

onlymacs_log_failure_classification() {
  local step_id="${1:-}"
  local attempt="${2:-0}"
  local message="${3:-${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-}}"
  local artifact_path="${4:-}"
  local provider_id="${5:-}"
  local provider_name="${6:-}"
  local model="${7:-}"
  local raw_path="${8:-}"
  local class
  class="$(onlymacs_classify_failure "$message")"
  onlymacs_log_run_event "failure_classified" "$step_id" "failed" "$attempt" "${class}: ${message}" "$artifact_path" "$provider_id" "$provider_name" "$model" "$raw_path" "$(orchestrated_plan_path)"
  printf '%s' "$class"
}

orchestrated_last_chat_is_transient_transport() {
  case "${ONLYMACS_LAST_CHAT_HTTP_STATUS:-}" in
    429|500|502|503|504)
      return 0
      ;;
  esac
  return 1
}

orchestrated_failure_should_try_lower_quant() {
  local failure_class="${1:-}"
  local model="${2:-}"
  case "$failure_class" in
    first_token_timeout|reasoning_only_timeout|idle_timeout|wall_clock_timeout|provider_maintenance)
      onlymacs_model_is_large_or_cold "$model"
      ;;
    *)
      return 1
      ;;
  esac
}

onlymacs_provider_health_path() {
  printf '%s/provider-health.json' "$(onlymacs_state_dir)"
}

onlymacs_update_provider_health() {
  local provider_id="${1:-}"
  local provider_name="${2:-}"
  local model="${3:-}"
  local outcome="${4:-unknown}"
  local failure_class="${5:-}"
  local tokens_per_second="${6:-0}"
  local health_path now key
  [[ -n "$provider_id" || -n "$provider_name" ]] || return 0
  key="${provider_id:-$provider_name}"
  health_path="$(onlymacs_provider_health_path)"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$(dirname "$health_path")" || return 0
  [[ -f "$health_path" ]] || printf '{}\n' >"$health_path"
  [[ "$tokens_per_second" =~ ^[0-9]+([.][0-9]+)?$ ]] || tokens_per_second=0
  jq \
    --arg key "$key" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg outcome "$outcome" \
    --arg failure_class "$failure_class" \
    --arg updated_at "$now" \
    --argjson tps "$tokens_per_second" \
    '.[$key] = ((.[$key] // {
        provider_id: $provider_id,
        provider_name: $provider_name,
        runs: 0,
        successes: 0,
        failures: 0,
        first_token_timeouts: 0,
        idle_timeouts: 0,
        transport_drops: 0,
        validation_failures: 0,
        maintenance_events: 0,
        tps_samples: []
      }) as $entry
      | $entry + {
        provider_id: ($provider_id | if length > 0 then . else ($entry.provider_id // null) end),
        provider_name: ($provider_name | if length > 0 then . else ($entry.provider_name // null) end),
        model: ($model | if length > 0 then . else ($entry.model // null) end),
        last_outcome: $outcome,
        last_failure_class: ($failure_class | if length > 0 then . else null end),
        last_seen: $updated_at,
        runs: (($entry.runs // 0) + 1),
        successes: (($entry.successes // 0) + (if $outcome == "success" then 1 else 0 end)),
        failures: (($entry.failures // 0) + (if $outcome == "failure" then 1 else 0 end)),
        first_token_timeouts: (($entry.first_token_timeouts // 0) + (if $failure_class == "first_token_timeout" then 1 else 0 end)),
        idle_timeouts: (($entry.idle_timeouts // 0) + (if $failure_class == "idle_timeout" then 1 else 0 end)),
        transport_drops: (($entry.transport_drops // 0) + (if $failure_class == "transport_drop" then 1 else 0 end)),
        validation_failures: (($entry.validation_failures // 0) + (if $failure_class == "validation_failed" or $failure_class == "malformed_artifact" then 1 else 0 end)),
        maintenance_events: (($entry.maintenance_events // 0) + (if $failure_class == "provider_maintenance" then 1 else 0 end)),
        tps_samples: ((($entry.tps_samples // []) + (if $tps > 0 then [$tps] else [] end)) | .[-20:])
      })' "$health_path" >"${health_path}.tmp" 2>/dev/null && mv "${health_path}.tmp" "$health_path" || rm -f "${health_path}.tmp"
}
