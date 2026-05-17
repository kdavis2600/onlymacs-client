#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"
VALIDATION_DIR="${ONLYMACS_VALIDATION_DIR:-$ROOT_DIR/.tmp/validation}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="${ONLYMACS_FRIEND_MATRIX_LOG_PATH:-$VALIDATION_DIR/onlymacs-friend-public-matrix-$TIMESTAMP.log}"
SUMMARY_PATH="${ONLYMACS_FRIEND_MATRIX_SUMMARY_PATH:-$VALIDATION_DIR/onlymacs-friend-public-matrix-$TIMESTAMP.summary.json}"
RESULTS_PATH="${ONLYMACS_FRIEND_MATRIX_RESULTS_PATH:-$VALIDATION_DIR/onlymacs-friend-public-matrix-$TIMESTAMP.results.jsonl}"

APP_BUILD_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-build-$TIMESTAMP.log"
SWIFT_TEST_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-swift-$TIMESTAMP.log"
COORD_TEST_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-coordinator-$TIMESTAMP.log"
BRIDGE_TEST_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-bridge-$TIMESTAMP.log"
COORD_FOCUS_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-coordinator-focus-$TIMESTAMP.log"
BRIDGE_FOCUS_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-bridge-focus-$TIMESTAMP.log"
PUBLIC_REHEARSAL_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-public-rehearsal-$TIMESTAMP.log"
PUBLIC_EXECUTION_REHEARSAL_LOG="$VALIDATION_DIR/onlymacs-friend-public-matrix-public-execution-rehearsal-$TIMESTAMP.log"

APP_PATH="$ROOT_DIR/dist/OnlyMacs.app"
INFO_PLIST=""
TEST_COORDINATOR_URL="${ONLYMACS_FRIEND_MATRIX_COORDINATOR_URL:-https://relay.onlymacs.example.com}"
PUBLIC_REHEARSAL_TMP="$ROOT_DIR/.tmp/two-bridge-public-smoke"
PUBLIC_REHEARSAL_SUMMARY="$PUBLIC_REHEARSAL_TMP/summary.json"
PUBLIC_REHEARSAL_MODELS="$PUBLIC_REHEARSAL_TMP/requester-models.json"
PUBLIC_EXECUTION_TMP="$ROOT_DIR/.tmp/two-bridge-public-execution-smoke"
PUBLIC_EXECUTION_SUMMARY="$PUBLIC_EXECUTION_TMP/summary.json"
APP_COORDINATOR_URL=""
SHARED_MODEL=""
EXECUTION_SHARED_MODEL=""
COMPLETED_EXECUTION_SESSION_ID=""

mkdir -p "$VALIDATION_DIR"
: >"$LOG_PATH"
: >"$RESULTS_PATH"

pass_count=0
fail_count=0

log() {
  printf '[friend-public-matrix] %s\n' "$*" | tee -a "$LOG_PATH"
}

append_result() {
  local scenario_id="$1"
  local status="$2"
  local detail="$3"
  jq -cn \
    --arg id "$scenario_id" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{id:$id,status:$status,detail:$detail}' >>"$RESULTS_PATH"
}

record_pass() {
  local scenario_id="$1"
  local detail="$2"
  pass_count=$((pass_count + 1))
  append_result "$scenario_id" "passed" "$detail"
  log "PASS $scenario_id $detail"
}

record_fail() {
  local scenario_id="$1"
  local detail="$2"
  fail_count=$((fail_count + 1))
  append_result "$scenario_id" "failed" "$detail"
  log "FAIL $scenario_id $detail"
}

check_cmd() {
  local scenario_id="$1"
  local detail="$2"
  shift 2
  if "$@" >>"$LOG_PATH" 2>&1; then
    record_pass "$scenario_id" "$detail"
  else
    record_fail "$scenario_id" "$detail"
  fi
}

check_shell() {
  local scenario_id="$1"
  local detail="$2"
  local command="$3"
  if bash -lc "$command" >>"$LOG_PATH" 2>&1; then
    record_pass "$scenario_id" "$detail"
  else
    record_fail "$scenario_id" "$detail"
  fi
}

log "Building OnlyMacs app bundle with test coordinator default $TEST_COORDINATOR_URL"
if ONLYMACS_DEFAULT_COORDINATOR_URL="$TEST_COORDINATOR_URL" "$ROOT_DIR/scripts/build-macos-app-public.sh" >"$APP_BUILD_LOG" 2>&1; then
  build_ok=1
