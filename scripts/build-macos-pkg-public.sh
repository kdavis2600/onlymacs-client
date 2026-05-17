#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/macos-pkg/build-lib.sh"

APP_PATH="${ONLYMACS_APP_PATH:-$ROOT_DIR/dist/OnlyMacs.app}"
PKG_PATH="$ROOT_DIR/dist/OnlyMacs-public.pkg"
MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg-manifest.json"
CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg.sha256"
WELCOME_TEMPLATE_PATH="$ROOT_DIR/scripts/macos-pkg/welcome.html"
CONCLUSION_TEMPLATE_PATH="$ROOT_DIR/scripts/macos-pkg/conclusion.html"
DISTIBUTION_TEMPLATE_PATH="$ROOT_DIR/scripts/macos-pkg/distribution.xml.tmpl"
INSTALLER_SESSION_HELPER_PATH="$ROOT_DIR/scripts/macos-pkg/installer-session-helper.sh"
PACKAGE_SCRIPTS_DIR="$ROOT_DIR/scripts/macos-pkg/package-scripts"
INSTALLER_SELECTIONS_ROOT="/Library/Application Support/OnlyMacs/InstallerSelections"
INSTALLER_APP_PATH="/Applications/OnlyMacs.app"
INSTALLER_APP_ARG="--onlymacs-apply-installer-selections"
REBUILD_APP="${ONLYMACS_REBUILD_APP:-1}"
SIGN_APP_FIRST="${ONLYMACS_SIGN_APP_BEFORE_PKG:-}"
INSTALLER_IDENTITY="${ONLYMACS_INSTALLER_IDENTITY:-}"
DEFAULT_COORDINATOR_URL="${ONLYMACS_DEFAULT_COORDINATOR_URL:-}"

if [[ -z "$SIGN_APP_FIRST" ]]; then
  if [[ -n "${ONLYMACS_CODESIGN_IDENTITY:-}" ]]; then
    SIGN_APP_FIRST="1"
  else
    SIGN_APP_FIRST="0"
  fi
fi

if [[ "$REBUILD_APP" != "0" ]]; then
  if [[ -z "$DEFAULT_COORDINATOR_URL" && -f "$APP_PATH/Contents/Info.plist" ]]; then
    DEFAULT_COORDINATOR_URL="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsDefaultCoordinatorURL' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [[ -n "$DEFAULT_COORDINATOR_URL" ]]; then
    build_output="$(ONLYMACS_DEFAULT_COORDINATOR_URL="$DEFAULT_COORDINATOR_URL" "$ROOT_DIR/scripts/build-macos-app-public.sh")"
  else
    build_output="$("$ROOT_DIR/scripts/build-macos-app-public.sh")"
  fi
  APP_PATH="${ONLYMACS_APP_PATH:-$build_output}"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "missing app bundle: $APP_PATH" >&2
  echo "build it first with: make macos-app-public" >&2
  exit 1
fi

if [[ "$SIGN_APP_FIRST" == "1" && -n "${ONLYMACS_CODESIGN_IDENTITY:-}" ]]; then
  ONLYMACS_APP_DIR="$APP_PATH" "$ROOT_DIR/scripts/sign-macos-public.sh" >/dev/null
fi

for required_path in \
  "$WELCOME_TEMPLATE_PATH" \
  "$CONCLUSION_TEMPLATE_PATH" \
  "$DISTIBUTION_TEMPLATE_PATH" \
  "$INSTALLER_SESSION_HELPER_PATH"; do
  require_installer_resource "$required_path"
done

for required_path in \
  "$PACKAGE_SCRIPTS_DIR/seed-reset.sh" \
  "$PACKAGE_SCRIPTS_DIR/install-core-tools.sh" \
  "$PACKAGE_SCRIPTS_DIR/join-public.sh" \
  "$PACKAGE_SCRIPTS_DIR/share-this-mac.sh" \
  "$PACKAGE_SCRIPTS_DIR/run-on-startup.sh" \
  "$PACKAGE_SCRIPTS_DIR/install-starter-models.sh" \
  "$PACKAGE_SCRIPTS_DIR/install-codex.sh" \
  "$PACKAGE_SCRIPTS_DIR/install-claude.sh" \
  "$PACKAGE_SCRIPTS_DIR/finalize.sh"; do
  require_installer_resource "$required_path"
done

INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"
BUNDLE_ID="$(plist_value "$INFO_PLIST_PATH" "CFBundleIdentifier")"
VERSION="$(plist_value "$INFO_PLIST_PATH" "CFBundleShortVersionString")"
BUILD_NUMBER="$(plist_value "$INFO_PLIST_PATH" "CFBundleVersion")"
BUILD_CHANNEL="$(plist_value "$INFO_PLIST_PATH" "OnlyMacsBuildChannel")"
BUILD_TIMESTAMP="$(plist_value "$INFO_PLIST_PATH" "OnlyMacsBuildTimestamp")"
APP_DEFAULT_COORDINATOR_URL="$(/usr/libexec/PlistBuddy -c 'Print :OnlyMacsDefaultCoordinatorURL' "$INFO_PLIST_PATH" 2>/dev/null || true)"

