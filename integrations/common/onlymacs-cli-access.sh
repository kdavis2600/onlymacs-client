# Request policy, file-access approval, and context artifact helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after routing helpers are loaded.

prompt_looks_sensitive() {
  local lowered
  lowered="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  lowered="${lowered//non-secret/}"
  lowered="${lowered//non secret/}"
  lowered="${lowered//not secret/}"
  lowered="${lowered//token-free/}"
  lowered="${lowered//token free/}"
  lowered="${lowered//paid tokens/}"
  lowered="${lowered//paid token/}"
  lowered="${lowered//spend tokens/}"
  lowered="${lowered//save tokens/}"
  string_has_any "$lowered" \
    "password" \
    "secret" \
    "api key" \
    "apikey" \
    "token" \
    "private key" \
    "ssh key" \
    "credential" \
    ".env" \
    "access key"
}

prompt_declares_prompt_only() {
  local lowered
  lowered="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "prompt-only" \
    "prompt only" \
    "self-contained prompt" \
    "use only the facts inside this message" \
    "do not ask for local repository access" \
    "do not ask for local repo access" \
    "do not ask for local files" \
    "do not use local files"
}

prompt_looks_file_bound() {
  local lowered
  lowered="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  if prompt_declares_prompt_only "$lowered"; then
    return 1
  fi
  if string_has_any "$lowered" \
    "review my code" \
    "review my project" \
    "code review on my project" \
    "review this repo" \
    "review this codebase" \
    "review this project" \
    "project folder" \
    "workspace" \
    "this branch" \
    "current branch" \
    "current project" \
    "current folder" \
    "project files" \
    "source files" \
    "local checkout" \
    "working tree" \
    "working copy" \
    "test suite" \
    "run tests" \
    "run the tests" \
    "unit tests" \
    "check the tests" \
    "uploaded file" \
    "attached file" \
    "this upload" \
    "attached pdf" \
    "screenshot i attached" \
    "this spreadsheet" \
    "attached screenshot" \
    "repo" \
    "repository" \
    "codebase" \
    "source tree" \
    "local file" \
    "package.json" \
    "tsconfig" \
    "rearrange this file" \
    "rearrange this json" \
    "edit this file" \
    "rewrite this file" \
    "apply this patch" \
    "open the files" \
    "scan this project" \
    "content pipeline" \
    "pipeline docs"; then
    return 0
  fi

  if [[ "$lowered" == *"this project"* ]] && string_has_any "$lowered" "docs" "files" "schema" "json" "pipeline" "readme"; then
    return 0
  fi

  if [[ "$lowered" == *"current project"* ]] && string_has_any "$lowered" "architecture" "docs" "files" "schema" "json" "pipeline" "readme" "review"; then
    return 0
  fi

  if [[ "$lowered" == *"the project"* ]] && string_has_any "$lowered" "fix" "errors" "typescript" "tests" "files" "source" "architecture" "docs"; then
    return 0
  fi

  if [[ "$lowered" == *"workspace"* ]] && string_has_any "$lowered" "docs" "files" "schema" "json" "pipeline" "readme"; then
    return 0
  fi

  if [[ "$lowered" == *"repo"* || "$lowered" == *"repository"* ]] && string_has_any "$lowered" "docs" "files" "schema" "json" "pipeline" "readme"; then
    return 0
  fi

  if string_has_any "$lowered" "look at" "open " "read " "inspect" "review" "analyze" "use " "process" "summarize" "clean"; then
    if [[ "$lowered" =~ (^|[[:space:]])[A-Za-z0-9._/-]+\.(json|js|ts|tsx|jsx|md|txt|csv|yml|yaml|xml|html|css|py|go|swift|toml|lock|rb|sql)([[:space:][:punct:]]|$) ]]; then
      return 0
    fi
    if [[ "$lowered" =~ (^|[[:space:]])(readme|cargo|gemfile|package|tsconfig|pyproject|requirements)\.(md|toml|lock|json|txt)([[:space:][:punct:]]|$) ]]; then
      return 0
    fi
  fi

  if [[ "$lowered" =~ (^|[[:space:]:])(\./|\../|~/|/)[^[:space:]]+\.(json|js|ts|md|txt|csv|yml|yaml|xml|html|css|py|go|swift)([[:space:][:punct:]]|$) ]]; then
    return 0
  fi

  if [[ "$lowered" == *".json"* ]] && string_has_any "$lowered" "this json file" "local json file" "existing json file" "translate this" "process this" "convert this"; then
    return 0
  fi

  return 1
}

prompt_looks_trivial() {
  local lowered
  lowered="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  if string_has_any "$lowered" "review" "debug" "bug" "refactor" "audit" "migration" "test failure" "failing test" "concurrency"; then
    return 1
  fi
  string_has_any "$lowered" \
    "summarize" \
    "summary" \
    "classify" \
    "tag these" \
    "rename these" \
    "sort these" \
    "translate" \
    "categorize"
}

launch_advisories_text() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local lowered_model

  if [[ "$ONLYMACS_JSON_MODE" -eq 1 || -z "$prompt" ]]; then
    return 0
  fi

  lowered_model="$(printf '%s' "$model_alias" | tr '[:upper:]' '[:lower:]')"

  if prompt_looks_sensitive "$prompt" && ! string_has_any "$lowered_model" "local-first" "local" "trusted-only" "trusted" "offload-max"; then
    printf 'OnlyMacs note: this request looks sensitive. Consider a `local-first` or `trusted-only` route before sending secrets into a swarm.\n\n'
  fi

  if prompt_looks_trivial "$prompt" && string_has_any "$lowered_model" "best" "coder" "precise" "qwen2.5-coder:32b" "qwen" "gemma4" "gemma-4"; then
    printf 'OnlyMacs note: this request looks lightweight. You may not need a scarce premium model or beast-capacity slot for it.\n\n'
  fi
}

