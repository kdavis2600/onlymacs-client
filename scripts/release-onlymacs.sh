#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/onlymacs-version-lib.sh"
source "$ROOT_DIR/scripts/onlymacs-release-config.sh"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

BUILD_CHANNEL="${ONLYMACS_BUILD_CHANNEL:-public}"
BUILD_VERSION="$(onlymacs_resolve_build_version "$BUILD_CHANNEL")"
BUILD_NUMBER="${ONLYMACS_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
BUILD_TIMESTAMP="${ONLYMACS_BUILD_TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
DEFAULT_COORDINATOR_URL="$(onlymacs_default_coordinator_url)"

onlymacs_release_require_nonlocal_coordinator_url "release OnlyMacs" "$DEFAULT_COORDINATOR_URL" || exit 1

export ONLYMACS_BUILD_VERSION="$BUILD_VERSION"
export ONLYMACS_BUILD_CHANNEL="$BUILD_CHANNEL"
export ONLYMACS_BUILD_NUMBER="$BUILD_NUMBER"
export ONLYMACS_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
export ONLYMACS_DEFAULT_COORDINATOR_URL="$DEFAULT_COORDINATOR_URL"
export ONLYMACS_EXPECT_DEFAULT_COORDINATOR_URL="$DEFAULT_COORDINATOR_URL"

APP_DIR=""

run_step() {
  local label="$1"
  shift
  echo "==> $label"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

run_step_capture() {
  local label="$1"
  shift
  echo "==> $label" >&2
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY RUN CAPTURE:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  "$@"
}

relaunch_installed_onlymacs() {
  local skip="${ONLYMACS_RELEASE_SKIP_RELAUNCH:-0}"
  local app_path="/Applications/OnlyMacs.app"
  local app_pid bridge_pid health installed_version installed_build
  local deadline

  if [[ "$skip" == "1" || "$skip" == "true" ]]; then
    echo "Skipping installed OnlyMacs relaunch because ONLYMACS_RELEASE_SKIP_RELAUNCH=$skip"
    return 0
  fi
  if [[ ! -d "$app_path" ]]; then
    echo "Installed OnlyMacs app not found at $app_path; cannot relaunch after release." >&2
    return 1
  fi

  /usr/bin/open -a OnlyMacs
  deadline=$((SECONDS + 30))
  while ((SECONDS < deadline)); do
    app_pid="$(pgrep -f "$app_path/Contents/MacOS/OnlyMacsApp" | head -1 || true)"
    bridge_pid="$(pgrep -f "$app_path/Contents/Helpers/onlymacs-local-bridge" | head -1 || true)"
    health="$(curl -fsS --max-time 2 http://127.0.0.1:4318/health 2>/dev/null || true)"
    if [[ -n "$app_pid" && -n "$bridge_pid" && "$health" == *'"status":"ok"'* ]]; then
      installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || printf 'unknown')"
      installed_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist" 2>/dev/null || printf 'unknown')"
      echo "Installed OnlyMacs running"
      echo "App PID: $app_pid"
      echo "Bridge PID: $bridge_pid"
      echo "Installed build: $installed_version ($installed_build)"
      echo "Bridge health: $health"
      if [[ "$installed_build" != "$BUILD_NUMBER" ]]; then
        echo "Installed app is behind published build $BUILD_VERSION ($BUILD_NUMBER); leaving OnlyMacs running so Sparkle can detect/apply the update."
      fi
      return 0
    fi
    sleep 1
  done

  echo "OnlyMacs did not relaunch cleanly after release." >&2
  echo "App PID: ${app_pid:-missing}" >&2
  echo "Bridge PID: ${bridge_pid:-missing}" >&2
  echo "Bridge health: ${health:-missing}" >&2
  return 1
}

echo "OnlyMacs release"
echo "Build: $BUILD_VERSION ($BUILD_NUMBER) $BUILD_CHANNEL"
echo "Timestamp: $BUILD_TIMESTAMP"
echo "Default coordinator: $DEFAULT_COORDINATOR_URL"

APP_DIR="$(run_step_capture "Build unsigned app bundle" \
  "$ROOT_DIR/scripts/build-macos-app-public.sh")"

run_step "Run packaged app smoke test" \
  env ONLYMACS_APP_DIR="$APP_DIR" ONLYMACS_REBUILD_APP=0 \
  "$ROOT_DIR/scripts/make-app-bundle-smoke.sh"

run_step "Sign app bundle" \
  env ONLYMACS_APP_DIR="$APP_DIR" \
  "$ROOT_DIR/scripts/sign-macos-public.sh"

run_step "Verify signed app bundle" \
  env ONLYMACS_APP_DIR="$APP_DIR" \
  "$ROOT_DIR/scripts/verify-signed-macos-public.sh"

run_step "Build signed installer package" \
  env ONLYMACS_APP_PATH="$APP_DIR" ONLYMACS_REBUILD_APP=0 ONLYMACS_SIGN_APP_BEFORE_PKG=0 \
  "$ROOT_DIR/scripts/build-macos-pkg-public.sh"

run_step "Notarize installer package" \
  "$ROOT_DIR/scripts/notarize-macos-pkg-public.sh"

run_step "Verify installer package" \
  "$ROOT_DIR/scripts/verify-macos-pkg-public.sh"

run_step "Build signed DMG archive" \
  env ONLYMACS_APP_PATH="$APP_DIR" ONLYMACS_REBUILD_APP=0 \
  "$ROOT_DIR/scripts/build-macos-dmg-public.sh"

run_step "Notarize DMG archive" \
  "$ROOT_DIR/scripts/notarize-macos-dmg-public.sh"

run_step "Verify DMG archive" \
  "$ROOT_DIR/scripts/verify-macos-dmg-public.sh"

run_step "Sync hosted website package" \
  "$ROOT_DIR/scripts/sync-onlymacs-web-package.sh"

run_step "Deploy coordinator website and update server" \
  "$ROOT_DIR/scripts/deploy-railway-coordinator.sh"

run_step "Publish Sparkle update and release notice" \
  env ONLYMACS_REBUILD_DMG_BEFORE_PUBLISH=0 \
  "$ROOT_DIR/scripts/publish-onlymacs-update.sh"

run_step "Relaunch installed OnlyMacs and verify local bridge" \
  relaunch_installed_onlymacs

echo
echo "OnlyMacs release finished"
echo "Build: $BUILD_VERSION ($BUILD_NUMBER) $BUILD_CHANNEL"
echo "PKG: $ROOT_DIR/dist/OnlyMacs-public.pkg"
echo "DMG: $ROOT_DIR/dist/OnlyMacs-public.dmg"
