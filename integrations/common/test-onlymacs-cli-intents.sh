#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ONLYMACS_ENABLE_CONTENT_PIPELINE_VALIDATORS=1
# shellcheck source=./onlymacs-cli.sh
source "$SCRIPT_DIR/onlymacs-cli.sh"

TEMP_STATE_DIR="$(mktemp -d)"
export ONLYMACS_STATE_DIR="$TEMP_STATE_DIR"
trap 'rm -rf "$TEMP_STATE_DIR"' EXIT

fail() {
  printf 'intent smoke test failed: %s\n' "$1" >&2
  exit 1
}

assert_intent() {
  local phrase="$1"
  local expected_interpretation="$2"
  shift 2
  local expected_args=("$@")

  unset ONLYMACS_CONTEXT_READ_MODE ONLYMACS_CONTEXT_WRITE_MODE ONLYMACS_CONTEXT_ALLOW_TESTS ONLYMACS_CONTEXT_ALLOW_INSTALL
  ONLYMACS_EXECUTION_MODE="auto"
  ONLYMACS_SIMPLE_MODE=0

  if ! resolve_natural_language_command "$phrase"; then
    fail "did not resolve phrase: $phrase"
  fi

  if [[ "${ONLYMACS_ROUTER_INTERPRETATION:-}" != "$expected_interpretation" ]]; then
    fail "unexpected interpretation for '$phrase' (wanted '$expected_interpretation', got '${ONLYMACS_ROUTER_INTERPRETATION:-}')"
  fi

  if [[ "${#ONLYMACS_ROUTED_ARGS[@]}" -ne "${#expected_args[@]}" ]]; then
    fail "unexpected arg count for '$phrase'"
  fi

  local idx
  for idx in "${!expected_args[@]}"; do
    if [[ "${ONLYMACS_ROUTED_ARGS[$idx]}" != "${expected_args[$idx]}" ]]; then
      fail "unexpected arg $idx for '$phrase' (wanted '${expected_args[$idx]}', got '${ONLYMACS_ROUTED_ARGS[$idx]}')"
    fi
  done
}

assert_intent_with_reason() {
  local phrase="$1"
  local expected_interpretation="$2"
  local expected_reason="$3"
  shift 3
  local expected_args=("$@")

  assert_intent "$phrase" "$expected_interpretation" "${expected_args[@]}"

  if [[ "${ONLYMACS_ROUTER_REASON:-}" != "$expected_reason" ]]; then
    fail "unexpected router reason for '$phrase' (wanted '$expected_reason', got '${ONLYMACS_ROUTER_REASON:-}')"
  fi
}

if ! parse_leading_options; then
  fail "expected empty leading options to parse"
fi
if [[ "${#ONLYMACS_PARSED_ARGS[@]}" -ne 0 ]]; then
  fail "expected empty leading options to leave no parsed args"
fi
if [[ "$(ONLYMACS_REPAIR_LIMIT=5 orchestrated_repair_limit)" != "5" ]]; then
  fail "expected ONLYMACS_REPAIR_LIMIT to override bounded repair attempts"
fi
if [[ "$(ONLYMACS_EXECUTION_MODE=overnight orchestrated_repair_limit)" != "3" ]]; then
  fail "expected overnight mode to allow one extra repair attempt"
fi

help_output="$(onlymacs_cli_main "OnlyMacs" "onlymacs")" || fail "expected no-arg CLI invocation to print help"
if [[ "$help_output" != *"OnlyMacs for OnlyMacs"* || "$help_output" != *"onlymacs \"your task\""* || "$help_output" != *"plain onlymacs and plain chat requests prefer another Mac when available"* || "$help_output" != *"resume-run [latest|run-id|inbox-path]"* || "$help_output" != *"support-bundle [latest|run-id|inbox-path]"* || "$help_output" != *"inbox [latest|run-id|inbox-path]"* ]]; then
  fail "expected no-arg CLI help to describe the best-available swarm default"
fi

status_output="$(format_system_status '{"bridge":{"status":"ready","active_swarm_name":"OnlyMacs Public"},"runtime":{"mode":"both"},"swarm":{"slots_free":2,"slots_total":2,"model_count":11,"active_session_count":0,"queued_session_count":0,"queue_summary":{}},"providers":[{},{}],"sharing":{"status":"available"},"usage":{}}')"
if [[ "$status_output" != *"Providers: 2"* || "$status_output" != *"Models: 11"* ]]; then
  fail "expected system status formatting to count provider arrays from current status payloads"
fi
benchmark_status_fixture='{
  "identity": {"member_id": "member-local", "provider_id": "provider-kevin"},
  "members": [
    {
      "member_id": "member-local",
      "member_name": "Kevin",
      "capabilities": [{
        "provider_id": "provider-kevin",
        "provider_name": "Kevin",
        "status": "available",
        "slots": {"free": 1, "total": 1},
        "recent_uploaded_tokens_per_second": 30,
        "models": [{"id": "qwen3.6:35b-a3b-q4_K_M"}]
      }]
    },
    {
      "member_id": "member-charles",
      "member_name": "Charles",
      "capabilities": [{
        "provider_id": "provider-charles",
        "provider_name": "Charles",
        "status": "available",
        "slots": {"free": 1, "total": 1},
        "recent_uploaded_tokens_per_second": 42,
        "models": [{"id": "qwen3.6:35b-a3b-q8_0"}, {"id": "qwen3.6:35b-a3b-q4_K_M"}]
      }]
    }
  ]
}'
benchmark_report="$(onlymacs_benchmark_preflight_report "$benchmark_status_fixture" "swarm" "remote-first" "return 5 strict JSON objects")"
if [[ "$(jq -r '.recommended.provider_id // empty' <<<"$benchmark_report")" != "provider-charles" || "$(jq -r '.recommended.model // empty' <<<"$benchmark_report")" != "qwen3.6:35b-a3b-q8_0" ]]; then
  fail "expected benchmark preflight to recommend the strongest eligible remote provider/model"
fi
if jq -e '.candidates[] | select(.provider_id == "provider-kevin")' <<<"$benchmark_report" >/dev/null; then
  fail "expected remote-first benchmark preflight to exclude the requester provider"
fi
if ! jq -e '.recommended.benchmark_metrics.first_artifact_latency_seconds == null and (.note | contains("--live"))' <<<"$benchmark_report" >/dev/null; then
  fail "expected benchmark preflight report to expose live-probe metric slots and --live guidance"
fi

unset ONLYMACS_GO_WIDE_JSON_LANES
parse_leading_options --go-wide "use both my Mac and other Macs for this audit" || fail "expected --go-wide to parse"
if [[ "${ONLYMACS_FORCE_ACTION:-}" != "go" || "${ONLYMACS_FORCE_PRESET:-}" != "wide" ]]; then
  fail "expected --go-wide to force go wide routing"
fi
if [[ "${ONLYMACS_GO_WIDE_MODE:-0}" != "1" || "$(orchestrated_go_wide_json_lanes wide)" != "2" || "$(orchestrated_go_wide_shadow_review_mode wide)" != "async" ]]; then
  fail "expected --go-wide to enable reusable go-wide JSON scheduling defaults"
fi
unset ONLYMACS_GO_WIDE_JSON_LANES
parse_leading_options --go-wide=4 "use four Macs for this batch job" || fail "expected --go-wide=4 to parse"
if [[ "${ONLYMACS_GO_WIDE_MODE:-0}" != "1" || "$(orchestrated_go_wide_json_lanes wide)" != "4" ]]; then
  fail "expected --go-wide=4 to configure four go-wide worker lanes"
fi
parse_leading_options --go-wide-lanes 99 "cap a swarm-sized job" || fail "expected --go-wide-lanes to parse"
if [[ "$(orchestrated_go_wide_json_lanes wide)" != "8" ]]; then
  fail "expected go-wide lane counts to clamp at eight workers"
fi
parse_leading_options --go-wide=max "use every ticket-board lane allowed by the swarm test" || fail "expected --go-wide=max to parse"
if [[ "$(orchestrated_go_wide_json_lanes wide)" != "8" ]]; then
  fail "expected --go-wide=max to configure the eight-lane ticket-board cap"
fi
parse_leading_options --go-wide-lanes 1 "run the same ticket board on one Mac" || fail "expected --go-wide-lanes 1 to parse"
if [[ "$(orchestrated_go_wide_json_lanes wide)" != "1" ]]; then
  fail "expected go-wide ticket board to support a single worker lane"
fi
unset ONLYMACS_GO_WIDE_JSON_LANES
go_wide_settings="$(onlymacs_execution_settings_json "Create exactly 40 JSON items." "wide" "swarm" 1)"
if ! jq -e '.go_wide.enabled == true and .go_wide.local_shadow_review == "async" and .go_wide.provider_affinity == "relaxed_between_batches" and .route_continuity.prefer_same_provider_for_followups == false' <<<"$go_wide_settings" >/dev/null; then
  fail "expected go-wide execution settings to relax provider affinity and pipeline local review"
fi
go_wide_resume_plan="$TEMP_STATE_DIR/go-wide-resume-plan.json"
cat >"$go_wide_resume_plan" <<'GO_WIDE_RESUME_JSON'
{
  "model_alias": "qwen3.6:35b-a3b-q8_0",
  "route_scope": "swarm",
  "execution_settings": {
    "model_alias": "qwen3.6:35b-a3b-q8_0",
    "route_scope": "swarm",
    "route_continuity": {
      "prefer_same_provider_for_followups": true,
      "provider_route_locked": true,
      "pinned_provider_id": "provider-stale"
    }
  },
  "steps": []
}
GO_WIDE_RESUME_JSON
ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=0
ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
orchestrated_backfill_go_wide_resume_settings "$go_wide_resume_plan" "wide" "swarm"
if ! jq -e '.model_alias == "wide" and .execution_settings.model_alias == "wide" and .execution_settings.go_wide.enabled == true and .execution_settings.go_wide.json_batch_lanes == 2 and .execution_settings.go_wide.local_shadow_review == "async" and .execution_settings.route_continuity.prefer_same_provider_for_followups == false and .execution_settings.route_continuity.pinned_provider_id == null' "$go_wide_resume_plan" >/dev/null; then
  fail "expected --go-wide resume backfill to persist relaxed scheduling settings"
fi
ONLYMACS_GO_WIDE_JSON_LANES=4
orchestrated_restore_execution_settings "$go_wide_resume_plan"
if [[ "$(orchestrated_go_wide_json_lanes wide)" != "4" ]]; then
  fail "expected explicit go-wide lane count to override persisted resume settings"
fi
unset ONLYMACS_GO_WIDE_JSON_LANES
orchestrated_restore_execution_settings "$go_wide_resume_plan"
if [[ "$(orchestrated_go_wide_json_lanes wide)" != "2" ]]; then
  fail "expected persisted go-wide lane count to restore when no explicit lane count is set"
fi
go_wide_ticket_run="$TEMP_STATE_DIR/go-wide-ticket-run"
mkdir -p "$go_wide_ticket_run"
cat >"$go_wide_ticket_run/plan.json" <<'GO_WIDE_TICKET_PLAN_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 10,
        "batches": [
          {"index": 1, "status": "pending"},
          {"index": 2, "status": "pending"},
          {"index": 3, "status": "pending"},
          {"index": 4, "status": "pending"},
          {"index": 5, "status": "pending"},
          {"index": 6, "status": "pending"},
          {"index": 7, "status": "pending"},
          {"index": 8, "status": "pending"},
          {"index": 9, "status": "pending"},
          {"index": 10, "status": "pending"}
        ]
      }
    }
  ]
}
GO_WIDE_TICKET_PLAN_JSON
ticket_claims="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_ticket_run/plan.json" "step-01" 8 | paste -sd, -)"
if [[ "$ticket_claims" != "1,2,3,4,5,6,7,8" ]]; then
  fail "expected go-wide ticket board to lease up to eight distinct initial batch tickets, got '$ticket_claims'"
fi
if ! jq -e '[.steps[0].batching.batches[] | select(.status == "leased")] | length == 8' "$go_wide_ticket_run/plan.json" >/dev/null; then
  fail "expected initial go-wide ticket claim to mark eight leased workers"
fi
if ! jq -e '[.steps[0].batching.batches[] | select(.status == "leased" and .ticket_kind == "generate")] | length == 8' "$go_wide_ticket_run/plan.json" >/dev/null; then
  fail "expected initially claimed go-wide tickets to be generation tickets"
fi
jq '
  .steps[0].batching.batches |= map(
    if .index == 1 then .status = "completed"
    elif .index == 3 then .status = "leased" | .updated_at = "2000-01-01T00:00:00Z"
    elif .index == 4 then .status = "repair_queued" | .updated_at = "2000-01-01T00:00:00Z"
    elif .index == 5 then .status = "retry_queued" | .updated_at = "2000-01-01T00:00:00Z"
    elif .index == 6 then .status = "partial" | .updated_at = "2000-01-01T00:00:00Z"
    else . end
  )
' "$go_wide_ticket_run/plan.json" >"$go_wide_ticket_run/plan.tmp" && mv "$go_wide_ticket_run/plan.tmp" "$go_wide_ticket_run/plan.json"
ticket_reclaims="$(ONLYMACS_GO_WIDE_TICKET_STALE_SECONDS=1 orchestrated_claim_go_wide_batch_tickets "$go_wide_ticket_run/plan.json" "step-01" 5 | paste -sd, -)"
if [[ "$ticket_reclaims" != "9,10,5,6,4" ]]; then
  fail "expected ticket board to prefer pending tickets before queued transport retries, repair tickets, and stale tickets, got '$ticket_reclaims'"
fi
if ! jq -e '.steps[0].batching.batches[] | select(.index == 5 and .status == "leased" and .ticket_kind == "generate")' "$go_wide_ticket_run/plan.json" >/dev/null; then
  fail "expected queued transport retry ticket to be leased as a generation ticket"
fi
if ! jq -e '.steps[0].batching.batches[] | select(.index == 6 and .status == "leased" and .ticket_kind == "generate")' "$go_wide_ticket_run/plan.json" >/dev/null; then
  fail "expected partial transport ticket to be leased as a generation retry ticket"
fi
if ! jq -e '.steps[0].batching.batches[] | select(.index == 4 and .status == "leased" and .ticket_kind == "repair")' "$go_wide_ticket_run/plan.json" >/dev/null; then
  fail "expected queued repair ticket to be leased as a repair ticket"
fi
go_wide_ticket_overclaim_run="$TEMP_STATE_DIR/go-wide-ticket-overclaim-run"
mkdir -p "$go_wide_ticket_overclaim_run"
cat >"$go_wide_ticket_overclaim_run/plan.json" <<'GO_WIDE_TICKET_OVERCLAIM_PLAN_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 12,
        "batches": [
          {"index": 1, "status": "pending"},
          {"index": 2, "status": "pending"},
          {"index": 3, "status": "pending"},
          {"index": 4, "status": "pending"},
          {"index": 5, "status": "pending"},
          {"index": 6, "status": "pending"},
          {"index": 7, "status": "pending"},
          {"index": 8, "status": "pending"},
          {"index": 9, "status": "pending"},
          {"index": 10, "status": "pending"},
          {"index": 11, "status": "pending"},
          {"index": 12, "status": "pending"}
        ]
      }
    }
  ]
}
GO_WIDE_TICKET_OVERCLAIM_PLAN_JSON
ticket_overclaim="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_ticket_overclaim_run/plan.json" "step-01" 99 | paste -sd, -)"
if [[ "$ticket_overclaim" != "1,2,3,4,5,6,7,8" ]]; then
  fail "expected go-wide ticket claims above eight to clamp at eight tickets, got '$ticket_overclaim'"
fi
go_wide_ticket_striped_run="$TEMP_STATE_DIR/go-wide-ticket-striped-run"
mkdir -p "$go_wide_ticket_striped_run"
cat >"$go_wide_ticket_striped_run/plan.json" <<'GO_WIDE_TICKET_STRIPED_PLAN_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 20,
        "ticket_board": {"batch_group_size": 4},
        "batches": [
          {"index": 1, "status": "pending"}, {"index": 2, "status": "pending"},
          {"index": 3, "status": "pending"}, {"index": 4, "status": "pending"},
          {"index": 5, "status": "pending"}, {"index": 6, "status": "pending"},
          {"index": 7, "status": "pending"}, {"index": 8, "status": "pending"},
          {"index": 9, "status": "pending"}, {"index": 10, "status": "pending"},
          {"index": 11, "status": "pending"}, {"index": 12, "status": "pending"},
          {"index": 13, "status": "pending"}, {"index": 14, "status": "pending"},
          {"index": 15, "status": "pending"}, {"index": 16, "status": "pending"},
          {"index": 17, "status": "pending"}, {"index": 18, "status": "pending"},
          {"index": 19, "status": "pending"}, {"index": 20, "status": "pending"}
        ]
      }
    }
  ]
}
GO_WIDE_TICKET_STRIPED_PLAN_JSON
ticket_striped="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_ticket_striped_run/plan.json" "step-01" 4 | paste -sd, -)"
if [[ "$ticket_striped" != "1,5,9,13" ]]; then
  fail "expected go-wide source-card tickets to stripe fresh work across item sets, got '$ticket_striped'"
fi
go_wide_ticket_cooldown_run="$TEMP_STATE_DIR/go-wide-ticket-cooldown-run"
mkdir -p "$go_wide_ticket_cooldown_run"
cat >"$go_wide_ticket_cooldown_run/plan.json" <<'GO_WIDE_TICKET_COOLDOWN_PLAN_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 16,
        "ticket_board": {"batch_group_size": 4},
        "batches": [
          {"index": 1, "status": "repair_queued"},
          {"index": 2, "status": "pending"},
          {"index": 3, "status": "pending"},
          {"index": 4, "status": "pending"},
          {"index": 5, "status": "pending"},
          {"index": 6, "status": "pending"},
          {"index": 7, "status": "pending"},
          {"index": 8, "status": "pending"},
          {"index": 9, "status": "pending"},
          {"index": 10, "status": "pending"},
          {"index": 11, "status": "pending"},
          {"index": 12, "status": "pending"},
          {"index": 13, "status": "pending"},
          {"index": 14, "status": "pending"},
          {"index": 15, "status": "pending"},
          {"index": 16, "status": "pending"}
        ]
      }
    }
  ]
}
GO_WIDE_TICKET_COOLDOWN_PLAN_JSON
ticket_cooldown="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_ticket_cooldown_run/plan.json" "step-01" 4 | paste -sd, -)"
if [[ "$ticket_cooldown" != "2,5,9,13" ]]; then
  fail "expected fresh source-card generation to outrank stale repair tickets while still striping sets, got '$ticket_cooldown'"
fi
if ! jq -e '.steps[0].batching.batches[] | select(.index == 2 and .status == "leased")' "$go_wide_ticket_cooldown_run/plan.json" >/dev/null; then
  fail "expected source-card ticket board to keep fresh siblings eligible ahead of repeated repair work"
fi
go_wide_retry_cooldown_run="$TEMP_STATE_DIR/go-wide-retry-cooldown-run"
mkdir -p "$go_wide_retry_cooldown_run"
future_retry_epoch="$(($(date +%s) + 60))"
past_retry_epoch="$(($(date +%s) - 60))"
cat >"$go_wide_retry_cooldown_run/plan.json" <<GO_WIDE_RETRY_COOLDOWN_PLAN_JSON
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 3,
        "batches": [
          {"index": 1, "status": "retry_queued", "retry_after_epoch": $future_retry_epoch},
          {"index": 2, "status": "pending"},
          {"index": 3, "status": "repair_queued"}
        ]
      }
    }
  ]
}
GO_WIDE_RETRY_COOLDOWN_PLAN_JSON
retry_cooldown_claim="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_retry_cooldown_run/plan.json" "step-01" 2 | paste -sd, -)"
if [[ "$retry_cooldown_claim" != "2,3" ]]; then
  fail "expected future retry cooldown to keep the transport retry off the board while other tickets claim, got '$retry_cooldown_claim'"
fi
jq --argjson past_retry_epoch "$past_retry_epoch" '
  .steps[0].batching.batches |= map(
    if .index == 1 then .retry_after_epoch = $past_retry_epoch
    elif .index == 2 or .index == 3 then .status = "completed"
    else . end
  )
' "$go_wide_retry_cooldown_run/plan.json" >"$go_wide_retry_cooldown_run/plan.tmp" && mv "$go_wide_retry_cooldown_run/plan.tmp" "$go_wide_retry_cooldown_run/plan.json"
retry_after_cooldown_claim="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_retry_cooldown_run/plan.json" "step-01" 1 | paste -sd, -)"
if [[ "$retry_after_cooldown_claim" != "1" ]]; then
  fail "expected expired retry cooldown to make the transport retry claimable, got '$retry_after_cooldown_claim'"
fi
if ! jq -e '.steps[0].batching.batches[] | select(.index == 1 and .status == "leased" and .retry_after_epoch == null)' "$go_wide_retry_cooldown_run/plan.json" >/dev/null; then
  fail "expected claiming a cooled retry to clear retry_after_epoch"
fi
go_wide_retry_repair_run="$TEMP_STATE_DIR/go-wide-retry-repair-run"
mkdir -p "$go_wide_retry_repair_run"
cat >"$go_wide_retry_repair_run/plan.json" <<GO_WIDE_RETRY_REPAIR_PLAN_JSON
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 1,
        "batches": [
          {"index": 1, "status": "retry_queued", "ticket_kind": "repair", "retry_after_epoch": $past_retry_epoch}
        ]
      }
    }
  ]
}
GO_WIDE_RETRY_REPAIR_PLAN_JSON
retry_repair_claim="$(orchestrated_claim_go_wide_batch_tickets "$go_wide_retry_repair_run/plan.json" "step-01" 1 | paste -sd, -)"
if [[ "$retry_repair_claim" != "1" ]]; then
  fail "expected cooled repair retry ticket to be claimable, got '$retry_repair_claim'"
fi
if ! jq -e '.steps[0].batching.batches[] | select(.index == 1 and .status == "leased" and .ticket_kind == "repair")' "$go_wide_retry_repair_run/plan.json" >/dev/null; then
  fail "expected cooled retry ticket to preserve repair ticket_kind after leasing"
fi
go_wide_stale_ticket_run="$TEMP_STATE_DIR/go-wide-stale-ticket-run"
mkdir -p "$go_wide_stale_ticket_run"
cat >"$go_wide_stale_ticket_run/plan.json" <<'GO_WIDE_STALE_TICKET_PLAN_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 2,
        "batches": [
          {"index": 1, "status": "running", "updated_at": "2000-01-01T00:00:00Z"},
          {"index": 2, "status": "completed"}
        ]
      }
    }
  ]
}
GO_WIDE_STALE_TICKET_PLAN_JSON
stale_ticket_claim="$(ONLYMACS_GO_WIDE_TICKET_STALE_SECONDS=1 orchestrated_claim_go_wide_batch_tickets "$go_wide_stale_ticket_run/plan.json" "step-01" 1 | paste -sd, -)"
if [[ "$stale_ticket_claim" != "1" ]]; then
  fail "expected go-wide ticket board to reclaim stale running tickets, got '$stale_ticket_claim'"
fi
go_wide_triaged_ticket_run="$TEMP_STATE_DIR/go-wide-triaged-ticket-run"
mkdir -p "$go_wide_triaged_ticket_run"
cat >"$go_wide_triaged_ticket_run/plan.json" <<'GO_WIDE_TRIAGED_TICKET_PLAN_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 3,
        "batches": [
          {"index": 1, "status": "churn", "updated_at": "2000-01-01T00:00:00Z"},
          {"index": 2, "status": "needs_local_salvage", "updated_at": "2000-01-01T00:00:00Z"},
          {"index": 3, "status": "pending"}
        ]
      }
    }
  ]
}
GO_WIDE_TRIAGED_TICKET_PLAN_JSON
triaged_ticket_claim="$(ONLYMACS_GO_WIDE_TICKET_STALE_SECONDS=1 orchestrated_claim_go_wide_batch_tickets "$go_wide_triaged_ticket_run/plan.json" "step-01" 3 | paste -sd, -)"
if [[ "$triaged_ticket_claim" != "3" ]]; then
  fail "expected go-wide ticket board to leave churn/local-salvage tickets parked instead of cycling them, got '$triaged_ticket_claim'"
fi
parked_requeue_run="$TEMP_STATE_DIR/go-wide-parked-requeue-run"
mkdir -p "$parked_requeue_run"
cat >"$parked_requeue_run/plan.json" <<'GO_WIDE_PARKED_REQUEUE_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 4,
        "batches": [
          {"index": 1, "status": "churn", "message": "schema miss"},
          {"index": 2, "status": "needs_local_salvage", "message": "tail repair miss"},
          {"index": 3, "status": "failed_validation", "go_wide_requeue_count": 3},
          {"index": 4, "status": "completed"}
        ]
      }
    }
  ]
}
GO_WIDE_PARKED_REQUEUE_JSON
parked_requeue_claim="$(ONLYMACS_SOURCE_CARD_QUALITY_MODE=throughput ONLYMACS_GO_WIDE_PARKED_REQUEUE_SECONDS=0 orchestrated_requeue_go_wide_parked_tickets "$parked_requeue_run/plan.json" "step-01" 3 1 4 | paste -sd, -)"
if [[ "$parked_requeue_claim" != "1,2" ]]; then
  fail "expected go-wide parked-tail requeue to revive bounded repair tickets below target, got '$parked_requeue_claim'"
fi
if ! jq -e '[.steps[0].batching.batches[] | select((.index == 1 or .index == 2) and .status == "repair_queued" and .ticket_kind == "repair" and .go_wide_requeue_count == 1 and .retry_after_epoch == null)] | length == 2' "$parked_requeue_run/plan.json" >/dev/null; then
  fail "expected parked go-wide tickets to re-enter the board as repair tickets with a requeue counter"
fi
if jq -e '.steps[0].batching.batches[] | select(.index == 3 and .status == "repair_queued")' "$parked_requeue_run/plan.json" >/dev/null; then
  fail "expected parked go-wide tickets at the requeue limit to stay parked"
