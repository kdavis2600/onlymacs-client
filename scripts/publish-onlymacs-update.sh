#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/onlymacs-version-lib.sh"
source "$ROOT_DIR/scripts/onlymacs-release-config.sh"
PACKAGE_PATH="$ROOT_DIR/apps/onlymacs-macos"
RAILWAY_CONTEXT_DIR="$(onlymacs_railway_context_dir)"
SERVER_REPO="${ONLYMACS_UPDATE_SERVER_REPO:-$RAILWAY_CONTEXT_DIR}"
SERVER_BASE_URL="$(onlymacs_update_server_base_url)"
UPLOAD_BASE_URL="$(onlymacs_update_upload_base_url "$SERVER_BASE_URL")"
SERVER_SERVICE="$(onlymacs_update_server_service)"
SERVER_ENVIRONMENT="$(onlymacs_update_server_environment)"
SPARKLE_ACCOUNT="${ONLYMACS_SPARKLE_KEY_ACCOUNT:-onlymacs}"
PUBLIC_KEY_FILE="${ONLYMACS_SPARKLE_PUBLIC_KEY_FILE:-$ROOT_DIR/config/macos/OnlyMacs.sparkle-public-ed25519.txt}"
ALLOW_UNSIGNED="${ONLYMACS_ALLOW_UNSIGNED_SPARKLE_PUBLISH:-0}"
REBUILD_DMG="${ONLYMACS_REBUILD_DMG_BEFORE_PUBLISH:-1}"
BUILD_CHANNEL="${ONLYMACS_BUILD_CHANNEL:-public}"
export ONLYMACS_BUILD_VERSION="${ONLYMACS_BUILD_VERSION:-$(onlymacs_resolve_build_version "$BUILD_CHANNEL")}"
export ONLYMACS_BUILD_CHANNEL="$BUILD_CHANNEL"
DEFAULT_COORDINATOR_URL="$(onlymacs_default_coordinator_url)"

onlymacs_release_require_nonlocal_coordinator_url "publish OnlyMacs update" "$DEFAULT_COORDINATOR_URL" || exit 1
export ONLYMACS_DEFAULT_COORDINATOR_URL="$DEFAULT_COORDINATOR_URL"

DMG_PATH="$ROOT_DIR/dist/OnlyMacs-public.dmg"
DMG_MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-manifest.json"
DMG_CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public.sha256"
SPARKLE_BIN_DIR="$PACKAGE_PATH/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_KEYS="$SPARKLE_BIN_DIR/generate_keys"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"

if [[ ! -x "$GENERATE_KEYS" || ! -x "$GENERATE_APPCAST" ]]; then
  swift package resolve --package-path "$PACKAGE_PATH" >/dev/null
fi