else
  build_ok=0
fi
if [[ "$build_ok" -eq 1 ]]; then
  built_app_path="$(tail -n 1 "$APP_BUILD_LOG" 2>/dev/null || true)"
  if [[ -n "$built_app_path" && -d "$built_app_path" ]]; then
    APP_PATH="$built_app_path"
  fi
fi
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  APP_COORDINATOR_URL="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsDefaultCoordinatorURL' "$INFO_PLIST" 2>/dev/null || true)"
fi

log "Running macOS app tests"
if swift test --package-path "$ROOT_DIR/apps/onlymacs-macos" >"$SWIFT_TEST_LOG" 2>&1; then
  swift_ok=1
else
  swift_ok=0
fi

log "Running coordinator tests"
if (cd "$COORDINATOR_REPO" && go test ./...) >"$COORD_TEST_LOG" 2>&1; then
  coord_ok=1
else
  coord_ok=0
fi

log "Running local bridge tests"
if (cd "$ROOT_DIR/apps/local-bridge" && go test ./...) >"$BRIDGE_TEST_LOG" 2>&1; then
  bridge_ok=1
else
  bridge_ok=0
fi

log "Running focused public-membership coordinator tests"
if (cd "$COORDINATOR_REPO" && go test ./internal/httpapi -run 'TestPublicCapableParticipantContributesVisiblePublicMembership|TestPrivateMemberUpsertRequiresExistingInviteJoin') >"$COORD_FOCUS_LOG" 2>&1; then
  coord_focus_ok=1
else
  coord_focus_ok=0
fi

log "Running focused public-swarm bridge tests"
if (cd "$ROOT_DIR/apps/local-bridge" && go test ./internal/httpapi -run 'TestPublicRuntimeStatusKeepsRequesterMembershipWithoutShareCapability|TestPublicRuntimeStatusAutoPublishesCapableMachine|TestElasticSwarmSpreadsAcrossDistinctProvidersBeforeReusingOne') >"$BRIDGE_FOCUS_LOG" 2>&1; then
  bridge_focus_ok=1
else
  bridge_focus_ok=0
fi

log "Running two-bridge public-swarm rehearsal"
if bash "$ROOT_DIR/scripts/make-two-bridge-public-smoke.sh" >"$PUBLIC_REHEARSAL_LOG" 2>&1; then
  public_rehearsal_ok=1
else
  public_rehearsal_ok=0
fi
if [[ -f "$PUBLIC_REHEARSAL_SUMMARY" ]]; then
  SHARED_MODEL="$(jq -r '.shared_model // ""' "$PUBLIC_REHEARSAL_SUMMARY" 2>/dev/null || true)"
fi

log "Running two-bridge public execution rehearsal"
if bash "$ROOT_DIR/scripts/make-two-bridge-public-execution-smoke.sh" >"$PUBLIC_EXECUTION_REHEARSAL_LOG" 2>&1; then
  public_execution_ok=1
else
  public_execution_ok=0
fi
if [[ -f "$PUBLIC_EXECUTION_SUMMARY" ]]; then
  EXECUTION_SHARED_MODEL="$(jq -r '.shared_model // ""' "$PUBLIC_EXECUTION_SUMMARY" 2>/dev/null || true)"
  COMPLETED_EXECUTION_SESSION_ID="$(jq -r '.completed_session.id // ""' "$PUBLIC_EXECUTION_SUMMARY" 2>/dev/null || true)"
fi