fi
almost_valid_json="$TEMP_STATE_DIR/almost-valid-source-card.json"
cat >"$almost_valid_json" <<'ALMOST_VALID_JSON'
[
  {"id":"es-bue-card-01-001","setId":"es-bue-card-01","teachingOrder":1,"lemma":"subte","display":"subte","english":"subway","pos":"noun","stage":"recognition","register":"neutral","topic":"transport","topicTags":["transport","city"],"cityTags":["buenos-aires"],"grammarNote":"Common noun","dialectNote":"Use in Buenos Aires","example": ¿Dónde está el &aacute;rea de <target>subte</target>?,"example_en":"Where is the subway area?","usage":["Use <target>subte</target> for Buenos Aires metro.']}
]
ALMOST_VALID_JSON
repair_json_artifact_if_possible "$almost_valid_json" "cards-source source-card lean source schema"
if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-}" != "repaired" ]] || ! jq -e '.[0].example == "¿Dónde está el área de <target>subte</target>?" and .[0].usage[0] == "Use <target>subte</target> for Buenos Aires metro."' "$almost_valid_json" >/dev/null; then
  fail "expected almost-valid source-card JSON repair to quote unquoted fields, fix stray single-quote closers, and decode common entities"
fi
ONLYMACS_PLAN_FILE_CONTENT=$'1. Greetings\n2. Transport'
source_shell="$(orchestrated_source_card_batch_starter_json "Output: cards-source.json. Create source-card lean source schema. Exactly 20 items per set." "cards-source.json" 6 10 5)"
unset ONLYMACS_PLAN_FILE_CONTENT
if ! jq -e 'length == 5 and .[0].id == "es-bue-card-01-006" and .[0].setId == "es-bue-card-01" and .[0].teachingOrder == 6 and (.[0] | keys_unsorted) == ["id","setId","teachingOrder","lemma","display","english","pos","stage","register","topic","topicTags","cityTags","grammarNote","dialectNote","example","example_en","usage"]' <<<"$source_shell" >/dev/null; then
  fail "expected source-card starter shell to prefill deterministic ids, set IDs, teaching order, and exact schema keys"
fi
go_wide_model_score_run="$TEMP_STATE_DIR/go-wide-model-score-run"
mkdir -p "$go_wide_model_score_run"
cat >"$go_wide_model_score_run/plan.json" <<'GO_WIDE_MODEL_SCORE_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batches": [
          {"index": 1, "status": "repair_queued", "model": "qwen2.5-coder:32b"},
          {"index": 2, "status": "completed", "model": "codestral:22b"}
        ]
      }
    }
  ]
}
GO_WIDE_MODEL_SCORE_JSON
ONLYMACS_CURRENT_RETURN_DIR="$go_wide_model_score_run"
ranked_source_models="$(orchestrated_go_wide_worker_model_candidates_json "source-card lean source schema" "cards-source.json" "generate")"
unset ONLYMACS_CURRENT_RETURN_DIR
if [[ "$(jq -r 'index("codestral:22b") < index("qwen2.5-coder:32b")' <<<"$ranked_source_models")" != "true" ]]; then
  fail "expected go-wide model score routing to push recently malformed source-card models behind cleaner candidates"
fi
lease_fence_run="$TEMP_STATE_DIR/go-wide-lease-fence-run"
mkdir -p "$lease_fence_run"
cat >"$lease_fence_run/plan.json" <<'GO_WIDE_LEASE_FENCE_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 1,
        "batches": [
          {"index": 1, "status": "leased", "lease_id": "lease-current"}
        ]
      }
    }
  ]
}
GO_WIDE_LEASE_FENCE_JSON
ONLYMACS_CURRENT_RETURN_DIR="$lease_fence_run"
ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX=1
ONLYMACS_GO_WIDE_WORKER_LEASE_ID="lease-stale"
orchestrated_update_json_batch_status "step-01" 1 1 "completed" "$lease_fence_run/batch.json" "provider-stale" "Stale" "model-stale" "stale completion"
unset ONLYMACS_GO_WIDE_WORKER_BATCH_INDEX ONLYMACS_GO_WIDE_WORKER_LEASE_ID ONLYMACS_CURRENT_RETURN_DIR
if ! jq -e '.steps[0].batching.batches[0].status == "leased" and .steps[0].batching.batches[0].provider_id == null' "$lease_fence_run/plan.json" >/dev/null; then
  fail "expected stale go-wide worker lease to be unable to update a superseded ticket"
fi
accepted_artifact_run="$TEMP_STATE_DIR/go-wide-accepted-artifact-run"
mkdir -p "$accepted_artifact_run"
cat >"$accepted_artifact_run/plan.json" <<'GO_WIDE_ACCEPTED_ARTIFACT_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batch_count": 1,
        "batches": [
          {"index": 1, "status": "completed"}
        ]
      }
    }
  ]
}
GO_WIDE_ACCEPTED_ARTIFACT_JSON
printf '[{"id":"original"}]\n' >"$accepted_artifact_run/batch.json"
printf '[{"id":"stale"}]\n' >"$accepted_artifact_run/new-batch.json"
ONLYMACS_CURRENT_RETURN_DIR="$accepted_artifact_run"
orchestrated_promote_json_batch_artifact "$accepted_artifact_run/new-batch.json" "$accepted_artifact_run/batch.json" "step-01" 1 "completed"
unset ONLYMACS_CURRENT_RETURN_DIR
if ! jq -e '.[0].id == "original"' "$accepted_artifact_run/batch.json" >/dev/null || ! jq -e '.[0].id == "original"' "$accepted_artifact_run/batch.json.accepted" >/dev/null; then
  fail "expected immutable accepted batch promotion to preserve the first accepted artifact and snapshot it"
fi
metrics_run="$TEMP_STATE_DIR/go-wide-metrics-run"
mkdir -p "$metrics_run"
cat >"$metrics_run/plan.json" <<'GO_WIDE_METRICS_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "ticket_board": {},
        "batches": []
      }
    }
  ]
}
GO_WIDE_METRICS_JSON
orchestrated_record_go_wide_lane_metric "$metrics_run/plan.json" "step-01" "provider-charles" "qwen3.6:35b-a3b-q8_0" 7 "success"
orchestrated_record_go_wide_idle_metric "$metrics_run/plan.json" "step-01" "provider_capacity_wait" 5 4 2
orchestrated_mark_go_wide_finalizer "$metrics_run/plan.json" "step-01" "started"
if ! jq -e '.steps[0].batching.ticket_board.metrics.worker_seconds == 7 and .steps[0].batching.ticket_board.metrics.provider_seconds["provider-charles"] == 7 and .steps[0].batching.ticket_board.metrics.idle_lane_seconds == 10 and .steps[0].batching.ticket_board.finalizer_state == "started"' "$metrics_run/plan.json" >/dev/null; then
  fail "expected go-wide metrics and finalizer state to persist under the ticket board"
fi
go_wide_failed_provider_plan="$TEMP_STATE_DIR/go-wide-failed-provider-plan.json"
cat >"$go_wide_failed_provider_plan" <<'GO_WIDE_FAILED_PROVIDER_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batches": [
          {"index": 1, "status": "completed", "provider_id": "provider-ok"},
          {"index": 2, "status": "partial", "provider_id": "provider-failed"}
        ]
      }
    }
  ]
}
GO_WIDE_FAILED_PROVIDER_JSON
if [[ "$(orchestrated_resume_failed_provider_id "$go_wide_failed_provider_plan")" != "provider-failed" ]]; then
  fail "expected go-wide resume to identify the provider from the failed batch checkpoint"
fi
go_wide_validation_failed_provider_plan="$TEMP_STATE_DIR/go-wide-validation-failed-provider-plan.json"
cat >"$go_wide_validation_failed_provider_plan" <<'GO_WIDE_VALIDATION_FAILED_PROVIDER_JSON'
{
  "steps": [
    {
      "id": "step-01",
      "batching": {
        "batches": [
          {
            "index": 2,
            "status": "churn",
            "provider_id": "provider-schema",
            "message": "JSON batch 99/200 did not validate after bounded repair attempts: source-card entries must follow the lean source schema exactly"
          }
        ]
      }
    }
  ]
}
GO_WIDE_VALIDATION_FAILED_PROVIDER_JSON
if [[ -n "$(orchestrated_resume_failed_provider_id "$go_wide_validation_failed_provider_plan")" ]]; then
  fail "expected go-wide resume to keep providers eligible after content validation failures"
fi
ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=0
ONLYMACS_ORCHESTRATION_PROVIDER_ID=""
ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="[]"
ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="[]"
orchestrated_exclude_provider "$(orchestrated_resume_failed_provider_id "$go_wide_failed_provider_plan")"
orchestrated_set_chat_route_env 256 "swarm" "qwen2.5-coder:32b"
go_wide_exclude_payload="$(build_chat_payload "qwen2.5-coder:32b" "Return OK." "swarm" "wide")"
orchestrated_clear_chat_route_env
if ! jq -e '.exclude_provider_ids == ["provider-failed"] and .avoid_provider_ids == ["provider-failed"]' <<<"$go_wide_exclude_payload" >/dev/null; then
  fail "expected go-wide failed-provider reroute to hard-exclude the failed provider from the next payload"
fi
original_fetch_admin_status_definition="$(declare -f onlymacs_fetch_admin_status)"
GO_WIDE_STATUS_FIXTURE='{
  "identity": {"provider_id": "provider-failed"},
  "members": [
    {
      "member_id": "member-local",
      "capabilities": [
        {
          "provider_id": "provider-failed",
          "status": "available",
          "slots": {"free": 1, "total": 1},
          "models": [{"id": "qwen3.6:35b-a3b-q4_K_M", "slots_free": 1}]
        }
      ]
    }
  ]
}'
onlymacs_fetch_admin_status() {
  printf '%s' "$GO_WIDE_STATUS_FIXTURE"
}
ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE="qwen3.6:35b-a3b-q4_K_M"
ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="[]"
ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="[]"
orchestrated_apply_go_wide_resume_provider_avoidance "$go_wide_failed_provider_plan" "wide" "swarm"
if ! onlymacs_json_contains_string "$ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON" "provider-failed"; then
  fail "expected single-provider go-wide resume to keep a failed provider as an avoided fallback"
fi
if onlymacs_json_contains_string "$ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON" "provider-failed"; then
  fail "expected single-provider go-wide resume not to hard-exclude the only visible provider"
fi
GO_WIDE_STATUS_FIXTURE='{
  "identity": {"provider_id": "provider-local"},
  "members": [
    {
      "member_id": "member-local",
      "capabilities": [
        {
          "provider_id": "provider-failed",
          "status": "available",
          "slots": {"free": 1, "total": 1},
          "models": [{"id": "qwen3.6:35b-a3b-q4_K_M", "slots_free": 1}]
        },
        {
          "provider_id": "provider-charles",
          "status": "available",
          "slots": {"free": 1, "total": 1},
          "models": [{"id": "qwen3.6:35b-a3b-q4_K_M", "slots_free": 1}]
        }
      ]
    }
  ]
}'
ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON="[]"
ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON="[]"
orchestrated_apply_go_wide_resume_provider_avoidance "$go_wide_failed_provider_plan" "wide" "swarm"
if ! onlymacs_json_contains_string "$ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON" "provider-failed"; then
  fail "expected multi-provider go-wide resume to hard-exclude the failed provider when an alternate is visible"
fi
ONLYMACS_GO_WIDE_JOB_BOARD_WORKER=1
ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=0
ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON='["provider-failed","provider-charles"]'
ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON='["provider-failed","provider-charles"]'
orchestrated_set_chat_route_env 5000 "swarm" "qwen3.6:35b-a3b-q4_K_M"
go_wide_sanitized_payload="$(build_chat_payload "qwen3.6:35b-a3b-q4_K_M" "ONLYMACS_ARTIFACT_BEGIN" "swarm" "wide")"
orchestrated_clear_chat_route_env
unset ONLYMACS_GO_WIDE_JOB_BOARD_WORKER ONLYMACS_GO_WIDE_ROUTE_LISTS_SANITIZED
if jq -e '.exclude_provider_ids? | length > 0' <<<"$go_wide_sanitized_payload" >/dev/null; then
  fail "expected go-wide worker route guard to clear hard excludes when every visible provider would be excluded"
fi
if ! jq -e '.avoid_provider_ids == ["provider-failed","provider-charles"]' <<<"$go_wide_sanitized_payload" >/dev/null; then
  fail "expected go-wide worker route guard to keep soft avoids after clearing all-provider hard excludes"
fi
eval "$original_fetch_admin_status_definition"
unset GO_WIDE_STATUS_FIXTURE ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE
go_wide_plan_path="$TEMP_STATE_DIR/go-wide-route-plan.md"
cat >"$go_wide_plan_path" <<'PLAN'
# Go Wide Route Plan

## Step 1 - Generate
Output: cards.json

Use Charles's remote Mac for primary generation.

## Step 2 - Review
Output: review.json

Run local validation and duplicate detection.
PLAN
ONLYMACS_PLAN_FILE_PATH="$go_wide_plan_path"
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$go_wide_plan_path"
ONLYMACS_PLAN_FILE_CONTENT="$(cat "$go_wide_plan_path")"
if [[ "$(orchestrated_route_alias_for_step wide 1 cards.json)" != "wide" ]]; then
  fail "expected go-wide route resolver to override stale remote-only generation hints"
fi
if [[ "$(orchestrated_route_alias_for_step wide 2 review.json)" != "local-first" ]]; then
  fail "expected go-wide route resolver to keep validation and review local"
fi
unset ONLYMACS_PLAN_FILE_PATH ONLYMACS_RESOLVED_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT
ONLYMACS_GO_WIDE_MODE=0
parse_leading_options --trusted-only "review this repo" || fail "expected --trusted-only to parse"
if [[ "${ONLYMACS_FORCE_PRESET:-}" != "trusted-only" ]]; then
  fail "expected --trusted-only to force trusted route"
fi

if [[ "$(prompt_exact_count_requirement "Use exactly 30 common Vietnamese words and include three modes.")" != "30" ]]; then
  fail "expected exact-count parser to tolerate adjectives before the counted noun"
fi
if [[ -n "$(prompt_exact_count_requirement "Report exact saved file paths." || true)" ]]; then
  fail "expected exact-count parser to ignore exact saved file path language"
fi
large_timeout_policy="$(onlymacs_timeout_policy_json "qwen3.6:35b-a3b-q8_0" "Create exactly 100 JSON entries." "items.json")"
if [[ "$(jq -r '.class' <<<"$large_timeout_policy")" != "large_or_cold_model" || "$(jq -r '.first_progress_timeout_seconds' <<<"$large_timeout_policy")" -lt 420 || "$(jq -r '.idle_timeout_seconds' <<<"$large_timeout_policy")" -lt 600 ]]; then
  fail "expected q8/large models to get a longer adaptive timeout policy"
fi
coder_timeout_policy="$(onlymacs_timeout_policy_json "qwen2.5-coder:32b" "" "")"
if [[ "$(jq -r '.class' <<<"$coder_timeout_policy")" != "large_or_cold_model" || "$(jq -r '.first_progress_timeout_seconds' <<<"$coder_timeout_policy")" -lt 420 ]]; then
  fail "expected qwen2.5-coder:32b to get the large/cold adaptive timeout policy"
fi
if [[ "$(onlymacs_classify_failure "remote stream timed out waiting for the first output token after 420s" "" "first_progress_timeout")" != "first_token_timeout" ]]; then
  fail "expected first-progress timeout classification"
fi
if [[ "$(onlymacs_classify_failure "remote stream spent 600s producing reasoning but no artifact output" "" "reasoning_only_timeout")" != "reasoning_only_timeout" ]]; then
  fail "expected reasoning-only timeout classification"
fi
if [[ "$(chat_progress_phase 0 running 128)" != "reasoning_only" || "$(chat_progress_phase_label reasoning_only 0.0)" != "reasoning before artifact" ]]; then
  fail "expected reasoning-only progress phase before artifact content starts"
fi
ONLYMACS_ORCHESTRATION_PROVIDER_ID="provider-charles"
ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=1
ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON='["provider-charles"]'
ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON='["provider-charles"]'
orchestrated_set_chat_route_env 100 swarm "qwen3.6:35b-a3b-q4_K_M"
pinned_payload="$(build_chat_payload "qwen3.6:35b-a3b-q4_K_M" "test pinned route" "swarm" "qwen3.6:35b-a3b-q4_K_M")"
if [[ "$(jq -r '.route_provider_id // empty' <<<"$pinned_payload")" != "provider-charles" ]]; then
  fail "expected locked route to keep route_provider_id"
fi
if jq -e '.avoid_provider_ids // [] | index("provider-charles") != null' <<<"$pinned_payload" >/dev/null; then
  fail "expected locked route to strip pinned provider from avoid list"
fi
if jq -e '.exclude_provider_ids // [] | index("provider-charles") != null' <<<"$pinned_payload" >/dev/null; then
  fail "expected locked route to strip pinned provider from exclude list"
fi
orchestrated_clear_chat_route_env
ONLYMACS_GO_WIDE_MODE=1
ONLYMACS_ORCHESTRATION_PROVIDER_ID="provider-charles"
ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=0
orchestrated_set_chat_route_env 100 swarm "qwen2.5-coder:32b"
wide_payload="$(build_chat_payload "qwen2.5-coder:32b" "test wide route" "swarm" "wide")"
if [[ "$(jq -r '.route_provider_id // empty' <<<"$wide_payload")" == "provider-charles" ]]; then
  fail "expected go-wide unlocked route to drop stale provider affinity"
fi
wide_artifact_payload="$(build_chat_payload "gemma4:31b" "ONLYMACS_ARTIFACT_BEGIN filename=cards-source-1000.batch-01.json\n[]\nONLYMACS_ARTIFACT_END" "swarm" "wide")"
if ! jq -e '.think == false and .reasoning_effort == "low"' <<<"$wide_artifact_payload" >/dev/null; then
  fail "expected artifact payloads to disable thinking/reasoning before remote execution"
fi
qwen_artifact_payload="$(build_chat_payload "qwen2.5-coder:32b" "ONLYMACS_ARTIFACT_BEGIN filename=cards-source-1000.batch-01.json\n[]\nONLYMACS_ARTIFACT_END" "swarm" "wide")"
if jq -e 'has("think") or has("reasoning_effort")' <<<"$qwen_artifact_payload" >/dev/null; then
  fail "expected non-thinking qwen2.5 artifact payloads to omit thinking controls for Ollama compatibility"
fi
orchestrated_clear_chat_route_env
ONLYMACS_GO_WIDE_MODE=0
ONLYMACS_ORCHESTRATION_PROVIDER_ID="provider-charles"
ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED=1
ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON='[]'
orchestrated_avoid_provider "provider-charles"
if onlymacs_json_contains_string "$ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON" "provider-charles"; then
  fail "expected locked provider not to be avoided"
fi
orchestrated_avoid_provider "provider-kevin"
if ! onlymacs_json_contains_string "$ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON" "provider-kevin"; then
  fail "expected unlocked provider to be avoidable"
fi
unset ONLYMACS_ORCHESTRATION_PROVIDER_ID ONLYMACS_ORCHESTRATION_PROVIDER_ROUTE_LOCKED ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON
if [[ "$(onlymacs_classify_failure "local bridge unavailable; waiting for the OnlyMacs bridge to recover" "" "")" != "bridge_unavailable" ]]; then
  fail "expected bridge failure classification"
fi
if orchestrated_stream_failure_should_wait_for_bridge "first_progress_timeout" ""; then
  fail "expected first-token timeout not to wait for bridge recovery"
fi
if ! orchestrated_stream_failure_should_wait_for_bridge "transport_error" ""; then
  fail "expected empty-status transport error to wait for bridge recovery"
fi
if orchestrated_stream_failure_should_wait_for_bridge "transport_error" "502"; then
  fail "expected HTTP transport error not to wait for bridge recovery"
fi
if [[ "$(onlymacs_classify_failure "downloading model qwen while provider is busy" "" "")" != "provider_maintenance" ]]; then
  fail "expected installing/downloading model classification"
fi
ONLYMACS_LAST_CHAT_FAILURE_KIND="detached_activity_running"
if [[ "$(orchestrated_failure_status_for_last_chat)" != "queued" ]]; then
  fail "expected still-running detached relay activity to become queued/resumable"
fi
unset ONLYMACS_LAST_CHAT_FAILURE_KIND
ONLYMACS_LAST_CHAT_HTTP_STATUS="502"
if ! orchestrated_last_chat_is_transient_transport; then
  fail "expected HTTP 502 to be classified as transient transport"
fi
if [[ "$(orchestrated_failure_status_for_last_chat)" != "queued" ]]; then
  fail "expected transient HTTP 502 with no partial output to become queued/resumable"
fi
unset ONLYMACS_LAST_CHAT_HTTP_STATUS
ONLYMACS_LAST_CHAT_HTTP_STATUS="504"
ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT=1
if [[ "$(orchestrated_failure_status_for_last_chat)" != "partial" ]]; then
  fail "expected transient HTTP 504 with partial output to preserve partial status"
fi
unset ONLYMACS_LAST_CHAT_HTTP_STATUS ONLYMACS_LAST_CHAT_PARTIAL_OUTPUT
empty_chat_path="$(mktemp "$TEMP_STATE_DIR/empty-chat-XXXXXX")"
: >"$empty_chat_path"
if chat_failure_safe_for_stream_retry "$empty_chat_path" "409"; then
  fail "expected direct chat to avoid replay retries after remote capacity conflicts"
fi
if ! chat_failure_safe_for_stream_retry "$empty_chat_path" "502"; then
  fail "expected direct chat to allow one safe replay retry after transient relay failures"
fi
capacity_failure_message="$(direct_chat_failure_message "remote-first" "swarm" "409" "remote capacity unavailable (HTTP 409)")"
if [[ "$capacity_failure_message" != *"no eligible remote Mac is currently available"* ]]; then
  fail "expected direct chat capacity failures to explain unavailable remote Macs"
fi
capacity_next_step="$(direct_chat_failure_next_step "remote-first" "swarm" "409")"
if [[ "$capacity_next_step" != *"local-first"* ]]; then
  fail "expected direct chat capacity next step to mention local-first fallback"
fi
relay_failure_message="$(direct_chat_failure_message "remote-first" "swarm" "502" "coordinator or remote relay returned HTTP 502")"
if [[ "$relay_failure_message" != *"transient coordinator or provider handoff issue"* ]]; then
  fail "expected direct chat 5xx failures to be framed as transient relay failures"
fi
empty_success_message="$(direct_chat_failure_message "local-first" "local" "200" "the stream ended without generated answer text")"
if [[ "$empty_success_message" != *"completed but did not return usable output"* ]]; then
  fail "expected direct chat empty successful streams to explain missing output"
fi
failure_headers_path="$(mktemp "$TEMP_STATE_DIR/failure-headers-XXXXXX")"
cat >"$failure_headers_path" <<'HEADERS'
HTTP/1.1 409 Conflict
Content-Type: application/json
HEADERS
ONLYMACS_CURRENT_RETURN_DIR="$TEMP_STATE_DIR/direct-failure-run"
ONLYMACS_CURRENT_RETURN_STARTED_AT="2026-04-30T00:00:00Z"
ONLYMACS_LAST_CHAT_HTTP_STATUS="409"
ONLYMACS_LAST_CHAT_FAILURE_KIND="http_409"
ONLYMACS_LAST_CHAT_FAILURE_MESSAGE="remote capacity unavailable (HTTP 409)"
write_chat_failure_artifact "$empty_chat_path" "$failure_headers_path" "remote-first" "test prompt" "swarm" "$capacity_failure_message" "$capacity_next_step"
if ! jq -e '.status == "failed" and .failure.http_status == "409" and (.failure.message | contains("no eligible remote Mac")) and (.next_step | contains("local-first"))' "$ONLYMACS_CURRENT_RETURN_DIR/status.json" >/dev/null; then
  fail "expected direct chat failure artifacts to persist friendly failure metadata"
fi
unset ONLYMACS_CURRENT_RETURN_DIR ONLYMACS_CURRENT_RETURN_STARTED_AT ONLYMACS_LAST_CHAT_HTTP_STATUS ONLYMACS_LAST_CHAT_FAILURE_KIND ONLYMACS_LAST_CHAT_FAILURE_MESSAGE
if ! (
  export ONLYMACS_RETURNS_DIR="$TEMP_STATE_DIR/empty-success-runs"
  export ONLYMACS_JSON_MODE=0
  stream_chat_payload_capture() {
    local _payload="$1"
    local content="$2"
    local headers="$3"
    : >"$content"
    cat >"$headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-empty
X-OnlyMacs-Resolved-Model: qwen3.6:35b-a3b-q4_K_M
X-OnlyMacs-Provider-ID: provider-kevin
X-OnlyMacs-Provider-Name: Kevin
X-OnlyMacs-Owner-Member-Name: Kevin
X-OnlyMacs-Route-Scope: local
HEADERS
    return 0
  }
  if run_chat_with_context_loop "qwen3.6:35b-a3b-q4_K_M" "local-first" "return an empty response" "local" >/dev/null 2>/dev/null; then
    exit 1
  fi
  jq -e '.status == "failed" and .failure.http_status == "200" and .failure.kind == "empty_output" and (.failure.message | contains("did not return usable output")) and (.next_step | contains("larger max token"))' "$ONLYMACS_CURRENT_RETURN_DIR/status.json" >/dev/null
); then
  fail "expected direct chat successful empty streams to fail instead of leaving a running inbox"
fi
if [[ "$(orchestrated_progress_detail_for_status queued)" == *"remote capacity"* ]]; then
  fail "expected queued detail to avoid capacity-only wording"
fi
buenos_count_prompt=$'Total required: exactly 1000 items.\nUse exactly 50 set IDs with exactly 20 items per set.'
if [[ "$(prompt_exact_count_requirement "$buenos_count_prompt")" != "1000" ]]; then
  fail "expected exact-count parser to prefer the total count over per-set counts"
fi

assert_intent "do a code review on my project" \
  "chat trusted-only" \
  "chat" "trusted-only" "do a code review on my project"

assert_intent "review this private auth flow and secret rotation plan" \
  "chat local-first" \
  "chat" "local-first" "review this private auth flow and secret rotation plan"

assert_intent "what is my latest swarm doing" \
  "status latest" \
  "status" "latest"

assert_intent "pause the current swarm" \
  "pause current" \
  "pause" "current"

assert_intent "split this refactor into parallel workstreams" \
  "plan wide" \
  "plan" "wide" "split this refactor into parallel workstreams"

assert_intent "use both my computer and as many other computers as possible for this audit" \
  "go wide" \
  "go" "wide" "use both my computer and as many other computers as possible for this audit"

assert_intent "go wide across the swarm and execute this migration review" \
  "go wide" \
  "go" "wide" "go wide across the swarm and execute this migration review"

assert_intent "use the exact qwen2.5-coder:32b model for this audit" \
  "chat exact-model qwen2.5-coder:32b" \
  "chat" "qwen2.5-coder:32b" "use the exact qwen2.5-coder:32b model for this audit"

assert_intent "use my Macs first to save tokens on this analysis" \
  "chat offload-max" \
  "chat" "offload-max" "use my Macs first to save tokens on this analysis"

assert_intent "use other computers first for this review" \
  "chat remote-first" \
  "chat" "remote-first" "use other computers first for this review"

assert_intent "keep this on my Macs only for now" \
  "chat trusted-only" \
  "chat" "trusted-only" "keep this on my Macs only for now"

assert_intent "use the swarm for this review if that is the best available route" \
  "chat best-available (swarm allowed)" \
  "chat" "use the swarm for this review if that is the best available route"

assert_intent "check my setup" \
  "check" \
  "check"

assert_intent_with_reason "how do I use this?" \
  "help" \
  "OnlyMacs recognized this as a usage/help question and opened the built-in command guide instead of sending it into the swarm." \
  "help"

assert_intent_with_reason "what can I do with OnlyMacs?" \
  "help" \
  "OnlyMacs recognized this as a usage/help question and opened the built-in command guide instead of sending it into the swarm." \
  "help"

assert_intent_with_reason "show me examples" \
  "help" \
  "OnlyMacs recognized this as a usage/help question and opened the built-in command guide instead of sending it into the swarm." \
  "help"

assert_intent_with_reason "what are the commands" \
  "help" \
  "OnlyMacs recognized this as a usage/help question and opened the built-in command guide instead of sending it into the swarm." \
  "help"

