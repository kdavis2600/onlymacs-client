#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"
PKG_PATH="${ONLYMACS_WEB_PACKAGE_SOURCE:-$ROOT_DIR/dist/OnlyMacs-public.pkg}"
PACKAGE_TARGET_PATH="${ONLYMACS_WEB_PACKAGE_TARGET:-$COORDINATOR_REPO/downloads/OnlyMacs-latest.pkg}"
STALE_EMBEDDED_PACKAGE_PATH="$COORDINATOR_REPO/internal/webstatic/static/downloads/OnlyMacs-latest.pkg"

if [[ ! -f "$PKG_PATH" ]]; then
  echo "OnlyMacs web package source is missing: $PKG_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$PACKAGE_TARGET_PATH")"
cp "$PKG_PATH" "$PACKAGE_TARGET_PATH"
rm -f "$STALE_EMBEDDED_PACKAGE_PATH"
rmdir "$COORDINATOR_REPO/internal/webstatic/static/downloads" 2>/dev/null || true

source_sha="$(shasum -a 256 "$PKG_PATH" | awk '{print $1}')"
target_sha="$(shasum -a 256 "$PACKAGE_TARGET_PATH" | awk '{print $1}')"
if [[ "$source_sha" != "$target_sha" ]]; then
  echo "OnlyMacs web package sync failed: checksum mismatch" >&2
  exit 1
fi

echo "Synced OnlyMacs website package"
echo "Source: $PKG_PATH"
echo "Target: $PACKAGE_TARGET_PATH"
echo "SHA256: $target_sha"
