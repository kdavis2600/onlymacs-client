#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  "$ROOT_DIR/scripts/stop-dev.sh" >/dev/null 2>&1 || true
}

trap cleanup EXIT

ONLYMACS_ENABLE_CANNED_CHAT=1 "$ROOT_DIR/scripts/make-dev.sh" >/dev/null

wait_for_url() {
  local url="$1"
  local attempts=0
  until curl -fsS "$url" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -gt 30 ]]; then
      echo "timed out waiting for $url" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_for_url "http://127.0.0.1:4319/health"
wait_for_url "http://127.0.0.1:4318/health"

ALPHA_POOL_RESPONSE="$(
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d '{"name":"Alpha Swarm"}' \
    http://127.0.0.1:4319/admin/v1/swarms
)"
ALPHA_POOL_ID="$(echo "$ALPHA_POOL_RESPONSE" | sed -E 's/.*"id":"([^"]+)".*/\1/')"

BETA_POOL_RESPONSE="$(
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d '{"name":"Beta Swarm"}' \
    http://127.0.0.1:4319/admin/v1/swarms
)"
BETA_POOL_ID="$(echo "$BETA_POOL_RESPONSE" | sed -E 's/.*"id":"([^"]+)".*/\1/')"

ALPHA_INVITE_RESPONSE="$(
  curl -fsS -X POST http://127.0.0.1:4319/admin/v1/swarms/"$ALPHA_POOL_ID"/invites
)"
ALPHA_INVITE_TOKEN="$(echo "$ALPHA_INVITE_RESPONSE" | sed -E 's/.*"invite_token":"([^"]+)".*/\1/')"

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"invite_token\":\"$ALPHA_INVITE_TOKEN\",\"member_id\":\"kevin-client\",\"member_name\":\"Kevin\",\"mode\":\"use\"}" \
  http://127.0.0.1:4319/admin/v1/swarms/join >/dev/null

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"provider\":{\"id\":\"charles-m5\",\"name\":\"Charles's Mac Studio\",\"swarm_id\":\"$ALPHA_POOL_ID\",\"status\":\"available\",\"modes\":[\"share\",\"both\"],\"slots\":{\"free\":2,\"total\":2},\"models\":[{\"id\":\"qwen2.5-coder:32b\",\"name\":\"Qwen2.5 Coder 32B\",\"slots_free\":2,\"slots_total\":2}]}}" \
  http://127.0.0.1:4319/admin/v1/providers/register >/dev/null

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"provider\":{\"id\":\"dana-m4\",\"name\":\"Dana's MacBook Pro\",\"swarm_id\":\"$BETA_POOL_ID\",\"status\":\"available\",\"modes\":[\"share\",\"both\"],\"slots\":{\"free\":1,\"total\":1},\"models\":[{\"id\":\"gemma4:26b\",\"name\":\"Gemma 4 26B\",\"slots_free\":1,\"slots_total\":1}]}}" \
  http://127.0.0.1:4319/admin/v1/providers/register >/dev/null

POOLS_OUTPUT="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/swarms
)"

echo "$POOLS_OUTPUT" | grep -q '"Alpha Swarm"'
echo "$POOLS_OUTPUT" | grep -q '"Beta Swarm"'

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"mode\":\"use\",\"active_swarm_id\":\"$ALPHA_POOL_ID\"}" \
  http://127.0.0.1:4318/admin/v1/runtime >/dev/null

STATUS_OUTPUT="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/status
)"

echo "$STATUS_OUTPUT" | grep -q "\"active_swarm_id\":\"$ALPHA_POOL_ID\""
echo "$STATUS_OUTPUT" | grep -q "Charles's Mac Studio"
if echo "$STATUS_OUTPUT" | grep -q "Dana's MacBook Pro"; then
  echo "beta provider leaked into alpha swarm status" >&2
  exit 1
fi

MODELS_OUTPUT="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/models
)"

echo "$MODELS_OUTPUT" | grep -q '"qwen2.5-coder:32b"'
echo "$MODELS_OUTPUT" | grep -q '"slots_free":2'
if echo "$MODELS_OUTPUT" | grep -q '"gemma4:26b"'; then
  echo "beta model leaked into alpha swarm models" >&2
  exit 1
fi

PREFLIGHT_OUTPUT="$(
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen2.5-coder:32b","max_providers":1}' \
    http://127.0.0.1:4318/admin/v1/preflight
)"