assert_intent "write a python script for a basic cebu alphabet flash card app" \
  "chat best-available (artifact inbox)" \
  "chat" "write a python script for a basic cebu alphabet flash card app"

save_workspace_default_preset "trusted-only"

assert_intent "review this repo for concurrency issues" \
  "chat trusted-only" \
  "chat" "trusted-only" "review this repo for concurrency issues"

payload="$(build_swarm_payload "local-first" 1 "review this private auth flow" "elastic" "")"
if [[ "$(jq -r '.route_scope' <<<"$payload")" != "local_only" ]]; then
  fail "expected local-first payload to use local_only route scope"
fi

payload="$(build_swarm_payload "offload-max" 1 "debug this without burning paid tokens" "elastic" "")"
if [[ "$(jq -r '.route_scope' <<<"$payload")" != "trusted_only" ]]; then
  fail "expected offload-max payload to use trusted_only route scope"
fi
if [[ "$(jq -r '.model' <<<"$payload")" != "" ]]; then
  fail "expected offload-max payload to avoid pinning an exact model"
fi

payload="$(build_swarm_payload "remote-first" 1 "force this onto another Mac" "elastic" "")"
if [[ "$(jq -r '.route_scope' <<<"$payload")" != "swarm" ]]; then
  fail "expected remote-first payload to keep swarm route scope"
fi
if [[ "$(jq -r '.prefer_remote // false' <<<"$payload")" != "true" ]]; then
  fail "expected remote-first payload to exclude This Mac"
fi
if [[ "$(jq -r '.prefer_remote_soft // false' <<<"$payload")" != "false" ]]; then
  fail "expected remote-first payload not to use the soft remote preference flag"
fi
if [[ "$(jq -r '.model' <<<"$payload")" != "" ]]; then
  fail "expected remote-first payload to avoid pinning an exact model"
fi

payload="$(build_swarm_payload "coder" 1 "review this patch" "elastic" "")"
if [[ "$(jq -r '.prefer_remote // false' <<<"$payload")" != "false" ]]; then
  fail "expected default swarm payload not to hard-exclude This Mac"
fi
if [[ "$(jq -r '.prefer_remote_soft // false' <<<"$payload")" != "true" ]]; then
  fail "expected default swarm payload to prefer other Macs softly"
fi

payload="$(build_chat_payload "" "review this patch" "swarm" "")"
if [[ "$(jq -r '.prefer_remote_soft // false' <<<"$payload")" != "true" ]]; then
  fail "expected plain chat payload to prefer other Macs softly"
fi

payload="$(build_swarm_payload "balanced" 1 "estimate this migration" "elastic" "")"
if [[ "$(jq -r '.model // ""' <<<"$payload")" != "" ]]; then
  fail "expected balanced preset payload to avoid pinning an exact model"
fi
if [[ "$(jq -r '.prefer_remote_soft // false' <<<"$payload")" != "true" ]]; then
  fail "expected balanced preset payload to prefer other Macs softly"
fi

payload="$(build_swarm_payload "wide" 4 "split this migration" "elastic" "")"
if [[ "$(jq -r '.model // ""' <<<"$payload")" != "" ]]; then
  fail "expected wide preset payload to avoid pinning an exact model"
fi
if [[ "$(jq -r '.strategy // ""' <<<"$payload")" != "go_wide" ]]; then
  fail "expected wide preset payload to declare go_wide strategy"
fi

payload="$(build_swarm_payload "quick" 1 "answer quickly" "elastic" "")"
if [[ "$(jq -r '.model // ""' <<<"$payload")" != "${ONLYMACS_FAST_MODEL:-gemma4:26b}" ]]; then
  fail "expected quick preset payload to resolve to the fast model"
fi

payload="$(build_chat_payload "" "review this private auth flow" "local_only" "local-first")"
if [[ "$(jq -r '.prefer_remote_soft // false' <<<"$payload")" != "false" ]]; then
  fail "expected local-first chat payload not to prefer other Macs softly"
fi

if [[ -n "$(resolve_model_for_preflight_or_chat "remote-first")" ]]; then
  fail "expected remote-first preflight model resolution to stay dynamic"
fi

parse_chat_request "review this private auth flow without leaving this Mac"
if [[ "${ONLYMACS_CHAT_MODEL_ALIAS:-}" != "" ]]; then
  fail "expected prompt-only chat request to keep an empty model alias"
fi
if [[ "${ONLYMACS_CHAT_PROMPT:-}" != "review this private auth flow without leaving this Mac" ]]; then
  fail "expected prompt-only chat request to preserve the full prompt"
fi

parse_chat_request "trusted-only" "keep this on my Macs only"
if [[ "${ONLYMACS_CHAT_MODEL_ALIAS:-}" != "trusted-only" ]]; then
  fail "expected trusted-only chat request to keep the route alias"
fi
if [[ "${ONLYMACS_CHAT_PROMPT:-}" != "keep this on my Macs only" ]]; then
  fail "expected trusted-only chat request to preserve the prompt"
fi

parse_chat_request "remote-first" "force this onto another Mac"
if [[ "${ONLYMACS_CHAT_MODEL_ALIAS:-}" != "remote-first" ]]; then
  fail "expected remote-first chat request to keep the route alias"
fi
if [[ "${ONLYMACS_CHAT_PROMPT:-}" != "force this onto another Mac" ]]; then
  fail "expected remote-first chat request to preserve the prompt"
fi

warning_output="$(emit_launch_advisories "coder" "summarize these files for me")"
if [[ "$warning_output" != *"lightweight"* ]]; then
  fail "expected lightweight advisory for trivial premium request"
fi

warning_output="$(emit_launch_advisories "coder" "review this api key leak and secret rotation plan")"
if [[ "$warning_output" != *"looks sensitive"* ]]; then
  fail "expected sensitive advisory for secret-bearing request"
fi

warning_output="$(emit_launch_advisories "trusted-only" "review this api key leak and secret rotation plan")"
if [[ "$warning_output" == *"looks sensitive"* ]]; then
  fail "did not expect a sensitive advisory for trusted-only routing"
fi

if ! prompt_looks_file_bound "review my code in this repo and rearrange this json file"; then
  fail "expected repo/json prompt to be treated as file-bound"
fi

if ! prompt_looks_file_bound "review the pipeline docs in this project and tell me what is unclear"; then
  fail "expected project pipeline docs prompt to be treated as file-bound"
fi

if prompt_looks_file_bound "brainstorm a tagline for this feature"; then
  fail "did not expect simple brainstorming prompt to be treated as file-bound"
fi

if prompt_looks_file_bound "Self-contained prompt-only content pipeline request. Use only the facts inside this message and create Step 2 content for groups 01-05."; then
  fail "did not expect explicit prompt-only content pipeline generation to require local files"
fi

if prompt_requests_artifact_mode "Self-contained prompt-only content pipeline request. Use only the facts inside this message and create Step 2 content for groups 01-05."; then
  fail "did not expect self-contained prompt-only wording alone to force artifact mode"
fi

if prompt_looks_file_bound "Create one JSON artifact file named cards-source-model-benchmark.json. Return only a strict JSON array inside artifact markers."; then
  fail "did not expect generated JSON artifact wording to require local file approval"
fi

content_pack_prompt="Self-contained prompt-only request. Generate actual Step 2 content pack output for learn-spanish-buenos-aires groups 01-05 with vocab.json, sentences.json, and lessons.json batches."
if ! prompt_requests_extended_mode "$content_pack_prompt"; then
  fail "expected content-pack generation to enter extended mode"
fi

large_prompt="Create a full end-to-end pipeline document with step 1 through step 4, checkpoints, validation, resume instructions, and final handoff notes."
if ! prompt_needs_plan_mode "$large_prompt"; then
  fail "expected large multi-step prompt to require a plan"
fi
if ! prompt_requests_extended_mode "$large_prompt"; then
  fail "expected large unplanned prompt to auto-enter extended mode"
fi

parse_leading_options "--simple" "chat" "remote-first" "$large_prompt" || fail "expected --simple to parse"
if prompt_requests_extended_mode "$large_prompt"; then
  fail "expected --simple to prevent automatic extended planning"
fi
if parse_leading_options "--simple" "--plan:work.md" "chat" "remote-first" "execute"; then
  fail "expected --simple and --plan to conflict"
fi
ONLYMACS_SIMPLE_MODE=0
ONLYMACS_EXECUTION_MODE="auto"
unset ONLYMACS_PLAN_FILE_PATH ONLYMACS_PLAN_COMPILED_PROMPT ONLYMACS_RESOLVED_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT ONLYMACS_PLAN_FILE_STEP_COUNT ONLYMACS_PLAN_USER_PROMPT

old_content_batch_size="${ONLYMACS_CONTENT_BATCH_SIZE:-}"
ONLYMACS_CONTENT_BATCH_SIZE=2
if [[ "$(orchestrated_step_count "$content_pack_prompt")" != "10" ]]; then
  fail "expected groups 01-05 content pack to plan manifest plus 9 module batch steps"
fi
if [[ "$(orchestrated_expected_filename "$content_pack_prompt" 2 10)" != "vocab-groups-01-02.json" ]]; then
  fail "expected first content-pack batch to save vocab groups 01-02"
fi
if [[ "$(orchestrated_expected_filename "$content_pack_prompt" 10 10)" != "lessons-groups-05-05.json" ]]; then
  fail "expected final content-pack batch to save lessons group 05"
fi
if [[ -n "$old_content_batch_size" ]]; then
  ONLYMACS_CONTENT_BATCH_SIZE="$old_content_batch_size"
else
  unset ONLYMACS_CONTENT_BATCH_SIZE
fi

plan_file="$TEMP_STATE_DIR/content-pipeline.md"
cat >"$plan_file" <<'PLAN_MD'
# OnlyMacs Plan

## Step 1 - Manifest
Output: content-pack-manifest.json

Create the manifest and list the exact validation rules.

## Step 2 - First Batch
Output: vocab-groups-01-02.json

Create the first vocabulary batch only.
PLAN_MD

if ! parse_leading_options "--plan:$plan_file" "chat" "remote-first" "execute this plan"; then
  fail "expected --plan:file to parse"
fi
if [[ "${ONLYMACS_PLAN_FILE_PATH:-}" != "$plan_file" ]]; then
  fail "expected --plan:file to preserve the plan path"
fi
if [[ "${ONLYMACS_EXECUTION_MODE:-}" != "extended" ]]; then
  fail "expected --plan:file to imply extended mode"
fi
compile_prompt_with_plan_file "execute this plan" || fail "expected plan file to compile into a prompt"
if [[ "${ONLYMACS_PLAN_FILE_STEP_COUNT:-}" != "2" ]]; then
  fail "expected markdown step headings to define a two-step plan"
fi
if [[ "${ONLYMACS_PLAN_COMPILED_PROMPT:-}" != *"Self-contained prompt-only OnlyMacs plan-file job"* ]]; then
  fail "expected compiled plan prompt to mark the job prompt-only"
fi
if [[ "$(orchestrated_step_count "$ONLYMACS_PLAN_COMPILED_PROMPT")" != "2" ]]; then
  fail "expected orchestrated plan-file job to use the detected step count"
fi
if [[ "$(orchestrated_expected_filename "$ONLYMACS_PLAN_COMPILED_PROMPT" 1 2)" != "content-pack-manifest.json" ]]; then
  fail "expected step 1 filename to come from the plan file"
fi
if [[ "$(orchestrated_expected_filename "$ONLYMACS_PLAN_COMPILED_PROMPT" 2 2)" != "vocab-groups-01-02.json" ]]; then
  fail "expected step 2 filename to come from the plan file"
fi
go_wide_plan_capture="$TEMP_STATE_DIR/go-wide-plan-capture.txt"
(
  set_activity_context() { :; }
  record_current_activity() { :; }
  resolve_prompt_with_file_access() {
    ONLYMACS_RESOLVED_PROMPT="${2:-}"
    return 0
  }
  confirm_chat_launch() { return 0; }
  run_start() {
    printf 'go\n%s\n%s\n' "${1:-}" "${3:-}" >"$go_wide_plan_capture"
    return 0
  }
  run_orchestrated_chat() {
    printf 'chat\n%s\n%s\n' "${2:-}" "${4:-}" >"$go_wide_plan_capture"
    return 0
  }
  onlymacs_cli_main "OnlyMacs" "onlymacs" --yes --extended --go-wide "--plan:$plan_file" "execute this plan" >/dev/null
) || fail "expected --go-wide --extended --plan to dispatch cleanly"
if [[ "$(sed -n '1p' "$go_wide_plan_capture")" != "chat" || "$(sed -n '2p' "$go_wide_plan_capture")" != "wide" ]]; then
  fail "expected --go-wide plan-file requests to dispatch to extended chat wide instead of generic go wide"
fi
step_prompt="$(orchestrated_compile_step_prompt "$ONLYMACS_PLAN_COMPILED_PROMPT" 2 2 "vocab-groups-01-02.json")"
if [[ "$step_prompt" != *"Complete step 2 of 2"* || "$step_prompt" != *"Create the first vocabulary batch only."* ]]; then
  fail "expected plan-file step prompt to scope the remote worker to the current step"
fi
if [[ "$step_prompt" != *"Do not invent OnlyMacs member names"* || "$step_prompt" != *"see OnlyMacs run metadata"* ]]; then
  fail "expected plan-file step prompts to prevent invented provider/model provenance"
fi
ONLYMACS_PLAN_FILE_CONTENT=$'# OnlyMacs Go-Wide Plan\n\n## Step 1 - Primary Generation\nRouting: primary generation on Charles 128 GB M4 Max remote Mac\nOutput: sentences.json\n\nTotal required: exactly 1000 items. Use exactly 50 set IDs with exactly 20 items per set.\n\n## Step 2 - Local Validation\nRouting: strongest available local 64 GB Mac for validation and duplicate detection\nOutput: validation-report.json\n\nValidate the generated artifact.'
ONLYMACS_PLAN_FILE_STEP_COUNT="2"
ONLYMACS_PLAN_FILE_PATH="$TEMP_STATE_DIR/go-wide-routing-plan.md"
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$ONLYMACS_PLAN_FILE_PATH"
printf '%s' "$ONLYMACS_PLAN_FILE_CONTENT" >"$ONLYMACS_PLAN_FILE_PATH"
if [[ "$(orchestrated_route_alias_for_step "wide" 1 "sentences.json")" != "wide" ]]; then
  fail "expected go-wide plan primary generation to keep the swarm-wide generation lane"
fi
if [[ "$(orchestrated_route_alias_for_step "wide" 2 "validation-report.json")" != "local-first" ]]; then
  fail "expected go-wide plan validation to route local-first"
fi
if [[ "$(orchestrated_json_batch_size_for_step "$(plan_file_step_text 1)" "sentences.json")" != "5" ]]; then
  fail "expected large nested exact-count JSON plan steps to use small resumable batches"
fi
if [[ "$(prompt_items_per_set_requirement "$(plan_file_step_text 1)")" != "20" ]]; then
  fail "expected items-per-set parser to detect plan set sizing"
fi
range_hint="$(orchestrated_json_batch_range_hint "$(plan_file_step_text 1)" 11 20)"
if [[ "$range_hint" != *"set index 01"* || "$range_hint" != *"11-20"* || "$range_hint" != *"Continue at item 011 exactly"* ]]; then
  fail "expected internal JSON batch prompts to spell out the current set/item range"
fi
ba_source_step=$'## Step 1: Generate 1,000 Source Cards\n\nOutput: cards-source-1000.json\n\nGenerate exactly 50 sets with exactly 20 items per set.\n\n## Set Map\n\n1. Greetings, farewells, and polite openers\n2. People, names, origin, and identity\n3. Voseo pronouns and core verbs\n4. Courtesy, apology, clarification, and repetition\n\nValidation for this step:\n- Return exactly 1000 cards total.\n- Items per set: exactly 20.\n- Every card must have a unique normalized `lemma` plus `display` combination across the artifact.\n- Use Rioplatense Buenos Aires Spanish.'
if ! prompt_requires_unique_item_terms "$ba_source_step"; then
  fail "expected strict source-card mode to enforce unique terms"
fi
if ONLYMACS_SOURCE_CARD_QUALITY_MODE=throughput prompt_requires_unique_item_terms "$ba_source_step"; then
  fail "expected throughput source-card mode to skip duplicate-term gating"
fi
diversity_guidance="$(orchestrated_json_batch_diversity_guidance "$ba_source_step" "cards-source-1000.json" 56 60 "hablás, ver")"
if [[ "$diversity_guidance" != *"set 03"* || "$diversity_guidance" != *"aprendés/aprender"* || "$diversity_guidance" != *"hard surface-form exclusion"* || "$diversity_guidance" != *"Uniqueness preflight"* || "$diversity_guidance" != *"lemma must be the infinitive/base form"* ]]; then
  fail "expected dense Buenos Aires JSON batches to include positive replacement inventory and surface exclusion guidance"
fi
saved_plan_content="${ONLYMACS_PLAN_FILE_CONTENT-}"
saved_plan_file_path="${ONLYMACS_PLAN_FILE_PATH-}"
saved_resolved_plan_file_path="${ONLYMACS_RESOLVED_PLAN_FILE_PATH-}"
saved_plan_file_step_count="${ONLYMACS_PLAN_FILE_STEP_COUNT-}"
ONLYMACS_PLAN_FILE_CONTENT=$'# OnlyMacs Plan: Buenos Aires 1,000 Source Cards\n\n## Step 1: Generate 1,000 Source Cards\n\nOutput: cards-source-1000.json\n\nGenerate exactly 50 sets with exactly 20 items per set.\n\n## Set Map\n\n1. Greetings, farewells, and polite openers\n2. People, names, origin, and identity\n3. Voseo pronouns and core verbs\n4. Courtesy, apology, clarification, and repetition\n\nValidation for this step:\n- Return exactly 1000 cards total.\n- Items per set: exactly 20.\n- Every card must have a unique normalized `lemma` plus `display` combination across the artifact.\n- Use Rioplatense Buenos Aires Spanish.'
ONLYMACS_PLAN_FILE_PATH="$TEMP_STATE_DIR/ba-source-plan.md"
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$ONLYMACS_PLAN_FILE_PATH"
ONLYMACS_PLAN_FILE_STEP_COUNT=1
compiled_ba_batch_prompt="$(orchestrated_compile_plan_file_json_batch_prompt "execute BA source cards" 1 1 "cards-source-1000.json" 12 200 56 60 5 "cards-source-1000.batch-12.json" "hablás, ver")"
if [[ "$compiled_ba_batch_prompt" != *"Accepted surface hard exclusions: hablás, ver"* || "$compiled_ba_batch_prompt" != *"Exact duplicate guard: never emit any accepted exclusion"* || "$compiled_ba_batch_prompt" != *"Current set/topic: set 03 is \"Voseo pronouns and core verbs\""* || "$compiled_ba_batch_prompt" != *"Use this positive term inventory"* || "$compiled_ba_batch_prompt" != *"display should be the voseo surface form"* ]]; then
  fail "expected compiled JSON batch prompt to include banned prior surfaces and positive inventory guidance"
fi
wrong_topic_batch="$TEMP_STATE_DIR/wrong-topic-batch.json"
cat >"$wrong_topic_batch" <<'WRONG_TOPIC_BATCH_JSON'
[
  {"id":"es-bue-card-04-001","setId":"es-bue-card-04","teachingOrder":1,"lemma":"calle","display":"calle","english":"street","pos":"noun","stage":"beginner","register":"neutral","topic":"directions","topicTags":["directions","navigation"],"cityTags":["urban"],"grammarNote":"Noun.","dialectNote":"neutral in Buenos Aires","example":"La calle está llena.","example_en":"The street is full.","usage":["Usá <target>calle</target> para hablar de una calle.","Sirve en mapas.","Es femenino."]}
]
WRONG_TOPIC_BATCH_JSON
orchestrated_validate_json_batch_set_topic "$wrong_topic_batch" "$ONLYMACS_PLAN_FILE_CONTENT" 61
if [[ "${ONLYMACS_JSON_BATCH_TOPIC_STATUS:-passed}" != "failed" || "${ONLYMACS_JSON_BATCH_TOPIC_MESSAGE:-}" != *"set 04 should cover Courtesy, apology, clarification, and repetition"* ]]; then
  fail "expected set-topic validation to reject structurally valid items assigned to the wrong plan topic"
fi
right_topic_batch="$TEMP_STATE_DIR/right-topic-batch.json"
cat >"$right_topic_batch" <<'RIGHT_TOPIC_BATCH_JSON'
[
  {"id":"es-bue-card-04-001","setId":"es-bue-card-04","teachingOrder":1,"lemma":"perdón","display":"perdón","english":"sorry","pos":"expression","stage":"beginner","register":"polite-informal","topic":"Courtesy and apology","topicTags":["courtesy","apology"],"cityTags":["diario"],"grammarNote":"Expression.","dialectNote":"neutral in Buenos Aires","example":"Perdón, no te escuché.","example_en":"Sorry, I didn't hear you.","usage":["Usá <target>perdón</target> para disculparte.","Sirve al interrumpir.","Suena amable."]}
]
RIGHT_TOPIC_BATCH_JSON
orchestrated_validate_json_batch_set_topic "$right_topic_batch" "$ONLYMACS_PLAN_FILE_CONTENT" 61
if [[ "${ONLYMACS_JSON_BATCH_TOPIC_STATUS:-passed}" == "failed" ]]; then
  fail "expected set-topic validation to accept items whose topic overlaps the plan set map"
fi
ONLYMACS_PLAN_FILE_CONTENT=$'# OnlyMacs Plan: Buenos Aires 1,000 Source Cards\n\n## Step 1: Generate 1,000 Source Cards\n\nOutput: cards-source-1000.json\n\nGenerate exactly 50 sets with exactly 20 items per set.\n\n## Set Map\n\n50. Review: mixed Buenos Aires daily life\n\nValidation for this step:\n- Return exactly 1000 cards total.\n- Items per set: exactly 20.\n- Every card must have a unique normalized `lemma` plus `display` combination across the artifact.\n- Use Rioplatense Buenos Aires Spanish.'
review_topic_batch="$TEMP_STATE_DIR/review-topic-batch.json"
cat >"$review_topic_batch" <<'REVIEW_TOPIC_BATCH_JSON'
[
  {"id":"es-bue-card-50-001","setId":"es-bue-card-50","teachingOrder":1,"lemma":"convenir","display":"¿Cuándo te viene bien?","english":"when works for you","pos":"phrase","stage":"review","register":"polite-informal","topic":"scheduling meetings","topicTags":["time","meeting"],"cityTags":["social"],"grammarNote":"Review expression.","dialectNote":"neutral in Buenos Aires","example":"La reunión puede ser a las diez, ¿cuándo te viene bien?","example_en":"The meeting can be at ten, when works for you?","usage":["Usá <target>¿Cuándo te viene bien?</target> para coordinar.","Sirve para planes sociales.","Es útil en mensajes."]}
]
REVIEW_TOPIC_BATCH_JSON
orchestrated_validate_json_batch_set_topic "$review_topic_batch" "$ONLYMACS_PLAN_FILE_CONTENT" 981
if [[ "${ONLYMACS_JSON_BATCH_TOPIC_STATUS:-passed}" == "failed" ]]; then
  fail "expected broad review source-card sets to skip brittle topic token-overlap validation"
fi
ONLYMACS_PLAN_FILE_CONTENT="$saved_plan_content"
ONLYMACS_PLAN_FILE_PATH="$saved_plan_file_path"
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$saved_resolved_plan_file_path"
ONLYMACS_PLAN_FILE_STEP_COUNT="$saved_plan_file_step_count"
wrong_range_batch="$TEMP_STATE_DIR/wrong-range-batch.json"
cat >"$wrong_range_batch" <<'WRONG_RANGE_JSON'
[
  {"id":"es-bue-sent-06-011","setId":"es-bue-sent-06","teachingOrder":11},
  {"id":"es-bue-sent-06-012","setId":"es-bue-sent-06","teachingOrder":12}
]
WRONG_RANGE_JSON
orchestrated_validate_json_batch_item_range "$wrong_range_batch" "$(plan_file_step_text 1)" 11
if [[ "${ONLYMACS_JSON_BATCH_RANGE_STATUS:-passed}" != "failed" || "${ONLYMACS_JSON_BATCH_RANGE_MESSAGE:-}" != *"expected set index 1"* ]]; then
  fail "expected JSON batch range validation to reject wrong plan set IDs"
fi
restarted_range_batch="$TEMP_STATE_DIR/restarted-range-batch.json"
cat >"$restarted_range_batch" <<'RESTARTED_RANGE_JSON'
[
  {"id":"es-bue-sent-02-001","setId":"es-bue-sent-02","text":"repeat one","teachingOrder":1},
  {"id":"es-bue-sent-02-002","setId":"es-bue-sent-02","text":"repeat two","teachingOrder":2}
]
RESTARTED_RANGE_JSON
orchestrated_validate_json_batch_item_range "$restarted_range_batch" "$(plan_file_step_text 1)" 31
if [[ "${ONLYMACS_JSON_BATCH_RANGE_STATUS:-passed}" != "failed" || "${ONLYMACS_JSON_BATCH_RANGE_MESSAGE:-}" != *"expected 11"* ]]; then
  fail "expected JSON batch range validation to reject a set restart when the micro-batch should continue"
fi
if ! orchestrated_alias_is_wide "go-wide" || ! orchestrated_alias_is_wide "wide" || orchestrated_alias_is_wide "remote-first"; then
  fail "expected go-wide aliases to be identifiable without treating remote-first as wide"
fi
shadow_review_prompt="$(orchestrated_compile_local_shadow_json_batch_review_prompt "execute this plan" 1 2 "sentences.json" 4 100 31 40 10 "sentences.batch-04.json" "$restarted_range_batch" "$(plan_file_step_text 1)")"
if [[ "$shadow_review_prompt" != *"local OnlyMacs requester-side reviewer"* || "$shadow_review_prompt" != *"expected item numbers: 31-40"* || "$shadow_review_prompt" != *"future/past/imperative-looking lemma"* || "$shadow_review_prompt" != *"ONLYMACS_ARTIFACT_BEGIN filename=sentences.batch-04.local-review.json"* ]]; then
  fail "expected go-wide local shadow review prompt to include the range and machine artifact contract"
