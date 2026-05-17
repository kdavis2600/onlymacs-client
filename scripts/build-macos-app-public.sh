#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/macos-app/build-lib.sh"

APP_NAME="OnlyMacs"
DEFAULT_APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
APP_DIR="${ONLYMACS_APP_DIR:-$DEFAULT_APP_DIR}"
HELPER_BUILD_DIR="$ROOT_DIR/.tmp/bin"
PACKAGE_PATH="$ROOT_DIR/apps/onlymacs-macos"
INFO_PLIST_TEMPLATE_PATH="$ROOT_DIR/scripts/macos-app/Info.plist.tmpl"
APP_ICON_SOURCE="$ROOT_DIR/only-macs-app-icon.jpg"
MENU_BAR_ICON_SOURCE="$ROOT_DIR/app-icon-logo.png"
INSTALLER_ART_SOURCE="$ROOT_DIR/only-macs-installer.png"
BUILD_VERSION="${ONLYMACS_BUILD_VERSION:-0.1.1}"
BUILD_NUMBER="${ONLYMACS_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
BUILD_TIMESTAMP="${ONLYMACS_BUILD_TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
BUILD_CHANNEL="${ONLYMACS_BUILD_CHANNEL:-public}"
BUNDLE_ID="${ONLYMACS_BUNDLE_ID:-com.kizzle.onlymacs}"
URL_NAME="${ONLYMACS_URL_NAME:-${BUNDLE_ID}.invites}"
SPARKLE_FEED_URL="${ONLYMACS_SPARKLE_FEED_URL:-https://onlymacs.ai/onlymacs/updates/appcast-${BUILD_CHANNEL}.xml}"
SPARKLE_PUBLIC_KEY_FILE="${ONLYMACS_SPARKLE_PUBLIC_KEY_FILE:-$ROOT_DIR/config/macos/OnlyMacs.sparkle-public-ed25519.txt}"
SPARKLE_PUBLIC_KEY="${ONLYMACS_SPARKLE_PUBLIC_KEY:-}"
DEFAULT_COORDINATOR_URL="${ONLYMACS_DEFAULT_COORDINATOR_URL:-https://onlymacs.ai}"
ADHOC_SIGN_BUILD="${ONLYMACS_ADHOC_SIGN_BUILD:-1}"
SPARKLE_FRAMEWORK_SOURCE="$PACKAGE_PATH/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

require_build_asset "$INFO_PLIST_TEMPLATE_PATH"

if ! rm -rf "$APP_DIR" 2>/dev/null; then
  if [[ -z "${ONLYMACS_APP_DIR:-}" ]]; then
    BUILD_ROOT="$(mktemp -d "$ROOT_DIR/.tmp/onlymacs-app-build.XXXXXX")"
    APP_DIR="$BUILD_ROOT/$APP_NAME.app"
  else
    echo "unable to remove existing app bundle: $APP_DIR" >&2
    exit 1
  fi
fi

MACOS_DIR="$APP_DIR/Contents/MacOS"
HELPERS_DIR="$APP_DIR/Contents/Helpers"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

"$ROOT_DIR/scripts/build-helper-binaries.sh" "$HELPER_BUILD_DIR" >/dev/null

swift build --package-path "$PACKAGE_PATH" -c release >/dev/null
BIN_DIR="$(swift build --package-path "$PACKAGE_PATH" -c release --show-bin-path)"

cp "$BIN_DIR/OnlyMacsApp" "$MACOS_DIR/OnlyMacsApp"
if [[ -x "$HELPER_BUILD_DIR/onlymacs-coordinator" ]]; then
  cp "$HELPER_BUILD_DIR/onlymacs-coordinator" "$HELPERS_DIR/onlymacs-coordinator"
else
  echo "building app without bundled coordinator helper" >&2
fi
cp "$HELPER_BUILD_DIR/onlymacs-local-bridge" "$HELPERS_DIR/onlymacs-local-bridge"
if [[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  ditto "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/OnlyMacsApp" 2>/dev/null || true
fi
cp -R "$ROOT_DIR/integrations" "$RESOURCES_DIR/Integrations"
copy_if_present "$MENU_BAR_ICON_SOURCE" "$RESOURCES_DIR/app-icon-logo.png"
copy_if_present "$INSTALLER_ART_SOURCE" "$RESOURCES_DIR/only-macs-installer.png"
create_app_icon_icns "$APP_ICON_SOURCE" "$RESOURCES_DIR/OnlyMacs.icns"
shopt -s nullglob
swiftpm_resource_bundles=("$BIN_DIR"/*.bundle)
shopt -u nullglob

if [[ ${#swiftpm_resource_bundles[@]} -eq 0 ]]; then
  echo "missing SwiftPM resource bundles in $BIN_DIR" >&2
  exit 1
fi

for resource_bundle in "${swiftpm_resource_bundles[@]}"; do
  ditto "$resource_bundle" "$RESOURCES_DIR/$(basename "$resource_bundle")"
done

chmod +x "$MACOS_DIR/OnlyMacsApp" "$HELPERS_DIR/onlymacs-local-bridge"
if [[ -f "$HELPERS_DIR/onlymacs-coordinator" ]]; then
  chmod +x "$HELPERS_DIR/onlymacs-coordinator"
fi
find "$RESOURCES_DIR/Integrations" -name '*.sh' -exec chmod +x {} +

if [[ -z "$SPARKLE_PUBLIC_KEY" && -f "$SPARKLE_PUBLIC_KEY_FILE" ]]; then
  SPARKLE_PUBLIC_KEY="$(tr -d '\n' < "$SPARKLE_PUBLIC_KEY_FILE")"
fi

SPARKLE_INFO_KEYS="$(sparkle_plist_snippet "$SPARKLE_FEED_URL" "$SPARKLE_PUBLIC_KEY")"
DEFAULT_COORDINATOR_INFO_KEY="$(string_plist_key_snippet "OnlyMacsDefaultCoordinatorURL" "$DEFAULT_COORDINATOR_URL")"

render_app_info_plist \
  "$INFO_PLIST_TEMPLATE_PATH" \
  "$INFO_PLIST" \
  "BUNDLE_ID=$BUNDLE_ID" \
  "BUILD_VERSION=$BUILD_VERSION" \
  "URL_NAME=$URL_NAME" \
  "BUILD_NUMBER=$BUILD_NUMBER" \
  "BUILD_CHANNEL=$BUILD_CHANNEL" \
  "BUILD_TIMESTAMP=$BUILD_TIMESTAMP" \
  "DEFAULT_COORDINATOR_INFO_KEY=$DEFAULT_COORDINATOR_INFO_KEY" \
  "SPARKLE_INFO_KEYS=$SPARKLE_INFO_KEYS"

maybe_ad_hoc_sign_app "$APP_DIR" "$ADHOC_SIGN_BUILD"

echo "$APP_DIR"
