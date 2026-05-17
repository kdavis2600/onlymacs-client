#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_coordinator_repo "$ROOT_DIR")"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS %s\n' "$1"
}

rg -q 'ONLYMACS_BUILD_VERSION:-0\.1\.1' "$ROOT_DIR/scripts/build-macos-app-public.sh" \
  || fail "macOS app build should default to 0.1.x beta versioning"
pass "macOS build defaults to 0.1.x versioning"

rg -q 'onlymacs\.ai/onlymacs/updates/appcast-' "$ROOT_DIR/scripts/build-macos-app-public.sh" \
  || fail "Sparkle feed should default to the OnlyMacs coordinator"
pass "Sparkle feed defaults to the OnlyMacs coordinator"

rg -q 'onlymacs\.ai' "$ROOT_DIR/scripts/publish-onlymacs-update.sh" "$ROOT_DIR/scripts/onlymacs-release-config.sh" \
  || fail "Sparkle publish script should publish release metadata to the coordinator"
rg -q 'ONLYMACS_RAILWAY_CONTEXT_DIR' "$ROOT_DIR/scripts/publish-onlymacs-update.sh" "$ROOT_DIR/scripts/onlymacs-release-config.sh" \
  || fail "Sparkle publish script should use the linked Railway context by default"
rg -q 'railway variable set --service' "$ROOT_DIR/scripts/publish-onlymacs-update.sh" \
  || fail "Sparkle publish script should set first-run publish keys with the current Railway CLI syntax"
rg -q 'deploy-railway-coordinator\.sh' "$ROOT_DIR/scripts/publish-onlymacs-update.sh" \
  || fail "Sparkle publish script should redeploy after creating a first-run publish key"
pass "Sparkle publish script targets the coordinator by default"

for step in \
  'Build unsigned app bundle' \
  'Sign app bundle' \
  'Notarize installer package' \
  'Sync hosted website package' \
  'Deploy coordinator website and update server' \
  'Publish Sparkle update and release notice'
do
  rg -q "$step" "$ROOT_DIR/scripts/release-onlymacs.sh" || fail "release script is missing step: $step"
done
pass "release script includes build, sign, notarize, Sparkle publication"

rg -q 'OnlyMacs-latest\.pkg' "$ROOT_DIR/scripts/sync-onlymacs-web-package.sh" \
  || fail "website package sync should refresh the hosted download package"
rg -q 'COORDINATOR_REPO/downloads/OnlyMacs-latest\.pkg' "$ROOT_DIR/scripts/sync-onlymacs-web-package.sh" \
  || fail "website package sync should keep installers outside embedded webstatic"
rg -q -- "--exclude='/downloads/'" "$ROOT_DIR/scripts/sync-onlymacs-web-static.sh" \
  || fail "web static sync should exclude installer downloads from embedded assets"
pass "release script refreshes hosted website package without embedding it in the app"

rg -q 'Join Waitlist' "$ROOT_DIR/apps/onlymacs-web/src/components/HeroContent.tsx" \
  || fail "web primary CTA should join the waitlist"
rg -q '/waitlist/join' "$ROOT_DIR/apps/onlymacs-web/src/components/HeroContent.tsx" \
  || fail "web waitlist CTA should link to the hosted waitlist form"
rg -q 'I have an invite code' "$ROOT_DIR/apps/onlymacs-web/src/components/HeroContent.tsx" \
  || fail "web secondary CTA should offer invite code redemption"
rg -q '/redeem' "$ROOT_DIR/apps/onlymacs-web/src/components/HeroContent.tsx" \
  || fail "web invite CTA should link to the hosted redeem form"
rg -q '/downloads/OnlyMacs-latest\.pkg' "$COORDINATOR_REPO/internal/httpapi/router.go" \
  || fail "coordinator should gate the hosted package behind invite redemption"
pass "web CTA routes visitors through waitlist and invite redemption"

rg -q '/internal/onlymacs/updates/files/' "$COORDINATOR_REPO/internal/httpapi/update_handlers.go" "$ROOT_DIR/scripts/publish-onlymacs-update.sh" \
  || fail "coordinator update upload endpoints should be wired"
pass "coordinator update hosting endpoints are wired"