fi
(
  counter_file="$TEMP_STATE_DIR/local-shadow-review-model-counter"
  event_file="$TEMP_STATE_DIR/local-shadow-review-wait-events.jsonl"
  printf '0' >"$counter_file"
  orchestrated_model_for_step() {
    local count
    count="$(cat "$counter_file")"
    count=$((count + 1))
    printf '%s' "$count" >"$counter_file"
    if [[ "$count" -lt 2 ]]; then
      return 1
    fi
    printf 'qwen2.5-coder:32b'
  }
  sleep() { :; }
  onlymacs_log_run_event() {
    printf '%s\n' "$1" >>"$event_file"
  }
  ONLYMACS_GO_WIDE_LOCAL_REVIEW_MODEL_WAIT_SECONDS=5
  ONLYMACS_GO_WIDE_LOCAL_REVIEW_MODEL_WAIT_INTERVAL_SECONDS=5
  picked_shadow_model="$(orchestrated_pick_local_shadow_review_model "sentences.batch-04.local-review.json" "step-01" 4 100 "$restarted_range_batch" "$TEMP_STATE_DIR/review-raw.md")"
  if [[ "$picked_shadow_model" != "qwen2.5-coder:32b" || "$(cat "$counter_file")" != "2" ]]; then
    fail "expected go-wide local shadow review to wait for a busy local slot instead of skipping"
  fi
  if [[ "$(cat "$event_file")" != *"local_shadow_review_waiting"* ]]; then
    fail "expected waiting local shadow reviews to log backlog visibility"
  fi
)
(
  orchestrated_model_for_step() { return 1; }
  sleep() { :; }
  onlymacs_log_run_event() { :; }
  ONLYMACS_GO_WIDE_LOCAL_REVIEW_MODEL_WAIT_SECONDS=0
  if orchestrated_pick_local_shadow_review_model "sentences.batch-04.local-review.json" "step-01" 4 100 "$restarted_range_batch" "$TEMP_STATE_DIR/review-raw.md" >/dev/null; then
    fail "expected go-wide local shadow review model selection to honor zero wait limits"
  fi
)
(
  unset ONLYMACS_CAPACITY_RETRY_LIMIT ONLYMACS_CAPACITY_RETRY_INTERVAL ONLYMACS_EXECUTION_MODE ONLYMACS_GO_WIDE_MODE ONLYMACS_GO_WIDE_JOB_BOARD_WORKER
  if [[ "$(orchestrated_capacity_retry_limit)" != "30" || "$(orchestrated_capacity_retry_interval)" != "10" ]]; then
    fail "expected normal capacity waits to keep the standard retry defaults"
  fi
  ONLYMACS_GO_WIDE_MODE=1
  if [[ "$(orchestrated_capacity_retry_limit)" != "3" || "$(orchestrated_capacity_retry_interval)" != "3" ]]; then
    fail "expected go-wide parent capacity waits to recycle quickly"
  fi
  ONLYMACS_GO_WIDE_JOB_BOARD_WORKER=1
  if [[ "$(orchestrated_capacity_retry_limit)" != "2" || "$(orchestrated_capacity_retry_interval)" != "3" ]]; then
    fail "expected go-wide ticket workers to avoid long busy-wait capacity loops"
  fi
  ONLYMACS_CAPACITY_RETRY_LIMIT=9
  ONLYMACS_CAPACITY_RETRY_INTERVAL=4
  if [[ "$(orchestrated_capacity_retry_limit)" != "9" || "$(orchestrated_capacity_retry_interval)" != "4" ]]; then
    fail "expected explicit capacity retry env overrides to win"
  fi
  unset ONLYMACS_CAPACITY_RETRY_LIMIT ONLYMACS_CAPACITY_RETRY_INTERVAL ONLYMACS_EXECUTION_MODE ONLYMACS_GO_WIDE_MODE ONLYMACS_GO_WIDE_JOB_BOARD_WORKER
)
(
  curl() {
    if [[ "${*: -1}" == */admin/v1/status ]]; then
      cat <<'STATUS_JSON'
{
  "identity": {"member_id": "member-local", "provider_id": "provider-kevin"},
  "members": [
    {
      "member_id": "member-remote",
      "capabilities": [{
        "status": "available",
        "slots": {"free": 1, "total": 1},
        "best_model": "qwen3.6:35b-a3b-q8_0",
        "models": [{"id": "qwen3.6:35b-a3b-q8_0"}, {"id": "qwen3.6:35b-a3b-q4_K_M"}]
      }]
    },
    {
      "member_id": "member-local",
      "capabilities": [{
        "status": "available",
        "slots": {"free": 1, "total": 1},
        "best_model": "qwen3.6:35b-a3b-q4_K_M",
        "models": [{"id": "qwen3.6:35b-a3b-q4_K_M"}, {"id": "gemma4:31b"}, {"id": "qwen2.5-coder:32b"}]
      }]
    }
  ]
}
STATUS_JSON
      return 0
    fi
    command curl "$@"
  }
  review_model="$(orchestrated_model_for_step "" "local-first" "local_only" "Validate the accepted JSON artifact, duplicate risks, range contract, and quality warnings." "sentences.batch-04.local-review.json")"
  if [[ "$review_model" != "qwen2.5-coder:32b" ]]; then
    fail "expected go-wide local shadow review to pick a fast non-thinking local review model, got '$review_model'"
  fi
  ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE="gpt-oss:120b"
  review_model_with_remote_override="$(orchestrated_model_for_step "" "local-first" "local_only" "Validate the accepted JSON artifact, duplicate risks, range contract, and quality warnings." "sentences.batch-04.local-review.json")"
  unset ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE
  if [[ "$review_model_with_remote_override" != "qwen2.5-coder:32b" ]]; then
    fail "expected local shadow review to ignore unavailable remote-only overrides, got '$review_model_with_remote_override'"
  fi
  ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT=1
  fallback_model="$(orchestrated_model_for_step "qwen3.6:35b-a3b-q8_0" "qwen3.6:35b-a3b-q8_0" "swarm" "Generate source-card content." "cards-source-1000.batch-01.json")"
  unset ONLYMACS_ORCHESTRATION_PREFER_LOWER_QUANT
  if [[ "$fallback_model" != "qwen3.6:35b-a3b-q4_K_M" ]]; then
    fail "expected explicit q8 plan to allow lower-quant fallback after a stall, got '$fallback_model'"
  fi
  wide_source_model="$(orchestrated_model_for_step "" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json")"
  if [[ "$wide_source_model" != "qwen2.5-coder:32b" ]]; then
    fail "expected go-wide source-card JSON to prefer an artifact-stable content model before reasoning-heavy candidates, got '$wide_source_model'"
  fi
  wide_source_model_with_default="$(orchestrated_model_for_step "qwen3.6:35b-a3b-q4_K_M" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json")"
  if [[ "$wide_source_model_with_default" != "qwen2.5-coder:32b" ]]; then
    fail "expected go-wide source-card JSON to override a normalized default thinking model with an artifact-stable content model, got '$wide_source_model_with_default'"
  fi
  status_timeout_model="$(
    curl() {
      return 28
    }
    orchestrated_model_for_step "" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json"
  )"
  if [[ "$status_timeout_model" != "gemma3:27b" ]]; then
    fail "expected go-wide source-card JSON to use a deterministic non-empty model when status lookup times out, got '$status_timeout_model'"
  fi
  ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE="qwen2.5-coder:32b"
  override_model="$(orchestrated_model_for_step "qwen3.6:35b-a3b-q8_0" "qwen3.6:35b-a3b-q8_0" "swarm" "Generate source-card content." "cards-source-1000.batch-01.json")"
  unset ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE
  if [[ "$override_model" != "qwen2.5-coder:32b" ]]; then
    fail "expected explicit orchestration model override to win during resumed runs, got '$override_model'"
  fi
)
(
  curl() {
    if [[ "${*: -1}" == */admin/v1/status ]]; then
      cat <<'STATUS_JSON'
{
  "identity": {"member_id": "member-local", "provider_id": "provider-kevin"},
  "members": [
    {
      "member_id": "member-remote",
      "capabilities": [{
        "status": "busy",
        "slots": {"free": 0, "total": 1},
        "best_model": "qwen3.6:35b-a3b-q8_0",
        "models": [{"id": "qwen3.6:35b-a3b-q8_0"}]
      }]
    },
    {
      "member_id": "member-local",
      "capabilities": [{
        "status": "available",
        "slots": {"free": 1, "total": 1},
        "best_model": "qwen3.6:35b-a3b-q4_K_M",
        "models": [{"id": "qwen3.6:35b-a3b-q4_K_M"}, {"id": "gemma4:31b"}, {"id": "qwen2.5-coder:32b"}]
      }]
    }
  ]
}
STATUS_JSON
      return 0
    fi
    command curl "$@"
  }
  wide_free_slot_model="$(orchestrated_model_for_step "" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json")"
  if [[ "$wide_free_slot_model" != "qwen2.5-coder:32b" ]]; then
    fail "expected go-wide model choice to skip busy thinking-model capacity and use an artifact-stable content model, got '$wide_free_slot_model'"
  fi
  ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE="gpt-oss:120b"
  wide_override_fallback_model="$(orchestrated_model_for_step "" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json")"
  unset ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE
  if [[ "$wide_override_fallback_model" != "qwen2.5-coder:32b" ]]; then
    fail "expected go-wide unavailable override to fall back to an artifact-stable content model, got '$wide_override_fallback_model'"
  fi
  ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE="gpt-oss:120b"
  ONLYMACS_ORCHESTRATION_STRICT_MODEL_OVERRIDE=1
  wide_strict_override_model="$(orchestrated_model_for_step "" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json")"
  unset ONLYMACS_ORCHESTRATION_MODEL_OVERRIDE
  unset ONLYMACS_ORCHESTRATION_STRICT_MODEL_OVERRIDE
if [[ "$wide_strict_override_model" != "gpt-oss:120b" ]]; then
  fail "expected strict go-wide model override to avoid silent fallback while waiting for capacity, got '$wide_strict_override_model'"
fi
)
(
  curl() {
    if [[ "${*: -1}" == */admin/v1/status ]]; then
      cat <<'STATUS_JSON'
{
  "identity": {"member_id": "member-local", "provider_id": "provider-kevin"},
  "members": [
    {
        "member_id": "member-charles",
        "member_name": "Charles",
      "capabilities": [{
        "provider_id": "provider-charles",
        "status": "available",
        "slots": {"free": 2, "total": 2},
        "hardware": {"memory_gb": 128},
        "models": [{"id": "gemma3:27b"}, {"id": "qwen2.5-coder:32b"}]
      }]
    },
    {
      "member_id": "member-kevin",
      "member_name": "Kevin",
      "capabilities": [{
        "provider_id": "provider-kevin",
        "status": "available",
        "slots": {"free": 1, "total": 1},
        "models": [{"id": "gemma4:31b"}, {"id": "gemma4:26b"}, {"id": "qwen2.5-coder:32b"}]
      }]
    }
  ]
}
STATUS_JSON
      return 0
    fi
    command curl "$@"
  }
  worker_routes="$(orchestrated_pick_go_wide_worker_routes "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json" 8)"
  expected_routes=$'provider-charles\tgemma3:27b\tCharles\t0\t2\nprovider-charles\tgemma3:27b\tCharles\t0\t2\nprovider-kevin\tqwen2.5-coder:32b\tKevin\t1\t1'
  if [[ "$worker_routes" != "$expected_routes" ]]; then
    fail "expected go-wide to assign provider-specific artifact models and respect advertised free slots without forcing one model across Macs, got '$worker_routes'"
  fi
  worker_repair_routes="$(orchestrated_pick_go_wide_worker_routes "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json" 8 "repair")"
  expected_repair_routes=$'provider-charles\tqwen2.5-coder:32b\tCharles\t0\t2\nprovider-charles\tqwen2.5-coder:32b\tCharles\t0\t2\nprovider-kevin\tqwen2.5-coder:32b\tKevin\t1\t1'
  if [[ "$worker_repair_routes" != "$expected_repair_routes" ]]; then
    fail "expected go-wide repair tickets to use repair-oriented provider-specific model order, got '$worker_repair_routes'"
  fi
  worker_routes_skip_local="$(ONLYMACS_GO_WIDE_SKIP_LOCAL_PROVIDERS=1 orchestrated_pick_go_wide_worker_routes "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json" 8)"
  expected_skip_local_routes=$'provider-charles\tgemma3:27b\tCharles\t0\t2\nprovider-charles\tgemma3:27b\tCharles\t0\t2'
  if [[ "$worker_routes_skip_local" != "$expected_skip_local_routes" ]]; then
    fail "expected go-wide skip-local provider gate to keep only remote workers eligible, got '$worker_routes_skip_local'"
  fi
  worker_routes_override="$(ONLYMACS_GO_WIDE_MODEL_CANDIDATES="gemma4:31b,qwen2.5-coder:32b" orchestrated_pick_go_wide_worker_routes "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json" 8)"
  expected_override_routes=$'provider-charles\tqwen2.5-coder:32b\tCharles\t0\t2\nprovider-charles\tqwen2.5-coder:32b\tCharles\t0\t2\nprovider-kevin\tgemma4:31b\tKevin\t1\t1'
  if [[ "$worker_routes_override" != "$expected_override_routes" ]]; then
    fail "expected go-wide model candidate override to stay per-provider instead of hard-pinning one shared model, got '$worker_routes_override'"
  fi
  ONLYMACS_GO_WIDE_MODE=1
  ONLYMACS_GO_WIDE_JOB_BOARD_WORKER=1
  ONLYMACS_GO_WIDE_WORKER_MODEL="gemma3:27b"
  worker_model="$(orchestrated_model_for_step "" "wide" "swarm" "Generate Buenos Aires source-card content." "cards-source-1000.batch-01.json")"
  if [[ "$worker_model" != "gemma3:27b" ]]; then
    fail "expected go-wide worker-specific model to win over generic swarm model selection, got '$worker_model'"
  fi
  ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID="provider-charles"
  ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON='["provider-charles","provider-kevin"]'
  ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON='["provider-charles","provider-kevin"]'
  orchestrated_set_chat_route_env 5000 "swarm" "gemma3:27b"
  routed_payload="$(build_chat_payload "gemma3:27b" "ONLYMACS_ARTIFACT_BEGIN" "swarm" "wide")"
  orchestrated_clear_chat_route_env
  unset ONLYMACS_GO_WIDE_MODE ONLYMACS_GO_WIDE_JOB_BOARD_WORKER ONLYMACS_GO_WIDE_WORKER_MODEL ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID
  unset ONLYMACS_ORCHESTRATION_AVOID_PROVIDER_IDS_JSON ONLYMACS_ORCHESTRATION_EXCLUDE_PROVIDER_IDS_JSON
  if ! jq -e '.route_provider_id == "provider-charles" and (.exclude_provider_ids | index("provider-charles") | not) and (.avoid_provider_ids | index("provider-charles") | not)' <<<"$routed_payload" >/dev/null; then
    fail "expected go-wide worker provider pin to keep its assigned Mac eligible, got '$routed_payload'"
  fi
  ONLYMACS_GO_WIDE_MODE=1
  ONLYMACS_GO_WIDE_JOB_BOARD_WORKER=1
  ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID="provider-kevin"
  ONLYMACS_GO_WIDE_WORKER_PROVIDER_IS_LOCAL=1
  orchestrated_set_chat_route_env 5000 "swarm" "qwen2.5-coder:32b"
  local_routed_payload="$(build_chat_payload "qwen2.5-coder:32b" "ONLYMACS_ARTIFACT_BEGIN" "swarm" "wide")"
  orchestrated_clear_chat_route_env
  unset ONLYMACS_GO_WIDE_MODE ONLYMACS_GO_WIDE_JOB_BOARD_WORKER ONLYMACS_GO_WIDE_WORKER_PROVIDER_ID ONLYMACS_GO_WIDE_WORKER_PROVIDER_IS_LOCAL
  if ! jq -e '.route_provider_id == "provider-kevin" and .prefer_remote == false and .prefer_remote_soft == false' <<<"$local_routed_payload" >/dev/null; then
    fail "expected go-wide local provider pin to keep This Mac eligible instead of forcing remote-first, got '$local_routed_payload'"
  fi
)
complex_lesson_prompt="Create exactly 2 lesson items. Each lesson must include at least 4 contentBlocks and 8 quiz questions."
if orchestrated_should_batch_plan_json_step "$complex_lesson_prompt" "lessons-groups-01-02.json"; then
  fail "expected very small lesson steps to stay as one artifact unless small-lesson batching is forced"
fi
ONLYMACS_FORCE_SMALL_LESSON_BATCHING=1
if ! orchestrated_should_batch_plan_json_step "$complex_lesson_prompt" "lessons-groups-01-02.json"; then
  fail "expected small complex lesson batching to be available when explicitly forced"
fi
unset ONLYMACS_FORCE_SMALL_LESSON_BATCHING
if [[ "$(orchestrated_json_batch_size_for_step "$complex_lesson_prompt" "lessons-groups-01-02.json")" != "1" ]]; then
  fail "expected complex nested JSON plan steps to default to one top-level item per batch"
fi
overfull_batch="$TEMP_STATE_DIR/overfull-batch.json"
printf '[{"id":"one"},{"id":"two"}]\n' >"$overfull_batch"
orchestrated_normalize_chunk_artifact "$overfull_batch" "Return exactly 1 entries/items as a JSON array."
if [[ "$(jq -r 'length' "$overfull_batch")" != "1" || "$(jq -r '.[0].id' "$overfull_batch")" != "one" ]]; then
  fail "expected overfull JSON batches to trim to the requested batch size"
fi
placeholder_check_report="$TEMP_STATE_DIR/placeholder-check-report.md"
printf 'Schema status: pass. Placeholder check: pass. No placeholder values were found.\n' >"$placeholder_check_report"
validate_return_artifact "$placeholder_check_report" "Return a concise Markdown validation report."
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-failed}" == "failed" ]]; then
  fail "expected validation reports to mention placeholder checks without failing"
fi
previous_artifact_run_dir="$TEMP_STATE_DIR/previous-artifacts-run"
mkdir -p "$previous_artifact_run_dir/steps/step-01/files"
{
  printf '['
  for idx in $(seq 1 80); do
    [[ "$idx" -gt 1 ]] && printf ','
    printf '{"id":"item-%03d","value":"%080d"}' "$idx" "$idx"
  done
  printf ']'
} >"$previous_artifact_run_dir/steps/step-01/files/previous.json"
ONLYMACS_CURRENT_RETURN_DIR="$previous_artifact_run_dir"
ONLYMACS_PREVIOUS_ARTIFACT_BYTES=12000
previous_artifact_excerpt="$(orchestrated_previous_artifact_excerpts 2)"
unset ONLYMACS_PREVIOUS_ARTIFACT_BYTES
if [[ "$previous_artifact_excerpt" != *"item-080"* ]]; then
  fail "expected previous-artifact excerpts to include complete small artifacts for validation steps"
fi
canonical_run_dir="$TEMP_STATE_DIR/canonical-artifacts-run"
mkdir -p "$canonical_run_dir/steps/step-01/files" "$canonical_run_dir/files"
printf '{"step":true}\n' >"$canonical_run_dir/steps/step-01/files/setDefinitions.json"
printf '{"root":true}\n' >"$canonical_run_dir/files/setDefinitions.json"
cat >"$canonical_run_dir/plan.json" <<CANONICAL_PLAN_JSON
{
  "steps": [
    {
      "id": "step-01",
      "status": "completed",
      "artifact_path": "$canonical_run_dir/steps/step-01/files/setDefinitions.json"
    }
  ]
}
CANONICAL_PLAN_JSON
ONLYMACS_CURRENT_RETURN_DIR="$canonical_run_dir"
canonical_artifacts="$(orchestrated_canonical_artifacts_json "[\"$canonical_run_dir/steps/step-01/files/setDefinitions.json\"]" "$canonical_run_dir/plan.json")"
if [[ "$(jq -r 'length' <<<"$canonical_artifacts")" != "1" || "$(jq -r '.[0]' <<<"$canonical_artifacts")" != "$canonical_run_dir/files/setDefinitions.json" ]]; then
  fail "expected final handoff artifacts to prefer root inbox files over internal step files"
fi

events_run_dir="$TEMP_STATE_DIR/events-run"
mkdir -p "$events_run_dir/files"
ONLYMACS_CURRENT_RETURN_DIR="$events_run_dir"
ONLYMACS_CURRENT_RETURN_RUN_ID="events-run"
ONLYMACS_CURRENT_RETURN_STARTED_AT="2026-04-25T00:00:00Z"
ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE="swarm"
ONLYMACS_CURRENT_RETURN_MODEL_ALIAS="remote-first"
ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON="[]"
orchestrated_write_plan "private raw prompt that should not appear in events" "remote-first" "swarm" 1
if ! jq -e '.execution_settings.validator_version != null and .validator_version != null and .schema_contract.kind != null and .steps[0].schema_contract.kind != null' "$events_run_dir/plan.json" >/dev/null; then
  fail "expected plan.json to persist execution settings, validator version, and schema contract"
fi
orchestrated_update_plan_step "step-01" "waiting_for_capacity" 0 "" "" "pending" "capacity wait test" "" "" "" "running"
orchestrated_update_plan_step "step-01" "completed" 0 "$events_run_dir/files/result.md" "$events_run_dir/steps/step-01/RESULT.md" "passed" "" "provider-1" "Charles" "qwen-test" "completed"
if [[ ! -f "$events_run_dir/events.jsonl" ]]; then
  fail "expected orchestrated run events to be written"
fi
if [[ "$(jq -sr '[.[] | select(.event == "run_planned")] | length' "$events_run_dir/events.jsonl")" != "1" ]]; then
  fail "expected run_planned event"
fi
if [[ "$(jq -sr '[.[] | select(.event == "capacity_wait")] | length' "$events_run_dir/events.jsonl")" != "1" ]]; then
  fail "expected capacity_wait event"
fi
if rg -q "private raw prompt" "$events_run_dir/events.jsonl"; then
  fail "expected events log to avoid storing raw prompt text"
fi
diagnostics_output="$(run_diagnostics "$events_run_dir")"
if [[ "$diagnostics_output" != *"OnlyMacs Diagnostics"* || "$diagnostics_output" != *"1 capacity waits"* || "$diagnostics_output" != *"Status file:"* ]]; then
  fail "expected diagnostics output to summarize run events"
fi
support_bundle_output="$(run_support_bundle "$events_run_dir")"
support_bundle_path="${events_run_dir}/support-bundle.json"
if [[ "$support_bundle_output" != *"support bundle created"* || ! -f "$support_bundle_path" ]]; then
  fail "expected support-bundle command to write a redacted diagnostics bundle"
fi
if rg -q "private raw prompt" "$support_bundle_path"; then
  fail "expected support bundle to avoid raw prompt text"
fi
if ! jq -e '.plan_summary.execution_settings != null and (.events | length) > 0' "$support_bundle_path" >/dev/null; then
  fail "expected support bundle to include plan settings and diagnostic events"
fi

resume_batch_run_dir="$TEMP_STATE_DIR/resume-batch-run"
mkdir -p "$resume_batch_run_dir/steps/step-01/batches/batch-01/files" "$resume_batch_run_dir/steps/step-01/batches/batch-02/files"
ONLYMACS_CURRENT_RETURN_DIR="$resume_batch_run_dir"
ONLYMACS_CURRENT_RETURN_RUN_ID="resume-batch-run"
ONLYMACS_CURRENT_RETURN_STARTED_AT="2026-04-25T00:00:00Z"
ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE="swarm"
ONLYMACS_CURRENT_RETURN_MODEL_ALIAS="remote-first"
ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON="[]"
ONLYMACS_PLAN_FILE_PATH="$TEMP_STATE_DIR/resume-batch-plan.md"
ONLYMACS_RESOLVED_PLAN_FILE_PATH="$ONLYMACS_PLAN_FILE_PATH"
ONLYMACS_PLAN_FILE_CONTENT=$'# Resume Batch Plan\n\n## Step 1 - Lessons\nOutput: lessons-groups-01-02.json\n\nCreate exactly 2 lesson items. Each lesson must include at least 4 contentBlocks and 8 quiz questions.'
ONLYMACS_PLAN_FILE_STEP_COUNT="1"
printf '%s' "$ONLYMACS_PLAN_FILE_CONTENT" >"$ONLYMACS_PLAN_FILE_PATH"
orchestrated_write_plan "$ONLYMACS_PLAN_FILE_CONTENT" "remote-first" "swarm" 1
printf '[{"id":"lesson-1"}]\n' >"$resume_batch_run_dir/steps/step-01/batches/batch-01/files/lessons-groups-01-02.batch-01.json"
printf '[{"id":"lesson-2"}]\n' >"$resume_batch_run_dir/steps/step-01/batches/batch-02/files/lessons-groups-01-02.batch-02.json"
if ! orchestrated_execute_plan_json_batch_step "" "remote-first" "swarm" "$ONLYMACS_PLAN_FILE_CONTENT" 1 1 "lessons-groups-01-02.json" "Create exactly 2 lesson items. Each lesson must include at least 4 contentBlocks and 8 quiz questions."; then
  fail "expected existing valid JSON batches to be reused without remote streaming"
fi
if [[ "$(jq -r 'length' "$resume_batch_run_dir/files/lessons-groups-01-02.json")" != "2" ]]; then
  fail "expected reused JSON batches to assemble the final artifact"
fi
if [[ "$(jq -sr '[.[] | select(.event == "batch_reused")] | length' "$resume_batch_run_dir/events.jsonl")" != "2" ]]; then
  fail "expected batch_reused events for resumable JSON batches"
fi
if ! jq -e '.steps[0].batching.type == "json_array" and .steps[0].batching.batch_count == 2 and .progress.batch_count == 2' "$resume_batch_run_dir/plan.json" >/dev/null; then
  fail "expected resumable JSON batches to persist typed batch policy and batch progress"
fi
detached_run_dir="$TEMP_STATE_DIR/detached-run"
mkdir -p "$detached_run_dir/steps/step-01/batches/batch-01/files" "$detached_run_dir/files"
detached_artifact="$detached_run_dir/steps/step-01/batches/batch-01/files/items.batch-01.json"
cat >"$detached_run_dir/status.json" <<'DETACHED_STATUS'
{
  "status": "running",
  "session_id": "sess-detached-001",
  "progress": {
    "step_id": "step-01",
    "batch_index": 1,
    "batch_count": 1
  }
}
DETACHED_STATUS
cat >"$detached_run_dir/plan.json" <<DETACHED_PLAN
{
  "steps": [
    {
      "id": "step-01",
      "status": "running",
      "batching": {
        "batch_count": 1,
        "batches": [
          {
            "index": 1,
            "status": "running",
            "artifact_path": "$detached_artifact"
          }
        ]
      }
    }
  ],
  "progress": {
    "step_id": "step-01",
    "batch_index": 1,
    "batch_count": 1
  }
}
DETACHED_PLAN
detached_body="$(printf 'ONLYMACS_ARTIFACT_BEGIN filename=items.batch-01.json\n{"id":"one"}\nONLYMACS_ARTIFACT_END\n' | base64 | tr -d '\n')"
printf 'invalid partial batch\n' >"$detached_artifact"
(
  request_json() {
    ONLYMACS_LAST_HTTP_STATUS="200"
    ONLYMACS_LAST_HTTP_BODY="$(jq -cn --arg body "$detached_body" '{activities:[{status:"completed", provider_id:"provider-charles", provider_name:"Charles", owner_member_name:"Charles", resolved_model:"qwen-test", final_body_base64:$body}]}')"
    return 0
  }
  ONLYMACS_CURRENT_RETURN_DIR="$detached_run_dir"
  ONLYMACS_CURRENT_RETURN_RUN_ID="detached-run"
  orchestrated_recover_detached_batch_from_activity "$detached_run_dir"
) || fail "expected detached relay activity to recover the saved batch artifact"
if [[ "$(cat "$detached_artifact")" != '{"id":"one"}' ]]; then
  fail "expected detached relay recovery to extract the machine artifact body"
fi
if [[ "$(jq -r '.steps[0].batching.batches[0].status' "$detached_run_dir/plan.json")" != "recovered" ]]; then
  fail "expected detached relay recovery to update batch status"
