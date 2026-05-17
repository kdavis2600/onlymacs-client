#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ONLYMACS_ENABLE_CONTENT_PIPELINE_VALIDATORS=1
# shellcheck source=../../integrations/common/onlymacs-cli.sh
source "$ROOT_DIR/integrations/common/onlymacs-cli.sh"

PLAN_PATH="${ONLYMACS_BUENOS_AIRES_PLAN_PATH:-$ROOT_DIR/scripts/qa/fixtures/buenos-aires-content-pipeline-plan.md}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-ba-pipeline.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export ONLYMACS_STATE_DIR="$TEMP_DIR/state"
export ONLYMACS_JSON_MODE=1
export ONLYMACS_PROGRESS=0
export ONLYMACS_RETURNS_DIR="$TEMP_DIR/inbox"

PROJECT_DIR="$TEMP_DIR/project"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

pass_count=0
fail_count=0

record_pass() {
  printf '[buenos-aires-pipeline] PASS %s %s\n' "$1" "$2"
  pass_count=$((pass_count + 1))
}

record_fail() {
  printf '[buenos-aires-pipeline] FAIL %s %s\n' "$1" "$2" >&2
  fail_count=$((fail_count + 1))
}

check() {
  local id="$1"
  local description="$2"
  shift 2
  if "$@"; then
    record_pass "$id" "$description"
  else
    record_fail "$id" "$description"
  fi
}

assert_eq() {
  [[ "${1:-}" == "${2:-}" ]]
}

assert_contains_text() {
  [[ "${1:-}" == *"${2:-}"* ]]
}

assert_file() {
  [[ -r "$1" ]]
}

assert_no_json_batch() {
  local prompt="$1"
  local filename="$2"
  if orchestrated_should_batch_plan_json_step "$prompt" "$filename"; then
    return 1
  fi
  return 0
}

assert_no_exact_count() {
  local prompt="$1"
  [[ -z "$(prompt_exact_count_requirement "$prompt" || true)" ]]
}

assert_validation_pass() {
  local artifact_path="$1"
  local prompt="$2"
  validate_return_artifact "$artifact_path" "$prompt"
  [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]
}

assert_validation_fail_contains() {
  local artifact_path="$1"
  local prompt="$2"
  local needle="$3"
  validate_return_artifact "$artifact_path" "$prompt"
  [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" && "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" == *"$needle"* ]]
}

validation_prompt_for_step() {
  local step_index="$1"
  orchestrated_validation_prompt "Execute the Buenos Aires content-pipeline plan file." "$step_index" ""
}

write_set_definitions() {
  local path="$1"
  jq -n '{
    packSlug: "learn-spanish-buenos-aires",
    sourcePrefix: "es-bue",
    languageId: "es-AR",
    modules: {
      vocab: [
        {id: "es-bue-vocab-beg-01", title: "Greetings, People, and Voseo Basics"},
        {id: "es-bue-vocab-beg-02", title: "Food, Cafe, and Ordering Basics"}
      ],
      sentences: [
        {id: "es-bue-sent-01", title: "Greetings, Courtesy, and Voseo Openers"},
        {id: "es-bue-sent-02", title: "Cafe Ordering and Simple Requests"}
      ],
      lessons: [
        {id: "es-bue-lesson-01", title: "Buenos Aires Greetings and Voseo Basics"},
        {id: "es-bue-lesson-02", title: "Ordering Coffee and Food Politly"}
      ],
      alphabet: [
        {id: "es-bue-alpha-01", title: "Rioplatense Sounds"}
      ]
    }
  }' >"$path"
}

write_vocab() {
  local path="$1"
  local count="$2"
  jq -n --argjson count "$count" '[
    range(0; $count) as $i | {
      id: ("es-bue-vocab-" + (($i + 1) | tostring)),
      setId: (if $i < 20 then "es-bue-vocab-beg-01" else "es-bue-vocab-beg-02" end),
      lemma: ("palabra-" + (($i + 1) | tostring)),
      display: ("Palabra " + (($i + 1) | tostring)),
      translationsByLocale: {
        en: ("word " + (($i + 1) | tostring)),
        de: ("Wort " + (($i + 1) | tostring)),
        fr: ("mot " + (($i + 1) | tostring)),
        it: ("parola " + (($i + 1) | tostring)),
        ko: ("단어 " + (($i + 1) | tostring))
      },
      pos: "noun",
      stage: "beginner",
      register: "neutral",
      grammar: {gender: "common"},
      supportedPromptModes: ["recognition","production"],
      defaultPromptMode: "recognition",
      source: {kind: "qa-fixture"}
    }
  ]' >"$path"
}

