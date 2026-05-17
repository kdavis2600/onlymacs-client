#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_PATH="$ROOT_DIR/dist/OnlyMacs-public.pkg"
MANIFEST_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg-manifest.json"
CHECKSUM_PATH="$ROOT_DIR/dist/OnlyMacs-public-pkg.sha256"
TEAM_ID="${ONLYMACS_TEAM_ID:?ONLYMACS_TEAM_ID must be set}"
PROFILE="${ONLYMACS_NOTARY_PROFILE:-}"
ASC_KEY_PATH="${ONLYMACS_ASC_KEY_PATH:-}"
ASC_KEY_ID="${ONLYMACS_ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ONLYMACS_ASC_ISSUER_ID:-}"
STAPLE_RETRIES="${ONLYMACS_STAPLER_RETRIES:-6}"
STAPLE_RETRY_DELAY="${ONLYMACS_STAPLER_RETRY_DELAY:-10}"

if [[ ! -f "$PKG_PATH" || ! -f "$MANIFEST_PATH" ]]; then
  echo "missing release artifact or manifest" >&2
  echo "build it first with: make macos-pkg-public" >&2
  exit 1
fi

notary_submit_args=()
if [[ -n "$PROFILE" ]]; then
  notary_submit_args+=(--keychain-profile "$PROFILE")
elif [[ -n "$ASC_KEY_PATH" && -n "$ASC_KEY_ID" && -n "$ASC_ISSUER_ID" ]]; then
  notary_submit_args+=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
else
  echo "set ONLYMACS_NOTARY_PROFILE or ONLYMACS_ASC_KEY_PATH/ONLYMACS_ASC_KEY_ID/ONLYMACS_ASC_ISSUER_ID" >&2
  exit 1
fi

staple_retry() {
  local artifact="$1" attempt=1 rc=0
  while true; do
    xcrun stapler staple "$artifact" && return 0
    rc=$?
    if [[ "$attempt" -ge "$STAPLE_RETRIES" ]]; then
      return "$rc"
    fi
    echo "stapler failed; retrying in ${STAPLE_RETRY_DELAY}s (attempt ${attempt}/${STAPLE_RETRIES})" >&2
    sleep "$STAPLE_RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

xcrun notarytool submit \
  "$PKG_PATH" \
  "${notary_submit_args[@]}" \
  --team-id "$TEAM_ID" \
  --wait

staple_retry "$PKG_PATH"

python3 - "$MANIFEST_PATH" "$CHECKSUM_PATH" "$PKG_PATH" <<'PY'
import hashlib
import json
import pathlib
from datetime import datetime, timezone
import sys

manifest_path = pathlib.Path(sys.argv[1])
checksum_path = pathlib.Path(sys.argv[2])
pkg_path = pathlib.Path(sys.argv[3])

manifest = json.loads(manifest_path.read_text())
sha = hashlib.sha256(pkg_path.read_bytes()).hexdigest()

manifest["artifact_sha256"] = sha
manifest["artifact_bytes"] = pkg_path.stat().st_size
manifest["artifact_notarized"] = True
manifest["notarized_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
checksum_path.write_text(f"{sha}  {pkg_path.name}\n")
PY

echo "$PKG_PATH"
