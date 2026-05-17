#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ONLYMACS_APP_DIR:-$ROOT_DIR/dist/OnlyMacs.app}"
LOG_DIR="$HOME/Library/Application Support/OnlyMacs/Logs"
REBUILD_APP="${ONLYMACS_REBUILD_APP:-1}"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
RESOURCE_BUNDLE_PATH="$APP_DIR/Contents/Resources/OnlyMacsApp_OnlyMacsCore.bundle"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  pkill -f "$APP_DIR/Contents/MacOS/OnlyMacsApp" >/dev/null 2>&1 || true
  pkill -f "$APP_DIR/Contents/Helpers/onlymacs-coordinator" >/dev/null 2>&1 || true
  pkill -f "$APP_DIR/Contents/Helpers/onlymacs-local-bridge" >/dev/null 2>&1 || true
}

trap cleanup EXIT

"$ROOT_DIR/scripts/stop-dev.sh" >/dev/null
cleanup
rm -rf "$LOG_DIR"

if [[ "$REBUILD_APP" == "1" ]]; then
  APP_DIR="$("$ROOT_DIR/scripts/build-macos-app-public.sh")"
  INFO_PLIST="$APP_DIR/Contents/Info.plist"
  RESOURCE_BUNDLE_PATH="$APP_DIR/Contents/Resources/OnlyMacsApp_OnlyMacsCore.bundle"
elif [[ ! -d "$APP_DIR" ]]; then
  echo "missing packaged app bundle: $APP_DIR" >&2
  echo "rebuild it first with make macos-app-public or rerun with ONLYMACS_REBUILD_APP=1" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "missing packaged SwiftPM resource bundle: $RESOURCE_BUNDLE_PATH" >&2
  exit 1
fi

if [[ -f "$INFO_PLIST" ]]; then
  bundle_icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$bundle_icon_file" != "OnlyMacs.icns" ]]; then
    echo "unexpected app icon setting: expected CFBundleIconFile=OnlyMacs.icns, got ${bundle_icon_file:-missing}" >&2
    exit 1
  fi
  if [[ ! -f "$APP_DIR/Contents/Resources/$bundle_icon_file" ]]; then
    echo "missing packaged app icon resource: $APP_DIR/Contents/Resources/$bundle_icon_file" >&2
    exit 1
  fi

  sparkle_auto_update="$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$sparkle_auto_update" != "true" ]]; then
    echo "unexpected Sparkle automatic download setting: expected SUAutomaticallyUpdate=true, got ${sparkle_auto_update:-missing}" >&2
    exit 1
  fi

  sparkle_allows_automatic_updates="$(/usr/libexec/PlistBuddy -c 'Print :SUAllowsAutomaticUpdates' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$sparkle_allows_automatic_updates" != "true" ]]; then
    echo "unexpected Sparkle automatic update option: expected SUAllowsAutomaticUpdates=true, got ${sparkle_allows_automatic_updates:-missing}" >&2
    exit 1
  fi
fi

COORDINATOR_HEALTH_URL="http://127.0.0.1:4319/health"
EXPECTED_BRIDGE_COORDINATOR_URL="http://127.0.0.1:4319"
EXPECT_LOCAL_COORDINATOR_LOG=1
if [[ -f "$INFO_PLIST" ]]; then
  embedded_coordinator_url="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsDefaultCoordinatorURL' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ -n "$embedded_coordinator_url" ]]; then
    EXPECTED_BRIDGE_COORDINATOR_URL="${embedded_coordinator_url%/}"
    COORDINATOR_HEALTH_URL="$EXPECTED_BRIDGE_COORDINATOR_URL/health"
    EXPECT_LOCAL_COORDINATOR_LOG=0
  fi
fi

"$APP_DIR/Contents/MacOS/OnlyMacsApp" --onlymacs-automation-mode >/dev/null 2>&1 &
APP_PID="$!"

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

wait_for_body() {
  local url="$1"
  local attempts=0
  local body
  until body="$(curl -fsS "$url" 2>/dev/null)" && [[ -n "$body" ]]; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -gt 30 ]]; then
      echo "timed out waiting for response body from $url" >&2
      exit 1
    fi
    sleep 1
  done
  printf '%s' "$body"
}

wait_for_url "$COORDINATOR_HEALTH_URL"
wait_for_url "http://127.0.0.1:4318/health"

bridge_status_json="$(wait_for_body "http://127.0.0.1:4318/admin/v1/status")"
actual_bridge_coordinator_url="$(
  python3 -c 'import json, sys; print((json.load(sys.stdin).get("bridge") or {}).get("coordinator_url", "").rstrip("/"))' <<<"$bridge_status_json"
)"
if [[ "$actual_bridge_coordinator_url" != "$EXPECTED_BRIDGE_COORDINATOR_URL" ]]; then
  echo "bridge coordinator mismatch: expected $EXPECTED_BRIDGE_COORDINATOR_URL, got $actual_bridge_coordinator_url" >&2
  exit 1
fi

if [[ "$EXPECT_LOCAL_COORDINATOR_LOG" == "1" ]]; then
  test -f "$LOG_DIR/coordinator.log"
fi
test -f "$LOG_DIR/local-bridge.log"

echo "app bundle smoke ok"