write_sentences() {
  local path="$1"
  local count="$2"
  jq -n --argjson count "$count" '[
    range(0; $count) as $i | {
      id: ("es-bue-sent-" + (($i + 1) | tostring)),
      setId: (if $i < 20 then "es-bue-sent-01" else "es-bue-sent-02" end),
      text: ("Disculpá, ejemplo " + (($i + 1) | tostring) + "."),
      translationsByLocale: {
        en: ("example " + (($i + 1) | tostring)),
        de: ("Beispiel " + (($i + 1) | tostring)),
        fr: ("exemple " + (($i + 1) | tostring)),
        it: ("esempio " + (($i + 1) | tostring)),
        ko: ("예문 " + (($i + 1) | tostring))
      },
      register: "neutral",
      scenarioTags: ["greeting"],
      cityContextTags: ["buenos-aires"],
      translationMode: "natural",
      supportedPromptModes: ["recognition","production"],
      defaultPromptMode: "recognition",
      segmentation: [{text: "Disculpá", gloss: "excuse me"}],
      frequencyBand: "common",
      patternType: "request",
      teachingOrder: ($i + 1),
      source: {kind: "qa-fixture"},
      highlights: {en: {viet: ["Disculpá"], trans: ["excuse me"]}},
      usage: {note: "Beginner-safe Buenos Aires interaction."}
    }
  ]' >"$path"
}

write_lessons() {
  local path="$1"
  local block_count="${2:-4}"
  local quiz_count="${3:-8}"
  jq -n --argjson block_count "$block_count" --argjson quiz_count "$quiz_count" '[
    range(0; 2) as $i | {
      id: ("es-bue-lesson-0" + (($i + 1) | tostring)),
      setId: (if $i == 0 then "es-bue-lesson-01" else "es-bue-lesson-02" end),
      level: "beginner",
      titlesByLocale: {
        en: ("Lesson " + (($i + 1) | tostring)),
        de: ("Lektion " + (($i + 1) | tostring)),
        fr: ("Leçon " + (($i + 1) | tostring)),
        it: ("Lezione " + (($i + 1) | tostring)),
        ko: ("수업 " + (($i + 1) | tostring))
      },
      scenario: "Reusable Buenos Aires interaction",
      grammarFocus: ["voseo"],
      prerequisiteSetIds: ["es-bue-alpha-01", "es-bue-vocab-beg-01", "es-bue-sent-01"],
      cityTags: ["buenos-aires"],
      notesByLocale: {
        en: "Practice polite daily speech.",
        de: "Uebe hoefliche Alltagssprache.",
        fr: "Pratiquez le langage quotidien poli.",
        it: "Esercita il linguaggio quotidiano cortese.",
        ko: "공손한 일상 표현을 연습합니다."
      },
      contentBlocks: [range(0; $block_count) | {type: "tip", text: ("Block " + ((. + 1) | tostring))}],
      quiz: [range(0; $quiz_count) | {type: "multipleChoice", prompt: ("Quiz " + ((. + 1) | tostring)), answer: "a"}]
    }
  ]' >"$path"
}

write_alphabet() {
  local path="$1"
  local count="$2"
  jq -n --argjson count "$count" '[
    range(0; $count) as $i | {
      id: ("es-bue-alpha-card-" + (($i + 1) | tostring)),
      groupId: "es-bue-alpha-01",
      order: ($i + 1),
      display: (["a","e","i","o","u","ll","h","r","rr","ñ","vos","tenés","podés","mira","espera"][$i] // ("sound-" + (($i + 1) | tostring))),
      reading: "clear vowel or Rioplatense cue",
      phonicsCue: "Keep the sound short and clear.",
      noteByLocale: {
        en: "Short note.",
        de: "Kurzer Hinweis.",
        fr: "Note courte.",
        it: "Nota breve.",
        ko: "짧은 메모."
      },
      unitType: "sound",
      example: "hola",
      exampleTranslationByLocale: {
        en: "hello",
        de: "hallo",
        fr: "bonjour",
        it: "ciao",
        ko: "안녕하세요"
      },
      pronunciationFeatures: ["clear-vowel"],
      scriptId: "latin"
    }
  ]' >"$path"
}

export ONLYMACS_PLAN_FILE_PATH="$PLAN_PATH"
compile_prompt_with_plan_file "Execute the Buenos Aires content-pipeline plan file." >/dev/null
step1_prompt="$(validation_prompt_for_step 1)"
step2_prompt="$(validation_prompt_for_step 2)"
step3_prompt="$(validation_prompt_for_step 3)"
step4_prompt="$(validation_prompt_for_step 4)"
step5_prompt="$(validation_prompt_for_step 5)"