active_swarm_id_from_status() {
  local body="$1"
  jq -r '.runtime.active_swarm_id // empty' <<<"$body"
}

active_swarm_name_from_status() {
  local body="$1"
  local active_swarm_id swarm_name
  active_swarm_id="$(active_swarm_id_from_status "$body")"
  if [[ -z "$active_swarm_id" ]]; then
    printf ''
    return 0
  fi
  swarm_name="$(jq -r --arg active_swarm_id "$active_swarm_id" '.swarms[]? | select(.id == $active_swarm_id) | .name' <<<"$body" | head -n 1)"
  if [[ -n "$swarm_name" ]]; then
    printf '%s' "$swarm_name"
    return 0
  fi
  if [[ "$active_swarm_id" == "swarm-public" ]]; then
    printf 'OnlyMacs Public'
    return 0
  fi
  printf '%s' "$active_swarm_id"
}

active_swarm_visibility_from_status() {
  local body="$1"
  local active_swarm_id visibility
  active_swarm_id="$(active_swarm_id_from_status "$body")"
  if [[ -z "$active_swarm_id" ]]; then
    printf 'unknown'
    return 0
  fi
  visibility="$(jq -r --arg active_swarm_id "$active_swarm_id" '.swarms[]? | select(.id == $active_swarm_id) | .visibility' <<<"$body" | head -n 1)"
  if [[ -n "$visibility" && "$visibility" != "null" ]]; then
    printf '%s' "$visibility"
    return 0
  fi
  if [[ "$active_swarm_id" == "swarm-public" ]]; then
    printf 'public'
    return 0
  fi
  printf 'unknown'
}

ONLYMACS_REQUEST_POLICY_DECISION=""
ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES=""
ONLYMACS_REQUEST_POLICY_REASONS=""
ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_NAME=""
ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_VISIBILITY=""
ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND=""
ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET=""
ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION=""
ONLYMACS_REQUEST_POLICY_TASK_KIND=""
ONLYMACS_REQUEST_POLICY_FILE_ACCESS_MODE=""
ONLYMACS_REQUEST_POLICY_TRUST_TIER=""
ONLYMACS_REQUEST_POLICY_ALLOW_CONTEXT_REQUESTS=""
ONLYMACS_REQUEST_POLICY_MAX_CONTEXT_REQUEST_ROUNDS=""
ONLYMACS_REQUEST_POLICY_USER_FACING_WARNING=""
ONLYMACS_REQUEST_POLICY_SUGGESTED_CONTEXT_PACKS_JSON="[]"
ONLYMACS_REQUEST_POLICY_SUGGESTED_FILES_JSON="[]"

