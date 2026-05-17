#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"
TMP_DIR="$ROOT_DIR/.tmp/two-bridge-remote-smoke"
COORD_LOG="$TMP_DIR/coordinator.log"
REQUESTER_LOG="$TMP_DIR/requester-bridge.log"
PROVIDER_LOG="$TMP_DIR/provider-bridge.log"
COORD_PID_FILE="$TMP_DIR/coordinator.pid"
REQUESTER_PID_FILE="$TMP_DIR/requester-bridge.pid"
PROVIDER_PID_FILE="$TMP_DIR/provider-bridge.pid"
REQUESTER_STATUS_FILE="$TMP_DIR/requester-status.json"
PROVIDER_STATUS_FILE="$TMP_DIR/provider-status.json"
REQUESTER_MODELS_FILE="$TMP_DIR/requester-models.json"
STREAM_FILE="$TMP_DIR/remote-stream.txt"

cleanup() {
  for pid_file in "$COORD_PID_FILE" "$REQUESTER_PID_FILE" "$PROVIDER_PID_FILE"; do
    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi
      rm -f "$pid_file"
    fi
  done

  for port in 4319 4318 4317; do
    pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      while read -r pid; do
        [[ -z "$pid" ]] && continue
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      done <<< "$pids"
    fi
  done
}

trap cleanup EXIT

mkdir -p "$TMP_DIR"

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

start_background() {
  local pid_file="$1"
  shift
  (
    "$@"
  ) &
  local pid=$!
  echo "$pid" > "$pid_file"
}

cleanup

start_background "$COORD_PID_FILE" env \
  bash -lc "cd '$COORDINATOR_REPO' && ONLYMACS_COORDINATOR_ADDR='127.0.0.1:4319' go run ./cmd/coordinator >'$COORD_LOG' 2>&1"

start_background "$REQUESTER_PID_FILE" env \
  bash -lc "cd '$ROOT_DIR/apps/local-bridge' && ONLYMACS_BRIDGE_ADDR='127.0.0.1:4318' ONLYMACS_COORDINATOR_URL='http://127.0.0.1:4319' ONLYMACS_ENABLE_CANNED_CHAT=0 ONLYMACS_OLLAMA_URL='${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}' ONLYMACS_NODE_ID='requester-a' ONLYMACS_PROVIDER_NAME='Kevin MacBook Pro' ONLYMACS_MEMBER_NAME='Kevin' go run ./cmd/local-bridge >'$REQUESTER_LOG' 2>&1"

start_background "$PROVIDER_PID_FILE" env \
  bash -lc "cd '$ROOT_DIR/apps/local-bridge' && ONLYMACS_BRIDGE_ADDR='127.0.0.1:4317' ONLYMACS_COORDINATOR_URL='http://127.0.0.1:4319' ONLYMACS_ENABLE_CANNED_CHAT=0 ONLYMACS_OLLAMA_URL='${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}' ONLYMACS_NODE_ID='provider-b' ONLYMACS_PROVIDER_NAME='Charles Mac Studio' ONLYMACS_MEMBER_NAME='Charles' go run ./cmd/local-bridge >'$PROVIDER_LOG' 2>&1"

wait_for_url "http://127.0.0.1:4319/health"
wait_for_url "http://127.0.0.1:4318/health"
wait_for_url "http://127.0.0.1:4317/health"
wait_for_url "${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}/v1/models"

POOL_RESPONSE="$(
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d '{"name":"Remote Relay Public","member_name":"Kevin","mode":"use"}' \
    http://127.0.0.1:4318/admin/v1/swarms/create
)"
INVITE_TOKEN="$(jq -r '.invite.invite_token' <<<"$POOL_RESPONSE")"
[[ -n "$INVITE_TOKEN" && "$INVITE_TOKEN" != "null" ]]

curl -fsS \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg token "$INVITE_TOKEN" '{invite_token:$token,member_name:"Charles",mode:"share"}')" \
  http://127.0.0.1:4317/admin/v1/swarms/join >/dev/null

curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"slots_total":1}' \
  http://127.0.0.1:4317/admin/v1/share/publish >/dev/null

attempts=0
MODEL_ID=""
until [[ -n "$MODEL_ID" ]]; do
  curl -fsS http://127.0.0.1:4318/admin/v1/models > "$REQUESTER_MODELS_FILE"
  MODEL_ID="$(jq -r '
    ([.models[]?.id | select(. == "qwen2.5-coder:32b")][0]
    // [.models[]?.id | select(test("coder"; "i"))][0]
    // .models[0].id
    // empty)
  ' "$REQUESTER_MODELS_FILE")"
  attempts=$((attempts + 1))
  if [[ "$attempts" -gt 20 ]]; then
    echo "requester bridge never saw a remote model" >&2
    exit 1
  fi
  [[ -n "$MODEL_ID" ]] || sleep 1
done

curl -fsS http://127.0.0.1:4318/admin/v1/status > "$REQUESTER_STATUS_FILE"
curl -fsS http://127.0.0.1:4317/admin/v1/status > "$PROVIDER_STATUS_FILE"

grep -q '"Charles Mac Studio"' "$REQUESTER_STATUS_FILE"
grep -Fq "\"$MODEL_ID\"" "$REQUESTER_MODELS_FILE"

curl -fsS -N \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_ID\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with ONLYMACS_REMOTE_SMOKE_OK exactly.\"}]}" \
  http://127.0.0.1:4318/v1/chat/completions > "$STREAM_FILE"

COMBINED_CONTENT="$(
  grep '^data: {' "$STREAM_FILE" |
    sed 's/^data: //' |
    jq -r '.choices[0].delta.content // empty' |
    tr -d '\n'
)"

[[ -n "$COMBINED_CONTENT" ]]
echo "$COMBINED_CONTENT" | grep -q 'ONLYMACS_REMOTE_SMOKE_OK'
grep -q '\[DONE\]' "$STREAM_FILE"

curl -fsS http://127.0.0.1:4318/admin/v1/status > "$REQUESTER_STATUS_FILE"
curl -fsS http://127.0.0.1:4317/admin/v1/status > "$PROVIDER_STATUS_FILE"

[[ "$(jq -r '.usage.downloaded_tokens_estimate // 0' "$REQUESTER_STATUS_FILE")" -gt 0 ]]
[[ "$(jq -r '.usage.community_boost.label // empty' "$REQUESTER_STATUS_FILE")" == "Steady" || "$(jq -r '.usage.community_boost.label // empty' "$REQUESTER_STATUS_FILE")" == "Warming Up" || "$(jq -r '.usage.community_boost.label // empty' "$REQUESTER_STATUS_FILE")" == "Hot" || "$(jq -r '.usage.community_boost.label // empty' "$REQUESTER_STATUS_FILE")" == "Headliner" || "$(jq -r '.usage.community_boost.label // empty' "$REQUESTER_STATUS_FILE")" == "Cold" ]]
[[ "$(jq -r '.sharing.uploaded_tokens_estimate // 0' "$PROVIDER_STATUS_FILE")" -gt 0 ]]
[[ "$(jq -r '.usage.uploaded_tokens_estimate // 0' "$PROVIDER_STATUS_FILE")" -gt 0 ]]
[[ -n "$(jq -r '.usage.community_boost.primary_trait // empty' "$PROVIDER_STATUS_FILE")" ]]

echo "two-bridge remote smoke ok"
echo "requester status: $REQUESTER_STATUS_FILE"
echo "provider status: $PROVIDER_STATUS_FILE"
echo "models: $REQUESTER_MODELS_FILE"
echo "stream: $STREAM_FILE"
