#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"
TMP_DIR="$ROOT_DIR/.tmp/two-bridge-public-execution-smoke"
REMOTE_COORDINATOR_URL="${ONLYMACS_PUBLIC_EXECUTION_COORDINATOR_URL:-}"
LOCAL_COORDINATOR_URL="http://127.0.0.1:4329"
COORDINATOR_URL="$LOCAL_COORDINATOR_URL"
COORD_LOG="$TMP_DIR/coordinator.log"
REQUESTER_LOG="$TMP_DIR/requester-bridge.log"
FRIEND_LOG="$TMP_DIR/friend-bridge.log"
COORD_PID_FILE="$TMP_DIR/coordinator.pid"
REQUESTER_PID_FILE="$TMP_DIR/requester-bridge.pid"
FRIEND_PID_FILE="$TMP_DIR/friend-bridge.pid"
REQUESTER_STATUS_BEFORE_FILE="$TMP_DIR/requester-status-before.json"
FRIEND_STATUS_BEFORE_FILE="$TMP_DIR/friend-status-before.json"
REQUESTER_STATUS_DURING_FILE="$TMP_DIR/requester-status-during.json"
FRIEND_STATUS_DURING_FILE="$TMP_DIR/friend-status-during.json"
REQUESTER_STATUS_AFTER_FILE="$TMP_DIR/requester-status-after.json"
FRIEND_STATUS_AFTER_FILE="$TMP_DIR/friend-status-after.json"
COORD_POOLS_FILE="$TMP_DIR/coordinator-swarms.json"
REQUESTER_MODELS_FILE="$TMP_DIR/requester-models.json"
SWARM_START_FILE="$TMP_DIR/swarm-start.json"
SWARM_SESSIONS_AFTER_FILE="$TMP_DIR/swarm-sessions-after.json"
COMPLETED_SESSION_FILE="$TMP_DIR/completed-session.json"
SUMMARY_FILE="$TMP_DIR/summary.json"
REQUESTER_REQUEST_METRICS="$TMP_DIR/requester-request-metrics.json"
REQUESTER_SHARE_METRICS="$TMP_DIR/requester-share-metrics.json"
FRIEND_REQUEST_METRICS="$TMP_DIR/friend-request-metrics.json"
FRIEND_SHARE_METRICS="$TMP_DIR/friend-share-metrics.json"

if [[ -n "$REMOTE_COORDINATOR_URL" ]]; then
  COORDINATOR_URL="${REMOTE_COORDINATOR_URL%/}"
fi

cleanup() {
  if [[ -f "$SWARM_START_FILE" ]]; then
    jq -r '.session.reservations[]?.reservation_id // empty' "$SWARM_START_FILE" 2>/dev/null | while read -r reservation_id; do
      [[ -z "$reservation_id" ]] && continue
      curl -fsS -H 'Content-Type: application/json' \
        -d "{\"session_id\":\"$reservation_id\"}" \
        "$COORDINATOR_URL/admin/v1/sessions/release" >/dev/null 2>&1 || true
    done
  fi

  for bridge_url in "http://127.0.0.1:4328" "http://127.0.0.1:4327"; do
    curl -fsS -H 'Content-Type: application/json' -d '{}' \
      "$bridge_url/admin/v1/share/unpublish" >/dev/null 2>&1 || true
  done

  local pid_files=("$REQUESTER_PID_FILE" "$FRIEND_PID_FILE")
  if [[ "$COORDINATOR_URL" == "$LOCAL_COORDINATOR_URL" ]]; then
    pid_files=("$COORD_PID_FILE" "${pid_files[@]}")
  fi

  for pid_file in "${pid_files[@]}"; do
    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi
      rm -f "$pid_file"
    fi
  done

  local ports=(4328 4327)
  if [[ "$COORDINATOR_URL" == "$LOCAL_COORDINATOR_URL" ]]; then
    ports=(4329 "${ports[@]}")
  fi
  for port in "${ports[@]}"; do
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
rm -f \
  "$REQUESTER_STATUS_BEFORE_FILE" "$FRIEND_STATUS_BEFORE_FILE" \
  "$REQUESTER_STATUS_DURING_FILE" "$FRIEND_STATUS_DURING_FILE" \
  "$REQUESTER_STATUS_AFTER_FILE" "$FRIEND_STATUS_AFTER_FILE" \
  "$COORD_POOLS_FILE" "$REQUESTER_MODELS_FILE" "$SWARM_START_FILE" \
  "$SWARM_SESSIONS_AFTER_FILE" "$COMPLETED_SESSION_FILE" "$SUMMARY_FILE" \
  "$REQUESTER_REQUEST_METRICS" "$REQUESTER_SHARE_METRICS" \
  "$FRIEND_REQUEST_METRICS" "$FRIEND_SHARE_METRICS"

wait_for_url() {
  local url="$1"
  local attempts=0
  until curl -fsS "$url" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -gt 40 ]]; then
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