if [[ ! -x "$GENERATE_KEYS" || ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle tools are unavailable. Resolve the macOS package dependencies first." >&2
  exit 1
fi

ensure_public_key_file() {
  local public_key=""
  if [[ -f "$PUBLIC_KEY_FILE" ]]; then
    public_key="$(tr -d '\n' < "$PUBLIC_KEY_FILE")"
  else
    public_key="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null || true)"
    public_key="$(printf '%s\n' "$public_key" | sed -n 's@.*<string>\(.*\)</string>.*@\1@p' | tail -n1)"
    if [[ -n "$public_key" ]]; then
      mkdir -p "$(dirname "$PUBLIC_KEY_FILE")"
      printf '%s\n' "$public_key" > "$PUBLIC_KEY_FILE"
    fi
  fi

  if [[ -z "$public_key" ]]; then
    echo "Could not resolve the Sparkle public key for account '$SPARKLE_ACCOUNT'." >&2
    echo "Run $GENERATE_KEYS --account $SPARKLE_ACCOUNT once and try again." >&2
    exit 1
  fi
}

build_release_dmg() {
  if [[ "$REBUILD_DMG" == "0" ]]; then
    return
  fi

  if [[ -n "${ONLYMACS_CODESIGN_IDENTITY:-}" ]]; then
    ONLYMACS_DEFAULT_COORDINATOR_URL="$DEFAULT_COORDINATOR_URL" "$ROOT_DIR/scripts/build-macos-app-public.sh" >/dev/null
    "$ROOT_DIR/scripts/sign-macos-public.sh" >/dev/null
    ONLYMACS_REBUILD_APP=0 "$ROOT_DIR/scripts/build-macos-dmg-public.sh" >/dev/null
    if [[ -n "${ONLYMACS_TEAM_ID:-}" ]] && {
      [[ -n "${ONLYMACS_NOTARY_PROFILE:-}" ]] ||
      {
        [[ -n "${ONLYMACS_ASC_KEY_PATH:-}" ]] &&
        [[ -n "${ONLYMACS_ASC_KEY_ID:-}" ]] &&
        [[ -n "${ONLYMACS_ASC_ISSUER_ID:-}" ]]
      }
    }; then
      "$ROOT_DIR/scripts/notarize-macos-dmg-public.sh" >/dev/null
    fi
  else
    "$ROOT_DIR/scripts/build-macos-dmg-public.sh" >/dev/null
  fi
}

ensure_public_key_file
build_release_dmg

for required_path in "$DMG_PATH" "$DMG_MANIFEST_PATH" "$DMG_CHECKSUM_PATH"; do
  if [[ ! -f "$required_path" ]]; then
    echo "missing required Sparkle artifact: $required_path" >&2
    exit 1
  fi
done

if [[ ! -d "$SERVER_REPO/.git" ]]; then
  echo "missing Railway server repo: $SERVER_REPO" >&2
  exit 1
fi

if ! command -v railway >/dev/null 2>&1; then
  echo "railway CLI is required to publish OnlyMacs updates" >&2
  exit 1
fi

DMG_FIELDS="$(
python3 - "$DMG_MANIFEST_PATH" "$DMG_CHECKSUM_PATH" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
checksum = pathlib.Path(sys.argv[2]).read_text().strip().split()[0]

print(manifest["build_version"])
print(manifest["build_number"])
print(manifest["build_channel"])
print(manifest["build_timestamp"])
print(str(manifest["artifact_bytes"]))
print(checksum)
print("true" if manifest.get("app_signed") else "false")
print("true" if manifest.get("artifact_notarized") else "false")
print("true" if manifest.get("artifact_signed") else "false")
PY
)"

BUILD_VERSION="$(printf '%s\n' "$DMG_FIELDS" | sed -n '1p')"
BUILD_NUMBER="$(printf '%s\n' "$DMG_FIELDS" | sed -n '2p')"
BUILD_CHANNEL="$(printf '%s\n' "$DMG_FIELDS" | sed -n '3p')"
BUILD_TIMESTAMP="$(printf '%s\n' "$DMG_FIELDS" | sed -n '4p')"
ARTIFACT_BYTES="$(printf '%s\n' "$DMG_FIELDS" | sed -n '5p')"
ARTIFACT_SHA="$(printf '%s\n' "$DMG_FIELDS" | sed -n '6p')"
APP_SIGNED="$(printf '%s\n' "$DMG_FIELDS" | sed -n '7p')"
DMG_NOTARIZED="$(printf '%s\n' "$DMG_FIELDS" | sed -n '8p')"
DMG_SIGNED="$(printf '%s\n' "$DMG_FIELDS" | sed -n '9p')"

if [[ "$APP_SIGNED" != "true" && "$ALLOW_UNSIGNED" != "1" ]]; then
  echo "Refusing to publish an unsigned OnlyMacs Sparkle update." >&2
  echo "Set ONLYMACS_CODESIGN_IDENTITY and rebuild, or override with ONLYMACS_ALLOW_UNSIGNED_SPARKLE_PUBLISH=1 for local-only testing." >&2
  exit 1
fi

RELEASE_NOTES="${ONLYMACS_UPDATE_NOTES:-$(git -C "$ROOT_DIR" log -1 --pretty=%s 2>/dev/null || echo "OnlyMacs update")}"
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
APPCAST_NAME="appcast-${BUILD_CHANNEL}.xml"
RELEASE_NOTICE_NAME="latest-${BUILD_CHANNEL}.json"
ARTIFACT_FILE_NAME="OnlyMacs-${BUILD_CHANNEL}-${BUILD_VERSION}-${BUILD_NUMBER}.dmg"
CHECKSUM_FILE_NAME="OnlyMacs-${BUILD_CHANNEL}-${BUILD_VERSION}-${BUILD_NUMBER}.sha256"
MANIFEST_FILE_NAME="OnlyMacs-${BUILD_CHANNEL}-${BUILD_VERSION}-${BUILD_NUMBER}-manifest.json"

PUBLISH_KEY="$(
  cd "$SERVER_REPO" &&
  railway variable --service "$SERVER_SERVICE" --environment "$SERVER_ENVIRONMENT" --json | jq -r '.ONLYMACS_UPDATE_PUBLISH_KEY // empty'
)"

if [[ -z "$PUBLISH_KEY" ]]; then
  PUBLISH_KEY="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
  (
    cd "$SERVER_REPO"
    railway variable set --service "$SERVER_SERVICE" --environment "$SERVER_ENVIRONMENT" "ONLYMACS_UPDATE_PUBLISH_KEY=$PUBLISH_KEY" >/dev/null
  )
  ONLYMACS_RAILWAY_CONTEXT_DIR="$SERVER_REPO" \
    ONLYMACS_RAILWAY_COORDINATOR_SERVICE="$SERVER_SERVICE" \
    ONLYMACS_RAILWAY_ENVIRONMENT="$SERVER_ENVIRONMENT" \
    "$ROOT_DIR/scripts/deploy-railway-coordinator.sh" >/dev/null

  for _ in $(seq 1 60); do
    if curl --fail --silent --show-error "$SERVER_BASE_URL/health" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-sparkle-publish.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVES_DIR="$TEMP_DIR/archives"