fi
stream_recovery_content="$TEMP_STATE_DIR/stream-recovery-content.md"
stream_recovery_headers="$TEMP_STATE_DIR/stream-recovery-headers.txt"
cat >"$stream_recovery_headers" <<'STREAM_RECOVERY_HEADERS'
HTTP/1.1 200 OK
x-onlymacs-session-id: sess-detached-001

STREAM_RECOVERY_HEADERS
(
  request_json() {
    ONLYMACS_LAST_HTTP_STATUS="200"
    ONLYMACS_LAST_HTTP_BODY="$(jq -cn --arg body "$detached_body" '{activities:[{status:"completed", provider_id:"provider-charles", provider_name:"Charles", owner_member_name:"Charles", resolved_model:"qwen-test", final_body_base64:$body}]}')"
    return 0
  }
  ONLYMACS_CURRENT_RETURN_DIR="$detached_run_dir"
  ONLYMACS_CURRENT_RETURN_RUN_ID="detached-run"
  orchestrated_recover_stream_content_from_activity "$stream_recovery_content" "$stream_recovery_headers" "step-01" "0" "$detached_artifact" "$detached_run_dir/steps/step-01/batches/batch-01/RESULT.md"
) || fail "expected stream transport recovery to read completed relay activity"
if [[ "$(cat "$stream_recovery_content")" != *'"id":"one"'* ]]; then
  fail "expected stream transport recovery to restore final relay body content"
fi
stream_recovery_no_header_content="$TEMP_STATE_DIR/stream-recovery-no-header-content.md"
stream_recovery_no_header_headers="$TEMP_STATE_DIR/stream-recovery-no-header-headers.txt"
cat >"$stream_recovery_no_header_headers" <<'STREAM_RECOVERY_NO_HEADER_HEADERS'
HTTP/1.1 000

STREAM_RECOVERY_NO_HEADER_HEADERS
(
  orchestrated_recover_session_id_from_provider_activity() {
    ONLYMACS_LAST_CHAT_PROVIDER_ID="provider-charles"
    ONLYMACS_LAST_CHAT_PROVIDER_NAME="Charles"
    ONLYMACS_LAST_CHAT_OWNER_MEMBER_NAME="Charles"
    ONLYMACS_LAST_CHAT_RESOLVED_MODEL="gemma3:27b"
    printf 'sess-provider-activity-001'
  }
  request_json() {
    if [[ "${2:-}" != "/admin/v1/relay/activity?session_id=sess-provider-activity-001" ]]; then
      return 1
    fi
    ONLYMACS_LAST_HTTP_STATUS="200"
    ONLYMACS_LAST_HTTP_BODY="$(jq -cn --arg body "$detached_body" '{activities:[{status:"completed", provider_id:"provider-charles", provider_name:"Charles", owner_member_name:"Charles", resolved_model:"gemma3:27b", final_body_base64:$body}]}')"
    return 0
  }
  ONLYMACS_CURRENT_RETURN_DIR="$detached_run_dir"
  ONLYMACS_CURRENT_RETURN_RUN_ID="detached-run"
  orchestrated_recover_stream_content_from_activity "$stream_recovery_no_header_content" "$stream_recovery_no_header_headers" "step-01" "0" "$detached_artifact" "$detached_run_dir/steps/step-01/batches/batch-01/RESULT.md"
) || fail "expected stream transport recovery to fall back to provider activity when headers lack a session id"
if [[ "$(cat "$stream_recovery_no_header_content")" != *'"id":"one"'* ]]; then
  fail "expected provider-activity stream recovery to restore final relay body content"
fi
stored_batch_plan="$TEMP_STATE_DIR/stored-batch-plan.json"
cat >"$stored_batch_plan" <<STORED_BATCH_JSON
{
  "execution_settings": {
    "execution_mode": "extended",
    "json_batch_size": 5,
    "json_batch_threshold": 20,
    "chunk_size": 20,
    "chunk_threshold": 80,
    "max_tokens": 18000,
    "timeout_policy": {
      "first_progress_timeout_seconds": 300,
      "idle_timeout_seconds": 420,
      "max_wall_clock_timeout_seconds": 10800,
      "provider_heartbeat_seconds": 15,
      "terminal_preview_limit_bytes": 8000
    },
    "validator_version": "$(onlymacs_validator_version)"
  },
  "steps": [
    {
      "id": "step-01",
      "status": "running",
      "batching": {
        "filename": "sentences.json",
        "batch_size": 5
      }
    }
  ]
}
STORED_BATCH_JSON
ONLYMACS_JSON_BATCH_SIZE=1
if [[ "$(orchestrated_stored_json_batch_size "step-01" "sentences.json" "$stored_batch_plan")" != "5" ]]; then
  fail "expected persisted batch size to win over later environment defaults"
fi
orchestrated_restore_execution_settings "$stored_batch_plan"
if [[ "${ONLYMACS_JSON_BATCH_SIZE:-}" != "5" || "${ONLYMACS_FIRST_PROGRESS_TIMEOUT_SECONDS:-}" != "300" || "${ONLYMACS_PROGRESS_INTERVAL:-}" != "15" ]]; then
  fail "expected resume to restore persisted execution settings"
fi
unset ONLYMACS_JSON_BATCH_SIZE ONLYMACS_JSON_BATCH_THRESHOLD ONLYMACS_CHUNK_SIZE ONLYMACS_CHUNK_THRESHOLD ONLYMACS_ORCHESTRATED_MAX_TOKENS ONLYMACS_FIRST_PROGRESS_TIMEOUT_SECONDS ONLYMACS_IDLE_TIMEOUT_SECONDS ONLYMACS_MAX_WALL_CLOCK_TIMEOUT_SECONDS ONLYMACS_PROGRESS_INTERVAL ONLYMACS_TERMINAL_PREVIEW_BYTES
unset ONLYMACS_CURRENT_RETURN_DIR ONLYMACS_CURRENT_RETURN_RUN_ID ONLYMACS_CURRENT_RETURN_STARTED_AT ONLYMACS_CURRENT_RETURN_ROUTE_SCOPE ONLYMACS_CURRENT_RETURN_MODEL_ALIAS ONLYMACS_ORCHESTRATED_ARTIFACT_PATHS_JSON
unset ONLYMACS_PLAN_FILE_PATH ONLYMACS_RESOLVED_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT ONLYMACS_PLAN_FILE_STEP_COUNT
lesson_batch_prompt="$(orchestrated_compile_plan_file_json_batch_prompt "$ONLYMACS_PLAN_COMPILED_PROMPT" 4 5 "lessons-groups-01-02.json" 1 2 1 1 1 "lessons-groups-01-02.batch-01.json" "")"
if [[ "$lesson_batch_prompt" != *"Return exactly 1 complete item objects"* || "$lesson_batch_prompt" != *"strict JSON array"* || "$lesson_batch_prompt" != *"use exactly N unless it explicitly asks for more"* ]]; then
  fail "expected complex JSON batch prompt to constrain top-level and nested counts with a strict JSON array contract"
fi
jsonl_input="$TEMP_STATE_DIR/jsonl-artifact.json"
jsonl_output="$TEMP_STATE_DIR/jsonl-artifact.normalized.json"
printf '%s\n%s\n' '{"id":"one","lemma":"hola"}' '{"id":"two","lemma":"chau"}' >"$jsonl_input"
if ! json_artifact_to_item_array "$jsonl_input" "$jsonl_output"; then
  fail "expected JSON Lines artifact to normalize to item array"
fi
if [[ "$(jq -r 'length' "$jsonl_output")" != "2" ]]; then
  fail "expected JSON Lines normalization to preserve item count"
fi
object_stream_input="$TEMP_STATE_DIR/object-stream-artifact.json"
object_stream_output="$TEMP_STATE_DIR/object-stream-artifact.normalized.json"
printf '%s' '{"id":"one","lemma":"hola","nested":{"ok":true}}{"id":"two","lemma":"chau","nested":{"ok":true}}' >"$object_stream_input"
if ! json_artifact_to_item_array "$object_stream_input" "$object_stream_output"; then
  fail "expected adjacent JSON object stream to normalize to item array"
fi
if [[ "$(jq -r 'length' "$object_stream_output")" != "2" ]]; then
  fail "expected adjacent object stream normalization to preserve item count"
fi
vocab_batch_size="$(orchestrated_json_batch_size_for_step "Return exactly 1000 vocab items total. Items per set: exactly 20. Each item has lemma, display, translationsByLocale, and usage." "vocab.json")"
if [[ "$vocab_batch_size" != "20" ]]; then
  fail "expected vocab JSON plan batching to use 20-item micro-batches, got ${vocab_batch_size}"
fi
gold_vocab_batch_size="$(orchestrated_json_batch_size_for_step "Gold Vocab Item Schema. Return exactly 40 vocab items total. Items per set: exactly 20. Each item has lemma, display, translationsByLocale, exampleTranslationByLocale, audioHint, and usage." "vocab-40-benchmark.json")"
if [[ "$gold_vocab_batch_size" != "10" ]]; then
  fail "expected gold vocab JSON plan batching to use 10-item micro-batches, got ${gold_vocab_batch_size}"
fi
vocab_validation_prompt=$'Validation for this step:\n- Return exactly 1000 vocab items total.\n- Items per set: exactly 20.\n- Every set must contain exactly 20 items.\n\nFinal response format:'
if [[ "$(prompt_exact_count_requirement "$vocab_validation_prompt")" != "1000" ]]; then
  fail "expected validation-scoped total count to outrank per-set counts"
fi
vocab_contract_kind="$(onlymacs_schema_contract_json "Create 1000 vocab items with example sentences and translationsByLocale." "vocab.json" | jq -r '.kind')"
if [[ "$vocab_contract_kind" != "vocab_items" ]]; then
  fail "expected vocab filename to select vocab schema contract, got ${vocab_contract_kind}"
fi
source_card_contract="$(onlymacs_schema_contract_json "Generate exactly 1000 Buenos Aires source cards using the Lean Card Source Schema." "cards-source-1000.json")"
if [[ "$(jq -r '.kind' <<<"$source_card_contract")" != "source_card_items" || "$(jq -r '.required_fields | index("english") != null and index("translationsByLocale") == null' <<<"$source_card_contract")" != "true" ]]; then
  fail "expected source-card plan files to select the lean source-card schema contract"
fi
if ! prompt_requires_unique_item_terms 'Every card must have a unique normalized `lemma` plus `display` combination across the artifact.'; then
  fail "expected source-card unique normalized lemma/display language to trigger uniqueness validation"
fi
if [[ "$(orchestrated_json_batch_size_for_step "Return exactly 1000 source cards using the Lean Card Source Schema." "cards-source-1000.json")" != "5" ]]; then
  fail "expected rich source-card jobs to use small transport-safe JSON batches"
fi
enum_guidance="$(orchestrated_json_batch_enum_guidance $'- `stage` must be one of `beginner`, `early-intermediate`, `intermediate`, `upper-intermediate`, or `review`.\n- `register` must be one of `neutral`, `informal-voseo`, `polite-informal`, `formal-usted`, or `recognition-only`.')"
if [[ "$enum_guidance" != *"register"* || "$enum_guidance" != *"informal-voseo"* || "$enum_guidance" != *"do not invent variants"* ]]; then
  fail "expected JSON batch prompt enum guidance to preserve exact allowed register values"
fi
duplicate_repair_prompt="$(orchestrated_compile_repair_prompt "Return exactly 5 JSON items." "items.batch-01.json" "duplicate item terms from earlier batches: display:hablás" "/no/such/file")"
if [[ "$duplicate_repair_prompt" != *"listed duplicate terms are banned"* ]]; then
  fail "expected duplicate validation repair prompt to explicitly ban repeated terms"
fi
tuteo_repair_prompt="$(orchestrated_compile_repair_prompt "Return Buenos Aires source cards." "cards-source-1000.batch-01.json" "source-card content contains productive tuteo forms outside recognition-only items" "/no/such/file")"
if [[ "$tuteo_repair_prompt" != *"Rioplatense voseo forms"* || "$tuteo_repair_prompt" != *"podés"* ]]; then
  fail "expected tuteo validation repair prompt to give concrete voseo replacements"
fi
source_card_repair_prompt="$(orchestrated_compile_repair_prompt "Return Buenos Aires source cards." "cards-source-1000.batch-12.json" "source-card entries must follow the lean source schema exactly, include valid ids/setIds, natural examples containing the taught form, and exactly 3 real-world usage notes with a <target> tag" "/no/such/file")"
if [[ "$source_card_repair_prompt" != *"Do not use meta words such as study"* || "$source_card_repair_prompt" != *"The example sentence must contain the lemma or display"* || "$source_card_repair_prompt" != *"lemma must be the infinitive/base form"* ]]; then
  fail "expected source-card schema repair prompt to name common hidden source-card blockers"
fi
compact_retry_prompt="$(orchestrated_compile_plan_file_json_batch_compact_retry_prompt "Return exactly 5 source-card entries. Every card must have unique terms." "cards-source-1000.json" 1 81 200 401 405 5 "cards-source-1000.batch-81.json" "hola, ayuda" "batch artifact was not a JSON array or object containing item arrays")"
if [[ "$compact_retry_prompt" != *"OnlyMacs compact JSON retry"* || "$compact_retry_prompt" != *"Return exactly 5 complete JSON object"* || "$compact_retry_prompt" != *"Accepted surface hard exclusions: hola, ayuda"* || "$compact_retry_prompt" != *"Exact duplicate guard: never emit any accepted exclusion"* || "$compact_retry_prompt" != *"lemma must be the infinitive/base form"* || "$compact_retry_prompt" == *"Previous artifact excerpt"* ]]; then
  fail "expected repeated malformed JSON retries to use a compact prompt without replaying broken artifact excerpts"
fi
compact_duplicate_prompt="$(orchestrated_compile_plan_file_json_batch_compact_retry_prompt "Return exactly 5 source-card entries. Every card must have unique terms." "cards-source-1000.json" 1 97 200 481 485 5 "cards-source-1000.batch-97.json" "querés, preferís" "duplicate item terms from earlier batches: display:querés")"
if [[ "$compact_duplicate_prompt" != *"Duplicate hard ban"* || "$compact_duplicate_prompt" != *"Forbidden duplicate lemma/display strings for this retry: querés"* || "$compact_duplicate_prompt" == *"Previous artifact excerpt"* ]]; then
  fail "expected duplicate JSON retries to use a compact prompt that bans the duplicate terms"
fi
compact_seed_prompt="$(orchestrated_compile_plan_file_json_batch_compact_retry_prompt "Return exactly 5 source-card entries. Every card must have unique terms." "cards-source-1000.json" 1 185 200 921 925 5 "cards-source-1000.batch-185.json" "hola, ayuda" "duplicate item terms from earlier batches: display:bueno")"
if [[ "$compact_seed_prompt" != *"Suggested replacement surfaces for this range"* || "$compact_seed_prompt" != *"a ver"* || "$compact_seed_prompt" != *"no pasa nada"* ]]; then
  fail "expected late source-card repair prompts to include range-specific replacement surfaces"
fi
source_card_prompt='Create exactly 1 Buenos Aires source card. Output: cards-source-1000.json. Use the Lean Card Source Schema for source cards.'
source_card_good="$TEMP_STATE_DIR/source-card-good.json"
cat >"$source_card_good" <<'SOURCE_CARD_GOOD'
[
  {
    "id": "es-bue-card-01-001",
    "setId": "es-bue-card-01",
    "teachingOrder": 1,
    "lemma": "Hola",
    "display": "Hola",
    "english": "Hello",
    "pos": "interjection",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Saludos",
    "topicTags": ["saludos", "básico"],
    "cityTags": ["diario"],
    "grammarNote": "Funciona como saludo simple.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "Hola, ¿cómo andás esta mañana?",
    "example_en": "Hello, how are you this morning?",
    "usage": ["Usá <target>Hola</target> al empezar una charla.", "Sirve con conocidos y desconocidos.", "Es breve y seguro."]
  }
]
SOURCE_CARD_GOOD
validate_return_artifact "$source_card_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected lean source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_usage_string="$TEMP_STATE_DIR/source-card-usage-string.json"
jq '.[0].usage = "Use <target>Hola</target> when greeting someone."' "$source_card_good" >"$source_card_usage_string"
repair_source_card_usage_artifact_if_possible "$source_card_usage_string" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS:-}" != "repaired" ]] || ! jq -e '.[0].usage | type == "array" and length == 3' "$source_card_usage_string" >/dev/null; then
  fail "expected source-card usage repair to expand a single usage string into a 3-item array"
fi
validate_return_artifact "$source_card_usage_string" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected repaired source-card usage string artifact to pass validation"
fi
source_card_inflected_verb="$TEMP_STATE_DIR/source-card-inflected-verb.json"
jq '.[0] |= (.id = "es-bue-card-24-001" | .setId = "es-bue-card-24" | .teachingOrder = 1 | .lemma = "gustar" | .display = "gustar" | .english = "to like" | .pos = "verb" | .topic = "Preferencias" | .topicTags = ["preferences","feelings"] | .example = "Me gusta el café." | .example_en = "I like coffee." | .usage = ["Use <target>gustar</target> to express likes.", "The example may conjugate the verb naturally.", "It works like other indirect-object verbs."])' "$source_card_good" >"$source_card_inflected_verb"
validate_return_artifact "$source_card_inflected_verb" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected source-card verb examples to allow natural inflected forms when usage targets the lemma"
fi
source_card_bad_display_target="$TEMP_STATE_DIR/source-card-bad-display-target.json"
jq '.[0] |= (.id = "es-bue-card-46-017" | .setId = "es-bue-card-46" | .teachingOrder = 17 | .lemma = "dudar" | .display = "dudás" | .english = "you doubt" | .pos = "verb" | .stage = "intermediate" | .register = "informal-voseo" | .topic = "Feelings" | .topicTags = ["feelings","uncertainty"] | .cityTags = ["diario"] | .example = "¿Dudás de la dirección?" | .example_en = "Do you doubt the address?" | .usage = ["Use <target>dudar</target> for uncertainty.", "It appears in quick decisions.", "Keep it informal."])' "$source_card_good" >"$source_card_bad_display_target"
validate_return_artifact "$source_card_bad_display_target" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"exact display surface"* ]]; then
  fail "expected source-card validation to reject usage targets that wrap the lemma instead of the taught display"
fi
ONLYMACS_SOURCE_CARD_QUALITY_MODE=throughput validate_return_artifact "$source_card_bad_display_target" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" && "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" == *"exact display surface"* ]]; then
  fail "expected throughput source-card mode to relax exact usage target display matching"
fi
source_card_bad_typo="$TEMP_STATE_DIR/source-card-bad-typo.json"
jq '.[0] |= (.id = "es-bue-card-47-004" | .setId = "es-bue-card-47" | .teachingOrder = 4 | .lemma = "en cambio" | .display = "en cambio" | .english = "instead" | .pos = "adverb" | .stage = "intermediate" | .register = "neutral" | .topic = "Conversation fillers" | .topicTags = ["conversation","contrast"] | .cityTags = ["diario"] | .example = "En cambio, prefiero esperar." | .example_en = "Instead, I prefer to wait." | .usage = ["<target>En cambio</target>, prefero balear.", "Use it for contrast.", "It is common in casual speech."])' "$source_card_good" >"$source_card_bad_typo"
validate_return_artifact "$source_card_bad_typo" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"suspicious generated Spanish typo"* ]]; then
  fail "expected source-card validation to reject suspicious generated Spanish typo surfaces"
fi
source_card_bad_verb_lemma="$TEMP_STATE_DIR/source-card-bad-verb-lemma.json"
jq '.[0] |= (.id = "es-bue-card-27-011" | .setId = "es-bue-card-27" | .teachingOrder = 11 | .lemma = "ahorraré" | .display = "Ahorraré" | .english = "I will save" | .pos = "verb" | .topic = "Future plans" | .topicTags = ["future","plans"] | .example = "Ahorraré para el viaje." | .example_en = "I will save for the trip." | .usage = ["Use <target>Ahorraré</target> for a future saving plan.", "It works with dates like next month.", "It expresses a clear intention."])' "$source_card_good" >"$source_card_bad_verb_lemma"
validate_return_artifact "$source_card_bad_verb_lemma" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"verb lemma must be an infinitive"* ]]; then
  fail "expected source-card validation to reject conjugated verb lemmas"
fi
source_card_inflected_adjective="$TEMP_STATE_DIR/source-card-inflected-adjective.json"
jq '.[0] |= (.id = "es-bue-card-24-017" | .setId = "es-bue-card-24" | .teachingOrder = 17 | .lemma = "monótono" | .display = "monótono" | .english = "monotonous" | .pos = "adjective" | .topic = "Preferencias" | .topicTags = ["preferences","opinions"] | .example = "La clase fue monótona y todos nos dormimos." | .example_en = "The class was monotonous and we all fell asleep." | .usage = ["Decí <target>monótono</target> cuando algo se repite demasiado.", "Sirve para clases o trabajos repetitivos.", "Suena natural en una opinión breve."])' "$source_card_good" >"$source_card_inflected_adjective"
validate_return_artifact "$source_card_inflected_adjective" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected source-card adjective examples to allow common gender and number agreement"
fi
source_card_glued_key_json="$TEMP_STATE_DIR/source-card-glued-key-json.json"
cat >"$source_card_glued_key_json" <<'SOURCE_CARD_GLUED_KEY_JSON'
[{"id":"es-bue-card-18-013","setIdes-bue-card-18","teachingOrder":13,"lemma":"reanimación","display":"reanimación","english":"resuscitation","pos":"noun","stage":"intermediate","register":"neutral","topic":"Emergency","topicTags":["health","emergency"],"cityTags":["hospital"],"grammarNote":"Reanimación is a feminine noun.","dialectNote":"neutral in Buenos Aires","example":"El personal inició la reanimación rápido.","example_en":"The staff started resuscitation quickly.","usage":["Pedí ayuda para la <target>reanimación</target>.","Seguí las instrucciones del personal.","Esperá a la ambulancia."]}]
SOURCE_CARD_GLUED_KEY_JSON
repair_json_artifact_if_possible "$source_card_glued_key_json" "$source_card_prompt"
if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-}" != "repaired" ]] || ! jq -e '.[0].setId == "es-bue-card-18"' "$source_card_glued_key_json" >/dev/null; then
  fail "expected JSON repair to recover glued setId source-card key/value"
fi
source_card_missing_object_close_json="$TEMP_STATE_DIR/source-card-missing-object-close-json.json"
cat >"$source_card_missing_object_close_json" <<'SOURCE_CARD_MISSING_OBJECT_CLOSE_JSON'
[{"id":"es-bue-card-21-020","setId":"es-bue-card-21","teachingOrder":20,"lemma":"cerrar","display":"¿Podés cerrar la ventana?","english":"Can you close the window?","pos":"question","stage":"beginner","register":"informal-voseo","topic":"Window request","topicTags":["service","environment"],"cityTags":["apartment","home"],"grammarNote":"La specifies which window.","dialectNote":"neutral in Buenos Aires","example":"¿Podés cerrar la ventana, hace frío?","example_en":"Can you close the window, it is cold?","usage":["Tell a roommate: <target>¿Podés cerrar la ventana?</target>.","Used when temperature changes require closing.","Polite and typical in shared living spaces."]]
SOURCE_CARD_MISSING_OBJECT_CLOSE_JSON
repair_json_artifact_if_possible "$source_card_missing_object_close_json" "$source_card_prompt"
if [[ "${ONLYMACS_JSON_REPAIR_STATUS:-}" != "repaired" ]] || ! jq -e '.[0].id == "es-bue-card-21-020"' "$source_card_missing_object_close_json" >/dev/null; then
  fail "expected JSON repair to recover array object with missing final object brace"
fi
source_card_dialnote_alias="$TEMP_STATE_DIR/source-card-dialnote-alias.json"
jq '.[0] |= (.dialNote = .dialectNote | del(.dialectNote))' "$source_card_good" >"$source_card_dialnote_alias"
validate_return_artifact "$source_card_dialnote_alias" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]; then
  fail "expected unnormalized dialNote source-card alias to fail strict validation"
fi
repair_source_card_schema_aliases_if_possible "$source_card_dialnote_alias" "$source_card_prompt"
validate_return_artifact "$source_card_dialnote_alias" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-}" != "repaired" || "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected source-card schema alias repair to normalize dialNote into dialectNote"
fi
source_card_enum_variant="$TEMP_STATE_DIR/source-card-enum-variant.json"
jq '.[0] |= (.stage = "begin" | .register = "informal voseo")' "$source_card_good" >"$source_card_enum_variant"
validate_return_artifact "$source_card_enum_variant" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]; then
  fail "expected unnormalized source-card enum variants to fail strict validation"
fi
repair_source_card_schema_aliases_if_possible "$source_card_enum_variant" "$source_card_prompt"
validate_return_artifact "$source_card_enum_variant" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-}" != "repaired" || "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]] || ! jq -e '.[0].stage == "beginner" and .[0].register == "informal-voseo"' "$source_card_enum_variant" >/dev/null; then
  fail "expected source-card schema repair to normalize common enum variants"
fi
source_card_teaching_order_alias="$TEMP_STATE_DIR/source-card-teaching-order-alias.json"
jq '.[0] |= (.teOrder = .teachingOrder | del(.teachingOrder))' "$source_card_good" >"$source_card_teaching_order_alias"
repair_source_card_schema_aliases_if_possible "$source_card_teaching_order_alias" "$source_card_prompt"
validate_return_artifact "$source_card_teaching_order_alias" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-}" != "repaired" || "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]] || ! jq -e '.[0].teachingOrder == 1 and (.[0] | has("teOrder") | not)' "$source_card_teaching_order_alias" >/dev/null; then
  fail "expected source-card schema repair to normalize teachingOrder aliases"
fi
source_card_set_id_typo="$TEMP_STATE_DIR/source-card-set-id-typo.json"
jq '.[0] |= (.id = "es-bue-card-24-017" | .setId = "es-b-card-24" | .teachingOrder = 17 | .lemma = "monótono" | .display = "monótono" | .english = "monotonous" | .pos = "adjective" | .topic = "Preferencias" | .topicTags = ["preferences","opinions"] | .example = "La clase fue monótona y todos nos dormimos." | .example_en = "The class was monotonous and we all fell asleep." | .usage = ["Decí <target>monótono</target> cuando algo se repite demasiado.", "Sirve para clases o trabajos repetitivos.", "Suena natural en una opinión breve."])' "$source_card_good" >"$source_card_set_id_typo"
repair_source_card_schema_aliases_if_possible "$source_card_set_id_typo" "$source_card_prompt"
validate_return_artifact "$source_card_set_id_typo" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-}" != "repaired" || "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]] || ! jq -e '.[0].setId == "es-bue-card-24"' "$source_card_set_id_typo" >/dev/null; then
  fail "expected source-card schema repair to recover setId from a valid card id"
fi
source_card_short_tags="$TEMP_STATE_DIR/source-card-short-tags.json"
jq '.[0] |= (.topicTags = ["refusal"] | .cityTags = ["buenos aires"])' "$source_card_good" >"$source_card_short_tags"
repair_source_card_schema_aliases_if_possible "$source_card_short_tags" "$source_card_prompt"
validate_return_artifact "$source_card_short_tags" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_SCHEMA_REPAIR_STATUS:-}" != "repaired" || "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]] || ! jq -e '.[0].topicTags | length >= 2' "$source_card_short_tags" >/dev/null; then
  fail "expected source-card schema repair to normalize short topic tag arrays"