check_shell "S01" "App bundle build succeeded for packaged friend flow" "[[ $build_ok -eq 1 ]]"
check_shell "S02" "OnlyMacs.app exists after build" "[[ -d '$APP_PATH' ]]"
check_shell "S03" "Info.plist exists in app bundle" "[[ -f '$INFO_PLIST' ]]"
check_shell "S04" "Packaged app embeds a default coordinator URL" "[[ '$APP_COORDINATOR_URL' != '' ]]"
check_shell "S05" "Packaged coordinator URL matches the injected shared coordinator target" "[[ '$APP_COORDINATOR_URL' == '$TEST_COORDINATOR_URL' ]]"
check_shell "S06" "Packaged coordinator URL uses HTTPS" "[[ '$APP_COORDINATOR_URL' == https://* ]]"
check_shell "S07" "Sparkle feed URL is still embedded in the app bundle" "[[ \"$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' '$INFO_PLIST' 2>/dev/null || true)\" != '' ]]"
check_shell "S08" "Sparkle public key is still embedded in the app bundle" "[[ \"$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' '$INFO_PLIST' 2>/dev/null || true)\" != '' ]]"
check_shell "S09" "Bundled coordinator helper exists in the app package" "[[ -x '$APP_PATH/Contents/Helpers/onlymacs-coordinator' ]]"
check_shell "S10" "Bundled local bridge helper exists in the app package" "[[ -x '$APP_PATH/Contents/Helpers/onlymacs-local-bridge' ]]"
check_shell "S11" "Bundled integrations resources exist in the app package" "[[ -d '$APP_PATH/Contents/Resources/Integrations' ]]"
check_shell "S12" "Bundled Codex integration uses one skill and the onlymacs-shell launcher" "[[ -f '$APP_PATH/Contents/Resources/Integrations/codex/skills/onlymacs/SKILL.md' && -x '$APP_PATH/Contents/Resources/Integrations/codex/onlymacs-shell.sh' && ! -e '$APP_PATH/Contents/Resources/Integrations/codex/onlymacs-codex.sh' ]]"
check_shell "S12b" "Installer no longer seeds hidden Ollama auto-launch markers" "! rg -q 'seed-ollama|bootstrap-ollama|OnlyMacs-seed-ollama' '$ROOT_DIR/scripts/macos-pkg/distribution.xml.tmpl' '$ROOT_DIR/scripts/build-macos-pkg-public.sh' && [[ ! -e '$ROOT_DIR/scripts/macos-pkg/package-scripts/bootstrap-ollama.sh' ]]"
sparkle_auto_update="$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$INFO_PLIST" 2>/dev/null || true)"
sparkle_allows_automatic_updates="$(/usr/libexec/PlistBuddy -c 'Print :SUAllowsAutomaticUpdates' "$INFO_PLIST" 2>/dev/null || true)"
sparkle_check_interval="$(/usr/libexec/PlistBuddy -c 'Print :SUScheduledCheckInterval' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$sparkle_auto_update" == "true" && "$sparkle_allows_automatic_updates" == "true" && "$sparkle_check_interval" == "3600" ]]; then
  record_pass "S12c" "Sparkle can automatically download signed updates"
else
  record_fail "S12c" "Sparkle can automatically download signed updates"
fi

check_shell "S13" "Qwen 2.5 Coder 14B exists in the catalog" "jq -e '.models[] | select(.id == \"qwen25-coder-14b-q4km\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S14" "Qwen 2.5 Coder 14B is visible to tier3 hosts" "jq -e '.models[] | select(.id == \"qwen25-coder-14b-q4km\") | .capability_tiers.first_run_visible_tiers | index(\"tier3\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S15" "Qwen 2.5 Coder 14B is visible to tier2 hosts" "jq -e '.models[] | select(.id == \"qwen25-coder-14b-q4km\") | .capability_tiers.first_run_visible_tiers | index(\"tier2\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S16" "Qwen 2.5 Coder 14B is default-selected for tier3 installs" "jq -e '.models[] | select(.id == \"qwen25-coder-14b-q4km\") | .installer.default_selected_tiers | index(\"tier3\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S17" "Qwen 2.5 Coder 14B remains in the starter subset for mixed-tier compatibility" "jq -e '.models[] | select(.id == \"qwen25-coder-14b-q4km\") | .installer.starter_subset == true' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S18" "Qwen 3.6 35B exists in the catalog" "jq -e '.models[] | select(.id == \"qwen36-35b-a3b-q8_0\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S19" "Qwen 3.6 35B stays default-selected for tier2 installs" "jq -e '.models[] | select(.id == \"qwen36-35b-a3b-q8_0\") | .installer.default_selected_tiers | index(\"tier2\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S20" "Qwen 2.5 Coder 32B still exists in the catalog for premium hosts" "jq -e '.models[] | select(.id == \"qwen25-coder-32b-q4km\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"
check_shell "S21" "Qwen 2.5 Coder 32B stays default-selected for tier2 installs" "jq -e '.models[] | select(.id == \"qwen25-coder-32b-q4km\") | .installer.default_selected_tiers | index(\"tier2\")' '$ROOT_DIR/apps/onlymacs-macos/Sources/OnlyMacsCore/Resources/model-catalog.v1.json' >/dev/null"

