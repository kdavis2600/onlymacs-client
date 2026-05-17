# Orchestrated execution engine, go-wide batching, and final status helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after run status helpers are loaded.

orchestrated_repair_limit() {
  if [[ -n "${ONLYMACS_REPAIR_LIMIT:-}" && "${ONLYMACS_REPAIR_LIMIT:-}" =~ ^[0-9]+$ && "$ONLYMACS_REPAIR_LIMIT" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_REPAIR_LIMIT"
    return 0
  fi
  case "${ONLYMACS_EXECUTION_MODE:-auto}" in
    overnight)
      printf '3'
      ;;
    *)
      printf '2'
      ;;
  esac
}

orchestrated_max_tokens() {
  if [[ -n "${ONLYMACS_ORCHESTRATED_MAX_TOKENS:-}" && "${ONLYMACS_ORCHESTRATED_MAX_TOKENS:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ONLYMACS_ORCHESTRATED_MAX_TOKENS"
    return 0
  fi
  case "${ONLYMACS_EXECUTION_MODE:-auto}" in
    overnight)
      printf '24000'
      ;;
    extended)
      printf '18000'
      ;;
    *)
      printf '16000'
      ;;
  esac
}

orchestrated_max_tokens_for_step() {
  local prompt="${1:-}"
  local filename="${2:-}"
  local base expected max_tokens
  base="$(orchestrated_max_tokens)"
  max_tokens="$base"
  expected="$(prompt_exact_count_requirement "$prompt" || true)"
  if [[ "$filename" == *.json && "$expected" =~ ^[0-9]+$ ]]; then
    if [[ "$expected" -ge 40 && "$max_tokens" -lt 36000 ]]; then
      max_tokens=36000
    elif [[ "$expected" -ge 20 && "$max_tokens" -lt 24000 ]]; then
      max_tokens=24000
    fi
  fi
  printf '%s' "$max_tokens"
}

orchestrated_capacity_retry_limit() {
  if [[ -n "${ONLYMACS_CAPACITY_RETRY_LIMIT:-}" && "${ONLYMACS_CAPACITY_RETRY_LIMIT:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ONLYMACS_CAPACITY_RETRY_LIMIT"
    return 0
  fi
  if [[ "${ONLYMACS_GO_WIDE_JOB_BOARD_WORKER:-0}" == "1" ]]; then
    printf '2'
    return 0
  fi
  if [[ "${ONLYMACS_GO_WIDE_MODE:-0}" == "1" ]]; then
    printf '3'
    return 0
  fi
  case "${ONLYMACS_EXECUTION_MODE:-auto}" in
    overnight)
      printf '720'
      ;;
    extended)
      printf '120'
      ;;
    *)
      printf '30'
      ;;
  esac
}