if [[ "$COORDINATOR_URL" == "$LOCAL_COORDINATOR_URL" ]]; then
  start_background "$COORD_PID_FILE" env \
    bash -lc "cd '$COORDINATOR_REPO' && ONLYMACS_COORDINATOR_ADDR='127.0.0.1:4329' go run ./cmd/coordinator >'$COORD_LOG' 2>&1"
fi

start_background "$REQUESTER_PID_FILE" env \
  bash -lc "cd '$ROOT_DIR/apps/local-bridge' && ONLYMACS_BRIDGE_ADDR='127.0.0.1:4328' ONLYMACS_COORDINATOR_URL='$COORDINATOR_URL' ONLYMACS_ENABLE_CANNED_CHAT=1 ONLYMACS_CANNED_CHAT_DELAY_MS=800 ONLYMACS_REQUEST_METRICS_PATH='$REQUESTER_REQUEST_METRICS' ONLYMACS_SHARE_METRICS_PATH='$REQUESTER_SHARE_METRICS' ONLYMACS_OLLAMA_URL='${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}' ONLYMACS_NODE_ID='requester-public-a' ONLYMACS_PROVIDER_NAME='Kevin MacBook Pro' ONLYMACS_MEMBER_NAME='Kevin' go run ./cmd/local-bridge >'$REQUESTER_LOG' 2>&1"

start_background "$FRIEND_PID_FILE" env \
  bash -lc "cd '$ROOT_DIR/apps/local-bridge' && ONLYMACS_BRIDGE_ADDR='127.0.0.1:4327' ONLYMACS_COORDINATOR_URL='$COORDINATOR_URL' ONLYMACS_ENABLE_CANNED_CHAT=1 ONLYMACS_CANNED_CHAT_DELAY_MS=800 ONLYMACS_REQUEST_METRICS_PATH='$FRIEND_REQUEST_METRICS' ONLYMACS_SHARE_METRICS_PATH='$FRIEND_SHARE_METRICS' ONLYMACS_OLLAMA_URL='${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}' ONLYMACS_NODE_ID='friend-public-b' ONLYMACS_PROVIDER_NAME='Charles Mac Studio' ONLYMACS_MEMBER_NAME='Charles' go run ./cmd/local-bridge >'$FRIEND_LOG' 2>&1"

wait_for_url "$COORDINATOR_URL/health"
wait_for_url "http://127.0.0.1:4328/health"
wait_for_url "http://127.0.0.1:4327/health"
wait_for_url "${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}/v1/models"

curl -fsS -H 'Content-Type: application/json' -d '{"mode":"both","active_swarm_id":"swarm-public"}' \
  http://127.0.0.1:4328/admin/v1/runtime >/dev/null
curl -fsS -H 'Content-Type: application/json' -d '{"mode":"both","active_swarm_id":"swarm-public"}' \
  http://127.0.0.1:4327/admin/v1/runtime >/dev/null