check_shell "S22" "Full macOS app test suite passed" "[[ $swift_ok -eq 1 ]]"
check_shell "S23" "Full coordinator test suite passed" "[[ $coord_ok -eq 1 ]]"
check_shell "S24" "Full local bridge test suite passed" "[[ $bridge_ok -eq 1 ]]"
check_shell "S25" "Focused coordinator public-membership tests passed" "[[ $coord_focus_ok -eq 1 ]]"
check_shell "S26" "Focused bridge public-membership and spread tests passed" "[[ $bridge_focus_ok -eq 1 ]]"

check_shell "S27" "Two-bridge public rehearsal completed successfully" "[[ $public_rehearsal_ok -eq 1 ]]"
check_shell "S28" "Two-bridge public rehearsal wrote a summary artifact" "[[ -f '$PUBLIC_REHEARSAL_SUMMARY' ]]"
check_shell "S29" "Public swarm registers exactly two members in the rehearsal" "jq -e '.public_swarm.member_count == 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S30" "Public swarm remains visible as a public swarm in the rehearsal" "jq -e '.public_swarm.visibility == \"public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S31" "Public swarm shows two sharing Macs in the rehearsal" "jq -e '.public_swarm.provider_count == 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S32" "Public swarm exposes at least two total slots in the rehearsal" "jq -e '.public_swarm.slots_total >= 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S33" "Public swarm has at least two free slots before the swarm starts" "jq -e '.public_swarm.slots_free >= 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S34" "Requester bridge runtime is pinned to swarm-public" "jq -e '.requester_status.runtime.active_swarm_id == \"swarm-public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S35" "Friend bridge runtime is pinned to swarm-public" "jq -e '.friend_status.runtime.active_swarm_id == \"swarm-public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S36" "Requester bridge sees OnlyMacs Public as the active swarm name" "jq -e '.requester_status.bridge.active_swarm_name == \"OnlyMacs Public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S37" "Friend bridge sees OnlyMacs Public as the active swarm name" "jq -e '.friend_status.bridge.active_swarm_name == \"OnlyMacs Public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S38" "Requester bridge is published into the public swarm" "jq -e '.requester_status.sharing.published == true' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S39" "Friend bridge is published into the public swarm" "jq -e '.friend_status.sharing.published == true' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S40" "Requester published share points at swarm-public" "jq -e '.requester_status.sharing.active_swarm_id == \"swarm-public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S41" "Friend published share points at swarm-public" "jq -e '.friend_status.sharing.active_swarm_id == \"swarm-public\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S42" "Requester discovers at least one local model before sharing" "jq -e '(.requester_status.sharing.discovered_models | length) > 0' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S43" "Friend discovers at least one local model before sharing" "jq -e '(.friend_status.sharing.discovered_models | length) > 0' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S44" "Rehearsal selects a shared model for both Macs" "jq -e '.shared_model != null and .shared_model != \"\"' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S45" "Requester aggregated model list contains the shared model" "jq -e --arg model '$SHARED_MODEL' '.models[] | select(.id == \$model)' '$PUBLIC_REHEARSAL_MODELS' >/dev/null"
check_shell "S46" "Shared model exposes two total slots across the two Macs" "jq -e --arg model '$SHARED_MODEL' '[.models[] | select(.id == \$model)][0].slots_total == 2' '$PUBLIC_REHEARSAL_MODELS' >/dev/null"
check_shell "S47" "Swarm start asks for two agents in the public rehearsal" "jq -e '.swarm_start.session.requested_agents == 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S48" "Swarm start admits two agents in the public rehearsal" "jq -e '.swarm_start.session.admitted_agents == 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S49" "Swarm start uses two distinct providers instead of doubling up on one Mac" "jq -e '(.swarm_start.session.reservations | map(.provider_id) | unique | length) == 2' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"
check_shell "S50" "Swarm route summary explicitly reports This Mac plus one remote Mac" "jq -e '.swarm_start.session.route_summary | test(\"This Mac and 1 remote Mac\")' '$PUBLIC_REHEARSAL_SUMMARY' >/dev/null"

