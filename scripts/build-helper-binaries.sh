#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/coordinator-path.sh"
OUTPUT_DIR="${1:-$ROOT_DIR/.tmp/bin}"
HELPER_GOOS="${ONLYMACS_HELPER_GOOS:-darwin}"
HELPER_GOARCH="${ONLYMACS_HELPER_GOARCH:-}"
REQUIRE_COORDINATOR_HELPER="${ONLYMACS_REQUIRE_COORDINATOR_HELPER:-0}"

mkdir -p "$OUTPUT_DIR"

if [[ -z "$HELPER_GOARCH" ]]; then
  case "$(uname -m)" in
    arm64|aarch64)
      HELPER_GOARCH="arm64"
      ;;
    x86_64|amd64)
      HELPER_GOARCH="amd64"
      ;;
    *)
      HELPER_GOARCH="$(go env GOARCH)"
      ;;
  esac
fi

COORDINATOR_REPO="$(onlymacs_coordinator_repo "$ROOT_DIR")"
if [[ -f "$COORDINATOR_REPO/go.mod" ]]; then
  (
    cd "$COORDINATOR_REPO"
    GOOS="$HELPER_GOOS" GOARCH="$HELPER_GOARCH" go build -o "$OUTPUT_DIR/onlymacs-coordinator" ./cmd/coordinator
  )
else
  rm -f "$OUTPUT_DIR/onlymacs-coordinator"
  if [[ "$REQUIRE_COORDINATOR_HELPER" == "1" ]]; then
    onlymacs_require_coordinator_repo "$ROOT_DIR" >/dev/null
  fi
  echo "skipping coordinator helper; checkout not found at $COORDINATOR_REPO" >&2
fi

(
  cd "$ROOT_DIR/apps/local-bridge"
  GOOS="$HELPER_GOOS" GOARCH="$HELPER_GOARCH" go build -o "$OUTPUT_DIR/onlymacs-local-bridge" ./cmd/local-bridge
)

echo "$OUTPUT_DIR"