attempts=0
until curl -fsS "$COORDINATOR_URL/admin/v1/swarms" > "$COORD_POOLS_FILE" && \
  [[ "$(jq -r '.swarms[] | select(.id == "swarm-public") | .member_count' "$COORD_POOLS_FILE")" -ge 2 ]]; do
  attempts=$((attempts + 1))
  if [[ "$attempts" -gt 30 ]]; then
    echo "public swarm never registered both members" >&2
    cat "$COORD_POOLS_FILE" >&2 || true
    exit 1
  fi
  curl -fsS http://127.0.0.1:4328/admin/v1/status > "$REQUESTER_STATUS_BEFORE_FILE" || true
  curl -fsS http://127.0.0.1:4327/admin/v1/status > "$FRIEND_STATUS_BEFORE_FILE" || true
  sleep 1
done

curl -fsS "${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}/v1/models" > "$REQUESTER_MODELS_FILE"
SHARED_MODEL_ID="$(jq -r '
  ([.data[]?.id | select(. == "qwen2.5-coder:14b")][0]
   // [.data[]?.id | select(. == "qwen2.5-coder:32b")][0]
   // [.data[]?.id | select(test("coder"; "i"))][0]
   // [.data[]?.id | select(test("gemma"; "i"))][0]
   // .data[0].id
   // empty)
' "$REQUESTER_MODELS_FILE")"

if [[ -z "$SHARED_MODEL_ID" ]]; then
  echo "no local Ollama models available to publish" >&2
  exit 1
fi

PUBLISH_PAYLOAD="$(jq -n --arg model "$SHARED_MODEL_ID" '{slots_total:1, model_ids:[$model]}')"
curl -fsS -H 'Content-Type: application/json' -d "$PUBLISH_PAYLOAD" \
  http://127.0.0.1:4328/admin/v1/share/publish >/dev/null
curl -fsS -H 'Content-Type: application/json' -d "$PUBLISH_PAYLOAD" \
  http://127.0.0.1:4327/admin/v1/share/publish >/dev/null

attempts=0
until curl -fsS http://127.0.0.1:4328/admin/v1/models > "$REQUESTER_MODELS_FILE" && \
  [[ "$(jq -r --arg model "$SHARED_MODEL_ID" '[.models[] | select(.id == $model)][0].slots_total // 0' "$REQUESTER_MODELS_FILE")" -ge 2 ]]; do
  attempts=$((attempts + 1))
  if [[ "$attempts" -gt 30 ]]; then
    echo "shared public model never became visible on requester bridge" >&2
    cat "$REQUESTER_MODELS_FILE" >&2 || true
    exit 1
  fi
  sleep 1
done

curl -fsS http://127.0.0.1:4328/admin/v1/status > "$REQUESTER_STATUS_BEFORE_FILE"
curl -fsS http://127.0.0.1:4327/admin/v1/status > "$FRIEND_STATUS_BEFORE_FILE"

SWARM_PAYLOAD="$(jq -n --arg model "$SHARED_MODEL_ID" --arg prompt "Reply with ONLYMACS_PUBLIC_SWARM_OK exactly." '{
  model:$model,
  requested_agents:2,
  max_agents:2,
  scheduling:"elastic",
  prompt:$prompt
}')"
curl -fsS -H 'Content-Type: application/json' -d "$SWARM_PAYLOAD" \
  http://127.0.0.1:4328/admin/v1/swarm/start > "$SWARM_START_FILE"

SESSION_ID="$(jq -r '.session.id // empty' "$SWARM_START_FILE")"
if [[ -z "$SESSION_ID" ]]; then
  echo "swarm start did not return a session id" >&2
  cat "$SWARM_START_FILE" >&2 || true
  exit 1
fi