check_shell "S51" "Two-bridge public execution rehearsal completed successfully" "[[ $public_execution_ok -eq 1 ]]"
check_shell "S52" "Two-bridge public execution rehearsal wrote a summary artifact" "[[ -f '$PUBLIC_EXECUTION_SUMMARY' ]]"
check_shell "S53" "Execution rehearsal keeps exactly two public members visible" "jq -e '.public_swarm.member_count == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S54" "Execution rehearsal keeps two sharing Macs visible in the public swarm" "jq -e '.public_swarm.provider_count == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S55" "Execution rehearsal keeps at least two total public slots available" "jq -e '.public_swarm.slots_total >= 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S56" "Requester status before execution is pinned to OnlyMacs Public" "jq -e '.requester_status_before.bridge.active_swarm_name == \"OnlyMacs Public\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S57" "Friend status before execution is pinned to OnlyMacs Public" "jq -e '.friend_status_before.bridge.active_swarm_name == \"OnlyMacs Public\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S58" "Requester is already published into the public swarm before execution" "jq -e '.requester_status_before.sharing.published == true' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S59" "Friend is already published into the public swarm before execution" "jq -e '.friend_status_before.sharing.published == true' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S60" "Requester has at least one local model discovered before execution" "jq -e '(.requester_status_before.sharing.discovered_models | length) > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S61" "Friend has at least one local model discovered before execution" "jq -e '(.friend_status_before.sharing.discovered_models | length) > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S62" "Execution rehearsal resolves a shared model for the two Macs" "jq -e '.shared_model != null and .shared_model != \"\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S63" "Requester sees at least one live swarm while execution is in flight" "jq -e '.requester_status_during.swarm.active_session_count >= 1' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S64" "Friend sees at least one live local share job while execution is in flight" "jq -e '.friend_status_during.sharing.active_sessions >= 1' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S65" "Requester swarm snapshot reports live work while execution is in flight" "jq -e '.requester_status_during.swarm.active_session_count >= 1' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S66" "Friend remains published while execution is in flight" "jq -e '.friend_status_during.sharing.published == true' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S67" "Requester swarm start still asks for two agents in the execution rehearsal" "jq -e '.swarm_start.session.requested_agents == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S68" "Requester swarm start still admits two agents in the execution rehearsal" "jq -e '.swarm_start.session.admitted_agents == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S69" "Execution rehearsal reserves two workers up front" "jq -e '(.swarm_start.session.reservations | length) == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S70" "Execution rehearsal reserves two distinct Macs up front" "jq -e '(.swarm_start.session.reservations | map(.provider_id) | unique | length) == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S71" "Completed execution session reaches completed status" "jq -e '.completed_session.status == \"completed\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S72" "Completed execution session checkpoint is marked completed" "jq -e '.completed_session.checkpoint.status == \"completed\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S73" "Completed execution session keeps the same resolved shared model" "jq -e --arg model '$EXECUTION_SHARED_MODEL' '.completed_session.resolved_model == \$model' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S74" "Completed execution session route summary reports This Mac plus one remote Mac" "jq -e '.completed_session.route_summary | test(\"This Mac and 1 remote Mac\")' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S75" "Completed execution session preserves two admitted agents" "jq -e '.completed_session.admitted_agents == 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S76" "Completed execution session checkpoint output mentions Kevin's Mac" "jq -e '.completed_session.checkpoint.output_preview | test(\"Kevin MacBook Pro\")' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S77" "Completed execution session checkpoint output mentions Charles's Mac" "jq -e '.completed_session.checkpoint.output_preview | test(\"Charles Mac Studio\")' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S78" "Completed execution session checkpoint output mentions the shared model" "jq -e --arg model '$EXECUTION_SHARED_MODEL' '.completed_session.checkpoint.output_preview | contains(\$model)' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S79" "Requester returns to zero live swarms after execution finishes" "jq -e '.requester_status_after.swarm.active_session_count == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S80" "Friend returns to zero live share jobs after execution finishes" "jq -e '.friend_status_after.sharing.active_sessions == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S81" "Requester post-run saved token estimate is non-zero" "jq -e '.requester_status_after.usage.tokens_saved_estimate > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S82" "Requester post-run downloaded token estimate is non-zero" "jq -e '.requester_status_after.usage.downloaded_tokens_estimate > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S83" "Completed execution session stores a non-zero saved token estimate" "jq -e '.completed_session.saved_tokens_estimate > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S84" "Friend post-run served session count increments" "jq -e '.friend_status_after.sharing.served_sessions > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S85" "Friend post-run uploaded token estimate increments" "jq -e '.friend_status_after.sharing.uploaded_tokens_estimate > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S86" "Friend usage summary reflects uploaded token contribution" "jq -e '.friend_status_after.usage.uploaded_tokens_estimate > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S87" "Friend post-run last served model matches the shared model" "jq -e --arg model '$EXECUTION_SHARED_MODEL' '.friend_status_after.sharing.last_served_model == \$model' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S88" "Requester post-run session list still contains the completed session" "jq -e --arg session_id '$COMPLETED_EXECUTION_SESSION_ID' '.requester_sessions_after.sessions[] | select(.id == \$session_id and .status == \"completed\")' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S89" "Requester post-run session checkpoint output stays non-empty" "jq -e '.completed_session.checkpoint.output_preview != null and .completed_session.checkpoint.output_preview != \"\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S90" "Requester starts the execution rehearsal with zero downloaded tokens" "jq -e '.requester_status_before.usage.downloaded_tokens_estimate == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S91" "Friend starts the execution rehearsal with zero uploaded tokens" "jq -e '.friend_status_before.sharing.uploaded_tokens_estimate == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S92" "Requester starts the execution rehearsal with zero live swarms" "jq -e '.requester_status_before.swarm.active_session_count == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S93" "Friend starts the execution rehearsal with zero live share jobs" "jq -e '.friend_status_before.sharing.active_sessions == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S94" "Requester stays pinned to OnlyMacs Public after execution" "jq -e '.requester_status_after.bridge.active_swarm_name == \"OnlyMacs Public\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S95" "Friend stays pinned to OnlyMacs Public after execution" "jq -e '.friend_status_after.bridge.active_swarm_name == \"OnlyMacs Public\"' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S96" "Public swarm returns to at least two free slots after execution" "jq -e '.public_swarm.slots_free >= 2' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S97" "Requester swarm snapshot returns to zero live work after execution" "jq -e '.requester_status_after.swarm.active_session_count == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S98" "Friend swarm snapshot returns to zero live work after execution" "jq -e '.friend_status_after.swarm.active_session_count == 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S99" "Requester local share side also records that its Mac served work" "jq -e '.requester_status_after.sharing.served_sessions > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"
check_shell "S100" "Requester local share side also records uploaded tokens from its worker" "jq -e '.requester_status_after.sharing.uploaded_tokens_estimate > 0' '$PUBLIC_EXECUTION_SUMMARY' >/dev/null"