echo "$PREFLIGHT_OUTPUT" | grep -q '"available":true'
echo "$PREFLIGHT_OUTPUT" | grep -q '"resolved_model":"qwen2.5-coder:32b"'
echo "$PREFLIGHT_OUTPUT" | grep -q "Charles's Mac Studio"

RESERVE_OUTPUT="$(
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"qwen2.5-coder:32b\",\"swarm_id\":\"$ALPHA_POOL_ID\"}" \
    http://127.0.0.1:4319/admin/v1/sessions/reserve
)"

echo "$RESERVE_OUTPUT" | grep -q '"status":"reserved"'
echo "$RESERVE_OUTPUT" | grep -q '"slots_free":1'
echo "$RESERVE_OUTPUT" | grep -q '"active_sessions":1'

SESSION_ID="$(echo "$RESERVE_OUTPUT" | sed -E 's/.*"session_id":"([^"]+)".*/\1/')"

STATUS_DURING_RESERVE="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/status
)"

echo "$STATUS_DURING_RESERVE" | grep -q '"active_session_count":1'
echo "$STATUS_DURING_RESERVE" | grep -q '"active_sessions":1'
echo "$STATUS_DURING_RESERVE" | grep -q '"free":1'

MODELS_DURING_RESERVE="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/models
)"

echo "$MODELS_DURING_RESERVE" | grep -q '"slots_free":1'

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SESSION_ID\"}" \
  http://127.0.0.1:4319/admin/v1/sessions/release >/dev/null

STATUS_AFTER_RELEASE="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/status
)"

echo "$STATUS_AFTER_RELEASE" | grep -q '"active_session_count":0'
echo "$STATUS_AFTER_RELEASE" | grep -q '"active_sessions":0'
echo "$STATUS_AFTER_RELEASE" | grep -q '"free":2'

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"mode\":\"share\",\"active_swarm_id\":\"$ALPHA_POOL_ID\"}" \
  http://127.0.0.1:4318/admin/v1/runtime >/dev/null

SHARE_PREFLIGHT_BODY="$(mktemp)"
SHARE_PREFLIGHT_STATUS="$(
  curl -sS -o "$SHARE_PREFLIGHT_BODY" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen2.5-coder:32b","max_providers":1}' \
    http://127.0.0.1:4318/admin/v1/preflight
)"

if [[ "$SHARE_PREFLIGHT_STATUS" != "409" ]]; then
  echo "expected share-mode preflight to fail with 409, got $SHARE_PREFLIGHT_STATUS" >&2
  exit 1
fi
grep -q '"MODE_BLOCKED"' "$SHARE_PREFLIGHT_BODY"
rm -f "$SHARE_PREFLIGHT_BODY"

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"mode\":\"both\",\"active_swarm_id\":\"$ALPHA_POOL_ID\"}" \
  http://127.0.0.1:4318/admin/v1/runtime >/dev/null

STREAM_OUTPUT="$(
  curl -fsS -N \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen2.5-coder:32b","stream":true,"messages":[{"role":"user","content":"hello"}]}' \
    http://127.0.0.1:4318/v1/chat/completions
)"

echo "$STREAM_OUTPUT" | grep -q "OnlyMacs "
echo "$STREAM_OUTPUT" | grep -q "Charles's Mac Studio"
echo "$STREAM_OUTPUT" | grep -q "qwen2.5-coder:32b"
echo "$STREAM_OUTPUT" | grep -q "\\[DONE\\]"

STATUS_AFTER_CHAT="$(
  curl -fsS http://127.0.0.1:4318/admin/v1/status
)"

echo "$STATUS_AFTER_CHAT" | grep -q '"active_session_count":0'

echo "smoke ok"
