# Source-card/content-pipeline validation extension for historical QA fixtures.
# This file is intentionally not sourced by the default CLI path.
# Enable with ONLYMACS_ENABLE_CONTENT_PIPELINE_VALIDATORS=1 for content-pipeline test runs.

repair_rioplatense_tuteo_artifact_if_possible() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local lowered before_hash after_hash
  ONLYMACS_DIALECT_REPAIR_STATUS="skipped"
  ONLYMACS_DIALECT_REPAIR_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  lowered="$(printf '%s\n%s' "$(basename "$artifact_path")" "$prompt" | tr '[:upper:]' '[:lower:]')"
  if ! string_has_any "$lowered" "buenos aires" "rioplatense" "es-bue" "voseo" "cards-source" "source-card" "source cards"; then
    return 0
  fi
  before_hash="$(shasum -a 256 "$artifact_path" 2>/dev/null | awk '{print $1}')"
  perl -0pi -e '
    s/\bPodes\b/Podés/g;
    s/\bpodes\b/podés/g;
    s/\bTenes\b/Tenés/g;
    s/\btenes\b/tenés/g;
    s/\bQueres\b/Querés/g;
    s/\bqueres\b/querés/g;
    s/\bVenis\b/Venís/g;
    s/\bvenis\b/venís/g;
    s/\bSabes\b/Sabés/g;
    s/\bsabes\b/sabés/g;
    s/\bPuedes\b/Podés/g;
    s/\bpuedes\b/podés/g;
    s/\bTienes\b/Tenés/g;
    s/\btienes\b/tenés/g;
    s/\bQuieres\b/Querés/g;
    s/\bquieres\b/querés/g;
    s/\bVienes\b/Venís/g;
    s/\bvienes\b/venís/g;
    s/\bConoces\b/Conocés/g;
    s/\bconoces\b/conocés/g;
    s/\bLlamas\b/Llamás/g;
    s/\bllamas\b/llamás/g;
    s/\bVives\b/Vivís/g;
    s/\bvives\b/vivís/g;
    s/\bTrabajas\b/Trabajás/g;
    s/\btrabajas\b/trabajás/g;
    s/\bPierdes\b/Perdés/g;
    s/\bpierdes\b/perdés/g;
    s/\bConfiguras\b/Configurás/g;
    s/\bconfiguras\b/configurás/g;
    s/\bEstudias\b/Estudiás/g;
    s/\bestudias\b/estudiás/g;
    s/\bNecesitas\b/Necesitás/g;
    s/\bnecesitas\b/necesitás/g;
    s/\bBuscas\b/Buscás/g;
    s/\bbuscas\b/buscás/g;
    s/\bUsas\b/Usás/g;
    s/\busas\b/usás/g;
    s/\bConfirmas\b/Confirmás/g;
    s/\bconfirmas\b/confirmás/g;
    s/\bVerificas\b/Verificás/g;
    s/\bverificas\b/verificás/g;
    s/\bGiras\b/Girás/g;
    s/\bgiras\b/girás/g;
    s/\bGuardas\b/Guardás/g;
    s/\bguardas\b/guardás/g;
    s/\bTomas\b/Tomás/g;
    s/\btomas\b/tomás/g;
    s/\bReservas\b/Reservás/g;
    s/\breservas\b/reservás/g;
    s/\bPagas\b/Pagás/g;
    s/\bpagas\b/pagás/g;
    s/\bCompras\b/Comprás/g;
    s/\bcompras\b/comprás/g;
    s/\bComes\b/Comés/g;
    s/\bcomes\b/comés/g;
    s/\bBebes\b/Bebés/g;
    s/\bbebes\b/bebés/g;
    s/\bPides\b/Pedís/g;
    s/\bpides\b/pedís/g;
    s/\bAbri\b/Abrí/g;
    s/\babri\b/abrí/g;
    s/\bPide\b/Pedí/g;
    s/\bDices\b/Decís/g;
    s/\bdices\b/decís/g;
    s/\bHaces\b/Hacés/g;
    s/\bhaces\b/hacés/g;
    s/\bBusca\b/Buscá/g;
    s/\bbusca\b/buscá/g;
    s/\bUsa\b/Usá/g;
    s/\busa\b/usá/g;
    s/\bConfirma\b/Confirmá/g;
    s/\bconfirma\b/confirmá/g;
    s/\bVerifica\b/Verificá/g;
    s/\bverifica\b/verificá/g;
    s/\bGira\b/Girá/g;
    s/\bgira\b/girá/g;
    s/\bAcompaña\b/Acompañá/g;
    s/\bacompaña\b/acompañá/g;
    s/\bCombínalo\b/Combinálo/g;
    s/\bcombínalo\b/combinálo/g;
    s/\bGuarda\b/Guardá/g;
    s/\bguarda\b/guardá/g;
    s/\bToma\b/Tomá/g;
    s/\btoma\b/tomá/g;
    s/\bReserva\b/Reservá/g;
    s/\breserva\b/reservá/g;
    s/\bPaga\b/Pagá/g;
    s/\bpaga\b/pagá/g;
    s/\bCompra\b/Comprá/g;
    s/\bcompra\b/comprá/g;
    s/\bCambia\b/Cambiá/g;
    s/\bcambia\b/cambiá/g;
    s/\bLlama\b/Llamá/g;
    s/\bEscribe\b/Escribí/g;
    s/\bescribe\b/escribí/g;
    s/\bRepite\b/Repetí/g;
    s/\brepite\b/repetí/g;
    s/\bEspera\b/Esperá/g;
    s/\bespera\b/esperá/g;
    s/\bMira\b/Mirá/g;
    s/\bmira\b/mirá/g;
    s/Pedecí/Pedí/g;
    s/pedecí/pedí/g;
    s/Se pedí/Se pide/g;
    s/se pedí/se pide/g;
    s/\b(Me|Te|Se|Nos|Lo|La|Los|Las|Le|Les) (buscá|usá|confirmá|verificá|girá|acompañá|guardá|tomá|reservá|pagá|comprá|cambiá|llamá|escribí|repetí|esperá|mirá|escuchá)(?=$|[^[:alpha:]])/$1 . " " . ({ "buscá"=>"busca", "usá"=>"usa", "confirmá"=>"confirma", "verificá"=>"verifica", "girá"=>"gira", "acompañá"=>"acompaña", "guardá"=>"guarda", "tomá"=>"toma", "reservá"=>"reserva", "pagá"=>"paga", "comprá"=>"compra", "cambiá"=>"cambia", "llamá"=>"llama", "escribí"=>"escribe", "repetí"=>"repite", "esperá"=>"espera", "mirá"=>"mira", "escuchá"=>"escucha" }->{$2})/ge;
    s/\b(me|te|se|nos|lo|la|los|las|le|les) (buscá|usá|confirmá|verificá|girá|acompañá|guardá|tomá|reservá|pagá|comprá|cambiá|llamá|escribí|repetí|esperá|mirá|escuchá)(?=$|[^[:alpha:]])/$1 . " " . ({ "buscá"=>"busca", "usá"=>"usa", "confirmá"=>"confirma", "verificá"=>"verifica", "girá"=>"gira", "acompañá"=>"acompaña", "guardá"=>"guarda", "tomá"=>"toma", "reservá"=>"reserva", "pagá"=>"paga", "comprá"=>"compra", "cambiá"=>"cambia", "llamá"=>"llama", "escribí"=>"escribe", "repetí"=>"repite", "esperá"=>"espera", "mirá"=>"mira", "escuchá"=>"escucha" }->{$2})/ge;
    s/\btrabajá (mi|tu|su) /trabaja $1 /g;
    s/\bTrabajá (mi|tu|su) /Trabaja $1 /g;
    s/\bMantequilla\b/Manteca/g;
    s/\bmantequilla\b/manteca/g;
    s/\bEn el metro\b/En el subte/g;
    s/\ben el metro\b/en el subte/g;
    s/\bDel metro\b/Del subte/g;
    s/\bdel metro\b/del subte/g;
    s/\bAl metro\b/Al subte/g;
    s/\bal metro\b/al subte/g;
    s/\bZumo\b/Jugo/g;
    s/\bzumo\b/jugo/g;
    s/\bRefresco\b/Gaseosa/g;
    s/\brefresco\b/gaseosa/g;
    s/\bPastel\b/Torta/g;
    s/\bpastel\b/torta/g;
    s/\bCamarero\b/Mozo/g;
    s/\bcamarero\b/mozo/g;
    s/\bMesero\b/Mozo/g;
    s/\bmesero\b/mozo/g;
    s/\bpide (el|la|un|una|los|las)\b/pedí $1/g;
    s/\bPide (el|la|un|una|los|las)\b/Pedí $1/g;
    s/\bPerdona\b/Perdoná/g;
    s/\bperdona\b/perdoná/g;
    s/(?<!\p{L})Dí(?!\p{L})/Decí/g;
    s/(?<!\p{L})dí(?!\p{L})/decí/g;
    s/\bEscucha\b/Escuchá/g;
    s/\bescucha\b/escuchá/g;
    s/\bLee\b/Leé/g;
    s/\blee\b/leé/g;
    s/\bLleva\b/Llevá/g;
    s/\blleva\b/llevá/g;
    s/\bEvita\b/Evitá/g;
    s/\bevita\b/evitá/g;
    s/\bConsulta\b/Consultá/g;
    s/\bRevisa\b/Revisá/g;
    s/\bElige\b/Elegí/g;
    s/\belige\b/elegí/g;
    s/\bPrueba\b/Probá/g;
    s/\bprueba\b/probá/g;
    s/\bVuelve\b/Volvé/g;
    s/\bvuelve\b/volvé/g;
    s/\bSube\b/Subí/g;
    s/\bsube\b/subí/g;
    s/\bBaja\b/Bajá/g;
    s/\bbaja\b/bajá/g;
    s/\bSigue\b/Seguí/g;
    s/\bsigue\b/seguí/g;
    s/\bEnciende\b/Encendé/g;
    s/\benciende\b/encendé/g;
    s/\bApaga\b/Apagá/g;
    s/\bapaga\b/apagá/g;
    s/\bLimpia\b/Limpiá/g;
    s/\blimpia\b/limpiá/g;
    s/\bMarca\b/Marcá/g;
    s/\bPrograma\b/Programá/g;
    s/\bLlega\b/Llegá/g;
    s/\bEncuentra\b/Encontrá/g;
    s/\bPregunta\b/Preguntá/g;
    s/\bMantén\b/Mantené/g;
    s/\bmantén\b/mantené/g;
    s/\bMantene\b/Mantené/g;
    s/\bmantene\b/mantené/g;
    s/\bInforma\b/Informá/g;
    s/\bAnota\b/Anotá/g;
    s/\bDescribe\b/Describí/g;
    s/\bTrae\b/Traé/g;
    s/\bAbre\b/Abrí/g;
    s/\bCierra\b/Cerrá/g;
    s/\bPide\b/Pedí/g;
    s/\bVisita\b/Visitá/g;
    s/\bInstala\b/Instalá/g;
    s/\bDisfruta\b/Disfrutá/g;
    s/\bConfigura\b/Configurá/g;
    s/\bSe pedí\b/Se pide/g;
    s/\bse pedí\b/se pide/g;
    s/\bCuídate\b/Cuidate/g;
    s/\bcuídate\b/cuidate/g;
    s/\bHas visto\b/Viste/g;
    s/\bhas visto\b/viste/g;
    s/\bHas llamado\b/Llamaste/g;
    s/\bhas llamado\b/llamaste/g;
    s/\bHas probado\b/Probaste/g;
    s/\bhas probado\b/probaste/g;
    s/\bHas comido\b/Comiste/g;
    s/\bhas comido\b/comiste/g;
    s/\bHas bebido\b/Bebiste/g;
    s/\bhas bebido\b/bebiste/g;
    s/\bHas visitado\b/Visitaste/g;
    s/\bhas visitado\b/visitaste/g;
    s/\bHas estado\b/Estuviste/g;
    s/\bhas estado\b/estuviste/g;
  ' "$artifact_path"
  after_hash="$(shasum -a 256 "$artifact_path" 2>/dev/null | awk '{print $1}')"
  if [[ -n "$before_hash" && -n "$after_hash" && "$before_hash" != "$after_hash" ]]; then
    ONLYMACS_DIALECT_REPAIR_STATUS="repaired"
    ONLYMACS_DIALECT_REPAIR_MESSAGE="normalized common tuteo forms to Rioplatense voseo before validation"
  else
    ONLYMACS_DIALECT_REPAIR_STATUS="not_needed"
    ONLYMACS_DIALECT_REPAIR_MESSAGE="no simple Rioplatense dialect cleanup needed"
  fi
}