mkdir -p "$ARCHIVES_DIR"

cp "$DMG_PATH" "$ARCHIVES_DIR/$ARTIFACT_FILE_NAME"
cp "$DMG_MANIFEST_PATH" "$ARCHIVES_DIR/$MANIFEST_FILE_NAME"
cp "$DMG_CHECKSUM_PATH" "$ARCHIVES_DIR/$CHECKSUM_FILE_NAME"
printf '%s\n' "$RELEASE_NOTES" > "$ARCHIVES_DIR/${ARTIFACT_FILE_NAME%.dmg}.md"

"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$SERVER_BASE_URL/onlymacs/updates/files/" \
  --channel "$BUILD_CHANNEL" \
  --embed-release-notes \
  -o "$ARCHIVES_DIR/$APPCAST_NAME" \
  "$ARCHIVES_DIR" >/dev/null

python3 - \
  "$ARCHIVES_DIR/$RELEASE_NOTICE_NAME" \
  "$BUILD_VERSION" \
  "$BUILD_NUMBER" \
  "$BUILD_CHANNEL" \
  "$BUILD_TIMESTAMP" \
  "$SERVER_BASE_URL/onlymacs/updates/$APPCAST_NAME" \
  "$SERVER_BASE_URL/onlymacs/updates/files/$ARTIFACT_FILE_NAME" \
  "$RELEASE_NOTES" \
  "$GIT_COMMIT" <<'PY'
import json
import pathlib
import sys

output_path = pathlib.Path(sys.argv[1])
payload = {
    "version": sys.argv[2],
    "build_number": sys.argv[3],
    "channel": sys.argv[4],
    "published_at": sys.argv[5],
    "appcast_url": sys.argv[6],
    "archive_url": sys.argv[7],
    "release_notes": sys.argv[8],
    "commit": sys.argv[9],
}

output_path.write_text(json.dumps(payload, indent=2) + "\n")
PY

upload_file() {
  local source_path="$1"
  local target_url="$2"
  local content_type="$3"

  curl --fail --silent --show-error \
    --http1.1 \
    --connect-timeout 20 \
    --max-time 300 \
    --retry 2 \
    --retry-delay 3 \
    --retry-all-errors \
    --request PUT \
    --header "x-onlymacs-publish-key: $PUBLISH_KEY" \
    --header "content-type: $content_type" \
    --data-binary "@$source_path" \
    "$target_url" >/dev/null
}

upload_file \
  "$ARCHIVES_DIR/$ARTIFACT_FILE_NAME" \
  "$UPLOAD_BASE_URL/internal/onlymacs/updates/files/$ARTIFACT_FILE_NAME" \
  "application/octet-stream"

upload_file \
  "$ARCHIVES_DIR/$MANIFEST_FILE_NAME" \
  "$UPLOAD_BASE_URL/internal/onlymacs/updates/files/$MANIFEST_FILE_NAME" \
  "application/octet-stream"

upload_file \
  "$ARCHIVES_DIR/$CHECKSUM_FILE_NAME" \
  "$UPLOAD_BASE_URL/internal/onlymacs/updates/files/$CHECKSUM_FILE_NAME" \
  "text/plain"

upload_file \
  "$ARCHIVES_DIR/$APPCAST_NAME" \
  "$UPLOAD_BASE_URL/internal/onlymacs/updates/manifests/$APPCAST_NAME" \
  "application/xml"

upload_file \
  "$ARCHIVES_DIR/$RELEASE_NOTICE_NAME" \
  "$UPLOAD_BASE_URL/internal/onlymacs/updates/manifests/$RELEASE_NOTICE_NAME" \
  "application/octet-stream"

if ! curl --fail --silent --show-error "$SERVER_BASE_URL/onlymacs/updates/$APPCAST_NAME" | rg -q "$BUILD_NUMBER"; then
  echo "published Sparkle appcast verification failed for build $BUILD_NUMBER" >&2
  exit 1
fi

if ! curl --fail --silent --show-error "$SERVER_BASE_URL/onlymacs/updates/$RELEASE_NOTICE_NAME" | rg -q "$BUILD_NUMBER"; then
  echo "published release notice verification failed for build $BUILD_NUMBER" >&2
  exit 1
fi

cat <<EOF
Published OnlyMacs Sparkle update
Appcast: $SERVER_BASE_URL/onlymacs/updates/$APPCAST_NAME
Release notice: $SERVER_BASE_URL/onlymacs/updates/$RELEASE_NOTICE_NAME
Build: $BUILD_VERSION ($BUILD_NUMBER) $BUILD_CHANNEL
Archive: $SERVER_BASE_URL/onlymacs/updates/files/$ARTIFACT_FILE_NAME
Signed: $APP_SIGNED
DMG signed: $DMG_SIGNED
Notarized: $DMG_NOTARIZED
Commit: ${GIT_COMMIT:-unknown}
EOF
