# Artifact extraction, target-path, and bundle-shape helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after transport helpers are loaded.

sanitize_return_filename() {
  local raw="${1:-}"
  local base
  base="$(basename "$raw")"
  base="$(printf '%s' "$base" | tr -cd 'A-Za-z0-9._-')"
  if [[ -z "$base" || "$base" == "." || "$base" == ".." ]]; then
    printf 'answer.md'
  else
    printf '%s' "$base"
  fi
}

filename_from_prompt() {
  local prompt="${1:-}"
  printf '%s\n' "$prompt" \
    | sed -nE 's/.*([Ff]ile[[:space:]]+)?named[[:space:]]+`?([A-Za-z0-9._-]+\.[A-Za-z0-9]+)`?.*/\2/p' \
    | head -n 1
}

extension_for_fence_language() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    javascript|js|node|nodejs)
      printf 'js'
      ;;
    typescript|ts)
      printf 'ts'
      ;;
    python|py)
      printf 'py'
      ;;
    swift)
      printf 'swift'
      ;;
    go|golang)
      printf 'go'
      ;;
    json)
      printf 'json'
      ;;
    markdown|md)
      printf 'md'
      ;;
    *)
      printf 'md'
      ;;
  esac
}

extract_single_fenced_code_block() {
  local content_path="${1:-}"
  local output_path="${2:-}"
  [[ -s "$content_path" && -n "$output_path" ]] || return 1
  perl -0777 -ne '
    my $body = $_;
    my $count = () = $body =~ /```/g;
    exit 1 unless $count == 2;
    $body =~ s/^\s*```[A-Za-z0-9_-]*[ \t]*\r?\n?//s;
    $body =~ s/\r?\n?```\s*$//s;
    print $body;
  ' "$content_path" >"$output_path"
  [[ -s "$output_path" ]]
}

extract_marked_artifact_block() {
  local content_path="${1:-}"
  local output_path="${2:-}"
  [[ -s "$content_path" && -n "$output_path" ]] || return 1
  perl -0777 -ne '
    if (/ONLYMACS_ARTIFACT_BEGIN[^\n]*?\.(?:json|cjs|mjs|jsx|tsx|html|css|swift|go|py|md|txt|sh|js|ts)(.*?)\r?\n?ONLYMACS_ARTIFACT_END/s) {
      my $artifact = $1;
      $artifact =~ s/^\r?\n//;
      print $artifact;
      exit 0;
    }
    if (/ONLYMACS_ARTIFACT_BEGIN[^\n]*\r?\n(.*?)\r?\n?ONLYMACS_ARTIFACT_END/s) {
      print $1;
      exit 0;
    }
    exit 1;
  ' "$content_path" >"$output_path"
  [[ -s "$output_path" ]]
}

artifact_target_path_from_content() {
  local content_path="${1:-}"
  [[ -s "$content_path" ]] || return 1
  perl -0777 -ne '
    exit 1 unless /ONLYMACS_ARTIFACT_BEGIN([^\n]*)/s;
    my $header = $1 // "";
    my $value = "";
    if ($header =~ /\b(?:target_path|target|path)=["'"'"']([^"'"'"'\s]+)["'"'"']/) {
      $value = $1;
    } elsif ($header =~ /\b(?:target_path|target|path)=([^\s]+)/) {
      $value = $1;
    } elsif ($header =~ /\bfilename=["'"'"']([^"'"'"']+)["'"'"']/) {
      $value = $1;
    } elsif ($header =~ /\bfilename=([^\s]+)/) {
      $value = $1;
    }
    if ($value =~ /^([A-Za-z0-9._\/-]+\.(?:json|cjs|mjs|jsx|tsx|html|css|swift|go|py|md|txt|sh|js|ts|patch|diff))(?:[\{\[<].*)?$/) {
      $value = $1;
    }
    $value =~ s/^\s+|\s+$//g;
    print $value if length $value;
  ' "$content_path"
}

safe_artifact_target_path() {
  local raw="${1:-}"
  local fallback="${2:-}"
  raw="$(printf '%s' "$raw" | tr -d '\r' | sed -E 's#\\#/#g; s#^\./##; s#/{2,}#/#g; s#^/##; s#[[:space:]]+$##; s#^[[:space:]]+##')"
  case "$raw" in
    *"{"*|*"}"*|*"["*|*"]"*|*"\""*|*"'"*|*"<"*|*">"*|*"|"*|*";"*|*","*|*":"*)
      raw="$(basename "$fallback")"
      ;;
  esac
  if [[ -z "$raw" || "$raw" == "." || "$raw" == ".." || "$raw" == *"/../"* || "$raw" == "../"* || "$raw" == *"/.." ]]; then
    raw="$(basename "$fallback")"
  fi
  if [[ -z "$raw" ]]; then
    raw="answer.md"
  fi
  printf '%s' "$raw"
}

artifact_schema_name() {
  local artifact_path="${1:-}"
  [[ -s "$artifact_path" && "$artifact_path" == *.json ]] || return 1
  jq -r '.schema // .kind // .artifact_type // empty' "$artifact_path" 2>/dev/null | head -1
}

artifact_is_bundle_json() {
  local artifact_path="${1:-}"
  local schema
  schema="$(artifact_schema_name "$artifact_path" 2>/dev/null || true)"
  [[ "$schema" == "onlymacs.artifact_bundle.v1" || "$schema" == "onlymacs.artifact_bundle" ]]
}

json_path_values_are_safe() {
  local artifact_path="${1:-}"
  jq -e '
    def badpath:
      type != "string" or
      length == 0 or
      startswith("/") or
      test("(^|/)\\.\\.(/|$)") or
      test("\\\\") or
      test("[\u0000-\u001f]");
    [
      ((.files // [])[]? | (.path // .target_path // .filename // empty)),
      ((.patches // [])[]? | (.path // .target_path // .filename // empty))
    ] | all(.[]; (badpath | not))
  ' "$artifact_path" >/dev/null 2>&1
}

artifact_bundle_duplicate_targets() {
  local artifact_path="${1:-}"
  jq -r '
    [
      ((.files // [])[]? | (.path // .target_path // .filename // empty)),
      ((.patches // [])[]? | (.path // .target_path // .filename // empty))
    ]
    | map(select(length > 0))
    | group_by(.)[]?
    | select(length > 1)
    | .[0]
  ' "$artifact_path" 2>/dev/null | head -5 | paste -sd ', ' -
}

artifact_bundle_commands_are_safe() {
  local artifact_path="${1:-}"
  local allow_installs="${ONLYMACS_CONTEXT_ALLOW_INSTALL:-${ONLYMACS_ALLOW_BUNDLE_INSTALL_COMMANDS:-0}}"
  jq -e --argjson allow_installs "$([[ "$allow_installs" == "1" || "$allow_installs" == "true" ]] && printf 'true' || printf 'false')" '
    def command_text:
      if type == "string" then .
      elif type == "object" then (.command // .cmd // .run // "")
      else ""
      end;
    def normalized: ascii_downcase | gsub("^\\s+|\\s+$"; "");
    def dangerous:
      normalized as $cmd |
      (
        ($cmd | test("(^|[;&|[:space:]])sudo([[:space:]]|$)")) or
        ($cmd | test("rm[[:space:]]+-[^\\n]*r[^\\n]*f[[:space:]]+(/|~|\\$HOME|\\.)")) or
        ($cmd | test("(curl|wget)[^\\n]*[|][[:space:]]*(sh|bash|zsh)")) or
        ($cmd | test("(^|[;&|[:space:]])(dd|mkfs|diskutil|launchctl|security)[[:space:]]")) or
        ($cmd | test("chmod[[:space:]]+777")) or
        (($cmd | test("(^|[;&|[:space:]])(brew|npm|pnpm|yarn|pip|pip3|cargo|gem)[[:space:]]+(global[[:space:]]+)?(install|add)")) and ($allow_installs | not))
      );
    [
      ((.commands // [])[]? | command_text),
      ((.validators // [])[]? | command_text)
    ] | all(.[]; ((. | tostring | length) == 0) or ((. | dangerous) | not))
  ' "$artifact_path" >/dev/null 2>&1
}

patch_file_paths_are_safe() {
  local patch_path="${1:-}"
  [[ -s "$patch_path" ]] || return 1
  perl -ne '
    chomp;
    my @paths;
    if (/^diff --git a\/(.+?) b\/(.+)$/) { push @paths, $1, $2; }
    if (/^(?:---|\+\+\+) ([ab]\/.+)$/) { my $p = $1; $p =~ s#^[ab]/##; push @paths, $p; }
    for my $p (@paths) {
      next if $p eq "/dev/null";
      if ($p eq "" || $p =~ m#^/# || $p =~ m#(^|/)\.\.(/|$)# || $p =~ /\\/ || $p =~ /[\x00-\x1f]/) {
        exit 1;
      }
    }
  ' "$patch_path"
}

validate_artifact_bundle_json() {
  local artifact_path="${1:-}"
  local duplicates
  if ! jq -e '
    type == "object" and
    ((.schema // .kind // .artifact_type // "") | test("^onlymacs\\.artifact_bundle(\\.v1)?$")) and
    ((.files // []) | type == "array") and
    ((.patches // []) | type == "array") and
    ((.commands // []) | type == "array") and
    ((.validators // []) | type == "array") and
    (((.files // []) | length) + ((.patches // []) | length) > 0) and
    all((.files // [])[]?; type == "object" and ((.path // .target_path // .filename // "") | length > 0) and (((.content // .source // .body // "") | tostring | length) > 0)) and
    all((.patches // [])[]?; type == "object" and ((.path // .target_path // .filename // "") | length > 0) and (((.patch // .content // "") | tostring | length) > 0)) and
    all((.commands // [])[]?; (type == "string") or (type == "object" and (((.command // .cmd // .run // "") | tostring | length) > 0))) and
    all((.validators // [])[]?; (type == "string") or (type == "object" and (((.command // .cmd // .run // .kind // "") | tostring | length) > 0)))
  ' "$artifact_path" >/dev/null 2>&1; then
    printf 'artifact bundle must declare schema onlymacs.artifact_bundle.v1 and contain files/patches with safe target paths and content; commands/validators must be arrays when present'
    return 1
  fi
  if ! json_path_values_are_safe "$artifact_path"; then
    printf 'artifact bundle includes an unsafe target path'
    return 1
  fi
  if ! artifact_bundle_commands_are_safe "$artifact_path"; then
    printf 'artifact bundle includes unsafe command metadata or dependency install commands without --allow-installs'
    return 1
  fi
  duplicates="$(artifact_bundle_duplicate_targets "$artifact_path" || true)"
  if [[ -n "$duplicates" ]]; then
    printf 'artifact bundle includes duplicate target paths: %s' "$duplicates"
    return 1
  fi
  return 0
}

artifact_braces_balanced() {
  local artifact_path="${1:-}"
  perl -0777 -ne '
    my $text = $_;
    my $open = ($text =~ tr/{//);
    my $close = ($text =~ tr/}//);
    exit($open == $close ? 0 : 1);
  ' "$artifact_path"
}