attempts=0
until \
  curl -fsS http://127.0.0.1:4328/admin/v1/status > "$REQUESTER_STATUS_DURING_FILE" && \
  curl -fsS http://127.0.0.1:4327/admin/v1/status > "$FRIEND_STATUS_DURING_FILE" && \
  [[ "$(jq -r '.swarm.active_session_count // 0' "$REQUESTER_STATUS_DURING_FILE")" -ge 1 ]] && \
  [[ "$(jq -r '.sharing.active_sessions // 0' "$FRIEND_STATUS_DURING_FILE")" -ge 1 ]]; do
  attempts=$((attempts + 1))
  if [[ "$attempts" -gt 25 ]]; then
    echo "public execution never showed both requester and friend as active" >&2
    cat "$REQUESTER_STATUS_DURING_FILE" >&2 || true
    cat "$FRIEND_STATUS_DURING_FILE" >&2 || true
    exit 1
  fi
  sleep 0.2
done

attempts=0
until curl -fsS http://127.0.0.1:4328/admin/v1/swarm/sessions > "$SWARM_SESSIONS_AFTER_FILE" && \
  jq -e --arg session_id "$SESSION_ID" '.sessions[] | select(.id == $session_id and (.status == "completed" or .status == "failed"))' "$SWARM_SESSIONS_AFTER_FILE" > "$COMPLETED_SESSION_FILE"; do
	attempts=$((attempts + 1))
	if [[ "$attempts" -gt 120 ]]; then
		echo "public execution never reached a terminal swarm session state" >&2
		cat "$SWARM_SESSIONS_AFTER_FILE" >&2 || true
		exit 1
  fi
  sleep 0.5
done

curl -fsS http://127.0.0.1:4328/admin/v1/status > "$REQUESTER_STATUS_AFTER_FILE"
curl -fsS http://127.0.0.1:4327/admin/v1/status > "$FRIEND_STATUS_AFTER_FILE"
curl -fsS "$COORDINATOR_URL/admin/v1/swarms" > "$COORD_POOLS_FILE"

jq -n \
  --arg model "$SHARED_MODEL_ID" \
  --arg coordinator_url "$COORDINATOR_URL" \
  --slurpfile swarms "$COORD_POOLS_FILE" \
  --slurpfile requesterBefore "$REQUESTER_STATUS_BEFORE_FILE" \
  --slurpfile friendBefore "$FRIEND_STATUS_BEFORE_FILE" \
  --slurpfile requesterDuring "$REQUESTER_STATUS_DURING_FILE" \
  --slurpfile friendDuring "$FRIEND_STATUS_DURING_FILE" \
  --slurpfile requesterAfter "$REQUESTER_STATUS_AFTER_FILE" \
  --slurpfile friendAfter "$FRIEND_STATUS_AFTER_FILE" \
  --slurpfile start "$SWARM_START_FILE" \
  --slurpfile sessions "$SWARM_SESSIONS_AFTER_FILE" \
  --slurpfile completed "$COMPLETED_SESSION_FILE" \
  '{
    shared_model: $model,
    coordinator_url: $coordinator_url,
    public_swarm: ($swarms[0].swarms[] | select(.id == "swarm-public")),
    requester_status_before: $requesterBefore[0],
    friend_status_before: $friendBefore[0],
    requester_status_during: $requesterDuring[0],
    friend_status_during: $friendDuring[0],
    requester_status_after: $requesterAfter[0],
    friend_status_after: $friendAfter[0],
    swarm_start: $start[0],
    requester_sessions_after: $sessions[0],
    completed_session: $completed[0]
  }' > "$SUMMARY_FILE"

echo "two-bridge public execution smoke ok"
echo "summary: $SUMMARY_FILE"
echo "requester status before: $REQUESTER_STATUS_BEFORE_FILE"
echo "friend status before: $FRIEND_STATUS_BEFORE_FILE"
echo "requester status during: $REQUESTER_STATUS_DURING_FILE"
echo "friend status during: $FRIEND_STATUS_DURING_FILE"
echo "requester status after: $REQUESTER_STATUS_AFTER_FILE"
echo "friend status after: $FRIEND_STATUS_AFTER_FILE"