repair_source_card_usage_artifact_if_possible() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local lowered before_hash after_hash tmp_path
  ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS="skipped"
  ONLYMACS_SOURCE_CARD_USAGE_REPAIR_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  lowered="$(printf '%s\n%s' "$(basename "$artifact_path")" "$prompt" | tr '[:upper:]' '[:lower:]')"
  if ! string_has_any "$lowered" "buenos aires" "rioplatense" "es-bue" "cards-source" "source-card" "source cards" "lean card source"; then
    return 0
  fi
  before_hash="$(shasum -a 256 "$artifact_path" 2>/dev/null | awk '{print $1}')"
  tmp_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-source-card-usage-XXXXXX")"
  if ! jq '
    def clean_usage:
      tostring
      | gsub("</>"; "</target>")
      | gsub("[Oo]ngoing[[:space:]]+study"; "classes and daily learning")
      | gsub("\\b[Ss]tudy\\b"; "learning")
      | gsub("\\b[Rr]eviewing\\b"; "practicing")
      | gsub("\\b[Rr]eview\\b"; "practice")
      | gsub("\\b[Dd]rills?\\b"; "practice")
      | gsub("[Ss]urface[[:space:]]+forms?"; "word")
      | gsub("[Tt]arget[[:space:]]+tags?"; "highlighted word")
      | gsub("\\b[Ww]rapping\\b"; "highlighting")
      | gsub("\\b[Ww]rap\\b"; "highlight")
      | gsub("\\b[Tt]ags?\\b"; "labels")
      | gsub("@"; "o");
    def normalize_usage:
      if type == "array" then
        map(clean_usage)
      elif type == "string" then
        (split("|") | map(clean_usage | gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))) as $parts
        | if ($parts | length) >= 3 then
            $parts[:3]
          elif ($parts | length) > 0 then
            [range(0; 3) | $parts[(if . < ($parts | length) then . else (($parts | length) - 1) end)]]
          else
            []
          end
      else
        .
      end;
    def compact($v): (($v // "") | tostring | ascii_downcase | gsub("[¿?¡!.,;:()\\[\\]\"'\''`]"; "") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""));
    def target_contains_surface($item):
      (compact($item.display)) as $display
      | (compact($item.lemma)) as $lemma
      | any(($item.usage // [])[]?; tostring
          | [match("<target>([^<]+)</target>"; "g").captures[0].string] as $targets
          | any($targets[]; (compact(.)) as $target
              | (($display | length) > 0 and ($target | contains($display)))
                or (($lemma | length) > 0 and ($target | contains($lemma)))));
    def retarget_usage:
      . as $item
      | ((.display // .lemma // "") | tostring | gsub("^[[:space:]]+|[[:space:]]+$"; "")) as $surface
      | if (($surface | length) > 0) and ((.usage? | type) == "array") and ((target_contains_surface($item)) | not) then
          .usage = ((.usage // []) | to_entries | map(
            if .key == 0 then
              (.value | tostring) as $usage
              | if ($usage | test("<target>[^<]+</target>")) then
                  ($usage | gsub("<target>[^<]+</target>"; "<target>" + $surface + "</target>"))
                else
                  "<target>" + $surface + "</target> " + $usage
                end
            else .value end
          ))
        else . end;
    def fix_item:
      if type == "object" then
        (if (.usage? != null) then .usage |= normalize_usage else . end)
        | retarget_usage
      else
        .
      end;
    if type == "array" then
      map(fix_item)
    elif type == "object" then
      if (.items? | type) == "array" then .items |= map(fix_item)
      elif (.entries? | type) == "array" then .entries |= map(fix_item)
      elif (.data? | type) == "array" then .data |= map(fix_item)
      elif (.results? | type) == "array" then .results |= map(fix_item)
      elif (.records? | type) == "array" then .records |= map(fix_item)
      elif (.cards? | type) == "array" then .cards |= map(fix_item)
      else . end
    else
      .
    end
  ' "$artifact_path" >"$tmp_path" 2>/dev/null; then
    rm -f "$tmp_path"
    return 0
  fi
  mv "$tmp_path" "$artifact_path"
  after_hash="$(shasum -a 256 "$artifact_path" 2>/dev/null | awk '{print $1}')"
  if [[ -n "$before_hash" && -n "$after_hash" && "$before_hash" != "$after_hash" ]]; then
    ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS="repaired"
    ONLYMACS_SOURCE_CARD_USAGE_REPAIR_MESSAGE="normalized source-card usage arrays, text, and target tags before validation"
  else
    ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS="not_needed"
    ONLYMACS_SOURCE_CARD_USAGE_REPAIR_MESSAGE="no source-card usage meta cleanup needed"
  fi
}

repair_source_card_schema_aliases_if_possible() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local lowered before_hash after_hash tmp_path
  ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS="skipped"
  ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_MESSAGE=""
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  lowered="$(printf '%s\n%s' "$(basename "$artifact_path")" "$prompt" | tr '[:upper:]' '[:lower:]')"
  if ! string_has_any "$lowered" "buenos aires" "rioplatense" "es-bue" "cards-source" "source-card" "source cards" "lean card source"; then
    return 0
  fi
  before_hash="$(shasum -a 256 "$artifact_path" 2>/dev/null | awk '{print $1}')"
  tmp_path="$(mktemp "${TMPDIR:-/tmp}/onlymacs-source-card-schema-XXXXXX")"
  if ! jq '
    def enum_key($v):
      (($v // "") | tostring | ascii_downcase | gsub("[_[:space:]]+"; "-") | gsub("^-+|-+$"; ""));
    def normalize_stage($v):
      (enum_key($v)) as $s
      | if $s == "begin" or $s == "beginner-level" then "beginner"
        elif $s == "early-intermediate" or $s == "earlyintermediate" or $s == "early-intermediate-level" then "early-intermediate"
        elif $s == "intermediate" or $s == "intermediate-level" then "intermediate"
        elif $s == "upper-intermediate" or $s == "upperintermediate" or $s == "upper-intermediate-level" then "upper-intermediate"
        elif $s == "review" or $s == "review-level" then "review"
        else $v end;
    def normalize_register($v):
      (enum_key($v)) as $s
      | if $s == "informal-voseo" or $s == "informalvoseo" or $s == "informal-vos" or $s == "voseo" then "informal-voseo"
        elif $s == "polite-informal" or $s == "politeinformal" or $s == "polite" then "polite-informal"
        elif $s == "formal-usted" or $s == "formalusted" or $s == "usted" then "formal-usted"
        elif $s == "recognition-only" or $s == "recognitiononly" or $s == "recognition" then "recognition-only"
        else $v end;
    def tag_key:
      tostring
      | ascii_downcase
      | gsub("[^[:alnum:]áéíóúñü-]+"; "-")
      | gsub("^-+|-+$"; "");
    def normalize_tags($v; $fallback; $min; $max):
      (if ($v | type) == "array" then $v else [$v] end)
      | map(tag_key | select(length > 0))
      | . as $tags
      | (if ($tags | length) == 0 then $fallback
         elif ($tags | length) < $min then
           reduce $fallback[] as $tag ($tags; if (index($tag) == null) then . + [$tag] else . end)
         else $tags end)
      | .[:$max];
    def clean_example:
      tostring
      | gsub("</?[Tt][Aa][Rr][Gg][Ee][Tt]>"; "")
      | gsub("@"; "o");
    def clean_surface:
      tostring
      | gsub("</?[Tt][Aa][Rr][Gg][Ee][Tt]>"; "")
      | gsub("@"; "o")
      | gsub("^[[:space:]]+|[[:space:]]+$"; "");
    def fix_item:
      if type == "object" then
        (if (has("dialectNote") | not) and has("dialNote") then .dialectNote = .dialNote | del(.dialNote) else . end)
        | (if (has("dialectNote") | not) and has("dialect_note") then .dialectNote = .dialect_note | del(.dialect_note) else . end)
        | (if (has("dialectNote") | not) and has("dialectNotes") then .dialectNote = .dialectNotes | del(.dialectNotes) else . end)
        | (if (has("dialectNote") | not) and has("dialect") then .dialectNote = .dialect | del(.dialect) else . end)
        | (if (has("grammarNote") | not) and has("grammar_note") then .grammarNote = .grammar_note | del(.grammar_note) else . end)
        | (if (has("example_en") | not) and has("exampleEn") then .example_en = .exampleEn | del(.exampleEn) else . end)
        | (if (has("teachingOrder") | not) and has("teOrder") then .teachingOrder = .teOrder | del(.teOrder) else . end)
        | (if (has("teachingOrder") | not) and has("teaching_order") then .teachingOrder = .teaching_order | del(.teaching_order) else . end)
        | (if ((.id // "") | tostring | test("^es-bue-card-[0-9]{2}-[0-9]{3}$"))
              and (((.setId // "") | tostring | test("^es-bue-card-[0-9]{2}$")) | not)
           then .setId = ((.id | tostring | capture("^(?<setId>es-bue-card-[0-9]{2})-[0-9]{3}$")).setId)
           else . end)
        | (if has("stage") then .stage = normalize_stage(.stage) else . end)
        | (if has("register") then .register = normalize_register(.register) else . end)
        | (if has("topicTags") then .topicTags = normalize_tags(.topicTags; ["general","usage"]; 2; 4) else . end)
        | (if has("cityTags") then .cityTags = normalize_tags(.cityTags; ["buenos-aires"]; 1; 3) else . end)
        | (if has("lemma") then .lemma = (.lemma | clean_surface) else . end)
        | (if has("display") then .display = (.display | clean_surface) else . end)
        | (if has("example") then .example = (.example | clean_example) else . end)
        | (if ((.usage? | type) == "array" and (.usage | length) > 3) then .usage = (.usage[0:3]) else . end)
      else
        .
      end;
    if type == "array" then
      map(fix_item)
    elif type == "object" then
      if (.items? | type) == "array" then .items |= map(fix_item)
      elif (.entries? | type) == "array" then .entries |= map(fix_item)
      elif (.data? | type) == "array" then .data |= map(fix_item)
      elif (.results? | type) == "array" then .results |= map(fix_item)
      elif (.records? | type) == "array" then .records |= map(fix_item)
      elif (.cards? | type) == "array" then .cards |= map(fix_item)
      else fix_item end
    else
      .
    end
  ' "$artifact_path" >"$tmp_path" 2>/dev/null; then
    rm -f "$tmp_path"
    return 0
  fi
  mv "$tmp_path" "$artifact_path"
  after_hash="$(shasum -a 256 "$artifact_path" 2>/dev/null | awk '{print $1}')"
  if [[ -n "$before_hash" && -n "$after_hash" && "$before_hash" != "$after_hash" ]]; then
    ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS="repaired"
    ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_MESSAGE="normalized source-card schema aliases, enum variants, and example target markup before validation"
  else
    ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS="not_needed"
    ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_MESSAGE="no source-card schema aliases needed normalization"
  fi
}


artifact_looks_like_source_cards() {
  local artifact_path="${1:-}"
  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 1
  jq -e '
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
    item_array
    | any(.[]?; type == "object"
      and ((.id // "") | tostring | test("^es-bue-card-[0-9]{2}-[0-9]{3}$"))
      and has("lemma")
      and has("display")
      and has("example_en")
      and has("usage"))
  ' "$artifact_path" >/dev/null 2>&1
}

artifact_duplicate_vocabulary_terms() {
  local artifact_path="${1:-}"
  if artifact_looks_like_source_cards "$artifact_path"; then
    artifact_json_identity_terms "$artifact_path" | LC_ALL=C sort | uniq -d | join_terms_csv
    return 0
  fi
  artifact_vocabulary_terms "$artifact_path" | LC_ALL=C sort | uniq -d | join_terms_csv
}

prompt_requires_unique_item_terms() {
  local prompt="${1:-}" lowered
  lowered="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  if [[ "$(printf '%s' "${ONLYMACS_SOURCE_CARD_QUALITY_MODE:-strict}" | tr '[:upper:]' '[:lower:]')" == "throughput" ]] && string_has_any "$lowered" \
    "source card" \
    "source-card" \
    "cards-source" \
    "lean card source" \
    "lean source card"; then
    return 1
  fi
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

prompt_learner_locales_json() {
  local prompt="${1:-}"
  printf '%s' "$prompt" | perl -0777 -ne '
    if (/learnerLocales\s*:\s*([^\n]+)/i) {
      my @locales;
      for my $locale (split(/[,\s]+/, $1)) {
        $locale =~ s/^\s+|\s+$//g;
        next unless $locale =~ /^[A-Za-z][A-Za-z0-9_-]*$/;
        push @locales, lc($locale);
      }
      my %seen;
      @locales = grep { !$seen{$_}++ } @locales;
      print "[" . join(",", map { "\"" . $_ . "\"" } @locales) . "]";
      exit;
    }
    print "[]";
  '
}

prompt_card_count_range() {
  local prompt="${1:-}"
  local range
  range="$(printf '%s' "$prompt" | perl -0777 -ne '
    while (/(\d{1,4})\s*(?:-|to|through)\s*(\d{1,4})\s+cards?\b/gi) {
      $min = $1;
      $max = $2;
    }
    END { print "$min $max" if defined $min && defined $max }
  ')"
  if [[ "$range" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then
    printf '%s' "$range"
    return 0
  fi
  return 1
}

orchestrated_source_card_repair_seed_terms() {
  local batch_start="${1:-1}"
  local items_per_set set_index
  items_per_set="$(prompt_items_per_set_requirement "${ONLYMACS_PLAN_FILE_CONTENT:-}" 2>/dev/null || true)"
  [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 ]] || items_per_set=20
  [[ "$batch_start" =~ ^[0-9]+$ && "$batch_start" -gt 0 ]] || batch_start=1
  set_index=$((((batch_start - 1) / items_per_set) + 1))
  case "$set_index" in
    44)
      printf '%s' "sacar turno online, cargar saldo, escanear QR, confirmar contraseña, cambiar el mail, mandar captura, subir comprobante, abrir la app, activar notificaciones, recuperar usuario"
      ;;
    45)
      printf '%s' "primero, después, mientras tanto, igual, entonces, por eso, además, en cambio, aunque, así que"
      ;;
    46)
      printf '%s' "estoy cansado, tengo frío, me duele la cabeza, estoy tranquilo, me siento mejor, estoy preocupado, tengo sueño, estoy mareado, me quedé sin voz, tengo hambre"
      ;;
    47)
      printf '%s' "a ver, bueno, claro, dale, puede ser, más o menos, depende, pará, tranqui, igual, no pasa nada, listo, ahí vemos"
      ;;
    48)
      printf '%s' "necesito ayuda ahora, llamá a emergencias, perdí mi documento, no encuentro la salida, estoy buscando la parada, necesito un médico, se cortó la luz, no tengo señal, me quedé sin batería, dónde pago"
      ;;
    49)
      printf '%s' "te parece si cambiamos, gracias por avisar, me viene bien, te aviso después, prefiero otro horario, sumate cuando puedas, quedamos para mañana, paso más tarde, avisame si podés, nos encontramos ahí"
      ;;
    50)
      printf '%s' "salgo temprano, vuelvo más tarde, llevo efectivo, consulto el horario, reviso la dirección, pido un recibo, guardo el comprobante, busco una farmacia, cambio de parada, confirmo la reserva"
      ;;
    *)
      return 0
      ;;
  esac
}

orchestrated_content_pipeline_diversity_guidance() {
  local validation_prompt="${1:-}"
  local filename="${2:-items.json}"
  local batch_start="${3:-1}"
  local batch_end="${4:-1}"
  local previous_terms="${5:-}"
  local start_set="${6:-0}"
  local end_set="${7:-0}"
  local start_item="${8:-0}"
  local end_item="${9:-0}"
  local topic="${10:-}"
  local lowered
  lowered="$(printf '%s %s' "$validation_prompt" "$filename" | tr '[:upper:]' '[:lower:]')"
  string_has_any "$lowered" "buenos aires" "rioplatense" "es-bue" "cards-source" "source card" "source-card" || return 0

  printf -- '- For Buenos Aires source cards, prefer common learner-safe forms over rare slang; keep dialect notes conservative when a term is standard rather than specifically local.\n'
  printf -- '- Buenos Aires cafe/food guard: prefer jugo, gaseosa, torta, mozo, manteca, and medialunas over Spain/general terms like zumo, refresco, pastel, camarero, or mantequilla.\n'
  printf -- '- Buenos Aires transport guard: prefer subte, colectivo, boleto, parada, estación, línea, and recorrido. Do not use metro, autobús, billete as a transport ticket, or paradero for Buenos Aires learner transport cards.\n'
  printf -- '- Buenos Aires voseo command guard: use vos commands in examples and usage, such as leé, llevá, evitá, consultá, revisá, elegí, probá, volvé, subí, bajá, seguí, encendé, apagá, limpiá, marcá, programá, llegá, encontrá, preguntá, mantené, informá, anotá, describí, traé, abrí, cerrá, pedí, visitá, instalá, disfrutá, and configurá. Do not use tuteo command forms like Lee, Lleva, Evita, Consulta, Revisa, Elige, Prueba, Vuelve, Sube, Baja, Sigue, Enciende, Apaga, Limpia, Marca, Programa, Llega, Encuentra, Pregunta, Mantén, Informa, Anota, Describe, Trae, Abre, Cierra, Pide, Visita, Instala, Disfruta, or Configura.\n'
  printf -- '- Buenos Aires accent guard: do not emit unaccented voseo forms such as podes, tenes, queres, venis, sabes, abri, or mantene; use podés, tenés, querés, venís, sabés, abrí, and mantené.\n'
  printf -- '- English learner-note guard: grammarNote, dialectNote, and usage must be learner-facing English guidance. Spanish belongs in lemma, display, example, and short quoted/targeted phrases only; do not write usage notes like "Usá...", "Decí...", "Al narrar...", or "En conversaciones...".\n'
  printf -- '- Source-card lemma guard: for verb cards, lemma must be the infinitive/base form such as ahorrar, cocinar, llamar, llegar, or leer; put conjugated taught forms such as ahorraré, cocinarás, llamá, or leé in display only.\n'
  printf -- '- Source-card usage guard: usage notes must be practical real-world notes, not meta-learning notes. Do not use the words study, review, drill, surface form, target tag, tags, wrapping, or placeholder in usage.\n'
  printf -- '- Source-card target guard: at least one usage note must wrap the exact taught display text itself in <target>...</target>, not a conjugated/inflected variant and not a larger sentence unless the display is itself a full sentence. If display is preferir, emit <target>preferir</target>, not <target>preferís</target>.\n'
  if [[ "$start_set" -eq 3 ]]; then
    printf -- '- Use this positive term inventory for set 03 if a term is not already banned: aprendés/aprender, leés/leer, escribís/escribir, abrís/abrir, cerrás/cerrar, buscás/buscar, encontrás/encontrar, esperás/esperar, pagás/pagar, cambiás/cambiar, viajás/viajar, volvés/volver, salís/salir, entrás/entrar, traés/traer, ponés/poner, pedís/pedir, seguís/seguir, elegís/elegir, repetís/repetir.\n'
    printf -- '- For set 03, display should be the voseo surface form and lemma should be the infinitive when practical. Avoid repeating accepted voseo surfaces such as hablás even if you change the lemma.\n'
    printf -- '- For set 03, English should describe the voseo surface, for example "you learn" for aprendés, not only the infinitive "to learn".\n'
  elif [[ "$start_set" -eq 39 ]]; then
    printf -- '- For set 39, avoid repeating the obvious core voseo/imperative cards from earlier sets. Do not use hablar/hablá, comer/comé, vivir/viví, abrir/abrí, cerrar/cerrá, llevar/llevá, decir/decí, pedir/pedí, venir/vení, tener/tenés, poder/podés, querer/querés, saber/sabés, or estar/estás unless they are explicitly not already banned.\n'
    printf -- '- Use less-repeated learner-safe voseo stress examples for set 39, such as reservá, confirmá, imprimí, compartí, descargá, coordiná, cambiá, avisá, cruzá, doblá, guardá, firmá, completá, verificá, respondé, proponé, resolvé, elegí, repetí, corregí, and traducí.\n'
    printf -- '- For set 39 verb cards, lemma should usually be an infinitive and display should be the taught voseo surface. Keep examples grammatical with the displayed form exactly present.\n'
  elif [[ "$start_set" -eq 40 ]]; then
    printf -- '- Set 40 is recognition-only tuteo contrast. If display is a tuteo form such as eres, tienes, puedes, quieres, vienes, sabes, mira, espera, habla, come, vive, abre, cierra, pide, or lleva, register must be exactly recognition-only.\n'
    printf -- '- For set 40, examples may show the tuteo form only as something the learner recognizes from outside Argentina; usage and dialectNote must steer Buenos Aires production back to vos.\n'
    printf -- '- Do not mark tuteo items as neutral, formal-usted, polite-informal, or informal-voseo. Do not mix usted meanings into tuteo items.\n'
  elif [[ "$start_set" -ge 41 && "$start_set" -le 50 ]]; then
    printf -- '- For late review/application sets %s, avoid recycled beginner core terms. Prefer concrete topic-specific nouns, phrases, connectors, or service verbs tied to "%s".\n' "$start_set" "${topic:-the current set topic}"
    printf -- '- If this is a review set, review by applying new surfaces in familiar situations, not by repeating earlier cards with new ids.\n'
  fi
}

orchestrated_source_card_batch_starter_json() {
  local validation_prompt="${1:-}"
  local filename="${2:-items.json}"
  local batch_start="${3:-1}"
  local batch_end="${4:-1}"
  local batch_items="${5:-1}"
  local items_per_set start_set end_set topic
  orchestrated_json_step_is_source_card_content "$validation_prompt" "$filename" || return 0
  items_per_set="$(prompt_items_per_set_requirement "$validation_prompt" || true)"
  [[ "$items_per_set" =~ ^[0-9]+$ && "$items_per_set" -gt 0 ]] || return 0
  [[ "$batch_start" =~ ^[0-9]+$ && "$batch_end" =~ ^[0-9]+$ && "$batch_items" =~ ^[0-9]+$ ]] || return 0
  start_set=$((((batch_start - 1) / items_per_set) + 1))
  end_set=$((((batch_end - 1) / items_per_set) + 1))
  topic=""
  if [[ "$start_set" -eq "$end_set" ]]; then
    topic="$(orchestrated_plan_set_topic "${ONLYMACS_PLAN_FILE_CONTENT:-$validation_prompt}" "$start_set")"
  fi
  jq -cn \
    --argjson batch_start "$batch_start" \
    --argjson batch_items "$batch_items" \
    --argjson items_per_set "$items_per_set" \
    --arg topic "$topic" \
    '
      def pad2: tostring | if length == 1 then "0" + . else . end;
      def pad3: tostring | if length == 1 then "00" + . elif length == 2 then "0" + . else . end;
      [
        range(0; $batch_items)
        | ($batch_start + .) as $global
        | (((($global - 1) / $items_per_set) | floor) + 1) as $set
        | ((($global - 1) % $items_per_set) + 1) as $order
        | {
            id: ("es-bue-card-" + ($set | pad2) + "-" + ($order | pad3)),
            setId: ("es-bue-card-" + ($set | pad2)),
            teachingOrder: $order,
            lemma: "",
            display: "",
            english: "",
            pos: "",
            stage: "",
            register: "",
            topic: $topic,
            topicTags: ["", ""],
            cityTags: ["buenos-aires"],
            grammarNote: "",
            dialectNote: "",
            example: "",
            example_en: "",
            usage: ["", "", ""]
          }
      ]
    '
}

validate_content_pipeline_json_artifact() {
  local artifact_path="${1:-}"
  local prompt="${2:-}"
  local base_lower lowered_prompt locales_json range min_cards max_cards banned_hits schema_details source_card_quality_mode
  local is_set_definitions=0 is_source_cards=0 is_vocab=0 is_sentences=0 is_lessons=0 is_alphabet=0 detected=0
  local failures=()
  ONLYMACS_CONTENT_PIPELINE_VALIDATION_STATUS="skipped"
  ONLYMACS_CONTENT_PIPELINE_VALIDATION_MESSAGE=""

  [[ -f "$artifact_path" && "$artifact_path" == *.json ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  base_lower="$(basename "$artifact_path" | tr '[:upper:]' '[:lower:]')"
  lowered_prompt="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  source_card_quality_mode="$(printf '%s' "${ONLYMACS_SOURCE_CARD_QUALITY_MODE:-strict}" | tr '[:upper:]' '[:lower:]')"
  if ! string_has_any "$lowered_prompt" \
    "learn-spanish-buenos-aires" \
    "buenos aires" \
    "rioplatense" \
    "es-bue" \
    "learnerlocales" \
    "voseo" \
    "existing step 2 shape" \
    "setdefinitions.json" \
    "vocab-groups-01-02" \
    "sentences-groups-01-02" \
    "lessons-groups-01-02" \
    "es-bue-alpha-01"; then
    return 0
  fi
  locales_json="$(prompt_learner_locales_json "$prompt")"

  case "$base_lower" in
    *setdefinitions*)
      is_set_definitions=1
      detected=1
      ;;
    *cards-source*|*source-card*|*source_cards*)
      is_source_cards=1
      detected=1
      ;;
    *vocab*)
      is_vocab=1
      detected=1
      ;;
    *sentence*)
      is_sentences=1
      detected=1
      ;;
    *lesson*)
      is_lessons=1
      detected=1
      ;;
    *alphabet*|*alpha*)
      is_alphabet=1
      detected=1
      ;;
  esac

  if [[ "$detected" -eq 0 ]]; then
    if string_has_any "$lowered_prompt" "output: setdefinitions.json" "set definitions" "modules.vocab"; then
      is_set_definitions=1
    elif string_has_any "$lowered_prompt" "output: cards-source" "source cards" "source-card" "lean card source schema" "lean source card"; then
      is_source_cards=1
    elif string_has_any "$lowered_prompt" "output: vocab" "vocab groups" "vocab items total" "vocab items should follow"; then
      is_vocab=1
    elif string_has_any "$lowered_prompt" "output: sentences" "sentence groups" "sentence items total" "sentence items should follow"; then
      is_sentences=1
    elif string_has_any "$lowered_prompt" "output: lessons" "lesson groups" "lesson items" "lesson items should follow"; then
      is_lessons=1
    elif string_has_any "$lowered_prompt" "output: alphabet" "alphabet group" "alphabet item shape"; then
      is_alphabet=1
    fi
  fi

  if [[ "$is_set_definitions" -eq 1 ]]; then
    if ! jq -e '
      def root: if (.modules? | type) == "object" then . elif (.setDefinitions.modules? | type) == "object" then .setDefinitions else . end;
      root as $root |
      type == "object" and
      ($root.modules | type) == "object" and
      (($root.modules.vocab // []) | type) == "array" and (($root.modules.vocab // []) | length) > 0 and
      (($root.modules.sentences // []) | type) == "array" and (($root.modules.sentences // []) | length) > 0 and
      (($root.modules.lessons // []) | type) == "array" and (($root.modules.lessons // []) | length) > 0 and
      (($root.modules.alphabet // []) | type) == "array" and (($root.modules.alphabet // []) | length) > 0 and
      all([
        ($root.modules.vocab[]?),
        ($root.modules.sentences[]?),
        ($root.modules.lessons[]?),
        ($root.modules.alphabet[]?)
      ][]; type == "object" and ((.id // .setId // "") | tostring | length) > 0)
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("setDefinitions must include non-empty modules.vocab, modules.sentences, modules.lessons, and modules.alphabet arrays with ids")
    fi
    for expected_id in \
      es-bue-vocab-beg-01 \
      es-bue-vocab-beg-02 \
      es-bue-sent-01 \
      es-bue-sent-02 \
      es-bue-lesson-01 \
      es-bue-lesson-02 \
      es-bue-alpha-01
    do
      if [[ "$prompt" == *"$expected_id"* ]] && ! jq -e --arg id "$expected_id" '
        def root: if (.modules? | type) == "object" then . elif (.setDefinitions.modules? | type) == "object" then .setDefinitions else . end;
        root as $root |
        [
          ($root.modules.vocab[]? | if type == "object" then (.id // .setId // empty) else tostring end),
          ($root.modules.sentences[]? | if type == "object" then (.id // .setId // empty) else tostring end),
          ($root.modules.lessons[]? | if type == "object" then (.id // .setId // empty) else tostring end),
          ($root.modules.alphabet[]? | if type == "object" then (.id // .setId // empty) else tostring end)
        ] | index($id) != null
      ' "$artifact_path" >/dev/null 2>&1; then
        failures+=("setDefinitions is missing expected id ${expected_id}")
      fi
    done
  fi

  if [[ "$is_source_cards" -eq 1 ]]; then
    if ! jq -e --arg quality "$source_card_quality_mode" --argjson required '["id","setId","teachingOrder","lemma","display","english","pos","stage","register","topic","topicTags","cityTags","grammarNote","dialectNote","example","example_en","usage"]' '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
      def compact($v): (($v // "") | tostring | ascii_downcase | gsub("[¿?¡!.,;:()\\[\\]\"'\''`]"; "") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""));
      def surface_variants($v):
        (compact($v)) as $surface
        | if ($surface | length) == 0 then []
          elif ($surface | test("o$")) then
            [$surface, ($surface | sub("o$"; "a")), ($surface | sub("o$"; "os")), ($surface | sub("o$"; "as"))]
          elif ($surface | test("or$")) then
            [$surface, ($surface | sub("or$"; "ora")), ($surface | sub("or$"; "ores")), ($surface | sub("or$"; "oras"))]
          else [$surface]
          end;
      def contains_surface($item):
        (compact($item.example)) as $example
        | any(((surface_variants($item.display) + surface_variants($item.lemma)) | unique)[]; ($example | contains(.)));
      def verb_lemma_ok($item):
        if ((($item.pos // "") | tostring | ascii_downcase) != "verb") then true
        else (($item.lemma // "") | tostring | ascii_downcase | gsub("^\\s+|\\s+$"; "") | test("(ré|rás|rá|remos|rán)$") | not)
        end;
      def target_contains_surface($item):
        (compact($item.display)) as $display
        | any(($item.usage // [])[]; tostring
            | [match("<target>([^<]+)</target>"; "g").captures[0].string] as $targets
            | any($targets[]; (compact(.)) as $target
                | (($display | length) > 0 and ($target | contains($display)))));
      artifact_items as $items
      | ($items | length) > 0 and all($items[]; . as $item |
        type == "object" and
        ((($item | keys_unsorted) | sort) == ($required | sort)) and
        all($required[]; . as $field | $item | has($field)) and
        (($item.id // "") | tostring | test("^es-bue-card-[0-9]{2}-[0-9]{3}$")) and
        (($item.setId // "") | tostring | test("^es-bue-card-[0-9]{2}$")) and
        (($item.teachingOrder // null) | type) == "number" and
        (($item.teachingOrder // 0) >= 1 and ($item.teachingOrder // 0) <= 20) and
        nonblank($item.lemma) and nonblank($item.display) and nonblank($item.english) and
        nonblank($item.pos) and nonblank($item.stage) and nonblank($item.register) and nonblank($item.topic) and
        (($item.stage // "") | IN("beginner","early-intermediate","intermediate","upper-intermediate","review")) and
        (($item.register // "") | IN("neutral","informal-voseo","polite-informal","formal-usted","recognition-only")) and
        verb_lemma_ok($item) and
        (($item.topicTags // []) | type) == "array" and (($item.topicTags // []) | length) >= 2 and (($item.topicTags // []) | length) <= 4 and
        (($item.cityTags // []) | type) == "array" and (($item.cityTags // []) | length) >= 1 and (($item.cityTags // []) | length) <= 3 and
        nonblank($item.grammarNote) and nonblank($item.dialectNote) and nonblank($item.example) and nonblank($item.example_en) and
        (((($item.pos // "") | tostring | ascii_downcase) == "verb") or contains_surface($item)) and
        (($item.example // "") | tostring | test("<target>|</target>|\\bes la palabra\\b|\\bsignifica\\b"; "i") | not) and
        (($item.usage // []) | type) == "array" and (($item.usage // []) | length) == 3 and
        any(($item.usage // [])[]; tostring | test("<target>[^<]+</target>")) and
        ($quality == "throughput" or target_contains_surface($item)) and
        all(($item.usage // [])[]; (tostring | test("</>") | not)) and
        all(($item.usage // [])[]; tostring as $usage | (($usage | test("<target>") | not) or ($usage | test("<target>[^<]+</target>")))) and
        (all(($item.usage // [])[]; tostring | test("\\b(wrap|tag|tags|study|review|reviewing|drill|drills|surface form|target tags)\\b"; "i") | not))
      )
    ' "$artifact_path" >/dev/null 2>&1; then
      schema_details="$(jq -r --arg quality "$source_card_quality_mode" --argjson required '["id","setId","teachingOrder","lemma","display","english","pos","stage","register","topic","topicTags","cityTags","grammarNote","dialectNote","example","example_en","usage"]' '
        def artifact_items:
          if type == "array" then .
          elif type == "object" then
            if (.items? | type) == "array" then .items
            elif (.entries? | type) == "array" then .entries
            elif (.data? | type) == "array" then .data
            elif (.results? | type) == "array" then .results
            elif (.records? | type) == "array" then .records
            elif (.cards? | type) == "array" then .cards
            else []
            end
          else []
          end;
        def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
        def compact($v): (($v // "") | tostring | ascii_downcase | gsub("[¿?¡!.,;:()\\[\\]\"'\''`]"; "") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""));
        def surface_variants($v):
          (compact($v)) as $surface
          | if ($surface | length) == 0 then []
            elif ($surface | test("o$")) then
              [$surface, ($surface | sub("o$"; "a")), ($surface | sub("o$"; "os")), ($surface | sub("o$"; "as"))]
            elif ($surface | test("or$")) then
              [$surface, ($surface | sub("or$"; "ora")), ($surface | sub("or$"; "ores")), ($surface | sub("or$"; "oras"))]
            else [$surface]
            end;
        def contains_surface($item):
          (compact($item.example)) as $example
          | any(((surface_variants($item.display) + surface_variants($item.lemma)) | unique)[]; ($example | contains(.)));
        def verb_lemma_ok($item):
          if ((($item.pos // "") | tostring | ascii_downcase) != "verb") then true
          else (($item.lemma // "") | tostring | ascii_downcase | gsub("^\\s+|\\s+$"; "") | test("(ré|rás|rá|remos|rán)$") | not)
          end;
      def target_contains_surface($item):
        (compact($item.display)) as $display
          | any(($item.usage // [])[]?; tostring
              | [match("<target>([^<]+)</target>"; "g").captures[0].string] as $targets
              | any($targets[]; (compact(.)) as $target
                  | (($display | length) > 0 and ($target | contains($display)))));
        artifact_items as $items
        | if ($items | length) == 0 then
            ["no item array found"]
          else
            [
              $items
              | to_entries[] as $entry
              | ($entry.key + 1) as $n
              | $entry.value as $item
              | if ($item | type) != "object" then
                  "item \($n): not an object"
                else
                  (
                    [$required[] as $field | select(($item | has($field)) | not) | "missing " + $field]
                    + (if (($item.id // "") | tostring | test("^es-bue-card-[0-9]{2}-[0-9]{3}$") | not) then ["bad id " + (($item.id // "") | tostring)] else [] end)
                    + (if (($item.setId // "") | tostring | test("^es-bue-card-[0-9]{2}$") | not) then ["bad setId " + (($item.setId // "") | tostring)] else [] end)
                    + (if ((($item.teachingOrder // null) | type) != "number") then ["teachingOrder is not numeric"] elif (($item.teachingOrder // 0) < 1 or ($item.teachingOrder // 0) > 20) then ["teachingOrder out of range"] else [] end)
                    + (if (($item.stage // "") | IN("beginner","early-intermediate","intermediate","upper-intermediate","review") | not) then ["bad stage " + (($item.stage // "") | tostring)] else [] end)
                    + (if (($item.register // "") | IN("neutral","informal-voseo","polite-informal","formal-usted","recognition-only") | not) then ["bad register " + (($item.register // "") | tostring)] else [] end)
                    + (if verb_lemma_ok($item) then [] else ["verb lemma must be an infinitive/base form, not conjugated display text"] end)
                    + (if (((($item.pos // "") | tostring | ascii_downcase) == "verb") or contains_surface($item)) then [] else ["example missing lemma/display surface"] end)
                    + (if (($item.example // "") | tostring | test("<target>|</target>|\\bes la palabra\\b|\\bsignifica\\b"; "i")) then ["example contains target/meta markup"] else [] end)
                    + (if (($item.topicTags // []) | type) != "array" then ["topicTags not array"] elif (($item.topicTags // []) | length) < 2 or (($item.topicTags // []) | length) > 4 then ["topicTags count must be 2-4"] else [] end)
                    + (if (($item.cityTags // []) | type) != "array" then ["cityTags not array"] elif (($item.cityTags // []) | length) < 1 or (($item.cityTags // []) | length) > 3 then ["cityTags count must be 1-3"] else [] end)
                    + (if (($item.usage // []) | type) != "array" then ["usage not array"] elif (($item.usage // []) | length) != 3 then ["usage must have exactly 3 notes"] else [] end)
                    + (if any(($item.usage // [])[]?; tostring | test("<target>[^<]+</target>")) then [] else ["usage missing concrete <target> tag"] end)
                    + (if ($quality == "throughput" or target_contains_surface($item)) then [] else ["usage target must contain exact display surface"] end)
                    + (if any(($item.usage // [])[]?; tostring | test("</>|<target>\\s*</target>|<target>[^<]*$")) then ["usage has malformed target tag"] else [] end)
                    + ([$required[] as $field | select(($item | has($field)) and (($item[$field] | type) == "string") and (nonblank($item[$field]) | not)) | "blank " + $field])
                  )[:5][]? as $problem
                  | "item \($n): \($problem)"
                end
            ]
          end
        | .[:10][]
      ' "$artifact_path" 2>/dev/null | perl -0777 -pe 's/\n/; /g; s/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c 1-350 || true)"
      if [[ -n "$schema_details" ]]; then
        failures+=("source-card entries must follow the lean source schema exactly. Details: ${schema_details}")
      else
        failures+=("source-card entries must follow the lean source schema exactly, include valid ids/setIds, natural examples containing the taught form, and exactly 3 real-world usage notes with a <target> tag")
      fi
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      artifact_items
      | any(.[]?; any((.usage // [])[]?; tostring | test("<target>\\s*</target>|<target>(\\s|$)|(^|\\s)</target>|<target>[^<]*$")))
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("usage must wrap the actual taught form, for example <target>Hola</target>; do not emit the literal placeholder <target>")
    fi
    if [[ "$source_card_quality_mode" != "throughput" ]]; then
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      def without_targets: tostring | gsub("<target>[^<]+</target>"; " <target> ");
      artifact_items
      | any(.[]?; any((.usage // [])[]?; without_targets as $note |
          ($note | test("(^|[.!?]\\s*)(siempre|es importante|debemos|necesito que|el jefe|prefiero|lo siento|hay que|quiero|vamos|estamos|podrías|podrias|asegurate|decime|decíme|verificá|verifica|no consumas|¿)\\b"; "i"))
          or ($note | test("\\b(por ti|después de|cuando alguien|para todos|todos los días|debes|quieres|tienes|podrías|podrias|sentís|tenés|sos alérgico)\\b"; "i"))
        ))
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card usage notes must be learner-facing English, not full Spanish sentences outside the taught <target> surface")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      artifact_items
      | any(.[]?; [
          (.lemma // ""),
          (.display // ""),
          (.example // ""),
          ((.usage // [])[]?)
          ] | any(tostring | test("\\b(hacas|andas|podes|tenes|queres|venis|sabes|abri|mantene)\\b"; "i")))
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card content contains likely unaccented Rioplatense voseo spelling such as hacas/andas/podes/tenes/queres/venis/sabes/abri/mantene")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      def display_lower: ((.display // .lemma // "") | tostring | ascii_downcase | gsub("[¿?¡!.,;:()\\[\\]\"'\''`]"; "") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""));
      artifact_items
      | any(.[]; . as $item |
          (($item.english // "") | tostring | test("\\b(hello|good morning|good evening|good night|bye|goodbye|see you|nice to meet you|what.s up|how are you)\\b"; "i")) and
          ((display_lower | test("^(hola|buenas|buen día|buenos días|buenas tardes|buenas noches|chau|adiós|nos vemos|hasta luego|hasta mañana|hasta pronto|hasta la próxima|un gusto|mucho gusto|encantad[oa]( de conocerte)?|qué (gusto|bueno|alegría) verte|cómo (andás|estás|está|va|te va)|qué (hacés|contás|tal)|todo bien|saludos|que te vaya bien)") | not))
        )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card greeting/farewell items include a suspicious or invented Spanish surface form for the English meaning")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      artifact_items
      | any(.[]?; . as $item |
          ((($item.register // "") | tostring | ascii_downcase) != "recognition-only") and
          ([
            ($item.lemma // ""),
            ($item.display // ""),
            ($item.example // ""),
            (($item.usage // [])[]?)
          ] | any(tostring as $text |
            ($text | test("\\b(eres|tienes|puedes|quieres|vienes|conoces|llamas|vives|trabajas|estudias|necesitas|buscas|usas|confirmas|verificas|giras|guardas|tomas|reservas|pagas|compras|comes|bebes|pides|pierdes|configuras|dices|haces|dudas|dudes|insistes|premeditas|podes|tenes|queres|venis|sabes|has (visto|llamado|probado|comido|bebido|visitado|estado))\\b"; "i"))
            or ($text | test("\\b(trata de|prepárate|preparate|premedita tu|insiste en)\\b"; "i"))
            or ($text | test("\\b(Busca|Usa|Confirma|Verifica|Gira|Acompaña|Combínalo|Guarda|Toma|Reserva|Paga|Compra|Cambia|Llama|Escribe|Repite|Espera|Escucha|Lee|Lleva|Evita|Consulta|Revisa|Elige|Prueba|Vuelve|Sube|Baja|Sigue|Enciende|Apaga|Limpia|Marca|Programa|Llega|Encuentra|Pregunta|Mantén|Informa|Anota|Describe|Trae|Abre|Cierra|Pide|Visita|Instala|Disfruta|Configura|Cuídate|Mira|Perdona|Dí)\\b"))
          ))
        )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card content contains productive tuteo forms outside recognition-only items; use Rioplatense voseo or mark true contrast items as recognition-only")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      artifact_items
      | any(.[]?; [
          (.lemma // ""),
          (.display // ""),
          (.example // ""),
          ((.usage // [])[]?)
        ] | any(tostring | test("\\b(insistema|prefero|balear|ejarre|deleá|dicí|reconozcá|asiigne|agradécetela|agradecetela|coórdinalemos|coordinalemos|coordinaras)\\b"; "i")))
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card content contains suspicious generated Spanish typo or invented surface forms")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      def norm: tostring | ascii_downcase | gsub("[¿?¡!.,;:()\\[\\]\"'\''`]"; "") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "");
      def command_surface:
        test("^(consultá|marcá|programá|llegá|encontrá|preguntá|mantené|informá|anotá|describí|traé|abrí|cerrá|pedí|visitá|instalá|disfrutá|configurá|leé|llevá|evitá|revisá|elegí|probá|volvé|subí|bajá|seguí|encendé|apagá|limpiá)$");
      artifact_items
      | any(.[]?; . as $item |
          ((($item.pos // "") | tostring | ascii_downcase) | test("\\bnoun\\b")) and
          (((($item.lemma // "") | norm) | command_surface) or (((($item.display // "") | norm) | command_surface)))
        )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card noun lemma/display was over-normalized into a voseo command form; keep noun surfaces such as consulta as nouns and only use voseo commands for verb items or usage commands")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      def norm: tostring | ascii_downcase | gsub("[¿?¡!.,;:()\\[\\]\"'\''`]"; "") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "");
      artifact_items
      | any(.[]?; . as $item |
          ([($item.topic // ""), (($item.topicTags // [])[]?), (($item.cityTags // [])[]?)] | map(norm) | join(" ") | test("\\b(transport|transporte|ticket|tickets|route|routes|ruta|rutas|subte|colectivo|bus|station|estación)\\b")) and
          (
            ((($item.lemma // "") | norm) | test("^(metro|paradero|billete)$")) or
            ((($item.display // "") | norm) | test("^(metro|paradero|billete)$")) or
            ([($item.example // ""), (($item.usage // [])[]?)] | map(tostring) | join(" ") | test("\\b(autob[uú]s|autobuses|paradero|billete)\\b"; "i"))
          )
        )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card content contains non-Buenos Aires transport terms; use learner-safe local forms like subte, colectivo, boleto, parada, estación, línea, recorrido, or trasbordo")
    fi
    if jq -e '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.cards? | type) == "array" then .cards
          else []
          end
        else []
        end;
      artifact_items
      | any(.[]?; [(.lemma // ""), (.display // ""), (.example // ""), ((.usage // [])[]?)] | map(tostring) | join(" ") | test("\\b(en el|del|al) metro\\b|\\b(mantequilla|zumo|refresco|pastel|camarero|mesero)\\b|\\bpide (el|la|un|una|los|las)\\b"; "i"))
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("source-card content contains non-local Buenos Aires wording such as en el metro, mantequilla, zumo, refresco, pastel, camarero, mesero, or pide la/el; use en el subte, manteca, jugo, gaseosa, torta, mozo, or pedí la/el")
    fi
    fi
  fi

  if [[ "$is_vocab" -eq 1 ]]; then
    if ! jq -e --argjson locales "$locales_json" '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.vocab? | type) == "array" then .vocab
          else []
          end
        else []
        end;
      def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
      def has_locale_map($field):
        . as $item
        | if ($locales | length) == 0 then true
          else (($item[$field]? | type) == "object" and all($locales[]; (($item[$field][.] // "") | tostring | length) > 0))
          end;
      artifact_items as $items
      | ($items | length) > 0 and all($items[]; . as $item |
        type == "object" and
        all(["id","setId","lemma","display","translationsByLocale","pos","stage","register","grammar","supportedPromptModes","defaultPromptMode","source"][]; . as $field | $item | has($field)) and
        nonblank(.id) and nonblank(.setId) and nonblank(.lemma) and nonblank(.display) and
        has_locale_map("translationsByLocale") and
        nonblank(.pos) and nonblank(.stage) and nonblank(.register) and
        ((.supportedPromptModes // []) | type) == "array" and ((.supportedPromptModes // []) | length) > 0 and
        nonblank(.defaultPromptMode)
      )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("vocab entries must follow the Step 2 schema and include complete translationsByLocale values")
    fi
    if string_has_any "$lowered_prompt" \
      "gold vocab item schema" \
      "exampletranslationbylocale" \
      "audiohint" \
      "example_en" \
      "usage must be exactly 3"; then
      if ! jq -e --argjson locales "$locales_json" '
        def artifact_items:
          if type == "array" then .
          elif type == "object" then
            if (.items? | type) == "array" then .items
            elif (.entries? | type) == "array" then .entries
            elif (.data? | type) == "array" then .data
            elif (.results? | type) == "array" then .results
            elif (.records? | type) == "array" then .records
            elif (.vocab? | type) == "array" then .vocab
            else []
            end
          else []
          end;
        def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
        def has_locale_map($field):
          . as $item
          | if ($locales | length) == 0 then true
            else (($item[$field]? | type) == "object" and all($locales[]; (($item[$field][.] // "") | tostring | length) > 0))
            end;
        artifact_items as $items
        | ($items | length) > 0 and all($items[]; . as $item |
          type == "object" and
          all(["teachingOrder","difficultyBand","topicTags","cityContextTags","pronunciationHint","example","example_en","exampleTranslationByLocale","usage","audioHint"][]; . as $field | $item | has($field)) and
          ((.teachingOrder // null) | type) == "number" and
          nonblank(.difficultyBand) and
          ((.topicTags // []) | type) == "array" and ((.topicTags // []) | length) > 0 and
          ((.cityContextTags // []) | type) == "array" and ((.cityContextTags // []) | length) > 0 and
          nonblank(.example) and nonblank(.example_en) and
          has_locale_map("exampleTranslationByLocale") and
          ((.usage // []) | type) == "array" and ((.usage // []) | length) == 3 and
          any((.usage // [])[]; test("<target>.*</target>")) and
          ((.audioHint // null) | type) == "object" and nonblank(.audioHint.pace) and nonblank(.audioHint.stress)
        )
      ' "$artifact_path" >/dev/null 2>&1; then
        failures+=("gold vocab entries must include teaching metadata, natural examples, example translations, exactly 3 usage lines with a <target> tag, and audio hints")
      fi
      if jq -e '
        def artifact_items:
          if type == "array" then .
          elif type == "object" then
            if (.items? | type) == "array" then .items
            elif (.entries? | type) == "array" then .entries
            elif (.data? | type) == "array" then .data
            elif (.results? | type) == "array" then .results
            elif (.records? | type) == "array" then .records
            elif (.vocab? | type) == "array" then .vocab
            else []
            end
          else []
          end;
        artifact_items
        | any(.[]; ((.example // "") | tostring | test("<target>|</target>|\\bes la palabra\\b|\\bsignifica\\b"; "i")))
      ' "$artifact_path" >/dev/null 2>&1; then
        failures+=("gold vocab examples must be natural usage examples, not target-tagged or meta explanations")
      fi
      if jq -e '
        def artifact_items:
          if type == "array" then .
          elif type == "object" then
            if (.items? | type) == "array" then .items
            elif (.entries? | type) == "array" then .entries
            elif (.data? | type) == "array" then .data
            elif (.results? | type) == "array" then .results
            elif (.records? | type) == "array" then .records
            elif (.vocab? | type) == "array" then .vocab
            else []
            end
          else []
          end;
        artifact_items
        | any(.[]; any((.usage // [])[]?; tostring | test("\\b(wrap|tag|tags|study|review|reviewing|drill|drills|speech practice|surface form|target tags)\\b"; "i")))
      ' "$artifact_path" >/dev/null 2>&1; then
        failures+=("gold vocab usage lines must describe real-world use, not study/review/tagging instructions")
      fi
    fi
  fi

  if [[ "$is_sentences" -eq 1 ]]; then
    if ! jq -e --argjson locales "$locales_json" '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.sentences? | type) == "array" then .sentences
          else []
          end
        else []
        end;
      def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
      def has_locale_map($field):
        . as $item
        | if ($locales | length) == 0 then true
          else (($item[$field]? | type) == "object" and all($locales[]; (($item[$field][.] // "") | tostring | length) > 0))
          end;
      artifact_items as $items
      | ($items | length) > 0 and all($items[]; . as $item |
        type == "object" and
        all(["id","setId","text","translationsByLocale","register","scenarioTags","cityContextTags","translationMode","supportedPromptModes","defaultPromptMode","segmentation","frequencyBand","patternType","teachingOrder","source","highlights","usage"][]; . as $field | $item | has($field)) and
        nonblank(.id) and nonblank(.setId) and nonblank(.text) and has_locale_map("translationsByLocale") and
        nonblank(.register) and ((.scenarioTags // []) | type) == "array" and ((.cityContextTags // []) | type) == "array" and
        nonblank(.translationMode) and ((.supportedPromptModes // []) | type) == "array" and ((.supportedPromptModes // []) | length) > 0 and
        nonblank(.defaultPromptMode) and nonblank(.frequencyBand) and nonblank(.patternType) and
        ((.teachingOrder // null) | type) == "number" and
        ((.highlights["en.viet"]? // .highlights.en.viet? // null) != null) and ((.highlights["en.trans"]? // .highlights.en.trans? // null) != null)
      )
    ' "$artifact_path" >/dev/null 2>&1; then
      schema_details="$(jq -r --argjson locales "$locales_json" '
        def artifact_items:
          if type == "array" then .
          elif type == "object" then
            if (.items? | type) == "array" then .items
            elif (.entries? | type) == "array" then .entries
            elif (.data? | type) == "array" then .data
            elif (.results? | type) == "array" then .results
            elif (.records? | type) == "array" then .records
            elif (.sentences? | type) == "array" then .sentences
            else []
            end
          else []
          end;
        def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
        def missing_required($item):
          ["id","setId","text","translationsByLocale","register","scenarioTags","cityContextTags","translationMode","supportedPromptModes","defaultPromptMode","segmentation","frequencyBand","patternType","teachingOrder","source","highlights","usage"]
          | map(select(($item | has(.)) | not));
        artifact_items | to_entries | map(
          .value as $item
          | (missing_required($item)
            + (if (($item.translationsByLocale? | type) == "object") then
                ($locales | map(select((($item.translationsByLocale[.] // "") | tostring | length) == 0) | "translationsByLocale." + .))
              else ["translationsByLocale"] end)
            + (if (($item.cityContextTags? | type) == "array") then [] else ["cityContextTags"] end)
            + (if (($item.scenarioTags? | type) == "array") then [] else ["scenarioTags"] end)
            + (if (($item.teachingOrder? // null) | type) == "number" then [] else ["teachingOrder"] end)
            + (if (($item.highlights["en.viet"]? // $item.highlights.en.viet? // null) != null) then [] else ["highlights.en.viet"] end)
            + (if (($item.highlights["en.trans"]? // $item.highlights.en.trans? // null) != null) then [] else ["highlights.en.trans"] end)) as $missing
          | select($missing | length > 0)
          | "item " + ((.key + 1) | tostring) + " (" + (($item.id // "no-id") | tostring) + ") missing/invalid " + ($missing | unique | join(","))
        )[:5] | join("; ")
      ' "$artifact_path" 2>/dev/null || true)"
      if [[ -n "$schema_details" ]]; then
        failures+=("sentence entries failed Step 2 schema: ${schema_details}")
      else
        failures+=("sentence entries must follow the Step 2 schema, include locale translations, cityContextTags, and highlights.en.viet/trans")
      fi
    fi
  fi

  if [[ "$is_lessons" -eq 1 ]]; then
    if ! jq -e --argjson locales "$locales_json" '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          elif (.lessons? | type) == "array" then .lessons
          else []
          end
        else []
        end;
      def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
      def has_locale_map($field):
        . as $item
        | if ($locales | length) == 0 then true
          else (($item[$field]? | type) == "object" and all($locales[]; (($item[$field][.] // "") | tostring | length) > 0))
          end;
      artifact_items as $items
      | ($items | length) > 0 and all($items[]; . as $item |
        type == "object" and
        all(["id","setId","level","titlesByLocale","scenario","grammarFocus","prerequisiteSetIds","cityTags","notesByLocale","contentBlocks","quiz"][]; . as $field | $item | has($field)) and
        nonblank(.id) and nonblank(.setId) and nonblank(.level) and has_locale_map("titlesByLocale") and
        nonblank(.scenario) and ((.prerequisiteSetIds // []) | type) == "array" and ((.prerequisiteSetIds // []) | length) > 0 and
        ((.cityTags // []) | type) == "array" and has_locale_map("notesByLocale") and
        ((.contentBlocks // []) | type) == "array" and ((.contentBlocks // []) | length) >= 4 and
        ((.quiz // []) | type) == "array" and ((.quiz // []) | length) >= 8
      )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("lesson entries must follow the Step 2 schema, include locale titles/notes, prerequisites, at least 4 contentBlocks, and at least 8 quiz questions")
    fi
  fi

  if [[ "$is_alphabet" -eq 1 ]]; then
    if ! jq -e --argjson locales "$locales_json" '
      def artifact_items:
        if type == "array" then .
        elif type == "object" then
          if (.cards? | type) == "array" then .cards
          elif (.items? | type) == "array" then .items
          elif (.entries? | type) == "array" then .entries
          elif (.data? | type) == "array" then .data
          elif (.results? | type) == "array" then .results
          elif (.records? | type) == "array" then .records
          else []
          end
        else []
        end;
      def nonblank($v): (($v // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) > 0;
      def has_locale_map($field):
        . as $item
        | if ($locales | length) == 0 then true
          else (($item[$field]? | type) == "object" and all($locales[]; (($item[$field][.] // "") | tostring | length) > 0))
          end;
      artifact_items as $items
      | ($items | length) > 0 and all($items[]; . as $item |
        type == "object" and
        all(["id","groupId","order","display","reading","phonicsCue","noteByLocale","unitType","example","exampleTranslationByLocale","pronunciationFeatures","scriptId"][]; . as $field | $item | has($field)) and
        nonblank(.id) and nonblank(.groupId) and ((.order // null) | type) == "number" and
        nonblank(.display) and nonblank(.reading) and nonblank(.phonicsCue) and
        has_locale_map("noteByLocale") and nonblank(.unitType) and nonblank(.example) and has_locale_map("exampleTranslationByLocale") and
        ((.pronunciationFeatures // []) | type) == "array" and ((.pronunciationFeatures // []) | length) > 0 and nonblank(.scriptId)
      )
    ' "$artifact_path" >/dev/null 2>&1; then
      failures+=("alphabet cards must follow the expected phonics card schema and include locale notes/translations")
    fi

    range="$(prompt_card_count_range "$prompt" || true)"
    if [[ "$range" =~ ^([0-9]+)[[:space:]]([0-9]+)$ ]]; then
      min_cards="${BASH_REMATCH[1]}"
      max_cards="${BASH_REMATCH[2]}"
      if ! jq -e --argjson min "$min_cards" --argjson max "$max_cards" '
        def artifact_items:
          if type == "array" then .
          elif type == "object" then
            if (.cards? | type) == "array" then .cards
            elif (.items? | type) == "array" then .items
            elif (.entries? | type) == "array" then .entries
            elif (.data? | type) == "array" then .data
            elif (.results? | type) == "array" then .results
            elif (.records? | type) == "array" then .records
            else []
            end
          else []
          end;
        (artifact_items | length) >= $min and (artifact_items | length) <= $max
      ' "$artifact_path" >/dev/null 2>&1; then
        failures+=("alphabet card count must be between ${min_cards} and ${max_cards}")
      fi
    fi
  fi

  if [[ "$is_source_cards" -eq 1 || "$is_vocab" -eq 1 || "$is_sentences" -eq 1 || "$is_lessons" -eq 1 || "$is_alphabet" -eq 1 ]]; then
    if string_has_any "$lowered_prompt" "avoid vulgarity" "slang traps" "concha" "coger" "boludo"; then
      banned_hits="$(jq -r '.. | strings | ascii_downcase | scan("\\b(concha|coger|boludo|mina|quilombo|garcha|pelotudo|forro)\\b")' "$artifact_path" 2>/dev/null | LC_ALL=C sort -u | join_terms_csv || true)"
      if [[ -n "$banned_hits" ]]; then
        failures+=("artifact includes banned Buenos Aires slang/safety terms: ${banned_hits}")
      fi
    fi
  fi

  if [[ "${#failures[@]}" -gt 0 ]]; then
    ONLYMACS_CONTENT_PIPELINE_VALIDATION_STATUS="failed"
    ONLYMACS_CONTENT_PIPELINE_VALIDATION_MESSAGE="$(printf '%s; ' "${failures[@]}" | sed -E 's/; $//' | cut -c 1-500)"
  elif [[ "$is_set_definitions" -eq 1 || "$is_source_cards" -eq 1 || "$is_vocab" -eq 1 || "$is_sentences" -eq 1 || "$is_lessons" -eq 1 || "$is_alphabet" -eq 1 ]]; then
    ONLYMACS_CONTENT_PIPELINE_VALIDATION_STATUS="passed"
    ONLYMACS_CONTENT_PIPELINE_VALIDATION_MESSAGE="Content-pipeline artifact schema validation passed."
  fi
}
