#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ONLYMACS_APP_DIR:-$ROOT_DIR/dist/OnlyMacs.app}"
ENTITLEMENTS_PATH="$ROOT_DIR/config/macos/OnlyMacs.entitlements"
IDENTITY="${ONLYMACS_CODESIGN_IDENTITY:?ONLYMACS_CODESIGN_IDENTITY must be set}"

MAIN_BINARY="$APP_DIR/Contents/MacOS/OnlyMacsApp"
HELPERS_DIR="$APP_DIR/Contents/Helpers"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
SIGN_RETRIES="${ONLYMACS_CODESIGN_RETRIES:-6}"
SIGN_RETRY_DELAY="${ONLYMACS_CODESIGN_RETRY_DELAY:-10}"
SIGN_TIMESTAMP_URL="${ONLYMACS_CODESIGN_TIMESTAMP_URL:-http://timestamp.apple.com/ts01}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "missing app bundle: $APP_DIR" >&2
  echo "build it first with: make macos-app-public" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "missing entitlements file: $ENTITLEMENTS_PATH" >&2
  exit 1
fi

codesign_retry() {
  local attempt=1 rc=0
  while true; do
    codesign "$@" && return 0
    rc=$?
    if [[ "$attempt" -ge "$SIGN_RETRIES" ]]; then
      return "$rc"
    fi
    echo "codesign failed; retrying in ${SIGN_RETRY_DELAY}s (attempt ${attempt}/${SIGN_RETRIES})" >&2
    sleep "$SIGN_RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

sign_binary() {
  local path="$1"
  codesign_retry \
    --force \
    "--timestamp=$SIGN_TIMESTAMP_URL" \
    --options runtime \
    --sign "$IDENTITY" \
    "$path"
}

sign_bundle() {
  local path="$1"
  codesign_retry \
    --force \
    "--timestamp=$SIGN_TIMESTAMP_URL" \
    --options runtime \
    --sign "$IDENTITY" \
    "$path"
}

if [[ -d "$HELPERS_DIR" ]]; then
  while IFS= read -r helper_path; do
    sign_binary "$helper_path"
  done < <(find "$HELPERS_DIR" -type f -perm -0111 | sort)
fi

if [[ -d "$FRAMEWORKS_DIR" ]]; then
  while IFS= read -r nested_binary; do
    sign_binary "$nested_binary"
  done < <(find "$FRAMEWORKS_DIR" -type f -perm -0111 | sort)

  while IFS= read -r xpc_path; do
    sign_bundle "$xpc_path"
  done < <(find "$FRAMEWORKS_DIR" -type d -name '*.xpc' | sort)

  while IFS= read -r nested_app_path; do
    sign_bundle "$nested_app_path"
  done < <(find "$FRAMEWORKS_DIR" -type d -name '*.app' | sort)

  while IFS= read -r framework_path; do
    sign_bundle "$framework_path"
  done < <(find "$FRAMEWORKS_DIR" -type d -name '*.framework' | sort)
fi

sign_binary "$MAIN_BINARY"

codesign_retry \
  --force \
  "--timestamp=$SIGN_TIMESTAMP_URL" \
  --options runtime \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type exec --verbose=2 "$APP_DIR" || true

echo "$APP_DIR"
