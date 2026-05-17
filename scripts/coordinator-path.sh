#!/usr/bin/env bash

onlymacs_coordinator_repo() {
  local root_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  if [[ -n "${ONLYMACS_COORDINATOR_REPO:-}" ]]; then
    printf '%s\n' "$ONLYMACS_COORDINATOR_REPO"
    return
  fi
  printf '%s\n' "$(cd "$root_dir/.." && pwd)/OnlyMacs-coordinator"
}

onlymacs_require_coordinator_repo() {
  local root_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local coordinator_repo
  coordinator_repo="$(onlymacs_coordinator_repo "$root_dir")"
  if [[ ! -f "$coordinator_repo/go.mod" ]]; then
    echo "missing coordinator checkout: $coordinator_repo" >&2
    echo "Set ONLYMACS_COORDINATOR_REPO to the coordinator repo path." >&2
    return 1
  fi
  printf '%s\n' "$coordinator_repo"
}