check F01 "plan file exists and is readable" assert_file "$PLAN_PATH"
check F02 "plan parser detects five steps" assert_eq "${ONLYMACS_PLAN_FILE_STEP_COUNT:-}" "5"
check F03 "plan parser detects all expected output filenames" assert_eq "$(for i in 1 2 3 4 5; do printf '%s\n' "$(printf '%s' "$ONLYMACS_PLAN_FILE_CONTENT" | plan_file_step_filename_from_content "$i")"; done | awk 'BEGIN { first=1 } { if (!first) printf ","; printf "%s", $0; first=0 }')" "setDefinitions.json,vocab-groups-01-02.json,sentences-groups-01-02.json,lessons-groups-01-02.json,alphabet.json"
check F04 "step 1 validation prompt does not inherit later exact-count requirements" assert_no_exact_count "$step1_prompt"
check F05 "vocab step triggers JSON batching" orchestrated_should_batch_plan_json_step "$step2_prompt" "vocab-groups-01-02.json"
check F06 "sentence step triggers JSON batching" orchestrated_should_batch_plan_json_step "$step3_prompt" "sentences-groups-01-02.json"
check F07 "small lesson step does not trigger JSON batching" assert_no_json_batch "$step4_prompt" "lessons-groups-01-02.json"
check F08 "alphabet card-count range is parsed" assert_eq "$(prompt_card_count_range "$step5_prompt")" "12 16"

set_defs="$TEMP_DIR/setDefinitions.json"
write_set_definitions "$set_defs"
check F09 "valid setDefinitions passes schema validation" assert_validation_pass "$set_defs" "$step1_prompt"

missing_alpha="$TEMP_DIR/setDefinitions-missing-alpha.json"
jq 'del(.modules.alphabet)' "$set_defs" >"$missing_alpha"
check F10 "setDefinitions missing alphabet module fails before gold review" assert_validation_fail_contains "$missing_alpha" "$step1_prompt" "modules.alphabet"

missing_expected_id="$TEMP_DIR/setDefinitions-missing-id.json"
jq 'del(.modules.vocab[1])' "$set_defs" >"$missing_expected_id"
check F11 "setDefinitions missing expected group id fails" assert_validation_fail_contains "$missing_expected_id" "$step1_prompt" "es-bue-vocab-beg-02"

vocab40="$TEMP_DIR/vocab-40.json"
write_vocab "$vocab40" 40
check F12 "valid 40-item vocab artifact passes" assert_validation_pass "$vocab40" "$step2_prompt"

vocab39="$TEMP_DIR/vocab-39.json"
write_vocab "$vocab39" 39
check F13 "39-item vocab artifact fails exact-count validation" assert_validation_fail_contains "$vocab39" "$step2_prompt" "expected 40"

vocab_no_translations="$TEMP_DIR/vocab-no-translations.json"
jq '.[0] |= del(.translationsByLocale)' "$vocab40" >"$vocab_no_translations"
check F14 "vocab missing translationsByLocale fails schema validation" assert_validation_fail_contains "$vocab_no_translations" "$step2_prompt" "translationsByLocale"

vocab_missing_ko="$TEMP_DIR/vocab-missing-ko.json"
jq '.[0].translationsByLocale |= del(.ko)' "$vocab40" >"$vocab_missing_ko"
check F15 "vocab missing one required learner locale fails" assert_validation_fail_contains "$vocab_missing_ko" "$step2_prompt" "translationsByLocale"

vocab_duplicate="$TEMP_DIR/vocab-duplicate.json"
jq '.[1].lemma = .[0].lemma' "$vocab40" >"$vocab_duplicate"
check F16 "duplicate vocab lemma fails uniqueness validation" assert_validation_fail_contains "$vocab_duplicate" "$step2_prompt" "duplicate item terms"

vocab_banned="$TEMP_DIR/vocab-banned.json"
jq '.[0].lemma = "boludo" | .[0].display = "boludo"' "$vocab40" >"$vocab_banned"
check F17 "banned Buenos Aires slang term fails safety validation" assert_validation_fail_contains "$vocab_banned" "$step2_prompt" "banned Buenos Aires"

sentences40="$TEMP_DIR/sentences-40.json"
write_sentences "$sentences40" 40
check F18 "valid 40-item sentence artifact passes" assert_validation_pass "$sentences40" "$step3_prompt"

sent_no_trans_highlight="$TEMP_DIR/sentences-no-trans-highlight.json"
jq '.[0].highlights.en |= del(.trans)' "$sentences40" >"$sent_no_trans_highlight"
check F19 "sentence missing highlights.en.trans fails schema validation" assert_validation_fail_contains "$sent_no_trans_highlight" "$step3_prompt" "highlights.en.viet/trans"

sent_no_city="$TEMP_DIR/sentences-no-city.json"
jq '.[0] |= del(.cityContextTags)' "$sentences40" >"$sent_no_city"
check F20 "sentence missing cityContextTags fails schema validation" assert_validation_fail_contains "$sent_no_city" "$step3_prompt" "cityContextTags"

