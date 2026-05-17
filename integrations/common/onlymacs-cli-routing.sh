# Command routing, leading option parsing, and plan-file helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after shared CLI helpers are loaded.

resolve_model_for_preflight_or_chat() {
  local raw="${1:-}"
  local requested
  requested="$(normalize_model_alias "$raw")"
  if [[ -n "$requested" ]]; then
    printf '%s\n' "$requested"
    return 0
  fi
  if chat_arg_looks_like_route_or_model "$raw"; then
    printf '\n'
    return 0
  fi

  if ! request_json GET "/admin/v1/models"; then
    pretty_error "Could not discover models."
    return 1
  fi
  require_success "Could not discover models." || return 1

  local discovered
  discovered="$(jq -r '
    ([.models[]?.id | select(test("qwen3\\.6"; "i"))][0]
    // [.models[]?.id | select(. == "qwen2.5-coder:32b")][0]
    // [.models[]?.id | select(test("coder"; "i"))][0]
    // .models[0].id
    // empty)
  ' <<<"$ONLYMACS_LAST_HTTP_BODY")"
  if [[ -z "$discovered" ]]; then
    printf 'No models are visible through the local OnlyMacs bridge yet.\n' >&2
    printf 'Next: open the OnlyMacs app and publish a model, then run %s models\n' "$ONLYMACS_WRAPPER_NAME" >&2
    return 1
  fi
  printf '%s\n' "$discovered"
}

set_plan_file_option() {
  local plan_path="${1:-}"
  if [[ -z "$plan_path" ]]; then
    printf 'OnlyMacs needs a path after --plan.\n' >&2
    return 1
  fi
  ONLYMACS_PLAN_FILE_PATH="$plan_path"
  if [[ "${ONLYMACS_EXECUTION_MODE:-auto}" == "auto" ]]; then
    ONLYMACS_EXECUTION_MODE="extended"
  fi
}

validate_leading_options() {
  if [[ "${ONLYMACS_SIMPLE_MODE:-0}" -eq 1 ]]; then
    if [[ -n "${ONLYMACS_PLAN_FILE_PATH:-}" ]]; then
      printf 'OnlyMacs cannot combine --simple with --plan. Remove --simple to run the plan, or remove --plan to force one normal request.\n' >&2
      return 1
    fi
    if [[ "${ONLYMACS_EXECUTION_MODE:-auto}" != "auto" ]]; then
      printf 'OnlyMacs cannot combine --simple with --extended or --overnight. Choose either planned execution or one normal request.\n' >&2
      return 1
    fi
  fi
  return 0
}

normalize_go_wide_lane_count() {
  local lanes="${1:-}"
  local fallback="${2:-2}"
  [[ "$fallback" =~ ^[0-9]+$ && "$fallback" -gt 0 ]] || fallback=2
  case "$(printf '%s' "$lanes" | tr '[:upper:]' '[:lower:]')" in
    max|all)
      lanes=8
      ;;
  esac
  if [[ ! "$lanes" =~ ^[0-9]+$ || "$lanes" -lt 1 ]]; then
    lanes="$fallback"
  fi
  if [[ "$lanes" -gt 8 ]]; then
    lanes=8
  fi
  printf '%s' "$lanes"
}

set_go_wide_lanes_option() {
  local lanes="${1:-}"
  local lane_label
  lane_label="$(printf '%s' "$lanes" | tr '[:upper:]' '[:lower:]')"
  case "$lane_label" in
    max|all)
      ;;
    *)
      if [[ ! "$lanes" =~ ^[0-9]+$ || "$lanes" -lt 1 ]]; then
        printf 'OnlyMacs needs a lane count from 1 to 8, or max, for --go-wide-lanes.\n' >&2
        return 1
      fi
      ;;
  esac
  ONLYMACS_GO_WIDE_MODE=1
  ONLYMACS_GO_WIDE_JSON_LANES="$(normalize_go_wide_lane_count "$lanes" 2)"
  ONLYMACS_GO_WIDE_JSON_LANES_EXPLICIT=1
}

set_go_wide_force_option() {
  ONLYMACS_FORCE_ACTION="go"
  ONLYMACS_GO_WIDE_MODE=1
  case "${ONLYMACS_FORCE_PRESET:-}" in
    local|local-first|trusted-only|trusted_only|trusted|offload-max)
      ;;
    *)
      ONLYMACS_FORCE_PRESET="wide"
      ;;
  esac
}

set_context_read_option() {
  local mode="${1:-}"
  case "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" in
    manual|manual-approval|manual_approval)
      ONLYMACS_CONTEXT_READ_MODE="manual_approval"
      ;;
    packs|context-packs|context_packs|remembered-packs|remembered_context_packs)
      ONLYMACS_CONTEXT_READ_MODE="remembered_context_packs"
      ;;
    full|full-project|full_project|full-project-folder|full_project_folder)
      ONLYMACS_CONTEXT_READ_MODE="full_project_folder"
      ;;
    git|git-checkout|git_checkout|git-backed|git_backed_checkout)
      ONLYMACS_CONTEXT_READ_MODE="git_backed_checkout"
      ;;
    *)
      printf 'OnlyMacs context read mode must be manual, packs, full-project, or git.\n' >&2
      return 1
      ;;
  esac
}

set_context_write_option() {
  local mode="${1:-}"
  case "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" in
    inbox)
      ONLYMACS_CONTEXT_WRITE_MODE="inbox"
      ;;
    staged|staged-apply|staged_apply|apply)
      ONLYMACS_CONTEXT_WRITE_MODE="staged_apply"
      ;;
    direct|direct-write|direct_write)
      ONLYMACS_CONTEXT_WRITE_MODE="direct_write"
      ;;
    readonly|read-only|read_only)
      ONLYMACS_CONTEXT_WRITE_MODE="read_only"
      ;;
    *)
      printf 'OnlyMacs context write mode must be inbox, staged, direct, or read-only.\n' >&2
      return 1
      ;;
  esac
}