fi
source_card_common_greetings_prompt='Create exactly 3 Buenos Aires source cards. Output: cards-source-1000.json. Use the Lean Card Source Schema for source cards.'
source_card_common_greetings_good="$TEMP_STATE_DIR/source-card-common-greetings-good.json"
cat >"$source_card_common_greetings_good" <<'SOURCE_CARD_COMMON_GREETINGS_GOOD'
[
  {
    "id": "es-bue-card-01-016",
    "setId": "es-bue-card-01",
    "teachingOrder": 16,
    "lemma": "qué tal",
    "display": "¿Qué tal?",
    "english": "How's it going?",
    "pos": "question",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Saludos",
    "topicTags": ["saludos", "charla"],
    "cityTags": ["diario"],
    "grammarNote": "Funciona como pregunta breve de saludo.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "¿Qué tal? Te veo más tarde.",
    "example_en": "How's it going? I'll see you later.",
    "usage": ["Usá <target>¿Qué tal?</target> al cruzarte con alguien.", "Sirve en charlas informales.", "Suena breve y natural."]
  },
  {
    "id": "es-bue-card-01-017",
    "setId": "es-bue-card-01",
    "teachingOrder": 17,
    "lemma": "cómo te va",
    "display": "¿Cómo te va?",
    "english": "How's it going?",
    "pos": "question",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Saludos",
    "topicTags": ["saludos", "charla"],
    "cityTags": ["diario"],
    "grammarNote": "Usa el pronombre te con el verbo ir.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "¿Cómo te va? ¿Todo bien?",
    "example_en": "How's it going? Everything okay?",
    "usage": ["Preguntá <target>¿Cómo te va?</target> en una charla casual.", "Funciona con conocidos.", "Es más cercano que una pregunta formal."]
  },
  {
    "id": "es-bue-card-01-018",
    "setId": "es-bue-card-01",
    "teachingOrder": 18,
    "lemma": "hasta pronto",
    "display": "Hasta pronto",
    "english": "See you soon",
    "pos": "phrase",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Despedidas",
    "topicTags": ["despedidas", "charla"],
    "cityTags": ["diario"],
    "grammarNote": "Combina hasta con un adverbio temporal.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "Me voy al trabajo, hasta pronto.",
    "example_en": "I'm going to work, see you soon.",
    "usage": ["Decí <target>Hasta pronto</target> si esperás volver a ver a alguien.", "Sirve para despedidas breves.", "Es más cálido que una despedida seca."]
  }
]
SOURCE_CARD_COMMON_GREETINGS_GOOD
validate_return_artifact "$source_card_common_greetings_good" "$source_card_common_greetings_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected common Buenos Aires greeting/farewell source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_nice_to_see_good="$TEMP_STATE_DIR/source-card-nice-to-see-good.json"
cat >"$source_card_nice_to_see_good" <<'SOURCE_CARD_NICE_TO_SEE_GOOD'
[
  {
    "id": "es-bue-card-01-019",
    "setId": "es-bue-card-01",
    "teachingOrder": 19,
    "lemma": "qué gusto verte",
    "display": "¡Qué gusto verte!",
    "english": "Nice to see you!",
    "pos": "interjection",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Saludos",
    "topicTags": ["saludos", "charla"],
    "cityTags": ["diario"],
    "grammarNote": "Expresa alegría al reencontrarse con alguien.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "¡Qué gusto verte! Pasó mucho tiempo.",
    "example_en": "Nice to see you! It has been a long time.",
    "usage": ["Decí <target>¡Qué gusto verte!</target> al reencontrarte con alguien.", "Suena cálido e informal.", "Funciona cuando ya conocés a la otra persona."]
  }
]
SOURCE_CARD_NICE_TO_SEE_GOOD
validate_return_artifact "$source_card_nice_to_see_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected nice-to-see-you Buenos Aires source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_good_to_see_good="$TEMP_STATE_DIR/source-card-good-to-see-good.json"
cat >"$source_card_good_to_see_good" <<'SOURCE_CARD_GOOD_TO_SEE_GOOD'
[
  {
    "id": "es-bue-card-01-020",
    "setId": "es-bue-card-01",
    "teachingOrder": 20,
    "lemma": "qué bueno verte",
    "display": "¡Qué bueno verte!",
    "english": "Great to see you!",
    "pos": "interjection",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Saludos",
    "topicTags": ["saludos", "charla"],
    "cityTags": ["diario"],
    "grammarNote": "Expresa alegría al encontrarse con alguien.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "¡Qué bueno verte! ¿Cómo andás?",
    "example_en": "Great to see you! How are you?",
    "usage": ["Decí <target>¡Qué bueno verte!</target> al saludar a alguien conocido.", "Suena cercano y natural.", "Funciona en reuniones informales."]
  }
]
SOURCE_CARD_GOOD_TO_SEE_GOOD
validate_return_artifact "$source_card_good_to_see_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected great-to-see-you Buenos Aires source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_intro_good="$TEMP_STATE_DIR/source-card-intro-good.json"
cat >"$source_card_intro_good" <<'SOURCE_CARD_INTRO_GOOD'
[
  {
    "id": "es-bue-card-01-020",
    "setId": "es-bue-card-01",
    "teachingOrder": 20,
    "lemma": "encantado de conocerte",
    "display": "¡Encantado de conocerte!",
    "english": "Nice to meet you!",
    "pos": "phrase",
    "stage": "beginner",
    "register": "polite-informal",
    "topic": "Saludos",
    "topicTags": ["saludos", "presentación"],
    "cityTags": ["diario"],
    "grammarNote": "Es una fórmula de presentación.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "¡Encantado de conocerte! Me llamo Leo.",
    "example_en": "Nice to meet you! My name is Leo.",
    "usage": ["Usá <target>¡Encantado de conocerte!</target> al conocer a alguien.", "Suena amable en presentaciones.", "Funciona en reuniones informales."]
  }
]
SOURCE_CARD_INTRO_GOOD
validate_return_artifact "$source_card_intro_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected introduction source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_batches_dir="$TEMP_STATE_DIR/source-card-batches"
mkdir -p "$source_card_batches_dir/batch-01/files"
cp "$source_card_good" "$source_card_batches_dir/batch-01/files/cards-source-1000.batch-01.json"
source_card_duplicate_batch="$TEMP_STATE_DIR/source-card-duplicate-batch.json"
cat >"$source_card_duplicate_batch" <<'SOURCE_CARD_DUPLICATE_BATCH'
[
  {
    "id": "es-bue-card-01-002",
    "setId": "es-bue-card-01",
    "teachingOrder": 2,
    "lemma": "hola",
    "display": "Hola",
    "english": "Hello again",
    "pos": "interjection",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Saludos",
    "topicTags": ["saludos", "básico"],
    "cityTags": ["diario"],
    "grammarNote": "Funciona como saludo simple.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "Hola, ¿cómo andás ahora?",
    "example_en": "Hello, how are you now?",
    "usage": ["Usá <target>Hola</target> al entrar.", "Sirve con todos.", "Es breve."]
  }
]
SOURCE_CARD_DUPLICATE_BATCH
orchestrated_validate_json_batch_uniqueness "$source_card_duplicate_batch" "$source_card_batches_dir" 2
if [[ "${ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS:-}" != "failed" || "${ONLYMACS_JSON_BATCH_UNIQUENESS_MESSAGE:-}" != *"duplicate"* ]]; then
  fail "expected source-card JSON batches to reject duplicate lemma/display terms across accepted batches"
fi
source_card_phrase_batches_dir="$TEMP_STATE_DIR/source-card-phrase-batches"
mkdir -p "$source_card_phrase_batches_dir/batch-01/files"
cat >"$source_card_phrase_batches_dir/batch-01/files/cards-source-1000.batch-01.json" <<'SOURCE_CARD_PHRASE_PREVIOUS'
[
  {
    "id": "es-bue-card-01-010",
    "setId": "es-bue-card-01",
    "teachingOrder": 10,
    "lemma": "ver",
    "display": "Nos vemos.",
    "english": "See you.",
    "pos": "phrase",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Saludos",
    "topicTags": ["saludos", "despedida"],
    "cityTags": ["diario"],
    "grammarNote": "Es una despedida fija.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "Nos vemos mañana en el café.",
    "example_en": "See you tomorrow at the cafe.",
    "usage": ["Decí <target>Nos vemos.</target> al despedirte.", "Sirve con conocidos.", "Es breve y natural."]
  }
]
SOURCE_CARD_PHRASE_PREVIOUS
source_card_core_verb_batch="$TEMP_STATE_DIR/source-card-core-verb-batch.json"
cat >"$source_card_core_verb_batch" <<'SOURCE_CARD_CORE_VERB_BATCH'
[
  {
    "id": "es-bue-card-03-020",
    "setId": "es-bue-card-03",
    "teachingOrder": 20,
    "lemma": "ver",
    "display": "ves",
    "english": "you see",
    "pos": "verb",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Voseo",
    "topicTags": ["voseo", "verbos"],
    "cityTags": ["diario"],
    "grammarNote": "Voseo present form of ver.",
    "dialectNote": "Uses Rioplatense voseo.",
    "example": "¿Ves el cartel de la esquina?",
    "example_en": "Do you see the sign on the corner?",
    "usage": ["Usá <target>ves</target> para preguntar si alguien sees something.", "Es común en preguntas simples.", "Mantiene trato informal."]
  }
]
SOURCE_CARD_CORE_VERB_BATCH
orchestrated_validate_json_batch_uniqueness "$source_card_core_verb_batch" "$source_card_phrase_batches_dir" 2
if [[ "${ONLYMACS_JSON_BATCH_UNIQUENESS_STATUS:-}" == "failed" ]]; then
  fail "expected source-card uniqueness to allow a core verb card when an earlier phrase used the same lemma behind a different display"
fi
source_card_prompt_terms="$(orchestrated_previous_json_batch_terms_for_prompt "$source_card_phrase_batches_dir" 2)"
if [[ "$source_card_prompt_terms" == *"ver"* || "$source_card_prompt_terms" != *"nos vemos."* ]]; then
  fail "expected prior-term prompts to ban the learner-facing phrase surface instead of over-banning the hidden lemma"
fi
source_card_current_set_terms_dir="$TEMP_STATE_DIR/source-card-current-set-terms"
mkdir -p "$source_card_current_set_terms_dir/batch-01/files" "$source_card_current_set_terms_dir/batch-02/files" "$source_card_current_set_terms_dir/batch-03/files"
cp "$source_card_good" "$source_card_current_set_terms_dir/batch-01/files/cards-source-1000.batch-01.json"
cat >"$source_card_current_set_terms_dir/batch-02/files/cards-source-1000.batch-02.json" <<'SOURCE_CARD_SET_TERMS_02'
[
  {"id":"es-bue-card-04-001","setId":"es-bue-card-04","teachingOrder":1,"lemma":"perdón","display":"Perdón"}
]
SOURCE_CARD_SET_TERMS_02
cat >"$source_card_current_set_terms_dir/batch-03/files/cards-source-1000.batch-03.json" <<'SOURCE_CARD_SET_TERMS_03'
[
  {"id":"es-bue-card-04-002","setId":"es-bue-card-04","teachingOrder":2,"lemma":"entender","display":"¿Me entendés?"}
]
SOURCE_CARD_SET_TERMS_03
cat >"$source_card_current_set_terms_dir/batch-03/files/cards-source-1000.batch-03.invalid-pre-guard.json" <<'SOURCE_CARD_SET_TERMS_INVALID'
[
  {"id":"es-bue-card-04-999","setId":"es-bue-card-04","teachingOrder":99,"lemma":"metro","display":"metro"}
]
SOURCE_CARD_SET_TERMS_INVALID
source_card_current_set_prompt_terms="$(orchestrated_previous_json_batch_terms_for_prompt "$source_card_current_set_terms_dir" 4 61 'Return exactly 1000 cards total. Items per set: exactly 20. Every card must have unique terms.')"
if [[ "$source_card_current_set_prompt_terms" != *"Current set HARD EXCLUSION surfaces (do not use as lemma/display/text in this set): perdón, ¿me entendés?"* || "$source_card_current_set_prompt_terms" != *"Global accepted surface exclusions"* || "$source_card_current_set_prompt_terms" != *"hola"* ]]; then
  fail "expected previous-term prompts to prioritize current-set accepted surfaces while still including global accepted terms"
fi
if [[ "$source_card_current_set_prompt_terms" == *"metro"* ]]; then
  fail "expected previous-term prompts to ignore archived invalid batch artifacts"
fi
source_card_large_global_terms_dir="$TEMP_STATE_DIR/source-card-large-global-terms"
mkdir -p "$source_card_large_global_terms_dir/batch-01/files" "$source_card_large_global_terms_dir/batch-02/files"
cat >"$source_card_large_global_terms_dir/batch-01/files/cards-source-1000.batch-01.json" <<'SOURCE_CARD_LARGE_GLOBAL_SET_ANCHOR'
[
  {"id":"es-bue-card-04-001","setId":"es-bue-card-04","teachingOrder":1,"lemma":"ancla","display":"current-set-anchor"}
]
SOURCE_CARD_LARGE_GLOBAL_SET_ANCHOR
{
  printf '[\n'
  for term_index in $(seq 1 260); do
    printf '  {"id":"es-bue-card-01-%03d","setId":"es-bue-card-01","teachingOrder":%d,"lemma":"term-%03d-with-padding","display":"term-%03d-with-padding"},\n' "$term_index" "$term_index" "$term_index" "$term_index"
  done
  printf '  {"id":"es-bue-card-01-999","setId":"es-bue-card-01","teachingOrder":999,"lemma":"zzzz-tail-term","display":"zzzz-tail-term"}\n'
  printf ']\n'
} >"$source_card_large_global_terms_dir/batch-02/files/cards-source-1000.batch-02.json"
source_card_large_global_prompt_terms="$(orchestrated_previous_json_batch_terms_for_prompt "$source_card_large_global_terms_dir" 3 61 'Return exactly 1000 cards total. Items per set: exactly 20. Every card must have unique terms.')"
if [[ "$source_card_large_global_prompt_terms" != *"Current set HARD EXCLUSION surfaces (do not use as lemma/display/text in this set): current-set-anchor"* || "$source_card_large_global_prompt_terms" != *"zzzz-tail-term"* ]]; then
  fail "expected previous-term prompts to keep enough global accepted terms for late go-wide source-card batches"
fi
source_card_literal_target_bad="$TEMP_STATE_DIR/source-card-literal-target-bad.json"
cat >"$source_card_literal_target_bad" <<'SOURCE_CARD_LITERAL_TARGET_BAD'
[
  {
    "id": "es-bue-card-01-001",
    "setId": "es-bue-card-01",
    "teachingOrder": 1,
    "lemma": "Hola",
    "display": "Hola",
    "english": "Hello",
    "pos": "interjection",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Saludos",
    "topicTags": ["saludos", "básico"],
    "cityTags": ["diario"],
    "grammarNote": "Funciona como saludo simple.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "Hola, ¿cómo andás esta mañana?",
    "example_en": "Hello, how are you this morning?",
    "usage": ["Usá <target> al empezar una charla.", "Sirve con conocidos y desconocidos.", "Es breve y seguro."]
  }
]
SOURCE_CARD_LITERAL_TARGET_BAD
validate_return_artifact "$source_card_literal_target_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"actual taught form"* ]]; then
  fail "expected lean source-card validation to reject literal target placeholders"
fi
source_card_unaccented_voseo_bad="$TEMP_STATE_DIR/source-card-unaccented-voseo-bad.json"
cat >"$source_card_unaccented_voseo_bad" <<'SOURCE_CARD_UNACCENTED_VOSEO_BAD'
[
  {
    "id": "es-bue-card-01-008",
    "setId": "es-bue-card-01",
    "teachingOrder": 8,
    "lemma": "que hacas",
    "display": "¿Qué hacés?",
    "english": "What are you doing?",
    "pos": "question",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Saludos",
    "topicTags": ["saludos", "voseo"],
    "cityTags": ["diario"],
    "grammarNote": "Funciona como pregunta informal.",
    "dialectNote": "Uses voseo in Buenos Aires.",
    "example": "¿Qué hacés? Te esperaba en la esquina.",
    "example_en": "What are you doing? I was waiting for you on the corner.",
    "usage": ["Usá <target>¿Qué hacés?</target> con amigos.", "Suena informal.", "No va en trámites formales."]
  }
]
SOURCE_CARD_UNACCENTED_VOSEO_BAD
validate_return_artifact "$source_card_unaccented_voseo_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"unaccented Rioplatense"* ]]; then
  fail "expected lean source-card validation to reject unaccented voseo spellings in lemma/display"
fi
source_card_tuteo_bad="$TEMP_STATE_DIR/source-card-tuteo-bad.json"
cat >"$source_card_tuteo_bad" <<'SOURCE_CARD_TUTEO_BAD'
[
  {
    "id": "es-bue-card-01-020",
    "setId": "es-bue-card-01",
    "teachingOrder": 20,
    "lemma": "cuídate",
    "display": "Cuídate",
    "english": "Take care",
    "pos": "verb",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Despedidas",
    "topicTags": ["despedidas", "cuidado"],
    "cityTags": ["diario"],
    "grammarNote": "Es un imperativo informal.",
    "dialectNote": "Should use voseo in Buenos Aires.",
    "example": "Te llamo después, cuídate.",
    "example_en": "I'll call you later, take care.",
    "usage": ["Use <target>Cuídate</target> when saying goodbye.", "Avoid puedes and conoces in this Buenos Aires card.", "Replace has llamado with a local phrasing before accepting."]
  }
]
SOURCE_CARD_TUTEO_BAD
validate_return_artifact "$source_card_tuteo_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"productive tuteo"* ]]; then
  fail "expected lean source-card validation to reject productive tuteo leakage"
fi
source_card_tuteo_repairable="$TEMP_STATE_DIR/source-card-tuteo-repairable.json"
cp "$source_card_tuteo_bad" "$source_card_tuteo_repairable"
repair_rioplatense_tuteo_artifact_if_possible "$source_card_tuteo_repairable" "$source_card_prompt"
if [[ "${ONLYMACS_DIALECT_REPAIR_STATUS:-}" != "repaired" ]]; then
  fail "expected simple tuteo leakage to be locally repairable"
fi
validate_return_artifact "$source_card_tuteo_repairable" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected locally repaired tuteo source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_perdona_bad="$TEMP_STATE_DIR/source-card-perdona-bad.json"
cat >"$source_card_perdona_bad" <<'SOURCE_CARD_PERDONA_BAD'
[
  {
    "id": "es-bue-card-04-011",
    "setId": "es-bue-card-04",
    "teachingOrder": 11,
    "lemma": "perdonar",
    "display": "Perdona",
    "english": "Sorry",
    "pos": "verb",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Apology",
    "topicTags": ["apology", "courtesy"],
    "cityTags": ["diario"],
    "grammarNote": "Imperative apology.",
    "dialectNote": "Should use voseo in Buenos Aires.",
    "example": "Perdona, llegué tarde.",
    "example_en": "Sorry, I arrived late.",
    "usage": ["Use <target>Perdona</target> when apologizing.", "Local command before repair: Dí la frase con calma.", "Keep this for informal chats."]
  }
]
SOURCE_CARD_PERDONA_BAD
validate_return_artifact "$source_card_perdona_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"productive tuteo"* ]]; then
  fail "expected lean source-card validation to reject tuteo imperatives like Perdona and Dí"
fi
repair_rioplatense_tuteo_artifact_if_possible "$source_card_perdona_bad" "$source_card_prompt"
validate_return_artifact "$source_card_perdona_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local tuteo imperative repair to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_common_imperatives_bad="$TEMP_STATE_DIR/source-card-common-imperatives-bad.json"
cat >"$source_card_common_imperatives_bad" <<'SOURCE_CARD_COMMON_IMPERATIVES_BAD'
[
  {
    "id": "es-bue-card-06-017",
    "setId": "es-bue-card-06",
    "teachingOrder": 17,
    "lemma": "intersección",
    "display": "intersección",
    "english": "intersection",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Directions",
    "topicTags": ["directions", "location"],
    "cityTags": ["diario"],
    "grammarNote": "A crossing where streets meet.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "La intersección está cerca del parque.",
    "example_en": "The intersection is near the park.",
    "usage": ["Local command before repair: Busca la señal de la <target>intersección</target>.", "Route note before repair: Gira right, lee el cartel, and enciende la linterna after crossing.", "Emergency note before repair: Marca el cruce, Programa la ruta, Pregunta por ayuda, and Mantén la calma."]
  }
]
SOURCE_CARD_COMMON_IMPERATIVES_BAD
validate_return_artifact "$source_card_common_imperatives_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"productive tuteo"* ]]; then
  fail "expected lean source-card validation to reject common tuteo imperatives like Busca and Usa"
fi
repair_rioplatense_tuteo_artifact_if_possible "$source_card_common_imperatives_bad" "$source_card_prompt"
validate_return_artifact "$source_card_common_imperatives_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local common-imperative repair to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
if [[ "$(jq -r '.[0].usage | join(" ")' "$source_card_common_imperatives_bad")" != *"Leé el cartel"* && "$(jq -r '.[0].usage | join(" ")' "$source_card_common_imperatives_bad")" != *"leé el cartel"* ]]; then
  fail "expected local common-imperative repair to normalize Lee/lee to Leé/leé"
fi
if [[ "$(jq -r '.[0].usage | join(" ")' "$source_card_common_imperatives_bad")" != *"encendé la linterna"* ]]; then
  fail "expected local common-imperative repair to normalize enciende to encendé"
fi
if [[ "$(jq -r '.[0].usage | join(" ")' "$source_card_common_imperatives_bad")" != *"Marcá el cruce"* || ( "$(jq -r '.[0].usage | join(" ")' "$source_card_common_imperatives_bad")" != *"Mantené la calma"* && "$(jq -r '.[0].usage | join(" ")' "$source_card_common_imperatives_bad")" != *"mantené la calma"* ) ]]; then
  fail "expected local common-imperative repair to normalize broader health/service command verbs"
fi
source_card_consulta_noun_good="$TEMP_STATE_DIR/source-card-consulta-noun-good.json"
cat >"$source_card_consulta_noun_good" <<'SOURCE_CARD_CONSULTA_NOUN_GOOD'
[
  {
    "id": "es-bue-card-18-001",
    "setId": "es-bue-card-18",
    "teachingOrder": 1,
    "lemma": "consulta",
    "display": "consulta",
    "english": "medical appointment",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Doctor visit",
    "topicTags": ["health", "appointment"],
    "cityTags": ["clinic"],
    "grammarNote": "Consulta is a feminine noun for a scheduled doctor visit.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Tengo una consulta mañana.",
    "example_en": "I have a medical appointment tomorrow.",
    "usage": ["Llegá temprano a la <target>consulta</target>.", "Traé tu documento a la consulta.", "Podés cambiar la consulta por teléfono."]
  }
]
SOURCE_CARD_CONSULTA_NOUN_GOOD
repair_rioplatense_tuteo_artifact_if_possible "$source_card_consulta_noun_good" "$source_card_prompt"
if [[ "$(jq -r '.[0].display' "$source_card_consulta_noun_good")" != "consulta" || "$(jq -r '.[0].example' "$source_card_consulta_noun_good")" != *"consulta mañana"* ]]; then
  fail "expected tuteo repair not to over-normalize consulta noun surfaces into consultá"
fi
validate_return_artifact "$source_card_consulta_noun_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected consulta noun source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_command_noun_bad="$TEMP_STATE_DIR/source-card-command-noun-bad.json"
cat >"$source_card_command_noun_bad" <<'SOURCE_CARD_COMMAND_NOUN_BAD'
[
  {
    "id": "es-bue-card-18-002",
    "setId": "es-bue-card-18",
    "teachingOrder": 2,
    "lemma": "consultá",
    "display": "consultá",
    "english": "medical appointment",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Doctor visit",
    "topicTags": ["health", "appointment"],
    "cityTags": ["clinic"],
    "grammarNote": "Consultá is a feminine noun for a scheduled doctor visit.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Tengo una consultá mañana.",
    "example_en": "I have a medical appointment tomorrow.",
    "usage": ["Llegá temprano a la <target>consultá</target>.", "Traé tu documento.", "Podés cambiarla por teléfono."]
  }
]
SOURCE_CARD_COMMAND_NOUN_BAD
validate_return_artifact "$source_card_command_noun_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"noun lemma/display was over-normalized"* ]]; then
  fail "expected source-card validation to reject command-looking noun lemma/display over-normalization"
fi
source_card_pedi_good="$TEMP_STATE_DIR/source-card-pedi-good.json"
cat >"$source_card_pedi_good" <<'SOURCE_CARD_PEDI_GOOD'
[
  {
    "id": "es-bue-card-08-002",
    "setId": "es-bue-card-08",
    "teachingOrder": 2,
    "lemma": "café con leche",
    "display": "café con leche",
    "english": "coffee with milk",
    "pos": "phrase",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Cafe ordering",
    "topicTags": ["cafe", "drink"],
    "cityTags": ["cafe"],
    "grammarNote": "A common cafe order.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Pedí un café con leche en la barra.",
    "example_en": "I ordered a coffee with milk at the counter.",
    "usage": ["Pedí <target>café con leche</target> en una cafetería.", "Se pedí con medialunas en muchos cafés.", "Es común con medialunas."]
  }
]
SOURCE_CARD_PEDI_GOOD
repair_rioplatense_tuteo_artifact_if_possible "$source_card_pedi_good" "$source_card_prompt"
if rg -q 'Pedecí|pedecí' "$source_card_pedi_good"; then
  fail "expected Dí repair not to corrupt Pedí into Pedecí"
fi
if rg -q 'se pedí|Se pedí' "$source_card_pedi_good"; then
  fail "expected pide repair not to corrupt neutral se pide phrasing"
fi
validate_return_artifact "$source_card_pedi_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected existing Pedí source-card text to stay valid, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_llama_good="$TEMP_STATE_DIR/source-card-llama-good.json"
cat >"$source_card_llama_good" <<'SOURCE_CARD_LLAMA_GOOD'
[
  {
    "id": "es-bue-card-14-003",
    "setId": "es-bue-card-14",
    "teachingOrder": 3,
    "lemma": "sobrina",
    "display": "sobrina",
    "english": "niece",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Family",
    "topicTags": ["family", "relatives"],
    "cityTags": ["home"],
    "grammarNote": "Sobrina is a feminine noun.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Mi sobrina ganó la carrera en la escuela.",
    "example_en": "My niece won the race at school.",
    "usage": ["<target>sobrina</target> siempre me llama para pedir ayuda.", "Podés invitar a tu sobrina a cenar.", "Mi sobrina dibujó un cuadro."]
  }
]
SOURCE_CARD_LLAMA_GOOD
repair_rioplatense_tuteo_artifact_if_possible "$source_card_llama_good" "$source_card_prompt"
if rg -q 'me llamá|Me llamá' "$source_card_llama_good"; then
  fail "expected voseo repair not to corrupt neutral me llama phrasing"