request_policy_classify() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local payload

  payload="$(jq -n \
    --arg prompt "$prompt" \
    --arg route_scope "$(route_scope_for_alias "$model_alias")" \
    '{prompt:$prompt, route_scope:$route_scope}')"

  request_json POST "/admin/v1/request-policy/classify" "$payload" || return 1
  require_success "OnlyMacs could not classify this request." || return 1

  ONLYMACS_REQUEST_POLICY_DECISION="$(jq -r '.decision // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES="$(jq -r '.classification.requires_local_files // false' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_REASONS="$(jq -r '.reasons[]? // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_NAME="$(jq -r '.active_swarm_name // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_VISIBILITY="$(jq -r '.active_swarm_visibility // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="$(jq -r '.routing.suggested_command // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="$(jq -r '.routing.suggested_preset // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="$(jq -r '.routing.explanation // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_TASK_KIND="$(jq -r '.classification.task_kind // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_FILE_ACCESS_MODE="$(jq -r '.file_access_plan.mode // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_TRUST_TIER="$(jq -r '.file_access_plan.trust_tier // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_ALLOW_CONTEXT_REQUESTS="$(jq -r '.file_access_plan.allow_context_requests // false' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_MAX_CONTEXT_REQUEST_ROUNDS="$(jq -r '.file_access_plan.max_context_request_rounds // 0' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_USER_FACING_WARNING="$(jq -r '.file_access_plan.user_facing_warning // empty' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_SUGGESTED_CONTEXT_PACKS_JSON="$(jq -c '.file_access_plan.suggested_context_packs // []' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  ONLYMACS_REQUEST_POLICY_SUGGESTED_FILES_JSON="$(jq -c '.file_access_plan.suggested_files // []' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  return 0
}

evaluate_file_access_policy() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local status_body="${3:-}"
  local route_scope visibility

  if ! prompt_looks_file_bound "$prompt"; then
    printf 'not_file_bound'
    return 0
  fi

  route_scope="$(route_scope_for_alias "$model_alias")"
  if [[ "$route_scope" == "local_only" ]]; then
    printf 'allow_local'
    return 0
  fi

  visibility="$(active_swarm_visibility_from_status "$status_body")"
  case "$visibility" in
    public)
      printf 'block_public'
      ;;
    private)
      printf 'allow_private'
      ;;
    *)
      printf 'block_unverified'
      ;;
  esac
}