rm -f "$PKG_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/onlymacs-pkg.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

COMPONENT_PKG_PATH="$TEMP_DIR/OnlyMacs-component.pkg"
COMPONENT_PLIST_PATH="$TEMP_DIR/OnlyMacs-component.plist"
STAGED_APP_PATH="$TEMP_DIR/OnlyMacs.app"
PAYLOAD_ROOT="$TEMP_DIR/payload-root"
SEED_RESET_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-reset.pkg"
SEED_CORE_TOOLS_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-core-tools.pkg"
SEED_PUBLIC_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-public.pkg"
SEED_SHARE_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-share.pkg"
SEED_STARTUP_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-startup.pkg"
SEED_MODELS_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-models.pkg"
SEED_CODEX_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-codex.pkg"
SEED_CLAUDE_PKG_PATH="$TEMP_DIR/OnlyMacs-seed-claude.pkg"
FINALIZE_PKG_PATH="$TEMP_DIR/OnlyMacs-finalize.pkg"
RESOURCES_DIR="$TEMP_DIR/resources"
DISTRIBUTION_PATH="$TEMP_DIR/Distribution"
WELCOME_HTML_PATH="$RESOURCES_DIR/welcome.html"
CONCLUSION_HTML_PATH="$RESOURCES_DIR/conclusion.html"

mkdir -p "$RESOURCES_DIR"
rm -rf "$STAGED_APP_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGED_APP_PATH"
mkdir -p "$PAYLOAD_ROOT/Applications"
/usr/bin/ditto "$STAGED_APP_PATH" "$PAYLOAD_ROOT/Applications/OnlyMacs.app"

pkgbuild --analyze --root "$PAYLOAD_ROOT" "$COMPONENT_PLIST_PATH" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST_PATH" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier false" "$COMPONENT_PLIST_PATH" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked false" "$COMPONENT_PLIST_PATH" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleOverwriteAction upgrade" "$COMPONENT_PLIST_PATH" >/dev/null

pkgbuild \
  --identifier "${BUNDLE_ID}.pkg" \
  --version "$VERSION" \
  --root "$PAYLOAD_ROOT" \
  --component-plist "$COMPONENT_PLIST_PATH" \
  --install-location / \
  "$COMPONENT_PKG_PATH" >/dev/null

build_script_package \
  "$SEED_RESET_PKG_PATH" \
  "${BUNDLE_ID}.seed.reset" \
  "$PACKAGE_SCRIPTS_DIR/seed-reset.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT" \
  "BUILD_VERSION=$VERSION" \
  "BUILD_NUMBER=$BUILD_NUMBER" \
  "BUILD_CHANNEL=$BUILD_CHANNEL"

build_script_package \
  "$SEED_CORE_TOOLS_PKG_PATH" \
  "${BUNDLE_ID}.seed.core-tools" \
  "$PACKAGE_SCRIPTS_DIR/install-core-tools.sh" \
  "ONLYMACS_INSTALLER_INTEGRATION_ROOT=$INSTALLER_APP_PATH/Contents/Resources/Integrations"

build_script_package \
  "$SEED_PUBLIC_PKG_PATH" \
  "${BUNDLE_ID}.seed.public" \
  "$PACKAGE_SCRIPTS_DIR/join-public.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT"

build_script_package \
  "$SEED_SHARE_PKG_PATH" \
  "${BUNDLE_ID}.seed.share" \
  "$PACKAGE_SCRIPTS_DIR/share-this-mac.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT"

build_script_package \
  "$SEED_STARTUP_PKG_PATH" \
  "${BUNDLE_ID}.seed.startup" \
  "$PACKAGE_SCRIPTS_DIR/run-on-startup.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT" \
  "ONLYMACS_INSTALLER_APP_PATH=$INSTALLER_APP_PATH"

build_script_package \
  "$SEED_MODELS_PKG_PATH" \
  "${BUNDLE_ID}.seed.models" \
  "$PACKAGE_SCRIPTS_DIR/install-starter-models.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT"

build_script_package \
  "$SEED_CODEX_PKG_PATH" \
  "${BUNDLE_ID}.seed.codex" \
  "$PACKAGE_SCRIPTS_DIR/install-codex.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT" \
  "ONLYMACS_INSTALLER_INTEGRATION_ROOT=$INSTALLER_APP_PATH/Contents/Resources/Integrations"

build_script_package \
  "$SEED_CLAUDE_PKG_PATH" \
  "${BUNDLE_ID}.seed.claude" \
  "$PACKAGE_SCRIPTS_DIR/install-claude.sh" \
  "SELECTION_ROOT=$INSTALLER_SELECTIONS_ROOT" \
  "ONLYMACS_INSTALLER_INTEGRATION_ROOT=$INSTALLER_APP_PATH/Contents/Resources/Integrations"

