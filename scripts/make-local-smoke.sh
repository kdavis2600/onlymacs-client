#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$ROOT_DIR/.tmp"
STATUS_FILE="$TMP_DIR/local-smoke-status.json"
STREAM_FILE="$TMP_DIR/local-smoke-stream.txt"

cleanup() {
  "$ROOT_DIR/scripts/stop-dev.sh" >/dev/null 2>&1 || true
}

trap cleanup EXIT

mkdir -p "$TMP_DIR"

ONLYMACS_ENABLE_CANNED_CHAT=0 "$ROOT_DIR/scripts/make-dev.sh" >/dev/null

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
wait_for_url "http://127.0.0.1:11434/v1/models"

POOL_RESPONSE="$(
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d '{"name":"Local Public Swarm","member_name":"Kevin","mode":"both"}' \
    http://127.0.0.1:4318/admin/v1/swarms/create
)"
POOL_ID="$(echo "$POOL_RESPONSE" | sed -E 's/.*"id":"([^"]+)".*/\1/')"

curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"slots_total":1}' \
  http://127.0.0.1:4318/admin/v1/share/publish >/dev/null

curl -fsS http://127.0.0.1:4318/admin/v1/status > "$STATUS_FILE"

grep -q '"This Mac"' "$STATUS_FILE"

MODEL_ID="${ONLYMACS_SMOKE_MODEL:-}"
if [[ -z "$MODEL_ID" ]]; then
  MODEL_ID="$(
    curl -fsS http://127.0.0.1:4318/admin/v1/models | jq -r '
      ([.models[]?.id | select(. == "qwen2.5-coder:32b")][0]
      // [.models[]?.id | select(test("coder"; "i"))][0]
      // .models[0].id
      // empty)
    '
  )"
fi

if [[ -z "$MODEL_ID" ]]; then
  echo "no model visible through bridge" >&2
  exit 1
fi

grep -Fq "\"$MODEL_ID\"" "$STATUS_FILE"

curl -fsS -N \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_ID\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with ONLYMACS_SMOKE_OK exactly.\"}]}" \
  http://127.0.0.1:4318/v1/chat/completions > "$STREAM_FILE"

COMBINED_CONTENT="$(
  grep '^data: {' "$STREAM_FILE" |
    sed 's/^data: //' |
    jq -r '.choices[0].delta.content // empty' |
    tr -d '\n'
)"

[[ -n "$COMBINED_CONTENT" ]]
echo "$COMBINED_CONTENT" | grep -q 'ONLYMACS_SMOKE_OK'
grep -q '\[DONE\]' "$STREAM_FILE"

echo "local smoke ok"
echo "status: $STATUS_FILE"
echo "stream: $STREAM_FILE"