write_file_access_request() {
  local request_id="${1:-}"
  local model_alias="${2:-}"
  local prompt="${3:-}"
  local status_body="${4:-}"
  local context_request_summary="${5:-}"
  local context_request_round="${6:-0}"
  local state_dir request_path created_at swarm_name

  state_dir="$(file_access_state_dir)"
  request_path="$(file_access_request_path "$request_id")"
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  swarm_name="$(active_swarm_name_from_status "$status_body")"

  mkdir -p "$state_dir"
  jq -n \
    --arg id "$request_id" \
    --arg created_at "$created_at" \
    --arg workspace_id "$(default_workspace_id)" \
    --arg workspace_root "$PWD" \
    --arg thread_id "$(default_thread_id)" \
    --arg prompt "$prompt" \
    --arg task_kind "${ONLYMACS_REQUEST_POLICY_TASK_KIND:-}" \
    --arg route_scope "$(route_scope_for_alias "$model_alias")" \
    --arg tool_name "$ONLYMACS_TOOL_NAME" \
    --arg wrapper_name "$ONLYMACS_WRAPPER_NAME" \
    --arg swarm_name "$swarm_name" \
    --arg file_access_mode "${ONLYMACS_REQUEST_POLICY_FILE_ACCESS_MODE:-}" \
    --arg trust_tier "${ONLYMACS_REQUEST_POLICY_TRUST_TIER:-}" \
    --arg user_facing_warning "${ONLYMACS_REQUEST_POLICY_USER_FACING_WARNING:-}" \
    --arg context_request_summary "$context_request_summary" \
    --arg lease_id "${ONLYMACS_RESOLVED_LEASE_ID:-}" \
    --argjson allow_context_requests "$(bool_is_true "${ONLYMACS_REQUEST_POLICY_ALLOW_CONTEXT_REQUESTS:-false}" && printf 'true' || printf 'false')" \
    --argjson max_context_request_rounds "${ONLYMACS_REQUEST_POLICY_MAX_CONTEXT_REQUEST_ROUNDS:-0}" \
    --argjson suggested_context_packs "${ONLYMACS_REQUEST_POLICY_SUGGESTED_CONTEXT_PACKS_JSON:-[]}" \
    --argjson suggested_files "${ONLYMACS_REQUEST_POLICY_SUGGESTED_FILES_JSON:-[]}" \
    --argjson seed_selected_paths "${ONLYMACS_RESOLVED_SELECTED_PATHS_JSON:-[]}" \
    --argjson context_request_round "$context_request_round" \
    '{
      id: $id,
      created_at: $created_at,
      workspace_id: $workspace_id,
      workspace_root: $workspace_root,
      thread_id: $thread_id,
      prompt: $prompt,
      task_kind: ($task_kind | select(length > 0)),
      route_scope: $route_scope,
      tool_name: $tool_name,
      wrapper_name: $wrapper_name,
      swarm_name: ($swarm_name | select(length > 0)),
      file_access_mode: ($file_access_mode | select(length > 0)),
      trust_tier: ($trust_tier | select(length > 0)),
      allow_context_requests: $allow_context_requests,
      max_context_request_rounds: $max_context_request_rounds,
      user_facing_warning: ($user_facing_warning | select(length > 0)),
      suggested_context_packs: $suggested_context_packs,
      suggested_files: $suggested_files,
      seed_selected_paths: $seed_selected_paths,
      context_request_summary: ($context_request_summary | select(length > 0)),
      context_request_round: $context_request_round,
      lease_id: ($lease_id | select(length > 0))
    }' >"$request_path"
}

open_file_access_request_ui() {
  local request_id="${1:-}"
  local bundle_id app_path
  bundle_id="${ONLYMACS_APP_BUNDLE_ID:-com.kizzle.onlymacs}"
  app_path="$(onlymacs_app_bundle_path || true)"

  mkdir -p "$(file_access_state_dir)"

  if pgrep -x "OnlyMacsApp" >/dev/null 2>&1; then
    if [[ -n "$app_path" ]]; then
      open -a "$app_path" >/dev/null 2>&1 || open "$app_path" >/dev/null 2>&1 || true
    else
      open -b "$bundle_id" >/dev/null 2>&1 || true
    fi
  elif [[ -n "$app_path" ]]; then
    open -a "$app_path" >/dev/null 2>&1 || open "$app_path" >/dev/null 2>&1 || true
  else
    open -b "$bundle_id" >/dev/null 2>&1 || true
  fi
  if wait_for_file_access_claim "$request_id" 8; then
    return 0
  fi

  return 1
}

