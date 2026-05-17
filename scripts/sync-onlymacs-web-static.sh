#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
WEB_DIR="$ROOT_DIR/apps/onlymacs-web"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"
STATIC_DIR="$COORDINATOR_REPO/internal/webstatic/static"

cd "$WEB_DIR"
npm run build

rm -rf "$STATIC_DIR"
mkdir -p "$STATIC_DIR"
rsync -a --exclude='/downloads/' "$WEB_DIR/out/" "$STATIC_DIR/"
rm -rf "$STATIC_DIR/downloads"

echo "Synced Next static export to $STATIC_DIR"