sent_missing_ko="$TEMP_DIR/sentences-missing-ko.json"
jq '.[0].translationsByLocale |= del(.ko)' "$sentences40" >"$sent_missing_ko"
check F21 "sentence missing one required learner locale fails" assert_validation_fail_contains "$sent_missing_ko" "$step3_prompt" "locale translations"

lessons2="$TEMP_DIR/lessons-2.json"
write_lessons "$lessons2" 4 8
check F22 "valid 2-lesson artifact passes" assert_validation_pass "$lessons2" "$step4_prompt"

lessons_short_blocks="$TEMP_DIR/lessons-short-blocks.json"
write_lessons "$lessons_short_blocks" 3 8
check F23 "lesson with fewer than four content blocks fails" assert_validation_fail_contains "$lessons_short_blocks" "$step4_prompt" "at least 4 contentBlocks"

lessons_short_quiz="$TEMP_DIR/lessons-short-quiz.json"
write_lessons "$lessons_short_quiz" 4 7
check F24 "lesson with fewer than eight quiz questions fails" assert_validation_fail_contains "$lessons_short_quiz" "$step4_prompt" "at least 8 quiz"

lessons_no_prereq="$TEMP_DIR/lessons-no-prereq.json"
jq '.[0] |= del(.prerequisiteSetIds)' "$lessons2" >"$lessons_no_prereq"
check F25 "lesson missing prerequisiteSetIds fails" assert_validation_fail_contains "$lessons_no_prereq" "$step4_prompt" "prerequisites"

alphabet12="$TEMP_DIR/alphabet-12.json"
write_alphabet "$alphabet12" 12
check F26 "valid 12-card alphabet artifact passes" assert_validation_pass "$alphabet12" "$step5_prompt"

alphabet11="$TEMP_DIR/alphabet-11.json"
write_alphabet "$alphabet11" 11
check F27 "alphabet artifact below requested range fails" assert_validation_fail_contains "$alphabet11" "$step5_prompt" "between 12 and 16"

alphabet_no_features="$TEMP_DIR/alphabet-no-features.json"
jq '.[0] |= del(.pronunciationFeatures)' "$alphabet12" >"$alphabet_no_features"
check F28 "alphabet missing pronunciationFeatures fails" assert_validation_fail_contains "$alphabet_no_features" "$step5_prompt" "phonics card schema"

batch_prompt="${step2_prompt}

Batch validation override:
Return exactly 10 entries/items as a JSON array.
Keep every item term unique with no duplicates."
batch_valid="$TEMP_DIR/vocab-batch-valid.json"
write_vocab "$batch_valid" 10
batch_invalid="$TEMP_DIR/vocab-batch-invalid.json"
jq '.[0] |= del(.translationsByLocale)' "$batch_valid" >"$batch_invalid"
batch_context_check() {
  assert_validation_pass "$batch_valid" "$batch_prompt" &&
    assert_validation_fail_contains "$batch_invalid" "$batch_prompt" "translationsByLocale"
}
check F29 "JSON batch validation uses batch exact count while preserving schema context" batch_context_check

resume_missing_plan_check() {
  local run_dir="$TEMP_DIR/resume-missing-plan"
  local output
  mkdir -p "$run_dir/files"
  printf 'Execute the missing plan.\n' >"$run_dir/prompt.txt"
  jq -n --arg missing "$TEMP_DIR/missing-plan.md" '{
    model_alias: "remote-first",
    route_scope: "swarm",
    plan_file_path: $missing,
    steps: [{id: "step-01", status: "running"}],
    resume_step_index: 1
  }' >"$run_dir/plan.json"
  if output="$(run_resume_orchestrated "$run_dir" 2>&1)"; then
    return 1
  fi
  assert_contains_text "$output" "original plan file is no longer readable"
}
check F30 "resume fails clearly when the original plan file is missing" resume_missing_plan_check

generic_shape_check() {
  local prompt="Customer records should follow the shape: id, name, email."
  local valid="$TEMP_DIR/customer-records.json"
  local invalid="$TEMP_DIR/customer-records-invalid.json"
  jq -n '[{id: "cust-1", name: "Ava", email: "ava@example.com"}]' >"$valid"
  jq '.[0] |= del(.email)' "$valid" >"$invalid"
  assert_validation_pass "$valid" "$prompt" &&
    assert_validation_fail_contains "$invalid" "$prompt" "prompt-declared fields"
}
check F31 "generic prompt-declared JSON shape validation works outside Buenos Aires" generic_shape_check

printf '[buenos-aires-pipeline] Summary: %s passed, %s failed\n' "$pass_count" "$fail_count"
if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