wait_for_file_access_response() {
  local request_id="${1:-}"
  local response_path deadline
  response_path="$(file_access_response_path "$request_id")"
  deadline=$((SECONDS + 300))
  while (( SECONDS < deadline )); do
    if [[ -f "$response_path" ]]; then
      cat "$response_path"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_file_access_claim() {
  local request_id="${1:-}"
  local timeout_seconds="${2:-8}"
  local claim_path deadline
  claim_path="$(file_access_claim_path "$request_id")"
  deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    if [[ -f "$claim_path" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

onlymacs_app_bundle_path() {
  local script_source script_dir current
  if [[ -n "${ONLYMACS_APP_PATH:-}" && -d "${ONLYMACS_APP_PATH:-}" ]]; then
    printf '%s\n' "$ONLYMACS_APP_PATH"
    return 0
  fi

  script_source="${BASH_SOURCE[0]}"
  script_dir="$(cd "$(dirname "$script_source")" && pwd)"
  current="$script_dir"
  while [[ "$current" != "/" ]]; do
    if [[ -f "$current/Contents/Info.plist" ]]; then
      printf '%s\n' "$current"
      return 0
    fi
    current="$(dirname "$current")"
  done

  if [[ -d "/Applications/OnlyMacs.app" ]]; then
    printf '%s\n' "/Applications/OnlyMacs.app"
    return 0
  fi

  return 1
}

run_file_access_flow() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local status_body="${3:-}"
  local context_request_summary="${4:-}"
  local context_request_round="${5:-0}"
  local request_id request_path response_path response_body response_status warnings

  request_id="$(default_file_access_request_id "$model_alias" "$prompt")"
  request_path="$(file_access_request_path "$request_id")"
  response_path="$(file_access_response_path "$request_id")"
  rm -f "$request_path" "$response_path" "$(file_access_claim_path "$request_id")" "$(file_access_manifest_path "$request_id")" "$(file_access_context_path "$request_id")"
  write_file_access_request "$request_id" "$model_alias" "$prompt" "$status_body" "$context_request_summary" "$context_request_round"
  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    if [[ "${ONLYMACS_REQUEST_POLICY_TRUST_TIER:-}" == "public_untrusted" ]]; then
      printf 'OnlyMacs needs approval for a public-safe file capsule.\n'
      printf 'Open the approval window in OnlyMacs, choose the exact excerpts to share, and this request will continue here when you approve it.\n\n'
    else
      printf 'OnlyMacs needs approval for local files.\n'
      printf 'Open the approval window in OnlyMacs, choose the files to share with your trusted swarm, and this request will continue here when you approve it.\n\n'
    fi
  fi
  if ! open_file_access_request_ui "$request_id"; then
    rm -f "$request_path" "$response_path" "$(file_access_claim_path "$request_id")" "$(file_access_manifest_path "$request_id")" "$(file_access_context_path "$request_id")"
    printf 'OnlyMacs could not confirm that the approval window opened. Bring OnlyMacs to the front and try again.\n' >&2
    return 1
  fi
  response_body="$(wait_for_file_access_response "$request_id")" || {
    rm -f "$request_path" "$response_path" "$(file_access_claim_path "$request_id")" "$(file_access_manifest_path "$request_id")" "$(file_access_context_path "$request_id")"
    printf 'OnlyMacs timed out waiting for file approval.\n' >&2
    printf 'Next: reopen OnlyMacs, approve the file request, then retry the command.\n' >&2
    return 1
  }
  response_status="$(jq -r '.status // empty' <<<"$response_body")"
  case "$response_status" in
    approved)
      warnings="$(jq -r '.warnings[]? // empty' <<<"$response_body")"
      if ! hydrate_artifact_from_approval_response "$response_body"; then
        clear_resolved_artifact
        printf 'OnlyMacs approved the file request, but the trusted export bundle is missing or incomplete.\n' >&2
        return 1
      fi
      ONLYMACS_RESOLVED_PROMPT="$prompt"
      if [[ -n "$warnings" && "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
        printf 'OnlyMacs note: some selected files were blocked or adjusted before export.\n\n'
      fi
      return 0
      ;;
    rejected)
      clear_resolved_artifact
      printf 'OnlyMacs stopped this request.\n' >&2
      printf '%s\n' "$(jq -r '.message // "You did not approve the file export."' <<<"$response_body")" >&2
      return 1
      ;;
    *)
      clear_resolved_artifact
      printf 'OnlyMacs got an unexpected file approval response.\n' >&2
      return 1
      ;;
  esac
}

hydrate_artifact_from_approval_response() {
  local response_body="${1:-}"
  local bundle_path manifest_path bundle_sha256 export_mode bundle_base64 normalized_manifest artifact_json lease_id

  bundle_path="$(jq -r '.bundle_path // empty' <<<"$response_body")"
  manifest_path="$(jq -r '.manifest_path // empty' <<<"$response_body")"
  bundle_sha256="$(jq -r '.bundle_sha256 // empty' <<<"$response_body")"
  export_mode="$(jq -r '.export_mode // empty' <<<"$response_body")"

  if [[ -z "$bundle_path" || -z "$manifest_path" || ! -f "$bundle_path" || ! -f "$manifest_path" ]]; then
    return 1
  fi

  bundle_base64="$(base64 <"$bundle_path" | tr -d '\n')" || return 1
  normalized_manifest="$(jq -c \
    --arg current_tool "$ONLYMACS_TOOL_NAME" \
    '
    def pick_string($snake; $camel):
      (if .[$snake] != null and .[$snake] != "" then .[$snake]
       elif .[$camel] != null and .[$camel] != "" then .[$camel]
       else "" end);
    def pick_number($snake; $camel):
      (if .[$snake] != null and .[$snake] != 0 then .[$snake]
       elif .[$camel] != null and .[$camel] != 0 then .[$camel]
       else 0 end);
    def normalize_file:
      {
        path: (.path // ""),
        relative_path: pick_string("relative_path"; "relativePath"),
        category: (.category // null),
        selection_reason: (pick_string("selection_reason"; "selectionReason") | select(length > 0)),
        is_recommended: (.is_recommended // .isRecommended // false),
        review_priority: pick_number("review_priority"; "reviewPriority"),
        evidence_hints: (.evidence_hints // .evidenceHints // []),
        evidence_anchors: (.evidence_anchors // .evidenceAnchors // []),
        original_bytes: pick_number("original_bytes"; "originalBytes"),
        exported_bytes: pick_number("exported_bytes"; "exportedBytes"),
        status: (.status // ""),
        reason: (.reason // null),
        sha256: (.sha256 // null)
      };
    .files as $raw_files |
    .blocked as $raw_blocked |
    .context_packs as $raw_context_packs |
    .warnings as $raw_warnings |
    {
      id: (.id // ""),
      schema: pick_string("schema"; "schema"),
      request_id: pick_string("request_id"; "requestID"),
      created_at: pick_string("created_at"; "createdAt"),
      expires_at: pick_string("expires_at"; "expiresAt"),
      workspace_root: pick_string("workspace_root"; "workspaceRoot"),
      workspace_root_label: pick_string("workspace_root_label"; "workspaceRootLabel"),
      workspace_fingerprint: pick_string("workspace_fingerprint"; "workspaceFingerprint"),
      route_scope: pick_string("route_scope"; "routeScope"),
      trust_tier: pick_string("trust_tier"; "trustTier"),
      absolute_paths_included: (.absolute_paths_included // .absolutePathsIncluded // false),
      swarm_name: pick_string("swarm_name"; "swarmName"),
      tool_name: (
        pick_string("tool_name"; "toolName") as $manifest_tool |
        if ($manifest_tool | length) == 0 then
          $current_tool
        elif ($manifest_tool | ascii_downcase) == "onlymacs" and ($current_tool | length) > 0 and ($current_tool | ascii_downcase) != "onlymacs" then
          $current_tool
        else
          $manifest_tool
        end
      ),
      prompt_summary: pick_string("prompt_summary"; "promptSummary"),
      request_intent: pick_string("request_intent"; "requestIntent"),
      export_mode: pick_string("export_mode"; "exportMode"),
      output_contract: pick_string("output_contract"; "outputContract"),
      required_sections: (.required_sections // .requiredSections // []),
      grounding_rules: (.grounding_rules // .groundingRules // []),
      context_request_rules: (.context_request_rules // .contextRequestRules // []),
      permissions: (.permissions // {}),
      budgets: (.budgets // {}),
      lease: (.lease // null),
      workspace: (.workspace // null),
      context_packs: ($raw_context_packs // .contextPacks // []),
      files: [(($raw_files // []))[] | normalize_file],
      blocked: ($raw_blocked // []),
      warnings: ($raw_warnings // []),
      total_selected_bytes: pick_number("total_selected_bytes"; "totalSelectedBytes"),
      total_export_bytes: pick_number("total_export_bytes"; "totalExportBytes")
    }
    ' "$manifest_path")" || return 1
  artifact_json="$(jq -cn \
    --arg export_mode "$export_mode" \
    --arg bundle_base64 "$bundle_base64" \
    --arg bundle_sha256 "$bundle_sha256" \
    --argjson manifest "$normalized_manifest" \
    '{
      export_mode: ($export_mode | select(length > 0)),
      bundle_base64: $bundle_base64,
      bundle_sha256: ($bundle_sha256 | select(length > 0)),
      manifest: $manifest
    }')"

  ONLYMACS_RESOLVED_ARTIFACT_JSON="$artifact_json"
  ONLYMACS_RESOLVED_ARTIFACT_SHA="$bundle_sha256"
  ONLYMACS_RESOLVED_SELECTED_PATHS_JSON="$(jq -c '.selected_paths // []' <<<"$response_body")"
  lease_id="$(jq -r '.manifest.lease.id // .manifest.lease_id // empty' <<<"$artifact_json" 2>/dev/null || true)"
  ONLYMACS_RESOLVED_LEASE_ID="$lease_id"
  return 0
}

resolve_prompt_with_file_access() {
  local model_alias="${1:-}"
  local prompt="${2:-}"
  local status_body policy swarm_name
  local used_request_policy=0

  clear_resolved_artifact

  if [[ -n "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-}" || -n "${ONLYMACS_PLAN_FILE_PATH:-}" ]]; then
    ONLYMACS_RESOLVED_PROMPT="$prompt"
    return 0
  fi

  if request_policy_classify "$model_alias" "$prompt"; then
    used_request_policy=1
    if ! prompt_looks_file_bound "$prompt" && ! bool_is_true "${ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES:-false}"; then
      ONLYMACS_RESOLVED_PROMPT="$prompt"
      return 0
    fi
    case "${ONLYMACS_REQUEST_POLICY_DECISION:-}" in
      allow_current_route)
        if [[ "$(route_scope_for_alias "$model_alias")" == "local_only" ]] \
          && bool_is_true "${ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES:-false}" \
          && prompt_looks_sensitive "$prompt"; then
          printf 'OnlyMacs stopped this request.\n' >&2
          printf 'This request needs local files and looks sensitive, so OnlyMacs is keeping it on This Mac.\n' >&2
          printf 'The `local-first` route is the right route here, but `/onlymacs` does not yet execute sensitive file-aware edits directly on This Mac.\n' >&2
          printf 'Next: review or edit these files directly in Codex on This Mac for now.\n' >&2
          return 1
        fi
        ONLYMACS_RESOLVED_PROMPT="$prompt"
        return 0
        ;;
      local_only_recommended)
        if [[ "$(route_scope_for_alias "$model_alias")" == "local_only" ]]; then
          ONLYMACS_RESOLVED_PROMPT="$prompt"
          return 0
        fi
        printf 'OnlyMacs stopped this request.\n' >&2
        if [[ -n "${ONLYMACS_REQUEST_POLICY_REASONS:-}" ]]; then
          printf '%s\n' "$ONLYMACS_REQUEST_POLICY_REASONS" >&2
        else
          printf 'This request looks sensitive enough that OnlyMacs recommends keeping it on This Mac.\n' >&2
        fi
        printf 'Next: retry with `local-first` if you want to keep this work on This Mac.\n' >&2
        return 1
        ;;
      blocked_public)
        printf 'OnlyMacs stopped this request.\n' >&2
        printf '%s is an open swarm, and open swarms cannot access your local files or repo.\n' "${ONLYMACS_REQUEST_POLICY_ACTIVE_SWARM_NAME:-This swarm}" >&2
        if [[ -n "${ONLYMACS_REQUEST_POLICY_REASONS:-}" ]]; then
          printf '%s\n' "$ONLYMACS_REQUEST_POLICY_REASONS" >&2
        fi
        printf 'Next: use `local-first`, switch to a private swarm, or export the exact files you want reviewed.\n' >&2
        return 1
        ;;
      blocked_unverified)
        printf 'OnlyMacs stopped this request.\n' >&2
        if [[ -n "${ONLYMACS_REQUEST_POLICY_REASONS:-}" ]]; then
          printf '%s\n' "$ONLYMACS_REQUEST_POLICY_REASONS" >&2
        else
          printf 'This looks like it needs local files or repo context, and OnlyMacs could not confirm that your current swarm is private.\n' >&2
        fi
        printf 'Next: use `local-first`, or open OnlyMacs and switch to a private swarm before retrying.\n' >&2
        return 1
        ;;
      public_export_required)
        if ! prompt_looks_file_bound "$prompt"; then
          ONLYMACS_RESOLVED_PROMPT="$prompt"
          return 0
        fi
        request_json GET "/admin/v1/status" || return 1
        require_success "OnlyMacs could not verify your current swarm for this file-aware request." || return 1
        status_body="$ONLYMACS_LAST_HTTP_BODY"
        run_file_access_flow "$model_alias" "$prompt" "$status_body"
        return $?
        ;;
      private_export_required)
        if ! prompt_looks_file_bound "$prompt"; then
          ONLYMACS_RESOLVED_PROMPT="$prompt"
          return 0
        fi
        request_json GET "/admin/v1/status" || return 1
        require_success "OnlyMacs could not verify your current swarm for this file-aware request." || return 1
        status_body="$ONLYMACS_LAST_HTTP_BODY"
        run_file_access_flow "$model_alias" "$prompt" "$status_body"
        return $?
        ;;
      *)
        # Fall back to the older safety heuristics if the bridge returns something unexpected.
        ;;
    esac
  elif [[ -n "${ONLYMACS_LAST_CURL_ERROR:-}" ]]; then
    pretty_error "OnlyMacs could not classify this request." || true
    return 1
  fi

  if [[ "$used_request_policy" -eq 0 ]]; then
    if ! prompt_looks_file_bound "$prompt"; then
      ONLYMACS_RESOLVED_PROMPT="$prompt"
      return 0
    fi
  fi

  if [[ "$(route_scope_for_alias "$model_alias")" == "local_only" ]]; then
    ONLYMACS_RESOLVED_PROMPT="$prompt"
    return 0
  fi

  request_json GET "/admin/v1/status" || return 1
  require_success "OnlyMacs could not verify your current swarm for this file-aware request." || return 1
  status_body="$ONLYMACS_LAST_HTTP_BODY"
  policy="$(evaluate_file_access_policy "$model_alias" "$prompt" "$status_body")"
  swarm_name="$(active_swarm_name_from_status "$status_body")"

  case "$policy" in
    block_public)
      printf 'OnlyMacs stopped this request.\n' >&2
      printf '%s is an open swarm, and open swarms cannot access your local files or repo.\n' "${swarm_name:-This swarm}" >&2
      printf 'Next: use `local-first`, switch to a private swarm, or export the exact files you want reviewed.\n' >&2
      return 1
      ;;
    block_unverified)
      printf 'OnlyMacs stopped this request.\n' >&2
      printf 'This looks like it needs local files or repo context, and OnlyMacs could not confirm that your current swarm is private.\n' >&2
      printf 'Next: use `local-first`, or open OnlyMacs and switch to a private swarm before retrying.\n' >&2
      return 1
      ;;
    allow_private)
      run_file_access_flow "$model_alias" "$prompt" "$status_body"
      return $?
  esac

  ONLYMACS_RESOLVED_PROMPT="$prompt"
  return 0
}

emit_launch_advisories() {
  local advisories
  advisories="$(launch_advisories_text "$@")"
  if [[ -n "$advisories" ]]; then
    printf '%s' "$advisories"
  fi
}

attach_resolved_artifact_to_payload() {
  local payload="${1:-}"
  if [[ -z "$payload" || -z "${ONLYMACS_RESOLVED_ARTIFACT_JSON:-}" ]]; then
    printf '%s' "$payload"
    return 0
  fi

  jq -c --argjson artifact "$ONLYMACS_RESOLVED_ARTIFACT_JSON" '.onlymacs_artifact = $artifact' <<<"$payload"
}
