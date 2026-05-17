#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DEST="$ROOT_DIR/.tmp/onlymacs-public-client-export"
DEST="${1:-${ONLYMACS_PUBLIC_EXPORT_DIR:-$DEFAULT_DEST}}"

if [[ "$DEST" != /* ]]; then
  DEST="$ROOT_DIR/$DEST"
fi

cd "$ROOT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "public export requires a clean working tree; commit or stash changes first" >&2
  exit 1
fi

commit_sha="$(git rev-parse HEAD)"

if [[ -e "$DEST" ]]; then
  if [[ "${ONLYMACS_PUBLIC_EXPORT_OVERWRITE:-0}" != "1" ]]; then
    echo "export destination already exists: $DEST" >&2
    echo "Set ONLYMACS_PUBLIC_EXPORT_OVERWRITE=1 to replace it." >&2
    exit 1
  fi
  rm -rf "$DEST"
fi

mkdir -p "$DEST"

git archive --format=tar "$commit_sha" | tar -x -C "$DEST"

(
  cd "$DEST"
  git init -q -b main
  git add -A
  git -c user.name="OnlyMacs Public Export" \
    -c user.email="public-export@onlymacs.local" \
    commit -q -m "Initial public client export"
  bash scripts/preflight-public-client.sh
)

cat <<EOF
[public-export] created fresh local export
[public-export] source commit: $commit_sha
[public-export] export path: $DEST
[public-export] next step when ready: add an empty public remote from inside that export and push main
EOF
