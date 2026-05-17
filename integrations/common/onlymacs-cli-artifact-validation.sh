# Artifact repair and semantic validation helpers for OnlyMacs.
# This file is sourced by onlymacs-cli.sh after execution-state helpers are loaded.

repair_json_artifact_if_possible() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local repaired_path validation_log
  ONLYMACS_JSON_REPAIR_STATUS="skipped"
  ONLYMACS_JSON_REPAIR_MESSAGE=""

  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    ONLYMACS_JSON_REPAIR_STATUS="skipped"
    ONLYMACS_JSON_REPAIR_MESSAGE="jq unavailable; JSON repair skipped"
    return 0
  fi
  if jq -e . "$artifact_path" >/dev/null 2>&1; then
    ONLYMACS_JSON_REPAIR_STATUS="not_needed"
    ONLYMACS_JSON_REPAIR_MESSAGE="JSON already parsed cleanly"
    return 0
  fi

  repaired_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-repair-XXXXXX")"
  perl -0777 -ne '
    my $s = $_;
    $s =~ s/^\x{FEFF}//;
    if ($s =~ /ONLYMACS_ARTIFACT_BEGIN[^\n]*\n(.*?)\n?ONLYMACS_ARTIFACT_END/s) {
      $s = $1;
    }
    $s =~ s/^\s*```(?:json)?\s*\n?//i;
    $s =~ s/\n?```\s*$//;
    $s =~ s/^\s+|\s+$//g;
    if ($s =~ /^\s*\[/s && $s =~ /\]\s*\]\s*$/s && $s !~ /\}\s*\]\s*$/s) {
      $s =~ s/\]\s*\]\s*$/\]\}\]/s;
    }
    $s =~ s/"([^"\\]*(?:\\.[^"\\]*)*)\x27\s*([,\]}])/"$1"$2/g;
    my $start = index($s, "{");
    my $array_start = index($s, "[");
    if ($array_start >= 0 && ($start < 0 || $array_start < $start)) {
      $start = $array_start;
    }
    exit 1 if $start < 0;
    my $open = substr($s, $start, 1);
    my $close = $open eq "[" ? "]" : "}";
    my @stack;
    my $in_string = 0;
    my $escape = 0;
    my $end = -1;
    for (my $i = $start; $i < length($s); $i++) {
      my $ch = substr($s, $i, 1);
      if ($in_string) {
        if ($escape) { $escape = 0; next; }
        if ($ch eq "\\") { $escape = 1; next; }
        if ($ch eq "\"") { $in_string = 0; next; }
        next;
      }
      if ($ch eq "\"") { $in_string = 1; next; }
      if ($ch eq "{" || $ch eq "[") { push @stack, $ch; next; }
      if ($ch eq "}" || $ch eq "]") {
        my $expected = $stack[-1] eq "{" ? "}" : "]";
        next unless $ch eq $expected;
        pop @stack;
        if (!@stack) { $end = $i; last; }
      }
    }
    exit 1 if $end < $start;
    my $json = substr($s, $start, $end - $start + 1);
    sub onlymacs_json_quote {
      my ($v) = @_;
      $v =~ s/^\s+|\s+$//g;
      $v =~ s/\\(?!["\\\/bfnrtu])/\\\\/g;
      $v =~ s/"/\\"/g;
      return "\"" . $v . "\"";
    }
    my %entity = (
      aacute => "á", eacute => "é", iacute => "í", oacute => "ó", uacute => "ú",
      Aacute => "Á", Eacute => "É", Iacute => "Í", Oacute => "Ó", Uacute => "Ú",
      ntilde => "ñ", Ntilde => "Ñ", uuml => "ü", Uuml => "Ü",
      iquest => "¿", iexcl => "¡", quot => "\\\"", amp => "&", lt => "<", gt => ">"
    );
    $json =~ s/&([A-Za-z]+);/exists $entity{$1} ? $entity{$1} : (exists $entity{lc($1)} ? $entity{lc($1)} : "&$1;")/ge;
    $json =~ s/"([^"\\]*(?:\\.[^"\\]*)*)\x27\s*([,\]}])/"$1"$2/g;
    for my $field (qw(example example_en grammarNote dialectNote lemma display english pos stage register topic)) {
      $json =~ s/("$field"\s*:\s*)(?!["\[\{0-9tfn-])([^,\}\]\r\n]+)(?=,|\})/$1 . onlymacs_json_quote($2)/ge;
    }
    for my $field (qw(id setId groupId itemId)) {
      $json =~ s/"$field([A-Za-z0-9][A-Za-z0-9_.:-]*)"/"\"$field\":\"$1\""/ge;
    }
    1 while $json =~ s/,\s*([}\]])/$1/g;
    print $json;
  ' "$artifact_path" >"$repaired_path" 2>/dev/null || {
    rm -f "$repaired_path"
    ONLYMACS_JSON_REPAIR_STATUS="failed"
    ONLYMACS_JSON_REPAIR_MESSAGE="could not extract a balanced JSON object or array"
    return 0
  }

  validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-json-repair-log-XXXXXX")"
  if jq -e . "$repaired_path" >/dev/null 2>"$validation_log"; then
    mv "$repaired_path" "$artifact_path"
    ONLYMACS_JSON_REPAIR_STATUS="repaired"
    ONLYMACS_JSON_REPAIR_MESSAGE="recovered strict JSON before model retry"
  else
    ONLYMACS_JSON_REPAIR_STATUS="failed"
    ONLYMACS_JSON_REPAIR_MESSAGE="$(head -5 "$validation_log" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-300)"
    rm -f "$repaired_path"
  fi
  rm -f "$validation_log"
}

repair_rioplatense_tuteo_artifact_if_possible() {
  ONLYMACS_DIALECT_REPAIR_STATUS="skipped"
  ONLYMACS_DIALECT_REPAIR_MESSAGE=""
}

repair_source_card_usage_artifact_if_possible() {
  ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS="skipped"
  ONLYMACS_SOURCE_CARD_USAGE_REPAIR_MESSAGE=""
}

repair_source_card_schema_aliases_if_possible() {
  ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS="skipped"
  ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_MESSAGE=""
}

validate_content_pipeline_json_artifact() {
  ONLYMACS_CONTENT_PIPELINE_VALIDATION_STATUS="skipped"
  ONLYMACS_CONTENT_PIPELINE_VALIDATION_MESSAGE=""
}

prompt_learner_locales_json() {
  printf '[]'
}

prompt_card_count_range() {
  return 1
}

artifact_mode_requested_filename() {
  local prompt="${1:-}"
  local requested
  requested="$(filename_from_prompt "$prompt")"
  if [[ -n "$requested" ]]; then
    sanitize_return_filename "$requested"
    return 0
  fi
  return 1
}

prompt_requests_artifact_mode() {
  local prompt="${1:-}"
  local lowered
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  if artifact_mode_requested_filename "$prompt" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$lowered" =~ (create|write|generate|make|return|output|produce|build|save)[^[:cntrl:]]*([a-z0-9._-]+\.(js|mjs|cjs|ts|tsx|jsx|py|rb|go|swift|html|css|json|yaml|yml|toml|csv|sql|md|txt|sh)|makefile|dockerfile) ]]; then
    return 0
  fi
  string_has_any "$lowered" \
    "fenced code block" \
    "create a file" \
    "write a file" \
    "generate a file" \
    "save as a file" \
    "save it as a file" \
    "save as an artifact" \
    "save it as an artifact" \
    "save the generated" \
    "single file" \
    "one file" \
    "one-file" \
    "cli tool" \
    "command-line utility" \
    "bash utility" \
    "command line tool" \
    "reusable tool" \
    "json file" \
    "csv file" \
    "pdf file" \
    "yaml file" \
    "yml file" \
    "toml config file" \
    "toml file" \
    "sql migration file" \
    "react component file" \
    "typescript file" \
    "python file" \
    "bash script" \
    "ruby script" \
    "swift helper file" \
    "swift source file" \
    "html file" \
    "markdown file" \
    "go command-line" \
    "go command line" \
    "standalone python app" \
    "standalone app" \
    "starter project" \
    "zipped starter project" \
    "standalone web app" \
    "single-page app" \
    "html app" \
    "create a .js file" \
    "write a .js file" \
    "generate a .js file" \
    "create a js file" \
    "write a js file" \
    "generate a js file" \
    "javascript file" \
    "single javascript file" \
    "single js file" \
    "return only one" \
    "complete js file" \
    "complete javascript file" \
    "dependency-free node" \
    "node.js script" \
    "node script" \
    "javascript script" \
    "python script" \
    "shell script" \
    "script file"
}

prompt_requests_content_pack_mode() {
  local prompt="${1:-}"
  local lowered
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "generate" \
    "create" \
    "write" \
    "emit" \
    "materialize" \
    "produce" \
    "build" \
    "make" || return 1
  string_has_any "$lowered" \
    "content pack" \
    "content pipeline" \
    "content generation" \
    "step 2 content" \
    "step2 content" \
    "content-complete" \
    "actual content" \
    "vocab.json" \
    "sentences.json" \
    "lessons.json" \
    "setdefinitions.json" \
    "alphabet.json"
}

prompt_word_count() {
  printf '%s' "${1:-}" | wc -w | tr -d ' '
}

prompt_numeric_count_after_words() {
  local prompt="${1:-}"
  local words_regex="${2:-items?|entries|files|outputs?|sections?|steps?|pages?}"
  printf '%s\n' "$prompt" | ONLYMACS_COUNT_WORDS_REGEX="$words_regex" perl -0777 -ne '
    my $regex = $ENV{ONLYMACS_COUNT_WORDS_REGEX} || "items?|entries|files|outputs?|sections?|steps?|pages?";
    my $max = 0;
    while (/\b(?:exactly|all|full|complete|create|generate|write|emit|produce|build)?\s*(\d{1,5})\s+(?:$regex)\b/gi) {
      $max = $1 if $1 > $max;
    }
    print $max if $max > 0;
  '
}

prompt_large_exact_count_requirement() {
  local prompt="${1:-}" count
  count="$(prompt_exact_count_requirement "$prompt" || true)"
  [[ "$count" =~ ^[0-9]+$ && "$count" -ge 80 ]]
}

prompt_requests_many_files_or_outputs() {
  local prompt="${1:-}" count
  count="$(prompt_numeric_count_after_words "$prompt" 'files?|outputs?|artifacts?|documents?|sections?')"
  [[ "$count" =~ ^[0-9]+$ && "$count" -ge 3 ]]
}

prompt_is_long_and_complex() {
  local prompt="${1:-}" lowered words
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  words="$(prompt_word_count "$prompt")"
  [[ "$words" =~ ^[0-9]+$ && "$words" -ge 120 ]] || return 1
  string_has_any "$lowered" \
    "validate" \
    "validation" \
    "resume" \
    "checkpoint" \
    "artifacts" \
    "outputs" \
    "pipeline" \
    "end-to-end" \
    "full" \
    "complete" \
    "entire" \
    "all"
}

prompt_needs_plan_mode() {
  local prompt="${1:-}"
  local lowered
  if [[ "${ONLYMACS_SIMPLE_MODE:-0}" -eq 1 ]]; then
    return 1
  fi
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  if prompt_requests_content_pack_mode "$prompt"; then
    return 0
  fi
  if prompt_large_exact_count_requirement "$prompt"; then
    return 0
  fi
  if prompt_requests_many_files_or_outputs "$prompt"; then
    return 0
  fi
  if prompt_is_long_and_complex "$prompt"; then
    return 0
  fi
  string_has_any "$lowered" \
    "step 1 to step" \
    "step 1 through step" \
    "plan then execute" \
    "plan and execute" \
    "multi-step" \
    "multiple steps" \
    "end-to-end" \
    "overnight" \
    "long complicated" \
    "resume if" \
    "checkpoint" \
    "pipeline doc" \
    "full pipeline" \
    "complete pipeline" \
    "entire pipeline" \
    "full content" \
    "content-complete" \
    "large refactor" \
    "full refactor" \
    "whole repo" \
    "entire repo"
}

prompt_requests_extended_mode() {
  local prompt="${1:-}"
  local lowered
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  if [[ "${ONLYMACS_SIMPLE_MODE:-0}" -eq 1 ]]; then
    return 1
  fi
  if [[ -n "${ONLYMACS_RESOLVED_PLAN_FILE_PATH:-}" || -n "${ONLYMACS_PLAN_FILE_PATH:-}" ]]; then
    return 0
  fi
  if [[ "${ONLYMACS_EXECUTION_MODE:-auto}" == "extended" || "${ONLYMACS_EXECUTION_MODE:-auto}" == "overnight" ]]; then
    return 0
  fi
  if prompt_requests_artifact_mode "$prompt"; then
    return 0
  fi
  if prompt_requests_content_pack_mode "$prompt"; then
    return 0
  fi
  if prompt_needs_plan_mode "$prompt"; then
    return 0
  fi
  string_has_any "$lowered" \
    "step 1 to step" \
    "step 1 through step" \
    "pipeline doc" \
    "multi-step" \
    "long complicated" \
    "resume if"
}

prompt_exact_count_requirement() {
  local prompt="${1:-}"
  local count scoped_override_count batch_override_count
  batch_override_count="$(printf '%s' "$prompt" | perl -0777 -ne '
    if (/Batch validation override:\s*(.*)\z/s) {
      my $tail = $1;
      if ($tail =~ /\b(?:Return|Create|Use)?\s*(?:exactly\s*)?([0-9]+)\s+(?:entries|entry|items|item|words|word|terms|term|vocab|vocabulary|sentences|sentence|rows|row|objects|object|records|record|lessons|lesson)\b/i) {
        print $1;
      }
    }
  ')"
  if [[ "$batch_override_count" =~ ^[0-9]+$ ]]; then
    printf '%s' "$batch_override_count"
    return 0
  fi
  scoped_override_count="$(printf '%s' "$prompt" | perl -0777 -ne '
    if (/Validation for this step:\s*(.*?)(?:\n\s*Final response format:|\z)/s) {
      my $tail = $1;
      my @matches;
      my $noun = qr/(?:entries|entry|items|item|words|word|terms|term|cards|card|lessons|lesson|sentences|sentence|vocab|vocabulary|rows|row|objects|object|records|record|questions|question|examples|example|ids|id|files|file)/;
      for my $line (split /\n/, $tail) {
        my $lc = lc($line);
        while ($line =~ /\b(?:Return|Create|Use)?\s*(?:exactly\s*)?([0-9]+)\s+(?:(?:[A-Za-z_-]+)\s+){0,5}$noun\b/gi) {
          my $n = $1;
          my $score = 10;
          $score += 120 if $lc =~ /\b(total|required|overall|grand total|final artifact|artifact|deliverable|create|contain|contains|must contain)\b/;
          $score += 80 if $lc =~ /\breturn\s+exactly\b/;
          $score -= 160 if $lc =~ /\b(per|for each|in each|within each|every)\s+(?:set|group|batch|file|section|topic|member|step)\b/;
          $score -= 120 if $lc =~ /\b(?:items|sentences|entries)\s+per\s+(?:set|group)\b/;
          push @matches, [$score, $n];
        }
        while ($line =~ /\b(?:total|required|overall|grand total)[^0-9\n]{0,100}\b(?:exactly\s*)?([0-9]+)\s+$noun\b/gi) {
          push @matches, [220, $1];
        }
        while ($line =~ /\b([0-9]+)\s+$noun\s+total\b/gi) {
          push @matches, [230, $1];
        }
      }
      if (@matches) {
        @matches = sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } @matches;
        print $matches[0]->[1];
      }
    }
  ')"
  if [[ "$scoped_override_count" =~ ^[0-9]+$ ]]; then
    printf '%s' "$scoped_override_count"
    return 0
  fi
  count="$(printf '%s' "$prompt" | perl -ne '
    my $line = $_;
    my $lc = lc($line);
    my $noun = qr/(?:entries|entry|items|item|words|word|terms|term|cards|card|lessons|lesson|sentences|sentence|vocab|vocabulary|rows|row|objects|object|records|record|questions|question|examples|example|ids|id|files|file)/;
    while ($line =~ /\b[Ee]xactly\s+([0-9]+)\s+(?:(?:[A-Za-z_-]+)\s+){0,5}$noun\s+total\b/g) {
      push @matches, [260, $1];
    }
    while ($line =~ /\b[Ee]xactly\s+([0-9]+)\s+(?:(?:[A-Za-z_-]+)\s+){0,5}$noun\b/g) {
      my $n = $1;
      my $after = substr($lc, $+[0], 120);
      my $score = 10;
      $score += 100 if $lc =~ /\b(total|required|overall|grand total|final artifact|artifact|deliverable|create|contain|contains|must contain)\b/;
      $score -= 120 if $after =~ /^\s+(?:per|for each|in each)\b/ || $lc =~ /\bper\s+(?:set|group|batch|file|section|topic|member|step)\b/;
      push @matches, [$score, $n];
    }
    while ($line =~ /\b(?:total|required|overall|grand total)[^0-9\n]{0,100}\b(?:exactly\s*)?([0-9]+)\s+$noun\b/g) {
      push @matches, [220, $1];
    }
    while ($line =~ /\b([0-9]+)\s+$noun\s+total\b/g) {
      push @matches, [210, $1];
    }
    END {
      if (@matches) {
        @matches = sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } @matches;
        print $matches[0]->[1];
      }
    }
  ')"
  if [[ "$count" =~ ^[0-9]+$ ]]; then
    printf '%s' "$count"
    return 0
  fi
  return 1
}

prompt_items_per_set_requirement() {
  local prompt="${1:-}"
  local count
  count="$(printf '%s' "$prompt" | perl -ne '
    while (/\b[Ee]xactly\s+([0-9]+)\s+(?:entries|entry|items|item|sentences|sentence|rows|row|objects|object|records|record)\s+per\s+(?:set|group)\b/g) {
      $count = $1
    }
    while (/\b(?:items|sentences|entries)\s+per\s+(?:set|group)\s*[:=-]\s*(?:exactly\s*)?([0-9]+)\b/ig) {
      $count = $1
    }
    END { print $count if defined $count }
  ')"
  if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
    printf '%s' "$count"
    return 0
  fi
  return 1
}

artifact_semantic_entry_count() {
  local artifact_path="${1:-}"
  local count json_count
  [[ -f "$artifact_path" ]] || return 1
  if [[ "$artifact_path" == *.json ]] && command -v jq >/dev/null 2>&1; then
    json_count="$(jq -r '
      if type == "array" then
        length
      elif type == "object" then
        (
          if (.items? | type) == "array" then .items | length
          elif (.entries? | type) == "array" then .entries | length
          elif (.data? | type) == "array" then .data | length
          elif (.results? | type) == "array" then .results | length
          elif (.records? | type) == "array" then .records | length
          elif (.cards? | type) == "array" then .cards | length
          elif (.vocab? | type) == "array" and ((.sentences? | type) != "array") and ((.lessons? | type) != "array") then .vocab | length
          elif (.sentences? | type) == "array" and ((.vocab? | type) != "array") and ((.lessons? | type) != "array") then .sentences | length
          elif (.lessons? | type) == "array" and ((.vocab? | type) != "array") and ((.sentences? | type) != "array") then .lessons | length
          elif ([.[]? | select(type == "array") | length] | length) > 0 then [.[]? | select(type == "array") | length] | add
          elif ([.[]? | select(type == "object") | .[]? | select(type == "array") | length] | length) > 0 then [.[]? | select(type == "object") | .[]? | select(type == "array") | length] | add
          else empty
          end
        )
      else
        empty
      end
    ' "$artifact_path" 2>/dev/null || true)"
    if [[ "$json_count" =~ ^[0-9]+$ && "$json_count" -gt 0 ]]; then
      printf '%s' "$json_count"
      return 0
    fi
  fi
  count="$(tr '\n' ' ' < "$artifact_path" | rg -o '[{][[:space:]]*["'\'']?(vi|pt|vietnamese|portuguese|spanish|french|german|italian|indonesian|japanese|korean|chinese|thai|word|term|phrase)["'\'']?[[:space:]]*:' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
    printf '%s' "$count"
    return 0
  fi
  return 1
}

artifact_vocabulary_terms() {
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
        elif ([.[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "array")[]]
        elif ([.[]? | select(type == "object") | .[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "object") | .[]? | select(type == "array")[]]
        else []
        end
      else
        []
      end;
    item_array[]?
    | select(type == "object")
    | (
      .vietnamese
      // .vi
      // .pt
      // .portuguese
      // .spanish
      // .french
      // .german
      // .italian
      // .indonesian
      // .japanese
      // .korean
      // .chinese
      // .thai
      // .lemma
      // .display
      // .word
      // .term
      // .phrase
      // .text
      // .sentence
      // empty
    )
    | tostring
    | gsub("^\\s+|\\s+$"; "")
    | select(length > 0)
    | ascii_downcase
  ' "$artifact_path" 2>/dev/null
}

artifact_json_prompt_terms() {
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
        elif ([.[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "array")[]]
        elif ([.[]? | select(type == "object") | .[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "object") | .[]? | select(type == "array")[]]
        else []
        end
      else
        []
      end;
    item_array[]?
    | select(type == "object")
    | (
      .display
      // .term
      // .word
      // .phrase
      // .text
      // .sentence
      // .vietnamese
      // .vi
      // .pt
      // .portuguese
      // .spanish
      // .french
      // .german
      // .italian
      // .indonesian
      // .japanese
      // .korean
      // .chinese
      // .thai
      // .lemma
      // empty
    )
    | tostring
    | gsub("^\\s+|\\s+$"; "")
    | select(length > 0)
    | ascii_downcase
  ' "$artifact_path" 2>/dev/null
}

join_terms_csv() {
  local limit="${ONLYMACS_TERMS_CSV_LIMIT:-2000}"
  [[ "$limit" =~ ^[0-9]+$ && "$limit" -gt 0 ]] || limit=2000
  awk 'NF { out = out ? out ", " $0 : $0 } END { print out }' | cut -c 1-"$limit"
}

artifact_duplicate_vocabulary_terms() {
  local artifact_path="${1:-}"
  artifact_vocabulary_terms "$artifact_path" | LC_ALL=C sort | uniq -d | join_terms_csv
}

prompt_requires_unique_item_terms() {
  local prompt="${1:-}" lowered
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" \
    "keep every lemma unique" \
    "every lemma unique" \
    "unique normalized" \
    "unique normalized lemma" \
    'unique `lemma`' \
    "unique lemma plus display" \
    'unique normalized `lemma` plus `display`' \
    "unique normalized lemma plus display" \
    "unique lemma" \
    "unique lemmas" \
    "no duplicate" \
    "no duplicates" \
    "unique terms" \
    "unique vocabulary" \
    "unique entries" \
    "unique items"
}


prompt_named_json_shape_specs_tsv() {
  local prompt="${1:-}"
  printf '%s' "$prompt" | perl -0777 -ne '
    my @specs;
    while (/^\s*(?:[-*]\s*)?([A-Za-z][A-Za-z0-9_-]*)\s+(?:items?|entries?|records?|objects?|cards?)\s+(?:should|must)\s+follow[^\n]*?\bshape\s*:\s*([^\n.]+)/gmi) {
      push @specs, [$1, $2];
    }
    while (/^\s*(?:[-*]\s*)?([A-Za-z][A-Za-z0-9_-]*)\s+(?:schema|shape)\s*:\s*([^\n.]+)/gmi) {
      push @specs, [$1, $2];
    }
    my %seen;
    for my $spec (@specs) {
      my ($label, $fields) = @$spec;
      my @fields;
      for my $field (split(/\s*,\s*/, $fields)) {
        $field =~ s/`//g;
        $field =~ s/^\s+|\s+$//g;
        next unless $field =~ /^[A-Za-z_][A-Za-z0-9_]*$/;
        push @fields, $field;
      }
      next unless @fields;
      my $key = lc($label) . "\t" . join(",", @fields);
      next if $seen{$key}++;
      print lc($label) . "\t" . join(",", @fields) . "\n";
    }
  '
}

validate_prompt_named_json_shape_artifact() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local specs spec_count base_lower label fields_csv singular fields_json
  local matched_count=0
  local failures=()
  ONLYMACS_PROMPT_SHAPE_VALIDATION_STATUS="skipped"
  ONLYMACS_PROMPT_SHAPE_VALIDATION_MESSAGE=""

  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  specs="$(prompt_named_json_shape_specs_tsv "$prompt" || true)"
  [[ -n "$specs" ]] || return 0

  spec_count="$(printf '%s\n' "$specs" | awk 'NF { count++ } END { print count + 0 }')"
  base_lower="$(basename "$artifact_path" | tr '[:upper:]' '[:lower:]')"

  while IFS=$'\t' read -r label fields_csv; do
    [[ -n "$label" && -n "$fields_csv" ]] || continue
    singular="${label%s}"
    if [[ "$spec_count" -gt 1 && "$base_lower" != *"$label"* && "$base_lower" != *"$singular"* ]]; then
      continue
    fi
    fields_json="$(printf '%s' "$fields_csv" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')"
    matched_count=$((matched_count + 1))
    if ! jq -e --argjson fields "$fields_json" '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          elif ([.[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "array")[]]
          elif ([.[]? | select(type == "object") | .[]? | select(type == "array")] | length) > 0 then [.[]? | select(type == "object") | .[]? | select(type == "array")[]]
          else []
          end
        else []
        end;
      artifact_items as $items
      | ($items | length) > 0 and all($items[]; . as $item |
        type == "object" and all($fields[]; . as $field | $item | has($field))
      )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("${label} JSON items are missing one or more prompt-declared fields: ${fields_csv}")
    fi
  done <<<"$specs"

  if [[ "${#failures[@]}" -gt 0 ]]; then
    ONLYMACS_PROMPT_SHAPE_VALIDATION_STATUS="failed"
    ONLYMACS_PROMPT_SHAPE_VALIDATION_MESSAGE="$(printf '%s; ' "${failures[@]}" | sed -E 's/; $//' | cut -c 1-500)"
  elif [[ "$matched_count" -gt 0 ]]; then
    ONLYMACS_PROMPT_SHAPE_VALIDATION_STATUS="passed"
    ONLYMACS_PROMPT_SHAPE_VALIDATION_MESSAGE="prompt-declared JSON shape validation passed."
  fi
}

node_builtin_module_name() {
  case "${1:-}" in
    assert|async_hooks|buffer|child_process|cluster|console|constants|crypto|dgram|diagnostics_channel|dns|domain|events|fs|http|http2|https|inspector|module|net|os|path|perf_hooks|process|punycode|querystring|readline|repl|stream|string_decoder|timers|tls|trace_events|tty|url|util|v8|vm|wasi|worker_threads|zlib)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

artifact_external_require_modules() {
  local artifact_path="${1:-}"
  local module
  [[ -f "$artifact_path" ]] || return 0
  rg -o "require[[:space:]]*\\([[:space:]]*['\"][^'\"]+['\"][[:space:]]*\\)" "$artifact_path" 2>/dev/null \
    | sed -E "s/^.*['\"]([^'\"]+)['\"].*$/\\1/" \
    | while IFS= read -r module; do
      case "$module" in
        node:*|./*|../*|/*)
          continue
          ;;
      esac
      if node_builtin_module_name "$module"; then
        continue
      fi
      printf '%s\n' "$module"
    done | LC_ALL=C sort -u | join_terms_csv
}

chat_return_filename() {
  local prompt="${1:-}"
  local content_path="${2:-}"
  local requested language extension
  requested="$(filename_from_prompt "$prompt")"
  if [[ -n "$requested" ]]; then
    sanitize_return_filename "$requested"
    return 0
  fi
  language="$(sed -nE 's/^```([A-Za-z0-9_-]+).*/\1/p' "$content_path" | head -n 1)"
  extension="$(extension_for_fence_language "$language")"
  printf 'answer.%s' "$extension"
}

validate_return_artifact() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local validation_log
  local failures=()
  local expected_count actual_count bytes lowered_prompt external_modules content_pack_expected duplicate_terms
  ONLYMACS_RETURN_VALIDATION_STATUS="skipped"
  ONLYMACS_RETURN_VALIDATION_MESSAGE=""

  if [[ ! -s "$artifact_path" ]]; then
    failures+=("artifact is empty")
  fi

  case "$artifact_path" in
    *.json)
      if ! command -v jq >/dev/null 2>&1; then
        ONLYMACS_RETURN_VALIDATION_STATUS="skipped"
        ONLYMACS_RETURN_VALIDATION_MESSAGE="jq was not available for a JSON syntax check."
        return 0
      fi
      validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-artifact-validation-XXXXXX")"
      if jq -e . "$artifact_path" > /dev/null 2>"$validation_log"; then
        ONLYMACS_RETURN_VALIDATION_STATUS="passed"
        ONLYMACS_RETURN_VALIDATION_MESSAGE="jq JSON validation passed."
        if artifact_is_bundle_json "$artifact_path"; then
          if validate_artifact_bundle_json "$artifact_path" >"$validation_log" 2>&1; then
            ONLYMACS_RETURN_VALIDATION_MESSAGE="artifact bundle validation passed."
          else
            failures+=("$(head -5 "$validation_log" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-300)")
          fi
        fi
      else
        failures+=("$(head -5 "$validation_log" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-300)")
      fi
      rm -f "$validation_log"
      ;;
    *.js|*.cjs|*.mjs)
      if ! command -v node >/dev/null 2>&1; then
        ONLYMACS_RETURN_VALIDATION_STATUS="skipped"
        ONLYMACS_RETURN_VALIDATION_MESSAGE="Node.js was not available for a JavaScript syntax check."
        return 0
      fi
      if head -n 1 "$artifact_path" | rg -q '^#!.*(const|let|var|function|import|require|console\.|=>)' 2>/dev/null; then
        failures+=("JavaScript shebang line appears to contain code; the artifact likely lost line breaks")
      fi
      if rg -q '(^|[^[:alnum:]_$])console[[:space:]]*\(' "$artifact_path" 2>/dev/null; then
        failures+=("JavaScript calls console as a function; use console.log/error instead")
      fi
      lowered_prompt="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
      if string_has_any "$lowered_prompt" "dependency-free" "no dependencies" "zero external dependencies"; then
        external_modules="$(artifact_external_require_modules "$artifact_path" || true)"
        if [[ -n "$external_modules" ]]; then
          failures+=("artifact imports external modules despite a dependency-free request: ${external_modules}")
        fi
      fi
      validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-artifact-validation-XXXXXX")"
      if node --check "$artifact_path" >"$validation_log" 2>&1; then
        ONLYMACS_RETURN_VALIDATION_STATUS="passed"
        ONLYMACS_RETURN_VALIDATION_MESSAGE="node --check passed."
      else
        failures+=("$(head -5 "$validation_log" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-300)")
      fi
      rm -f "$validation_log"
      ;;
    *.html|*.htm)
      if ! rg -qi '<(html|body|main|section|article|div|canvas|script|style)[^>]*>' "$artifact_path" 2>/dev/null; then
        failures+=("HTML artifact does not appear to contain document or app markup")
      fi
      if rg -qi '<script[^>]*>' "$artifact_path" 2>/dev/null && ! rg -qi '</script>' "$artifact_path" 2>/dev/null; then
        failures+=("HTML artifact contains an opening script tag without a closing script tag")
      fi
      if rg -qi '<style[^>]*>' "$artifact_path" 2>/dev/null && ! rg -qi '</style>' "$artifact_path" 2>/dev/null; then
        failures+=("HTML artifact contains an opening style tag without a closing style tag")
      fi
      ;;
    *.css|*.scss)
      if ! artifact_braces_balanced "$artifact_path"; then
        failures+=("stylesheet artifact has unbalanced braces")
      fi
      ;;
    *.ts|*.tsx|*.jsx)
      if ! artifact_braces_balanced "$artifact_path"; then
        failures+=("TypeScript/JSX artifact has unbalanced braces")
      fi
      if rg -q 'from[[:space:]]+["'\''][.][.]/[.][.]' "$artifact_path" 2>/dev/null; then
        failures+=("TypeScript/JSX artifact imports from a path that climbs two directories; verify target location before apply")
      fi
      ;;
  esac

  if rg -qi 'add the remaining|remaining [0-9]+ entries|omitted for brevity|and so on|lorem ipsum|insert [^[:cntrl:]]+ here|replace [^[:cntrl:]]+ here|fill in later|//[[:space:]]*\.\.\.|/\*[[:space:]]*\.\.\.' "$artifact_path" 2>/dev/null; then
    failures+=("artifact contains placeholder or ellipsis text")
  fi
  if rg -q '(^|[^[:alpha:]])(TODO|TBD)([^[:alpha:]]|$)' "$artifact_path" 2>/dev/null; then
    failures+=("artifact contains TODO/TBD placeholder text")
  fi

  expected_count="$(prompt_exact_count_requirement "$prompt" || true)"
  bytes="$(chat_output_bytes "$artifact_path")"
  if [[ -n "$expected_count" && "$expected_count" -ge 10 && "$artifact_path" == *.js && "$bytes" =~ ^[0-9]+$ && "$bytes" -gt 0 && "$bytes" -lt 300 ]]; then
    failures+=("artifact is suspiciously small for a generated JavaScript file with an exact count requirement (${bytes} bytes)")
  fi

  if [[ -n "$expected_count" ]]; then
    actual_count="$(artifact_semantic_entry_count "$artifact_path" || true)"
    if [[ -z "$actual_count" ]]; then
      failures+=("could not verify the requested exact count of ${expected_count} entries/items")
    elif [[ "$actual_count" != "$expected_count" ]]; then
      failures+=("expected ${expected_count} entries/items but found ${actual_count}")
    fi
  fi

  if [[ "$artifact_path" == *.json ]] && prompt_requires_unique_item_terms "$prompt"; then
    duplicate_terms="$(artifact_duplicate_vocabulary_terms "$artifact_path" || true)"
    if [[ -n "$duplicate_terms" ]]; then
      failures+=("duplicate item terms found: ${duplicate_terms}")
    fi
  fi

  if [[ "$artifact_path" == *.json ]] && prompt_requests_content_pack_mode "$prompt"; then
    content_pack_expected="$(content_pack_expected_json_count "$artifact_path" || true)"
    if [[ -n "$content_pack_expected" ]]; then
      actual_count="$(jq -r 'if type == "array" then length else empty end' "$artifact_path" 2>/dev/null || true)"
      if [[ -z "$actual_count" ]]; then
        failures+=("expected a JSON array with ${content_pack_expected} content-pack items")
      elif [[ "$actual_count" != "$content_pack_expected" ]]; then
        failures+=("expected ${content_pack_expected} content-pack items but found ${actual_count}")
      fi
    fi
  fi

  if [[ "$artifact_path" == *.json ]] && string_has_any "$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')" "partofspeech" "vietnamese, english"; then
    validation_log="$(mktemp "${TMPDIR:-/tmp}/onlymacs-artifact-fields-XXXXXX")"
    if ! jq -e '
      type == "array" and
      all(.[]; type == "object" and
        ((.vietnamese // "") | tostring | length > 0) and
        ((.english // "") | tostring | length > 0) and
        ((.partOfSpeech // "") | tostring | length > 0) and
        ((.pronunciation // "") | tostring | length > 0) and
        ((.difficulty // "") | tostring | length > 0) and
        ((.topic // "") | tostring | length > 0) and
        ((.example // "") | tostring | length > 0))
    ' "$artifact_path" >/dev/null 2>"$validation_log"; then
      failures+=("JSON entries are missing one or more required fields")
    fi
    rm -f "$validation_log"
  fi

  if [[ "$artifact_path" == *.json ]]; then
    validate_prompt_named_json_shape_artifact "$artifact_path" "$prompt"
    if [[ "${ONLYMACS_PROMPT_SHAPE_VALIDATION_STATUS:-skipped}" == "failed" ]]; then
      failures+=("${ONLYMACS_PROMPT_SHAPE_VALIDATION_MESSAGE:-prompt-declared JSON shape validation failed}")
    fi
    validate_content_pipeline_json_artifact "$artifact_path" "$prompt"
    if [[ "${ONLYMACS_CONTENT_PIPELINE_VALIDATION_STATUS:-skipped}" == "failed" ]]; then
      failures+=("${ONLYMACS_CONTENT_PIPELINE_VALIDATION_MESSAGE:-Content-pipeline artifact schema validation failed}")
    fi
  fi

  if [[ "${#failures[@]}" -gt 0 ]]; then
    ONLYMACS_RETURN_VALIDATION_STATUS="failed"
    ONLYMACS_RETURN_VALIDATION_MESSAGE="$(printf '%s; ' "${failures[@]}" | sed -E 's/; $//' | cut -c 1-500)"
  elif [[ -z "$ONLYMACS_RETURN_VALIDATION_MESSAGE" ]]; then
    ONLYMACS_RETURN_VALIDATION_STATUS="passed"
    ONLYMACS_RETURN_VALIDATION_MESSAGE="basic artifact validation passed."
  fi
}
