#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ONLYMACS_APP_DIR:-$ROOT_DIR/dist/OnlyMacs.app}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "missing app bundle: $APP_DIR" >&2
  echo "build it first with: make macos-app-public" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign -dv --verbose=4 "$APP_DIR"

spctl_output="$(spctl --assess --type open --verbose=2 "$APP_DIR" 2>&1 || true)"
printf '%s\n' "$spctl_output"

if printf '%s\n' "$spctl_output" | rg -q "accepted"; then
  :
elif printf '%s\n' "$spctl_output" | rg -q "Unnotarized Developer ID"; then
  echo "OnlyMacs.app is correctly Developer ID signed but not notarized yet." >&2
elif printf '%s\n' "$spctl_output" | rg -q "Insufficient Context"; then
  echo "Gatekeeper returned an inconclusive local assessment, but the Developer ID signature verified successfully." >&2
else
  echo "unexpected Gatekeeper assessment result for signed app" >&2
  exit 1
fi

echo "$APP_DIR"