fi
validate_return_artifact "$source_card_llama_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected repaired source-card with neutral me llama phrasing to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_more_tuteo_bad="$TEMP_STATE_DIR/source-card-more-tuteo-bad.json"
cat >"$source_card_more_tuteo_bad" <<'SOURCE_CARD_MORE_TUTEO_BAD'
[
  {
    "id": "es-bue-card-14-011",
    "setId": "es-bue-card-14",
    "teachingOrder": 11,
    "lemma": "cuñado",
    "display": "cuñado",
    "english": "brother-in-law",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Family",
    "topicTags": ["family", "relations"],
    "cityTags": ["home"],
    "grammarNote": "Cuñado is a masculine noun.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Mi cuñado viene a cenar esta noche.",
    "example_en": "My brother-in-law is coming for dinner tonight.",
    "usage": ["Preguntá por <target>cuñado</target>: ¿En qué trabajá tu cuñado?", "Si pierdes el número, abri la agenda.", "Las notificaciones aparecen si las configuras."]
  }
]
SOURCE_CARD_MORE_TUTEO_BAD
validate_return_artifact "$source_card_more_tuteo_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]; then
  fail "expected added tuteo/unaccented forms to fail before repair"
fi
repair_rioplatense_tuteo_artifact_if_possible "$source_card_more_tuteo_bad" "$source_card_prompt"
validate_return_artifact "$source_card_more_tuteo_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" || "$(jq -r '.[0].usage | join(" ")' "$source_card_more_tuteo_bad")" != *"trabaja tu cuñado"* ]]; then
  fail "expected added tuteo/unaccented forms to repair without over-accented third-person subjects"
fi
source_card_unaccented_voseo_bad="$TEMP_STATE_DIR/source-card-unaccented-voseo-bad.json"
cat >"$source_card_unaccented_voseo_bad" <<'SOURCE_CARD_UNACCENTED_VOSEO_BAD'
[
  {
    "id": "es-bue-card-08-011",
    "setId": "es-bue-card-08",
    "teachingOrder": 11,
    "lemma": "espresso",
    "display": "espresso",
    "english": "espresso",
    "pos": "noun",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Cafe ordering",
    "topicTags": ["cafe", "drink"],
    "cityTags": ["cafe"],
    "grammarNote": "A common cafe order.",
    "dialectNote": "Use accented voseo in Buenos Aires.",
    "example": "Podes pedir un espresso en la barra.",
    "example_en": "You can order an espresso at the counter.",
    "usage": ["Ask for an <target>espresso</target> at any cafe counter.", "Payment usually happens at the register.", "Queue note before repair: Mantene la calma if there is a line."]
  }
]
SOURCE_CARD_UNACCENTED_VOSEO_BAD
validate_return_artifact "$source_card_unaccented_voseo_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"unaccented Rioplatense voseo"* ]]; then
  fail "expected source-card validation to reject unaccented voseo in example/usage"
fi
repair_rioplatense_tuteo_artifact_if_possible "$source_card_unaccented_voseo_bad" "$source_card_prompt"
validate_return_artifact "$source_card_unaccented_voseo_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local unaccented-voseo repair to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
if [[ "$(jq -r '.[0].usage | join(" ")' "$source_card_unaccented_voseo_bad")" != *"Mantené la calma"* ]]; then
  fail "expected local unaccented-voseo repair to normalize Mantene to Mantené"
fi
source_card_target_tag_bad="$TEMP_STATE_DIR/source-card-target-tag-bad.json"
cat >"$source_card_target_tag_bad" <<'SOURCE_CARD_TARGET_TAG_BAD'
[
  {
    "id": "es-bue-card-07-002",
    "setId": "es-bue-card-07",
    "teachingOrder": 2,
    "lemma": "tarjeta",
    "display": "tarjeta",
    "english": "card",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Transport",
    "topicTags": ["transport", "ticket"],
    "cityTags": ["subte"],
    "grammarNote": "Tarjeta is a feminine noun.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Necesito cargar mi tarjeta antes de viajar.",
    "example_en": "I need to top up my card before traveling.",
    "usage": ["Comprá una <target>tarjeta</target> en la estación.", "Apoyá la <target>tarjeta</> en el lector.", "Guardá la tarjeta hasta terminar el viaje."]
  }
]
SOURCE_CARD_TARGET_TAG_BAD
validate_return_artifact "$source_card_target_tag_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]; then
  fail "expected lean source-card validation to reject malformed target closing tags"
fi
repair_source_card_usage_artifact_if_possible "$source_card_target_tag_bad" "$source_card_prompt"
validate_return_artifact "$source_card_target_tag_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local target-tag repair to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_example_target_markup_bad="$TEMP_STATE_DIR/source-card-example-target-markup-bad.json"
cat >"$source_card_example_target_markup_bad" <<'SOURCE_CARD_EXAMPLE_TARGET_MARKUP_BAD'
[
  {
    "id": "es-bue-card-07-003",
    "setId": "es-bue-card-07",
    "teachingOrder": 3,
    "lemma": "boleto",
    "display": "boleto",
    "english": "ticket",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Transport",
    "topicTags": ["transport", "ticket"],
    "cityTags": ["subte"],
    "grammarNote": "Boleto is a masculine noun.",
    "dialectNote": "Boleto is natural for transport fares in Buenos Aires.",
    "example": "Compré un <target>boleto</target> para el colectivo.",
    "example_en": "I bought a ticket for the bus.",
    "usage": ["Use <target>boleto</target> for a transport ticket.", "Pair it with colectivo, subte, or tren.", "Keep it tied to local fare and route contexts."]
  }
]
SOURCE_CARD_EXAMPLE_TARGET_MARKUP_BAD
validate_return_artifact "$source_card_example_target_markup_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]; then
  fail "expected lean source-card validation to reject target markup inside examples"
fi
repair_source_card_schema_aliases_if_possible "$source_card_example_target_markup_bad" "$source_card_prompt"
validate_return_artifact "$source_card_example_target_markup_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local source-card schema repair to strip example target markup, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_partial_target_bad="$TEMP_STATE_DIR/source-card-partial-target-bad.json"
cat >"$source_card_partial_target_bad" <<'SOURCE_CARD_PARTIAL_TARGET_BAD'
[
  {
    "id": "es-bue-card-16-004",
    "setId": "es-bue-card-16",
    "teachingOrder": 4,
    "lemma": "guante",
    "display": "guantes",
    "english": "gloves",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Clothing",
    "topicTags": ["clothing", "weather"],
    "cityTags": ["home"],
    "grammarNote": "Guantes is the plural of guante.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "Necesito guantes para la helada.",
    "example_en": "I need gloves for the frost.",
    "usage": ["Wear <target>gu</target> when it is cold.", "They protect your hands.", "You can buy guantes downtown."]
  }
]
SOURCE_CARD_PARTIAL_TARGET_BAD
validate_return_artifact "$source_card_partial_target_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" ]]; then
  fail "expected lean source-card validation to reject target tags that do not contain the display or lemma"
fi
repair_source_card_usage_artifact_if_possible "$source_card_partial_target_bad" "$source_card_prompt"
validate_return_artifact "$source_card_partial_target_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local source-card usage repair to retarget partial target tags, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_transport_locale_bad="$TEMP_STATE_DIR/source-card-transport-locale-bad.json"
cat >"$source_card_transport_locale_bad" <<'SOURCE_CARD_TRANSPORT_LOCALE_BAD'
[
  {
    "id": "es-bue-card-07-011",
    "setId": "es-bue-card-07",
    "teachingOrder": 11,
    "lemma": "metro",
    "display": "metro",
    "english": "subway",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "transport",
    "topicTags": ["transport", "routes"],
    "cityTags": ["buenos-aires"],
    "grammarNote": "Metro is a masculine noun.",
    "dialectNote": "Use subte in Buenos Aires.",
    "example": "El metro está rápido hoy.",
    "example_en": "The subway is fast today.",
    "usage": ["Take the <target>metro</target> downtown.", "Avoid saying autobús for a colectivo.", "The paradero is near the corner."]
  }
]
SOURCE_CARD_TRANSPORT_LOCALE_BAD
validate_return_artifact "$source_card_transport_locale_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"non-Buenos Aires transport"* ]]; then
  fail "expected Buenos Aires source-card validation to reject non-local transport terms"
fi
source_card_ba_wording_bad="$TEMP_STATE_DIR/source-card-ba-wording-bad.json"
cat >"$source_card_ba_wording_bad" <<'SOURCE_CARD_BA_WORDING_BAD'
[
  {
    "id": "es-bue-card-08-010",
    "setId": "es-bue-card-08",
    "teachingOrder": 10,
    "lemma": "tostada",
    "display": "tostada con mantequilla",
    "english": "buttered toast",
    "pos": "noun",
    "stage": "beginner",
    "register": "neutral",
    "topic": "Cafe ordering",
    "topicTags": ["cafe", "food"],
    "cityTags": ["cafe"],
    "grammarNote": "A common cafe order.",
    "dialectNote": "Use manteca in Buenos Aires.",
    "example": "Pedí una tostada con mantequilla y zumo en el metro.",
    "example_en": "I ordered a buttered toast in the subway.",
    "usage": ["Before repair, ask for the <target>tostada con mantequilla</target> at the cafe.", "Before repair, avoid saying en el metro for Buenos Aires.", "Before repair, replace camarero, mesero, pastel, and refresco with local wording."]
  }
]
SOURCE_CARD_BA_WORDING_BAD
validate_return_artifact "$source_card_ba_wording_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"non-local Buenos Aires wording"* ]]; then
  fail "expected Buenos Aires source-card validation to reject en el metro/mantequilla wording"
fi
repair_rioplatense_tuteo_artifact_if_possible "$source_card_ba_wording_bad" "$source_card_prompt"
if rg -qi '\\b(mantequilla|zumo|refresco|pastel|camarero|mesero)\\b|\\b(en el|del|al) metro\\b|\\bpide (el|la|un|una|los|las)\\b' "$source_card_ba_wording_bad"; then
  fail "expected local Buenos Aires wording repair to remove non-local terms"
fi
validate_return_artifact "$source_card_ba_wording_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected local Buenos Aires wording repair to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_usage_meta_bad="$TEMP_STATE_DIR/source-card-usage-meta-bad.json"
cat >"$source_card_usage_meta_bad" <<'SOURCE_CARD_USAGE_META_BAD'
[
  {
    "id": "es-bue-card-03-016",
    "setId": "es-bue-card-03",
    "teachingOrder": 16,
    "lemma": "aprender",
    "display": "aprendés",
    "english": "you learn",
    "pos": "verb",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Voseo",
    "topicTags": ["voseo", "verbos"],
    "cityTags": ["diario"],
    "grammarNote": "The vos form of aprender is aprendés.",
    "dialectNote": "Uses Rioplatense voseo.",
    "example": "¿Qué aprendés en la clase?",
    "example_en": "What are you learning in class?",
    "usage": ["Usá <target>aprendés</target> para preguntar por una clase.", "Sirve para hablar de ongoing study.", "Es común con amigos."]
  }
]
SOURCE_CARD_USAGE_META_BAD
validate_return_artifact "$source_card_usage_meta_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"lean source schema"* ]]; then
  fail "expected source-card validation to reject meta study language in usage"
fi
repair_source_card_usage_artifact_if_possible "$source_card_usage_meta_bad" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS:-}" != "repaired" ]]; then
  fail "expected source-card usage meta language to be locally repairable"
fi
validate_return_artifact "$source_card_usage_meta_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected locally repaired source-card usage artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_usage_pipe_string_bad="$TEMP_STATE_DIR/source-card-usage-pipe-string-bad.json"
cat >"$source_card_usage_pipe_string_bad" <<'SOURCE_CARD_USAGE_PIPE_STRING_BAD'
[
  {
    "id": "es-bue-card-30-001",
    "setId": "es-bue-card-30",
    "teachingOrder": 1,
    "lemma": "prohibido fumar",
    "display": "Prohibido fumar",
    "english": "No smoking",
    "pos": "phrase",
    "stage": "intermediate",
    "register": "neutral",
    "topic": "Permissions, rules, signs, and restrictions",
    "topicTags": ["permissions", "rules", "signs"],
    "cityTags": ["buenos-aires", "signage"],
    "grammarNote": "Used on signs to forbid smoking in the area.",
    "dialectNote": "neutral in Buenos Aires",
    "example": "En la entrada hay un cartel que dice Prohibido fumar.",
    "example_en": "At the entrance there is a sign that says No smoking.",
    "usage": "Look for <target>Prohibido fumar</target> in public areas. | Do not smoke where you see <target>Prohibido fumar</target>. | The rule <target>Prohibido fumar</target> applies inside restaurants."
  }
]
SOURCE_CARD_USAGE_PIPE_STRING_BAD
validate_return_artifact "$source_card_usage_pipe_string_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"usage not array"* ]]; then
  fail "expected source-card validation to reject pipe-delimited usage strings"
fi
repair_source_card_usage_artifact_if_possible "$source_card_usage_pipe_string_bad" "$source_card_prompt"
if [[ "${ONLYMACS_SOURCE_CARD_USAGE_REPAIR_STATUS:-}" != "repaired" ]]; then
  fail "expected source-card pipe-delimited usage strings to be locally repairable"
fi
if [[ "$(jq -r '.[0].usage | type + ":" + (length|tostring)' "$source_card_usage_pipe_string_bad")" != "array:3" ]]; then
  fail "expected repaired source-card usage string to become a 3-item array"
fi
validate_return_artifact "$source_card_usage_pipe_string_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected source-card usage string repair to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_tu_explanation_good="$TEMP_STATE_DIR/source-card-tu-explanation-good.json"
cat >"$source_card_tu_explanation_good" <<'SOURCE_CARD_TU_EXPLANATION_GOOD'
[
  {
    "id": "es-bue-card-03-001",
    "setId": "es-bue-card-03",
    "teachingOrder": 1,
    "lemma": "vos",
    "display": "vos",
    "english": "you (informal, voseo)",
    "pos": "pronoun",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Voseo",
    "topicTags": ["voseo", "pronombre"],
    "cityTags": ["diario"],
    "grammarNote": "Vos replaces tú in informal Buenos Aires speech.",
    "dialectNote": "Typical in Buenos Aires.",
    "example": "¿Vos venís al café?",
    "example_en": "Are you coming to the cafe?",
    "usage": ["Usá <target>vos</target> con pares.", "Escuchá vos en conversaciones informales.", "Es común en la ciudad."]
  }
]
SOURCE_CARD_TU_EXPLANATION_GOOD
validate_return_artifact "$source_card_tu_explanation_good" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected explanatory tú mention in voseo source-card artifact to pass validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
source_card_bad="$TEMP_STATE_DIR/source-card-bad.json"
cat >"$source_card_bad" <<'SOURCE_CARD_BAD'
[
  {
    "id": "es-bue-card-01-001",
    "setId": "es-bue-card-01",
    "teachingOrder": 1,
    "lemma": "Polacas",
    "display": "Polacas",
    "english": "Hello",
    "pos": "interjection",
    "stage": "beginner",
    "register": "informal-voseo",
    "topic": "Saludos",
    "topicTags": ["saludos", "básico"],
    "cityTags": ["diario"],
    "grammarNote": "Funciona como saludo simple.",
    "dialectNote": "Neutral in Buenos Aires.",
    "example": "Polacas, ¿cómo andás esta mañana?",
    "example_en": "Hello, how are you this morning?",
    "usage": ["Usá <target>Polacas</target> al empezar una charla.", "Sirve con conocidos y desconocidos.", "Es breve y seguro."]
  }
]
SOURCE_CARD_BAD
validate_return_artifact "$source_card_bad" "$source_card_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" != "failed" || "${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}" != *"suspicious"* ]]; then
  fail "expected lean source-card validation to reject suspicious invented greeting terms"
fi
resume_plan="$TEMP_STATE_DIR/resume-plan.json"
cat >"$resume_plan" <<'RESUME_JSON'
{
  "resume_step": "step-03",
  "steps": [
    {"id": "step-01", "status": "completed"},
    {"id": "step-02", "status": "completed"},
    {"id": "step-03", "status": "running"},
    {"id": "step-04", "status": "pending"},
    {"id": "step-05", "status": "pending"}
  ]
}
RESUME_JSON
if [[ "$(orchestrated_resume_index_for_plan "$resume_plan" "step-03" "5")" != "3" ]]; then
  fail "expected resume index to derive from resume_step when resume_step_index is missing"
fi
resume_plan_with_stale_index="$TEMP_STATE_DIR/resume-plan-stale-index.json"
cat >"$resume_plan_with_stale_index" <<'RESUME_JSON'
{
  "resume_step": "step-03",
  "resume_step_index": 1,
  "steps": [
    {"id": "step-01", "status": "completed"},
    {"id": "step-02", "status": "completed"},
    {"id": "step-03", "status": "running"},
    {"id": "step-04", "status": "pending"},
    {"id": "step-05", "status": "pending"}
  ]
}
RESUME_JSON
if [[ "$(orchestrated_resume_index_for_plan "$resume_plan_with_stale_index" "step-03" "5")" != "3" ]]; then
  fail "expected resume_step to win over stale resume_step_index"
fi
unset ONLYMACS_PLAN_FILE_PATH ONLYMACS_PLAN_COMPILED_PROMPT ONLYMACS_RESOLVED_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT ONLYMACS_PLAN_FILE_STEP_COUNT ONLYMACS_PLAN_USER_PROMPT
ONLYMACS_EXECUTION_MODE="auto"

auto_plan_dir="$TEMP_STATE_DIR/auto-plan-run"
mkdir -p "$auto_plan_dir"
ONLYMACS_CURRENT_RETURN_DIR="$auto_plan_dir"
activate_auto_plan_for_prompt "$large_prompt"
if [[ ! -f "$auto_plan_dir/plan.draft.md" ]]; then
  fail "expected large unplanned prompt to create a draft plan"
fi
if [[ "$(orchestrated_step_count "$large_prompt")" != "4" ]]; then
  fail "expected auto-created draft plan to drive a four-step orchestration"
fi
if [[ "$(orchestrated_expected_filename "$large_prompt" 1 4)" != "requirements-and-contract.md" ]]; then
  fail "expected auto-created plan step 1 filename"
fi
mkdir -p "$auto_plan_dir/steps/step-01/files"
printf 'accepted requirements' >"$auto_plan_dir/steps/step-01/files/requirements-and-contract.md"
step_prompt="$(orchestrated_compile_step_prompt "$large_prompt" 2 4 "draft-slice-01.md")"
if [[ "$step_prompt" != *"Previous completed step artifacts:"* || "$step_prompt" != *"accepted requirements"* ]]; then
  fail "expected later plan-file steps to include prior artifact excerpts"
fi
unset ONLYMACS_CURRENT_RETURN_DIR ONLYMACS_PLAN_FILE_PATH ONLYMACS_PLAN_COMPILED_PROMPT ONLYMACS_RESOLVED_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT ONLYMACS_PLAN_FILE_STEP_COUNT ONLYMACS_PLAN_USER_PROMPT

large_js_prompt='Create one self-contained JavaScript file named vietnamese-learning-lab.js with exactly 120 entries and a CLI.'
ONLYMACS_CURRENT_RETURN_DIR="$TEMP_STATE_DIR/large-js-run"
mkdir -p "$ONLYMACS_CURRENT_RETURN_DIR"
activate_auto_plan_for_prompt "$large_js_prompt"
if [[ -f "$ONLYMACS_CURRENT_RETURN_DIR/plan.draft.md" ]]; then
  fail "expected large exact JavaScript artifacts to keep the specialized chunk assembler instead of auto-plan"
fi
unset ONLYMACS_CURRENT_RETURN_DIR ONLYMACS_PLAN_FILE_PATH ONLYMACS_PLAN_COMPILED_PROMPT ONLYMACS_RESOLVED_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT ONLYMACS_PLAN_FILE_STEP_COUNT ONLYMACS_PLAN_USER_PROMPT

public_status='{"runtime":{"active_swarm_id":"swarm-public"},"swarms":[{"id":"swarm-public","name":"OnlyMacs Public","visibility":"public"}]}'
policy="$(evaluate_file_access_policy "balanced" "review my code in this repo" "$public_status")"
if [[ "$policy" != "block_public" ]]; then
  fail "expected public swarm file-bound request to be blocked"
fi

private_status='{"runtime":{"active_swarm_id":"swarm-alpha"},"swarms":[{"id":"swarm-alpha","name":"Friends","visibility":"private"}]}'
policy="$(evaluate_file_access_policy "balanced" "review my code in this repo" "$private_status")"
if [[ "$policy" != "allow_private" ]]; then
  fail "expected private swarm file-bound request to be allowed"
fi

policy="$(evaluate_file_access_policy "local-first" "review my code in this repo" "$public_status")"
if [[ "$policy" != "allow_local" ]]; then
  fail "expected local-first file-bound request to stay local"
fi

sensitive_plan='{"requested_agents":1,"admitted_agents":1,"warnings":["This request looks sensitive and the current route can leave your trusted Macs."]}'
if ! needs_confirmation "$sensitive_plan"; then
  fail "expected sensitive warning to require confirmation"
fi

premium_plan='{"requested_agents":1,"admitted_agents":1,"warnings":["This request looks lightweight for a scarce premium or beast-capacity slot."]}'
if ! needs_confirmation "$premium_plan"; then
  fail "expected premium misuse warning to require confirmation"
fi

safe_plan='{"requested_agents":1,"admitted_agents":1,"warnings":[]}'
if needs_confirmation "$safe_plan"; then
  fail "did not expect simple one-agent plan without warnings to require confirmation"
fi

if confirm_chat_launch "coder" "review this api key leak and secret rotation plan"; then
  fail "expected sensitive swarm chat to require confirmation in non-interactive mode"
fi

if confirm_chat_launch "coder" "summarize these files for me"; then
  fail "expected lightweight premium chat to require confirmation in non-interactive mode"
fi

if ! confirm_chat_launch "trusted-only" "review this api key leak and secret rotation plan"; then
  fail "did not expect trusted-only sensitive chat to require confirmation"
fi

if ! confirm_chat_launch "balanced" "review this patch for a race condition"; then
  fail "did not expect normal coding chat to require confirmation"
fi

set_activity_context "go balanced" "go balanced" "swarm" "qwen2.5-coder:32b"
record_current_activity "launched" "Started a new OnlyMacs swarm." "session-123" "running"
activity_path="$(activity_log_path)"
if [[ ! -f "$activity_path" ]]; then
  fail "expected activity log to be written"
fi
if [[ "$(jq -r '.command_label' <"$activity_path")" != "go balanced" ]]; then
  fail "expected activity log command label"
fi
if [[ "$(jq -r '.session_status' <"$activity_path")" != "running" ]]; then
  fail "expected activity log session status"
fi
if [[ "$(jq -r '.detail' <"$activity_path")" != "Started a new OnlyMacs swarm." ]]; then
  fail "expected activity log detail"
fi

artifact_content="$(mktemp)"
artifact_headers="$(mktemp)"
printf '```javascript\nconsole.log("hi")\n```\n' >"$artifact_content"
cat >"$artifact_headers" <<'HEADERS'
HTTP/1.1 200 OK
X-OnlyMacs-Session-ID: sess-abc
X-OnlyMacs-Resolved-Model: qwen2.5-coder:32b
X-OnlyMacs-Provider-ID: provider-charles
X-OnlyMacs-Provider-Name: Charles
X-OnlyMacs-Owner-Member-Name: Charles
X-OnlyMacs-Swarm-ID: swarm-public
X-OnlyMacs-Route-Scope: swarm
HEADERS
old_json_mode="${ONLYMACS_JSON_MODE:-0}"
ONLYMACS_JSON_MODE=1
(
  cd "$TEMP_STATE_DIR"
  write_chat_return_artifact "$artifact_content" "$artifact_headers" "remote-first" "Create a JavaScript file named vietnamese-flashcards.js"
)
ONLYMACS_JSON_MODE="$old_json_mode"
saved_artifact="$(find "$TEMP_STATE_DIR/onlymacs/inbox" -name vietnamese-flashcards.js -print -quit)"
if [[ -z "$saved_artifact" ]]; then
  fail "expected returned chat artifact to be saved with requested filename"
fi
if [[ "$(cat "$saved_artifact")" != 'console.log("hi")' ]]; then
  fail "expected saved artifact to contain the unfenced code block"
fi
saved_run_dir="$(dirname "$(dirname "$saved_artifact")")"
saved_manifest="$saved_run_dir/result.json"
if [[ "$(jq -r '.model' <"$saved_manifest")" != "qwen2.5-coder:32b" ]]; then
  fail "expected artifact manifest to include resolved model"
fi
if [[ "$(jq -r '.status' <"$saved_run_dir/status.json")" != "completed" ]]; then
  fail "expected returned chat status to be completed"
fi
if [[ "$(jq -r '.artifact_path' <"$TEMP_STATE_DIR/onlymacs/inbox/latest.json")" != "$saved_artifact" ]]; then
  fail "expected latest inbox pointer to reference saved artifact"
fi
if [[ ! -f "$saved_run_dir/RESULT.md" ]]; then
  fail "expected returned chat inbox to include RESULT.md"
fi

set_def_artifact="$TEMP_STATE_DIR/setDefinitions.json"
cat >"$set_def_artifact" <<'JSON'
{
  "setDefinitions": {
    "modules": {
      "vocab": [
        {"id": "es-bue-vocab-beg-01", "title": "Greetings"},
        {"id": "es-bue-vocab-beg-02", "title": "Food"}
      ],
      "sentences": [
        {"id": "es-bue-sent-01", "title": "Greetings"},
        {"id": "es-bue-sent-02", "title": "Food"}
      ],
      "lessons": [
        {"id": "es-bue-lesson-01", "title": "Greetings"},
        {"id": "es-bue-lesson-02", "title": "Food"}
      ],
      "alphabet": [
        {"id": "es-bue-alpha-01", "title": "Sounds"}
      ]
    }
  }
}
JSON
ONLYMACS_PLAN_FILE_PATH="$TEMP_STATE_DIR/content-pipeline.md"
ONLYMACS_PLAN_FILE_CONTENT=$'# OnlyMacs Plan\n\n## Step 1 - Set Definitions\nOutput: setDefinitions.json\n\nCreate a compact setDefinitions object for groups 01-02 and alphabet group 01 only. Include modules.vocab, modules.sentences, modules.lessons, and modules.alphabet arrays.\n\n## Step 4 - Lesson Groups 01-02\nOutput: lessons-groups-01-02.json\n\nCreate exactly 2 lesson items.'
compiled_step_prompt="$(orchestrated_compile_plan_file_step_prompt "$ONLYMACS_PLAN_FILE_CONTENT" 1 5 "setDefinitions.json")"
compiled_current_step="$(printf '%s' "$compiled_step_prompt" | perl -0777 -ne 'if (/Current step:\n(.*?)\nPrevious completed step artifacts:/s) { print $1 }')"
if [[ "$compiled_current_step" != *"## Step 1 - Set Definitions"* ]]; then
  fail "expected plan-file step prompt to include the current step"
fi
if [[ "$compiled_current_step" == *"## Step 4 - Lesson Groups 01-02"* ]]; then
  fail "expected plan-file current-step scope to exclude later steps"
fi
if [[ "$compiled_step_prompt" == *"## Step 4 - Lesson Groups 01-02"* ]]; then
  fail "expected plan-file step prompt not to embed the full plan"