build_script_package \
  "$FINALIZE_PKG_PATH" \
  "${BUNDLE_ID}.finalize" \
  "$PACKAGE_SCRIPTS_DIR/finalize.sh" \
  "ONLYMACS_INSTALLER_APP_PATH=$INSTALLER_APP_PATH" \
  "ONLYMACS_INSTALLER_APP_ARG=$INSTALLER_APP_ARG"

render_installer_template \
  "$WELCOME_TEMPLATE_PATH" \
  "$WELCOME_HTML_PATH" \
  "VERSION=$VERSION" \
  "BUILD_NUMBER=$BUILD_NUMBER" \
  "BUILD_CHANNEL=$BUILD_CHANNEL"

render_installer_template \
  "$CONCLUSION_TEMPLATE_PATH" \
  "$CONCLUSION_HTML_PATH" \
  "VERSION=$VERSION" \
  "BUILD_NUMBER=$BUILD_NUMBER" \
  "BUILD_CHANNEL=$BUILD_CHANNEL"

render_installer_template \
  "$DISTIBUTION_TEMPLATE_PATH" \
  "$DISTRIBUTION_PATH" \
  "BUNDLE_ID=$BUNDLE_ID" \
  "VERSION=$VERSION"

productbuild_arguments=(
  --distribution "$DISTRIBUTION_PATH"
  --resources "$RESOURCES_DIR"
  --package-path "$TEMP_DIR"
)

if [[ -n "$INSTALLER_IDENTITY" ]]; then
  productbuild_arguments+=(--sign "$INSTALLER_IDENTITY")
fi

productbuild "${productbuild_arguments[@]}" "$PKG_PATH" >/dev/null

PKG_SHA256="$(shasum -a 256 "$PKG_PATH" | awk '{print $1}')"
PKG_BYTES="$(stat -f%z "$PKG_PATH")"
APP_BYTES="$(du -sk "$APP_PATH" | awk '{print $1 * 1024}')"
CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
APP_SIGNED="false"
APP_SIGNING_AUTHORITY=""
APP_SIGNING_TEAM_ID=""
PKG_SIGNED="false"
PKG_SIGNING_AUTHORITY=""

if codesign --verify --deep --strict "$STAGED_APP_PATH" >/dev/null 2>&1 &&
   codesign_output="$(codesign -dv --verbose=4 "$STAGED_APP_PATH" 2>&1)"; then
  APP_SIGNED="true"
  APP_SIGNING_AUTHORITY="$(printf '%s\n' "$codesign_output" | awk -F= '/^Authority=/{print $2; exit}')"
  APP_SIGNING_TEAM_ID="$(printf '%s\n' "$codesign_output" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
fi

pkg_signature_output="$(pkgutil --check-signature "$PKG_PATH" 2>&1 || true)"
if ! printf '%s\n' "$pkg_signature_output" | grep -qi "no signature"; then
  PKG_SIGNED="true"
  PKG_SIGNING_AUTHORITY="$(printf '%s\n' "$pkg_signature_output" | awk '/^[[:space:]]*[0-9]+\./{sub(/^[[:space:]]*[0-9]+\.[[:space:]]*/, ""); print; exit}')"
fi

printf "%s  %s\n" "$PKG_SHA256" "$(basename "$PKG_PATH")" > "$CHECKSUM_PATH"

cat > "$MANIFEST_PATH" <<EOF
{
  "artifact": "OnlyMacs-public.pkg",
  "artifact_path": "$PKG_PATH",
  "artifact_sha256": "$PKG_SHA256",
  "artifact_bytes": $PKG_BYTES,
  "artifact_notarized": false,
  "installer_welcome_art": false,
  "installer_ui": "product-package",
  "app_path": "$APP_PATH",
  "app_bytes": $APP_BYTES,
  "bundle_id": "$BUNDLE_ID",
  "build_version": "$VERSION",
  "build_number": "$BUILD_NUMBER",
  "build_timestamp": "$BUILD_TIMESTAMP",
  "build_channel": "$BUILD_CHANNEL",
  "default_coordinator_url": "$APP_DEFAULT_COORDINATOR_URL",
  "app_signed": $APP_SIGNED,
  "app_signing_authority": "$APP_SIGNING_AUTHORITY",
  "app_signing_team_id": "$APP_SIGNING_TEAM_ID",
  "pkg_signed": $PKG_SIGNED,
  "pkg_signing_authority": "$PKG_SIGNING_AUTHORITY",
  "app_rebuilt_during_packaging": $([[ "$REBUILD_APP" == "1" ]] && echo true || echo false),
  "created_at": "$CREATED_AT"
}
EOF

echo "$PKG_PATH"