orchestrated_capacity_retry_interval() {
  if [[ -n "${ONLYMACS_CAPACITY_RETRY_INTERVAL:-}" && "${ONLYMACS_CAPACITY_RETRY_INTERVAL:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ONLYMACS_CAPACITY_RETRY_INTERVAL"
    return 0
  fi
  if [[ "${ONLYMACS_GO_WIDE_JOB_BOARD_WORKER:-0}" == "1" || "${ONLYMACS_GO_WIDE_MODE:-0}" == "1" ]]; then
    printf '3'
    return 0
  fi
  printf '10'
}

orchestrated_bridge_retry_limit() {
  if [[ -n "${ONLYMACS_BRIDGE_RETRY_LIMIT:-}" && "${ONLYMACS_BRIDGE_RETRY_LIMIT:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ONLYMACS_BRIDGE_RETRY_LIMIT"
    return 0
  fi
  printf '3'
}

onlymacs_bridge_wait_limit() {
  if [[ -n "${ONLYMACS_BRIDGE_WAIT_LIMIT:-}" && "${ONLYMACS_BRIDGE_WAIT_LIMIT:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ONLYMACS_BRIDGE_WAIT_LIMIT"
    return 0
  fi
  printf '90'
}

onlymacs_bridge_wait_interval() {
  if [[ -n "${ONLYMACS_BRIDGE_WAIT_INTERVAL:-}" && "${ONLYMACS_BRIDGE_WAIT_INTERVAL:-}" =~ ^[0-9]+$ && "$ONLYMACS_BRIDGE_WAIT_INTERVAL" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_BRIDGE_WAIT_INTERVAL"
    return 0
  fi
  printf '2'
}

onlymacs_bridge_available() {
  if [[ "${ONLYMACS_ASSUME_BRIDGE_AVAILABLE:-0}" == "1" ]]; then
    return 0
  fi
  curl -fsS --max-time 2 "${BASE_URL}/health" >/dev/null 2>&1
}

onlymacs_wait_for_bridge() {
  local wait_limit="${1:-$(onlymacs_bridge_wait_limit)}"
  local wait_interval elapsed
  wait_interval="$(onlymacs_bridge_wait_interval)"
  elapsed=0
  while [[ "$elapsed" -le "$wait_limit" ]]; do
    if onlymacs_bridge_available; then
      return 0
    fi
    sleep "$wait_interval"
    elapsed=$((elapsed + wait_interval))
  done
  return 1
}

orchestrated_chunk_size() {
  if [[ -n "${ONLYMACS_CHUNK_SIZE:-}" && "${ONLYMACS_CHUNK_SIZE:-}" =~ ^[0-9]+$ && "$ONLYMACS_CHUNK_SIZE" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_CHUNK_SIZE"
    return 0
  fi
  printf '20'
}

orchestrated_chunk_threshold() {
  if [[ -n "${ONLYMACS_CHUNK_THRESHOLD:-}" && "${ONLYMACS_CHUNK_THRESHOLD:-}" =~ ^[0-9]+$ && "$ONLYMACS_CHUNK_THRESHOLD" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_CHUNK_THRESHOLD"
    return 0
  fi
  printf '80'
}

orchestrated_json_batch_size() {
  if [[ -n "${ONLYMACS_JSON_BATCH_SIZE:-}" && "${ONLYMACS_JSON_BATCH_SIZE:-}" =~ ^[0-9]+$ && "$ONLYMACS_JSON_BATCH_SIZE" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_JSON_BATCH_SIZE"
    return 0
  fi
  printf '10'
}

orchestrated_json_batch_threshold() {
  if [[ -n "${ONLYMACS_JSON_BATCH_THRESHOLD:-}" && "${ONLYMACS_JSON_BATCH_THRESHOLD:-}" =~ ^[0-9]+$ && "$ONLYMACS_JSON_BATCH_THRESHOLD" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_JSON_BATCH_THRESHOLD"
    return 0
  fi
  printf '20'
}

orchestrated_json_step_is_nested_complex() {
  local validation_prompt="${1:-}"
  local filename="${2:-}"
  local lowered
  lowered="$(printf '%s\n%s' "$filename" "$validation_prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "translationsbylocale" \
    "translations by locale" \
    "segmentation" \
    "highlights" \
    "scenario tags" \
    "city context tags" \
    "learner locales" \
    "sentence item" \
    "sentence items" \
    "set ids" \
    "teachingorder" \
    "teaching order" \
    "contentblocks" \
    "content blocks" \
    "quiz" \
    "questions" \
    "lesson" \
    "lessons" \
    "sections" \
    "subsections" \
    "chapters" \
    "rubric" \
    "checklist" \
    "test cases" \
    "multi-file" \
    "multiple files" \
    "nested"
}

orchestrated_json_step_is_vocab_content() {
  local validation_prompt="${1:-}"
  local filename="${2:-}"
  local lowered
  lowered="$(printf '%s\n%s' "$filename" "$validation_prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "vocab" \
    "vocabulary" \
    "lemma" \
    "vocab item" \
    "vocabulary item"
}

orchestrated_json_step_is_source_card_content() {
  local validation_prompt="${1:-}"
  local filename="${2:-}"
  local lowered
  lowered="$(printf '%s\n%s' "$filename" "$validation_prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "cards-source" \
    "source-card" \
    "source cards" \
    "lean card source schema" \
    "lean source card"
}

orchestrated_json_batch_size_for_step() {
  local validation_prompt="${1:-}"
  local filename="${2:-}"
  local expected_count
  if [[ -n "${ONLYMACS_JSON_BATCH_SIZE:-}" && "${ONLYMACS_JSON_BATCH_SIZE:-}" =~ ^[0-9]+$ && "$ONLYMACS_JSON_BATCH_SIZE" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_JSON_BATCH_SIZE"
    return 0
  fi
  expected_count="$(prompt_exact_count_requirement "$validation_prompt" || true)"
  if orchestrated_json_step_is_source_card_content "$validation_prompt" "$filename"; then
    if [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge 100 ]]; then
      printf '5'
      return 0
    fi
  fi
  if orchestrated_json_step_is_vocab_content "$validation_prompt" "$filename"; then
    if [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge 20 ]]; then
      if string_has_any "$(printf '%s\n%s' "$filename" "$validation_prompt" | tr '[:upper:]' '[:lower:]')" \
        "gold vocab item schema" \
        "exampletranslationbylocale" \
        "audiohint"; then
        printf '10'
        return 0
      fi
      printf '20'
      return 0
    fi
  fi
  if orchestrated_json_step_is_nested_complex "$validation_prompt" "$filename"; then
    if [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge 500 ]]; then
      printf '5'
    elif [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge 100 ]]; then
      printf '5'
    else
      printf '1'
    fi
    return 0
  fi
  if [[ "$expected_count" =~ ^[0-9]+$ ]]; then
    if [[ "$expected_count" -ge 1000 ]]; then
      printf '50'
      return 0
    fi
    if [[ "$expected_count" -ge 500 ]]; then
      printf '40'
      return 0
    fi
    if [[ "$expected_count" -ge 100 ]]; then
      printf '25'
      return 0
    fi
  fi
  orchestrated_json_batch_size
}

alias_is_privacy_locked_route() {
  local requested="${1:-}"
  local lowered
  lowered="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    local|local-first|local_first|trusted-only|trusted_only|trusted|offload-max)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

orchestrated_route_alias_for_step() {
  local default_alias="${1:-}"
  local step_index="${2:-1}"
  local filename="${3:-plan-step.md}"
  local step_text metadata assignment role lowered route_hint default_lower

  if ! orchestrated_is_plan_file_job; then
    printf '%s' "$default_alias"
    return 0
  fi
  if alias_is_privacy_locked_route "$default_alias" || [[ "$default_alias" == *:* ]]; then
    printf '%s' "$default_alias"
    return 0
  fi

  step_text="$(plan_file_step_text "$step_index")"
  metadata="$(plan_file_step_metadata_json "$step_index" "$filename" 2>/dev/null || printf '{}')"
  assignment="$(jq -r '.assignment_policy // ""' <<<"$metadata" 2>/dev/null || true)"
  role="$(jq -r '.role // ""' <<<"$metadata" 2>/dev/null || true)"
  lowered="$(printf '%s\n%s\n%s' "$assignment" "$role" "$step_text" | tr '[:upper:]' '[:lower:]')"
  route_hint="$(printf '%s\n%s\n%s' "$assignment" "$role" "$filename" | tr '[:upper:]' '[:lower:]')"
  default_lower="$(printf '%s' "$default_alias" | tr '[:upper:]' '[:lower:]')"

  if orchestrated_go_wide_enabled "$default_alias"; then
    if string_has_any "$route_hint" \
      "validation" \
      "validate" \
      "duplicate detection" \
      "dialect audit" \
      "voseo audit" \
      "repair" \
      "review" \
      "final review" \
      "final handoff"; then
      printf 'local-first'
      return 0
    fi
    printf 'wide'
    return 0
  fi

  if string_has_any "$lowered" \
    "local-first" \
    "local first" \
    "local only" \
    "this mac" \
    "this 64 gb" \
    "this 64gb" \
    "64 gb mac" \
    "64gb mac" \
    "my computer" \
    "requester" \
    "requesting mac" \
    "local validation" \
    "local review" \
    "local audit" \
    "strongest available local"; then
    printf 'local-first'
    return 0
  fi

  if string_has_any "$lowered" \
    "remote-first" \
    "remote first" \
    "remote mac" \
    "charles" \
    "studiohost" \
    "128 gb" \
    "128gb" \
    "m4 max" \
    "primary generation" \
    "primary artifact" \
    "strongest available model on charles" \
    "strongest available remote"; then
    printf 'remote-first'
    return 0
  fi

  if [[ "$default_lower" == "wide" || "$default_lower" == "go-wide" || "$default_lower" == "go_wide" ]]; then
    if string_has_any "$lowered" \
      "validation" \
      "validate" \
      "duplicate detection" \
      "dialect audit" \
      "voseo audit" \
      "repair" \
      "final review" \
      "final handoff"; then
      printf 'local-first'
      return 0
    fi
  fi

  printf '%s' "$default_alias"
}

orchestrated_step_prefers_content_model() {
  local prompt="${1:-}"
  local filename="${2:-}"
  local lowered
  lowered="$(printf '%s\n%s' "$filename" "$prompt" | tr '[:upper:]' '[:lower:]')"
  if string_has_any "$lowered" \
    "deep reasoning" \
    "long reasoning" \
    "platinum" \
    "quality review" \
    "architecture review" \
    "planning only"; then
    return 1
  fi
  if [[ "$filename" == *.json || "$filename" == *.js || "$filename" == *.md || "$filename" == *.txt ]]; then
    string_has_any "$lowered" \
      "create exactly" \
      "generate" \
      "content generation" \
      "sentence" \
      "sentences" \
      "vocab" \
      "vocabulary" \
      "translation" \
      "translations" \
      "artifact" \
      "complete raw contents"
    return $?
  fi
  return 1
}

onlymacs_fetch_admin_status() {
  local attempts="${ONLYMACS_STATUS_FETCH_ATTEMPTS:-3}"
  local timeout="${ONLYMACS_STATUS_FETCH_TIMEOUT_SECONDS:-8}"
  local attempt body
  [[ "$attempts" =~ ^[0-9]+$ && "$attempts" -gt 0 ]] || attempts=3
  [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -gt 0 ]] || timeout=8
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    body="$(curl -fsS --max-time "$timeout" "${BASE_URL}/admin/v1/status" 2>/dev/null || true)"
    if [[ -n "$body" ]] && jq -e 'type == "object"' <<<"$body" >/dev/null 2>&1; then
      printf '%s' "$body"
      return 0
    fi
    sleep 1
  done
  return 1
}

onlymacs_fetch_admin_models() {
  local attempts="${ONLYMACS_STATUS_FETCH_ATTEMPTS:-3}"
  local timeout="${ONLYMACS_STATUS_FETCH_TIMEOUT_SECONDS:-8}"
  local attempt body
  [[ "$attempts" =~ ^[0-9]+$ && "$attempts" -gt 0 ]] || attempts=3
  [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -gt 0 ]] || timeout=8
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    body="$(curl -fsS --max-time "$timeout" "${BASE_URL}/admin/v1/models" 2>/dev/null || true)"
    if [[ -n "$body" ]] && jq -e 'type == "object"' <<<"$body" >/dev/null 2>&1; then
      printf '%s' "$body"
      return 0
    fi
    sleep 1
  done
  return 1
}

onlymacs_pick_available_model_for_route() {
  local model_alias="${1:-}"
  local route_scope="${2:-swarm}"
  shift 2 || true
  local body local_member candidate count lowered_alias
  [[ $# -gt 0 ]] || return 1
  body="$(onlymacs_fetch_admin_status)" || return 1
  local_member="$(jq -r '.identity.member_id // empty' <<<"$body" 2>/dev/null || true)"
  lowered_alias="$(printf '%s' "$model_alias" | tr '[:upper:]' '[:lower:]')"
  for candidate in "$@"; do
    count="$(jq -r \
      --arg candidate "$candidate" \
      --arg route_scope "$route_scope" \
      --arg alias "$lowered_alias" \
      --arg local_member "$local_member" '
      [
        .members[]?
        | select(
            if $route_scope == "local_only" then
              (.member_id == $local_member)
            elif ($alias == "remote-first" or $alias == "remote-only" or $alias == "remote") and ($local_member | length) > 0 then
              (.member_id != $local_member)
            else
              true
            end
          )
        | .capabilities[]?
        | select((((.status // "") | ascii_downcase) == "available") and ((.slots.free // 0) > 0))
        | .models[]?.id
        | select(. == $candidate)
      ] | length
    ' <<<"$body" 2>/dev/null || printf '0')"
    if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

orchestrated_rank_go_wide_model_candidates_json() {
  local candidates_json="${1:-[]}"
  local ticket_kind="${2:-generate}"
  local plan_path
  if [[ "${ONLYMACS_GO_WIDE_MODEL_SCORE_ROUTING:-1}" == "0" ]]; then
    printf '%s' "$candidates_json"
    return 0
  fi
  plan_path="$(orchestrated_plan_path)"
  if [[ ! -f "$plan_path" ]]; then
    printf '%s' "$candidates_json"
    return 0
  fi
  jq -c \
    --arg ticket_kind "$ticket_kind" \
    --argjson candidates "$candidates_json" '
      ($candidates | to_entries | map({model: .value, index: .key})) as $ordered
      | (
          [
            .steps[]?.batching.batches[]?
            | select((.model // "") as $m | $candidates | index($m))
            | {
                model: (.model // ""),
                success: (if ((.status // "") | IN("completed","reused","recovered","completed_from_partial")) then 1 else 0 end),
                validation_failure: (if ((.status // "") | IN("repair_queued","churn","needs_local_salvage","failed_validation")) then 1 else 0 end),
                transport_failure: (if ((.status // "") | IN("retry_queued","waiting_for_transport","partial")) then 1 else 0 end),
                repair_penalty: (if $ticket_kind == "repair" and ((.status // "") | IN("churn","needs_local_salvage","failed_validation")) then 1 else 0 end)
              }
          ]
          | group_by(.model)
          | map({
              key: .[0].model,
              value: {
                success: (map(.success) | add),
                validation_failure: (map(.validation_failure) | add),
                transport_failure: (map(.transport_failure) | add),
                repair_penalty: (map(.repair_penalty) | add)
              }
            })
          | from_entries
        ) as $stats
      | $ordered
      | map(. + {
          score: (
            (($stats[.model].success // 0) * 20)
            - (($stats[.model].validation_failure // 0) * 50)
            - (($stats[.model].transport_failure // 0) * 10)
            - (($stats[.model].repair_penalty // 0) * 30)
          )
        })
      | sort_by(-.score, .index)
      | map(.model)
    ' "$plan_path" 2>/dev/null || printf '%s' "$candidates_json"
}

orchestrated_go_wide_worker_model_candidates_json() {
  local step_prompt="${1:-}"
  local filename="${2:-}"
  local ticket_kind="${3:-generate}"
  local override_candidates="${ONLYMACS_GO_WIDE_MODEL_CANDIDATES:-${ONLYMACS_GO_WIDE_MODEL_ORDER:-}}"
  local candidates_json
  if [[ -n "$override_candidates" ]]; then
    printf '%s' "$override_candidates" | jq -R -c '
      split(",")
      | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
      | map(select(length > 0))
    '
    return 0
  fi
  if [[ "$filename" == *.json ]] && orchestrated_json_step_is_source_card_content "$step_prompt" "$filename"; then
    if [[ "$ticket_kind" == "repair" ]]; then
      candidates_json="$(jq -c -n '[
        "qwen2.5-coder:32b",
        "qwen2.5-coder:14b",
        "qwen3.6:35b-a3b-q4_K_M",
        "qwen3.6:35b-a3b-q8_0",
        "gemma3:27b",
        "translategemma:27b",
        "gemma4:31b",
        "gemma4:26b",
        "codestral:22b",
        "deepseek-r1:70b",
        "gpt-oss:120b"
      ]')"
      orchestrated_rank_go_wide_model_candidates_json "$candidates_json" "$ticket_kind"
      return 0
    fi
    candidates_json="$(jq -c -n '[
      "gemma3:27b",
      "qwen2.5-coder:32b",
      "codestral:22b",
      "translategemma:27b",
      "qwen2.5-coder:14b",
      "gemma4:31b",
      "gemma4:26b",
      "qwen3.6:35b-a3b-q4_K_M",
      "qwen3.6:35b-a3b-q8_0",
      "deepseek-r1:70b",
      "gpt-oss:120b"
    ]')"
    orchestrated_rank_go_wide_model_candidates_json "$candidates_json" "$ticket_kind"
    return 0
  fi
  candidates_json="$(jq -c -n '[
    "qwen2.5-coder:32b",
    "codestral:22b",
    "gemma3:27b",
    "gemma4:31b",
    "gemma4:26b",
    "translategemma:27b",
    "qwen3.6:35b-a3b-q4_K_M",
    "qwen3.6:35b-a3b-q8_0",
    "deepseek-r1:70b",
    "gpt-oss:120b",
    "qwen2.5-coder:14b"
  ]')"
  orchestrated_rank_go_wide_model_candidates_json "$candidates_json" "$ticket_kind"
}

orchestrated_pick_go_wide_worker_routes() {
  local model_alias="${1:-wide}"
  local route_scope="${2:-swarm}"
  local step_prompt="${3:-}"
  local filename="${4:-}"
  local limit="${5:-1}"
  local ticket_kind="${6:-generate}"
  local body local_member lowered_alias candidates_json skip_local_providers
  local local_provider
  [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || limit=1
  [[ "$route_scope" != "local_only" ]] || return 1
  body="$(onlymacs_fetch_admin_status)" || return 1
  local_member="$(jq -r '.identity.member_id // empty' <<<"$body" 2>/dev/null || true)"
  local_provider="$(jq -r '.identity.provider_id // empty' <<<"$body" 2>/dev/null || true)"
  lowered_alias="$(printf '%s' "$model_alias" | tr '[:upper:]' '[:lower:]')"
  candidates_json="$(orchestrated_go_wide_worker_model_candidates_json "$step_prompt" "$filename" "$ticket_kind")"
  if [[ "${ONLYMACS_GO_WIDE_SKIP_LOCAL_PROVIDERS:-0}" == "1" ]]; then
    skip_local_providers=true
  else
    skip_local_providers=false
  fi
  jq -r \
    --arg alias "$lowered_alias" \
    --arg route_scope "$route_scope" \
    --arg local_member "$local_member" \
    --arg local_provider "$local_provider" \
    --argjson skip_local_providers "$skip_local_providers" \
    --argjson limit "$limit" \
    --argjson candidates "$candidates_json" '
      def provider_id: (.provider_id // .id // "");
      def provider_name: (.owner_member_name // .member_name // .name // provider_id);
      def provider_status: ((.status // "available") | ascii_downcase);
      def free_slots: ((.slots.free // .slots_free // 0) | tonumber? // 0);
      def total_slots: ((.slots.total // .slots_total // free_slots) | tonumber? // free_slots);
      def model_ids: [(.models // [])[]? | (.id // .name // empty) | select(length > 0)];
      def picked_model($ids):
        first($candidates[] as $candidate | select($ids | index($candidate)) | $candidate);
      [
        (.members[]? as $member
          | $member.capabilities[]?
          | . + {
              member_id: ($member.member_id // ""),
              member_name: ($member.member_name // "")
            }
        ),
        (.providers[]?)
      ]
      | map(
          select(provider_id != "")
          | select(provider_status == "available")
          | select(free_slots > 0)
          | select(($skip_local_providers and provider_id == $local_provider) | not)
          | select(
              if $route_scope == "local_only" then
                (.member_id // "") == $local_member
              elif ($alias == "remote-first" or $alias == "remote-only" or $alias == "remote") and ($local_member | length) > 0 then
                (.member_id // "") != $local_member
              else
                true
              end
            )
          | .model_ids = model_ids
          | .picked_model = picked_model(model_ids)
          | select((.picked_model // "") | length > 0)
          | {
              provider_id: provider_id,
              provider_name: provider_name,
              free_slots: free_slots,
              total_slots: ([total_slots, free_slots] | max),
              picked_model: .picked_model,
              is_local_provider: (provider_id == $local_provider)
            }
        )
      | unique_by(.provider_id)
      | reduce .[] as $provider (
          [];
          if length >= $limit then
            .
          else
            . + [
              range(0; ([($provider.free_slots), ($limit - length)] | min))
              | [$provider.provider_id, $provider.picked_model, $provider.provider_name, (if $provider.is_local_provider then "1" else "0" end), ($provider.total_slots | tostring)] | @tsv
            ]
          end
        )
      | .[]
    ' <<<"$body" 2>/dev/null
}

orchestrated_pick_go_wide_model_swarm_routes() {
  local model_alias="${1:-wide}"
  local route_scope="${2:-swarm}"
  local step_prompt="${3:-}"
  local filename="${4:-}"
  local limit="${5:-1}"
  local ticket_kind="${6:-generate}"
  local body candidates_json
  [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || limit=1
  [[ "$route_scope" != "local_only" ]] || return 1
  body="$(onlymacs_fetch_admin_models)" || return 1
  candidates_json="$(orchestrated_go_wide_worker_model_candidates_json "$step_prompt" "$filename" "$ticket_kind")"
  jq -r \
    --argjson limit "$limit" \
    --argjson candidates "$candidates_json" '
      def model_id: (.id // .name // "");
      def free_slots: ((.slots_free // .slots.free // 0) | tonumber? // 0);
      def total_slots: ((.slots_total // .slots.total // free_slots) | tonumber? // free_slots);
      (.models // []) as $models
      | [
          $candidates[] as $candidate
          | ($models[]? | select(model_id == $candidate and free_slots > 0)) as $model
          | {
              model: $candidate,
              free: ($model | free_slots),
              total: ([($model | total_slots), ($model | free_slots)] | max),
              provider_id: ("__swarm_model_" + ($candidate | gsub("[^A-Za-z0-9_.-]"; "_")))
            }
        ]
      | reduce .[] as $picked (
          [];
          if length >= $limit then
            .
          else
            . + [
              range(0; ([$picked.free, ($limit - length)] | min))
              | [$picked.provider_id, $picked.model, "Coordinator swarm", "0", ($picked.total | tostring)] | @tsv
            ]
          end
        )
      | .[]
    ' <<<"$body" 2>/dev/null
}

orchestrated_pick_go_wide_provider_model() {
  local provider_id="${1:-}"
  local step_prompt="${2:-}"
  local filename="${3:-}"
  local ticket_kind="${4:-generate}"
  local body candidates_json picked
  [[ -n "$provider_id" ]] || return 1
  body="$(onlymacs_fetch_admin_status)" || return 1
  candidates_json="$(orchestrated_go_wide_worker_model_candidates_json "$step_prompt" "$filename" "$ticket_kind")"
  picked="$(jq -r \
    --arg provider_id "$provider_id" \
    --argjson candidates "$candidates_json" '
      def provider_id: (.provider_id // .id // "");
      def model_ids: [(.models // [])[]? | (.id // .name // empty) | select(length > 0)];
      [
        (.members[]? as $member
          | $member.capabilities[]?
          | select(provider_id == $provider_id)
        ),
        (.providers[]? | select(provider_id == $provider_id))
      ]
      | ([.[] | model_ids] | add // []) as $ids
      | first($candidates[] as $candidate | select($ids | index($candidate)) | $candidate) // empty
    ' <<<"$body" 2>/dev/null || true)"
  [[ -n "$picked" ]] || return 1
  printf '%s' "$picked"
}

onlymacs_pick_best_model_for_route() {
  local model_alias="${1:-}"
  local route_scope="${2:-swarm}"
  local body local_member lowered_alias picked
  body="$(onlymacs_fetch_admin_status)" || return 1
  local_member="$(jq -r '.identity.member_id // empty' <<<"$body" 2>/dev/null || true)"
  lowered_alias="$(printf '%s' "$model_alias" | tr '[:upper:]' '[:lower:]')"
  picked="$(jq -r \
    --arg route_scope "$route_scope" \
    --arg alias "$lowered_alias" \
    --arg local_member "$local_member" '
    [
      .members[]?
      | select(
          if $route_scope == "local_only" then
            (.member_id == $local_member)
          elif ($alias == "remote-first" or $alias == "remote-only" or $alias == "remote") and ($local_member | length) > 0 then
            (.member_id != $local_member)
          else
            true
          end
        )
      | .capabilities[]?
      | select((.status // "available") != "unavailable")
      | select(((.slots.free // .slots_free // 1) | tonumber? // 1) > 0)
      | (.best_model // (.models[0]?.id // .models[0]?.name // empty))
      | select(length > 0)
    ] | .[0] // empty
  ' <<<"$body" 2>/dev/null || true)"
  [[ -n "$picked" ]] || return 1
  printf '%s' "$picked"
}

orchestrated_step_prefers_review_model() {
  local prompt="${1:-}"
  local filename="${2:-}"
  local lowered
  lowered="$(printf '%s\n%s' "$filename" "$prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "validate" \
    "validation" \
    "review" \
    "audit" \
    "duplicate detection" \
    "duplicate risks" \
    "schema" \
    "quality warnings" \
    "range contract" \
    "consistency" \
    "final handoff" \
    "final report" \
    "repair" \
    "lint" \
    "check"
}

orchestrated_model_for_step() {
  local default_model="${1:-}"
  local step_model_alias="${2:-}"
  local step_route_scope="${3:-swarm}"
  local step_prompt="${4:-}"
  local filename="${5:-}"
  local picked model_override
  if [[ -n "${ONLYMACS_GO_WIDE_WORKER_MODEL:-}" ]] \
    && orchestrated_go_wide_enabled "$step_model_alias" \
    && [[ "${ONLYMACS_ORCHESTRATION_STRICT_MODEL_OVERRIDE:-0}" != "1" ]]; then
    printf '%s' "$ONLYMACS_GO_WIDE_WORKER_MODEL"
    return 0
  fi
  if [[ -n "${ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE:-}" ]]; then
    model_override="$ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE"
    if [[ "${ONLYMACS_ORCHESTRATION_STRICT_MODEL_OVERRIDE:-0}" == "1" ]]; then
      printf '%s' "$model_override"
      return 0
    fi
    if [[ "$step_route_scope" == "local_only" || "$step_route_scope" == "local" || "$step_route_scope" == "local-first" ]] || orchestrated_go_wide_enabled "$step_model_alias"; then
      picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" "$model_override" || true)"
      if [[ -n "$picked" ]]; then
        printf '%s' "$picked"
        return 0
      fi
    else
      printf '%s' "$model_override"
      return 0
    fi
  fi
  if orchestrated_go_wide_enabled "$step_model_alias" && [[ "$filename" == *.json ]] && orchestrated_json_step_is_source_card_content "$step_prompt" "$filename"; then
    picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
      "gemma3:27b" \
      "qwen2.5-coder:32b" \
      "codestral:22b" \
      "translategemma:27b" \
      "qwen2.5-coder:14b" \
      "gemma4:31b" \
      "gemma4:26b" \
      "qwen3.6:35b-a3b-q4_K_M" \
      "qwen3.6:35b-a3b-q8_0" \
      "deepseek-r1:70b" \
      "gpt-oss:120b" || true)"
    if [[ -n "$picked" ]]; then
      printf '%s' "$picked"
      return 0
    fi
    printf 'gemma3:27b'
    return 0
  fi
  if [[ -n "$default_model" ]]; then
    if [[ "${ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT:-0}" == "1" && "$step_route_scope" != "local_only" ]] && onlymacs_model_is_large_or_cold "$default_model"; then
      picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
        "qwen3.6:35b-a3b-q4_K_M" \
        "qwen2.5-coder:32b" \
        "codestral:22b" \
        "gemma4:31b" \
        "gemma4:26b" \
        "translategemma:27b" \
        "gemma3:27b" \
        "$default_model" \
        "deepseek-r1:70b" \
        "gpt-oss:120b" \
        "qwen2.5-coder:14b" || true)"
      if [[ -n "$picked" ]]; then
        printf '%s' "$picked"
        return 0
      fi
    fi
    printf '%s' "$default_model"
    return 0
  fi
  if ! orchestrated_step_prefers_content_model "$step_prompt" "$filename" && ! orchestrated_step_prefers_review_model "$step_prompt" "$filename"; then
    picked="$(onlymacs_pick_best_model_for_route "$step_model_alias" "$step_route_scope" || true)"
    if [[ -n "$picked" ]]; then
      printf '%s' "$picked"
      return 0
    fi
    printf '%s' "$default_model"
    return 0
  fi
  case "$(printf '%s' "$step_route_scope" | tr '[:upper:]' '[:lower:]')" in
    local_only)
      if orchestrated_step_prefers_review_model "$step_prompt" "$filename"; then
        picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
          "qwen2.5-coder:32b" \
          "qwen2.5-coder:14b" \
          "gemma4:31b" \
          "gemma4:26b" \
          "translategemma:27b" \
          "gemma3:27b" \
          "qwen3.6:35b-a3b-q4_K_M" || true)"
      else
        picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
          "qwen3.6:35b-a3b-q4_K_M" \
          "qwen2.5-coder:32b" \
          "translategemma:27b" \
          "gemma4:31b" \
          "gemma4:26b" \
          "gemma3:27b" \
          "qwen2.5-coder:14b" || true)"
      fi
      ;;
    *)
      if orchestrated_go_wide_enabled "$step_model_alias" && [[ "$filename" == *.json ]]; then
        if orchestrated_json_step_is_source_card_content "$step_prompt" "$filename"; then
          picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
            "qwen2.5-coder:32b" \
            "codestral:22b" \
            "gemma4:31b" \
            "gemma4:26b" \
            "translategemma:27b" \
            "gemma3:27b" \
            "qwen3.6:35b-a3b-q4_K_M" \
            "qwen3.6:35b-a3b-q8_0" \
            "deepseek-r1:70b" \
            "gpt-oss:120b" \
            "qwen2.5-coder:14b" || true)"
        else
          picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
            "qwen2.5-coder:32b" \
            "qwen3.6:35b-a3b-q4_K_M" \
            "codestral:22b" \
            "gemma4:31b" \
            "gemma4:26b" \
            "translategemma:27b" \
            "gemma3:27b" \
            "qwen3.6:35b-a3b-q8_0" \
            "deepseek-r1:70b" \
            "gpt-oss:120b" \
            "qwen2.5-coder:14b" || true)"
        fi
      elif [[ "${ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT:-0}" == "1" ]]; then
        picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
          "qwen3.6:35b-a3b-q4_K_M" \
          "qwen2.5-coder:32b" \
          "codestral:22b" \
          "gemma4:31b" \
          "gemma4:26b" \
          "translategemma:27b" \
          "gemma3:27b" \
          "qwen3.6:35b-a3b-q8_0" \
          "deepseek-r1:70b" \
          "gpt-oss:120b" \
          "qwen2.5-coder:14b" || true)"
      else
        picked="$(onlymacs_pick_available_model_for_route "$step_model_alias" "$step_route_scope" \
          "qwen3.6:35b-a3b-q8_0" \
          "deepseek-r1:70b" \
          "gpt-oss:120b" \
          "qwen3.6:35b-a3b-q4_K_M" \
          "qwen2.5-coder:32b" \
          "codestral:22b" \
          "gemma4:31b" \
          "gemma4:26b" \
          "translategemma:27b" \
          "gemma3:27b" \
          "qwen2.5-coder:14b" || true)"
      fi
      ;;
  esac
  if [[ -z "$picked" ]]; then
    picked="$(onlymacs_pick_best_model_for_route "$step_model_alias" "$step_route_scope" || true)"
  fi
  printf '%s' "$picked"
}

orchestrated_is_content_pack_job() {
  prompt_requests_content_pack_mode "${1:-}"
}

orchestrated_is_plan_file_job() {
  [[ -n "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-}" || -n "${ONLYMACS_PLAN_FILE_PATH:-}" ]]
}

orchestrated_plan_file_step_count() {
  if [[ "${ONLYMACS_PLAN_FILE_STEP_COUNT:-}" =~ ^[0-9]+$ && "$ONLYMACS_PLAN_FILE_STEP_COUNT" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_PLAN_FILE_STEP_COUNT"
    return 0
  fi
  printf '1'
}

orchestrated_plan_file_filename() {
  local step_index="${1:-1}"
  local requested
  requested="$(printf '%s' "${ONLYMACS_PLAN_FILE_CONTENT:-}" | plan_file_step_filename_from_content "$step_index" || true)"
  if [[ -n "$requested" ]]; then
    sanitize_return_filename "$requested"
    return 0
  fi
  printf 'plan-step-%02d.md' "$step_index"
}

orchestrated_content_batch_size() {
  if [[ -n "${ONLYMACS_CONTENT_BATCH_SIZE:-}" && "${ONLYMACS_CONTENT_BATCH_SIZE:-}" =~ ^[0-9]+$ && "$ONLYMACS_CONTENT_BATCH_SIZE" -gt 0 ]]; then
    printf '%s' "$ONLYMACS_CONTENT_BATCH_SIZE"
    return 0
  fi
  printf '2'
}

orchestrated_content_group_bounds() {
  local prompt="${1:-}"
  printf '%s\n' "$prompt" | perl -0777 -ne '
    my $s = lc($_);
    my ($start, $end) = (1, 50);
    if ($s =~ /\bgroups?\s+0*(\d{1,3})\s*(?:-|to|through)\s*0*(\d{1,3})\b/) {
      ($start, $end) = ($1, $2);
    } elsif ($s =~ /\b(?:sets?|lessons?|vocab(?:ulary)?|sentences?)\s+0*(\d{1,3})\s*(?:-|to|through)\s*0*(\d{1,3})\b/) {
      ($start, $end) = ($1, $2);
    } elsif ($s =~ /\b0*(\d{1,3})\s*[-–]\s*0*(\d{1,3})\b/ && $s =~ /\b(group|vocab|sentence|lesson|step 2|step2)\b/) {
      ($start, $end) = ($1, $2);
    } elsif ($s =~ /\bfirst\s+(\d{1,3})\s+(?:groups?|sets?|lessons?)\b/) {
      ($start, $end) = (1, $1);
    } elsif ($s =~ /\b(\d{1,3})\s+(?:groups?|sets?|lessons?)\b/ && $s =~ /\b(all|full|complete|entire)\b/) {
      ($start, $end) = (1, $1);
    }
    $start = 1 if $start < 1;
    $end = 1 if $end < 1;
    $start = 200 if $start > 200;
    $end = 200 if $end > 200;
    ($start, $end) = ($end, $start) if $end < $start;
    print "$start $end";
  '
}

orchestrated_content_group_start() {
  local bounds
  bounds="$(orchestrated_content_group_bounds "${1:-}")"
  printf '%s' "${bounds%% *}"
}

orchestrated_content_group_end() {
  local bounds
  bounds="$(orchestrated_content_group_bounds "${1:-}")"
  printf '%s' "${bounds##* }"
}

orchestrated_content_batch_count() {
  local prompt="${1:-}" start end count batch_size
  start="$(orchestrated_content_group_start "$prompt")"
  end="$(orchestrated_content_group_end "$prompt")"
  batch_size="$(orchestrated_content_batch_size)"
  count=$((end - start + 1))
  printf '%s' $(((count + batch_size - 1) / batch_size))
}

orchestrated_content_pack_step_count() {
  local batch_count
  batch_count="$(orchestrated_content_batch_count "${1:-}")"
  printf '%s' $((1 + (batch_count * 3)))
}

orchestrated_content_step_module() {
  local step_index="${1:-1}" slot module_index
  slot=$((step_index - 2))
  module_index=$((slot % 3))
  case "$module_index" in
    0) printf 'vocab' ;;
    1) printf 'sentences' ;;
    *) printf 'lessons' ;;
  esac
}

orchestrated_content_step_batch_index() {
  local step_index="${1:-1}" slot
  slot=$((step_index - 2))
  printf '%s' $(((slot / 3) + 1))
}

orchestrated_content_step_group_range() {
  local prompt="${1:-}" step_index="${2:-1}" start end batch_size batch_index batch_start batch_end
  start="$(orchestrated_content_group_start "$prompt")"
  end="$(orchestrated_content_group_end "$prompt")"
  batch_size="$(orchestrated_content_batch_size)"
  batch_index="$(orchestrated_content_step_batch_index "$step_index")"
  batch_start=$((start + ((batch_index - 1) * batch_size)))
  batch_end=$((batch_start + batch_size - 1))
  if [[ "$batch_end" -gt "$end" ]]; then
    batch_end="$end"
  fi
  printf '%s %s' "$batch_start" "$batch_end"
}

orchestrated_content_pack_filename() {
  local prompt="${1:-}" step_index="${2:-1}" step_count="${3:-1}" module range start end
  if [[ "$step_index" -eq 1 ]]; then
    printf 'content-pack-manifest.json'
    return 0
  fi
  module="$(orchestrated_content_step_module "$step_index")"
  range="$(orchestrated_content_step_group_range "$prompt" "$step_index")"
  start="${range%% *}"
  end="${range##* }"
  printf '%s-groups-%02d-%02d.json' "$module" "$start" "$end"
}

content_pack_expected_json_count() {
  local artifact_path="${1:-}" base start end group_count
  base="$(basename "$artifact_path")"
  case "$base" in
    vocab-groups-[0-9][0-9]-[0-9][0-9].json|sentences-groups-[0-9][0-9]-[0-9][0-9].json)
      start="${base#*-groups-}"
      start="${start%%-*}"
      end="${base##*-}"
      end="${end%.json}"
      group_count=$((10#$end - 10#$start + 1))
      printf '%s' $((group_count * 20))
      return 0
      ;;
    lessons-groups-[0-9][0-9]-[0-9][0-9].json)
      start="${base#*-groups-}"
      start="${start%%-*}"
      end="${base##*-}"
      end="${end%.json}"
      group_count=$((10#$end - 10#$start + 1))
      printf '%s' "$group_count"
      return 0
      ;;
  esac
  return 1
}

orchestrated_is_large_exact_js_artifact() {
  local prompt="${1:-}"
  local expected_count threshold filename lowered
  expected_count="$(prompt_exact_count_requirement "$prompt" || true)"
  [[ "$expected_count" =~ ^[0-9]+$ ]] || return 1
  threshold="$(orchestrated_chunk_threshold)"
  [[ "$expected_count" -ge "$threshold" ]] || return 1
  filename="$(artifact_mode_requested_filename "$prompt" || true)"
  [[ "$filename" == *.js || "$filename" == *.mjs || "$filename" == *.cjs ]] || return 1
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" "vocabulary" "words" "entries" "flashcards" "quiz"
}

orchestrated_chunk_count() {
  local prompt="${1:-}"
  local expected_count chunk_size
  expected_count="$(prompt_exact_count_requirement "$prompt" || true)"
  chunk_size="$(orchestrated_chunk_size)"
  if [[ ! "$expected_count" =~ ^[0-9]+$ || "$expected_count" -le 0 ]]; then
    printf '0'
    return 0
  fi
  printf '%s' $(((expected_count + chunk_size - 1) / chunk_size))
}

orchestrated_chunk_start() {
  local step_index="${1:-1}"
  local chunk_size
  chunk_size="$(orchestrated_chunk_size)"
  printf '%s' $((((step_index - 1) * chunk_size) + 1))
}

orchestrated_chunk_end() {
  local prompt="${1:-}"
  local step_index="${2:-1}"
  local expected_count chunk_size end
  expected_count="$(prompt_exact_count_requirement "$prompt" || true)"
  chunk_size="$(orchestrated_chunk_size)"
  end=$((step_index * chunk_size))
  if [[ "$expected_count" =~ ^[0-9]+$ && "$end" -gt "$expected_count" ]]; then
    end="$expected_count"
  fi
  printf '%s' "$end"
}

orchestrated_chunk_entry_count() {
  local prompt="${1:-}"
  local step_index="${2:-1}"
  local start end
  start="$(orchestrated_chunk_start "$step_index")"
  end="$(orchestrated_chunk_end "$prompt" "$step_index")"
  printf '%s' $((end - start + 1))
}

orchestrated_step_is_chunk_data() {
  local prompt="${1:-}"
  local step_index="${2:-1}"
  local chunk_count
  orchestrated_is_large_exact_js_artifact "$prompt" || return 1
  chunk_count="$(orchestrated_chunk_count "$prompt")"
  [[ "$step_index" -le "$chunk_count" ]]
}

orchestrated_step_is_local_assembly() {
  local prompt="${1:-}"
  local step_index="${2:-1}"
  local chunk_count
  orchestrated_is_large_exact_js_artifact "$prompt" || return 1
  chunk_count="$(orchestrated_chunk_count "$prompt")"
  [[ "$step_index" -eq $((chunk_count + 1)) ]]
}

orchestrated_previous_chunk_terms() {
  local step_index="${1:-1}"
  local previous_index previous_step_id artifact
  [[ "$step_index" =~ ^[0-9]+$ && "$step_index" -gt 1 ]] || return 0
  for ((previous_index = 1; previous_index < step_index; previous_index++)); do
    previous_step_id="$(orchestrated_step_id "$previous_index")"
    for artifact in "${ONLYMACS_CURRENT_RETURN_DIR}/steps/${previous_step_id}/files/"*.json; do
      [[ -f "$artifact" ]] || continue
      artifact_vocabulary_terms "$artifact" || true
    done
  done
}

orchestrated_previous_chunk_terms_for_prompt() {
  local step_index="${1:-1}"
  orchestrated_previous_chunk_terms "$step_index" | LC_ALL=C sort -u | join_terms_csv
}

orchestrated_validate_chunk_uniqueness() {
  local artifact_path="${1:-}"
  local step_index="${2:-1}"
  local current_terms previous_terms current_sorted previous_sorted duplicate_current duplicate_previous
  local failures=()
  ONLYMACS_CHUNK_UNIQUENESS_STATUS="passed"
  ONLYMACS_CHUNK_UNIQUENESS_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0

  current_terms="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chunk-current-XXXXXX")"
  previous_terms="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chunk-previous-XXXXXX")"
  current_sorted="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chunk-current-sorted-XXXXXX")"
  previous_sorted="$(mktemp "${TMPDIR:-/tmp}/onlymacs-chunk-previous-sorted-XXXXXX")"

  if ! artifact_vocabulary_terms "$artifact_path" >"$current_terms"; then
    rm -f "$current_terms" "$previous_terms" "$current_sorted" "$previous_sorted"
    return 0
  fi

  duplicate_current="$(LC_ALL=C sort "$current_terms" | uniq -d | head -20 | join_terms_csv)"
  if [[ -n "$duplicate_current" ]]; then
    failures+=("duplicate Vietnamese terms within this chunk: ${duplicate_current}")
  fi

  if [[ "$step_index" =~ ^[0-9]+$ && "$step_index" -gt 1 ]]; then
    orchestrated_previous_chunk_terms "$step_index" >"$previous_terms" || true
    if [[ -s "$previous_terms" ]]; then
      LC_ALL=C sort -u "$current_terms" >"$current_sorted"
      LC_ALL=C sort -u "$previous_terms" >"$previous_sorted"
      duplicate_previous="$(comm -12 "$previous_sorted" "$current_sorted" | head -20 | join_terms_csv)"
      if [[ -n "$duplicate_previous" ]]; then
        failures+=("duplicate Vietnamese terms from earlier chunks: ${duplicate_previous}")
      fi
    fi
  fi

  rm -f "$current_terms" "$previous_terms" "$current_sorted" "$previous_sorted"

  if [[ "${#failures[@]}" -gt 0 ]]; then
    ONLYMACS_CHUNK_UNIQUENESS_STATUS="failed"
    ONLYMACS_CHUNK_UNIQUENESS_MESSAGE="$(printf '%s; ' "${failures[@]}" | sed -E 's/; $//' | cut -c 1-500)"
  fi
}

orchestrated_stream_payload_with_capacity_wait() {
  local payload="${1:-}"
  local content_path="${2:-}"
  local headers_path="${3:-}"
  local step_id="${4:-step-01}"
  local attempt="${5:-0}"
  local artifact_path="${6:-}"
  local raw_path="${7:-}"
  local retry_limit retry_interval retry_index http_status message bridge_retry_limit bridge_retry_index bridge_wait_limit bridge_wait_interval

  retry_limit="$(orchestrated_capacity_retry_limit)"
  retry_interval="$(orchestrated_capacity_retry_interval)"
  bridge_retry_limit="$(orchestrated_bridge_retry_limit)"
  bridge_wait_limit="$(onlymacs_bridge_wait_limit)"
  bridge_wait_interval="$(onlymacs_bridge_wait_interval)"
  retry_index=0
  bridge_retry_index=0
  ONLYMACS_LAST_CHAT_HTTP_STATUS=""
  ONLYMACS_LAST_CHAT_FAILURE_MESSAGE=""
  ONLYMACS_LAST_CHAT_FAILURE_KIND=""
  ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT=0
  ONLYMACS_LAST_CHAT_SESSION_ID=""
  ONLYMACS_LAST_CHAT_PROVIDER_ID=""
  ONLYMACS_LAST_CHAT_PROVIDER_NAME=""
  ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME=""
  ONLYMACS_LAST_CHAT_RESOLVED_MODEL=""
  ONLYMACS_STREAM_CAPTURE_FAILURE_KIND=""
  ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE=""

  while true; do
    if stream_chat_payload_capture "$payload" "$content_path" "$headers_path"; then
      ONLYMACS_LAST_CHAT_HTTP_STATUS="$(onlymacs_chat_http_status "$headers_path")"
      onlymacs_capture_last_chat_headers "$headers_path"
      return 0
    fi

    http_status="$(onlymacs_chat_http_status "$headers_path")"
    ONLYMACS_LAST_CHAT_HTTP_STATUS="$http_status"
    onlymacs_capture_last_chat_headers "$headers_path"
    if [[ -n "${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}" ]]; then
      ONLYMACS_LAST_CHAT_FAILURE_KIND="$ONLYMACS_STREAM_CAPTURE_FAILURE_KIND"
    fi
    if [[ -n "${ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE:-}" ]]; then
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="$ONLYMACS_STREAM_CAPTURE_FAILURE_MESSAGE"
    fi
    if [[ "$http_status" == "409" && "${ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY:-0}" == "1" ]]; then
      ONLYMACS_LAST_CHAT_FAILURE_KIND="validation_reroute_capacity"
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="${ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE:-validation reroute could not find another eligible remote Mac}"
      return 1
    fi
    if [[ "$http_status" == "409" ]]; then
      if locked_provider_message="$(onlymacs_locked_provider_unavailable_message)"; then
        ONLYMACS_LAST_CHAT_FAILURE_KIND="locked_provider_unavailable"
        ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="$locked_provider_message"
        return 1
      fi
    fi
    if [[ "$http_status" == "409" && "$retry_index" -lt "$retry_limit" ]]; then
      retry_index=$((retry_index + 1))
      message="remote capacity unavailable; waiting for a free remote slot (retry ${retry_index}/${retry_limit})"
      orchestrated_update_plan_step "$step_id" "waiting_for_capacity" "$attempt" "$artifact_path" "$raw_path" "pending" "$message" "" "" "" "running"
      if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf '\nOnlyMacs is waiting for a remote slot for %s (%s/%s). Next check in %ss.\n' "$step_id" "$retry_index" "$retry_limit" "$retry_interval" >&2
      fi
      sleep "$retry_interval"
      continue
    fi

    if orchestrated_stream_failure_should_wait_for_bridge "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}}" "$http_status" && [[ "$bridge_retry_index" -lt "$bridge_retry_limit" ]]; then
      bridge_retry_index=$((bridge_retry_index + 1))
      message="local bridge unavailable; waiting for the OnlyMacs bridge to recover (retry ${bridge_retry_index}/${bridge_retry_limit})"
      orchestrated_update_plan_step "$step_id" "waiting_for_bridge" "$attempt" "$artifact_path" "$raw_path" "pending" "$message" "" "" "" "running"
      if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf '\nOnlyMacs cannot reach the local bridge for %s. Waiting up to %ss for it to recover (retry %s/%s, health check every %ss).\n' "$step_id" "$bridge_wait_limit" "$bridge_retry_index" "$bridge_retry_limit" "$bridge_wait_interval" >&2
      fi
      if onlymacs_wait_for_bridge "$bridge_wait_limit"; then
        continue
      fi
    fi

    if [[ "$http_status" == "409" ]]; then
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="remote capacity was still unavailable after ${retry_limit} retries"
    elif [[ -n "${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-}" ]]; then
      :
    elif [[ -z "$http_status" && "$bridge_retry_index" -ge "$bridge_retry_limit" ]]; then
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="local bridge was unavailable after ${bridge_retry_limit} recovery attempt(s)"
    elif [[ -n "$http_status" ]]; then
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="remote stream failed with HTTP ${http_status}"
    else
      ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="remote stream failed before a response was received"
    fi
    if [[ -s "$content_path" ]]; then
      ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT=1
    fi
    return 1
  done
}

orchestrated_stream_failure_should_wait_for_bridge() {
  local kind="${1:-${ONLYMACS_LAST_CHAT_FAILURE_KIND:-${ONLYMACS_STREAM_CAPTURE_FAILURE_KIND:-}}}"
  local http_status="${2:-${ONLYMACS_LAST_CHAT_HTTP_STATUS:-}}"

  [[ -z "$http_status" ]] || return 1

  case "$kind" in
    ""|transport_error)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

onlymacs_locked_provider_unavailable_message() {
  local provider_id body runtime_body swarm_id coordinator_url providers_url
  if [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" != "1" ]]; then
    return 1
  fi
  provider_id="${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-${ONLYMACS_CHAT_ROUTE_PROVIDER_ID:-}}"
  [[ -n "$provider_id" ]] || return 1
  body="$(curl -fsS --max-time 3 "${BASE_URL}/admin/v1/status" 2>/dev/null || true)"
  if [[ -n "$body" ]]; then
    if jq -e --arg provider_id "$provider_id" '
      any(.providers[]?; .id == $provider_id)
      or any(.members[]?.capabilities[]?; .provider_id == $provider_id)
    ' <<<"$body" >/dev/null 2>&1; then
      return 1
    fi
    printf 'pinned provider %s is not visible in the current swarm; preserving the checkpoint until that Mac rejoins' "$provider_id"
    return 0
  fi

  runtime_body="$(curl -fsS --max-time 2 "${BASE_URL}/admin/v1/runtime" 2>/dev/null || true)"
  swarm_id="$(jq -r '.active_swarm_id // "swarm-public"' <<<"$runtime_body" 2>/dev/null || printf 'swarm-public')"
  [[ -n "$swarm_id" && "$swarm_id" != "null" ]] || swarm_id="swarm-public"
  coordinator_url="${ONLYMACS_COORDINATOR_URL:-https://onlymacs.ai}"
  providers_url="${coordinator_url%/}/admin/v1/providers?swarm_id=${swarm_id}"
  body="$(curl -fsS --max-time 5 "$providers_url" 2>/dev/null || true)"
  [[ -n "$body" ]] || return 1
  if jq -e --arg provider_id "$provider_id" 'any(.providers[]?; .id == $provider_id)' <<<"$body" >/dev/null 2>&1; then
    return 1
  fi
  printf 'pinned provider %s is not visible in the current swarm; preserving the checkpoint until that Mac rejoins' "$provider_id"
  return 0
}

orchestrated_failure_status_for_last_chat() {
  if [[ "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}" == "validation_reroute_capacity" ]]; then
    printf 'churn'
  elif [[ "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}" == "locked_provider_unavailable" ]]; then
    printf 'queued'
  elif [[ "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}" == "detached_activity_running" ]]; then
    printf 'queued'
  elif [[ "${ONLYMACS_LAST_CHAT_HTTP_STATUS:-}" == "409" ]]; then
    printf 'queued'
  elif [[ "${ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT:-0}" == "1" ]]; then
    printf 'partial'
  elif orchestrated_last_chat_is_transient_transport; then
    printf 'queued'
  else
    printf 'failed'
  fi
}

orchestrated_step_count() {
  local prompt="${1:-}"
  local lowered start end count
  if orchestrated_is_plan_file_job; then
    orchestrated_plan_file_step_count
    return 0
  fi
  if orchestrated_is_content_pack_job "$prompt"; then
    orchestrated_content_pack_step_count "$prompt"
    return 0
  fi
  if orchestrated_is_large_exact_js_artifact "$prompt"; then
    printf '%s' "$(($(orchestrated_chunk_count "$prompt") + 1))"
    return 0
  fi
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lowered" =~ step[[:space:]]*([0-9]+)[[:space:]]*(to|through|-)[[:space:]]*(step[[:space:]]*)?([0-9]+) ]]; then
    start="${BASH_REMATCH[1]}"
    end="${BASH_REMATCH[4]}"
    if [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$end" -ge "$start" ]]; then
      count=$((end - start + 1))
      if [[ "$count" -gt 0 && "$count" -le 12 ]]; then
        printf '%s' "$count"
        return 0
      fi
    fi
  fi
  printf '1'
}

orchestrated_expected_filename() {
  local prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local requested base
  if orchestrated_is_plan_file_job; then
    orchestrated_plan_file_filename "$step_index"
    return 0
  fi
  if orchestrated_is_content_pack_job "$prompt"; then
    orchestrated_content_pack_filename "$prompt" "$step_index" "$step_count"
    return 0
  fi
  requested="$(artifact_mode_requested_filename "$prompt" || true)"
  if orchestrated_is_large_exact_js_artifact "$prompt"; then
    if orchestrated_step_is_chunk_data "$prompt" "$step_index"; then
      base="${requested%.*}"
      printf '%s.entries-%02d.json' "$base" "$step_index"
      return 0
    fi
    printf '%s' "$requested"
    return 0
  fi
  if [[ "$step_count" -eq 1 && -n "$requested" ]]; then
    printf '%s' "$requested"
    return 0
  fi
  if [[ "$step_count" -eq 1 ]] && prompt_requests_artifact_mode "$prompt"; then
    printf 'answer.js'
    return 0
  fi
  printf 'step-%02d.md' "$step_index"
}

orchestrated_step_id() {
  printf 'step-%02d' "${1:-1}"
}

orchestrated_plan_path() {
  printf '%s/plan.json' "${ONLYMACS_CURRENT_RETURN_DIR:-}"
}

orchestrated_plan_lock_path() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  printf '%s.lock' "$plan_path"
}

orchestrated_acquire_plan_lock() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local lock_path wait_count stale_after lock_pid
  [[ -n "$plan_path" ]] || return 0
  lock_path="$(orchestrated_plan_lock_path "$plan_path")"
  stale_after="${ONLYMACS_PLAN_LOCK_STALE_SECONDS:-120}"
  [[ "$stale_after" =~ ^[0-9]+$ && "$stale_after" -gt 0 ]] || stale_after=120
  wait_count=0
  while ! mkdir "$lock_path" 2>/dev/null; do
    if [[ -f "$lock_path/pid" ]]; then
      lock_pid="$(cat "$lock_path/pid" 2>/dev/null || true)"
      if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -rf "$lock_path"
        continue
      fi
    fi
    wait_count=$((wait_count + 1))
    if [[ "$wait_count" -ge "$stale_after" ]]; then
      rm -rf "$lock_path"
      wait_count=0
      continue
    fi
    sleep 1
  done
  printf '%s\n' "$$" >"$lock_path/pid" 2>/dev/null || true
}

orchestrated_release_plan_lock() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local lock_path
  [[ -n "$plan_path" ]] || return 0
  lock_path="$(orchestrated_plan_lock_path "$plan_path")"
  rm -rf "$lock_path" 2>/dev/null || true
}

orchestrated_prompt_path() {
  printf '%s/prompt.txt' "${ONLYMACS_CURRENT_RETURN_DIR:-}"
}

orchestrated_progress_phase_for_status() {
  case "${1:-running}" in
    running)
      printf 'first_token_wait'
      ;;
    resuming)
      printf 'resuming'
      ;;
    retrying)
      printf 'retrying'
      ;;
    repairing)
      printf 'repairing'
      ;;
    repair_queued)
      printf 'waiting_for_capacity'
      ;;
    rerouting)
      printf 'rerouting'
      ;;
    assembling)
      printf 'assembling'
      ;;
    completed)
      printf 'completed'
      ;;
    queued|blocked)
      printf 'waiting_for_capacity'
      ;;
    partial)
      printf 'partial'
      ;;
    failed_validation|churn|failed)
      printf 'failed'
      ;;
    *)
      printf '%s' "${1:-running}"
      ;;
  esac
}

orchestrated_progress_detail_for_status() {
  case "${1:-running}" in
    running)
      printf 'Remote model is loading or waiting for the first token.'
      ;;
    resuming)
      printf 'OnlyMacs is reusing a validated checkpoint from this run.'
      ;;
    retrying)
      printf 'OnlyMacs is retrying a dropped stream before surfacing a failure.'
      ;;
    repairing)
      printf 'OnlyMacs is asking for a full replacement artifact using validator errors.'
      ;;
    repair_queued)
      printf 'OnlyMacs queued this batch for repair after fresh generation tickets.'
      ;;
    rerouting)
      printf 'OnlyMacs is trying another eligible Mac after a provider-specific issue.'
      ;;
    assembling)
      printf 'OnlyMacs is assembling validated remote pieces locally.'
      ;;
    completed)
      printf 'Step completed and validation passed.'
      ;;
    queued)
      printf 'OnlyMacs saved the run after a capacity or transport interruption; resume from the checkpoint when the route is healthy.'
      ;;
    blocked)
      printf 'OnlyMacs saved the checkpoint but cannot continue until the route or provider is healthy.'
      ;;
    partial)
      printf 'OnlyMacs preserved partial output; resume when the provider or route is healthy.'
      ;;
    failed_validation|churn|failed)
      printf 'OnlyMacs stopped because validation or bounded repair did not converge.'
      ;;
    *)
      printf '%s' "${2:-}"
      ;;
  esac
}

orchestrated_emit_plan_progress() {
  local plan_path="${1:-}"
  local status="${2:-running}"
  [[ "$ONLYMACS_JSON_MODE" -ne 1 ]] || return 0
  [[ -f "$plan_path" ]] || return 0

  jq -r --arg status "$status" '
    .progress as $p
    | "ONLYMACS_PROGRESS phase=\($p.phase // "running") step=\($p.step_id // "step-01") step_index=\($p.step_index // 1) steps_total=\($p.steps_total // (.steps | length)) percent=\($p.percent_complete // 0) status=\($status)"
  ' "$plan_path" >&2 2>/dev/null || true
}

orchestrated_sync_running_status() {
  local status_value="${1:-running}"
  local plan_path status_path latest_path prompt_path now artifact_path artifacts_json step_count completed_count
  local progress_json resume_step resume_step_index provider_id provider_name model

  [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" ]] || return 0
  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" ]] || return 0

  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  status_path="${ONLYMACS_CURRENT_RETURN_DIR}/status.json"
  latest_path="$(dirname "$ONLYMACS_CURRENT_RETURN_DIR")/latest.json"
  prompt_path="$(orchestrated_prompt_path)"
  artifacts_json="${ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON:-[]}"
  artifact_path="$(jq -r '.[0] // empty' <<<"$artifacts_json")"
  step_count="$(jq -r '.steps | length' "$plan_path" 2>/dev/null || printf '0')"
  completed_count="$(jq -r '[.steps[]? | select(.status == "completed")] | length' "$plan_path" 2>/dev/null || printf '0')"
  progress_json="$(jq -c '.progress // {}' "$plan_path" 2>/dev/null || printf '{}')"
  resume_step="$(jq -r '.resume_step // empty' "$plan_path" 2>/dev/null || true)"
  resume_step_index="$(jq -r '.resume_step_index // 0' "$plan_path" 2>/dev/null || printf '0')"
  provider_id="$(jq -r '[.steps[]? | select(.provider_id != null) | .provider_id] | last // empty' "$plan_path" 2>/dev/null || true)"
  provider_name="$(jq -r '[.steps[]? | select(.provider_name != null) | .provider_name] | last // empty' "$plan_path" 2>/dev/null || true)"
  model="$(jq -r '[.steps[]? | select(.model != null) | .model] | last // empty' "$plan_path" 2>/dev/null || true)"

  jq -n \
    --arg status "$status_value" \
    --arg run_id "${ONLYMACS_CURRENT_RETURN_RUN_ID:-}" \
    --arg started_at "${ONLYMACS_CURRENT_RETURN_STARTED_AT:-$now}" \
    --arg updated_at "$now" \
    --arg model_alias "${ONLYMACS_CURRENT_RETURN_MODEL_ALIAS:-}" \
    --arg route_scope "${ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE:-swarm}" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg inbox "${ONLYMACS_CURRENT_RETURN_DIR:-}" \
    --arg files_dir "${ONLYMACS_CURRENT_RETURN_DIR:-}/files" \
    --arg plan_path "$plan_path" \
    --arg prompt_path "$prompt_path" \
    --arg artifact_path "$artifact_path" \
    --arg resume_step "$resume_step" \
    --argjson artifacts "$artifacts_json" \
    --argjson steps_total "${step_count:-0}" \
    --argjson steps_completed "${completed_count:-0}" \
    --argjson resume_step_index "${resume_step_index:-0}" \
    --argjson progress "$progress_json" \
    '{
      status: $status,
      run_id: $run_id,
      started_at: $started_at,
      updated_at: $updated_at,
      model_alias: ($model_alias | if length > 0 then . else null end),
      route_scope: $route_scope,
      provider_id: ($provider_id | if length > 0 then . else null end),
      provider_name: ($provider_name | if length > 0 then . else null end),
      model: ($model | if length > 0 then . else null end),
      inbox: $inbox,
      files_dir: $files_dir,
      plan_path: $plan_path,
      prompt_path: $prompt_path,
      artifact_path: ($artifact_path | if length > 0 then . else null end),
      artifacts: $artifacts,
      progress: $progress,
      steps: {
        completed: $steps_completed,
        total: $steps_total,
        resume_step: ($resume_step | if length > 0 then . else null end),
        resume_step_index: (if ($resume_step_index | type) == "number" and $resume_step_index > 0 then $resume_step_index else null end)
      }
    }' >"$status_path"

  jq -n \
    --arg run_id "${ONLYMACS_CURRENT_RETURN_RUN_ID:-}" \
    --arg status "$status_value" \
    --arg updated_at "$now" \
    --arg inbox "${ONLYMACS_CURRENT_RETURN_DIR:-}" \
    --arg artifact_path "$artifact_path" \
    --arg status_path "$status_path" \
    --arg plan_path "$plan_path" \
    --arg prompt_path "$prompt_path" \
    '{run_id:$run_id,status:$status,updated_at:$updated_at,inbox:$inbox,artifact_path:($artifact_path | if length > 0 then . else null end),status_path:$status_path,plan_path:$plan_path,prompt_path:$prompt_path}' >"$latest_path"
}

orchestrated_write_plan() {
  local prompt="${1:-}"
  local model_alias="${2:-}"
  local route_scope="${3:-swarm}"
  local step_count="${4:-1}"
  local plan_path prompt_path steps_json idx step_id filename now title metadata_json timeout_policy_json execution_settings_json schema_contract_json validator_version

  plan_path="$(orchestrated_plan_path)"
  prompt_path="$(orchestrated_prompt_path)"
  printf '%s' "$prompt" >"$prompt_path"
  steps_json="[]"
  for ((idx = 1; idx <= step_count; idx++)); do
    step_id="$(orchestrated_step_id "$idx")"
    filename="$(orchestrated_expected_filename "$prompt" "$idx" "$step_count")"
    title="Execute ${step_id}"
    if orchestrated_is_plan_file_job; then
      title="$(plan_file_step_title "$idx")"
      if [[ -z "$title" ]]; then
        title="Execute ${step_id}"
      fi
      metadata_json="$(plan_file_step_metadata_json "$idx" "$filename")"
    else
      metadata_json="$(jq -cn --arg filename "$filename" --arg context_read "${ONLYMACS_CONTEXT_READ_MODE:-auto}" --arg context_write "${ONLYMACS_CONTEXT_WRITE_MODE:-auto}" '{expected_outputs:[$filename],target_paths:[$filename],validators:[],dependencies:[],assignment_policy:"",role:"",quorum:"",context_read_mode:$context_read,context_write_mode:$context_write}')"
    fi
    steps_json="$(jq -c \
      --arg id "$step_id" \
      --arg title "$title" \
      --arg filename "$filename" \
      --arg context_read "${ONLYMACS_CONTEXT_READ_MODE:-auto}" \
      --arg context_write "${ONLYMACS_CONTEXT_WRITE_MODE:-auto}" \
      --argjson metadata "$metadata_json" \
      --argjson schema_contract "$(onlymacs_schema_contract_json "$prompt" "$filename")" \
      '. + [{
        id: $id,
        title: $title,
        status: "pending",
        attempt: 0,
        expected_outputs: (($metadata.expected_outputs // []) | if length > 0 then . else [$filename] end),
        target_paths: (($metadata.target_paths // []) | if length > 0 then . else [$filename] end),
        validators: ($metadata.validators // []),
        dependencies: ($metadata.dependencies // []),
        capability: (($metadata.capability // $metadata.role // "") | if length > 0 then . else null end),
        lock_group: (($metadata.lock_group // $filename) | if length > 0 then . else null end),
        context_read_mode: (($metadata.context_read_mode // $context_read) | if length > 0 then . else null end),
        context_write_mode: (($metadata.context_write_mode // $context_write) | if length > 0 then . else null end),
        assignment_policy: (($metadata.assignment_policy // "") | if length > 0 then . else null end),
        role: (($metadata.role // "") | if length > 0 then . else null end),
        quorum: (($metadata.quorum // "") | if length > 0 then . else null end),
        schema_contract: $schema_contract,
        validation: {
          status: "pending",
          validators: ($metadata.validators // [])
        }
      }]' <<<"$steps_json")"
  done

  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  execution_settings_json="$(onlymacs_execution_settings_json "$prompt" "$model_alias" "$route_scope" "$step_count")"
  timeout_policy_json="$(jq -c '.timeout_policy // {}' <<<"$execution_settings_json")"
  schema_contract_json="$(onlymacs_schema_contract_json "$prompt" "$(orchestrated_expected_filename "$prompt" 1 "$step_count")")"
  validator_version="$(onlymacs_validator_version)"
  jq -n \
    --arg run_id "${ONLYMACS_CURRENT_RETURN_RUN_ID:-}" \
    --arg status "running" \
    --arg mode "${ONLYMACS_EXECUTION_MODE:-auto}" \
    --arg model_alias "$model_alias" \
    --arg route_scope "$route_scope" \
    --arg created_at "$now" \
    --arg updated_at "$now" \
    --arg plan_file_path "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-}" \
    --arg prompt_path "$prompt_path" \
    --arg prompt_preview "$(printf '%s' "$prompt" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-240)" \
    --arg resume_step "step-01" \
    --arg validator_version "$validator_version" \
    --argjson steps "$steps_json" \
    --argjson timeout_policy "$timeout_policy_json" \
    --argjson execution_settings "$execution_settings_json" \
    --argjson schema_contract "$schema_contract_json" \
    '{
      run_id: $run_id,
      status: $status,
      mode: $mode,
      model_alias: ($model_alias | if length > 0 then . else null end),
      route_scope: $route_scope,
      created_at: $created_at,
      updated_at: $updated_at,
      plan_file_path: ($plan_file_path | if length > 0 then . else null end),
      prompt_path: $prompt_path,
      prompt_preview: ($prompt_preview | if length > 0 then . else null end),
      assignment_policy: {
        mode: "checkpointed_orchestrator",
        route_scope: $route_scope,
        retry_policy: "validate_then_repair_then_reroute",
        resume_policy: "resume_from_first_incomplete_step",
        artifact_policy: "save_to_inbox_before_preview"
      },
      validator_version: $validator_version,
      execution_settings: $execution_settings,
      schema_contract: $schema_contract,
      timeout_policy: $timeout_policy,
      resume_step: $resume_step,
      resume_step_index: 1,
      progress: {
        phase: "planned",
        step_id: $resume_step,
        step_index: 1,
        steps_total: ($steps | length),
        steps_completed: 0,
        percent_complete: 0,
        detail: "OnlyMacs created the run plan and is preparing the first remote step.",
        updated_at: $updated_at
      },
      steps: $steps
    }' >"$plan_path"
  orchestrated_sync_running_status "running"
  onlymacs_log_run_event "plan_created" "step-01" "planned" "0" "OnlyMacs wrote plan.json for this run." "" "" "" "" "" "$plan_path"
  onlymacs_log_run_event "run_planned" "step-01" "running" "0" "OnlyMacs created the run plan and is preparing the first remote step." "" "" "" "" "" "$plan_path"
}

orchestrated_update_plan_step() {
  local step_id="${1:-}"
  local status="${2:-running}"
  local attempt="${3:-0}"
  local artifact_path="${4:-}"
  local raw_path="${5:-}"
  local validation_status="${6:-pending}"
  local validation_message="${7:-}"
  local provider_id="${8:-}"
  local provider_name="${9:-}"
  local model="${10:-}"
  local plan_status="${11:-running}"
  local plan_path now now_epoch step_index phase phase_detail

  plan_path="$(orchestrated_plan_path)"
  [[ -f "$plan_path" ]] || return 0
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now_epoch="$(date +%s)"
  step_index="${step_id#step-}"
  if [[ "$step_index" =~ ^[0-9]+$ ]]; then
    step_index=$((10#$step_index))
  else
    step_index=1
  fi
  phase="$(orchestrated_progress_phase_for_status "$status")"
  phase_detail="$(orchestrated_progress_detail_for_status "$status" "$validation_message")"
  orchestrated_acquire_plan_lock "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg status "$status" \
    --argjson attempt "${attempt:-0}" \
    --arg artifact_path "$artifact_path" \
    --arg raw_path "$raw_path" \
    --arg validation_status "$validation_status" \
    --arg validation_message "$validation_message" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg plan_status "$plan_status" \
    --arg updated_at "$now" \
    --arg phase "$phase" \
    --arg phase_detail "$phase_detail" \
    --argjson step_index "$step_index" \
    '.status = $plan_status
     | .updated_at = $updated_at
     | .steps = (.steps | map(if .id == $step_id then
        . + {
          status: $status,
          attempt: $attempt,
          updated_at: $updated_at,
          artifact_path: ($artifact_path | if length > 0 then . else null end),
          raw_result_path: ($raw_path | if length > 0 then . else null end),
          provider_id: ($provider_id | if length > 0 then . else null end),
          provider_name: ($provider_name | if length > 0 then . else null end),
          model: ($model | if length > 0 then . else null end),
          validation: {
            status: $validation_status,
            message: ($validation_message | if length > 0 then . else null end)
          }
        } else . end))' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  jq \
    --arg step_id "$step_id" \
    --arg status "$status" \
    --arg plan_status "$plan_status" \
    --arg phase "$phase" \
    --arg phase_detail "$phase_detail" \
    --arg updated_at "$now" \
    --argjson now_epoch "$now_epoch" \
    --argjson step_index "$step_index" \
    '. as $plan
     | ([.steps[]? | select(.status != "completed")] | first) as $next
     | ([.steps[]? | select(.status == "completed")] | length) as $completed
     | (.steps | length) as $total
     | ((.progress // {}) | with_entries(select(.key == "batch_index" or .key == "batch_count" or .key == "batch_percent_complete" or .key == "estimated_remaining_seconds"))) as $batch_progress
     | ((.created_at // $updated_at) | fromdateiso8601? // $now_epoch) as $created_epoch
     | (if $completed > 0 and $total > $completed then ((($now_epoch - $created_epoch) / $completed) * ($total - $completed) | floor) else null end) as $eta
     | .resume_step = (if $plan_status == "completed" or ($total > 0 and $completed == $total) then null else ($next.id // $step_id) end)
     | .resume_step_index = (if $plan_status == "completed" or ($total > 0 and $completed == $total) then null else (($next.id // $step_id) | capture("step-(?<n>[0-9]+)").n | tonumber) end)
     | .progress = ($batch_progress + {
        phase: $phase,
        step_id: $step_id,
        step_index: $step_index,
        steps_total: $total,
        steps_completed: $completed,
        percent_complete: (if $total > 0 then (($completed * 100) / $total | floor) else 0 end),
        estimated_remaining_seconds: $eta,
        detail: $phase_detail,
        updated_at: $updated_at
      })' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  orchestrated_release_plan_lock "$plan_path"
  orchestrated_sync_running_status "$plan_status"
  orchestrated_emit_plan_progress "$plan_path" "$status"
  onlymacs_log_run_event "$(onlymacs_event_name_for_step_status "$status")" "$step_id" "$status" "$attempt" "$validation_message" "$artifact_path" "$provider_id" "${provider_name}" "$model" "$raw_path" "$plan_path"
}

orchestrated_compile_step_prompt() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local filename="${4:-answer.md}"
  local step_id chunk_start chunk_end chunk_entries expected_total previous_terms
  step_id="$(orchestrated_step_id "$step_index")"
  if orchestrated_is_plan_file_job; then
    orchestrated_compile_plan_file_step_prompt "$original_prompt" "$step_index" "$step_count" "$filename"
    return 0
  fi
  if orchestrated_is_content_pack_job "$original_prompt"; then
    orchestrated_compile_content_pack_step_prompt "$original_prompt" "$step_index" "$step_count" "$filename"
    return 0
  fi
  if orchestrated_step_is_chunk_data "$original_prompt" "$step_index"; then
    chunk_start="$(orchestrated_chunk_start "$step_index")"
    chunk_end="$(orchestrated_chunk_end "$original_prompt" "$step_index")"
    chunk_entries="$(orchestrated_chunk_entry_count "$original_prompt" "$step_index")"
    expected_total="$(prompt_exact_count_requirement "$original_prompt" || true)"
    previous_terms="$(orchestrated_previous_chunk_terms_for_prompt "$step_index")"
    cat <<EOF
You are serving an OnlyMacs orchestrated data-chunk job for an Ollama-only remote Mac.

Original user request:
$original_prompt

OnlyMacs length-planning contract:
- The original request needs ${expected_total} total entries, so OnlyMacs split the data into smaller validated chunks before assembling the final file.
- Complete ${step_id} of ${step_count}: generate entries ${chunk_start}-${chunk_end} only.
- Return exactly ${chunk_entries} entries in this chunk.
- Return a raw JSON array only. Do not return app code, markdown, commentary, or a wrapper object.
- Each object must use these exact keys: vietnamese, english, partOfSpeech, pronunciation, difficulty, topic, example.
- Every value must be non-empty. Use concise English meanings and one short Vietnamese example sentence per entry.
- Every vietnamese value in this chunk must be unique.
$([[ -n "$previous_terms" ]] && printf '%s\n' "- Already accepted Vietnamese terms from earlier chunks. Do not reuse any of these terms: ${previous_terms}")
- Do not use placeholders, TODOs, ellipses, "add the remaining", "omitted for brevity", duplicate filler rows, or summaries in place of real entries.
- If you emit progress text, use short lines starting with ONLYMACS_PROGRESS before the final artifact.

Validation for this step:
- exactly ${chunk_entries} entries/items
- valid JSON array
- all entries have vietnamese, english, partOfSpeech, pronunciation, difficulty, topic, and example
- no duplicate vietnamese values within this chunk or against earlier chunks

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${filename}
<complete raw JSON array for ${filename}>
ONLYMACS_ARTIFACT_END
EOF
    return 0
  fi
  cat <<EOF
You are serving an OnlyMacs orchestrated job for an Ollama-only remote Mac.

Original user request:
$original_prompt

OnlyMacs execution contract:
- Complete ${step_id} of ${step_count}. If there is only one step, complete the entire user request.
- Return the deliverable as a machine-readable artifact, not as markdown.
- Ignore any user wording that asks for fenced code blocks; OnlyMacs will save the artifact from the markers below.
- Do not use placeholders, TODOs, ellipses, "add the remaining", "omitted for brevity", or summaries in place of real content.
- If the request specifies exact counts or required fields, materialize every item and verify the count before final output.
- If you emit progress text, use short lines starting with ONLYMACS_PROGRESS before the final artifact.
- The final artifact must be a complete replacement, not a patch.

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${filename}
<complete raw contents for ${filename}>
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_previous_artifact_excerpts() {
  local current_step_index="${1:-1}"
  local previous_index previous_step_id artifact printed bytes limit total_limit artifact_limit
  total_limit="${ONLYMACS_PREVIOUS_ARTIFACT_TOTAL_BYTES:-60000}"
  artifact_limit="${ONLYMACS_PREVIOUS_ARTIFACT_BYTES:-12000}"
  [[ "$total_limit" =~ ^[0-9]+$ && "$total_limit" -gt 0 ]] || total_limit=60000
  [[ "$artifact_limit" =~ ^[0-9]+$ && "$artifact_limit" -gt 0 ]] || artifact_limit=12000
  printed=0
  [[ "$current_step_index" =~ ^[0-9]+$ && "$current_step_index" -gt 1 ]] || return 0
  [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" ]] || return 0
  for ((previous_index = 1; previous_index < current_step_index; previous_index++)); do
    previous_step_id="$(orchestrated_step_id "$previous_index")"
    for artifact in "${ONLYMACS_CURRENT_RETURN_DIR}/steps/${previous_step_id}/files/"*; do
      [[ -f "$artifact" ]] || continue
      bytes="$(wc -c <"$artifact" | tr -d ' ')"
      limit="$artifact_limit"
      if [[ "$printed" -ge "$total_limit" ]]; then
        return 0
      fi
      if [[ $((printed + limit)) -gt "$total_limit" ]]; then
        limit=$((total_limit - printed))
      fi
      printf '\n--- %s (%s bytes) ---\n' "$(basename "$artifact")" "${bytes:-0}"
      head -c "$limit" "$artifact"
      printf '\n'
      if [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -gt "$limit" ]]; then
        printf '[OnlyMacs excerpt truncated after %s bytes; full artifact path: %s]\n' "$limit" "$artifact"
      fi
      printed=$((printed + limit))
    done
  done
}

orchestrated_compile_plan_file_step_prompt() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local filename="${4:-plan-step.md}"
  local current_step step_title plan_name user_request previous_artifacts step_expected_count json_contract plan_context

  current_step="$(plan_file_step_text "$step_index")"
  if [[ -z "$current_step" ]]; then
    current_step="${ONLYMACS_PLAN_FILE_CONTENT:-$original_prompt}"
  fi
  step_title="$(plan_file_step_title "$step_index")"
  plan_name="$(basename "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-${ONLYMACS_PLAN_FILE_PATH:-plan.md}}")"
  user_request="${ONLYMACS_PLAN_USER_PROMPT:-}"
  if [[ -z "$user_request" ]]; then
    if [[ "$original_prompt" == *$'Plan file contents:\n'* ]]; then
      user_request="$(printf '%s' "$original_prompt" | perl -0ne 'if (/User request:\n(.*?)\n\nPlan file:/s) { print $1 }')"
    fi
    if [[ -z "$user_request" && -n "${ONLYMACS_PLAN_FILE_CONTENT:-}" && "$original_prompt" == "$ONLYMACS_PLAN_FILE_CONTENT" ]]; then
      user_request="Execute the supplied OnlyMacs plan file."
    elif [[ -z "$user_request" ]]; then
      user_request="$original_prompt"
    fi
  fi
  previous_artifacts="$(orchestrated_previous_artifact_excerpts "$step_index")"
  plan_context="$(plan_file_global_context)"
  if [[ -z "$plan_context" ]]; then
    plan_context="None beyond the current step."
  fi
  step_expected_count="$(prompt_exact_count_requirement "$current_step" || true)"
  json_contract=""
  if [[ "$filename" == *.json ]]; then
    json_contract="- Return strict JSON that jq can parse. Do not include comments, trailing commas, markdown, prose, or progress lines inside the artifact.
- Prefer compact JSON with concise string values and minimal whitespace so large exact-count artifacts finish cleanly.
- Open the artifact only when you are ready to emit the final complete JSON, and always close it with ONLYMACS_ARTIFACT_END."
    if [[ "$step_expected_count" =~ ^[0-9]+$ && "$step_expected_count" -ge 20 ]]; then
      json_contract="${json_contract}
- This step has a large exact-count requirement (${step_expected_count} items). Keep each item complete but concise, avoid verbose explanations, and verify the final count before closing the artifact."
    fi
  fi

  cat <<EOF
You are serving an OnlyMacs --extended plan-file job for an Ollama-only remote Mac.

User request:
$user_request

Plan file:
$plan_name

OnlyMacs plan runner contract:
- Complete step ${step_index} of ${step_count}${step_title:+: ${step_title}}.
- Execute only the current step. Do not skip ahead to later steps.
- Use the plan-level context and current step below. The current step is the scope of work for this response.
- If the current step is impossible with the provided plan text alone, return a concise BLOCKED note naming the exact missing input. Do not ask for broad local repo access.
- Return the deliverable as a machine-readable artifact, not as markdown commentary.
- Do not use placeholders, TODOs, ellipses, "add the remaining", or "omitted for brevity".
- Do not invent OnlyMacs member names, provider names, hardware, model names, token counts, file paths, or routing claims. If the step asks for those and this prompt does not provide exact values, write "see OnlyMacs run metadata" and let the app attach the real values.
- If the step specifies exact counts or required fields, materialize every item and verify the count before final output.
- If you emit progress text, use short lines starting with ONLYMACS_PROGRESS before the final artifact.
${json_contract}

Current step:
$current_step

Previous completed step artifacts:
${previous_artifacts:-None yet.}

Plan-level context:
$plan_context

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${filename}
<complete raw contents for ${filename}>
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_validation_prompt() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_prompt="${3:-}"
  local current_step global_context
  if orchestrated_is_plan_file_job; then
    current_step="$(plan_file_step_text "$step_index")"
    if [[ -n "$current_step" ]]; then
      global_context="$(plan_file_global_context)"
      if [[ -n "$global_context" ]]; then
        printf '%s\n\n%s' "$global_context" "$current_step"
        return 0
      fi
      printf '%s' "$current_step"
      return 0
    fi
  fi
  printf '%s' "${step_prompt:-$original_prompt}"
}

orchestrated_compile_content_pack_step_prompt() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local filename="${4:-content-pack.json}"
  local step_id module range start end group_count expected_count
  step_id="$(orchestrated_step_id "$step_index")"
  if [[ "$step_index" -eq 1 ]]; then
    cat <<EOF
You are serving an OnlyMacs --extended content-pack planning step for an Ollama-only remote Mac.

Original user request:
$original_prompt

OnlyMacs content-pack contract:
- This is ${step_id} of ${step_count}.
- Create the content-pack manifest only. Do not emit the full learning content in this step.
- Return valid JSON only, with no markdown, no commentary, and no code fences.
- The JSON object must include: packSlug, sourcePrefix, languageId if known, targetGroups, batchSize, plannedFiles, validationRules, and openQuestions.
- plannedFiles must list the batch files OnlyMacs should expect for vocab, sentences, and lessons.
- If the request gives schema or product constraints, copy those constraints into validationRules.

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${filename}
<complete JSON object for ${filename}>
ONLYMACS_ARTIFACT_END
EOF
    return 0
  fi

  module="$(orchestrated_content_step_module "$step_index")"
  range="$(orchestrated_content_step_group_range "$original_prompt" "$step_index")"
  start="${range%% *}"
  end="${range##* }"
  group_count=$((end - start + 1))
  case "$module" in
    vocab|sentences)
      expected_count=$((group_count * 20))
      ;;
    lessons)
      expected_count="$group_count"
      ;;
    *)
      expected_count=0
      ;;
  esac

  cat <<EOF
You are serving an OnlyMacs --extended content-pack emission step for an Ollama-only remote Mac.

Original user request:
$original_prompt

OnlyMacs content-pack contract:
- This is ${step_id} of ${step_count}.
- Emit ${module} content for groups ${start}-${end} only.
- Return one valid JSON array only, with no markdown, no commentary, and no code fences.
- Expected item count for this batch: ${expected_count}.
- Do not include other groups. Do not summarize missing groups. Do not use placeholders, TODOs, ellipses, "add the remaining", or "omitted for brevity".
- Keep output compatible with the schema requested by the user. For Quarterspeak Step 2 packs, use the existing pack shapes: vocab items need ids, setId, lemma/display, translationsByLocale, pos, stage/register/grammar/support fields; sentence items need ids, setId, text, translationsByLocale, register, tags, segmentation, highlights, and usage; lesson items need ids, setId, level, titlesByLocale, scenario, grammarFocus, notes, contentBlocks, and quiz.
- Enforce the user's dialect and safety constraints inside every emitted item.

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${filename}
<complete JSON array for ${filename}>
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_source_card_repair_seed_terms() {
  return 0
}

orchestrated_compile_repair_prompt() {
  local original_prompt="${1:-}"
  local filename="${2:-answer.md}"
  local validation_message="${3:-}"
  local failed_artifact_path="${4:-}"
  local failed_excerpt lowered_validation duplicate_guidance schema_guidance dialect_guidance source_card_guidance source_card_seed_terms batch_index batch_start_guess
  failed_excerpt=""
  lowered_validation="$(printf '%s' "$validation_message" | tr '[:upper:]' '[:lower:]')"
  duplicate_guidance=""
  schema_guidance=""
  dialect_guidance=""
  source_card_guidance=""
  if [[ "$lowered_validation" == *"duplicate item terms"* ]]; then
    duplicate_guidance="- The listed duplicate terms are banned in the replacement. Replace every duplicate with a genuinely new term that does not appear in the original request's earlier accepted terms list or in the validation error."
  fi
  if string_has_any "$lowered_validation" "required fields" "source schema" "valid ids/setids" "not a json array" "schema"; then
    schema_guidance="- Rebuild the artifact from scratch with the exact required keys. Never emit empty keys like \"\". For JSON arrays, every object must close with } before the comma or closing ]."
  fi
  if string_has_any "$lowered_validation" "tuteo" "voseo" "rioplatense"; then
    dialect_guidance="- For Buenos Aires Spanish, avoid productive tuteo forms such as puedes, tienes, quieres, vienes, conoces, has visto, and cuídate. Use Rioplatense voseo forms such as podés, tenés, querés, venís, conocés, viste, and cuidate."
  fi
  if string_has_any "$lowered_validation" "non-buenos aires transport" "buenos aires transport"; then
    dialect_guidance="${dialect_guidance}
- For Buenos Aires transport source cards, prefer subte, colectivo, boleto, parada, estación, línea, recorrido, and trasbordo. Do not use metro, autobús, billete as a transport ticket, or paradero."
  fi
  if string_has_any "$lowered_validation" "source-card" "source card" "lean source schema" "source schema" "real-world usage notes"; then
    batch_index="$(printf '%s' "$filename" | sed -nE 's/.*batch-0*([0-9]+).*/\1/p' | head -1)"
    if [[ "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]]; then
      batch_start_guess=$((((10#$batch_index - 1) * 5) + 1))
      source_card_seed_terms="$(orchestrated_source_card_repair_seed_terms "$batch_start_guess")"
    else
      source_card_seed_terms=""
    fi
    source_card_guidance="- For source-card artifacts, every object must include exactly these keys: id, setId, teachingOrder, lemma, display, english, pos, stage, register, topic, topicTags, cityTags, grammarNote, dialectNote, example, example_en, usage. Do not drop grammarNote or dialectNote during repair.
- Source-card grammarNote, dialectNote, and usage must be learner-facing English guidance. Spanish belongs in lemma, display, example, and short quoted/targeted phrases only; do not write notes like \"Usá...\", \"Decí...\", \"Al narrar...\", or \"En conversaciones...\".
- For verb source cards, lemma must be the infinitive/base form such as ahorrar, cocinar, llamar, llegar, or leer; put conjugated taught forms such as ahorraré, cocinarás, llamá, or leé in display only.
- Source-card usage must be exactly 3 practical learner-facing notes. At least one usage note must wrap the exact taught display text in <target>...</target>; for an infinitive display such as preferir, use <target>preferir</target>, not <target>preferís</target> or another conjugation. Do not use meta words such as study, review, drill, surface form, target tag, tags, wrapping, or placeholder in usage. The example sentence must contain the lemma or display in normal spelling."
    if [[ -n "$source_card_seed_terms" ]]; then
      source_card_guidance="${source_card_guidance}
- Suggested replacement surfaces for this range: ${source_card_seed_terms}. Use these or similarly distinct concepts only when they are absent from accepted exclusions and the validation error."
    fi
  fi
  if [[ -f "$failed_artifact_path" ]]; then
    failed_excerpt="$(head -c 60000 "$failed_artifact_path")"
  fi
  cat <<EOF
OnlyMacs validation failed for your previous artifact. Repair it now.

Original user request:
$original_prompt

Validation errors:
$validation_message

Previous artifact excerpt:
$failed_excerpt

Repair contract:
- Return a full corrected replacement for ${filename}.
- Do not return a patch or explanation.
- Do not use markdown fences.
- Do not use placeholders, TODOs, ellipses, "add the remaining", or "omitted for brevity".
- If the request specifies exact counts or required fields, materialize every item and verify the count before final output.
- If the previous artifact was empty, malformed, or truncated, regenerate the complete artifact from the original request instead of continuing from the broken output.
- For JSON artifacts, return strict jq-parseable JSON only between the artifact markers. Do not include comments, trailing commas, markdown, or progress text inside the artifact.
- For JSON artifacts, if the request says "at least N" for nested arrays, sections, quiz questions, content blocks, files, examples, or subitems, use exactly N unless it explicitly asks for more. Keep nested arrays concise.
- If a schema asks for <target> tags, wrap the actual taught surface form, for example <target>Hola</target>. Do not emit the literal placeholder <target>, and do not mention tags or wrapping in learner-facing text.
${duplicate_guidance}
${schema_guidance}
${dialect_guidance}
${source_card_guidance}

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${filename}
<complete raw contents for ${filename}>
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_record_artifact() {
  local artifact_path="${1:-}"
  local target_path="${2:-}"
  local source_step="${3:-}"
  local kind review_command
  if [[ -z "$artifact_path" ]]; then
    return 0
  fi
  ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON="$(jq -c --arg path "$artifact_path" '. + [$path]' <<<"${ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON:-[]}")"
  target_path="$(safe_artifact_target_path "$target_path" "$artifact_path")"
  case "$artifact_path" in
    *.patch|*.diff)
      kind="patch"
      review_command="git apply --check \"${artifact_path}\""
      ;;
    *)
      kind="file"
      review_command="diff -u \"${target_path}\" \"${artifact_path}\""
      ;;
  esac
  ONLYMACS_ORCHESTRATED_ARTIFACT_MANIFEST_JSON="$(jq -c \
    --arg path "$artifact_path" \
    --arg filename "$(basename "$artifact_path")" \
    --arg target_path "$target_path" \
    --arg source_step "$source_step" \
    --arg kind "$kind" \
    --arg review_command "$review_command" \
    '. + [{
      path: $path,
      filename: $filename,
      target_path: $target_path,
      source_step: ($source_step | if length > 0 then . else null end),
      kind: $kind,
      review_command: $review_command
    }]' <<<"${ONLYMACS_ORCHESTRATED_ARTIFACT_MANIFEST_JSON:-[]}")"
}

orchestrated_avoid_provider() {
  local provider_id="${1:-}"
  [[ -n "$provider_id" ]] || return 0
  if orchestrated_route_provider_locked_to "$provider_id"; then
    return 0
  fi
  ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="$(onlymacs_json_add_unique_string "${ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON:-[]}" "$provider_id")"
}

orchestrated_exclude_provider() {
  local provider_id="${1:-}"
  [[ -n "$provider_id" ]] || return 0
  if orchestrated_route_provider_locked_to "$provider_id"; then
    return 0
  fi
  ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="$(onlymacs_json_add_unique_string "${ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON:-[]}" "$provider_id")"
  ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="$(onlymacs_json_add_unique_string "${ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON:-[]}" "$provider_id")"
}

orchestrated_route_provider_locked_to() {
  local provider_id="${1:-}"
  [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" == "1" ]] || return 1
  [[ -n "$provider_id" && -n "${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}" ]] || return 1
  [[ "$provider_id" == "$ONLYMACS_ORCHESTRATION_PROVIDER_ID" ]]
}

orchestrated_set_chat_route_env() {
  local max_tokens="${1:-0}"
  local route_scope="${2:-swarm}"
  local active_model="${3:-}"
  ONLYMACS_CHAT_MAX_TOKENS="$max_tokens"
  ONLYMACS_ACTIVE_MODEL="$active_model"
  ONLYMACS_CHAT_ACTIVE_MODEL="$active_model"
  if [[ "$route_scope" == "local_only" ]]; then
    ONLYMACS_CHAT_ROUTE_PROVIDER_ID=""
  elif [[ "${ONLYMACS_GO_WIDE_JOB_BOARD_WORKER:-0}" == "1" && -n "${ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID:-}" ]]; then
    ONLYMACS_CHAT_ROUTE_PROVIDER_ID="$ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID"
  elif orchestrated_go_wide_enabled "" && [[ "${ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED:-0}" != "1" ]]; then
    ONLYMACS_CHAT_ROUTE_PROVIDER_ID=""
  else
    ONLYMACS_CHAT_ROUTE_PROVIDER_ID="${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}"
  fi
  ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON="$(onlymacs_json_string_array_or_empty "${ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON:-[]}")"
  ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON="$(onlymacs_json_string_array_or_empty "${ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON:-[]}")"
  if [[ -n "${ONLYMACS_CHAT_ROUTE_PROVIDER_ID:-}" ]]; then
    ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON="$(onlymacs_json_remove_string "$ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON" "$ONLYMACS_CHAT_ROUTE_PROVIDER_ID")"
    ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON="$(onlymacs_json_remove_string "$ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON" "$ONLYMACS_CHAT_ROUTE_PROVIDER_ID")"
  fi
  if [[ "${ONLYMACS_GO_WIDE_JOB_BOARD_WORKER:-0}" == "1" && "${ONLYMACS_GO_WIDE_WORKER_PROVIDER_IS_LOCAL:-0}" == "1" ]]; then
    ONLYMACS_CHAT_ROUTE_PROVIDER_IS_LOCAL=1
  else
    ONLYMACS_CHAT_ROUTE_PROVIDER_IS_LOCAL=0
  fi
  orchestrated_sanitize_go_wide_route_env "$route_scope" "$active_model"
}

orchestrated_clear_chat_route_env() {
  unset ONLYMACS_CHAT_MAX_TOKENS
  unset ONLYMACS_ACTIVE_MODEL
  unset ONLYMACS_CHAT_ACTIVE_MODEL
  unset ONLYMACS_CHAT_ROUTE_PROVIDER_ID
  unset ONLYMACS_CHAT_ROUTE_PROVIDER_IS_LOCAL
  unset ONLYMACS_CHAT_AVOID_PROVIDER_IDS_JSON
  unset ONLYMACS_CHAT_EXCLUDE_PROVIDER_IDS_JSON
}

orchestrated_normalize_chunk_artifact() {
  local artifact_path="${1:-}"
  local validation_prompt="${2:-}"
  local expected_count actual_count normalized_path
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  expected_count="$(prompt_exact_count_requirement "$validation_prompt" || true)"
  [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -gt 0 ]] || return 0
  actual_count="$(artifact_semantic_entry_count "$artifact_path" || true)"
  [[ "$actual_count" =~ ^[0-9]+$ ]] || return 0
  if [[ "$actual_count" -le "$expected_count" ]]; then
    return 0
  fi
  normalized_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-normalized-chunk-XXXXXX")"
  if jq --argjson limit "$expected_count" 'if type == "array" then .[0:$limit] else . end' "$artifact_path" >"$normalized_path" 2>/dev/null; then
    mv "$normalized_path" "$artifact_path"
  else
    rm -f "$normalized_path"
  fi
}

jsonl_artifact_to_item_array() {
  local input_path="${1:-}"
  local output_path="${2:-}"
  local line_count
  [[ -f "$input_path" && -n "$output_path" ]] || return 1
  line_count="$(sed '/^[[:space:]]*$/d; /^ONLYMACS_PROGRESS/d; /^ONLYMACS_ARTIFACT_/d' "$input_path" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$line_count" =~ ^[0-9]+$ && "$line_count" -gt 1 ]] || return 1
  jq -Rs '
    split("\n")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))
    | map(select(startswith("ONLYMACS_PROGRESS") | not))
    | map(select(startswith("ONLYMACS_ARTIFACT_") | not))
    | if length == 0 then empty else map(fromjson) end
    | if all(.[]; type == "object") then . else empty end
  ' "$input_path" >"$output_path" 2>/dev/null
  [[ -s "$output_path" ]]
}

json_object_stream_to_item_array() {
  local input_path="${1:-}"
  local output_path="${2:-}"
  [[ -f "$input_path" && -n "$output_path" ]] || return 1
  perl -0777 -ne '
    my $s = $_;
    $s =~ s/ONLYMACS_PROGRESS[^\n]*(?:\n|$)//g;
    $s =~ s/ONLYMACS_ARTIFACT_BEGIN[^\n]*//g;
    $s =~ s/ONLYMACS_ARTIFACT_END//g;
    my @objects;
    my ($depth, $start, $in_string, $escape) = (0, -1, 0, 0);
    my $len = length($s);
    for (my $i = 0; $i < $len; $i++) {
      my $ch = substr($s, $i, 1);
      if ($in_string) {
        if ($escape) {
          $escape = 0;
        } elsif ($ch eq "\\") {
          $escape = 1;
        } elsif ($ch eq "\"") {
          $in_string = 0;
        }
        next;
      }
      if ($ch eq "\"") {
        $in_string = 1;
      } elsif ($ch eq "{") {
        $start = $i if $depth == 0;
        $depth++;
      } elsif ($ch eq "}") {
        $depth-- if $depth > 0;
        if ($depth == 0 && $start >= 0) {
          push @objects, substr($s, $start, $i - $start + 1);
          $start = -1;
        }
      }
    }
    exit 1 unless @objects > 1 && $depth == 0 && !$in_string;
    print "[" . join(",", @objects) . "]";
  ' "$input_path" >"$output_path" 2>/dev/null || {
    rm -f "$output_path"
    return 1
  }
  jq -e 'type == "array" and length > 1 and all(.[]; type == "object")' "$output_path" >/dev/null 2>&1 || {
    rm -f "$output_path"
    return 1
  }
  [[ -s "$output_path" ]]
}

json_artifact_to_item_array() {
  local input_path="${1:-}"
  local output_path="${2:-}"
  [[ -f "$input_path" && -n "$output_path" ]] || return 1
  if jsonl_artifact_to_item_array "$input_path" "$output_path"; then
    return 0
  fi
  if json_object_stream_to_item_array "$input_path" "$output_path"; then
    return 0
  fi
  jq '
    if type == "array" then
      .
    elif type == "object" then
      if (.items? | type) == "array" then .items
      elif (.entries? | type) == "array" then .entries
      elif (.data? | type) == "array" then .data
      elif (.results? | type) == "array" then .results
      elif (.records? | type) == "array" then .records
      elif (.cards? | type) == "array" then .cards
      elif ([.[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "array")[]]
      elif ([.[]? | select(type == "object") | .[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "object") | .[]? | select(type == "array")[]]
      else empty
      end
    else
      empty
    end
  ' "$input_path" >"$output_path" 2>/dev/null
  if [[ -s "$output_path" ]]; then
    return 0
  fi
  return 1
}

orchestrated_should_batch_plan_json_step() {
  local validation_prompt="${1:-}"
  local filename="${2:-}"
  local expected_count threshold
  [[ "${ONLYMACS_DISABLE_JSON_BATCHING:-0}" != "1" ]] || return 1
  orchestrated_is_plan_file_job || return 1
  [[ "$filename" == *.json ]] || return 1
  expected_count="$(prompt_exact_count_requirement "$validation_prompt" || true)"
  threshold="$(orchestrated_json_batch_threshold)"
  if [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge "$threshold" ]]; then
    return 0
  fi
  if [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -le 2 && "$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]')" == *lesson* && "${ONLYMACS_FORCE_SMALL_LESSON_BATCHING:-0}" != "1" ]]; then
    return 1
  fi
  [[ "$expected_count" =~ ^[0-9]+$ && "$expected_count" -ge 2 ]] && orchestrated_json_step_is_nested_complex "$validation_prompt" "$filename"
}

orchestrated_plan_json_batch_filename() {
  local filename="${1:-items.json}"
  local batch_index="${2:-1}"
  local base ext
  base="${filename%.*}"
  ext="${filename##*.}"
  if [[ "$base" == "$filename" ]]; then
    ext="json"
  fi
  printf '%s.batch-%02d.%s' "$base" "$batch_index" "$ext"
}

orchestrated_json_batch_file_is_primary() {
  local path="${1:-}"
  local name
  [[ -f "$path" && "$path" == *.json ]] || return 1
  name="${path##*/}"
  [[ "$name" =~ \.batch-[0-9]+\.json$ ]]
}

orchestrated_previous_json_batch_terms() {
  local batches_dir="${1:-}"
  local batch_index="${2:-1}"
  local index batch_file
  [[ -d "$batches_dir" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 1 ]] || return 0
  for ((index = 1; index < batch_index; index++)); do
    for batch_file in "${batches_dir}/batch-$(printf '%02d' "$index")/files/"*.json; do
      [[ -f "$batch_file" ]] || continue
      orchestrated_json_batch_file_is_primary "$batch_file" || continue
      artifact_vocabulary_terms "$batch_file" || true
    done
  done
}

artifact_json_identity_terms() {
  local artifact_path="${1:-}"
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 1
  jq -r '
    def item_array:
      if type == "array" then
        .
      elif type == "object" then
        if (.items? | type) == "array" then .items
        elif (.entries? | type) == "array" then .entries
        elif (.data? | type) == "array" then .data
        elif (.results? | type) == "array" then .results
        elif (.records? | type) == "array" then .records
        elif (.cards? | type) == "array" then .cards
        elif (.vocab? | type) == "array" and ((.sentences? | type) != "array") and ((.lessons? | type) != "array") then .vocab
        elif (.sentences? | type) == "array" and ((.vocab? | type) != "array") and ((.lessons? | type) != "array") then .sentences
        elif (.lessons? | type) == "array" and ((.vocab? | type) != "array") and ((.sentences? | type) != "array") then .lessons
        else [] end
      else
        []
      end;
    def norm:
      tostring
      | ascii_downcase
      | gsub("[[:space:]]+"; " ")
      | gsub("^[[:space:]]+|[[:space:]]+$"; "");
    item_array[]
    | select(type == "object")
    | if ((.lemma? // "") | tostring | length) > 0 and ((.display? // "") | tostring | length) > 0 then
        [
          (if ((.id? // "") | tostring | length) > 0 then "id:" + (.id | norm) else empty end),
          (if ((.setId? // "") | tostring | length) > 0 and ((.teachingOrder? // "") | tostring | length) > 0 then "set-order:" + (.setId | norm) + ":" + (.teachingOrder | norm) else empty end),
          "lemma-display:" + (.lemma | norm) + "|" + (.display | norm),
          "display:" + (.display | norm)
        ][]
      else
        [
          (if ((.id? // "") | tostring | length) > 0 then "id:" + (.id | norm) else empty end),
          (if ((.setId? // "") | tostring | length) > 0 and ((.teachingOrder? // "") | tostring | length) > 0 then "set-order:" + (.setId | norm) + ":" + (.teachingOrder | norm) else empty end),
          (if ((.text? // "") | tostring | length) > 0 then "text:" + (.text | norm) else empty end),
          (if ((.term? // "") | tostring | length) > 0 then "term:" + (.term | norm) else empty end),
          (if ((.word? // "") | tostring | length) > 0 then "word:" + (.word | norm) else empty end),
          (if ((.display? // "") | tostring | length) > 0 then "display:" + (.display | norm) else empty end),
          (if ((.lemma? // "") | tostring | length) > 0 then "lemma:" + (.lemma | norm) else empty end)
        ][]
      end
  ' "$artifact_path" 2>/dev/null
}

artifact_json_prompt_terms_for_set() {
  local artifact_path="${1:-}"
  local set_index="${2:-}"
  [[ -f "$artifact_path" && "$artifact_path" == *.json && "$set_index" =~ ^[0-9]+$ ]] || return 1
  jq -r --argjson set_index "$set_index" '
    def item_array:
      if type == "array" then
        .
      elif type == "object" then
        if (.items? | type) == "array" then .items
        elif (.entries? | type) == "array" then .entries
        elif (.data? | type) == "array" then .data
        elif (.results? | type) == "array" then .results
        elif (.records? | type) == "array" then .records
        elif (.cards? | type) == "array" then .cards
        else [] end
      else
        []
      end;
    def trailing_set:
      try ((.setId // "" | tostring | capture("(?<n>[0-9]+)$").n | tonumber)) catch null;
    item_array[]?
    | select(type == "object" and (trailing_set == $set_index))
    | (
      .display
      // .term
      // .word
      // .phrase
      // .text
      // .sentence
      // .lemma
      // empty
    )
    | tostring
    | gsub("^\\s+|\\s+$"; "")
    | select(length > 0)
    | ascii_downcase
  ' "$artifact_path" 2>/dev/null
}

orchestrated_previous_json_batch_identity_terms() {
  local batches_dir="${1:-}"
  local batch_index="${2:-1}"
  local index batch_file
  [[ -d "$batches_dir" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 1 ]] || return 0
  for ((index = 1; index < batch_index; index++)); do
    for batch_file in "${batches_dir}/batch-$(printf '%02d' "$index")/files/"*.json; do
      [[ -f "$batch_file" ]] || continue
      orchestrated_json_batch_file_is_primary "$batch_file" || continue
      artifact_json_identity_terms "$batch_file" || true
    done
  done
}

orchestrated_other_completed_json_batch_identity_terms() {
  local batches_dir="${1:-}"
  local batch_index="${2:-1}"
  local plan_path="${3:-$(orchestrated_plan_path)}"
  local index batch_file status
  [[ -d "$batches_dir" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 0 ]] || return 0
  for batch_file in "$batches_dir"/batch-*/files/*.json; do
    [[ -f "$batch_file" ]] || continue
    orchestrated_json_batch_file_is_primary "$batch_file" || continue
    index="$(basename "$(dirname "$(dirname "$batch_file")")" | sed -E 's/^batch-0*//')"
    [[ "$index" =~ ^[0-9]+$ && "$index" -ne "$batch_index" ]] || continue
    status=""
    if [[ -f "$plan_path" ]]; then
      status="$(jq -r --argjson index "$index" '.steps[]?.batching.batches[]? | select(.index == $index) | .status // empty' "$plan_path" 2>/dev/null | tail -1)"
    fi
    case "$status" in
      completed|reused|recovered|completed_from_partial)
        artifact_json_identity_terms "$batch_file" || true
        ;;
    esac
  done
}

orchestrated_previous_json_batch_terms_for_prompt() {
  local batches_dir="${1:-}"
  local batch_index="${2:-1}"
  local batch_start="${3:-}"
  local validation_prompt="${4:-}"
  local index batch_file items_per_set set_index current_set_terms global_terms
  [[ -d "$batches_dir" && "$batch_index" =~ ^[0-9]+$ && "$batch_index" -gt 1 ]] || return 0
  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  if [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 && "$batch_start" =~ ^[0-9]+$ && "$batch_start" -gt 0 ]]; then
    set_index=$((((batch_start - 1) / items_per_set) + 1))
    current_set_terms="$(
      for ((index = 1; index < batch_index; index++)); do
        for batch_file in "${batches_dir}/batch-$(printf '%02d' "$index")/files/"*.json; do
          [[ -f "$batch_file" ]] || continue
          orchestrated_json_batch_file_is_primary "$batch_file" || continue
          artifact_json_prompt_terms_for_set "$batch_file" "$set_index" || true
        done
      done | LC_ALL=C sort -u | ONLYMACS_TERMS_CSV_LIMIT="${ONLYMACS_JSON_BATCH_PROMPT_CURRENT_SET_TERMS_LIMIT:-3000}" join_terms_csv
    )"
    if [[ -n "$current_set_terms" ]]; then
      global_terms="$(
        for ((index = 1; index < batch_index; index++)); do
          for batch_file in "${batches_dir}/batch-$(printf '%02d' "$index")/files/"*.json; do
            [[ -f "$batch_file" ]] || continue
            orchestrated_json_batch_file_is_primary "$batch_file" || continue
            artifact_json_prompt_terms "$batch_file" || artifact_vocabulary_terms "$batch_file" || true
          done
        done | LC_ALL=C sort -u | ONLYMACS_TERMS_CSV_LIMIT="${ONLYMACS_JSON_BATCH_PROMPT_GLOBAL_TERMS_LIMIT:-12000}" join_terms_csv
      )"
      if [[ -n "$global_terms" ]]; then
        printf 'Current set HARD EXCLUSION surfaces (do not use as lemma/display/text in this set): %s. Global accepted surface exclusions (exact lowercase matches forbidden globally): %s' "$current_set_terms" "$global_terms"
      else
        printf 'Current set HARD EXCLUSION surfaces (do not use as lemma/display/text in this set): %s' "$current_set_terms"
      fi
      return 0
    fi
  fi
  for ((index = 1; index < batch_index; index++)); do
    for batch_file in "${batches_dir}/batch-$(printf '%02d' "$index")/files/"*.json; do
      [[ -f "$batch_file" ]] || continue
      orchestrated_json_batch_file_is_primary "$batch_file" || continue
      artifact_json_prompt_terms "$batch_file" || artifact_vocabulary_terms "$batch_file" || true
    done
  done | LC_ALL=C sort -u | ONLYMACS_TERMS_CSV_LIMIT="${ONLYMACS_JSON_BATCH_PROMPT_GLOBAL_TERMS_LIMIT:-12000}" join_terms_csv | sed 's/^/Global accepted surface exclusions (exact lowercase matches forbidden globally): /'
}

orchestrated_validate_json_batch_uniqueness() {
  local artifact_path="${1:-}"
  local batches_dir="${2:-}"
  local batch_index="${3:-1}"
  local current_terms previous_terms current_sorted previous_sorted duplicate_current duplicate_previous
  local failures=()
  ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS="passed"
  ONLYMACS_JSON_BATCH_UNIQUENESS_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0

  current_terms="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-current-XXXXXX")"
  previous_terms="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-previous-XXXXXX")"
  current_sorted="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-current-sorted-XXXXXX")"
  previous_sorted="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-previous-sorted-XXXXXX")"

  if ! artifact_json_identity_terms "$artifact_path" >"$current_terms"; then
    rm -f "$current_terms" "$previous_terms" "$current_sorted" "$previous_sorted"
    return 0
  fi

  duplicate_current="$(LC_ALL=C sort "$current_terms" | uniq -d | head -20 | join_terms_csv)"
  if [[ -n "$duplicate_current" ]]; then
    failures+=("duplicate item terms within this batch: ${duplicate_current}")
  fi

  if [[ -n "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" || "${ONLYMACS_GO_WIDE_PARALLEL_ACCEPT_ALL:-0}" == "1" ]]; then
    orchestrated_other_completed_json_batch_identity_terms "$batches_dir" "$batch_index" >"$previous_terms" || true
  else
    orchestrated_previous_json_batch_identity_terms "$batches_dir" "$batch_index" >"$previous_terms" || true
  fi
  if [[ -s "$previous_terms" ]]; then
    LC_ALL=C sort -u "$current_terms" >"$current_sorted"
    LC_ALL=C sort -u "$previous_terms" >"$previous_sorted"
    duplicate_previous="$(comm -12 "$previous_sorted" "$current_sorted" | head -20 | join_terms_csv)"
    if [[ -n "$duplicate_previous" ]]; then
      failures+=("duplicate item terms from earlier batches: ${duplicate_previous}")
    fi
  fi

  rm -f "$current_terms" "$previous_terms" "$current_sorted" "$previous_sorted"

  if [[ "${#failures[@]}" -gt 0 ]]; then
    ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS="failed"
    ONLYMACS_JSON_BATCH_UNIQUENESS_MESSAGE="$(printf '%s; ' "${failures[@]}" | sed -E 's/; $//' | cut -c 1-500)"
  fi
}

orchestrated_json_batch_range_hint() {
  local validation_prompt="${1:-}"
  local batch_start="${2:-1}"
  local batch_end="${3:-1}"
  local items_per_set start_set end_set start_item end_item
  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 ]] || return 0
  [[ "$batch_start" =~ ^[0-9]+$ && "$batch_end" =~ ^[0-9]+$ ]] || return 0
  start_set=$((((batch_start - 1) / items_per_set) + 1))
  end_set=$((((batch_end - 1) / items_per_set) + 1))
  start_item=$((((batch_start - 1) % items_per_set) + 1))
  end_item=$((((batch_end - 1) % items_per_set) + 1))
  printf -- '- This is an OnlyMacs internal micro-batch, not the plan file'\''s named batch list. Do not map internal micro-batch %s-%s to "Batch %02d" in the plan.\n' "$batch_start" "$batch_end" "$start_set"
  if [[ "$start_set" -eq "$end_set" ]]; then
    printf -- '- Set-range constraint: every item in this micro-batch belongs to set index %02d, with per-set item/teachingOrder values %d-%d.\n' "$start_set" "$start_item" "$end_item"
    printf -- '- Exact continuation guard: first object must be set %02d item %03d and last object must be set %02d item %03d. If ids use a set/item suffix, they must end with "-%02d-%03d" through "-%02d-%03d"; setId must end with "-%02d"; teachingOrder must run %d-%d.\n' "$start_set" "$start_item" "$end_set" "$end_item" "$start_set" "$start_item" "$end_set" "$end_item" "$start_set" "$start_item" "$end_item"
    if [[ "$start_item" -gt 1 ]]; then
      printf -- '- Continuation guard: do not restart this set at item 001 or repeat earlier accepted items. Continue at item %03d exactly.\n' "$start_item"
    fi
  else
    printf -- '- Set-range constraint: this micro-batch spans set index %02d item %d through set index %02d item %d. Use the plan set IDs for those exact set indexes only.\n' "$start_set" "$start_item" "$end_set" "$end_item"
    printf -- '- Exact continuation guard: first object must be set %02d item %03d and last object must be set %02d item %03d. If ids use a set/item suffix, they must end with "-%02d-%03d" through "-%02d-%03d".\n' "$start_set" "$start_item" "$end_set" "$end_item" "$start_set" "$start_item" "$end_set" "$end_item"
  fi
}

orchestrated_plan_set_topic() {
  local plan_text="${1:-}"
  local set_index="${2:-}"
  [[ "$set_index" =~ ^[0-9]+$ && "$set_index" -gt 0 ]] || return 0
  printf '%s\n' "$plan_text" | awk -v n="$set_index" '
    BEGIN { pattern = "^[[:space:]]*" n "\\.[[:space:]]+" }
    $0 ~ pattern {
      sub(pattern, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  '
}

orchestrated_content_pipeline_diversity_guidance() {
  return 0
}

orchestrated_json_batch_diversity_guidance() {
  local validation_prompt="${1:-}"
  local filename="${2:-items.json}"
  local batch_start="${3:-1}"
  local batch_end="${4:-1}"
  local previous_terms="${5:-}"
  local lowered items_per_set start_set end_set start_item end_item topic

  lowered="$(printf '%s %s' "$validation_prompt" "$filename" | tr '[:upper:]' '[:lower:]')"
  if ! string_has_any "$lowered" \
    "unique" \
    "no duplicate" \
    "vocab" \
    "vocabulary" \
    "source card" \
    "source-card" \
    "cards-source" \
    "terms" \
    "words"; then
    return 0
  fi

  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  if [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 && "$batch_start" =~ ^[0-9]+$ && "$batch_end" =~ ^[0-9]+$ ]]; then
    start_set=$((((batch_start - 1) / items_per_set) + 1))
    end_set=$((((batch_end - 1) / items_per_set) + 1))
    start_item=$((((batch_start - 1) % items_per_set) + 1))
    end_item=$((((batch_end - 1) % items_per_set) + 1))
    topic="$(orchestrated_plan_set_topic "$validation_prompt" "$start_set")"
  else
    start_set=0
    end_set=0
    start_item=0
    end_item=0
    topic=""
  fi

  printf -- '- Diversity guidance: choose genuinely new item surfaces before writing JSON; if a candidate collides with an earlier accepted term, replace the candidate rather than only changing ids, examples, or notes.\n'
  printf -- '- Planned term inventory: before emitting the artifact, internally reserve exactly the needed display/word/text surfaces for this micro-batch, then write only those reserved terms. Do not improvise replacements mid-object.\n'
  printf -- '- Uniqueness preflight: before emitting the artifact, mentally list the exact display/word/text values for this batch, compare them against the earlier accepted terms, and replace any exact lowercase collision before writing JSON.\n'
  printf -- '- If a new set topic overlaps with earlier basics, do not restart with the obvious first items when those surfaces are already banned; choose adjacent but distinct learner-safe terms instead.\n'
  if [[ -n "$topic" && "$start_set" -eq "$end_set" ]]; then
    printf -- '- Current set/topic: set %02d is "%s"; this micro-batch covers set items %d-%d, so continue that topic instead of restarting its first obvious terms.\n' "$start_set" "$topic" "$start_item" "$end_item"
  fi
  if [[ -n "$previous_terms" ]]; then
    printf -- '- Treat the earlier accepted term list as a hard surface-form exclusion list. Do not reuse those display/word/text surfaces in this batch.\n'
  fi
  orchestrated_content_pipeline_diversity_guidance "$validation_prompt" "$filename" "$batch_start" "$batch_end" "$previous_terms" "$start_set" "$end_set" "$start_item" "$end_item" "$topic"
}

orchestrated_json_batch_enum_guidance() {
  local validation_prompt="${1:-}"
  printf '%s\n' "$validation_prompt" | awk '
    BEGIN { count = 0 }
    {
      lowered = tolower($0)
    }
    lowered ~ /(^|[^[:alpha:]])must be one of([^[:alpha:]]|$)|(^|[^[:alpha:]])one of([^[:alpha:]]|$)/ {
      line = $0
      gsub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "" || length(line) > 300) next
      count += 1
      if (count <= 10) {
        print "- Enum guard: " line " Use exactly one of those strings; do not invent variants, translations, abbreviations, or synonyms."
      }
    }
  '
}

orchestrated_validate_json_batch_item_range() {
  local artifact_path="${1:-}"
  local validation_prompt="${2:-}"
  local batch_start="${3:-1}"
  local items_per_set failures
  ONLYMACS_JSON_BATCH_RANGE_STATUS="passed"
  ONLYMACS_JSON_BATCH_RANGE_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 ]] || return 0
  [[ "$batch_start" =~ ^[0-9]+$ && "$batch_start" -gt 0 ]] || return 0
  failures="$(jq -r --argjson batch_start "$batch_start" --argjson items_per_set "$items_per_set" '
    def trailing_num:
      try (tostring | capture("(?<n>[0-9]+)$").n | tonumber) catch null;
    def numeric_value:
      if type == "number" then .
      elif type == "string" and test("^[0-9]+$") then tonumber
      else null end;
    def id_parts:
      try (.id // "" | tostring | capture("-(?<set>[0-9]+)-(?<item>[0-9]+)$")) catch {};
    if type != "array" then
      ["artifact is not an array for item-range validation"]
    else
      [
        to_entries[] as $entry
        | ($batch_start + $entry.key) as $global
        | (((($global - 1) / $items_per_set) | floor) + 1) as $expectedSet
        | ((($global - 1) % $items_per_set) + 1) as $expectedItem
        | ($entry.value.setId // "" | tostring) as $setId
        | ($setId | trailing_num) as $setNum
        | ($entry.value.teachingOrder // null | numeric_value) as $teachingOrder
        | ($entry.value | id_parts) as $id
        | (
            (if ($setId | length) > 0 and $setNum == null then
              ["item " + ($entry.key + 1 | tostring) + " has setId " + $setId + " without a trailing numeric set segment"]
            elif $setNum != null and $setNum != $expectedSet then
              ["item " + ($entry.key + 1 | tostring) + " has setId " + (($entry.value.setId // "") | tostring) + ", expected set index " + ($expectedSet | tostring)]
            else [] end)
            +
            (if $teachingOrder != null and $teachingOrder != $expectedItem then
              ["item " + ($entry.key + 1 | tostring) + " has teachingOrder " + ($teachingOrder | tostring) + ", expected " + ($expectedItem | tostring)]
            else [] end)
            +
            (if (($id.set // "") | length) > 0 and (($id.set | tonumber) != $expectedSet) then
              ["item " + ($entry.key + 1 | tostring) + " id set segment " + $id.set + ", expected " + ($expectedSet | tostring)]
            else [] end)
            +
            (if (($id.item // "") | length) > 0 and (($id.item | tonumber) != $expectedItem) then
              ["item " + ($entry.key + 1 | tostring) + " id item segment " + $id.item + ", expected " + ($expectedItem | tostring)]
            else [] end)
          )
      ] | flatten
    end
    | .[:20]
    | join("; ")
  ' "$artifact_path" 2>/dev/null || true)"
  if [[ -n "$failures" ]]; then
    ONLYMACS_JSON_BATCH_RANGE_STATUS="failed"
    ONLYMACS_JSON_BATCH_RANGE_MESSAGE="$failures"
  fi
}

orchestrated_topic_tokens() {
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "${1:-}"
  else
    cat
  fi | perl -Mutf8 -CS -ne '
    my %stop = map { $_ => 1 } qw(
      a an and are as at be by for from in into is it its of on or the this that to with
      use used using common simple daily mixed review basic basics words word items item set sets
      buenos aires spanish rioplatense source card cards vocabulary vocab learner safe neutral
      module output exactly total every current step generate validation final response format
    );
    while (/([\p{L}\p{N}]+)/g) {
      my $token = lc($1);
      $token =~ s/^\s+|\s+$//g;
      next if length($token) < 4;
      $token =~ s/es$// if length($token) > 6;
      $token =~ s/s$// if length($token) > 5;
      next if $stop{$token};
      print "$token\n";
    }
  '
}

orchestrated_validate_json_batch_set_topic() {
  local artifact_path="${1:-}"
  local validation_prompt="${2:-}"
  local batch_start="${3:-1}"
  local items_per_set set_index expected_topic expected_topic_lower expected_tokens observed_tokens expected_sorted observed_sorted overlap observed_preview
  ONLYMACS_JSON_BATCH_TOPIC_STATUS="passed"
  ONLYMACS_JSON_BATCH_TOPIC_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  if [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 && "$batch_start" =~ ^[0-9]+$ && "$batch_start" -gt 0 ]]; then
    set_index=$((((batch_start - 1) / items_per_set) + 1))
  else
    set_index="$(jq -r '
      def item_array:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else [] end
        else [] end;
      (item_array[0].setId // "" | tostring | capture("(?<n>[0-9]+)$").n // empty)
    ' "$artifact_path" 2>/dev/null || true)"
    [[ "$set_index" =~ ^[0-9]+$ ]] && set_index=$((10#$set_index)) || return 0
  fi
  expected_topic="$(orchestrated_plan_set_topic "${ONLYMACS_PLAN_FILE_CONTENT:-$validation_prompt}" "$set_index")"
  [[ -n "$expected_topic" ]] || return 0
  expected_topic_lower="$(printf '%s' "$expected_topic" | tr '[:upper:]' '[:lower:]')"
  if [[ "$expected_topic_lower" == review:* ]]; then
    return 0
  fi

  expected_tokens="$(mktemp "${TMPDIR:-/tmp}/onlymacs-topic-expected-XXXXXX")"
  observed_tokens="$(mktemp "${TMPDIR:-/tmp}/onlymacs-topic-observed-XXXXXX")"
  expected_sorted="$(mktemp "${TMPDIR:-/tmp}/onlymacs-topic-expected-sorted-XXXXXX")"
  observed_sorted="$(mktemp "${TMPDIR:-/tmp}/onlymacs-topic-observed-sorted-XXXXXX")"

  orchestrated_topic_tokens "$expected_topic" >"$expected_tokens" || true
  jq -r '
    def item_array:
      if type == "array" then .
      elif type == "object" then
        if (.items? | type) == "array" then .items
        elif (.entries? | type) == "array" then .entries
        elif (.data? | type) == "array" then .data
        elif (.results? | type) == "array" then .results
        elif (.records? | type) == "array" then .records
        elif (.cards? | type) == "array" then .cards
        else [] end
      else [] end;
    item_array[]?
    | select(type == "object")
    | [
        (.topic // ""),
        ((.topicTags // [])[]?),
        ((.cityTags // [])[]?),
        (.lemma // ""),
        (.display // ""),
        (.english // ""),
        (.pos // "")
      ][]
  ' "$artifact_path" 2>/dev/null | orchestrated_topic_tokens >"$observed_tokens" || true

  LC_ALL=C sort -u "$expected_tokens" >"$expected_sorted"
  LC_ALL=C sort -u "$observed_tokens" >"$observed_sorted"
  overlap="$(comm -12 "$expected_sorted" "$observed_sorted" | head -5 | join_terms_csv)"
  observed_preview="$(head -10 "$observed_sorted" | join_terms_csv)"
  if [[ -s "$expected_sorted" && -s "$observed_sorted" && -z "$overlap" ]]; then
    ONLYMACS_JSON_BATCH_TOPIC_STATUS="failed"
    ONLYMACS_JSON_BATCH_TOPIC_MESSAGE="batch set topic mismatch: set $(printf '%02d' "$set_index") should cover ${expected_topic}, but observed item topics/terms looked unrelated (${observed_preview})"
  fi
  rm -f "$expected_tokens" "$observed_tokens" "$expected_sorted" "$observed_sorted"
}

orchestrated_alias_is_wide() {
  local requested="${1:-}"
  local lowered
  lowered="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    wide|go-wide|go_wide)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

orchestrated_go_wide_enabled() {
  local requested="${1:-}"
  if [[ "${ONLYMACS_GO_WIDE_MODE:-0}" == "1" ]]; then
    return 0
  fi
  orchestrated_alias_is_wide "$requested"
}

orchestrated_go_wide_json_lanes() {
  local requested="${1:-}"
  local lanes="${ONLYMACS_GO_WIDE_JSON_LANES:-}"
  if [[ "$lanes" =~ ^[0-9]+$ && "$lanes" -gt 0 ]]; then
    normalize_go_wide_lane_count "$lanes" 2
    return 0
  fi
  if orchestrated_go_wide_enabled "$requested"; then
    printf '2'
  else
    printf '1'
  fi
}

orchestrated_go_wide_shadow_review_mode() {
  local requested="${1:-}"
  local mode="${ONLYMACS_GO_WIDE_SHADOW_REVIEW_MODE:-}"
  case "$mode" in
    off|sync|async)
      printf '%s' "$mode"
      return 0
      ;;
  esac
  if orchestrated_go_wide_enabled "$requested"; then
    printf 'async'
  else
    printf 'sync'
  fi
}

orchestrated_go_wide_batch_completed_count() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-step-01}"
  [[ -f "$plan_path" ]] || {
    printf '0'
    return 0
  }
  jq -r --arg step_id "$step_id" '
    [
      .steps[]? | select(.id == $step_id) | .batching.batches[]?
      | select((.status // "") as $s | ["completed","reused","recovered","completed_from_partial"] | index($s))
    ] | length
  ' "$plan_path" 2>/dev/null || printf '0'
}

orchestrated_claim_go_wide_batch_tickets() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-step-01}"
  local limit="${3:-1}"
  local now now_epoch stale_after lease_id claimed claimed_json batch_group_size batch_size items_per_set plan_file_path
  [[ -f "$plan_path" && "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || return 0
  limit="$(normalize_go_wide_lane_count "$limit" 1)"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now_epoch="$(date +%s)"
  stale_after="${ONLYMACS_GO_WIDE_TICKET_STALE_SECONDS:-180}"
  [[ "$stale_after" =~ ^[0-9]+$ && "$stale_after" -gt 0 ]] || stale_after=180
  lease_id="ticket-${$}-${now_epoch}"
  batch_group_size="$(jq -r --arg step_id "$step_id" '.steps[]? | select(.id == $step_id) | .batching.ticket_board.batch_group_size // empty' "$plan_path" 2>/dev/null | tail -1)"
  if [[ ! "$batch_group_size" =~ ^[0-9]+$ || "$batch_group_size" -le 0 ]]; then
    batch_size="$(jq -r --arg step_id "$step_id" '.steps[]? | select(.id == $step_id) | .batching.batch_size // empty' "$plan_path" 2>/dev/null | tail -1)"
    plan_file_path="$(jq -r '.plan_file_path // empty' "$plan_path" 2>/dev/null | tail -1)"
    items_per_set=""
    if [[ -n "$plan_file_path" && -f "$plan_file_path" ]]; then
      items_per_set="$(prompt_items_per_set_requirement "$(cat "$plan_file_path")" || true)"
    fi
    if [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 && "$batch_size" =~ ^[0-9]+$ && "$batch_size" -gt 0 ]]; then
      batch_group_size=$(((items_per_set + batch_size - 1) / batch_size))
    else
      batch_group_size=1
    fi
  fi
  [[ "$batch_group_size" =~ ^[0-9]+$ && "$batch_group_size" -gt 0 ]] || batch_group_size=1

  orchestrated_acquire_plan_lock "$plan_path"
  claimed="$(jq -r \
    --arg step_id "$step_id" \
    --argjson limit "$limit" \
    --argjson now_epoch "$now_epoch" \
    --argjson stale_after "$stale_after" \
    --argjson batch_group_size "$batch_group_size" \
    '
      def terminal:
        (.status // "") as $s
        | ["completed","reused","recovered","completed_from_partial"] | index($s);
      def stale:
        ((.updated_at // "" | fromdateiso8601? // 0) + $stale_after) < $now_epoch;
      def cooled:
        ((.retry_after_epoch // 0 | tonumber? // 0) <= $now_epoch);
      def active:
        (.status // "") as $s
        | ["leased","started","running","repairing","waiting_for_transport"] | index($s);
      def ticket_group:
        if $batch_group_size > 1 then (((.index - 1) / $batch_group_size) | floor) else (.index // 0) end;
      (.steps[]? | select(.id == $step_id) | .batching.batches // []) as $batches
      | ($batches | map(select(active and (stale | not)) | ticket_group)) as $active_groups
      | [
        $batches[]?
        | select((terminal | not) and cooled and (
            ((.status // "pending") | IN("pending","queued","waiting_for_transport"))
            or ((.status // "") == "retry_queued")
            or ((.status // "") == "partial")
            or ((.status // "") == "repair_queued")
            or (((.status // "") | IN("leased","started","running","repairing","failed")) and stale)
          ))
        | ticket_group as $ticket_group
        | {
            index,
            fresh_ticket: ((.status // "pending") | IN("pending","queued","waiting_for_transport")),
            priority: (
              if ((.status // "pending") | IN("pending","queued","waiting_for_transport")) then
                0
              elif ((.status // "") | IN("retry_queued","partial")) then 1
              elif ((.status // "") == "repair_queued") then 2
              else 4 end
            ),
            ticket_group: $ticket_group
          }
	      ]
	      | sort_by(.priority, .index)
	      | reduce .[] as $ticket (
	          {claimed: [], groups: $active_groups};
	          if (.claimed | length) >= $limit then
	            .
	          elif ($batch_group_size > 1 and (.groups | index($ticket.ticket_group))) then
	            .
	          else
	            {
	              claimed: (.claimed + [$ticket.index]),
	              groups: (.groups + [$ticket.ticket_group])
	            }
	          end
	        )
	      | .claimed[]
	    ' "$plan_path" 2>/dev/null || true)"
  if [[ -n "$claimed" ]]; then
    claimed_json="$(printf '%s\n' "$claimed" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')"
    jq \
      --arg step_id "$step_id" \
      --arg updated_at "$now" \
      --arg lease_id "$lease_id" \
      --argjson claimed "$claimed_json" \
      '
        .steps = (.steps | map(if .id == $step_id then
          . + {
            batching: ((.batching // {}) + {
              ticket_board: ((.batching.ticket_board // {}) + {
                enabled: true,
                last_lease_id: $lease_id,
                updated_at: $updated_at
              }),
              batches: ((.batching.batches // []) | map(
                if (.index as $i | $claimed | index($i)) then
                  . + {
                    status: "leased",
                    ticket_kind: (
                      if ((.status // "") == "repair_queued") then
                        "repair"
                      elif ((.status // "") == "retry_queued") and ((.ticket_kind // "") == "repair") then
                        "repair"
                      else
                        "generate"
                      end
                    ),
                    retry_after_epoch: null,
                    lease_id: $lease_id,
                    leased_at: (.leased_at // $updated_at),
                    updated_at: $updated_at,
                    message: ("Go-wide ticket board leased batch " + (.index | tostring) + " for a worker.")
                  }
                else . end
              ))
            })
          }
        else . end))
        | .updated_at = $updated_at
      ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  fi
  orchestrated_release_plan_lock "$plan_path"
  [[ -n "$claimed" ]] && printf '%s\n' "$claimed"
}

orchestrated_requeue_go_wide_parked_tickets() {
  local plan_path="${1:-$(orchestrated_plan_path)}"
  local step_id="${2:-step-01}"
  local limit="${3:-1}"
  local completed="${4:-0}"
  local target="${5:-0}"
  local now max_requeues cooldown_seconds now_epoch retry_after_epoch requeued requeued_json
  [[ -f "$plan_path" && "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || return 1
  limit="$(normalize_go_wide_lane_count "$limit" 1)"
  max_requeues="${ONLYMACS_GO_WIDE_PARKED_REQUEUE_LIMIT:-}"
  if [[ -z "$max_requeues" ]]; then
    case "$(printf '%s' "${ONLYMACS_SOURCE_CARD_QUALITY_MODE:-strict}" | tr '[:upper:]' '[:lower:]')" in
      throughput) max_requeues=3 ;;
      *) max_requeues=1 ;;
    esac
  fi
  [[ "$max_requeues" =~ ^[0-9]+$ && "$max_requeues" -gt 0 ]] || return 1
  cooldown_seconds="${ONLYMACS_GO_WIDE_PARKED_REQUEUE_SECONDS:-15}"
  [[ "$cooldown_seconds" =~ ^[0-9]+$ && "$cooldown_seconds" -ge 0 ]] || cooldown_seconds=15
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now_epoch="$(date +%s)"
  retry_after_epoch=0
  if [[ "$cooldown_seconds" -gt 0 ]]; then
    retry_after_epoch=$((now_epoch + cooldown_seconds))
  fi

  orchestrated_acquire_plan_lock "$plan_path"
  requeued="$(jq -r \
    --arg step_id "$step_id" \
    --argjson limit "$limit" \
    --argjson max_requeues "$max_requeues" \
    '
      def terminal:
        (.status // "") as $s
        | ["completed","reused","recovered","completed_from_partial"] | index($s);
      def parked:
        (.status // "") as $s
        | ["churn","needs_local_salvage","failed_validation"] | index($s);
      (.steps[]? | select(.id == $step_id) | .batching.batches // []) as $batches
      | [
          $batches[]?
          | select((terminal | not) and parked)
          | select(((.go_wide_requeue_count // 0) | tonumber? // 0) < $max_requeues)
          | .index
        ][0:$limit][]
    ' "$plan_path" 2>/dev/null || true)"
  if [[ -n "$requeued" ]]; then
    requeued_json="$(printf '%s\n' "$requeued" | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')"
    jq \
      --arg step_id "$step_id" \
      --arg updated_at "$now" \
      --argjson retry_after_epoch "$retry_after_epoch" \
      --argjson completed "$completed" \
      --argjson target "$target" \
      --argjson requeued "$requeued_json" \
      '
        .steps = (.steps | map(if .id == $step_id then
          . + {
            batching: ((.batching // {}) + {
              ticket_board: ((.batching.ticket_board // {}) + {
                enabled: true,
                updated_at: $updated_at,
                parked_requeue_updated_at: $updated_at,
                parked_requeue_completed: $completed,
                parked_requeue_target: $target
              }),
              batches: ((.batching.batches // []) | map(
                if (.index as $i | $requeued | index($i)) then
                  . + {
                    status: "repair_queued",
                    ticket_kind: "repair",
                    retry_after_epoch: (if $retry_after_epoch > 0 then $retry_after_epoch else null end),
                    go_wide_requeue_count: (((.go_wide_requeue_count // 0) | tonumber? // 0) + 1),
                    deferred_validation_message: (.message // .deferred_validation_message // "parked go-wide ticket requeued"),
                    deferred_at: $updated_at,
                    updated_at: $updated_at,
                    message: ("Requeued parked go-wide repair ticket after the board ran out of claimable work at " + ($completed | tostring) + "/" + ($target | tostring) + ".")
                  }
                else . end
              ))
            })
          }
        else . end))
        | .updated_at = $updated_at
      ' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
  fi
  orchestrated_release_plan_lock "$plan_path"
  [[ -n "$requeued" ]] && printf '%s\n' "$requeued"
}

orchestrated_prune_go_wide_workers() {
  local step_id="${1:-step-01}"
  local new_pids=() new_batches=() new_provider_ids=() new_models=() new_started_epochs=()
  local idx pid batch provider_id model started_epoch now_epoch duration exit_code failed=0 stat
  for idx in "${!ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}"; do
    pid="${ONLYMACS_GO_WIDE_ACTIVE_PIDS[$idx]}"
    batch="${ONLYMACS_GO_WIDE_ACTIVE_BATCHES[$idx]}"
    provider_id=""
    model=""
    if declare -p ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS >/dev/null 2>&1; then
      provider_id="${ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS[$idx]:-}"
    fi
    if declare -p ONLYMACS_GO_WIDE_ACTIVE_MODELS >/dev/null 2>&1; then
      model="${ONLYMACS_GO_WIDE_ACTIVE_MODELS[$idx]:-}"
    fi
    started_epoch=""
    if declare -p ONLYMACS_GO_WIDE_ACTIVE_STARTED_EPOCHS >/dev/null 2>&1; then
      started_epoch="${ONLYMACS_GO_WIDE_ACTIVE_STARTED_EPOCHS[$idx]:-}"
    fi
    if kill -0 "$pid" 2>/dev/null; then
      stat="$(ps -p "$pid" -o stat= 2>/dev/null | tr -d ' ' || true)"
      if [[ -n "$stat" && "$stat" != *Z* ]]; then
        new_pids+=("$pid")
        new_batches+=("$batch")
        new_provider_ids+=("$provider_id")
        new_models+=("$model")
        new_started_epochs+=("$started_epoch")
        continue
      fi
    fi
    now_epoch="$(date +%s)"
    if [[ "$started_epoch" =~ ^[0-9]+$ && "$started_epoch" -gt 0 && "$now_epoch" -ge "$started_epoch" ]]; then
      duration=$((now_epoch - started_epoch))
    else
      duration=0
    fi
    if wait "$pid" 2>/dev/null; then
      orchestrated_record_go_wide_lane_metric "$(orchestrated_plan_path)" "$step_id" "$provider_id" "$model" "$duration" "success"
      onlymacs_log_run_event "go_wide_ticket_completed" "$step_id" "running" "0" "Go-wide ticket worker finished batch ${batch} in ${duration}s." "" "$provider_id" "This Mac" "$model" "" "$(orchestrated_plan_path)"
    else
      exit_code=$?
      failed=$((failed + 1))
      orchestrated_record_go_wide_lane_metric "$(orchestrated_plan_path)" "$step_id" "$provider_id" "$model" "$duration" "failure"
      onlymacs_log_run_event "go_wide_ticket_failed" "$step_id" "running" "0" "Go-wide ticket worker for batch ${batch} exited with status ${exit_code} after ${duration}s." "" "$provider_id" "This Mac" "$model" "" "$(orchestrated_plan_path)"
    fi
  done
  ONLYMACS_GO_WIDE_ACTIVE_PIDS=()
  ONLYMACS_GO_WIDE_ACTIVE_BATCHES=()
  ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS=()
  ONLYMACS_GO_WIDE_ACTIVE_MODELS=()
  ONLYMACS_GO_WIDE_ACTIVE_STARTED_EPOCHS=()
  if [[ "${#new_pids[@]}" -gt 0 ]]; then
    ONLYMACS_GO_WIDE_ACTIVE_PIDS=("${new_pids[@]}")
    ONLYMACS_GO_WIDE_ACTIVE_BATCHES=("${new_batches[@]}")
    ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS=("${new_provider_ids[@]}")
    ONLYMACS_GO_WIDE_ACTIVE_MODELS=("${new_models[@]}")
    ONLYMACS_GO_WIDE_ACTIVE_STARTED_EPOCHS=("${new_started_epochs[@]}")
  fi
  return "$failed"
}

orchestrated_execute_go_wide_ticket_board() {
  local run_dir="${1:-${ONLYMACS_CURRENT_RETURN_DIR:-}}"
  local model="${2:-}"
  local model_alias="${3:-wide}"
  local route_scope="${4:-swarm}"
  local prompt="${5:-}"
  local step_index="${6:-1}"
  local step_count="${7:-1}"
  local plan_path step_id batch_count completed target lanes slots worker_dir ticket pid active_failed
  local step_filename route_assignments=() route_assignment route_idx route_claim_limit
  local route_provider_candidate route_total_slots route_active_count route_selected_count route_provider_id selected_provider_id active_provider
  local worker_provider_id worker_model worker_provider_name worker_provider_is_local worker_provider_total_slots
  local route_ticket_kind ticket_kind ticket_specific_model ticket_lease_id claimed_any cooling_count claimable_after_failure last_wait_log_epoch wait_log_interval now_epoch parked_requeued
  local poll_seconds finalizer_lock_path finalizer_rc root_artifact
  [[ -n "$run_dir" && -d "$run_dir" ]] || return 2
  [[ -z "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" ]] || return 2
  [[ "${ONLYMACS_GO_WIDE_TICKET_BOARD_DISABLED:-0}" != "1" ]] || return 2
  orchestrated_go_wide_enabled "$model_alias" || return 2
  plan_path="${run_dir}/plan.json"
  step_id="$(orchestrated_step_id "$step_index")"
  [[ -f "$plan_path" ]] || return 2
  batch_count="$(jq -r --arg step_id "$step_id" '.steps[]? | select(.id == $step_id) | .batching.batch_count // empty' "$plan_path" 2>/dev/null | tail -1)"
  [[ "$batch_count" =~ ^[0-9]+$ && "$batch_count" -gt 1 ]] || return 2
  step_filename="$(jq -r --arg step_id "$step_id" '.steps[]? | select(.id == $step_id) | .batching.filename // .expected_outputs[0] // .target_paths[0] // empty' "$plan_path" 2>/dev/null | tail -1)"

  lanes="$(orchestrated_go_wide_json_lanes "$model_alias")"
  [[ "$lanes" =~ ^[0-9]+$ && "$lanes" -gt 0 ]] || lanes=2
  target="${ONLYMACS_GO_WIDE_TARGET_COMPLETED:-$batch_count}"
  [[ "$target" =~ ^[0-9]+$ && "$target" -gt 0 ]] || target="$batch_count"
  [[ "$target" -gt "$batch_count" ]] && target="$batch_count"
  worker_dir="${run_dir}/.go-wide-workers"
  mkdir -p "$worker_dir" || return 1
  ONLYMACS_GO_WIDE_ACTIVE_PIDS=()
  ONLYMACS_GO_WIDE_ACTIVE_BATCHES=()
  ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS=()
  ONLYMACS_GO_WIDE_ACTIVE_MODELS=()
  ONLYMACS_GO_WIDE_ACTIVE_STARTED_EPOCHS=()
  last_wait_log_epoch=0
  wait_log_interval="${ONLYMACS_GO_WIDE_IDLE_LOG_SECONDS:-30}"
  [[ "$wait_log_interval" =~ ^[0-9]+$ && "$wait_log_interval" -gt 0 ]] || wait_log_interval=30
  onlymacs_log_run_event "go_wide_ticket_board_started" "$step_id" "running" "0" "Go-wide ticket board started with ${lanes} worker lane(s), target ${target}/${batch_count} completed batches." "" "" "This Mac" "" "" "$plan_path"

  while :; do
    completed="$(orchestrated_go_wide_batch_completed_count "$plan_path" "$step_id")"
    if [[ "$completed" =~ ^[0-9]+$ && "$completed" -ge "$target" ]]; then
      orchestrated_prune_go_wide_workers "$step_id" || true
      if [[ "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}" -eq 0 ]]; then
        onlymacs_log_run_event "go_wide_ticket_board_target_reached" "$step_id" "running" "0" "Go-wide ticket board reached ${completed}/${batch_count} completed batches." "" "" "This Mac" "" "" "$plan_path"
        if [[ "$completed" -lt "$batch_count" ]]; then
          return 3
        fi
        finalizer_lock_path="${plan_path}.finalizer"
        orchestrated_acquire_plan_lock "$finalizer_lock_path"
        root_artifact="${run_dir}/files/${step_filename}"
        if jq -e --arg step_id "$step_id" '.steps[]? | select(.id == $step_id and .status == "completed")' "$plan_path" >/dev/null 2>&1 && [[ -s "$root_artifact" ]]; then
          orchestrated_release_plan_lock "$finalizer_lock_path"
          return 0
        fi
        orchestrated_mark_go_wide_finalizer "$plan_path" "$step_id" "started"
        finalizer_rc=0
        ONLYMACS_GO_WIDE_TICKET_BOARD_DISABLED=1 ONLYMACS_GO_WIDE_ASSEMBLE_ONLY=1 orchestrated_execute_step "$model" "$model_alias" "$route_scope" "$prompt" "$step_index" "$step_count" || finalizer_rc=$?
        if [[ "$finalizer_rc" -eq 0 ]]; then
          orchestrated_mark_go_wide_finalizer "$plan_path" "$step_id" "completed"
        else
          orchestrated_mark_go_wide_finalizer "$plan_path" "$step_id" "failed"
        fi
        orchestrated_release_plan_lock "$finalizer_lock_path"
        return "$finalizer_rc"
	      fi
	    fi

    active_failed=0
    orchestrated_prune_go_wide_workers "$step_id" || active_failed=$?
    slots=$((lanes - ${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}))
    if [[ "$slots" -gt 0 ]]; then
      route_assignments=()
      route_ticket_kind="$(jq -r --arg step_id "$step_id" '
        def terminal:
          (.status // "") as $s
          | ["completed","reused","recovered","completed_from_partial"] | index($s);
        [
          .steps[]? | select(.id == $step_id) | .batching.batches[]?
          | select((terminal | not) and (((.retry_after_epoch // 0 | tonumber? // 0) <= now) and (
              ((.status // "pending") | IN("pending","queued","waiting_for_transport"))
              or ((.status // "") == "retry_queued")
              or ((.status // "") == "partial")
              or ((.status // "") == "repair_queued")
              or ((.status // "") == "failed")
            )))
          | {
              index,
              priority: (
                if ((.status // "pending") | IN("pending","queued","waiting_for_transport")) then 0
                elif ((.status // "") | IN("retry_queued","partial")) then 1
                elif ((.status // "") == "repair_queued") then 2
                else 4 end
              ),
              kind: (
                if ((.status // "") == "repair_queued") then
                  "repair"
                elif ((.status // "") == "retry_queued") and ((.ticket_kind // "") == "repair") then
                  "repair"
                else
                  "generate"
                end
              )
            }
        ]
        | sort_by(.priority, .index)
        | .[0].kind // "generate"
      ' "$plan_path" 2>/dev/null | tail -1)"
      [[ -n "$route_ticket_kind" ]] || route_ticket_kind="generate"
      while IFS= read -r route_assignment; do
        [[ -n "$route_assignment" ]] || continue
        IFS=$'\t' read -r route_provider_candidate _ _ _ route_total_slots <<<"$route_assignment"
        [[ -n "$route_provider_candidate" ]] || continue
        [[ "$route_total_slots" =~ ^[0-9]+$ && "$route_total_slots" -gt 0 ]] || route_total_slots=1
        route_active_count=0
        if [[ "${#ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS[@]}" -gt 0 ]]; then
          for active_provider in "${ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS[@]}"; do
            [[ "$active_provider" == "$route_provider_candidate" ]] && route_active_count=$((route_active_count + 1))
          done
        fi
        route_selected_count=0
        if [[ "${#route_assignments[@]}" -gt 0 ]]; then
          for route_provider_id in "${route_assignments[@]}"; do
            IFS=$'\t' read -r selected_provider_id _ <<<"$route_provider_id"
            [[ "$selected_provider_id" == "$route_provider_candidate" ]] && route_selected_count=$((route_selected_count + 1))
          done
        fi
        if [[ $((route_active_count + route_selected_count)) -lt "$route_total_slots" ]]; then
          route_assignments+=("$route_assignment")
        fi
      done < <(orchestrated_pick_go_wide_worker_routes "$model_alias" "$route_scope" "$prompt" "$step_filename" "$slots" "$route_ticket_kind" 2>/dev/null || true)
      if [[ "${ONLYMACS_GO_WIDE_MODEL_SWARM_FALLBACK:-1}" == "1" && "${#route_assignments[@]}" -lt "$slots" ]]; then
        while IFS= read -r route_assignment; do
          [[ -n "$route_assignment" ]] || continue
          IFS=$'\t' read -r route_provider_candidate worker_model _ _ route_total_slots <<<"$route_assignment"
          [[ -n "$route_provider_candidate" ]] || continue
          [[ "$route_total_slots" =~ ^[0-9]+$ && "$route_total_slots" -gt 0 ]] || route_total_slots=1
          route_active_count=0
          if [[ "$route_provider_candidate" == __swarm_model_* ]]; then
            if [[ "${#ONLYMACS_GO_WIDE_ACTIVE_MODELS[@]}" -gt 0 ]]; then
              for active_provider in "${ONLYMACS_GO_WIDE_ACTIVE_MODELS[@]}"; do
                [[ -n "$worker_model" && "$active_provider" == "$worker_model" ]] && route_active_count=$((route_active_count + 1))
              done
            fi
          elif [[ "${#ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS[@]}" -gt 0 ]]; then
            for active_provider in "${ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS[@]}"; do
              [[ "$active_provider" == "$route_provider_candidate" ]] && route_active_count=$((route_active_count + 1))
            done
          fi
          route_selected_count=0
          if [[ "${#route_assignments[@]}" -gt 0 ]]; then
            for route_provider_id in "${route_assignments[@]}"; do
              IFS=$'\t' read -r selected_provider_id selected_provider_model _ <<<"$route_provider_id"
              if [[ "$route_provider_candidate" == __swarm_model_* ]]; then
                [[ -n "$worker_model" && "$selected_provider_model" == "$worker_model" ]] && route_selected_count=$((route_selected_count + 1))
              else
                [[ "$selected_provider_id" == "$route_provider_candidate" ]] && route_selected_count=$((route_selected_count + 1))
              fi
            done
          fi
          if [[ $((route_active_count + route_selected_count)) -lt "$route_total_slots" ]]; then
            route_assignments+=("$route_assignment")
          fi
          [[ "${#route_assignments[@]}" -ge "$slots" ]] && break
        done < <(orchestrated_pick_go_wide_model_swarm_routes "$model_alias" "$route_scope" "$prompt" "$step_filename" "$((slots - ${#route_assignments[@]}))" "$route_ticket_kind" 2>/dev/null || true)
      fi
      route_claim_limit="$slots"
      if [[ "${#route_assignments[@]}" -gt 0 && "${#route_assignments[@]}" -lt "$route_claim_limit" ]]; then
        route_claim_limit="${#route_assignments[@]}"
      elif [[ "${#route_assignments[@]}" -eq 0 ]]; then
        route_claim_limit=0
      fi
      if [[ "$route_claim_limit" -le 0 ]]; then
        now_epoch="$(date +%s)"
        if [[ "$last_wait_log_epoch" -eq 0 || $((now_epoch - last_wait_log_epoch)) -ge "$wait_log_interval" ]]; then
          onlymacs_log_run_event "go_wide_waiting_for_workers" "$step_id" "running" "0" "Go-wide has ${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}/${lanes} active lane(s) and is waiting for eligible free provider slots before claiming more tickets." "" "" "This Mac" "" "" "$plan_path"
          last_wait_log_epoch="$now_epoch"
        fi
        poll_seconds="${ONLYMACS_GO_WIDE_TICKET_POLL_SECONDS:-5}"
        [[ "$poll_seconds" =~ ^[0-9]+$ && "$poll_seconds" -gt 0 ]] || poll_seconds=5
        orchestrated_record_go_wide_idle_metric "$plan_path" "$step_id" "provider_capacity_wait" "$poll_seconds" "$lanes" "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}"
        sleep "$poll_seconds"
        continue
      fi
      route_idx=0
      claimed_any=0
      while IFS= read -r ticket; do
        [[ "$ticket" =~ ^[0-9]+$ ]] || continue
        claimed_any=1
        worker_provider_id=""
        worker_model=""
        worker_provider_name=""
        worker_provider_is_local=""
        worker_provider_total_slots=""
        ticket_kind="$(jq -r --arg step_id "$step_id" --argjson index "$ticket" '.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $index) | .ticket_kind // "generate"' "$plan_path" 2>/dev/null | tail -1)"
        ticket_lease_id="$(jq -r --arg step_id "$step_id" --argjson index "$ticket" '.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $index) | .lease_id // empty' "$plan_path" 2>/dev/null | tail -1)"
        [[ -n "$ticket_kind" ]] || ticket_kind="generate"
        if [[ "${#route_assignments[@]}" -gt 0 ]]; then
          route_assignment="${route_assignments[$route_idx]}"
          IFS=$'\t' read -r worker_provider_id worker_model worker_provider_name worker_provider_is_local worker_provider_total_slots <<<"$route_assignment"
          route_idx=$((route_idx + 1))
        fi
        if [[ -n "$worker_provider_id" && "$worker_provider_id" != __swarm_model_* ]]; then
          ticket_specific_model="$(orchestrated_pick_go_wide_provider_model "$worker_provider_id" "$prompt" "$step_filename" "$ticket_kind" 2>/dev/null || true)"
          if [[ -n "$ticket_specific_model" ]]; then
            worker_model="$ticket_specific_model"
          fi
        fi
        (
          export ONLYMACS_GO_WIDE_MODE=1
          export ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX="$ticket"
          export ONLYMACS_GO_WIDE_WORKER_LEASE_ID="$ticket_lease_id"
          export ONLYMACS_GO_WIDE_JOB_BOARD_WORKER=1
          export ONLYMACS_DISABLE_GO_WIDE_LOCAL_SHADOW=1
          if [[ -n "$worker_provider_id" && "$worker_provider_id" != __swarm_model_* ]]; then
            export ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID="$worker_provider_id"
          fi
          if [[ -n "$worker_model" ]]; then
            export ONLYMACS_GO_WIDE_WORKER_MODEL="$worker_model"
          fi
          if [[ "$worker_provider_is_local" == "1" ]]; then
            export ONLYMACS_GO_WIDE_WORKER_PROVIDER_IS_LOCAL=1
          fi
          bash "$0" resume-run "$run_dir"
        ) >"${worker_dir}/batch-$(printf '%03d' "$ticket").log" 2>&1 &
        pid="$!"
        ONLYMACS_GO_WIDE_ACTIVE_PIDS+=("$pid")
        ONLYMACS_GO_WIDE_ACTIVE_BATCHES+=("$ticket")
        ONLYMACS_GO_WIDE_ACTIVE_PROVIDER_IDS+=("$worker_provider_id")
        ONLYMACS_GO_WIDE_ACTIVE_MODELS+=("$worker_model")
        ONLYMACS_GO_WIDE_ACTIVE_STARTED_EPOCHS+=("$(date +%s)")
        if [[ -n "$worker_provider_id" || -n "$worker_model" ]]; then
          onlymacs_log_run_event "go_wide_ticket_started" "$step_id" "running" "0" "Go-wide ticket worker ${pid} started ${ticket_kind} batch ${ticket}/${batch_count} on ${worker_provider_name:-$worker_provider_id} with ${worker_model:-auto}." "" "$worker_provider_id" "${worker_provider_name:-This Mac}" "$worker_model" "${worker_dir}/batch-$(printf '%03d' "$ticket").log" "$plan_path"
        else
          onlymacs_log_run_event "go_wide_ticket_started" "$step_id" "running" "0" "Go-wide ticket worker ${pid} started ${ticket_kind} batch ${ticket}/${batch_count}." "" "" "This Mac" "" "${worker_dir}/batch-$(printf '%03d' "$ticket").log" "$plan_path"
        fi
      done < <(orchestrated_claim_go_wide_batch_tickets "$plan_path" "$step_id" "$route_claim_limit")
      if [[ "$claimed_any" -eq 0 && "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}" -eq 0 ]]; then
        completed="$(orchestrated_go_wide_batch_completed_count "$plan_path" "$step_id")"
        if [[ "$completed" -lt "$target" ]]; then
          cooling_count="$(jq -r --arg step_id "$step_id" '
            def terminal:
              (.status // "") as $s
              | ["completed","reused","recovered","completed_from_partial"] | index($s);
            [
              .steps[]? | select(.id == $step_id) | .batching.batches[]?
              | select((terminal | not) and ((.retry_after_epoch // 0 | tonumber? // 0) > now))
            ] | length
          ' "$plan_path" 2>/dev/null || printf '0')"
	          if [[ "$cooling_count" =~ ^[0-9]+$ && "$cooling_count" -gt 0 ]]; then
	            onlymacs_log_run_event "go_wide_waiting_for_ticket_cooldown" "$step_id" "running" "0" "Go-wide has ${cooling_count} ticket(s) cooling down after transient transport misses; waiting for the next retry window instead of starting local salvage." "" "" "This Mac" "" "" "$plan_path"
	            poll_seconds="${ONLYMACS_GO_WIDE_TICKET_POLL_SECONDS:-5}"
	            [[ "$poll_seconds" =~ ^[0-9]+$ && "$poll_seconds" -gt 0 ]] || poll_seconds=5
	            orchestrated_record_go_wide_idle_metric "$plan_path" "$step_id" "ticket_cooldown_wait" "$poll_seconds" "$lanes" "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}"
	            sleep "$poll_seconds"
	            continue
	          fi
	          parked_requeued="$(orchestrated_requeue_go_wide_parked_tickets "$plan_path" "$step_id" "$route_claim_limit" "$completed" "$target" | paste -sd, -)"
	          if [[ -n "$parked_requeued" ]]; then
	            onlymacs_log_run_event "go_wide_parked_tickets_requeued" "$step_id" "running" "0" "Go-wide requeued parked repair ticket(s) ${parked_requeued} because the board was below target at ${completed}/${target}." "" "" "This Mac" "" "" "$plan_path"
	            poll_seconds="${ONLYMACS_GO_WIDE_TICKET_POLL_SECONDS:-5}"
	            [[ "$poll_seconds" =~ ^[0-9]+$ && "$poll_seconds" -gt 0 ]] || poll_seconds=5
	            orchestrated_record_go_wide_idle_metric "$plan_path" "$step_id" "parked_requeue_wait" "$poll_seconds" "$lanes" "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}"
	            sleep "$poll_seconds"
	            continue
	          fi
	          onlymacs_log_run_event "go_wide_ticket_board_exhausted" "$step_id" "needs_local_salvage" "0" "Go-wide has no claimable tickets left at ${completed}/${target}; remaining batches need local salvage or manual requeue." "" "" "This Mac" "" "" "$plan_path"
	          return 4
	        fi
      fi
    fi

    if [[ "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}" -eq 0 ]]; then
      completed="$(orchestrated_go_wide_batch_completed_count "$plan_path" "$step_id")"
      if [[ "$completed" -lt "$target" && "$active_failed" -gt 0 ]]; then
        claimable_after_failure="$(jq -r --arg step_id "$step_id" '
          def terminal:
            (.status // "") as $s
            | ["completed","reused","recovered","completed_from_partial"] | index($s);
          [
            .steps[]? | select(.id == $step_id) | .batching.batches[]?
            | select((terminal | not) and (((.retry_after_epoch // 0 | tonumber? // 0) <= now) and (
                ((.status // "pending") | IN("pending","queued","waiting_for_transport"))
                or ((.status // "") == "retry_queued")
                or ((.status // "") == "partial")
                or ((.status // "") == "repair_queued")
                or ((.status // "") == "failed")
              )))
          ] | length
        ' "$plan_path" 2>/dev/null || printf '0')"
        if [[ "$claimable_after_failure" =~ ^[0-9]+$ && "$claimable_after_failure" -gt 0 ]]; then
          onlymacs_log_run_event "go_wide_worker_failure_isolated" "$step_id" "running" "0" "Go-wide isolated ${active_failed} failed worker(s) and will keep claiming ${claimable_after_failure} remaining ticket(s)." "" "" "This Mac" "" "" "$plan_path"
          poll_seconds="${ONLYMACS_GO_WIDE_TICKET_POLL_SECONDS:-5}"
          [[ "$poll_seconds" =~ ^[0-9]+$ && "$poll_seconds" -gt 0 ]] || poll_seconds=5
          orchestrated_record_go_wide_idle_metric "$plan_path" "$step_id" "worker_failure_reclaim_wait" "$poll_seconds" "$lanes" "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}"
          sleep "$poll_seconds"
          continue
        fi
        return 1
      fi
    fi
    poll_seconds="${ONLYMACS_GO_WIDE_TICKET_POLL_SECONDS:-5}"
    [[ "$poll_seconds" =~ ^[0-9]+$ && "$poll_seconds" -gt 0 ]] || poll_seconds=5
    orchestrated_record_go_wide_idle_metric "$plan_path" "$step_id" "poll_wait" "$poll_seconds" "$lanes" "${#ONLYMACS_GO_WIDE_ACTIVE_PIDS[@]}"
    sleep "$poll_seconds"
  done
}

orchestrated_go_wide_shadow_review_pid_path() {
  local step_dir="${1:-}"
  [[ -n "$step_dir" ]] || return 1
  printf '%s/.local-shadow-review.pids' "$step_dir"
}

orchestrated_wait_for_go_wide_shadow_reviews() {
  local step_dir="${1:-}"
  local step_id="${2:-step-01}"
  local artifact_path="${3:-}"
  local raw_path="${4:-}"
  local pid_path pid failed_count=0 waited_count=0
  pid_path="$(orchestrated_go_wide_shadow_review_pid_path "$step_dir")" || return 0
  [[ -f "$pid_path" ]] || return 0
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    waited_count=$((waited_count + 1))
    if ! wait "$pid" 2>/dev/null; then
      failed_count=$((failed_count + 1))
    fi
  done <"$pid_path"
  rm -f "$pid_path"
  if [[ "$waited_count" -gt 0 ]]; then
    if [[ "$failed_count" -gt 0 ]]; then
      onlymacs_log_run_event "go_wide_shadow_reviews_completed" "$step_id" "running" "0" "OnlyMacs waited for ${waited_count} async local shadow review(s); ${failed_count} reported non-zero status." "$artifact_path" "" "This Mac" "" "$raw_path" "$(orchestrated_plan_path)"
    else
      onlymacs_log_run_event "go_wide_shadow_reviews_completed" "$step_id" "running" "0" "OnlyMacs waited for ${waited_count} async local shadow review(s) before final assembly." "$artifact_path" "" "This Mac" "" "$raw_path" "$(orchestrated_plan_path)"
    fi
  fi
  return 0
}

orchestrated_compile_local_shadow_json_batch_review_prompt() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local filename="${4:-items.json}"
  local batch_index="${5:-1}"
  local batch_count="${6:-1}"
  local batch_start="${7:-1}"
  local batch_end="${8:-1}"
  local batch_items="${9:-1}"
  local batch_filename="${10:-batch.json}"
  local artifact_path="${11:-}"
  local validation_prompt="${12:-}"
  local artifact_content range_hint review_filename

  review_filename="${batch_filename%.json}.local-review.json"
  range_hint="$(orchestrated_json_batch_range_hint "$validation_prompt" "$batch_start" "$batch_end")"
  artifact_content=""
  if [[ -f "$artifact_path" ]]; then
    artifact_content="$(cat "$artifact_path")"
  fi

  cat <<EOF
You are the local OnlyMacs requester-side reviewer for a go-wide long job.

This is not a rewrite request. Review the accepted remote artifact and return a compact strict JSON review report only.

Original user request:
$original_prompt

Current step:
Step ${step_index} of ${step_count}

Remote artifact:
- filename: ${batch_filename}
- expected top-level items: ${batch_items}
- expected item numbers: ${batch_start}-${batch_end}
${range_hint}

Validation context:
${validation_prompt:-None provided.}

Accepted artifact content:
${artifact_content}

Return JSON with exactly these keys:
- status: "pass", "warning", or "fail"
- batch: "${batch_index}/${batch_count}"
- reviewedFile: "${batch_filename}"
- expectedCount: ${batch_items}
- observedCount
- rangeWarnings: array of strings
- duplicateWarnings: array of strings
- schemaWarnings: array of strings
- qualityWarnings: array of strings
- recommendedAction: one short string

Review-specific checks:
- For source-card verb items, flag future/past/imperative-looking lemma values such as ahorraré, cocinarás, llamá, or leé when the base infinitive belongs in lemma and the taught form belongs in display.
- Flag grammarNote, dialectNote, or usage notes that are written as Spanish instructions instead of learner-facing English guidance.
- Flag usage notes that mention study/review/drills/tags or wrap a different conjugation than the exact taught display.

Do not include markdown or prose outside the artifact markers. Use this exact object shape, but replace values with actual review findings from the artifact; do not blindly copy the placeholder values.

ONLYMACS_ARTIFACT_BEGIN filename=${review_filename}
{"status":"pass","batch":"${batch_index}/${batch_count}","reviewedFile":"${batch_filename}","expectedCount":${batch_items},"observedCount":${batch_items},"rangeWarnings":[],"duplicateWarnings":[],"schemaWarnings":[],"qualityWarnings":[],"recommendedAction":"continue"}
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_pick_local_shadow_review_model() {
  local review_filename="${1:-local-review.json}"
  local step_id="${2:-step-01}"
  local batch_index="${3:-1}"
  local batch_count="${4:-1}"
  local artifact_path="${5:-}"
  local review_raw_path="${6:-}"
  local wait_limit wait_interval waited wait_logged local_model

  wait_limit="${ONLYMACS_GO_WIDE_LOCAL_REVIEW_MODEL_WAIT_SECONDS:-600}"
  wait_interval="${ONLYMACS_GO_WIDE_LOCAL_REVIEW_MODEL_WAIT_INTERVAL_SECONDS:-5}"
  [[ "$wait_limit" =~ ^[0-9]+$ ]] || wait_limit=600
  [[ "$wait_interval" =~ ^[0-9]+$ && "$wait_interval" -gt 0 ]] || wait_interval=5
  waited=0
  wait_logged=0
  local_model=""
  while [[ -z "$local_model" ]]; do
    local_model="$(orchestrated_model_for_step "" "local-first" "local_only" "Validate the accepted JSON artifact, duplicate risks, range contract, and quality warnings." "$review_filename" || true)"
    [[ -n "$local_model" ]] && break
    if [[ "$waited" -ge "$wait_limit" ]]; then
      break
    fi
    if [[ "$wait_logged" -eq 0 ]]; then
      wait_logged=1
      onlymacs_log_run_event "local_shadow_review_waiting" "$step_id" "running" "0" "Waiting for a local go-wide review slot for batch ${batch_index}/${batch_count}; generation can continue while this review is backlogged." "$artifact_path" "" "This Mac" "" "$review_raw_path" "$(orchestrated_plan_path)"
    fi
    sleep "$wait_interval"
    waited=$((waited + wait_interval))
  done
  ONLYMACS_LOCAL_SHADOW_REVIEW_MODEL_WAITED_SECONDS="$waited"
  [[ -n "$local_model" ]] || return 1
  printf '%s' "$local_model"
}

orchestrated_execute_local_shadow_json_batch_review_now() {
  local default_alias="${1:-}"
  local original_prompt="${2:-}"
  local step_index="${3:-1}"
  local step_count="${4:-1}"
  local filename="${5:-items.json}"
  local batch_index="${6:-1}"
  local batch_count="${7:-1}"
  local batch_start="${8:-1}"
  local batch_end="${9:-1}"
  local batch_items="${10:-1}"
  local batch_filename="${11:-batch.json}"
  local batch_dir="${12:-}"
  local artifact_path="${13:-}"
  local validation_prompt="${14:-}"
  local step_route_scope="${15:-swarm}"
  local step_id review_dir review_filename review_raw_path review_artifact_path review_body_path
  local local_model review_prompt max_tokens payload content_path headers_path provider_id provider_name owner_member_name model_header

  [[ "${ONLYMACS_DISABLE_GO_WIDE_LOCAL_SHADOW:-0}" != "1" ]] || return 0
  orchestrated_go_wide_enabled "$default_alias" || return 0
  [[ "$step_route_scope" != "local_only" ]] || return 0
  [[ -f "$artifact_path" ]] || return 0

  step_id="$(orchestrated_step_id "$step_index")"
  review_dir="${batch_dir}/local-review"
  review_filename="${batch_filename%.json}.local-review.json"
  review_raw_path="${review_dir}/RESULT.md"
  review_artifact_path="${review_dir}/${review_filename}"
  mkdir -p "$review_dir" || return 0

  local_model="$(orchestrated_pick_local_shadow_review_model "$review_filename" "$step_id" "$batch_index" "$batch_count" "$artifact_path" "$review_raw_path" || true)"
  if [[ -z "$local_model" ]]; then
    onlymacs_log_run_event "local_shadow_review_skipped" "$step_id" "running" "0" "No local model became available for go-wide shadow review after ${ONLYMACS_LOCAL_SHADOW_REVIEW_MODEL_WAITED_SECONDS:-0}s." "$artifact_path" "" "This Mac" "" "$review_raw_path" "$(orchestrated_plan_path)"
    return 0
  fi

  review_prompt="$(orchestrated_compile_local_shadow_json_batch_review_prompt "$original_prompt" "$step_index" "$step_count" "$filename" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$artifact_path" "$validation_prompt")"
  max_tokens="$(orchestrated_max_tokens_for_step "$review_prompt" "$review_filename")"
  content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-local-shadow-content-XXXXXX")"
  headers_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-local-shadow-headers-XXXXXX")"
  orchestrated_set_chat_route_env "$max_tokens" "local_only" "$local_model"
  payload="$(build_chat_payload "$local_model" "$review_prompt" "local_only" "local-first")"
  if ! orchestrated_stream_payload_with_capacity_wait "$payload" "$content_path" "$headers_path" "$step_id" "0" "$review_artifact_path" "$review_raw_path"; then
    orchestrated_clear_chat_route_env
    if [[ -s "$content_path" ]]; then
      cp "$content_path" "$review_raw_path"
    fi
    onlymacs_log_run_event "local_shadow_review_failed" "$step_id" "running" "0" "${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-local shadow review failed}" "$artifact_path" "" "This Mac" "$local_model" "$review_raw_path" "$(orchestrated_plan_path)"
    rm -f "$content_path" "$headers_path"
    return 0
  fi
  orchestrated_clear_chat_route_env

  provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
  provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
  owner_member_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
  model_header="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
  cp "$content_path" "$review_raw_path"
  review_body_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-local-shadow-body-XXXXXX")"
  if ! extract_marked_artifact_block "$content_path" "$review_body_path" && ! extract_single_fenced_code_block "$content_path" "$review_body_path"; then
    cp "$content_path" "$review_body_path"
  fi
  cp "$review_body_path" "$review_artifact_path"
  repair_json_artifact_if_possible "$review_artifact_path" "Return one strict JSON object."
  rm -f "$review_body_path" "$content_path" "$headers_path"
  onlymacs_log_run_event "local_shadow_review_completed" "$step_id" "running" "0" "Local go-wide shadow review saved for batch ${batch_index}/${batch_count}." "$review_artifact_path" "$provider_id" "${owner_member_name:-${provider_name:-This Mac}}" "${model_header:-$local_model}" "$review_raw_path" "$(orchestrated_plan_path)"
  return 0
}

orchestrated_execute_local_shadow_json_batch_review() {
  local default_alias="${1:-}"
  local batch_dir="${12:-}"
  local artifact_path="${13:-}"
  local step_route_scope="${15:-swarm}"
  local mode step_dir pid_path pid step_id

  [[ "${ONLYMACS_DISABLE_GO_WIDE_LOCAL_SHADOW:-0}" != "1" ]] || return 0
  orchestrated_go_wide_enabled "$default_alias" || return 0
  [[ "$step_route_scope" != "local_only" ]] || return 0
  [[ -f "$artifact_path" ]] || return 0

  mode="$(orchestrated_go_wide_shadow_review_mode "$default_alias")"
  [[ "$mode" != "off" ]] || return 0
  if [[ "$mode" == "async" ]]; then
    step_dir="$(dirname "$(dirname "$batch_dir")")"
    pid_path="$(orchestrated_go_wide_shadow_review_pid_path "$step_dir")" || return 0
    mkdir -p "$step_dir" || return 0
    (
      orchestrated_execute_local_shadow_json_batch_review_now "$@"
    ) &
    pid="$!"
    printf '%s\n' "$pid" >>"$pid_path"
    step_id="$(orchestrated_step_id "${3:-1}")"
    onlymacs_log_run_event "local_shadow_review_queued" "$step_id" "running" "0" "Queued async local go-wide shadow review for batch ${6:-1}/${7:-1}; generation can continue on the next batch." "$artifact_path" "" "This Mac" "" "" "$(orchestrated_plan_path)"
    return 0
  fi

  orchestrated_execute_local_shadow_json_batch_review_now "$@"
}

orchestrated_compile_plan_file_json_batch_compact_retry_prompt() {
  local validation_prompt="${1:-}"
  local filename="${2:-items.json}"
  local step_index="${3:-1}"
  local batch_index="${4:-1}"
  local batch_count="${5:-1}"
  local batch_start="${6:-1}"
  local batch_end="${7:-1}"
  local batch_items="${8:-1}"
  local batch_filename="${9:-batch.json}"
  local previous_terms="${10:-}"
  local validation_message="${11:-}"
  local current_step global_context range_hint enum_guidance diversity_guidance compact_context duplicate_guidance duplicate_ban_terms source_card_guidance source_card_seed_terms

  current_step="$(plan_file_step_text "$step_index")"
  if [[ -z "$current_step" ]]; then
    current_step="$validation_prompt"
  fi
  global_context="$(plan_file_global_context)"
  compact_context="${global_context}
${current_step}
${validation_prompt}"
  range_hint="$(orchestrated_json_batch_range_hint "$compact_context" "$batch_start" "$batch_end")"
  enum_guidance="$(orchestrated_json_batch_enum_guidance "$compact_context")"
  diversity_guidance="$(orchestrated_json_batch_diversity_guidance "$compact_context" "$filename" "$batch_start" "$batch_end" "$previous_terms")"
  duplicate_guidance=""
  source_card_guidance=""
  if [[ "$(printf '%s' "$validation_message" | tr '[:upper:]' '[:lower:]')" == *"duplicate item terms"* ]]; then
    duplicate_ban_terms="$(printf '%s' "$validation_message" | perl -ne '
      while (/display:([^,\n]+)/g) { print "$1\n"; }
      while (/lemma-display:([^|,\n]+)\|([^,\n]+)/g) { print "$1\n$2\n"; }
    ' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | LC_ALL=C sort -fu | join_terms_csv)"
    duplicate_guidance="- Duplicate hard ban: the duplicate terms named in the validation error are forbidden as lemma or display values in this replacement. Do not reuse them, even if they fit the topic; choose genuinely new terms and change the underlying concept, not only ids, examples, or notes.
${duplicate_ban_terms:+- Forbidden duplicate lemma/display strings for this retry: ${duplicate_ban_terms}
- Before closing the JSON, compare every lemma and display against that forbidden list. If any exact value matches, replace the entire card with a different concept.}"
  fi
  if orchestrated_json_step_is_source_card_content "$compact_context" "$filename"; then
    source_card_seed_terms="$(orchestrated_source_card_repair_seed_terms "$batch_start")"
    source_card_guidance="- Source-card hard schema: every object must include id, setId, teachingOrder, lemma, display, english, pos, stage, register, topic, topicTags, cityTags, grammarNote, dialectNote, example, example_en, and usage. Do not omit grammarNote or dialectNote.
- English learner-note guard: grammarNote, dialectNote, and usage must be learner-facing English guidance. Spanish belongs in lemma, display, example, and short quoted/targeted phrases only; do not write usage notes like \"Usá...\", \"Decí...\", \"Al narrar...\", or \"En conversaciones...\".
- Source-card lemma guard: for verb cards, lemma must be the infinitive/base form such as ahorrar, cocinar, llamar, llegar, or leer; put conjugated taught forms such as ahorraré, cocinarás, llamá, or leé in display only.
- Source-card target guard: at least one usage note must wrap the exact taught display text itself in <target>...</target>. For an infinitive display such as preferir, use <target>preferir</target>, not <target>preferís</target> or another conjugation."
    if [[ -n "$source_card_seed_terms" ]]; then
      source_card_guidance="${source_card_guidance}
- Suggested replacement surfaces for this range: ${source_card_seed_terms}. Treat these as a menu, not a checklist; use a suggestion or a similarly distinct concept only if it is absent from accepted exclusions and duplicate bans."
    fi
  fi

  cat <<EOF
OnlyMacs compact JSON retry.

The previous attempt failed validation:
${validation_message}

Return only the complete replacement artifact. Do not continue the broken output.

Essential contract:
- Filename: ${batch_filename}
- Internal micro-batch: ${batch_index}/${batch_count}
- Global item range: ${batch_start}-${batch_end}
- Return exactly ${batch_items} complete JSON object(s), inside one strict JSON array.
- Start with ONLYMACS_ARTIFACT_BEGIN on its own line and end with ONLYMACS_ARTIFACT_END on its own line.
- Do not emit prose, markdown fences, comments, hidden reasoning, progress text, trailing commas, or incomplete objects.
- Use compact one-line strings. Avoid embedded newlines and unnecessary quotation marks inside strings.
- Verify the JSON parses and has exactly ${batch_items} object(s) before closing the artifact.
${range_hint}
${enum_guidance}
${previous_terms:+- Earlier accepted terms. Accepted surface hard exclusions: ${previous_terms}
- Exact duplicate guard: never emit any accepted exclusion as lemma, display, term, word, phrase, text, or sentence. For source cards, changing ids, examples, notes, or casing is not enough; replace the whole concept before writing the JSON object.}
${diversity_guidance}
${duplicate_guidance}
${source_card_guidance}

Schema and validation context:
${validation_prompt}

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${batch_filename}
[
  <emit exactly ${batch_items} complete JSON objects here, comma-separated>
]
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_source_card_batch_starter_json() {
  return 0
}

orchestrated_compile_plan_file_json_batch_prompt() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local filename="${4:-items.json}"
  local batch_index="${5:-1}"
  local batch_count="${6:-1}"
  local batch_start="${7:-1}"
  local batch_end="${8:-1}"
  local batch_items="${9:-1}"
  local batch_filename="${10:-batch.json}"
  local previous_terms="${11:-}"
  local current_step step_title plan_name user_request global_context batch_context range_hint enum_guidance diversity_guidance starter_shell

  current_step="$(plan_file_step_text "$step_index")"
  if [[ -z "$current_step" ]]; then
    current_step="${ONLYMACS_PLAN_FILE_CONTENT:-$original_prompt}"
  fi
  step_title="$(plan_file_step_title "$step_index")"
  plan_name="$(basename "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-${ONLYMACS_PLAN_FILE_PATH:-plan.md}}")"
  user_request="${ONLYMACS_PLAN_USER_PROMPT:-}"
  if [[ -z "$user_request" ]]; then
    user_request="$original_prompt"
  fi
  global_context="$(plan_file_global_context)"
  batch_context="${global_context}
${current_step}
${ONLYMACS_PLAN_FILE_CONTENT:-}
${original_prompt}"
  range_hint="$(orchestrated_json_batch_range_hint "$batch_context" "$batch_start" "$batch_end")"
  enum_guidance="$(orchestrated_json_batch_enum_guidance "$batch_context")"
  diversity_guidance="$(orchestrated_json_batch_diversity_guidance "$batch_context" "$filename" "$batch_start" "$batch_end" "$previous_terms")"
  starter_shell="$(orchestrated_source_card_batch_starter_json "$batch_context" "$filename" "$batch_start" "$batch_end" "$batch_items" || true)"

  cat <<EOF
You are serving an OnlyMacs --extended plan-file JSON batch for an Ollama-only remote Mac.

User request:
$user_request

Plan file:
$plan_name

Plan-level constraints and schema expectations:
${global_context:-None provided.}

Current plan step:
Step ${step_index} of ${step_count}${step_title:+: ${step_title}}

Current step text:
$current_step

OnlyMacs batch contract:
- Generate only OnlyMacs internal micro-batch ${batch_index} of ${batch_count}.
- Generate item numbers ${batch_start}-${batch_end} for this step.
- Return exactly ${batch_items} complete item objects in this batch.
- Return one strict JSON array inside the artifact markers: an opening [, exactly ${batch_items} object elements separated by commas, then a closing ].
- OnlyMacs will normalize the accepted micro-batch into the final JSON array locally.
- Put the ONLYMACS_ARTIFACT_BEGIN header on its own line, then start the opening [ on the next line.
- Every object must have its own closing } before the comma or closing ]. Never let two top-level objects touch as "}{". That fails validation.
- Do not include comments, trailing commas, markdown, prose, or progress text inside the artifact.
- Prefer compact JSON with minimal whitespace and no blank lines to reduce stream length.
- Avoid embedded newlines in string values. Avoid unnecessary quotation marks inside string values so escaping stays simple.
- Finish planning the whole micro-batch before emitting the first artifact line; do not stream half-built objects.
- Do not emit hidden reasoning, chain-of-thought, analysis text, or a plan before the artifact. Start the response with ONLYMACS_ARTIFACT_BEGIN.
- Do not use placeholders, TODOs, ellipses, "add the remaining", or "omitted for brevity".
- Keep each object concise but complete for the current step's schema.
- For language-learning artifacts, use real high-frequency learner-safe terms. Do not invent regional slang or cute localisms; if uncertain, choose the standard common form and keep any dialect note conservative.
- If a schema asks for <target> tags, wrap the actual taught surface form, for example <target>Hola</target>. Do not emit the literal placeholder <target>, and do not mention tags or wrapping in learner-facing text.
- If the current step divides the total across groups or set IDs, assign item numbers to those groups in order. For example, with "20 items for A and 20 items for B", items 1-20 belong to A and items 21-40 belong to B.
${range_hint}
${starter_shell:+- Source-card starter shell: preserve the id, setId, teachingOrder, keys, and array shapes below; replace every empty string with final content before returning the artifact. Do not return this shell with blanks.
${starter_shell}
}
- If any field has an allowed set of values, use the exact allowed string only; never invent nearby enum values.
${enum_guidance}
- Use globally unique ids that include the batch/item number when practical.
- If the current step asks for unique terms or no duplicates, keep the generated terms unique within this batch and do not reuse earlier accepted terms.
${previous_terms:+- Earlier accepted terms. Accepted surface hard exclusions: ${previous_terms}
- Exact duplicate guard: never emit any accepted exclusion as lemma, display, term, word, phrase, text, or sentence. For source cards, changing ids, examples, notes, or casing is not enough; replace the whole concept before writing the JSON object.}
${diversity_guidance}
- If the current step says "at least N" for nested arrays, sections, quiz questions, content blocks, files, examples, or subitems, use exactly N unless it explicitly asks for more. Keep nested arrays concise.
- Verify the JSON array parses and contains exactly ${batch_items} objects before closing the artifact.

Final response format:
ONLYMACS_ARTIFACT_BEGIN filename=${batch_filename}
[
  <emit exactly ${batch_items} complete JSON objects here, comma-separated>
]
ONLYMACS_ARTIFACT_END
EOF
}

orchestrated_try_accept_partial_json_batch() {
  local content_path="${1:-}"
  local batch_artifact_path="${2:-}"
  local batch_raw_path="${3:-}"
  local batch_attempts_dir="${4:-}"
  local batch_filename="${5:-items.batch.json}"
  local batch_validation_prompt="${6:-}"
  local validation_prompt="${7:-}"
  local batches_dir="${8:-}"
  local batch_index="${9:-1}"
  local batch_count="${10:-1}"
  local batch_start="${11:-1}"
  local step_id="${12:-step-01}"
  local provider_id="${13:-}"
  local provider_name="${14:-}"
  local model_header="${15:-}"
  local partial_raw_path partial_body_path partial_artifact_path partial_normalized_path validation_status validation_message
  local accept_lock_path accept_lock_held=0

  [[ -s "$content_path" ]] || return 1
  mkdir -p "$batch_attempts_dir" "$(dirname "$batch_artifact_path")" || return 1
  partial_raw_path="${batch_attempts_dir}/partial-RESULT.md"
  partial_body_path="${batch_attempts_dir}/partial-${batch_filename}.body"
  partial_artifact_path="${batch_attempts_dir}/partial-${batch_filename}"
  partial_normalized_path="${batch_attempts_dir}/partial-${batch_filename%.json}.normalized.json"

  cp "$content_path" "$partial_raw_path"
  if ! extract_marked_artifact_block "$content_path" "$partial_body_path" && ! extract_single_fenced_code_block "$content_path" "$partial_body_path"; then
    cp "$content_path" "$partial_body_path"
  fi
  cp "$partial_body_path" "$partial_artifact_path"

  repair_json_artifact_if_possible "$partial_artifact_path" "$batch_validation_prompt"
  if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
    onlymacs_log_run_event "partial_json_repair_applied" "$step_id" "partial" "0" "${ONLYMACS_JSON_REPAIR_MESSAGE:-recovered strict JSON from partial stream}" "$partial_artifact_path" "$provider_id" "$provider_name" "$model_header" "$partial_raw_path" "$(orchestrated_plan_path)"
  fi
  if ! json_artifact_to_item_array "$partial_artifact_path" "$partial_normalized_path"; then
    onlymacs_log_run_event "partial_validation_failed" "$step_id" "partial" "0" "Partial stream did not contain a complete JSON array/object stream, so OnlyMacs will regenerate this micro-batch." "$partial_artifact_path" "$provider_id" "$provider_name" "$model_header" "$partial_raw_path" "$(orchestrated_plan_path)"
    return 1
  fi

  orchestrated_normalize_chunk_artifact "$partial_normalized_path" "$batch_validation_prompt"
  repair_rioplatense_tuteo_artifact_if_possible "$partial_normalized_path" "$batch_validation_prompt"
  repair_source_card_schema_aliases_if_possible "$partial_normalized_path" "$batch_validation_prompt"
  repair_source_card_usage_artifact_if_possible "$partial_normalized_path" "$batch_validation_prompt"
  if [[ -n "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" || "${ONLYMACS_GO_WIDE_PARALLEL_ACCEPT_ALL:-0}" == "1" ]]; then
    accept_lock_path="$(orchestrated_plan_path).accept"
    orchestrated_acquire_plan_lock "$accept_lock_path"
    accept_lock_held=1
  fi
  validate_return_artifact "$partial_normalized_path" "$batch_validation_prompt"
  validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-failed}"
  validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-partial batch validation failed}"
  if [[ "$validation_status" != "failed" ]] && prompt_requires_unique_item_terms "$validation_prompt"; then
    orchestrated_validate_json_batch_uniqueness "$partial_normalized_path" "$batches_dir" "$batch_index"
    if [[ "${ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS:-passed}" == "failed" ]]; then
      validation_status="failed"
      validation_message="${ONLYMACS_JSON_BATCH_UNIQUENESS_MESSAGE:-duplicate item terms found across JSON batches}"
    fi
  fi
  if [[ "$validation_status" != "failed" ]]; then
    orchestrated_validate_json_batch_item_range "$partial_normalized_path" "$validation_prompt" "$batch_start"
    if [[ "${ONLYMACS_JSON_BATCH_RANGE_STATUS:-passed}" == "failed" ]]; then
      validation_status="failed"
      validation_message="${ONLYMACS_JSON_BATCH_RANGE_MESSAGE:-batch item/set range did not match expected global item numbers}"
    fi
  fi
  if [[ "$validation_status" != "failed" ]]; then
    orchestrated_validate_json_batch_set_topic "$partial_normalized_path" "$validation_prompt" "$batch_start"
    if [[ "${ONLYMACS_JSON_BATCH_TOPIC_STATUS:-passed}" == "failed" ]]; then
      validation_status="failed"
      validation_message="${ONLYMACS_JSON_BATCH_TOPIC_MESSAGE:-batch topics did not match the plan set map}"
    fi
  fi
  if [[ "$validation_status" == "failed" ]]; then
    if [[ "$accept_lock_held" -eq 1 ]]; then
      orchestrated_release_plan_lock "$accept_lock_path"
      accept_lock_held=0
    fi
    onlymacs_log_run_event "partial_validation_failed" "$step_id" "partial" "0" "Partial stream failed validation before regeneration: ${validation_message}" "$partial_normalized_path" "$provider_id" "$provider_name" "$model_header" "$partial_raw_path" "$(orchestrated_plan_path)"
    return 1
  fi

  if ! orchestrated_promote_json_batch_artifact "$partial_normalized_path" "$batch_artifact_path" "$step_id" "$batch_index" "completed_from_partial"; then
    if [[ "$accept_lock_held" -eq 1 ]]; then
      orchestrated_release_plan_lock "$accept_lock_path"
      accept_lock_held=0
    fi
    [[ -n "${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" ]] && return 0
    return 1
  fi
  cp "$partial_raw_path" "$batch_raw_path"
  orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "completed_from_partial" "$batch_artifact_path" "$provider_id" "$provider_name" "$model_header" "Accepted complete validated artifact content recovered from a partial transport failure."
  if [[ "$accept_lock_held" -eq 1 ]]; then
    orchestrated_release_plan_lock "$accept_lock_path"
    accept_lock_held=0
  fi
  onlymacs_log_run_event "partial_artifact_accepted" "$step_id" "completed" "0" "Accepted complete validated artifact content recovered from a partial transport failure." "$batch_artifact_path" "$provider_id" "$provider_name" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
  return 0
}

orchestrated_execute_plan_json_batch_step() {
  local model="${1:-}"
  local model_alias="${2:-}"
  local route_scope="${3:-swarm}"
  local original_prompt="${4:-}"
  local step_index="${5:-1}"
  local step_count="${6:-1}"
  local filename="${7:-items.json}"
  local validation_prompt="${8:-}"
  local step_id step_dir files_dir batches_dir attempts_dir artifact_path raw_path root_artifact
  local expected_count batch_size batch_count batch_index batch_start batch_end batch_items batch_filename
  local batch_dir batch_files_dir batch_attempts_dir batch_artifact_path batch_raw_path body_path content_path headers_path payload step_prompt base_step_prompt step_prompt_bytes
  local batch_status_label batch_status_message
  local attempt repair_limit validation_status validation_message provider_id provider_name owner_member_name model_header max_tokens failure_class failed_provider_id
  local attempt_artifact_path attempt_raw_path normalized_path batch_validation_prompt previous_terms final_duplicate_terms
  local resume_normalized_path
  local step_model_alias step_model step_route_scope picked_step_model
  local json_extraction_failure_count
  local reused_batch_count=0 reused_batch_summary_emitted=0
  local worker_batch_index="${ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX:-}" worker_mode=0
  local go_wide_ticket_kind go_wide_deferred_validation_message
  local accept_lock_path accept_lock_held=0
  local recovered_content_path recovery_status
  local batch_paths=()

  step_id="$(orchestrated_step_id "$step_index")"
  step_dir="${ONLYMACS_CURRENT_RETURN_DIR}/steps/${step_id}"
  files_dir="${step_dir}/files"
  batches_dir="${step_dir}/batches"
  attempts_dir="${step_dir}/attempts"
  artifact_path="${files_dir}/${filename}"
  raw_path="${step_dir}/RESULT.md"
  mkdir -p "$files_dir" "$batches_dir" "$attempts_dir" "${ONLYMACS_CURRENT_RETURN_DIR}/files" || return 1

  step_model_alias="$(orchestrated_route_alias_for_step "$model_alias" "$step_index" "$filename")"
  step_model="$(orchestrated_model_for_step "$(normalize_model_alias "$step_model_alias")" "$step_model_alias" "$(route_scope_for_alias "$step_model_alias")" "$validation_prompt" "$filename")"
  step_route_scope="$(route_scope_for_alias "$step_model_alias")"

  expected_count="$(prompt_exact_count_requirement "$validation_prompt" || true)"
  batch_size="$(orchestrated_stored_json_batch_size "$step_id" "$filename" 2>/dev/null || orchestrated_json_batch_size_for_step "$validation_prompt" "$filename")"
  if [[ ! "$expected_count" =~ ^[0-9]+$ || "$expected_count" -le 0 ]]; then
    return 1
  fi
  batch_count=$(((expected_count + batch_size - 1) / batch_size))
  orchestrated_record_json_batch_policy "$step_id" "$filename" "$expected_count" "$batch_size" "$batch_count" "$validation_prompt"
  if [[ "$worker_batch_index" =~ ^[0-9]+$ && "$worker_batch_index" -gt 0 ]]; then
    worker_mode=1
    ONLYMACS_GO_WIDE_WORKER_COMPLETED=0
  fi
  repair_limit="$(orchestrated_repair_limit)"
  provider_id=""
  provider_name=""
  owner_member_name=""
  model_header=""

  for ((batch_index = 1; batch_index <= batch_count; batch_index++)); do
    batch_start=$((((batch_index - 1) * batch_size) + 1))
    batch_end=$((batch_start + batch_size - 1))
    if [[ "$batch_end" -gt "$expected_count" ]]; then
      batch_end="$expected_count"
    fi
    batch_items=$((batch_end - batch_start + 1))
    batch_filename="$(orchestrated_plan_json_batch_filename "$filename" "$batch_index")"
    batch_dir="${batches_dir}/batch-$(printf '%02d' "$batch_index")"
    batch_files_dir="${batch_dir}/files"
    batch_attempts_dir="${batch_dir}/attempts"
    batch_artifact_path="${batch_files_dir}/${batch_filename}"
    batch_raw_path="${batch_dir}/RESULT.md"
    mkdir -p "$batch_files_dir" "$batch_attempts_dir" || return 1

    if [[ "$worker_mode" -eq 1 && "$batch_index" -ne "$worker_batch_index" ]]; then
      continue
    fi
    ONLYMACS_CURRENT_BATCH_INPUT_TOKENS_ESTIMATE=""

    batch_validation_prompt="${validation_prompt}

Batch validation override:
Return exactly ${batch_items} entries/items as JSON Lines or a JSON array."
    if prompt_requires_unique_item_terms "$validation_prompt"; then
      batch_validation_prompt="${batch_validation_prompt} Keep every item term unique with no duplicates."
    fi
    go_wide_ticket_kind="generate"
    go_wide_deferred_validation_message=""
    if [[ "$worker_mode" -eq 1 ]]; then
      go_wide_ticket_kind="$(jq -r --arg step_id "$step_id" --argjson index "$batch_index" '.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $index) | .ticket_kind // "generate"' "$(orchestrated_plan_path)" 2>/dev/null | tail -1)"
      [[ -n "$go_wide_ticket_kind" ]] || go_wide_ticket_kind="generate"
      go_wide_deferred_validation_message="$(jq -r --arg step_id "$step_id" --argjson index "$batch_index" '.steps[]? | select(.id == $step_id) | .batching.batches[]? | select(.index == $index) | .deferred_validation_message // empty' "$(orchestrated_plan_path)" 2>/dev/null | tail -1)"
    fi
    if [[ -s "$batch_artifact_path" ]]; then
      resume_normalized_path="${batch_attempts_dir}/resume-${batch_filename%.json}.normalized.json"
      if json_artifact_to_item_array "$batch_artifact_path" "$resume_normalized_path"; then
        orchestrated_normalize_chunk_artifact "$resume_normalized_path" "$batch_validation_prompt"
        repair_rioplatense_tuteo_artifact_if_possible "$resume_normalized_path" "$batch_validation_prompt"
        if [[ "${ONLYMACS_DIALECT_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
          onlymacs_log_run_event "dialect_repair_applied" "$step_id" "resuming" "0" "${ONLYMACS_DIALECT_REPAIR_MESSAGE:-normalized dialect forms before validation}" "$resume_normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        fi
        repair_source_card_schema_aliases_if_possible "$resume_normalized_path" "$batch_validation_prompt"
        if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
          onlymacs_log_run_event "source_card_schema_repair_applied" "$step_id" "resuming" "0" "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_MESSAGE:-normalized source-card schema aliases before validation}" "$resume_normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        fi
        repair_source_card_usage_artifact_if_possible "$resume_normalized_path" "$batch_validation_prompt"
        if [[ "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
          onlymacs_log_run_event "source_card_usage_repair_applied" "$step_id" "resuming" "0" "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_MESSAGE:-removed source-card usage meta language before validation}" "$resume_normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        fi
        validate_return_artifact "$resume_normalized_path" "$batch_validation_prompt"
        validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-failed}"
        validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-existing batch validation failed}"
        if [[ "$validation_status" != "failed" ]] && prompt_requires_unique_item_terms "$validation_prompt"; then
          orchestrated_validate_json_batch_uniqueness "$resume_normalized_path" "$batches_dir" "$batch_index"
          if [[ "${ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS:-passed}" == "failed" ]]; then
            validation_status="failed"
            validation_message="${ONLYMACS_JSON_BATCH_UNIQUENESS_MESSAGE:-duplicate item terms found across JSON batches}"
          fi
        fi
        if [[ "$validation_status" != "failed" ]]; then
          orchestrated_validate_json_batch_item_range "$resume_normalized_path" "$validation_prompt" "$batch_start"
          if [[ "${ONLYMACS_JSON_BATCH_RANGE_STATUS:-passed}" == "failed" ]]; then
            validation_status="failed"
            validation_message="${ONLYMACS_JSON_BATCH_RANGE_MESSAGE:-batch item/set range did not match expected global item numbers}"
          fi
        fi
	        if [[ "$validation_status" != "failed" ]]; then
	          orchestrated_validate_json_batch_set_topic "$resume_normalized_path" "$validation_prompt" "$batch_start"
	          if [[ "${ONLYMACS_JSON_BATCH_TOPIC_STATUS:-passed}" == "failed" ]]; then
	            validation_status="failed"
	            validation_message="${ONLYMACS_JSON_BATCH_TOPIC_MESSAGE:-batch topics did not match the plan set map}"
	          fi
	        fi
	        if [[ "$validation_status" == "failed" && "${ONLYMACS_GO_WIDE_ASSEMBLE_ONLY:-0}" == "1" ]]; then
	          orchestrated_promote_json_batch_artifact "$resume_normalized_path" "$batch_artifact_path" "$step_id" "$batch_index" "reused" || true
	          batch_paths+=("$batch_artifact_path")
	          reused_batch_count=$((reused_batch_count + 1))
	          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "reused" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "Assembled accepted go-wide batch ${batch_index}/${batch_count} without reopening remote generation: ${validation_message}"
	          onlymacs_log_run_event "go_wide_assemble_only_batch_reused" "$step_id" "resuming" "0" "Assembled accepted go-wide batch ${batch_index}/${batch_count} without reopening remote generation: ${validation_message}" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
	          if [[ "$worker_mode" -eq 1 ]]; then
	            ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
	            return 0
	          fi
	          continue
	        fi
	        if [[ "$validation_status" != "failed" ]]; then
	          orchestrated_promote_json_batch_artifact "$resume_normalized_path" "$batch_artifact_path" "$step_id" "$batch_index" "reused" || true
	          batch_paths+=("$batch_artifact_path")
	          reused_batch_count=$((reused_batch_count + 1))
	          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "reused" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "Reused validated batch ${batch_index}/${batch_count}."
          onlymacs_log_run_event "batch_reused" "$step_id" "resuming" "0" "reused validated batch ${batch_index}/${batch_count}" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
          if [[ "$worker_mode" -eq 1 ]]; then
            ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
            return 0
          fi
          continue
        fi
      else
        validation_status="failed"
        validation_message="existing batch artifact could not be normalized; regenerating batch ${batch_index}/${batch_count}"
      fi
    fi

    if [[ "$reused_batch_count" -gt 0 && "$reused_batch_summary_emitted" -eq 0 ]]; then
      reused_batch_summary_emitted=1
      orchestrated_update_plan_step "$step_id" "resuming" "0" "$artifact_path" "$raw_path" "passed" "Reused ${reused_batch_count} accepted batch$(chat_plural_suffix "$reused_batch_count"); continuing at batch ${batch_index}/${batch_count}." "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "running"
      onlymacs_log_run_event "batch_reuse_summary" "$step_id" "resuming" "0" "Reused ${reused_batch_count} accepted batch$(chat_plural_suffix "$reused_batch_count"); continuing at batch ${batch_index}/${batch_count}." "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
      if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf '\nOnlyMacs reused %s accepted batch%s and is continuing at batch %s/%s.\n' "$reused_batch_count" "$(chat_plural_suffix "$reused_batch_count")" "$batch_index" "$batch_count" >&2
      fi
    fi

    transient_transport_retry_count=0
    transient_transport_retry_limit="${ONLYMACS_TRANSIENT_TRANSPORT_RETRY_LIMIT:-2}"
    transient_transport_backoff_seconds="${ONLYMACS_TRANSIENT_TRANSPORT_BACKOFF_SECONDS:-20}"
    [[ "$transient_transport_retry_limit" =~ ^[0-9]+$ ]] || transient_transport_retry_limit=2
    [[ "$transient_transport_backoff_seconds" =~ ^[0-9]+$ ]] || transient_transport_backoff_seconds=20
    base_step_prompt=""
    json_extraction_failure_count=0
    attempt=0
    validation_status="pending"
    validation_message=""
    if [[ "$worker_mode" -eq 1 && "$go_wide_ticket_kind" == "repair" && -s "$batch_artifact_path" ]]; then
      attempt=1
      validation_status="failed"
      validation_message="${go_wide_deferred_validation_message:-source-card batch did not validate on its first pass}"
      previous_terms=""
      if prompt_requires_unique_item_terms "$validation_prompt"; then
        previous_terms="$(orchestrated_previous_json_batch_terms_for_prompt "$batches_dir" "$batch_index" "$batch_start" "$validation_prompt")"
      fi
      base_step_prompt="$(orchestrated_compile_plan_file_json_batch_prompt "$original_prompt" "$step_index" "$step_count" "$filename" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$previous_terms")"
      onlymacs_log_run_event "go_wide_repair_ticket_started" "$step_id" "repairing" "$attempt" "Go-wide worker is repairing queued batch ${batch_index}/${batch_count}: ${validation_message}" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
    fi
    if [[ "$worker_mode" -eq 1 ]] && ! orchestrated_go_wide_worker_lease_matches "$step_id" "$batch_index"; then
      orchestrated_log_stale_go_wide_worker_ignored "$step_id" "$batch_index" "worker stopped before starting because the ticket lease was superseded"
      ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
      return 0
    fi
    orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "started" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "Starting batch ${batch_index}/${batch_count}."
    onlymacs_log_run_event "batch_started" "$step_id" "running" "0" "Starting batch ${batch_index}/${batch_count}." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
    while [[ "$attempt" -le "$repair_limit" ]]; do
      if [[ "$attempt" -eq 0 ]]; then
        previous_terms=""
        if prompt_requires_unique_item_terms "$validation_prompt"; then
          previous_terms="$(orchestrated_previous_json_batch_terms_for_prompt "$batches_dir" "$batch_index" "$batch_start" "$validation_prompt")"
        fi
        base_step_prompt="$(orchestrated_compile_plan_file_json_batch_prompt "$original_prompt" "$step_index" "$step_count" "$filename" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$previous_terms")"
        step_prompt="$base_step_prompt"
      elif [[ "$json_extraction_failure_count" -ge 2 && "$validation_message" == *"batch artifact was not a JSON array"* ]]; then
        step_prompt="$(orchestrated_compile_plan_file_json_batch_compact_retry_prompt "$batch_validation_prompt" "$filename" "$step_index" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$previous_terms" "$validation_message")"
        onlymacs_log_run_event "compact_json_retry_prompt" "$step_id" "repairing" "$attempt" "Using compact JSON retry prompt after repeated malformed or truncated artifacts for batch ${batch_index}/${batch_count}." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
      elif [[ "$validation_message" == *"duplicate item terms"* ]]; then
        step_prompt="$(orchestrated_compile_plan_file_json_batch_compact_retry_prompt "$batch_validation_prompt" "$filename" "$step_index" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$previous_terms" "$validation_message")"
        onlymacs_log_run_event "compact_duplicate_retry_prompt" "$step_id" "repairing" "$attempt" "Using compact JSON retry prompt after duplicate terms for batch ${batch_index}/${batch_count}." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
      elif [[ "$validation_message" == *"learner-facing English"* || "$validation_message" == *"Spanish sentences outside the taught"* ]]; then
        step_prompt="$(orchestrated_compile_plan_file_json_batch_compact_retry_prompt "$batch_validation_prompt" "$filename" "$step_index" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$previous_terms" "$validation_message")"
        onlymacs_log_run_event "compact_usage_retry_prompt" "$step_id" "repairing" "$attempt" "Using compact JSON retry prompt after source-card usage notes were not learner-facing English for batch ${batch_index}/${batch_count}." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
      else
        step_prompt="$(orchestrated_compile_repair_prompt "${base_step_prompt:-$step_prompt}" "$batch_filename" "$validation_message" "$batch_artifact_path")"
        if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
          printf '\nOnlyMacs is repairing %s batch %02d/%02d after validation failed: %s\n' "$step_id" "$batch_index" "$batch_count" "$validation_message" >&2
        fi
      fi
      step_prompt_bytes="$(printf '%s' "$step_prompt" | wc -c | tr -d ' ')"
      [[ "$step_prompt_bytes" =~ ^[0-9]+$ ]] || step_prompt_bytes=0
      ONLYMACS_CURRENT_BATCH_INPUT_TOKENS_ESTIMATE="$(chat_estimated_tokens "$step_prompt_bytes")"

      if [[ "$attempt" -gt 0 ]]; then
        batch_status_label="repairing"
        batch_status_message="Repairing batch ${batch_index}/${batch_count}: ${validation_message}"
      else
        batch_status_label="running"
        batch_status_message="Running batch ${batch_index}/${batch_count}."
      fi
      orchestrated_update_plan_step "$step_id" "running" "$attempt" "$artifact_path" "$raw_path" "$validation_status" "batch ${batch_index}/${batch_count}: ${validation_message}" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "running"
      orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "$batch_status_label" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_status_message"
      content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-content-XXXXXX")"
      headers_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-headers-XXXXXX")"
      picked_step_model="$(orchestrated_model_for_step "$(normalize_model_alias "$step_model_alias")" "$step_model_alias" "$step_route_scope" "$step_prompt" "$batch_filename")"
      if [[ -n "$picked_step_model" ]]; then
        step_model="$picked_step_model"
      fi
      max_tokens="$(orchestrated_max_tokens_for_step "Return exactly ${batch_items} entries/items as JSON." "$batch_filename")"
      orchestrated_set_chat_route_env "$max_tokens" "$step_route_scope" "$step_model"
      payload="$(build_chat_payload "$step_model" "$step_prompt" "$step_route_scope" "$step_model_alias")"
      if ! orchestrated_stream_payload_with_capacity_wait "$payload" "$content_path" "$headers_path" "$step_id" "$attempt" "$artifact_path" "$raw_path"; then
        if orchestrated_recover_stream_content_from_activity "$content_path" "$headers_path" "$step_id" "$attempt" "$batch_artifact_path" "$batch_raw_path"; then
          :
        else
        validation_status="failed"
        validation_message="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed for batch ${batch_index}/${batch_count}}"
        failed_provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
        [[ -z "$failed_provider_id" ]] && failed_provider_id="${ONLYMACS_LAST_CHAT_PROVIDER_ID:-}"
        [[ -z "$failed_provider_id" ]] && failed_provider_id="${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}"
        failed_provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
        [[ -z "$failed_provider_name" ]] && failed_provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
        [[ -z "$failed_provider_name" ]] && failed_provider_name="${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-${ONLYMACS_LAST_CHAT_PROVIDER_NAME:-}}"
        failed_model_header="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
        [[ -z "$failed_model_header" ]] && failed_model_header="${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-$model_header}"
        if [[ "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}" == "detached_activity_running" ]]; then
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="queued"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="$validation_message"
          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "queued" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$validation_message"
          orchestrated_update_plan_step "$step_id" "queued" "$attempt" "$artifact_path" "$raw_path" "pending" "$validation_message" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "queued"
          orchestrated_clear_chat_route_env
          rm -f "$content_path" "$headers_path"
          return 1
        fi
        if [[ "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}" == "locked_provider_unavailable" ]]; then
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="queued"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="$validation_message"
          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "queued" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$validation_message"
          orchestrated_update_plan_step "$step_id" "queued" "$attempt" "$artifact_path" "$raw_path" "pending" "$validation_message" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "queued"
          onlymacs_log_run_event "pinned_provider_unavailable" "$step_id" "queued" "$attempt" "$validation_message" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
          orchestrated_clear_chat_route_env
          rm -f "$content_path" "$headers_path"
          return 1
        fi
        failure_class="$(onlymacs_log_failure_classification "$step_id" "$attempt" "$validation_message" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path")"
        if [[ -s "$content_path" ]]; then
          if orchestrated_try_accept_partial_json_batch "$content_path" "$batch_artifact_path" "$batch_raw_path" "$batch_attempts_dir" "$batch_filename" "$batch_validation_prompt" "$validation_prompt" "$batches_dir" "$batch_index" "$batch_count" "$batch_start" "$step_id" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header"; then
            batch_paths+=("$batch_artifact_path")
            onlymacs_update_provider_health "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "success" "" "0"
            orchestrated_clear_chat_route_env
            rm -f "$content_path" "$headers_path"
            if [[ "$worker_mode" -eq 1 ]]; then
              ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
              return 0
            fi
            break
          fi
        fi
        if [[ "$worker_mode" -eq 1 && "$attempt" -eq 0 && ! -s "$content_path" ]]; then
          case "$failure_class" in
            first_token_timeout|idle_timeout|wall_clock_timeout|transport_drop|provider_unavailable|provider_maintenance)
              onlymacs_update_provider_health "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "failure" "$failure_class" "0"
              orchestrated_mark_go_wide_retry_ticket "$step_id" "$batch_index" "$validation_message" "$batch_artifact_path" "$batch_raw_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "0" "$go_wide_ticket_kind"
              onlymacs_log_run_event "go_wide_retry_ticket_queued" "$step_id" "retry_queued" "$attempt" "Go-wide deferred batch ${batch_index}/${batch_count} after ${failure_class}; fresh generation tickets stay ahead of this retry." "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
              orchestrated_clear_chat_route_env
              rm -f "$content_path" "$headers_path"
              ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
              return 0
              ;;
          esac
        fi
        if orchestrated_last_chat_is_transient_transport && { [[ "$worker_mode" -eq 1 ]] || [[ ! -s "$content_path" ]]; }; then
          if [[ "$worker_mode" -eq 1 ]]; then
            wait_seconds="${ONLYMACS_GO_WIDE_TRANSPORT_REQUEUE_SECONDS:-$transient_transport_backoff_seconds}"
            [[ "$wait_seconds" =~ ^[0-9]+$ ]] || wait_seconds="$transient_transport_backoff_seconds"
            [[ "$wait_seconds" -gt 0 ]] || wait_seconds=20
            onlymacs_update_provider_health "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "failure" "$failure_class" "0"
            orchestrated_mark_go_wide_retry_ticket "$step_id" "$batch_index" "$validation_message" "$batch_artifact_path" "$batch_raw_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$wait_seconds" "$go_wide_ticket_kind"
            onlymacs_log_run_event "go_wide_transport_ticket_requeued" "$step_id" "retry_queued" "$attempt" "Go-wide released lane after transient transport failure; batch ${batch_index}/${batch_count} can be retried after ${wait_seconds}s while other tickets keep moving: ${validation_message}" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
            orchestrated_clear_chat_route_env
            rm -f "$content_path" "$headers_path"
            ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
            return 0
          fi
          if [[ "$transient_transport_retry_count" -lt "$transient_transport_retry_limit" ]]; then
            transient_transport_retry_count=$((transient_transport_retry_count + 1))
            wait_seconds=$((transient_transport_backoff_seconds * transient_transport_retry_count))
            orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "waiting_for_transport" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "Transient transport error before output; retrying batch ${batch_index}/${batch_count} in ${wait_seconds}s (${transient_transport_retry_count}/${transient_transport_retry_limit})."
            onlymacs_log_run_event "transient_transport_retrying" "$step_id" "retrying" "$attempt" "Transient transport error before output; retrying batch ${batch_index}/${batch_count} in ${wait_seconds}s (${transient_transport_retry_count}/${transient_transport_retry_limit}): ${validation_message}" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
            orchestrated_clear_chat_route_env
            rm -f "$content_path" "$headers_path"
            sleep "$wait_seconds"
            continue
          fi
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="queued"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="$validation_message"
          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "queued" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$validation_message"
          orchestrated_update_plan_step "$step_id" "queued" "$attempt" "$artifact_path" "$raw_path" "pending" "$validation_message" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "queued"
          onlymacs_log_run_event "transient_transport_queued" "$step_id" "queued" "$attempt" "Transient transport error preserved this run as resumable: ${validation_message}" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
          orchestrated_clear_chat_route_env
          rm -f "$content_path" "$headers_path"
          return 1
        fi
        if [[ -s "$content_path" ]]; then
          cp "$content_path" "${batch_attempts_dir}/attempt-$(printf '%02d' "$((attempt + 1))")-RESULT.md"
          onlymacs_log_run_event "partial_preserved" "$step_id" "partial" "$attempt" "Preserved partial output for batch ${batch_index}/${batch_count}; OnlyMacs will regenerate this micro-batch from the checkpoint." "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${owner_member_name:-$provider_name}" "$model_header" "${batch_attempts_dir}/attempt-$(printf '%02d' "$((attempt + 1))")-RESULT.md" "$(orchestrated_plan_path)"
          onlymacs_log_run_event "continuation_policy" "$step_id" "retrying" "$attempt" "Partial stream replay is not safe for machine artifacts; regenerating the current micro-batch instead of continuing mid-file." "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        fi
        onlymacs_update_provider_health "${failed_provider_id:-$provider_id}" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "failure" "$failure_class" "0"
        orchestrated_clear_chat_route_env
        rm -f "$content_path" "$headers_path"
        if [[ "$attempt" -ge "$repair_limit" ]]; then
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="$(orchestrated_failure_status_for_last_chat)"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="$validation_message"
          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS" "$batch_artifact_path" "${failed_provider_id:-$provider_id}" "${owner_member_name:-$provider_name}" "$model_header" "$validation_message"
          orchestrated_update_plan_step "$step_id" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS" "$attempt" "$artifact_path" "$raw_path" "failed" "$validation_message" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS"
          return 1
        fi
        case "$failure_class" in
          first_token_timeout|idle_timeout|wall_clock_timeout|transport_drop|provider_unavailable|provider_maintenance)
            if [[ -n "$failed_provider_id" && "$step_route_scope" != "local_only" ]]; then
              if orchestrated_failure_should_try_lower_quant "$failure_class" "${model_header:-$step_model}"; then
                ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT=1
                ONLYMACS_ORCHESTRATION_PROVIDER_ID="$failed_provider_id"
                onlymacs_log_run_event "model_fallback_requested" "$step_id" "rerouting" "$attempt" "Large model stalled after ${failure_class}; trying the same provider with a lower-quantized/warm model before giving up on that Mac." "$batch_artifact_path" "$failed_provider_id" "${owner_member_name:-$provider_name}" "${model_header:-$step_model}" "$batch_raw_path" "$(orchestrated_plan_path)"
              elif orchestrated_route_provider_locked_to "$failed_provider_id"; then
                ONLYMACS_ORCHESTRATION_FAILURE_STATUS="queued"
                ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="${validation_message}; pinned provider ${failed_provider_id} is preserved for resume"
                orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "queued" "$batch_artifact_path" "$failed_provider_id" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE"
                orchestrated_update_plan_step "$step_id" "queued" "$attempt" "$artifact_path" "$raw_path" "pending" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$failed_provider_id" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "queued"
                onlymacs_log_run_event "pinned_provider_preserved" "$step_id" "queued" "$attempt" "Pinned provider ${failed_provider_id} failed with ${failure_class}; preserving route instead of trying another Mac." "$batch_artifact_path" "$failed_provider_id" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
                orchestrated_clear_chat_route_env
                rm -f "$content_path" "$headers_path"
                return 1
              else
                if orchestrated_go_wide_enabled "$model_alias"; then
                  orchestrated_exclude_provider "$failed_provider_id"
                  onlymacs_log_run_event "go_wide_provider_excluded" "$step_id" "rerouting" "$attempt" "Go-wide excluded provider ${failed_provider_id} for this micro-batch after ${failure_class}; the next attempt should use another eligible Mac or wait for capacity." "$batch_artifact_path" "$failed_provider_id" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
                else
                  orchestrated_avoid_provider "$failed_provider_id"
                fi
                ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
                onlymacs_log_run_event "model_fallback_requested" "$step_id" "rerouting" "$attempt" "Avoiding provider ${failed_provider_id} after ${failure_class}; coordinator may select a warmer or lower-quantized model/provider." "$batch_artifact_path" "$failed_provider_id" "${failed_provider_name:-${owner_member_name:-$provider_name}}" "$failed_model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
              fi
            fi
            ;;
        esac
        attempt=$((attempt + 1))
        continue
        fi
      fi
      orchestrated_clear_chat_route_env

      provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
      provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
      owner_member_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
      model_header="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
      [[ -z "$provider_id" ]] && provider_id="${ONLYMACS_LAST_CHAT_PROVIDER_ID:-}"
      [[ -z "$provider_name" ]] && provider_name="${ONLYMACS_LAST_CHAT_PROVIDER_NAME:-}"
      [[ -z "$owner_member_name" ]] && owner_member_name="${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-}"
      [[ -z "$model_header" ]] && model_header="${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-}"
      if [[ "$step_route_scope" != "local_only" && -n "$provider_id" ]] && ! orchestrated_go_wide_enabled "$model_alias" && ! onlymacs_json_contains_string "${ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON:-[]}" "$provider_id"; then
        ONLYMACS_ORCHESTRATION_PROVIDER_ID="$provider_id"
      fi
      onlymacs_log_run_event "provider_selected" "$step_id" "running" "$attempt" "OnlyMacs selected provider ${owner_member_name:-$provider_name} for batch ${batch_index}/${batch_count}." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"

      if orchestrated_stream_content_looks_detached_prefix "$content_path"; then
        recovered_content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-recovered-content-XXXXXX")"
        recovery_status=0
        if orchestrated_recover_stream_content_from_activity "$recovered_content_path" "$headers_path" "$step_id" "$attempt" "$batch_artifact_path" "$batch_raw_path"; then
          if [[ -s "$recovered_content_path" ]]; then
            cp "$recovered_content_path" "$content_path"
            onlymacs_log_run_event "stream_prefix_recovered" "$step_id" "running" "$attempt" "Recovered full relay body after the local stream returned only an artifact prefix for batch ${batch_index}/${batch_count}." "$batch_artifact_path" "${ONLYMACS_LAST_CHAT_PROVIDER_ID:-$provider_id}" "${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-${owner_member_name:-$provider_name}}" "${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-$model_header}" "$batch_raw_path" "$(orchestrated_plan_path)"
          fi
        else
          recovery_status=$?
          if [[ "$recovery_status" -eq 2 ]]; then
            validation_message="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote activity is still running after a detached prefix for batch ${batch_index}/${batch_count}}"
            ONLYMACS_ORCHESTRATION_FAILURE_STATUS="queued"
            ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="$validation_message"
            orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "queued" "$batch_artifact_path" "${ONLYMACS_LAST_CHAT_PROVIDER_ID:-$provider_id}" "${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-${owner_member_name:-$provider_name}}" "${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-$model_header}" "$validation_message"
            orchestrated_update_plan_step "$step_id" "queued" "$attempt" "$artifact_path" "$raw_path" "pending" "$validation_message" "${ONLYMACS_LAST_CHAT_PROVIDER_ID:-$provider_id}" "${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-${owner_member_name:-$provider_name}}" "${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-$model_header}" "queued"
            rm -f "$recovered_content_path" "$content_path" "$headers_path"
            return 1
          fi
        fi
        rm -f "$recovered_content_path"
      fi

      attempt_raw_path="${batch_attempts_dir}/attempt-$(printf '%02d' "$((attempt + 1))")-RESULT.md"
      attempt_artifact_path="${batch_attempts_dir}/attempt-$(printf '%02d' "$((attempt + 1))")-${batch_filename}"
      normalized_path="${batch_attempts_dir}/attempt-$(printf '%02d' "$((attempt + 1))")-${batch_filename%.json}.normalized.json"
      cp "$content_path" "$attempt_raw_path"
      body_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-batch-body-XXXXXX")"
      if ! extract_marked_artifact_block "$content_path" "$body_path" && ! extract_single_fenced_code_block "$content_path" "$body_path"; then
        cp "$content_path" "$body_path"
      fi
      cp "$body_path" "$attempt_artifact_path"
      rm -f "$body_path" "$content_path" "$headers_path"

      repair_json_artifact_if_possible "$attempt_artifact_path" "$batch_validation_prompt"
      if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
        onlymacs_log_run_event "json_repair_applied" "$step_id" "running" "$attempt" "${ONLYMACS_JSON_REPAIR_MESSAGE:-recovered strict JSON before model retry}" "$attempt_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
      elif [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "failed" ]]; then
        onlymacs_log_run_event "json_repair_failed" "$step_id" "running" "$attempt" "${ONLYMACS_JSON_REPAIR_MESSAGE:-JSON repair failed}" "$attempt_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
      fi

      if json_artifact_to_item_array "$attempt_artifact_path" "$normalized_path"; then
        orchestrated_normalize_chunk_artifact "$normalized_path" "$batch_validation_prompt"
        repair_rioplatense_tuteo_artifact_if_possible "$normalized_path" "$batch_validation_prompt"
        if [[ "${ONLYMACS_DIALECT_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
          onlymacs_log_run_event "dialect_repair_applied" "$step_id" "running" "$attempt" "${ONLYMACS_DIALECT_REPAIR_MESSAGE:-normalized dialect forms before validation}" "$normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
        fi
        repair_source_card_schema_aliases_if_possible "$normalized_path" "$batch_validation_prompt"
        if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
          onlymacs_log_run_event "source_card_schema_repair_applied" "$step_id" "running" "$attempt" "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_MESSAGE:-normalized source-card schema aliases before validation}" "$normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
        fi
        repair_source_card_usage_artifact_if_possible "$normalized_path" "$batch_validation_prompt"
        if [[ "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
          onlymacs_log_run_event "source_card_usage_repair_applied" "$step_id" "running" "$attempt" "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_MESSAGE:-removed source-card usage meta language before validation}" "$normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
        fi
        accept_lock_held=0
        if [[ "$worker_mode" -eq 1 ]]; then
          accept_lock_path="$(orchestrated_plan_path).accept"
          orchestrated_acquire_plan_lock "$accept_lock_path"
          accept_lock_held=1
        fi
        onlymacs_log_run_event "validation_started" "$step_id" "running" "$attempt" "Validating batch ${batch_index}/${batch_count}." "$normalized_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
        validate_return_artifact "$normalized_path" "$batch_validation_prompt"
      else
        ONLYMACS_RETURN_VALIDATION_STATUS="failed"
        ONLYMACS_RETURN_VALIDATION_MESSAGE="batch artifact was not a JSON array or object containing item arrays"
      fi
      validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-failed}"
      validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-batch validation failed}"
      if [[ "$validation_status" == "failed" && "$validation_message" == *"batch artifact was not a JSON array"* ]]; then
        json_extraction_failure_count=$((json_extraction_failure_count + 1))
      else
        json_extraction_failure_count=0
      fi
      if [[ "$validation_status" != "failed" ]] && prompt_requires_unique_item_terms "$validation_prompt"; then
        orchestrated_validate_json_batch_uniqueness "$normalized_path" "$batches_dir" "$batch_index"
        if [[ "${ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS:-passed}" == "failed" ]]; then
          validation_status="failed"
          validation_message="${ONLYMACS_JSON_BATCH_UNIQUENESS_MESSAGE:-duplicate item terms found across JSON batches}"
        fi
      fi
      if [[ "$validation_status" != "failed" ]]; then
        orchestrated_validate_json_batch_item_range "$normalized_path" "$validation_prompt" "$batch_start"
        if [[ "${ONLYMACS_JSON_BATCH_RANGE_STATUS:-passed}" == "failed" ]]; then
          validation_status="failed"
          validation_message="${ONLYMACS_JSON_BATCH_RANGE_MESSAGE:-batch item/set range did not match expected global item numbers}"
        fi
      fi
      if [[ "$validation_status" != "failed" ]]; then
        orchestrated_validate_json_batch_set_topic "$normalized_path" "$validation_prompt" "$batch_start"
        if [[ "${ONLYMACS_JSON_BATCH_TOPIC_STATUS:-passed}" == "failed" ]]; then
          validation_status="failed"
          validation_message="${ONLYMACS_JSON_BATCH_TOPIC_MESSAGE:-batch topics did not match the plan set map}"
        fi
      fi

      if [[ "$validation_status" != "failed" ]]; then
        if ! orchestrated_promote_json_batch_artifact "$normalized_path" "$batch_artifact_path" "$step_id" "$batch_index" "completed"; then
          if [[ "$accept_lock_held" -eq 1 ]]; then
            orchestrated_release_plan_lock "$accept_lock_path"
            accept_lock_held=0
          fi
          if [[ "$worker_mode" -eq 1 ]]; then
            ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
            return 0
          fi
          return 1
        fi
        cp "$attempt_raw_path" "$batch_raw_path"
        orchestrated_execute_local_shadow_json_batch_review "$model_alias" "$original_prompt" "$step_index" "$step_count" "$filename" "$batch_index" "$batch_count" "$batch_start" "$batch_end" "$batch_items" "$batch_filename" "$batch_dir" "$batch_artifact_path" "$validation_prompt" "$step_route_scope"
        batch_paths+=("$batch_artifact_path")
        orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "completed" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "Completed batch ${batch_index}/${batch_count}."
        onlymacs_update_provider_health "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "success" "" "0"
        if [[ "$attempt" -gt 0 ]]; then
          onlymacs_log_run_event "repair_passed" "$step_id" "completed" "$attempt" "Batch ${batch_index}/${batch_count} repair passed validation." "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        fi
        if [[ "$accept_lock_held" -eq 1 ]]; then
          orchestrated_release_plan_lock "$accept_lock_path"
          accept_lock_held=0
        fi
        if [[ "$worker_mode" -eq 1 ]]; then
          ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
          return 0
        fi
        break
      fi

      if [[ "$accept_lock_held" -eq 1 ]]; then
        orchestrated_release_plan_lock "$accept_lock_path"
        accept_lock_held=0
      fi

      if [[ "$worker_mode" -eq 1 && "$attempt" -eq 0 && "${ONLYMACS_GO_WIDE_DEFER_REPAIR_TICKETS:-1}" == "1" && "$go_wide_ticket_kind" != "repair" ]]; then
        if orchestrated_json_batch_can_write_checkpoint "$step_id" "$batch_index" "$batch_artifact_path"; then
          if [[ -s "$attempt_artifact_path" ]]; then
            cp "$attempt_artifact_path" "$batch_artifact_path"
          fi
          if [[ -s "$attempt_raw_path" ]]; then
            cp "$attempt_raw_path" "$batch_raw_path"
          fi
        fi
        ONLYMACS_ORCHESTRATION_FAILURE_STATUS="repair_queued"
        ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="Go-wide queued batch ${batch_index}/${batch_count} for repair after fresh generation tickets: ${validation_message}"
        orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "repair_queued" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE"
        orchestrated_mark_go_wide_repair_ticket "$step_id" "$batch_index" "$validation_message" "$batch_artifact_path" "$batch_raw_path"
        onlymacs_log_run_event "go_wide_repair_ticket_queued" "$step_id" "repair_queued" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
        return 0
      fi

      if orchestrated_json_batch_can_write_checkpoint "$step_id" "$batch_index" "$batch_artifact_path"; then
        if [[ -s "$attempt_artifact_path" ]]; then
          cp "$attempt_artifact_path" "$batch_artifact_path"
        fi
        if [[ -s "$attempt_raw_path" ]]; then
          cp "$attempt_raw_path" "$batch_raw_path"
        fi
      fi
      if [[ "$attempt" -ge "$repair_limit" ]]; then
        if [[ "$worker_mode" -eq 1 && "$go_wide_ticket_kind" == "repair" && "${ONLYMACS_GO_WIDE_TRIAGE_REPAIR_CHURN:-0}" == "1" ]]; then
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="needs_local_salvage"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="Go-wide repair batch ${batch_index}/${batch_count} needs local salvage after bounded repair attempts: ${validation_message}"
          failure_class="$(onlymacs_log_failure_classification "$step_id" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path")"
          onlymacs_update_provider_health "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failure" "$failure_class" "0"
          onlymacs_log_run_event "go_wide_repair_triaged" "$step_id" "needs_local_salvage" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "needs_local_salvage" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE"
          ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
          return 0
        fi
        if [[ "$worker_mode" -eq 1 && "$go_wide_ticket_kind" == "repair" ]]; then
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="churn"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="Go-wide parked repair batch ${batch_index}/${batch_count} after bounded repair attempts so other tickets can keep moving: ${validation_message}"
          failure_class="$(onlymacs_log_failure_classification "$step_id" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path")"
          onlymacs_update_provider_health "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failure" "$failure_class" "0"
          onlymacs_log_run_event "go_wide_repair_ticket_parked" "$step_id" "churn" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
          orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "churn" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE"
          ONLYMACS_GO_WIDE_WORKER_COMPLETED=1
          return 0
        fi
        ONLYMACS_ORCHESTRATION_FAILURE_STATUS="churn"
        ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="JSON batch ${batch_index}/${batch_count} did not validate after bounded repair attempts: ${validation_message}"
        failure_class="$(onlymacs_log_failure_classification "$step_id" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path")"
        onlymacs_update_provider_health "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failure" "$failure_class" "0"
        onlymacs_log_run_event "repair_failed" "$step_id" "churn" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$batch_raw_path" "$(orchestrated_plan_path)"
        orchestrated_update_json_batch_status "$step_id" "$batch_index" "$batch_count" "churn" "$batch_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE"
        orchestrated_update_plan_step "$step_id" "churn" "$attempt" "$artifact_path" "$raw_path" "$validation_status" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failed"
        return 1
      fi
      attempt=$((attempt + 1))
    done
  done

  if [[ "$worker_mode" -eq 1 ]]; then
    return 1
  fi

  orchestrated_wait_for_go_wide_shadow_reviews "$step_dir" "$step_id" "$artifact_path" "$raw_path"

  if [[ "$reused_batch_count" -gt 0 && "$reused_batch_summary_emitted" -eq 0 ]]; then
    orchestrated_update_plan_step "$step_id" "resuming" "0" "$artifact_path" "$raw_path" "passed" "Reused ${reused_batch_count} accepted batch$(chat_plural_suffix "$reused_batch_count"); assembling final artifact." "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "running"
    onlymacs_log_run_event "batch_reuse_summary" "$step_id" "resuming" "0" "Reused ${reused_batch_count} accepted batch$(chat_plural_suffix "$reused_batch_count"); assembling final artifact." "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
  fi

  if ! jq -s 'add' "${batch_paths[@]}" >"$artifact_path" 2>"${artifact_path}.validation.log"; then
    validation_status="failed"
    validation_message="$(head -5 "${artifact_path}.validation.log" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-300)"
    rm -f "${artifact_path}.validation.log"
    ONLYMACS_ORCHESTRATION_FAILURE_STATUS="failed"
    ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="local JSON batch assembly failed: ${validation_message}"
    orchestrated_update_plan_step "$step_id" "failed_validation" 0 "$artifact_path" "$raw_path" "$validation_status" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failed"
    return 1
  fi
  rm -f "${artifact_path}.validation.log"

  : >"$raw_path"
  for batch_index in "${!batch_paths[@]}"; do
    printf '## Batch %02d\n\n' "$((batch_index + 1))" >>"$raw_path"
    cat "${batch_paths[$batch_index]}" >>"$raw_path"
    printf '\n\n' >>"$raw_path"
  done

  validate_return_artifact "$artifact_path" "$validation_prompt"
  validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-skipped}"
  validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
  if [[ "$validation_status" != "failed" ]] && prompt_requires_unique_item_terms "$validation_prompt"; then
    final_duplicate_terms="$(artifact_duplicate_vocabulary_terms "$artifact_path" || true)"
    if [[ -n "$final_duplicate_terms" ]]; then
      validation_status="failed"
      validation_message="assembled JSON batches contain duplicate item terms: ${final_duplicate_terms}"
    fi
  fi
	  if [[ "$validation_status" == "failed" ]]; then
	    if [[ "${ONLYMACS_GO_WIDE_ASSEMBLE_ONLY:-0}" == "1" ]] && jq -e --argjson expected_count "$expected_count" 'type == "array" and length == $expected_count' "$artifact_path" >/dev/null 2>&1; then
	      onlymacs_log_run_event "go_wide_assemble_only_validation_downgraded" "$step_id" "completed" "0" "Assembled accepted go-wide batches without reopening remote generation after final semantic validation failed: ${validation_message}" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
	      validation_status="passed"
	      validation_message="assembled accepted go-wide batches; final semantic validation warning: ${validation_message}"
	    else
	      ONLYMACS_ORCHESTRATION_FAILURE_STATUS="failed"
	      ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="assembled JSON batches failed validation: ${validation_message}"
	      orchestrated_update_plan_step "$step_id" "failed_validation" 0 "$artifact_path" "$raw_path" "$validation_status" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failed"
	      return 1
	    fi
	  fi

  root_artifact="${ONLYMACS_CURRENT_RETURN_DIR}/files/${filename}"
  cp "$artifact_path" "$root_artifact"
  orchestrated_record_artifact "$root_artifact" "$filename" "$step_id"
  onlymacs_log_run_event "artifact_saved" "$step_id" "completed" "0" "Saved assembled batch artifact." "$root_artifact" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
  orchestrated_update_plan_step "$step_id" "completed" 0 "$artifact_path" "$raw_path" "$validation_status" "$validation_message" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "running"
  return 0
}

orchestrated_execute_step() {
  local model="${1:-}"
  local model_alias="${2:-}"
  local route_scope="${3:-swarm}"
  local original_prompt="${4:-}"
  local step_index="${5:-1}"
  local step_count="${6:-1}"
  local filename step_id step_dir files_dir attempts_dir content_path headers_path raw_path artifact_path body_path payload step_prompt
  local attempt repair_limit validation_prompt repair_context_prompt validation_status validation_message provider_id provider_name owner_member_name model_header root_artifact max_tokens stream_retry_same_prompt
  local failed_provider_id failure_class stream_transport_retry_count stream_reroute_count validation_reroute_count reroute_message stream_activity_recovered
  local attempt_sequence attempt_label attempt_raw_path attempt_artifact_path validation_artifact_path target_path
  local step_model_alias step_model step_route_scope picked_step_model

  filename="$(orchestrated_expected_filename "$original_prompt" "$step_index" "$step_count")"
  step_id="$(orchestrated_step_id "$step_index")"
  step_dir="${ONLYMACS_CURRENT_RETURN_DIR}/steps/${step_id}"
  files_dir="${step_dir}/files"
  attempts_dir="${step_dir}/attempts"
  mkdir -p "$files_dir" "$attempts_dir" "${ONLYMACS_CURRENT_RETURN_DIR}/files" || return 1

  repair_limit="$(orchestrated_repair_limit)"
  max_tokens="$(orchestrated_max_tokens)"
  attempt=0
  validation_status=""
  validation_message=""
  provider_id=""
  provider_name=""
  owner_member_name=""
  model_header=""
  failed_provider_id=""
  failure_class=""
  attempt_sequence=0
  artifact_path="${files_dir}/${filename}"
  raw_path="${step_dir}/RESULT.md"
  stream_retry_same_prompt=0
  stream_transport_retry_count=0
  stream_reroute_count=0
  validation_reroute_count=0
  step_model_alias="$(orchestrated_route_alias_for_step "$model_alias" "$step_index" "$filename")"
  step_route_scope="$(route_scope_for_alias "$step_model_alias")"
  step_model="$(normalize_model_alias "$step_model_alias")"

  if orchestrated_is_plan_file_job; then
    step_prompt="$(orchestrated_compile_step_prompt "$original_prompt" "$step_index" "$step_count" "$filename")"
    validation_prompt="$(orchestrated_validation_prompt "$original_prompt" "$step_index" "$step_prompt")"
    if orchestrated_should_batch_plan_json_step "$validation_prompt" "$filename"; then
      orchestrated_execute_plan_json_batch_step "$model" "$model_alias" "$route_scope" "$original_prompt" "$step_index" "$step_count" "$filename" "$validation_prompt"
      return $?
    fi
  fi

  while [[ "$attempt" -le "$repair_limit" ]]; do
    if [[ "$attempt" -eq 0 || "$stream_retry_same_prompt" -eq 1 ]]; then
      step_prompt="$(orchestrated_compile_step_prompt "$original_prompt" "$step_index" "$step_count" "$filename")"
      repair_context_prompt="$step_prompt"
      validation_prompt="$(orchestrated_validation_prompt "$original_prompt" "$step_index" "$step_prompt")"
      if [[ "$stream_retry_same_prompt" -eq 1 ]]; then
        orchestrated_update_plan_step "$step_id" "retrying" "$attempt" "$artifact_path" "$raw_path" "pending" "$validation_message" "" "" "" "running"
      else
        orchestrated_update_plan_step "$step_id" "running" "$attempt" "" "" "pending" "" "" "" "" "running"
      fi
      stream_retry_same_prompt=0
    else
      step_prompt="$(orchestrated_compile_repair_prompt "${repair_context_prompt:-$validation_prompt}" "$filename" "$validation_message" "$artifact_path")"
      orchestrated_update_plan_step "$step_id" "repairing" "$attempt" "$artifact_path" "$raw_path" "$validation_status" "$validation_message" "$provider_id" "$provider_name" "$model_header" "running"
      if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf '\nOnlyMacs is repairing %s after validation failed: %s\n' "$step_id" "$validation_message" >&2
      fi
    fi

    max_tokens="$(orchestrated_max_tokens_for_step "${validation_prompt:-$step_prompt}" "$filename")"
    picked_step_model="$(orchestrated_model_for_step "$(normalize_model_alias "$step_model_alias")" "$step_model_alias" "$step_route_scope" "${validation_prompt:-$step_prompt}" "$filename")"
    if [[ -n "$picked_step_model" ]]; then
      step_model="$picked_step_model"
    fi
    content_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-orchestrated-content-XXXXXX")"
    headers_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-orchestrated-headers-XXXXXX")"
    orchestrated_set_chat_route_env "$max_tokens" "$step_route_scope" "$step_model"
    payload="$(build_chat_payload "$step_model" "$step_prompt" "$step_route_scope" "$step_model_alias")"
    if ! orchestrated_stream_payload_with_capacity_wait "$payload" "$content_path" "$headers_path" "$step_id" "$attempt" "$artifact_path" "$raw_path"; then
      stream_activity_recovered=0
      if orchestrated_recover_stream_content_from_activity "$content_path" "$headers_path" "$step_id" "$attempt" "$artifact_path" "$raw_path"; then
        stream_activity_recovered=1
      fi
      if [[ "$stream_activity_recovered" -eq 0 ]]; then
      failed_provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
      if [[ -z "$failed_provider_id" && "$step_route_scope" != "local_only" ]]; then
        failed_provider_id="${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}"
      fi
      failure_class="$(onlymacs_log_failure_classification "$step_id" "$attempt" "${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}" "$artifact_path" "$failed_provider_id" "$provider_name" "$model_header" "$raw_path")"
      onlymacs_update_provider_health "$failed_provider_id" "$provider_name" "$model_header" "failure" "$failure_class" "0"
      if [[ "${ONLYMACS_LAST_CHAT_FAILURE_KIND:-}" == "detached_activity_running" ]] || (orchestrated_last_chat_is_transient_transport && [[ ! -s "$content_path" ]]); then
        ONLYMACS_ORCHESTRATION_FAILURE_STATUS="$(orchestrated_failure_status_for_last_chat)"
        ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}"
        orchestrated_update_plan_step "$step_id" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS" "$attempt" "$artifact_path" "$raw_path" "pending" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$failed_provider_id" "$provider_name" "$model_header" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS"
        onlymacs_log_run_event "transient_transport_queued" "$step_id" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS" "$attempt" "Transient transport error preserved this run as resumable: ${ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE}" "$artifact_path" "$failed_provider_id" "$provider_name" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
        unset ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE
        orchestrated_clear_chat_route_env
        rm -f "$content_path" "$headers_path"
        return 1
      fi
      if [[ -s "$content_path" ]]; then
        onlymacs_log_run_event "partial_preserved" "$step_id" "partial" "$attempt" "Preserved partial output for ${step_id}; OnlyMacs will retry/reroute only when replay is safe." "$artifact_path" "$failed_provider_id" "$provider_name" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
      fi
      if orchestrated_step_is_chunk_data "$original_prompt" "$step_index" && [[ "$attempt" -lt "$repair_limit" && "${ONLYMACS_LAST_CHAT_HTTP_STATUS:-}" != "409" && "$stream_transport_retry_count" -lt 1 ]]; then
        validation_message="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed; retrying the chunk from the start}"
        if [[ -s "$content_path" ]]; then
          cp "$content_path" "$raw_path"
        fi
        orchestrated_update_plan_step "$step_id" "retrying" "$attempt" "$artifact_path" "$raw_path" "failed" "$validation_message" "" "" "" "running"
        if [[ "$step_route_scope" != "local_only" && -n "$failed_provider_id" ]]; then
          ONLYMACS_ORCHESTRATION_PROVIDER_ID="$failed_provider_id"
        fi
        orchestrated_clear_chat_route_env
        rm -f "$content_path" "$headers_path"
        attempt=$((attempt + 1))
        stream_transport_retry_count=$((stream_transport_retry_count + 1))
        stream_retry_same_prompt=1
        continue
      fi
      if [[ -n "$failed_provider_id" && "$stream_reroute_count" -lt 1 ]]; then
        stream_reroute_count=$((stream_reroute_count + 1))
        if orchestrated_failure_should_try_lower_quant "$failure_class" "${model_header:-$step_model}"; then
          ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT=1
          ONLYMACS_ORCHESTRATION_PROVIDER_ID="$failed_provider_id"
          reroute_message="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}; trying provider ${failed_provider_id} with a lower-quantized/warm model"
          onlymacs_log_run_event "model_fallback_requested" "$step_id" "rerouting" "$attempt" "Large model stalled after ${failure_class}; trying the same provider with a lower-quantized/warm model before giving up on that Mac." "$artifact_path" "$failed_provider_id" "$provider_name" "${model_header:-$step_model}" "$raw_path" "$(orchestrated_plan_path)"
        elif orchestrated_route_provider_locked_to "$failed_provider_id"; then
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="queued"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}; pinned provider ${failed_provider_id} is preserved for resume"
          orchestrated_update_plan_step "$step_id" "queued" "$attempt" "$artifact_path" "$raw_path" "pending" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$failed_provider_id" "$provider_name" "$model_header" "queued"
          onlymacs_log_run_event "pinned_provider_preserved" "$step_id" "queued" "$attempt" "Pinned provider ${failed_provider_id} failed with ${failure_class}; preserving route instead of trying another Mac." "$artifact_path" "$failed_provider_id" "$provider_name" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
          unset ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE
          orchestrated_clear_chat_route_env
          rm -f "$content_path" "$headers_path"
          return 1
        else
          if orchestrated_go_wide_enabled "$model_alias"; then
            orchestrated_exclude_provider "$failed_provider_id"
            onlymacs_log_run_event "go_wide_provider_excluded" "$step_id" "rerouting" "$attempt" "Go-wide excluded provider ${failed_provider_id} for this step after ${failure_class}; the next attempt should use another eligible Mac or wait for capacity." "$artifact_path" "$failed_provider_id" "$provider_name" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
          else
            orchestrated_avoid_provider "$failed_provider_id"
          fi
          ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
          reroute_message="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}; avoiding provider ${failed_provider_id} and trying another eligible Mac"
          onlymacs_log_run_event "model_fallback_requested" "$step_id" "rerouting" "$attempt" "Avoiding provider ${failed_provider_id} after ${failure_class}; coordinator may select a warmer or lower-quantized model/provider." "$artifact_path" "$failed_provider_id" "$provider_name" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
        fi
        orchestrated_update_plan_step "$step_id" "rerouting" "$attempt" "$artifact_path" "$raw_path" "pending" "$reroute_message" "$failed_provider_id" "" "" "running"
        orchestrated_set_chat_route_env "$max_tokens" "$step_route_scope" "$step_model"
        payload="$(build_chat_payload "$step_model" "$step_prompt" "$step_route_scope" "$step_model_alias")"
        if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
          printf '\nOnlyMacs could not continue on the same Mac for %s, so it is trying another eligible Mac.\n' "$step_id" >&2
        fi
        if ! orchestrated_stream_payload_with_capacity_wait "$payload" "$content_path" "$headers_path" "$step_id" "$attempt" "$artifact_path" "$raw_path"; then
          write_chat_failure_artifact "$content_path" "$headers_path" "$step_model_alias" "$original_prompt" "$step_route_scope"
          ONLYMACS_ORCHESTRATION_FAILURE_STATUS="$(orchestrated_failure_status_for_last_chat)"
          ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}"
          orchestrated_update_plan_step "$step_id" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS" "$attempt" "$artifact_path" "$raw_path" "failed" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "" "" "" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS"
          unset ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE
          orchestrated_clear_chat_route_env
          rm -f "$content_path" "$headers_path"
          return 1
        fi
      else
        write_chat_failure_artifact "$content_path" "$headers_path" "$step_model_alias" "$original_prompt" "$step_route_scope"
        ONLYMACS_ORCHESTRATION_FAILURE_STATUS="$(orchestrated_failure_status_for_last_chat)"
        ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="${ONLYMACS_LAST_CHAT_FAILURE_MESSAGE:-remote stream failed}"
        orchestrated_update_plan_step "$step_id" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS" "$attempt" "$artifact_path" "$raw_path" "failed" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "" "" "" "$ONLYMACS_ORCHESTRATION_FAILURE_STATUS"
        unset ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE
        orchestrated_clear_chat_route_env
        rm -f "$content_path" "$headers_path"
        return 1
      fi
      fi
    fi
    orchestrated_clear_chat_route_env
    unset ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE

    attempt_sequence=$((attempt_sequence + 1))
    attempt_label="$(printf 'attempt-%02d' "$attempt_sequence")"
    attempt_raw_path="${attempts_dir}/${attempt_label}-RESULT.md"
    attempt_artifact_path="${attempts_dir}/${attempt_label}-${filename}"
    target_path="$(artifact_target_path_from_content "$content_path" 2>/dev/null || true)"
    target_path="$(safe_artifact_target_path "$target_path" "$filename")"
    cp "$content_path" "$attempt_raw_path"
    provider_id="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-id")"
    provider_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-provider-name")"
    owner_member_name="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-owner-member-name")"
    model_header="$(onlymacs_chat_header_value "$headers_path" "x-onlymacs-resolved-model")"
    if [[ "$step_route_scope" != "local_only" && -n "$provider_id" ]] && ! onlymacs_json_contains_string "${ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON:-[]}" "$provider_id"; then
      ONLYMACS_ORCHESTRATION_PROVIDER_ID="$provider_id"
    fi
    onlymacs_log_run_event "provider_selected" "$step_id" "running" "$attempt" "OnlyMacs selected provider ${owner_member_name:-$provider_name}." "" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"

    body_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-orchestrated-body-XXXXXX")"
    if ! extract_marked_artifact_block "$content_path" "$body_path" && ! extract_single_fenced_code_block "$content_path" "$body_path"; then
      cp "$content_path" "$body_path"
    fi
    cp "$body_path" "$attempt_artifact_path"
    rm -f "$body_path" "$content_path" "$headers_path"

    if orchestrated_step_is_chunk_data "$original_prompt" "$step_index"; then
      orchestrated_normalize_chunk_artifact "$attempt_artifact_path" "${validation_prompt:-$original_prompt}"
    fi
    repair_json_artifact_if_possible "$attempt_artifact_path" "${validation_prompt:-$original_prompt}"
    if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "repaired" ]]; then
      onlymacs_log_run_event "json_repair_applied" "$step_id" "running" "$attempt" "${ONLYMACS_JSON_REPAIR_MESSAGE:-recovered strict JSON before model retry}" "$attempt_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
    elif [[ "${ONLYMACS_JSON_REPAIR_STATUS:-skipped}" == "failed" ]]; then
      onlymacs_log_run_event "json_repair_failed" "$step_id" "running" "$attempt" "${ONLYMACS_JSON_REPAIR_MESSAGE:-JSON repair failed}" "$attempt_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
    fi
    validation_artifact_path="$attempt_artifact_path"
    onlymacs_log_run_event "validation_started" "$step_id" "running" "$attempt" "Validating returned artifact." "$validation_artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$attempt_raw_path" "$(orchestrated_plan_path)"
    validate_return_artifact "$validation_artifact_path" "${validation_prompt:-$original_prompt}"
    validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-skipped}"
    validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
    if [[ "$validation_status" != "failed" ]] && orchestrated_step_is_chunk_data "$original_prompt" "$step_index"; then
      orchestrated_validate_chunk_uniqueness "$validation_artifact_path" "$step_index"
      if [[ "${ONLYMACS_CHUNK_UNIQUENESS_STATUS:-passed}" == "failed" ]]; then
        validation_status="failed"
        validation_message="${ONLYMACS_CHUNK_UNIQUENESS_MESSAGE:-duplicate vocabulary terms found across chunked output}"
      fi
    fi

    if [[ "$validation_status" != "failed" ]]; then
      cp "$attempt_artifact_path" "$artifact_path"
      cp "$attempt_raw_path" "$raw_path"
      if ! orchestrated_step_is_chunk_data "$original_prompt" "$step_index"; then
        root_artifact="${ONLYMACS_CURRENT_RETURN_DIR}/files/${filename}"
        cp "$artifact_path" "$root_artifact"
        orchestrated_record_artifact "$root_artifact" "$target_path" "$step_id"
        onlymacs_log_run_event "artifact_saved" "$step_id" "completed" "$attempt" "Saved validated artifact." "$root_artifact" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
      fi
      if [[ "$attempt" -gt 0 ]]; then
        onlymacs_log_run_event "repair_passed" "$step_id" "completed" "$attempt" "Repair artifact passed validation." "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
      fi
      onlymacs_update_provider_health "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "success" "" "0"
      orchestrated_update_plan_step "$step_id" "completed" "$attempt" "$artifact_path" "$raw_path" "$validation_status" "$validation_message" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "running"
      return 0
    fi
    if [[ -s "$attempt_artifact_path" ]]; then
      cp "$attempt_artifact_path" "$artifact_path"
    fi
    if [[ -s "$attempt_raw_path" ]]; then
      cp "$attempt_raw_path" "$raw_path"
    fi

    if [[ "$attempt" -ge "$repair_limit" ]]; then
      if [[ -n "$provider_id" && "$validation_reroute_count" -lt 1 ]] \
        && ! orchestrated_route_provider_locked_to "$provider_id" \
        && ! onlymacs_json_contains_string "${ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON:-[]}" "$provider_id"; then
        validation_reroute_count=$((validation_reroute_count + 1))
        orchestrated_exclude_provider "$provider_id"
        ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
        reroute_message="validation failed after ${repair_limit} repair attempt(s) on ${owner_member_name:-$provider_name}; excluding provider ${provider_id} and trying another eligible Mac"
        orchestrated_update_plan_step "$step_id" "rerouting" "$attempt" "$artifact_path" "$raw_path" "$validation_status" "$reroute_message" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "running"
        if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
          printf '\nOnlyMacs validation did not converge on %s for %s, so it is trying another eligible Mac.\n' "${owner_member_name:-$provider_name}" "$step_id" >&2
        fi
        ONLYMACS_ORCHESTRATION_FAIL_FAST_ON_CAPACITY=1
        ONLYMACS_ORCHESTRATION_FAIL_FAST_CAPACITY_MESSAGE="validation did not converge on ${owner_member_name:-$provider_name}; no alternate eligible remote Mac is currently available"
        attempt=0
        stream_retry_same_prompt=0
        stream_transport_retry_count=0
        stream_reroute_count=0
        continue
      fi
      ONLYMACS_ORCHESTRATION_FAILURE_STATUS="churn"
      ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="validation did not converge after bounded repair/reroute attempts: ${validation_message}"
      failure_class="$(onlymacs_log_failure_classification "$step_id" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path")"
      onlymacs_update_provider_health "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failure" "$failure_class" "0"
      onlymacs_log_run_event "repair_failed" "$step_id" "churn" "$attempt" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "$artifact_path" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "$raw_path" "$(orchestrated_plan_path)"
      orchestrated_update_plan_step "$step_id" "churn" "$attempt" "$artifact_path" "$raw_path" "$validation_status" "$validation_message" "$provider_id" "${owner_member_name:-$provider_name}" "$model_header" "failed"
      return 1
    fi
    attempt=$((attempt + 1))
  done

  return 1
}

orchestrated_execute_local_assembly_step() {
  local original_prompt="${1:-}"
  local step_index="${2:-1}"
  local step_count="${3:-1}"
  local filename step_id step_dir files_dir raw_path artifact_path entries_path validation_log
  local expected_count actual_count duplicate_terms root_artifact validation_status validation_message

  filename="$(orchestrated_expected_filename "$original_prompt" "$step_index" "$step_count")"
  step_id="$(orchestrated_step_id "$step_index")"
  step_dir="${ONLYMACS_CURRENT_RETURN_DIR}/steps/${step_id}"
  files_dir="${step_dir}/files"
  raw_path="${step_dir}/RESULT.md"
  artifact_path="${files_dir}/${filename}"
  entries_path="${step_dir}/entries.json"
  expected_count="$(prompt_exact_count_requirement "$original_prompt" || true)"
  mkdir -p "$files_dir" "${ONLYMACS_CURRENT_RETURN_DIR}/files" || return 1

  orchestrated_update_plan_step "$step_id" "assembling" 0 "$artifact_path" "$raw_path" "pending" "" "" "OnlyMacs local assembler" "local" "running"

  validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-assemble-XXXXXX")"
  if ! jq -s 'add' "${ONLYMACS_CURRENT_RETURN_DIR}"/steps/step-*/files/*.json >"$entries_path" 2>"$validation_log"; then
    validation_message="$(head -5 "$validation_log" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-300)"
    rm -f "$validation_log"
    ONLYMACS_ORCHESTRATION_FAILURE_STATUS="failed_validation"
    ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="could not assemble chunk JSON: ${validation_message}"
    orchestrated_update_plan_step "$step_id" "failed_validation" 0 "$artifact_path" "$raw_path" "failed" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "" "OnlyMacs local assembler" "local" "failed"
    return 1
  fi
  rm -f "$validation_log"

  actual_count="$(jq -r 'length' "$entries_path" 2>/dev/null || printf '0')"
  if [[ "$expected_count" =~ ^[0-9]+$ && "$actual_count" != "$expected_count" ]]; then
    ONLYMACS_ORCHESTRATION_FAILURE_STATUS="failed_validation"
    ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="assembled ${actual_count} entries, expected ${expected_count}"
    orchestrated_update_plan_step "$step_id" "failed_validation" 0 "$artifact_path" "$raw_path" "failed" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "" "OnlyMacs local assembler" "local" "failed"
    return 1
  fi
  duplicate_terms="$(artifact_duplicate_vocabulary_terms "$entries_path" || true)"
  if [[ -n "$duplicate_terms" ]]; then
    ONLYMACS_ORCHESTRATION_FAILURE_STATUS="failed_validation"
    ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="assembled duplicate Vietnamese terms: ${duplicate_terms}"
    orchestrated_update_plan_step "$step_id" "failed_validation" 0 "$artifact_path" "$raw_path" "failed" "$ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE" "" "OnlyMacs local assembler" "local" "failed"
    return 1
  fi

  {
    cat <<'JS_HEAD'
#!/usr/bin/env node
const readline = require("node:readline");

const vocabulary =
JS_HEAD
    jq . "$entries_path"
    printf ';\n\nconst EXPECTED_COUNT = %s;\n' "${expected_count:-0}"
    cat <<'JS_TAIL'
const REQUIRED_FIELDS = ["vietnamese", "english", "partOfSpeech", "pronunciation", "difficulty", "topic", "example"];

function validateVocabulary() {
  if (!Array.isArray(vocabulary) || vocabulary.length !== EXPECTED_COUNT) {
    throw new Error(`Expected ${EXPECTED_COUNT} vocabulary entries, found ${Array.isArray(vocabulary) ? vocabulary.length : "non-array"}.`);
  }
  vocabulary.forEach((entry, index) => {
    for (const field of REQUIRED_FIELDS) {
      if (!entry[field] || String(entry[field]).trim() === "") {
        throw new Error(`Entry ${index + 1} is missing ${field}.`);
      }
    }
  });
}

validateVocabulary();

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
let score = 0;
let attempts = 0;
let streak = 0;
let bestStreak = 0;
const missed = [];

function ask(question) {
  return new Promise((resolve) => rl.question(question, (answer) => resolve(answer.trim())));
}

function normalize(value) {
  return String(value || "").trim().toLowerCase();
}

function shuffle(items) {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function sample(items, count) {
  return shuffle(items).slice(0, Math.min(count, items.length));
}

function recordResult(ok, entry, expected) {
  attempts += 1;
  if (ok) {
    score += 1;
    streak += 1;
    bestStreak = Math.max(bestStreak, streak);
    console.log("Correct.\n");
    return;
  }
  streak = 0;
  missed.push(entry);
  console.log(`Not quite. Expected: ${expected}\n`);
}

function printEntry(entry) {
  console.log(`${entry.vietnamese} = ${entry.english}`);
  console.log(`Part of speech: ${entry.partOfSpeech}`);
  console.log(`Pronunciation: ${entry.pronunciation}`);
  console.log(`Topic: ${entry.topic} | Difficulty: ${entry.difficulty}`);
  console.log(`Example: ${entry.example}\n`);
}

function printSummary() {
  console.log("\nSession summary");
  console.log(`Score: ${score}/${attempts}`);
  console.log(`Current streak: ${streak}`);
  console.log(`Best streak: ${bestStreak}`);
  console.log(`Missed words: ${missed.length}`);
  if (missed.length > 0) {
    console.log([...new Set(missed.map((entry) => entry.vietnamese))].join(", "));
  }
}

async function flashcards(entries = vocabulary) {
  for (const entry of shuffle(entries)) {
    printEntry(entry);
    await ask("Press Enter for the next card...");
  }
  printSummary();
}

async function multipleChoice(entries = vocabulary) {
  for (const entry of shuffle(entries)) {
    const wrong = sample(vocabulary.filter((candidate) => candidate !== entry), 3).map((candidate) => candidate.english);
    const choices = shuffle([entry.english, ...wrong]);
    console.log(`\n${entry.vietnamese} (${entry.pronunciation})`);
    choices.forEach((choice, index) => console.log(`${index + 1}. ${choice}`));
    const answer = await ask("Choose 1-4: ");
    const selected = choices[Number(answer) - 1] || "";
    recordResult(normalize(selected) === normalize(entry.english), entry, entry.english);
  }
  printSummary();
}

async function reverseLookup(entries = vocabulary) {
  for (const entry of shuffle(entries)) {
    const answer = await ask(`Vietnamese for "${entry.english}"? `);
    recordResult(normalize(answer) === normalize(entry.vietnamese), entry, entry.vietnamese);
  }
  printSummary();
}

async function spellingPractice(entries = vocabulary) {
  for (const entry of shuffle(entries)) {
    const answer = await ask(`Spell the Vietnamese for "${entry.english}" (${entry.pronunciation}): `);
    recordResult(normalize(answer) === normalize(entry.vietnamese), entry, entry.vietnamese);
  }
  printSummary();
}

async function topicReview() {
  const topics = [...new Set(vocabulary.map((entry) => entry.topic))].sort();
  console.log(`Topics: ${topics.join(", ")}`);
  const topic = normalize(await ask("Topic to review: "));
  const matches = vocabulary.filter((entry) => normalize(entry.topic).includes(topic));
  if (matches.length === 0) {
    console.log("No matching topic.\n");
    return;
  }
  await flashcards(matches);
}

async function mixedQuiz() {
  const questions = sample(vocabulary, 20);
  for (const entry of questions) {
    const mode = Math.floor(Math.random() * 3);
    if (mode === 0) {
      const answer = await ask(`Translate "${entry.vietnamese}" to English: `);
      recordResult(normalize(answer) === normalize(entry.english), entry, entry.english);
    } else if (mode === 1) {
      const answer = await ask(`Vietnamese for "${entry.english}"? `);
      recordResult(normalize(answer) === normalize(entry.vietnamese), entry, entry.vietnamese);
    } else {
      const answer = await ask(`Spell "${entry.english}" in Vietnamese (${entry.pronunciation}): `);
      recordResult(normalize(answer) === normalize(entry.vietnamese), entry, entry.vietnamese);
    }
  }
  printSummary();
}

async function missedWordReview() {
  if (missed.length === 0) {
    console.log("No missed words yet.\n");
    return;
  }
  await flashcards([...new Map(missed.map((entry) => [entry.vietnamese, entry])).values()]);
}

async function mainMenu() {
  console.log(`Vietnamese Learning Lab (${vocabulary.length} entries)`);
  while (true) {
    console.log("\n1. Flashcards");
    console.log("2. Multiple choice");
    console.log("3. Reverse lookup");
    console.log("4. Spelling practice");
    console.log("5. Topic review");
    console.log("6. 20-question mixed quiz");
    console.log("7. Missed-word review");
    console.log("8. Final summary and exit");
    const choice = await ask("Choose a mode: ");
    if (choice === "1") await flashcards();
    else if (choice === "2") await multipleChoice();
    else if (choice === "3") await reverseLookup();
    else if (choice === "4") await spellingPractice();
    else if (choice === "5") await topicReview();
    else if (choice === "6") await mixedQuiz();
    else if (choice === "7") await missedWordReview();
    else if (choice === "8") break;
    else console.log("Choose a number from 1 to 8.");
  }
  printSummary();
  rl.close();
}

mainMenu().catch((error) => {
  console.error(error.message);
  rl.close();
  process.exitCode = 1;
});
JS_TAIL
  } >"$artifact_path"

  {
    printf 'OnlyMacs assembled %s from %s validated remote data chunks.\n' "$filename" "$(orchestrated_chunk_count "$original_prompt")"
    printf 'Artifact: %s\n' "$artifact_path"
    printf 'Entries: %s\n' "$actual_count"
  } >"$raw_path"

  validate_return_artifact "$artifact_path" "$original_prompt"
  validation_status="${ONLYMACS_RETURN_VALIDATION_STATUS:-skipped}"
  validation_message="${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
  if [[ "$validation_status" == "failed" ]]; then
    ONLYMACS_ORCHESTRATION_FAILURE_STATUS="failed_validation"
    ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE="$validation_message"
    orchestrated_update_plan_step "$step_id" "failed_validation" 0 "$artifact_path" "$raw_path" "$validation_status" "$validation_message" "" "OnlyMacs local assembler" "local" "failed"
    return 1
  fi

  root_artifact="${ONLYMACS_CURRENT_RETURN_DIR}/files/${filename}"
  cp "$artifact_path" "$root_artifact"
  orchestrated_record_artifact "$root_artifact" "$filename" "$step_id"
  orchestrated_update_plan_step "$step_id" "completed" 0 "$artifact_path" "$raw_path" "$validation_status" "$validation_message" "" "OnlyMacs local assembler" "local" "running"
  return 0
}

orchestrated_write_result_summary() {
  local result_path="${ONLYMACS_CURRENT_RETURN_DIR}/RESULT.md"
  local step_dir step_id
  : >"$result_path"
  for step_dir in "${ONLYMACS_CURRENT_RETURN_DIR}"/steps/step-*; do
    [[ -d "$step_dir" ]] || continue
    step_id="$(basename "$step_dir")"
    printf '## %s\n\n' "$step_id" >>"$result_path"
    if [[ -f "$step_dir/RESULT.md" ]]; then
      cat "$step_dir/RESULT.md" >>"$result_path"
      printf '\n\n' >>"$result_path"
    fi
  done
  printf '%s' "$result_path"
}

orchestrated_token_estimate_for_path() {
  local path="${1:-}"
  local bytes
  [[ -f "$path" ]] || {
    printf '0'
    return 0
  }
  bytes="$(wc -c <"$path" | tr -d ' ')"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
  printf '%s' $(((bytes + 3) / 4))
}

orchestrated_token_estimate_for_paths_json() {
  local paths_json="${1:-[]}"
  local total_bytes=0 path bytes
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    bytes="$(wc -c <"$path" | tr -d ' ')"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    total_bytes=$((total_bytes + bytes))
  done < <(jq -r '.[]? // empty' <<<"$paths_json" 2>/dev/null || true)
  printf '%s' $(((total_bytes + 3) / 4))
}

orchestrated_local_orchestration_token_estimate() {
  local run_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}"
  local total_bytes=0 path bytes
  [[ -n "$run_dir" && -d "$run_dir" ]] || {
    printf '0'
    return 0
  }
  for path in "$run_dir/plan.json" "$run_dir/status.json"; do
    [[ -f "$path" ]] || continue
    bytes="$(wc -c <"$path" | tr -d ' ')"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    total_bytes=$((total_bytes + bytes))
  done
  path="$run_dir/events.jsonl"
  if [[ -f "$path" ]]; then
    bytes="$(wc -c <"$path" | tr -d ' ')"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [[ "$bytes" -gt 20000 ]]; then
      bytes=20000
    fi
    total_bytes=$((total_bytes + bytes))
  fi
  printf '%s' $(((total_bytes + 3) / 4))
}

orchestrated_resume_command_for_current_run() {
  if [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" ]]; then
    printf '%s resume-run %s' "${ONLYMACS_WRAPPER_NAME:-onlymacs}" "$ONLYMACS_CURRENT_RETURN_DIR"
  else
    printf '%s resume-run latest' "${ONLYMACS_WRAPPER_NAME:-onlymacs}"
  fi
}

orchestrated_canonical_artifacts_json() {
  local artifacts_json="${1:-[]}"
  local plan_path="${2:-$(orchestrated_plan_path)}"
  local files_dir="${ONLYMACS_CURRENT_RETURN_DIR:-}/files"
  local root_path

  {
    jq -r '.[]? // empty' <<<"$artifacts_json" 2>/dev/null || true
    if [[ -f "$plan_path" ]]; then
      jq -r '.steps[]?.artifact_path // empty' "$plan_path" 2>/dev/null || true
    fi
  } | while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    root_path="${files_dir}/$(basename "$path")"
    if [[ -f "$root_path" ]]; then
      printf '%s\n' "$root_path"
    elif [[ -f "$path" ]]; then
      printf '%s\n' "$path"
    fi
  done | awk '!seen[$0]++' | jq -R . | jq -s -c .
}

orchestrated_artifact_manifest_json() {
  local artifacts_json="${1:-[]}"
  local manifest_json="${ONLYMACS_ORCHESTRATED_ARTIFACT_MANIFEST_JSON:-[]}"
  jq -cn --argjson paths "$artifacts_json" --argjson manifest "$manifest_json" '
    ($manifest | map(select(.path != null and (.path | length) > 0))) as $known
    | ($known | map(.path)) as $known_paths
    | $known + ($paths | map(select(. as $path | $known_paths | index($path) | not) | {
        path: .,
        filename: (. | split("/")[-1]),
        target_path: (. | split("/")[-1]),
        kind: (if test("\\.(patch|diff)$") then "patch" else "file" end),
        review_command: (if test("\\.(patch|diff)$") then "git apply --check \"" + . + "\"" else "diff -u \"" + (. | split("/")[-1]) + "\" \"" + . + "\"" end)
      }))
  '
}

onlymacs_suggest_review_command() {
  local artifact_path="${1:-}"
  local status_path="${2:-${ONLYMACS_CURRENT_RETURN_DIR:-}/status.json}"
  local plan_path="${3:-$(orchestrated_plan_path)}"
  if [[ -n "$artifact_path" && -f "$artifact_path" ]]; then
    case "$artifact_path" in
      *.json)
        printf 'jq length "%s" && jq . "%s" >/dev/null' "$artifact_path" "$artifact_path"
        ;;
      *.js|*.cjs|*.mjs)
        printf 'node --check "%s"' "$artifact_path"
        ;;
      *.ts|*.tsx)
        printf 'sed -n '\''1,120p'\'' "%s"' "$artifact_path"
        ;;
      *.md|*.txt)
        printf 'sed -n '\''1,120p'\'' "%s"' "$artifact_path"
        ;;
      *.patch|*.diff)
        printf 'git apply --check "%s"' "$artifact_path"
        ;;
      *)
        printf 'ls -lh "%s"' "$artifact_path"
        ;;
    esac
    return 0
  fi
  if [[ -f "$status_path" ]]; then
    printf '%s inbox "%s"' "${ONLYMACS_WRAPPER_NAME:-onlymacs}" "${ONLYMACS_CURRENT_RETURN_DIR:-latest}"
  elif [[ -f "$plan_path" ]]; then
    printf 'jq .progress "%s"' "$plan_path"
  else
    printf '%s diagnostics latest' "${ONLYMACS_WRAPPER_NAME:-onlymacs}"
  fi
}

orchestrated_finalize_status() {
  local status_value="${1:-completed}"
  local prompt="${2:-}"
  local model_alias="${3:-}"
  local route_scope="${4:-swarm}"
  local result_path plan_path status_path manifest_path latest_path now artifact_path recorded_artifacts_json artifacts_json artifact_manifest_json artifact_count step_count completed_count next_step failure_message
  local prompt_path progress_json resume_step resume_step_index session_id provider_id provider_name model prompt_tokens output_tokens total_remote_tokens local_orchestration_tokens saved_tokens_estimate resume_command timeout_policy_json suggested_review_command validator_version execution_settings_json failure_class

  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  plan_path="$(orchestrated_plan_path)"
  prompt_path="$(orchestrated_prompt_path)"
  result_path="$(orchestrated_write_result_summary)"
  status_path="${ONLYMACS_CURRENT_RETURN_DIR}/status.json"
  manifest_path="${ONLYMACS_CURRENT_RETURN_DIR}/result.json"
  latest_path="$(dirname "$ONLYMACS_CURRENT_RETURN_DIR")/latest.json"
  recorded_artifacts_json="${ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON:-[]}"
  artifacts_json="$(orchestrated_canonical_artifacts_json "$recorded_artifacts_json" "$plan_path")"
  if [[ "$(jq -r 'length' <<<"$artifacts_json" 2>/dev/null || printf '0')" == "0" ]]; then
    artifacts_json="$recorded_artifacts_json"
  fi
  artifact_manifest_json="$(orchestrated_artifact_manifest_json "$artifacts_json")"
  artifact_count="$(jq -r 'length' <<<"$artifacts_json" 2>/dev/null || printf '0')"
  artifact_path="$(jq -r '.[0] // empty' <<<"$artifacts_json")"
  step_count="$(jq -r '.steps | length' "$plan_path" 2>/dev/null || printf '0')"
  completed_count="$(jq -r '[.steps[]? | select(.status == "completed")] | length' "$plan_path" 2>/dev/null || printf '0')"
  progress_json="$(jq -c '.progress // {}' "$plan_path" 2>/dev/null || printf '{}')"
  resume_step="$(jq -r '.resume_step // empty' "$plan_path" 2>/dev/null || true)"
  resume_step_index="$(jq -r '.resume_step_index // 0' "$plan_path" 2>/dev/null || printf '0')"
  session_id="$(jq -r '.session_id // empty' "$status_path" 2>/dev/null || true)"
  [[ -z "$session_id" ]] && session_id="${ONLYMACS_LAST_CHAT_SESSION_ID:-}"
  provider_id="$(jq -r '[.steps[]? | select(.provider_id != null) | .provider_id] | last // empty' "$plan_path" 2>/dev/null || true)"
  provider_name="$(jq -r '[.steps[]? | select(.provider_name != null) | .provider_name] | last // empty' "$plan_path" 2>/dev/null || true)"
  model="$(jq -r '[.steps[]? | select(.model != null) | .model] | last // empty' "$plan_path" 2>/dev/null || true)"
  [[ -z "$provider_id" ]] && provider_id="$(jq -r '.provider_id // empty' "$status_path" 2>/dev/null || true)"
  [[ -z "$provider_name" ]] && provider_name="$(jq -r '.owner_member_name // .provider_name // empty' "$status_path" 2>/dev/null || true)"
  [[ -z "$model" ]] && model="$(jq -r '.model // empty' "$status_path" 2>/dev/null || true)"
  [[ -z "$provider_id" ]] && provider_id="${ONLYMACS_LAST_CHAT_PROVIDER_ID:-}"
  [[ -z "$provider_name" ]] && provider_name="${ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME:-${ONLYMACS_LAST_CHAT_PROVIDER_NAME:-}}"
  [[ -z "$model" ]] && model="${ONLYMACS_LAST_CHAT_RESOLVED_MODEL:-}"
  prompt_tokens="$(orchestrated_token_estimate_for_path "$prompt_path")"
  output_tokens="$(orchestrated_token_estimate_for_paths_json "$artifacts_json")"
  total_remote_tokens=$((prompt_tokens + output_tokens))
  local_orchestration_tokens="$(orchestrated_local_orchestration_token_estimate)"
  saved_tokens_estimate="$output_tokens"
  resume_command="$(orchestrated_resume_command_for_current_run)"
  timeout_policy_json="$(onlymacs_timeout_policy_json)"
  if [[ -f "$plan_path" ]]; then
    local plan_timeout_policy_json
    plan_timeout_policy_json="$(jq -c '.timeout_policy // .execution_settings.timeout_policy // empty' "$plan_path" 2>/dev/null || true)"
    if [[ -n "$plan_timeout_policy_json" && "$plan_timeout_policy_json" != "null" ]]; then
      timeout_policy_json="$plan_timeout_policy_json"
    fi
  fi
  suggested_review_command="$(onlymacs_suggest_review_command "$artifact_path" "$status_path" "$plan_path")"
  validator_version="$(jq -r '.validator_version // .execution_settings.validator_version // empty' "$plan_path" 2>/dev/null || true)"
  [[ -z "$validator_version" ]] && validator_version="$(onlymacs_validator_version)"
  execution_settings_json="$(jq -c '.execution_settings // {}' "$plan_path" 2>/dev/null || printf '{}')"
  failure_message="${ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE:-}"
  failure_class=""
  if [[ -n "$failure_message" ]]; then
    failure_class="$(onlymacs_classify_failure "$failure_message" "" "")"
  fi
  case "$status_value" in
    completed)
      next_step="Review the saved artifacts locally before integrating them into the project."
      ;;
    queued)
      next_step="OnlyMacs saved this run after a capacity or transport interruption. Resume from the checkpoint when the route is healthy: ${resume_command}"
      ;;
    blocked)
      next_step="OnlyMacs saved the checkpoint but cannot continue until the route or provider is healthy. Retry later, or switch routes if local fallback is acceptable."
      ;;
    partial)
      next_step="OnlyMacs preserved partial output. Inspect the partial result, then resume from the saved step if replay is safe: ${resume_command}"
      ;;
    failed_validation)
      next_step="OnlyMacs stopped at the resume_step in plan.json after validation failed. Inspect the failed step artifact and retry or repair from that step."
      ;;
    churn)
      next_step="OnlyMacs stopped after bounded repair and reroute attempts did not converge. Inspect the failed step in plan.json before retrying with narrower instructions."
      ;;
    *)
      next_step="OnlyMacs stopped at the resume_step in plan.json. Inspect the failed step status and retry from that step."
      ;;
  esac

  if [[ -f "$plan_path" ]]; then
    jq --arg status "$status_value" --arg updated_at "$now" --arg failure_message "$failure_message" \
      '.status = $status
       | .updated_at = $updated_at
       | .progress = ((.progress // {}) + {phase: $status, updated_at: $updated_at})
       | (if ($failure_message | length) > 0 then .failure_message = $failure_message else . end)' "$plan_path" >"${plan_path}.tmp" && mv "${plan_path}.tmp" "$plan_path"
    progress_json="$(jq -c '.progress // {}' "$plan_path" 2>/dev/null || printf '{}')"
  fi

  jq -n \
    --arg status "$status_value" \
    --arg run_id "${ONLYMACS_CURRENT_RETURN_RUN_ID:-}" \
    --arg started_at "${ONLYMACS_CURRENT_RETURN_STARTED_AT:-$now}" \
    --arg updated_at "$now" \
    --arg completed_at "$now" \
    --arg model_alias "$model_alias" \
    --arg route_scope "$route_scope" \
    --arg session_id "$session_id" \
    --arg inbox "${ONLYMACS_CURRENT_RETURN_DIR:-}" \
    --arg files_dir "${ONLYMACS_CURRENT_RETURN_DIR:-}/files" \
    --arg plan_path "$plan_path" \
    --arg prompt_path "$prompt_path" \
    --arg result_path "$result_path" \
    --arg artifact_path "$artifact_path" \
    --arg provider_id "$provider_id" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg failure_message "$failure_message" \
    --arg failure_class "$failure_class" \
    --arg next_step "$next_step" \
    --arg resume_step "$resume_step" \
    --arg resume_command "$resume_command" \
    --arg suggested_review_command "$suggested_review_command" \
    --arg validator_version "$validator_version" \
    --argjson artifacts "$artifacts_json" \
    --argjson artifact_targets "$artifact_manifest_json" \
    --argjson steps_total "${step_count:-0}" \
    --argjson steps_completed "${completed_count:-0}" \
    --argjson resume_step_index "${resume_step_index:-0}" \
    --argjson progress "$progress_json" \
    --argjson timeout_policy "$timeout_policy_json" \
    --argjson execution_settings "$execution_settings_json" \
    --argjson prompt_tokens "${prompt_tokens:-0}" \
    --argjson output_tokens "${output_tokens:-0}" \
    --argjson total_remote_tokens "${total_remote_tokens:-0}" \
    --argjson local_orchestration_tokens "${local_orchestration_tokens:-0}" \
    --argjson saved_tokens_estimate "${saved_tokens_estimate:-0}" \
    '{
      status: $status,
      run_id: $run_id,
      started_at: $started_at,
      updated_at: $updated_at,
      completed_at: $completed_at,
      session_id: ($session_id | if length > 0 then . else null end),
      model_alias: ($model_alias | if length > 0 then . else null end),
      route_scope: $route_scope,
      provider_id: ($provider_id | if length > 0 then . else null end),
      provider_name: ($provider_name | if length > 0 then . else null end),
      model: ($model | if length > 0 then . else null end),
      inbox: $inbox,
      files_dir: $files_dir,
      plan_path: $plan_path,
      prompt_path: $prompt_path,
      result_path: $result_path,
      artifact_path: ($artifact_path | if length > 0 then . else null end),
      artifacts: $artifacts,
      artifact_targets: $artifact_targets,
      progress: $progress,
      timeout_policy: $timeout_policy,
      execution_settings: $execution_settings,
      validator_version: $validator_version,
      failure_message: ($failure_message | if length > 0 then . else null end),
      failure_class: ($failure_class | if length > 0 then . else null end),
      steps: {
        completed: $steps_completed,
        total: $steps_total,
        resume_step: ($resume_step | if length > 0 then . else null end),
        resume_step_index: (if ($resume_step_index | type) == "number" and $resume_step_index > 0 then $resume_step_index else null end)
      },
      token_accounting: {
        prompt_tokens_estimate: $prompt_tokens,
        output_tokens_estimate: $output_tokens,
        remote_work_tokens_estimate: $total_remote_tokens,
        total_remote_tokens_estimate: $total_remote_tokens,
        local_orchestration_tokens_estimate: $local_orchestration_tokens,
        estimated_codex_tokens_avoided: $saved_tokens_estimate,
        method: "rough bytes/4 estimate for saved prompt, artifacts, and local orchestration metadata"
      },
      resume_command: (if ($status != "completed") then $resume_command else null end),
      suggested_review_command: $suggested_review_command,
      next_step: $next_step
    }' >"$status_path"
  cp "$status_path" "$manifest_path"
  jq -n \
    --arg run_id "${ONLYMACS_CURRENT_RETURN_RUN_ID:-}" \
    --arg status "$status_value" \
    --arg updated_at "$now" \
    --arg inbox "${ONLYMACS_CURRENT_RETURN_DIR:-}" \
    --arg artifact_path "$artifact_path" \
    --arg status_path "$status_path" \
    --arg manifest_path "$manifest_path" \
    --arg plan_path "$plan_path" \
    --arg prompt_path "$prompt_path" \
    --arg provider_name "$provider_name" \
    --arg model "$model" \
    --arg failure_message "$failure_message" \
    --arg resume_command "$resume_command" \
    --arg suggested_review_command "$suggested_review_command" \
    --argjson artifacts "$artifacts_json" \
    --argjson artifact_targets "$artifact_manifest_json" \
    '{run_id:$run_id,status:$status,updated_at:$updated_at,inbox:$inbox,artifact_path:($artifact_path | if length > 0 then . else null end),artifacts:$artifacts,artifact_targets:$artifact_targets,status_path:$status_path,manifest_path:$manifest_path,plan_path:$plan_path,prompt_path:$prompt_path,provider_name:($provider_name | if length > 0 then . else null end),model:($model | if length > 0 then . else null end),failure_message:($failure_message | if length > 0 then . else null end),resume_command:(if ($status != "completed") then $resume_command else null end),suggested_review_command:$suggested_review_command}' >"$latest_path"
  if [[ "$status_value" == "completed" ]]; then
    onlymacs_log_run_event "run_completed" "" "$status_value" "0" "OnlyMacs completed the orchestrated job." "$artifact_path" "$provider_id" "$provider_name" "$model" "$result_path" "$status_path"
  else
    if [[ "$status_value" == "failed" || "$status_value" == "failed_validation" || "$status_value" == "churn" ]]; then
      onlymacs_log_run_event "run_failed" "$resume_step" "$status_value" "0" "$failure_message" "$artifact_path" "$provider_id" "$provider_name" "$model" "$result_path" "$status_path"
    fi
    onlymacs_log_run_event "run_stopped" "$resume_step" "$status_value" "0" "$failure_message" "$artifact_path" "$provider_id" "$provider_name" "$model" "$result_path" "$status_path"
  fi
  onlymacs_auto_report_public_run "${ONLYMACS_CURRENT_RETURN_DIR:-}"

  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    if [[ "$status_value" == "completed" ]]; then
      printf '\n\nOnlyMacs completed orchestrated job.\n'
    else
      printf '\n\nOnlyMacs stopped orchestrated job (%s).\n' "$status_value"
      if [[ -n "$failure_message" ]]; then
        printf 'Reason: %s\n' "$failure_message"
      fi
    fi
    printf 'Steps: %s/%s completed\n' "$completed_count" "$step_count"
    if [[ -n "$provider_name" || -n "$model" ]]; then
      if [[ -n "$provider_name" && -n "$model" ]]; then
        printf 'Provider/model: %s / %s\n' "$provider_name" "$model"
      else
        printf 'Provider/model: %s%s\n' "$provider_name" "$model"
      fi
    fi
    printf 'Remote token estimate: %s total (%s prompt + %s saved output)\n' "${total_remote_tokens:-0}" "${prompt_tokens:-0}" "${output_tokens:-0}"
    printf 'Local orchestration token estimate: %s; estimated Codex tokens avoided: %s\n' "${local_orchestration_tokens:-0}" "${saved_tokens_estimate:-0}"
    if [[ "$artifact_count" == "1" && -n "$artifact_path" ]]; then
      printf 'Saved file: %s\n' "$artifact_path"
    elif [[ "$artifact_count" -gt 1 ]]; then
      printf 'Saved files:\n'
      jq -r '.[]' <<<"$artifacts_json" | while IFS= read -r saved_path; do
        printf '  - %s\n' "$saved_path"
      done
    fi
    printf 'Plan: %s\nFull remote answer: %s\nInbox: %s\nStatus: %s\n' "$plan_path" "$result_path" "${ONLYMACS_CURRENT_RETURN_DIR:-}" "$status_path"
    if [[ "$status_value" != "completed" ]]; then
      printf 'Resume: %s\n' "$resume_command"
    fi
    printf 'Review: %s\n' "$suggested_review_command"
    printf 'Next: %s\n' "$next_step"
  fi
}

run_orchestrated_chat() {
  local model="${1:-}"
  local model_alias="${2:-}"
  local prompt="${3:-}"
  local route_scope="${4:-swarm}"
  local step_count idx requested_provider_id

  prepare_chat_return_run "$model_alias" "$prompt" "$route_scope"
  activate_auto_plan_for_prompt "$prompt"
  requested_provider_id="${ONLYMACS_ORCHESTRATION_PROVIDER_ID:-}"
  if [[ -n "$requested_provider_id" ]]; then
    ONLYMACS_ORCHESTRATION_PROVIDER_ID="$requested_provider_id"
    ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=1
  else
    ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
    ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=0
  fi
  ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="[]"
  ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="[]"
  : "${ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT:=0}"
  ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON="[]"
  ONLYMACS_ORCHESTRATION_FAILURE_STATUS=""
  ONLYMACS_ORCHESTRATION_FAILURE_MESSAGE=""
  step_count="$(orchestrated_step_count "$prompt")"
  orchestrated_write_plan "$prompt" "$model_alias" "$route_scope" "$step_count"

  for ((idx = 1; idx <= step_count; idx++)); do
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