parse_leading_options() {
  local args=()
  ONLYMACS_PLAN_FILE_PATH=""
  ONLYMACS_PLAN_COMPILED_PROMPT=""
  ONLYMACS_RESOLVED_PLAN_FILE_PATH=""
  ONLYMACS_PLAN_FILE_CONTENT=""
  ONLYMACS_PLAN_FILE_STEP_COUNT=""
  ONLYMACS_PLAN_USER_PROMPT=""
  ONLYMACS_SIMPLE_MODE=0
  ONLYMACS_EXECUTION_MODE_EXPLICIT=0
  ONLYMACS_FORCE_ACTION=""
  ONLYMACS_FORCE_PRESET=""
  ONLYMACS_GO_WIDE_MODE="${ONLYMACS_GO_WIDE_MODE:-0}"
  ONLYMACS_CONTEXT_READ_MODE="${ONLYMACS_CONTEXT_READ_MODE:-}"
  ONLYMACS_CONTEXT_WRITE_MODE="${ONLYMACS_CONTEXT_WRITE_MODE:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        ONLYMACS_JSON_MODE=1
        shift
        ;;
      --yes|-y)
        ONLYMACS_ASSUME_YES=1
        shift
        ;;
      --extended|--plan-then-execute)
        ONLYMACS_EXECUTION_MODE="extended"
        ONLYMACS_EXECUTION_MODE_EXPLICIT=1
        shift
        ;;
      --overnight)
        ONLYMACS_EXECUTION_MODE="overnight"
        ONLYMACS_EXECUTION_MODE_EXPLICIT=1
        shift
        ;;
      --simple|--one-shot)
        ONLYMACS_SIMPLE_MODE=1
        shift
        ;;
      --go-wide=*|--wide=*)
        set_go_wide_force_option
        set_go_wide_lanes_option "${1#*=}" || return 1
        shift
        ;;
      --go-wide-lanes=*|--wide-lanes=*)
        set_go_wide_force_option
        set_go_wide_lanes_option "${1#*=}" || return 1
        shift
        ;;
      --go-wide-lanes|--wide-lanes)
        set_go_wide_force_option
        if [[ $# -lt 2 ]]; then
          printf 'OnlyMacs needs a lane count after %s.\n' "$1" >&2
          return 1
        fi
        set_go_wide_lanes_option "$2" || return 1
        shift 2
        ;;
      --go-wide|--wide)
        set_go_wide_force_option
        shift
        ;;
      --remote-first)
        ONLYMACS_FORCE_PRESET="remote-first"
        shift
        ;;
      --local-first)
        ONLYMACS_FORCE_PRESET="local-first"
        shift
        ;;
      --trusted-only)
        ONLYMACS_FORCE_PRESET="trusted-only"
        shift
        ;;
      --offload-max)
        ONLYMACS_FORCE_PRESET="offload-max"
        shift
        ;;
      --context-read=*)
        set_context_read_option "${1#*=}" || return 1
        shift
        ;;
      --context-read)
        if [[ $# -lt 2 ]]; then
          printf 'OnlyMacs needs a mode after --context-read.\n' >&2
          return 1
        fi
        set_context_read_option "$2" || return 1
        shift 2
        ;;
      --context-write=*)
        set_context_write_option "${1#*=}" || return 1
        shift
        ;;
      --context-write)
        if [[ $# -lt 2 ]]; then
          printf 'OnlyMacs needs a mode after --context-write.\n' >&2
          return 1
        fi
        set_context_write_option "$2" || return 1
        shift 2
        ;;
      --allow-tests)
        ONLYMACS_CONTEXT_ALLOW_TESTS=1
        shift
        ;;
      --allow-installs|--allow-install|--allow-dependency-install)
        ONLYMACS_CONTEXT_ALLOW_INSTALL=1
        shift
        ;;
      --plan:*)
        set_plan_file_option "${1#--plan:}" || return 1
        shift
        ;;
      --plan=*)
        set_plan_file_option "${1#--plan=}" || return 1
        shift
        ;;
      --plan-file=*)
        set_plan_file_option "${1#--plan-file=}" || return 1
        shift
        ;;
      --plan|--plan-file)
        set_plan_file_option "${2:-}" || return 1
        shift 2
        ;;
      --title)
        ONLYMACS_TITLE_OVERRIDE="${2:-}"
        shift 2
        ;;
      --interval)
        ONLYMACS_WATCH_INTERVAL="${2:-2}"
        shift 2
        ;;
      --help|-h)
        args+=("help")
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  if ((${#args[@]} > 0)); then
    ONLYMACS_PARSED_ARGS=("${args[@]}")
  else
    ONLYMACS_PARSED_ARGS=()
  fi
  validate_leading_options
}

known_action() {
  case "${1:-}" in
    help|version|check|doctor|make-ready|status|runtime|sharing|swarms|models|preflight|benchmark|watch-provider|plan|start|go|watch|queue|jobs|job|tickets|board|pause|resume|resume-run|diagnostics|support-bundle|report|inbox|open|apply|cancel|stop|demo|repair|chat)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

string_has_any() {
  local haystack="${1:-}"
  shift || true
  local needle
  for needle in "$@"; do
    if [[ -n "$needle" && "$haystack" == *"$needle"* ]]; then
      return 0
    fi
  done
  return 1
}

trim_joined_text() {
  printf '%s' "$*" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

resolve_plan_file_path() {
  local raw="${1:-}"
  local resolved
  if [[ -z "$raw" ]]; then
    printf 'OnlyMacs needs a plan file path.\n' >&2
    return 1
  fi
  case "$raw" in
    "~/"*)
      resolved="${HOME}/${raw#~/}"
      ;;
    /*)
      resolved="$raw"
      ;;
    *)
      resolved="${PWD}/${raw}"
      ;;
  esac
  if [[ ! -f "$resolved" ]]; then
    printf 'OnlyMacs could not find the plan file: %s\n' "$raw" >&2
    return 1
  fi
  if [[ ! -r "$resolved" ]]; then
    printf 'OnlyMacs cannot read the plan file: %s\n' "$resolved" >&2
    return 1
  fi
  printf '%s' "$resolved"
}

plan_file_step_count_from_content() {
  perl -0777 -ne '
    my %seen;
    while (/^#{1,6}\s*(?:step|phase|stage|task)\s*0*(\d{1,3})\b/gmi) {
      $seen{0 + $1} = 1;
    }
    if (%seen) {
      my @nums = sort { $a <=> $b } keys %seen;
      print $nums[-1];
      exit;
    }
    print 1;
  '
}

plan_file_step_text_from_content() {
  local step_index="${1:-1}"
  ONLYMACS_PLAN_STEP_INDEX="$step_index" perl -0777 -ne '
    my $idx = $ENV{ONLYMACS_PLAN_STEP_INDEX} || 1;
    my $s = $_;
    my @headers;
    while ($s =~ /^#{1,6}\s*(?:step|phase|stage|task)\s*0*(\d{1,3})\b[^\n]*(?:\n|$)/gmi) {
      push @headers, { num => 0 + $1, start => $-[0] };
    }
    if (!@headers) {
      print $s if $idx == 1;
      exit;
    }
    for (my $i = 0; $i < @headers; $i++) {
      next unless $headers[$i]{num} == $idx;
      my $start = $headers[$i]{start};
      my $end = ($i + 1 < @headers) ? $headers[$i + 1]{start} : length($s);
      print substr($s, $start, $end - $start);
      exit;
    }
  '
}

plan_file_step_title_from_content() {
  local step_index="${1:-1}"
  plan_file_step_text_from_content "$step_index" | sed -nE 's/^#{1,6}[[:space:]]*//p' | head -n 1 | cut -c 1-120
}

plan_file_step_text() {
  local step_index="${1:-1}"
  printf '%s' "${ONLYMACS_PLAN_FILE_CONTENT:-}" | plan_file_step_text_from_content "$step_index"
}

plan_file_step_title() {
  local step_index="${1:-1}"
  plan_file_step_text "$step_index" | sed -nE 's/^#{1,6}[[:space:]]*//p' | head -n 1 | cut -c 1-120
}

plan_file_step_filename_from_content() {
  local step_index="${1:-1}"
  plan_file_step_text_from_content "$step_index" | perl -0777 -ne '
    if (/^\s*(?:outputs?|artifacts?|deliverables?|files?)\s*[:=-]\s*`?([A-Za-z0-9._\/-]+\.(?:json|md|txt|js|ts|tsx|jsx|py|go|swift|html|css|yaml|yml|csv))`?/mi) {
      print $1;
      exit;
    }
    if (/`([A-Za-z0-9._\/-]+\.(?:json|md|txt|js|ts|tsx|jsx|py|go|swift|html|css|yaml|yml|csv))`/) {
      print $1;
      exit;
    }
  '
}

plan_file_step_metadata_json() {
  local step_index="${1:-1}"
  local fallback_filename="${2:-plan-step.md}"
  local step_text
  step_text="$(plan_file_step_text "$step_index")"
  printf '%s' "$step_text" | jq -Rs \
    --arg fallback_filename "$fallback_filename" '
    def line_value($names):
      split("\n")
      | map(capture("^\\s*(?<key>[A-Za-z _-]+)\\s*[:=-]\\s*(?<value>.+?)\\s*$")? // empty)
      | map(select((.key | ascii_downcase | gsub("[ _-]"; "_")) as $k | any($names[]; . == $k)))
      | .[0].value // "";
    def split_terms:
      split(",")
      | map(gsub("^[\\s`'\''\"]+|[\\s`'\''\"]+$"; ""))
      | map(select(length > 0));
    def path_terms:
      split_terms
      | if length == 0 then [$fallback_filename] else . end;
    {
      expected_outputs: ((line_value(["output","outputs","artifact","artifacts","deliverable","deliverables","file","files"]) | path_terms) // [$fallback_filename]),
      target_paths: ((line_value(["target","target_path","target_paths","path","paths","destination","destinations"]) | path_terms) // [$fallback_filename]),
      validators: ((line_value(["validation","validator","validators","checks","acceptance_criteria"]) | split_terms) // []),
      dependencies: ((line_value(["depends_on","dependencies","after","requires"]) | split_terms) // []),
      assignment_policy: (line_value(["assignment_policy","assignment","routing","routing_policy","worker_policy"]) // ""),
      role: (line_value(["role","worker_role"]) // ""),
      quorum: (line_value(["quorum","review_quorum"]) // "")
    }'
}

plan_file_global_context_from_content() {
  perl -0777 -ne '
    if (/^(.*?)(?=^\s*#{1,6}\s*Step\s+\d+\b)/ms) {
      print $1;
    } else {
      print;
    }
  ' | cut -c 1-12000
}

plan_file_global_context() {
  printf '%s' "${ONLYMACS_PLAN_FILE_CONTENT:-}" | plan_file_global_context_from_content
}

compile_prompt_with_plan_file() {
  local prompt="${1:-}"
  local resolved content step_count display_name
  if [[ -z "${ONLYMACS_PLAN_FILE_PATH:-}" ]]; then
    ONLYMACS_PLAN_COMPILED_PROMPT="$prompt"
    return 0
  fi

  resolved="$(resolve_plan_file_path "$ONLYMACS_PLAN_FILE_PATH")" || return 1
  content="$(cat "$resolved")"
  step_count="$(printf '%s' "$content" | plan_file_step_count_from_content)"
  display_name="$(basename "$resolved")"

  ONLYMACS_RESOLVED_PLAN_FILE_PATH="$resolved"
  ONLYMACS_PLAN_FILE_CONTENT="$content"
  ONLYMACS_PLAN_FILE_STEP_COUNT="$step_count"
  ONLYMACS_PLAN_USER_PROMPT="$prompt"
  ONLYMACS_PLAN_COMPILED_PROMPT="$(cat <<EOF
Self-contained prompt-only OnlyMacs plan-file job. Use only the user request and plan file contents included in this message. Do not ask for local repository access, local repo access, or local files.

User request:
${prompt:-Execute the attached OnlyMacs plan file.}

Plan file: ${display_name}
Detected steps: ${step_count}

Plan file contents:
${content}
EOF
)"
  return 0
}

auto_plan_filename_for_step() {
  local prompt="${1:-}"
  local step_index="${2:-1}"
  local requested lowered
  requested="$(artifact_mode_requested_filename "$prompt" || true)"
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

  if prompt_requests_content_pack_mode "$prompt"; then
    case "$step_index" in
      1) printf 'content-pack-manifest.json' ;;
      2) printf 'content-batch-01.json' ;;
      3) printf 'content-batch-02.json' ;;
      4) printf 'content-validation-report.md' ;;
      *) printf 'final-handoff.md' ;;
    esac
    return 0
  fi

  case "$step_index" in
    1)
      printf 'requirements-and-contract.md'
      ;;
    2)
      if [[ "$lowered" == *"json"* ]]; then
        printf 'data-slice-01.json'
      else
        printf 'draft-slice-01.md'
      fi
      ;;
    3)
      if [[ -n "$requested" ]]; then
        printf '%s' "$requested"
      elif [[ "$lowered" == *"json"* ]]; then
        printf 'data-slice-02.json'
      else
        printf 'draft-slice-02.md'
      fi
      ;;
    *)
      printf 'validation-and-handoff.md'
      ;;
  esac
}

auto_plan_markdown_for_prompt() {
  local prompt="${1:-}"
  local title="${2:-OnlyMacs Auto Plan}"
  local step1 step2 step3 step4
  step1="$(auto_plan_filename_for_step "$prompt" 1)"
  step2="$(auto_plan_filename_for_step "$prompt" 2)"
  step3="$(auto_plan_filename_for_step "$prompt" 3)"
  step4="$(auto_plan_filename_for_step "$prompt" 4)"

  cat <<EOF
# ${title}

This plan was created automatically because the request looked too large, multi-step, or artifact-heavy for one brittle model response. It is self-contained for an OnlyMacs public-swarm run; remote workers should use this plan and the user request below, and should not ask for broad repository or local file access.

User request:
${prompt}

General execution rules:
- Execute one step at a time.
- Save each step as the named artifact.
- Return only the current step artifact between OnlyMacs artifact markers.
- Preserve constraints, exact counts, filenames, formats, and validation requirements from the user request.
- Do not use placeholders, TODOs, ellipses, "add the remaining", or "omitted for brevity".
- If a step cannot be completed from this plan and the user request, return a concise BLOCKED artifact naming the exact missing input.

## Step 1 - Requirements And Output Contract
Output: ${step1}

Restate the concrete deliverables, required formats, exact counts, validation checks, assumptions, and risks. Keep this short and operational so later steps can execute from it.

## Step 2 - First Work Slice
Output: ${step2}

Produce the first coherent slice of the requested work. If the final deliverable is a structured artifact, emit the first independently valid batch. If it is prose or architecture, emit the first half or first major section.

## Step 3 - Complete Main Deliverable
Output: ${step3}

Use the requirements and prior slice as context, then complete the main deliverable or second batch. If the user requested a named file, this step should produce the complete named file unless the request explicitly requires multiple files.

## Step 4 - Validation And Handoff
Output: ${step4}

Validate the produced work against the user request. Report counts, syntax/schema checks that can be reasoned about from the artifact text, missing pieces, repair recommendations, and exact files the requester should inspect next.
EOF
}

should_auto_create_plan_for_prompt() {
  local prompt="${1:-}"
  if [[ "${ONLYMACS_SIMPLE_MODE:-0}" -eq 1 ]]; then
    return 1
  fi
  if [[ -n "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-}" || -n "${ONLYMACS_PLAN_FILE_PATH:-}" ]]; then
    return 1
  fi
  if orchestrated_is_large_exact_js_artifact "$prompt"; then
    return 1
  fi
  if [[ "${ONLYMACS_EXECUTION_MODE_EXPLICIT:-0}" -eq 1 ]]; then
    return 0
  fi
  prompt_needs_plan_mode "$prompt"
}

activate_auto_plan_for_prompt() {
  local prompt="${1:-}"
  local plan_path content step_count
  should_auto_create_plan_for_prompt "$prompt" || return 0
  [[ -n "${ONLYMACS_CURRENT_RETURN_DIR:-}" ]] || return 0

  plan_path="${ONLYMACS_CURRENT_RETURN_DIR}/plan.draft.md"
  content="$(auto_plan_markdown_for_prompt "$prompt")"
  printf '%s\n' "$content" >"$plan_path"
  step_count="$(printf '%s' "$content" | plan_file_step_count_from_content)"

  ONLYMACS_RESOLVED_PLAN_FILE_PATH="$plan_path"
  ONLYMACS_PLAN_FILE_PATH="$plan_path"
  ONLYMACS_PLAN_FILE_CONTENT="$content"
  ONLYMACS_PLAN_FILE_STEP_COUNT="$step_count"
  ONLYMACS_PLAN_USER_PROMPT="$prompt"

  if [[ "$ONLYMACS_JSON_MODE" -ne 1 ]]; then
    printf 'OnlyMacs auto-created an extended plan for this larger request.\nPlan draft: %s\n\n' "$plan_path"
  fi
}

extract_exact_model_from_phrase() {
  local raw="${1:-}"
  local candidate
  if [[ "$raw" =~ [Ee]xact[[:space:]]+([[:alnum:]_.:-]+) ]]; then
    candidate="${BASH_REMATCH[1]}"
    if exact_model_candidate_looks_valid "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  if [[ "$raw" =~ [Mm]odel[[:space:]]+([[:alnum:]_.:-]+) ]]; then
    candidate="${BASH_REMATCH[1]}"
    if exact_model_candidate_looks_valid "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  return 1
}

exact_model_candidate_looks_valid() {
  local candidate="${1:-}"
  local lowered
  lowered="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    ""|saved|file|files|path|paths|count|counts|format|formats|output|outputs|artifact|artifacts|same|this|that|the|a|an|model|route|member|mac|computer|provider|step|steps|plan|prompt|answer|result|results)
      return 1
      ;;
  esac
  case "$lowered" in
    *:*|*/*|qwen*|llama*|mistral*|mixtral*|gemma*|deepseek*|codestral*|phi*|gpt-*|o[0-9]*|claude-*|sonnet-*|opus-*|haiku-*)
      return 0
      ;;
  esac
  [[ "$lowered" =~ [0-9] ]]
}

string_matches_any_regex() {
  local haystack="${1:-}"
  shift || true
  local pattern
  for pattern in "$@"; do
    if [[ -n "$pattern" && "$haystack" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

prompt_requests_staged_write_mode() {
  local lowered="${1:-}"
  if string_has_any "$lowered" "without patching" "without editing" "without changing" "don't change" "do not change" "only inspect"; then
    return 1
  fi
  if string_has_any "$lowered" "patch" "change code" "edit code" "make edits" "apply" "modify" "implement" "build the" "add the" "repair the tests" "repair tests" "staged changes" "update the workspace" "update source files" "source files" "failing test" "test failure" "typescript errors" "pr-ready" "pr ready"; then
    return 0
  fi
  string_matches_any_regex "$lowered" \
    '(^|[^a-z])fix([^a-z]|$)' \
    '(^|[^a-z])edit([^a-z]|$)'
}

prompt_requests_test_execution() {
  local lowered="${1:-}"
  if string_has_any "$lowered" \
    "run tests" \
    "run the tests" \
    "run the test suite" \
    "run unit tests" \
    "unit tests" \
    "test suite" \
    "check the tests" \
    "check tests" \
    "failing test" \
    "repair the tests" \
    "repair tests" \
    "test failures" \
    "test failure" \
    "fix test" \
    "fix tests"; then
    return 0
  fi
  [[ "$lowered" == *"failing"* && "$lowered" == *"test"* ]]
}

default_session_reference_from_phrase() {
  local lowered="${1:-}"
  local fallback="${2:-current}"
  if string_has_any "$lowered" "queue" "waiting line" "waiting room"; then
    printf 'queue\n'
  elif string_has_any "$lowered" "latest" "newest" "recent"; then
    printf 'latest\n'
  elif string_has_any "$lowered" "current" "this swarm" "the swarm" "my swarm" "this session" "the session"; then
    printf 'current\n'
  else
    printf '%s\n' "$fallback"
  fi
}

looks_like_pause_command() {
  local lowered="${1:-}"
  string_matches_any_regex "$lowered" \
    '^[[:space:][:punct:]]*pause([[:space:][:punct:]]+(current|latest|queue))?[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*pause([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$'
}

looks_like_resume_command() {
  local lowered="${1:-}"
  string_matches_any_regex "$lowered" \
    '^[[:space:][:punct:]]*resume([[:space:][:punct:]]+(current|latest|queue))?[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*resume([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*continue([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$'
}

looks_like_stop_command() {
  local lowered="${1:-}"
  string_matches_any_regex "$lowered" \
    '^[[:space:][:punct:]]*(stop|cancel)([[:space:][:punct:]]+(current|latest|queue))?[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*(stop|cancel)([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*end[[:space:]]+the[[:space:]]+swarm[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*kill[[:space:]]+the[[:space:]]+swarm[[:space:][:punct:]]*$'
}

looks_like_watch_command() {
  local lowered="${1:-}"
  string_matches_any_regex "$lowered" \
    '^[[:space:][:punct:]]*watch([[:space:][:punct:]]+(current|latest|queue))?[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*watch([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*follow([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*tail([[:space:][:punct:]]+((the|my|this)[[:space:]]+)?)?((current|latest|queue)[[:space:]]+)?(swarm|session|run|job)[[:space:][:punct:]]*$' \
    '^[[:space:][:punct:]]*track[[:space:]]+live[[:space:][:punct:]]*$'
}

resolve_natural_language_command() {
  local raw lowered model preset command target explicit_route workspace_preset plan_file_job
  local reused_workspace_default chat_alias exact_model used_request_policy policy_alias
  raw="$(trim_joined_text "$@")"
  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

  ONLYMACS_ROUTED_ARGS=()
  ONLYMACS_ROUTER_INTERPRETATION=""
  ONLYMACS_ROUTER_REASON=""
  explicit_route=0
  reused_workspace_default=0
  exact_model=""
  used_request_policy=0
  plan_file_job=0
  if [[ -n "${ONLYMACS_PLAN_FILE_PATH:-}" || -n "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-}" ]]; then
    plan_file_job=1
  fi

  if [[ -z "$raw" ]]; then
    return 1
  fi

  if string_has_any "$lowered" \
    "how do i use this" \
    "how do i use onlymacs" \
    "help me use onlymacs" \
    "what can i do with onlymacs" \
    "what are the commands" \
    "show me examples" \
    "show help" \
    "show usage"; then
    ONLYMACS_ROUTED_ARGS=("help")
    ONLYMACS_ROUTER_INTERPRETATION="help"
    ONLYMACS_ROUTER_REASON="OnlyMacs recognized this as a usage/help question and opened the built-in command guide instead of sending it into the swarm."
    return 0
  fi

  if string_has_any "$lowered" "show models" "list models" "what models" "which models" "available models" "visible models"; then
    ONLYMACS_ROUTED_ARGS=("models")
    ONLYMACS_ROUTER_INTERPRETATION="models"
    return 0
  fi

  if string_has_any "$lowered" "show version" "onlymacs version" "what version" "which version" "version info" "version information"; then
    ONLYMACS_ROUTED_ARGS=("version")
    ONLYMACS_ROUTER_INTERPRETATION="version"
    return 0
  fi

  if string_has_any "$lowered" "what commands exist" "which commands exist" "list commands" "show commands"; then
    ONLYMACS_ROUTED_ARGS=("help")
    ONLYMACS_ROUTER_INTERPRETATION="help"
    ONLYMACS_ROUTER_REASON="OnlyMacs recognized this as a usage/help question and opened the built-in command guide instead of sending it into the swarm."
    return 0
  fi

  if string_has_any "$lowered" "repair onlymacs" "fix onlymacs" "fix everything" "repair this" "repair setup"; then
    ONLYMACS_ROUTED_ARGS=("repair")
    ONLYMACS_ROUTER_INTERPRETATION="repair"
    return 0
  fi

  if string_has_any "$lowered" "check onlymacs" "check my setup" "check setup" "setup status" "health check" "is onlymacs ready" "make onlymacs ready" "am i ready"; then
    ONLYMACS_ROUTED_ARGS=("check")
    ONLYMACS_ROUTER_INTERPRETATION="check"
    return 0
  fi

  if looks_like_pause_command "$lowered"; then
    target="$(default_session_reference_from_phrase "$lowered" "current")"
    ONLYMACS_ROUTED_ARGS=("pause" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="pause $target"
    return 0
  fi

  if looks_like_resume_command "$lowered"; then
    target="$(default_session_reference_from_phrase "$lowered" "current")"
    ONLYMACS_ROUTED_ARGS=("resume" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="resume $target"
    return 0
  fi

  if string_has_any "$lowered" "resume the newest run" "resume newest run" "resume the newest job" "resume newest job"; then
    ONLYMACS_ROUTED_ARGS=("resume" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="resume latest"
    return 0
  fi

  if looks_like_stop_command "$lowered"; then
    target="$(default_session_reference_from_phrase "$lowered" "current")"
    ONLYMACS_ROUTED_ARGS=("stop" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="stop $target"
    return 0
  fi

  if string_has_any "$lowered" "cancel newest session" "cancel the newest session" "cancel newest run" "cancel the newest run" "stop newest session" "stop the newest session"; then
    ONLYMACS_ROUTED_ARGS=("stop" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="stop latest"
    return 0
  fi

  if looks_like_watch_command "$lowered"; then
    target="$(default_session_reference_from_phrase "$lowered" "current")"
    ONLYMACS_ROUTED_ARGS=("watch" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="watch $target"
    return 0
  fi

  if string_has_any "$lowered" "follow the latest run" "follow latest run" "follow the latest job" "follow latest job"; then
    ONLYMACS_ROUTED_ARGS=("watch" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="watch latest"
    return 0
  fi

  if string_has_any "$lowered" "watch the newest run" "watch newest run" "watch the newest job" "watch newest job"; then
    ONLYMACS_ROUTED_ARGS=("watch" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="watch latest"
    return 0
  fi

  if string_has_any "$lowered" "queue" "what is queued" "what's queued" "waiting right now"; then
    ONLYMACS_ROUTED_ARGS=("queue")
    ONLYMACS_ROUTER_INTERPRETATION="queue"
    return 0
  fi

  if string_has_any "$lowered" "status of the latest result" "status latest result" "latest result status"; then
    ONLYMACS_ROUTED_ARGS=("status" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="status latest"
    return 0
  fi

  if string_has_any "$lowered" "latest run status" "newest run status" "latest job status" "newest job status"; then
    ONLYMACS_ROUTED_ARGS=("status" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="status latest"
    return 0
  fi

  if string_has_any "$lowered" "what's running now" "what is running now" "running now"; then
    ONLYMACS_ROUTED_ARGS=("status" "current")
    ONLYMACS_ROUTER_INTERPRETATION="status current"
    return 0
  fi

  if string_has_any "$lowered" "run diagnostics" "show diagnostics" "diagnostics latest" "latest diagnostics"; then
    target="$(default_session_reference_from_phrase "$lowered" "latest")"
    ONLYMACS_ROUTED_ARGS=("diagnostics" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="diagnostics $target"
    return 0
  fi

  if string_has_any "$lowered" "support bundle" "support-bundle"; then
    target="$(default_session_reference_from_phrase "$lowered" "latest")"
    ONLYMACS_ROUTED_ARGS=("support-bundle" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="support-bundle $target"
    return 0
  fi

  if string_has_any "$lowered" "diagnostics bundle" "diagnostic bundle"; then
    ONLYMACS_ROUTED_ARGS=("support-bundle" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="support-bundle latest"
    return 0
  fi

  if string_has_any "$lowered" "report settings" "show report settings" "report status"; then
    ONLYMACS_ROUTED_ARGS=("report" "status")
    ONLYMACS_ROUTER_INTERPRETATION="report status"
    return 0
  fi

  if string_has_any "$lowered" "open the latest inbox" "open latest inbox" "open newest inbox" "open the newest inbox" "open latest result" "open the latest result" "open inbox latest"; then
    ONLYMACS_ROUTED_ARGS=("open" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="open latest"
    return 0
  fi

  if string_has_any "$lowered" "apply latest result" "apply the latest result" "apply latest inbox" "apply the latest inbox" "apply newest inbox" "apply the newest inbox"; then
    ONLYMACS_ROUTED_ARGS=("apply" "latest")
    ONLYMACS_ROUTER_INTERPRETATION="apply latest"
    return 0
  fi

  if string_has_any "$lowered" "show inbox" "inbox latest" "latest inbox" "newest inbox"; then
    target="$(default_session_reference_from_phrase "$lowered" "latest")"
    ONLYMACS_ROUTED_ARGS=("inbox" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="inbox $target"
    return 0
  fi

  if string_has_any "$lowered" "show runtime" "runtime status" "runtime mode"; then
    ONLYMACS_ROUTED_ARGS=("runtime")
    ONLYMACS_ROUTER_INTERPRETATION="runtime"
    return 0
  fi

  if string_has_any "$lowered" "list swarms" "show swarms" "active swarms" "what swarms" "which swarms"; then
    ONLYMACS_ROUTED_ARGS=("swarms")
    ONLYMACS_ROUTER_INTERPRETATION="swarms"
    return 0
  fi

  if string_has_any "$lowered" "sharing status" "sharing state" "show sharing"; then
    ONLYMACS_ROUTED_ARGS=("sharing")
    ONLYMACS_ROUTER_INTERPRETATION="sharing"
    return 0
  fi

  if string_has_any "$lowered" "latest swarm" "current swarm" "latest session" "current session" "swarm doing" "session doing" "swarm status" "session status" "swarm progress" "session progress"; then
    target="$(default_session_reference_from_phrase "$lowered" "latest")"
    ONLYMACS_ROUTED_ARGS=("status" "$target")
    ONLYMACS_ROUTER_INTERPRETATION="status $target"
    return 0
  fi

  preset="balanced"
  command="chat"

  if string_has_any "$lowered" "local only" "local machine only" "single-machine local" "this mac only" "keep this on this mac" "stay on this mac" "never leave this laptop" "this laptop only" "on my laptop only" "my laptop only" "this device only" "this machine only" "this computer only" "workstation only" "offline only" "offline on my mac" "stay on this workstation" "this workstation" "do not send this over the network" "don't send this over the network" "no network" "no network calls" "do not upload" "never transmit" "on-device only" "on device only" "airgapped"; then
    preset="local-first"
    explicit_route=1
  fi

  if string_has_any "$lowered" "trusted only" "trusted machines" "trusted macs" "trusted friends" "trusted circle" "trusted provider" "approved macs" "my macs only" "my machines only" "keep this on my macs" "keep this on my machines" "private swarm" "private machines" "private macs" "private worker pool" "trusted swarm" "owned macs" "owned machines" "owned fleet" "my fleet only" "family macs" "company macs" "my own macs" "my own machines" "our machines" "no public" "avoid public" "do not send to public" "don't send to public" "private code" "stranger mac" "stranger macs" "community swarm" "unknown providers" "personal mac" "personal macs" "inside my swarm" "keep this private"; then
    preset="trusted-only"
    explicit_route=1
  fi

  if [[ "$explicit_route" -eq 0 ]] && string_has_any "$lowered" "remote first" "force remote" "remote capacity" "remote mac" "remote macs" "remote worker" "non-local mac" "stronger mac" "shared worker mac" "external mac" "someone else's mac" "someone elses mac" "fast remote" "public swarm" "public capacity" "public macs" "public workers" "cloud mac" "other computers first" "other macs first" "use other computers" "use other macs" "use another mac first" "another mac" "not mine" "not this mac" "not local mac" "do not use the local mac" "don't use the local mac" "not on this laptop" "do not run this on this laptop" "don't run this on this laptop" "away from this mac" "outside this machine" "outside mine" "laptop out" "off-machine" "except this machine" "exclude this mac" "beast machine" "beast machines" "beast mac" "biggest mac" "beefiest" "fastest available remote"; then
    preset="remote-first"
    explicit_route=1
  fi

  if string_has_any "$lowered" "use the swarm" "swarm allowed" "broader swarm is okay" "best available" "automatic route" "auto route"; then
    preset="balanced"
    explicit_route=1
    ONLYMACS_ROUTER_INTERPRETATION="chat best-available (swarm allowed)"
  fi

  if string_has_any "$lowered" "save tokens" "save money" "token-free" "token free" "paid tokens" "spend paid" "don't spend paid" "do not spend paid" "zero paid" "paid model" "billable model" "zero credits" "spend zero credits" "avoid using credits" "use my mac first" "use my macs first" "local first" "offload" "cheaper" "cheapest" "avoid paid" "without paid" "no paid" "burn credits" "credits are expensive" "free compute" "spare macs" "spare capacity" "free local fleet" "idle capacity" "owned capacity" "owned idle" "idle owned" "idle workers" "no-cost" "cost reasons" "cloud spend" "free idle" "free worker" "free workers"; then
    preset="offload-max"
    explicit_route=1
  fi

  if string_has_any "$lowered" \
    "parallel" \
    "parallelize" \
    "fan out" \
    "workstreams" \
    "split this refactor" \
    "multiple agents" \
    "multiple computers" \
    "multi-computer" \
    "go wide" \
    "go-wide" \
    "use all available" \
    "use every available" \
    "every available mac" \
    "all available mac" \
    "all available computer" \
    "as many other computers" \
    "as many macs" \
    "both my computer and" \
    "both my mac and" \
    "across the swarm"; then
    preset="wide"
    explicit_route=1
  fi

  model="$(extract_exact_model_from_phrase "$raw" || true)"
  if [[ -n "$model" ]]; then
    exact_model="$model"
    ONLYMACS_ROUTER_INTERPRETATION="chat exact-model $model"
  elif string_has_any "$lowered" "do not degrade" "don't degrade" "same model" "keep on premium" "exact model"; then
    preset="precise"
  fi

  policy_alias="$preset"
  if [[ "$explicit_route" -eq 0 ]]; then
    policy_alias="balanced"
  fi

  if [[ "$plan_file_job" -eq 0 ]] && request_policy_classify "$policy_alias" "$raw"; then
    used_request_policy=1
    case "${ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND:-}" in
      chat|plan|go)
        command="$ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND"
        ;;
    esac
    if [[ "$explicit_route" -eq 0 && -z "$exact_model" ]]; then
      case "${ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET:-}" in
        balanced|wide|local-first|trusted-only|offload-max|remote-first|precise|quick|best|coder|fast)
          preset="$ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET"
          ;;
      esac
    fi
    if [[ -n "${ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION:-}" ]]; then
      ONLYMACS_ROUTER_REASON="$ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION"
    fi
  fi

  if [[ "$plan_file_job" -eq 0 ]]; then
    if prompt_requests_artifact_mode "$raw" && ! prompt_looks_file_bound "$raw"; then
      if [[ -z "${ONLYMACS_CONTEXT_WRITE_MODE:-}" ]]; then
        ONLYMACS_CONTEXT_WRITE_MODE="inbox"
      fi
      if [[ "${ONLYMACS_SIMPLE_MODE:-0}" -ne 1 && "${ONLYMACS_EXECUTION_MODE:-auto}" == "auto" ]]; then
        ONLYMACS_EXECUTION_MODE="extended"
      fi
      if [[ "$explicit_route" -eq 0 && -z "$exact_model" ]]; then
        preset="balanced"
      fi
      if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="chat best-available (artifact inbox)"
      fi
      if [[ -z "$ONLYMACS_ROUTER_REASON" ]]; then
        ONLYMACS_ROUTER_REASON="OnlyMacs recognized this as generated artifact work, so it will prefer capable Macs when available and save the result to the inbox for review."
      fi
    elif prompt_looks_file_bound "$raw"; then
      if [[ -z "${ONLYMACS_CONTEXT_READ_MODE:-}" ]] && string_has_any "$lowered" "repo" "repository" "codebase" "branch" "git" "project"; then
        ONLYMACS_CONTEXT_READ_MODE="git_backed_checkout"
      fi
      if [[ -z "${ONLYMACS_CONTEXT_WRITE_MODE:-}" ]]; then
        if prompt_requests_staged_write_mode "$lowered"; then
          ONLYMACS_CONTEXT_WRITE_MODE="staged_apply"
        else
          ONLYMACS_CONTEXT_WRITE_MODE="inbox"
        fi
      fi
      if prompt_requests_test_execution "$lowered"; then
        ONLYMACS_CONTEXT_ALLOW_TESTS=1
      fi
    fi
  fi

  if [[ "$used_request_policy" -eq 0 && "$explicit_route" -eq 0 ]] && prompt_looks_sensitive "$raw"; then
    preset="local-first"
    ONLYMACS_ROUTER_INTERPRETATION="chat local-first"
  fi

  if [[ "$used_request_policy" -eq 0 && "$explicit_route" -eq 0 && "$command" == "chat" && "$plan_file_job" -eq 0 ]] && prompt_looks_file_bound "$raw" && ! prompt_looks_sensitive "$raw"; then
    preset="trusted-only"
    ONLYMACS_ROUTER_INTERPRETATION="chat trusted-only"
  fi

  if [[ "$preset" == "balanced" && "$explicit_route" -eq 0 && "$command" == "chat" ]]; then
    workspace_preset="$(load_workspace_default_preset)"
    if workspace_default_reusable "$workspace_preset"; then
      preset="$workspace_preset"
      reused_workspace_default=1
    fi
  fi

  if [[ "$used_request_policy" -eq 0 ]]; then
    if string_has_any "$lowered" "make a plan" "plan this" "plan the" "estimate" "how many agents" "before you start"; then
      command="plan"
    fi

    if string_has_any "$lowered" "review" "code review" "debug" "summarize" "summary" "analyze" "analysis" "classify" "translate" "refactor" "audit" "write" "build" "create" "generate" "make " "implement"; then
      if [[ "$preset" == "wide" ]] && ! string_has_any "$lowered" "start" "run" "launch"; then
        command="plan"
      fi
    fi
  fi

  if [[ "$preset" == "wide" ]]; then
    if string_has_any "$lowered" "start" "run" "launch" "execute" "do " "use both" "as many" "all available" "every available" "go wide"; then
      ONLYMACS_ROUTED_ARGS=("go" "$preset" "$raw")
      if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="go $preset"
      fi
    else
      ONLYMACS_ROUTED_ARGS=("plan" "$preset" "$raw")
      if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="plan $preset"
      fi
    fi
    return 0
  fi

  if [[ "$command" == "plan" ]]; then
    if [[ -n "$exact_model" ]]; then
      ONLYMACS_ROUTED_ARGS=("plan" "$exact_model" "1" "$raw")
      if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" || "$ONLYMACS_ROUTER_INTERPRETATION" == chat* ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="plan exact-model $exact_model"
      fi
    else
      ONLYMACS_ROUTED_ARGS=("plan" "$preset" "$raw")
      if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" || "$ONLYMACS_ROUTER_INTERPRETATION" == chat* ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="plan $preset"
      fi
    fi
    return 0
  fi

  if [[ -n "$exact_model" ]]; then
    ONLYMACS_ROUTED_ARGS=("chat" "$exact_model" "$raw")
    if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" ]]; then
      ONLYMACS_ROUTER_INTERPRETATION="chat exact-model $exact_model"
    fi
    return 0
  fi

  case "$preset" in
    balanced)
      chat_alias=""
      ;;
    local-first|local)
      chat_alias="local-first"
      ;;
    trusted-only|trusted_only|trusted)
      chat_alias="trusted-only"
      ;;
    offload-max)
      chat_alias="offload-max"
      ;;
    remote-first|remote-only|remote_only|remote)
      chat_alias="remote-first"
      ;;
    precise|coder)
      chat_alias="coder"
      ;;
    quick|fast)
      chat_alias="fast"
      ;;
    *)
      chat_alias=""
      ;;
  esac

  if [[ -n "$chat_alias" ]]; then
    ONLYMACS_ROUTED_ARGS=("chat" "$chat_alias" "$raw")
    if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" ]]; then
      if [[ "$reused_workspace_default" -eq 1 ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="chat $chat_alias (workspace default)"
      else
        ONLYMACS_ROUTER_INTERPRETATION="chat $chat_alias"
      fi
    fi
    return 0
  fi

  if [[ "$raw" == *" "* ]]; then
    ONLYMACS_ROUTED_ARGS=("chat" "$raw")
    if [[ -z "$ONLYMACS_ROUTER_INTERPRETATION" ]]; then
      if [[ "$reused_workspace_default" -eq 1 ]]; then
        ONLYMACS_ROUTER_INTERPRETATION="chat best-available (workspace default)"
      else
        ONLYMACS_ROUTER_INTERPRETATION="chat best-available"
      fi
    fi
    return 0
  fi

  return 1
}
