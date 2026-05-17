#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/OnlyMacs.app"
DMG_PATH="$ROOT_DIR/dist/OnlyMacs-public.dmg"
MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-manifest.json"
CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public.sha256"
PKG_PATH="$ROOT_DIR/dist/OnlyMacs-public.pkg"
PKG_MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg-manifest.json"
PKG_CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg.sha256"

internal_missing=0
external_missing=0

pass() {
  printf 'PASS  %s\n' "$1"
}

warn() {
  printf 'WARN  %s\n' "$1"
}

fail_internal() {
  printf 'FAIL  %s\n' "$1"
  internal_missing=1
}

fail_external() {
  printf 'FAIL  %s\n' "$1"
  external_missing=1
}

check_file() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    pass "$label present"
  else
    fail_internal "$label missing ($path)"
  fi
}

check_command() {
  local cmd="$1"
  local label="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label available"
  else
    fail_external "$label missing"
  fi
}

check_xcrun_tool() {
  local tool="$1"
  local label="$2"
  if xcrun --find "$tool" >/dev/null 2>&1; then
    pass "$label available"
  else
    fail_external "$label missing"
  fi
}

echo "OnlyMacs release readiness"
echo "========================="

check_file "$APP_DIR" "Unsigned app bundle"
check_file "$DMG_PATH" "Unsigned DMG"
check_file "$MANIFEST_PATH" "Artifact manifest"
check_file "$CHECKSUM_PATH" "Artifact checksum"
check_file "$PKG_PATH" "Installer package"
check_file "$PKG_MANIFEST_PATH" "Installer manifest"
check_file "$PKG_CHECKSUM_PATH" "Installer checksum"

if [[ -e "$DMG_PATH" && -e "$MANIFEST_PATH" && -e "$CHECKSUM_PATH" ]]; then
  if "$ROOT_DIR/scripts/verify-macos-dmg-public.sh" >/dev/null 2>&1; then
    pass "Unsigned artifact verification passes"
  else
    fail_internal "Unsigned artifact verification failed (rebuild with make macos-dmg-public)"
  fi
fi

if [[ -e "$PKG_PATH" && -e "$PKG_MANIFEST_PATH" && -e "$PKG_CHECKSUM_PATH" ]]; then
  if "$ROOT_DIR/scripts/verify-macos-pkg-public.sh" >/dev/null 2>&1; then
    pass "Installer artifact verification passes"
  else
    fail_internal "Installer artifact verification failed (rebuild with make macos-pkg-public)"
  fi
fi

if ONLYMACS_REBUILD_APP=1 "$ROOT_DIR/scripts/make-app-bundle-smoke.sh" >/dev/null 2>&1; then
  pass "Packaged app smoke check passes"
else
  fail_internal "Packaged app smoke check failed (rebuild with make macos-app-public)"
fi

check_command codesign "codesign"
check_command productsign "productsign"
check_xcrun_tool notarytool "notarytool"
check_xcrun_tool stapler "stapler"

if command -v security >/dev/null 2>&1; then
  if security find-identity -v -p codesigning 2>/dev/null | rg -q "Developer ID Application"; then
    pass "Developer ID Application identity visible in keychain"
  else
    fail_external "Developer ID Application identity not visible in keychain"
  fi
  if security find-identity -v -p basic 2>/dev/null | rg -q "Developer ID Installer"; then
    pass "Developer ID Installer identity visible in keychain"
  else
    fail_external "Developer ID Installer identity not visible in keychain"
  fi
else
  fail_external "security tool missing"
fi

if [[ -n "${ONLYMACS_CODESIGN_IDENTITY:-}" ]]; then
  pass "ONLYMACS_CODESIGN_IDENTITY set"
else
  fail_external "ONLYMACS_CODESIGN_IDENTITY is not set"
fi

if [[ -n "${ONLYMACS_INSTALLER_IDENTITY:-}" ]]; then
  pass "ONLYMACS_INSTALLER_IDENTITY set"
else
  fail_external "ONLYMACS_INSTALLER_IDENTITY is not set"
fi

if [[ -n "${ONLYMACS_TEAM_ID:-}" ]]; then
  pass "ONLYMACS_TEAM_ID set"
else
  fail_external "ONLYMACS_TEAM_ID is not set"
fi

if [[ -n "${ONLYMACS_NOTARY_PROFILE:-}" ]]; then
  pass "ONLYMACS_NOTARY_PROFILE set"
elif [[ -n "${ONLYMACS_ASC_KEY_PATH:-}" && -n "${ONLYMACS_ASC_KEY_ID:-}" && -n "${ONLYMACS_ASC_ISSUER_ID:-}" ]]; then
  pass "Direct App Store Connect notarization credentials set"
else
  fail_external "Neither ONLYMACS_NOTARY_PROFILE nor ONLYMACS_ASC_KEY_PATH/ONLYMACS_ASC_KEY_ID/ONLYMACS_ASC_ISSUER_ID are set"
fi

echo
if [[ "$internal_missing" -eq 0 && "$external_missing" -eq 0 ]]; then
  echo "Release readiness looks good: remaining work is implementation and release execution."
  exit 0
fi

echo "Release readiness is not complete."
if [[ "$internal_missing" -ne 0 ]]; then
  echo "Internal follow-up required before external release checks are meaningful:"
  echo "- rebuild the unsigned DMG with make macos-dmg-public"
  echo "- rebuild the unsigned installer package with make macos-pkg-public"
fi
if [[ "$external_missing" -ne 0 ]]; then
  echo "Expected external prerequisites before the signed/notarized checkpoint can finish:"
  echo "- Developer ID Application identity installed on this Mac"
  echo "- Developer ID Installer identity installed on this Mac"
  echo "- ONLYMACS_CODESIGN_IDENTITY set to that identity"
  echo "- ONLYMACS_INSTALLER_IDENTITY set to the Developer ID Installer identity"
  echo "- ONLYMACS_TEAM_ID set"
  echo "- ONLYMACS_NOTARY_PROFILE set to a stored notarytool profile, or ONLYMACS_ASC_KEY_PATH/ONLYMACS_ASC_KEY_ID/ONLYMACS_ASC_ISSUER_ID set"
fi
exit 1
