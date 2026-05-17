#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_DIR="$ROOT_DIR/.tmp/dmg-staging"
DMG_PATH="$ROOT_DIR/dist/OnlyMacs-public.dmg"
MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-manifest.json"
CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public.sha256"
REBUILD_APP="${ONLYMACS_REBUILD_APP:-1}"
DEFAULT_APP_DIR="$ROOT_DIR/dist/OnlyMacs.app"
SIGN_RETRIES="${ONLYMACS_CODESIGN_RETRIES:-6}"
SIGN_RETRY_DELAY="${ONLYMACS_CODESIGN_RETRY_DELAY:-10}"
SIGN_TIMESTAMP_URL="${ONLYMACS_CODESIGN_TIMESTAMP_URL:-http://timestamp.apple.com/ts01}"

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

if [[ "$REBUILD_APP" == "1" ]]; then
  APP_DIR="$("$ROOT_DIR/scripts/build-macos-app-public.sh")"
else
  APP_DIR="${ONLYMACS_APP_PATH:-$DEFAULT_APP_DIR}"
fi

INFO_PLIST="$APP_DIR/Contents/Info.plist"

rm -rf "$STAGING_DIR" "$DMG_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_DIR"

if [[ ! -d "$APP_DIR" ]]; then
  echo "missing app bundle: $APP_DIR" >&2
  echo "build it first with: make macos-app-public" >&2
  exit 1
fi

cp -R "$APP_DIR" "$STAGING_DIR/OnlyMacs.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "OnlyMacs" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ -n "${ONLYMACS_CODESIGN_IDENTITY:-}" ]]; then
  codesign_retry --force "--timestamp=$SIGN_TIMESTAMP_URL" --sign "$ONLYMACS_CODESIGN_IDENTITY" "$DMG_PATH" >/dev/null
fi

BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
BUILD_TIMESTAMP="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsBuildTimestamp' "$INFO_PLIST")"
BUILD_CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsBuildChannel' "$INFO_PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
DEFAULT_COORDINATOR_URL="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsDefaultCoordinatorURL' "$INFO_PLIST" 2>/dev/null || true)"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
DMG_BYTES="$(stat -f%z "$DMG_PATH")"
APP_BYTES="$(du -sk "$APP_DIR" | awk '{print $1 * 1024}')"
CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
APP_SIGNED="false"
SIGNING_AUTHORITY=""
SIGNING_TEAM_ID=""
DMG_SIGNED="false"
DMG_SIGNING_AUTHORITY=""
DMG_SIGNING_TEAM_ID=""

if codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1 &&
   codesign_output="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"; then
  APP_SIGNED="true"
  SIGNING_AUTHORITY="$(printf '%s\n' "$codesign_output" | awk -F= '/^Authority=/{print $2; exit}')"
  SIGNING_TEAM_ID="$(printf '%s\n' "$codesign_output" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
fi

if codesign --verify "$DMG_PATH" >/dev/null 2>&1 &&
   dmg_codesign_output="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1)"; then
  DMG_SIGNED="true"
  DMG_SIGNING_AUTHORITY="$(printf '%s\n' "$dmg_codesign_output" | awk -F= '/^Authority=/{print $2; exit}')"
  DMG_SIGNING_TEAM_ID="$(printf '%s\n' "$dmg_codesign_output" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
fi

printf "%s  %s\n" "$DMG_SHA256" "$(basename "$DMG_PATH")" > "$CHECKSUM_PATH"

cat > "$MANIFEST_PATH" <<EOF
{
  "artifact": "OnlyMacs-public.dmg",
  "artifact_path": "$DMG_PATH",
  "artifact_sha256": "$DMG_SHA256",
  "artifact_bytes": $DMG_BYTES,
  "artifact_notarized": false,
  "artifact_signed": $DMG_SIGNED,
  "artifact_signing_authority": "$DMG_SIGNING_AUTHORITY",
  "artifact_signing_team_id": "$DMG_SIGNING_TEAM_ID",
  "app_path": "$APP_DIR",
  "app_bytes": $APP_BYTES,
  "bundle_id": "$BUNDLE_ID",
  "build_version": "$BUILD_VERSION",
  "build_number": "$BUILD_NUMBER",
  "build_timestamp": "$BUILD_TIMESTAMP",
  "build_channel": "$BUILD_CHANNEL",
  "default_coordinator_url": "$DEFAULT_COORDINATOR_URL",
  "app_signed": $APP_SIGNED,
  "app_signing_authority": "$SIGNING_AUTHORITY",
  "app_signing_team_id": "$SIGNING_TEAM_ID",
  "app_rebuilt_during_packaging": $([[ "$REBUILD_APP" == "1" ]] && echo true || echo false),
  "created_at": "$CREATED_AT"
}
EOF

echo "$DMG_PATH"