total_count=$((pass_count + fail_count))

jq -n \
  --arg generated_at "$TIMESTAMP" \
  --arg log_path "$LOG_PATH" \
  --arg results_path "$RESULTS_PATH" \
  --arg build_log "$APP_BUILD_LOG" \
  --arg swift_log "$SWIFT_TEST_LOG" \
  --arg coordinator_log "$COORD_TEST_LOG" \
  --arg bridge_log "$BRIDGE_TEST_LOG" \
  --arg public_rehearsal_log "$PUBLIC_REHEARSAL_LOG" \
  --arg public_rehearsal_summary "$PUBLIC_REHEARSAL_SUMMARY" \
  --arg public_execution_rehearsal_log "$PUBLIC_EXECUTION_REHEARSAL_LOG" \
  --arg public_execution_summary "$PUBLIC_EXECUTION_SUMMARY" \
  --arg coordinator_url "$TEST_COORDINATOR_URL" \
  --argjson passed "$pass_count" \
  --argjson failed "$fail_count" \
  --argjson total "$total_count" \
  '{
    generated_at: $generated_at,
    coordinator_url: $coordinator_url,
    passed: $passed,
    failed: $failed,
    total: $total,
    log_path: $log_path,
    results_path: $results_path,
    build_log: $build_log,
    swift_log: $swift_log,
    coordinator_log: $coordinator_log,
    bridge_log: $bridge_log,
    public_rehearsal_log: $public_rehearsal_log,
    public_rehearsal_summary: $public_rehearsal_summary,
    public_execution_rehearsal_log: $public_execution_rehearsal_log,
    public_execution_summary: $public_execution_summary
  }' >"$SUMMARY_PATH"

if [[ "$fail_count" -gt 0 ]]; then
  log "Friend public matrix failed: $fail_count scenario(s) failed"
  exit 1
fi

log "Friend public matrix passed: $pass_count / $total_count scenarios green"
echo "$SUMMARY_PATH"
