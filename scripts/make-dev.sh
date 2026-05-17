#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"
TMP_DIR="$ROOT_DIR/.tmp"
COORD_LOG="$TMP_DIR/coordinator.log"
BRIDGE_LOG="$TMP_DIR/local-bridge.log"
COORD_PID_FILE="$TMP_DIR/coordinator.pid"
BRIDGE_PID_FILE="$TMP_DIR/local-bridge.pid"

mkdir -p "$TMP_DIR"

stop_if_running() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi
}

stop_listener_on_port() {
  local port="$1"
  local pids
  pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    while read -r pid; do
      [[ -z "$pid" ]] && continue
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    done <<< "$pids"
  fi
}

stop_if_running "$COORD_PID_FILE"
stop_if_running "$BRIDGE_PID_FILE"
stop_listener_on_port 4319
stop_listener_on_port 4318

(
  cd "$COORDINATOR_REPO"
  go run ./cmd/coordinator >"$COORD_LOG" 2>&1
) &
COORD_PID=$!
echo "$COORD_PID" > "$COORD_PID_FILE"

(
  cd "$ROOT_DIR/apps/local-bridge"
  ONLYMACS_ENABLE_CANNED_CHAT="${ONLYMACS_ENABLE_CANNED_CHAT:-1}" \
  ONLYMACS_OLLAMA_URL="${ONLYMACS_OLLAMA_URL:-http://127.0.0.1:11434}" \
  go run ./cmd/local-bridge >"$BRIDGE_LOG" 2>&1
) &
BRIDGE_PID=$!
echo "$BRIDGE_PID" > "$BRIDGE_PID_FILE"

echo "started coordinator pid=$COORD_PID"
echo "started local bridge pid=$BRIDGE_PID"
echo "logs: $COORD_LOG $BRIDGE_LOG"