fi
plan_validation_prompt="$(orchestrated_validation_prompt "$ONLYMACS_PLAN_FILE_CONTENT" 1 "full prompt contains later exact counts")"
if [[ "$plan_validation_prompt" != *"## Step 1 - Set Definitions"* || "$plan_validation_prompt" == *"## Step 4 - Lesson Groups 01-02"* ]]; then
  fail "expected plan-file validation prompt to contain only the current step"
fi
if [[ -n "$(prompt_exact_count_requirement "$plan_validation_prompt" || true)" ]]; then
  fail "expected plan-file validation prompt to ignore later-step exact counts"
fi
validate_return_artifact "$set_def_artifact" "$plan_validation_prompt"
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected setDefinitions artifact to pass generic current-step validation, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi
unset ONLYMACS_PLAN_FILE_PATH ONLYMACS_PLAN_FILE_CONTENT

wrapped_lessons_artifact="$TEMP_STATE_DIR/wrapped-lessons.json"
printf '{"lessons":[{"id":"a"},{"id":"b"}]}\n' >"$wrapped_lessons_artifact"
if [[ "$(artifact_semantic_entry_count "$wrapped_lessons_artifact")" != "2" ]]; then
  fail "expected generic JSON wrapper semantic count to use the lessons array length"
fi
validate_return_artifact "$wrapped_lessons_artifact" "Create exactly 2 lesson items."
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected wrapped JSON array artifact to satisfy exact-count validation"
fi

grouped_vocab_artifact="$TEMP_STATE_DIR/grouped-vocab.json"
printf '{"vocabSets":{"group-01":[{"id":"a"},{"id":"b"}],"group-02":[{"id":"c"},{"id":"d"}]}}\n' >"$grouped_vocab_artifact"
if [[ "$(artifact_semantic_entry_count "$grouped_vocab_artifact")" != "4" ]]; then
  fail "expected grouped JSON arrays to count nested item arrays"
fi
validate_return_artifact "$grouped_vocab_artifact" "Create exactly 4 vocab items total."
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected grouped JSON array artifact to satisfy exact-count validation"
fi

spanish_todo_artifact="$TEMP_STATE_DIR/spanish-todo.json"
printf '[{"text":"Buen día, ¿todo bien?"}]\n' >"$spanish_todo_artifact"
validate_return_artifact "$spanish_todo_artifact" "Create exactly 1 sentence item."
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected Spanish natural-language todo to avoid TODO placeholder validation"
fi

sentence_schema_artifact="$TEMP_STATE_DIR/sentence-schema.json"
cat >"$sentence_schema_artifact" <<'JSON'
[
  {
    "id": "es-bue-sent-01-001",
    "setId": "es-bue-sent-01",
    "text": "Hola, ¿cómo andás?",
    "translationsByLocale": {"en":"Hello, how are you?","de":"Hallo, wie geht's?","fr":"Salut, comment ça va ?","it":"Ciao, come va?","ko":"안녕, 어떻게 지내?"},
    "register": "informal-voseo",
    "scenarioTags": ["greeting"],
    "cityContextTags": ["buenos-aires"],
    "translationMode": "natural",
    "supportedPromptModes": ["native","listen-only"],
    "defaultPromptMode": "native",
    "segmentation": ["Hola","¿cómo andás?"],
    "frequencyBand": "high",
    "patternType": "greeting",
    "teachingOrder": 1,
    "source": {"packSlug":"learn-spanish-buenos-aires","languageId":"es-AR","sourcePrefix":"es-bue"},
    "highlights": {"en.viet":["Hola"],"en.trans":["Hello"]},
    "usage": "casual greeting"
  }
]
JSON
validate_return_artifact "$sentence_schema_artifact" "Create exactly 1 sentence item with locale translations, cityContextTags, and highlights.en.viet/trans."
if [[ "${ONLYMACS_RETURN_VALIDATION_STATUS:-}" == "failed" ]]; then
  fail "expected sentence schema validation to accept dotted highlight keys, got ${ONLYMACS_RETURN_VALIDATION_MESSAGE:-}"
fi

bridge_error_output="$(mktemp)"
if (
  request_json() {
    ONLYMACS_LAST_HTTP_STATUS=""
    ONLYMACS_LAST_HTTP_BODY=""
    ONLYMACS_LAST_CURL_ERROR="Unable to reach the local OnlyMacs bridge at http://127.0.0.1:4318. Open the OnlyMacs app and try again."
    return 1
  }
  resolve_prompt_with_file_access "remote-first" "write a tiny script"
) >/dev/null 2>"$bridge_error_output"; then
  fail "expected bridge-down prompt resolution to fail before streaming"
fi
case "$(cat "$bridge_error_output")" in
  *"OnlyMacs could not connect."*"open the OnlyMacs app"*)
    ;;
  *)
    fail "expected bridge-down prompt resolution to show app-open guidance"
    ;;
esac

request_policy_classify() {
  local prompt="${2:-}"
  ONLYMACS_REQUEST_POLICY_DECISION=""
  ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES="false"
  ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND=""
  ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET=""
  ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION=""

  case "$prompt" in
    "brainstorm three launch taglines for OnlyMacs")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="balanced"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like a prompt-only request, so OnlyMacs will use the standard chat path."
      ;;
    "review the pipeline docs in this project")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="trusted-only"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like it needs repo or file context, so OnlyMacs will keep it on a trusted route and ask for approval before exporting files."
      ;;
    "review the .env and config files in this project")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="local-first"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks sensitive, so OnlyMacs recommends keeping it on This Mac."
      ;;
    "make a plan for refactoring this repo and cleaning up the tests")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="plan"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="trusted-only"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like planning work with repo or file context, so OnlyMacs will start with a trusted plan."
      ;;
    "split this refactor into parallel workstreams")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="plan"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="wide"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like multi-agent work, so OnlyMacs will plan a wider swarm first."
      ;;
    "start parallel workstreams to refactor this repo")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="go"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="wide"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like multi-agent work and you asked to run it, so OnlyMacs will launch a wider swarm."
      ;;
    "estimate how many agents this migration needs before you start")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="plan"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="balanced"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This sounds like planning or estimation work, so OnlyMacs will start with a plan."
      ;;
    "generate 10 new json files using the content pipeline in this project")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="trusted-only"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like it needs repo or file context, so OnlyMacs will keep it on a trusted route and ask for approval before exporting files."
      ;;
    "edit the auth helper in this repo so it stops returning a dev token fallback")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="local-first"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks sensitive, so OnlyMacs recommends keeping it on This Mac."
      ;;
    "keep this on this mac while brainstorming taglines")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="balanced"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like a prompt-only request, so OnlyMacs will use the standard chat path."
      ;;
    "use the exact qwen2.5-coder:32b model for this audit")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="balanced"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like a prompt-only request, so OnlyMacs will use the standard chat path."
      ;;
    "Execute the plan, save all returned work, and report exact saved file paths.")
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="balanced"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like a prompt-only request, so OnlyMacs will use the standard chat path."
      ;;
    "Create one JSON artifact named cards-source-model-benchmark.json. Return only a strict JSON array inside artifact markers.")
      ONLYMACS_REQUEST_POLICY_DECISION="public_export_required"
      ONLYMACS_REQUEST_POLICY_REQUIRES_LOCAL_FILES="false"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_COMMAND="chat"
      ONLYMACS_REQUEST_POLICY_SUGGESTED_PRESET="balanced"
      ONLYMACS_REQUEST_POLICY_ROUTING_EXPLANATION="This looks like generated output, so OnlyMacs should not open file approval."
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

rm -f "$(workspace_defaults_path)"

generated_artifact_prompt="Create one JSON artifact named cards-source-model-benchmark.json. Return only a strict JSON array inside artifact markers."
if ! resolve_prompt_with_file_access "qwen2.5-coder:32b" "$generated_artifact_prompt"; then
  fail "expected generated JSON artifact prompt to bypass public file approval even when coordinator policy is conservative"
fi
if [[ "${ONLYMACS_RESOLVED_PROMPT:-}" != "$generated_artifact_prompt" ]]; then
  fail "expected generated JSON artifact prompt to pass through unchanged"
fi
clear_resolved_artifact

artifact_script_prompt="Create a .js file that will translate a large JSON file to english"
assert_intent "$artifact_script_prompt" \
  "chat best-available (artifact inbox)" \
  "chat" "$artifact_script_prompt"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" ]]; then
  fail "expected generated script prompt to default to inbox write mode"
fi
if [[ "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected generated script prompt to default to extended execution"
fi
unset ONLYMACS_CONTEXT_READ_MODE ONLYMACS_CONTEXT_WRITE_MODE ONLYMACS_CONTEXT_ALLOW_TESTS ONLYMACS_CONTEXT_ALLOW_INSTALL
ONLYMACS_EXECUTION_MODE="auto"

if prompt_looks_file_bound "$artifact_script_prompt"; then
  fail "did not expect reusable generated script prompt to require local file approval"
fi

if ! prompt_looks_file_bound "Translate this local JSON file to English: ./data/messages.json"; then
  fail "expected explicit local JSON path prompt to require file approval"
fi

assert_intent_with_reason "brainstorm three launch taglines for OnlyMacs" \
  "chat best-available" \
  "This looks like a prompt-only request, so OnlyMacs will use the standard chat path." \
  "chat" "brainstorm three launch taglines for OnlyMacs"

assert_intent "use public swarm capacity for this public benchmark" \
  "chat remote-first" \
  "chat" "remote-first" "use public swarm capacity for this public benchmark"

assert_intent "use remote capacity for this public copywriting task" \
  "chat remote-first" \
  "chat" "remote-first" "use remote capacity for this public copywriting task"

assert_intent "run this on another Mac, not mine" \
  "chat remote-first" \
  "chat" "remote-first" "run this on another Mac, not mine"

assert_intent "use a beast machine for this benchmark" \
  "chat remote-first" \
  "chat" "remote-first" "use a beast machine for this benchmark"

assert_intent "please route this away from this Mac" \
  "chat remote-first" \
  "chat" "remote-first" "please route this away from this Mac"

assert_intent "do not run this on this laptop" \
  "chat remote-first" \
  "chat" "remote-first" "do not run this on this laptop"

assert_intent "public workers are okay for this launch copy" \
  "chat remote-first" \
  "chat" "remote-first" "public workers are okay for this launch copy"

assert_intent "prefer a non-local Mac for this public benchmark" \
  "chat remote-first" \
  "chat" "remote-first" "prefer a non-local Mac for this public benchmark"

assert_intent "do not use the local Mac for this" \
  "chat remote-first" \
  "chat" "remote-first" "do not use the local Mac for this"

assert_intent "use my private swarm for this review" \
  "chat trusted-only" \
  "chat" "trusted-only" "use my private swarm for this review"

assert_intent "use owned idle capacity for this batch job" \
  "chat offload-max" \
  "chat" "offload-max" "use owned idle capacity for this batch job"

assert_intent "keep this on trusted machines only" \
  "chat trusted-only" \
  "chat" "trusted-only" "keep this on trusted machines only"

assert_intent "no public models for this private code review" \
  "chat trusted-only" \
  "chat" "trusted-only" "no public models for this private code review"

assert_intent "do not use stranger Macs for this review" \
  "chat trusted-only" \
  "chat" "trusted-only" "do not use stranger Macs for this review"

assert_intent "trusted friends only for this private review" \
  "chat trusted-only" \
  "chat" "trusted-only" "trusted friends only for this private review"

assert_intent "do not send to public swarm" \
  "chat trusted-only" \
  "chat" "trusted-only" "do not send to public swarm"

assert_intent "only approved Macs for this review" \
  "chat trusted-only" \
  "chat" "trusted-only" "only approved Macs for this review"

assert_intent "never leave this laptop" \
  "chat local-first" \
  "chat" "local-first" "never leave this laptop"

assert_intent "do not send this over the network" \
  "chat local-first" \
  "chat" "local-first" "do not send this over the network"

assert_intent "do not upload this anywhere" \
  "chat local-first" \
  "chat" "local-first" "do not upload this anywhere"

assert_intent "don't spend paid tokens on this" \
  "chat offload-max" \
  "chat" "offload-max" "don't spend paid tokens on this"

assert_intent "cheapest route for this non-secret summary" \
  "chat offload-max" \
  "chat" "offload-max" "cheapest route for this non-secret summary"

assert_intent "use token-free capacity for this rewrite" \
  "chat offload-max" \
  "chat" "offload-max" "use token-free capacity for this rewrite"

assert_intent "don't burn credits on this task" \
  "chat offload-max" \
  "chat" "offload-max" "don't burn credits on this task"

assert_intent "avoid using credits" \
  "chat offload-max" \
  "chat" "offload-max" "avoid using credits"

assert_intent "Write a Node.js CLI tool in a single file" \
  "chat best-available (artifact inbox)" \
  "chat" "Write a Node.js CLI tool in a single file"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected single-file CLI tool prompt to default to extended inbox artifact mode"
fi

assert_intent "Create a reusable tool to convert JSON to CSV" \
  "chat best-available (artifact inbox)" \
  "chat" "Create a reusable tool to convert JSON to CSV"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected reusable-tool prompt to default to extended inbox artifact mode"
fi

assert_intent "Write a Go command-line utility" \
  "chat best-available (artifact inbox)" \
  "chat" "Write a Go command-line utility"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected Go command-line utility prompt to default to extended inbox artifact mode"
fi

assert_intent "Build a small standalone web app" \
  "chat best-available (artifact inbox)" \
  "chat" "Build a small standalone web app"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected standalone web app prompt to default to extended inbox artifact mode"
fi

assert_intent "Produce a Ruby script" \
  "chat best-available (artifact inbox)" \
  "chat" "Produce a Ruby script"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected Ruby script prompt to default to extended inbox artifact mode"
fi

assert_intent "Generate a YAML file" \
  "chat best-available (artifact inbox)" \
  "chat" "Generate a YAML file"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected YAML file prompt to default to extended inbox artifact mode"
fi

assert_intent "Create a Dockerfile" \
  "chat best-available (artifact inbox)" \
  "chat" "Create a Dockerfile"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected Dockerfile prompt to default to extended inbox artifact mode"
fi

assert_intent "Save this as translate-json.js" \
  "chat best-available (artifact inbox)" \
  "chat" "Save this as translate-json.js"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_EXECUTION_MODE:-auto}" != "extended" ]]; then
  fail "expected save-as JavaScript prompt to default to extended inbox artifact mode"
fi

assert_intent "Read ../fixtures/config.yaml and summarize it" \
  "chat trusted-only" \
  "chat" "trusted-only" "Read ../fixtures/config.yaml and summarize it"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" ]]; then
  fail "expected fixture path read to stay in inbox mode, not staged writes"
fi

assert_intent "process this uploaded file and summarize it" \
  "chat trusted-only" \
  "chat" "trusted-only" "process this uploaded file and summarize it"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" ]]; then
  fail "expected uploaded file prompt to be treated as file-aware inbox work"
fi

assert_intent "process this spreadsheet and summarize the outliers" \
  "chat trusted-only" \
  "chat" "trusted-only" "process this spreadsheet and summarize the outliers"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" ]]; then
  fail "expected spreadsheet prompt to be treated as file-aware inbox work"
fi

assert_intent "look at README.md" \
  "chat trusted-only" \
  "chat" "trusted-only" "look at README.md"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" ]]; then
  fail "expected README prompt to be treated as file-aware inbox work"
fi

assert_intent "open src/App.tsx and summarize" \
  "chat trusted-only" \
  "chat" "trusted-only" "open src/App.tsx and summarize"
if [[ "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" ]]; then
  fail "expected source path prompt to be treated as file-aware inbox work"
fi

assert_intent "Apply a fix to this branch and run the test suite" \
  "chat trusted-only" \
  "chat" "trusted-only" "Apply a fix to this branch and run the test suite"
if [[ "${ONLYMACS_CONTEXT_READ_MODE:-}" != "git_backed_checkout" || "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "staged_apply" || "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" != "1" ]]; then
  fail "expected branch fix/test prompt to use git, staged writes, and test execution"
fi

assert_intent "Run tests for this project and tell me failures" \
  "chat trusted-only" \
  "chat" "trusted-only" "Run tests for this project and tell me failures"
if [[ "${ONLYMACS_CONTEXT_READ_MODE:-}" != "git_backed_checkout" || "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" != "1" ]]; then
  fail "expected run-tests report prompt to use git, inbox writes, and test execution"
fi

assert_intent "modify this codebase to fix the failing login test" \
  "chat trusted-only" \
  "chat" "trusted-only" "modify this codebase to fix the failing login test"
if [[ "${ONLYMACS_CONTEXT_READ_MODE:-}" != "git_backed_checkout" || "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "staged_apply" || "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" != "1" ]]; then
  fail "expected codebase failing-test fix prompt to use git, staged writes, and test execution"
fi

assert_intent "check this branch test failures without patching" \
  "chat trusted-only" \
  "chat" "trusted-only" "check this branch test failures without patching"
if [[ "${ONLYMACS_CONTEXT_READ_MODE:-}" != "git_backed_checkout" || "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "inbox" || "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" != "1" ]]; then
  fail "expected readonly branch test prompt to use git, inbox writes, and test execution"
fi

assert_intent "repair the tests in this repo" \
  "chat trusted-only" \
  "chat" "trusted-only" "repair the tests in this repo"
if [[ "${ONLYMACS_CONTEXT_READ_MODE:-}" != "git_backed_checkout" || "${ONLYMACS_CONTEXT_WRITE_MODE:-}" != "staged_apply" || "${ONLYMACS_CONTEXT_ALLOW_TESTS:-0}" != "1" ]]; then
  fail "expected repo test repair prompt to use git, staged writes, and test execution"
fi

assert_intent "show inbox latest" \
  "inbox latest" \
  "inbox" "latest"

assert_intent "open the latest inbox result" \
  "open latest" \
  "open" "latest"

assert_intent "apply latest result" \
  "apply latest" \
  "apply" "latest"

assert_intent "make a support bundle for latest" \
  "support-bundle latest" \
  "support-bundle" "latest"

assert_intent "run diagnostics for latest" \
  "diagnostics latest" \
  "diagnostics" "latest"

assert_intent "status of the latest result" \
  "status latest" \
  "status" "latest"

assert_intent "follow the latest run live" \
  "watch latest" \
  "watch" "latest"

assert_intent "latest run status" \
  "status latest" \
  "status" "latest"

assert_intent "watch the newest run" \
  "watch latest" \
  "watch" "latest"

assert_intent "show report settings" \
  "report status" \
  "report" "status"

assert_intent "show runtime status" \
  "runtime" \
  "runtime"

assert_intent "list swarms" \
  "swarms" \
  "swarms"

assert_intent "what is sharing status" \
  "sharing" \
  "sharing"

ONLYMACS_PLAN_FILE_PATH="$TEMP_STATE_DIR/content-pipeline.md"
assert_intent "Execute the Buenos Aires content-pipeline plan file and save returned work under the OnlyMacs inbox" \
  "chat best-available" \
  "chat" "Execute the Buenos Aires content-pipeline plan file and save returned work under the OnlyMacs inbox"
unset ONLYMACS_PLAN_FILE_PATH

assert_intent_with_reason "review the pipeline docs in this project" \
  "chat trusted-only" \
  "This looks like it needs repo or file context, so OnlyMacs will keep it on a trusted route and ask for approval before exporting files." \
  "chat" "trusted-only" "review the pipeline docs in this project"

assert_intent_with_reason "review the .env and config files in this project" \
  "chat local-first" \
  "This looks sensitive, so OnlyMacs recommends keeping it on This Mac." \
  "chat" "local-first" "review the .env and config files in this project"

assert_intent_with_reason "edit the auth helper in this repo so it stops returning a dev token fallback" \
  "chat local-first" \
  "This looks sensitive, so OnlyMacs recommends keeping it on This Mac." \
  "chat" "local-first" "edit the auth helper in this repo so it stops returning a dev token fallback"

assert_intent_with_reason "make a plan for refactoring this repo and cleaning up the tests" \
  "plan trusted-only" \
  "This looks like planning work with repo or file context, so OnlyMacs will start with a trusted plan." \
  "plan" "trusted-only" "make a plan for refactoring this repo and cleaning up the tests"

assert_intent_with_reason "split this refactor into parallel workstreams" \
  "plan wide" \
  "This looks like multi-agent work, so OnlyMacs will plan a wider swarm first." \
  "plan" "wide" "split this refactor into parallel workstreams"

assert_intent_with_reason "start parallel workstreams to refactor this repo" \
  "go wide" \
  "This looks like multi-agent work and you asked to run it, so OnlyMacs will launch a wider swarm." \
  "go" "wide" "start parallel workstreams to refactor this repo"

assert_intent_with_reason "estimate how many agents this migration needs before you start" \
  "plan balanced" \
  "This sounds like planning or estimation work, so OnlyMacs will start with a plan." \
  "plan" "balanced" "estimate how many agents this migration needs before you start"

assert_intent_with_reason "generate 10 new json files using the content pipeline in this project" \
  "chat trusted-only" \
  "This looks like it needs repo or file context, so OnlyMacs will keep it on a trusted route and ask for approval before exporting files." \
  "chat" "trusted-only" "generate 10 new json files using the content pipeline in this project"

assert_intent_with_reason "keep this on this mac while brainstorming taglines" \
  "chat local-first" \
  "This looks like a prompt-only request, so OnlyMacs will use the standard chat path." \
  "chat" "local-first" "keep this on this mac while brainstorming taglines"

assert_intent_with_reason "use the exact qwen2.5-coder:32b model for this audit" \
  "chat exact-model qwen2.5-coder:32b" \
  "This looks like a prompt-only request, so OnlyMacs will use the standard chat path." \
  "chat" "qwen2.5-coder:32b" "use the exact qwen2.5-coder:32b model for this audit"

assert_intent_with_reason "Execute the plan, save all returned work, and report exact saved file paths." \
  "chat best-available" \
  "This looks like a prompt-only request, so OnlyMacs will use the standard chat path." \
  "chat" "Execute the plan, save all returned work, and report exact saved file paths."

mkdir -p "$TEMP_STATE_DIR/OnlyMacs.app"
ONLYMACS_APP_PATH="$TEMP_STATE_DIR/OnlyMacs.app"
open() {
  if [[ "${1:-}" == "-a" && "${2:-}" == "$ONLYMACS_APP_PATH" ]]; then
    (
      sleep 1
      printf '{"id":"mock-request"}\n' >"$(file_access_claim_path "mock-request")"
    ) &
    return 0
  fi
  return 0
}

if ! open_file_access_request_ui "mock-request"; then
  fail "expected launcher handshake to succeed once the app writes a claim"
fi

unset -f open

job_worker_run_dir="$TEMP_STATE_DIR/job-worker-run"
job_worker_complete_payload="$TEMP_STATE_DIR/job-worker-complete.json"
(
  request_json() {
    local method="${1:-}" path="${2:-}" payload="${3:-}"
    ONLYMACS_LAST_HTTP_STATUS="200"
    case "${method} ${path}" in
      "POST /admin/v1/jobs/job-000123/tickets/claim")
        ONLYMACS_LAST_HTTP_BODY='{"status":"claimed","job_id":"job-000123","tickets":[{"id":"ticket-app","job_id":"job-000123","kind":"file_create","title":"Create app shell","target_files":["src/App.tsx"],"lease_id":"lease-abc","required_capability":"frontend"}],"job":{"id":"job-000123","invocation":"onlymacs --go-wide build app","prompt_preview":"build app","context_policy":{"context_read_mode":"full_project_folder","context_write_mode":"staged_apply"}}}'
        ;;
      "POST /admin/v1/jobs/job-000123/tickets/ticket-app/complete")
        printf '%s' "$payload" >"$job_worker_complete_payload"
        ONLYMACS_LAST_HTTP_BODY='{"status":"updated","job":{"id":"job-000123"}}'
        ;;
      *)
        ONLYMACS_LAST_HTTP_STATUS="404"
        ONLYMACS_LAST_HTTP_BODY='{"error":{"message":"unexpected worker mock request"}}'
        return 1
        ;;
    esac
    return 0
  }
  run_orchestrated_chat() {
    ONLYMACS_CURRENT_RETURN_DIR="$job_worker_run_dir"
    mkdir -p "$job_worker_run_dir/files"
    printf 'worker result body\n' >"$job_worker_run_dir/RESULT.md"
    printf 'export default function App() { return null; }\n' >"$job_worker_run_dir/files/App.tsx"
    jq -n --arg inbox "$job_worker_run_dir" '{run_id:"worker-run",status:"completed",provider_name:"Kevin",model:"local-test",inbox:$inbox,artifacts:[$inbox + "/files/App.tsx"],artifact_path:($inbox + "/files/App.tsx")}' >"$job_worker_run_dir/status.json"
    return 0
  }
  ONLYMACS_JSON_MODE=1
  onlymacs_jobs_work_loop --job job-000123 --once --max 1 --heartbeat-seconds 99 >/dev/null
) || fail "expected jobs work to claim, execute, and complete a model ticket"
if ! jq -e '.lease_id == "lease-abc" and .metadata.executor == "onlymacs-cli jobs work" and .artifact_bundle.schema == "onlymacs.artifact_bundle.v1" and .output_bytes > 0 and .output_tokens_estimate > 0' "$job_worker_complete_payload" >/dev/null; then
  fail "expected jobs work complete payload to include lease, metadata, artifact bundle, and output estimates"
fi

job_worker_validator_payload="$TEMP_STATE_DIR/job-worker-validator.json"
(
  request_json() {
    local method="${1:-}" path="${2:-}" payload="${3:-}"
    ONLYMACS_LAST_HTTP_STATUS="200"
    case "${method} ${path}" in
      "POST /admin/v1/jobs/job-000124/tickets/claim")
        ONLYMACS_LAST_HTTP_BODY='{"status":"claimed","job_id":"job-000124","tickets":[{"id":"ticket-test","job_id":"job-000124","kind":"validator","title":"Run validator","validator_commands":["true"],"lease_id":"lease-test","required_capability":"validator"}],"job":{"id":"job-000124","invocation":"onlymacs jobs create","prompt_preview":"validate app","context_policy":{}}}'
        ;;
      "POST /admin/v1/jobs/job-000124/tickets/ticket-test/complete")
        printf '%s' "$payload" >"$job_worker_validator_payload"
        ONLYMACS_LAST_HTTP_BODY='{"status":"updated","job":{"id":"job-000124"}}'
        ;;
      *)
        ONLYMACS_LAST_HTTP_STATUS="404"
        ONLYMACS_LAST_HTTP_BODY='{"error":{"message":"unexpected validator worker mock request"}}'
        return 1
        ;;
    esac
    return 0
  }
  ONLYMACS_JSON_MODE=1
  run_jobs work --job job-000124 --once --allow-tests --heartbeat-seconds 99 >/dev/null
) || fail "expected jobs work --allow-tests to execute validator tickets"
if ! jq -e '.lease_id == "lease-test" and .validation_results[0].status == "passed" and .metadata.validation_results[0].command == "true"' "$job_worker_validator_payload" >/dev/null; then
  fail "expected validator worker to complete with validation results"
fi

printf 'onlymacs intent smoke tests passed.\n'
