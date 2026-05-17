#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/coordinator-path.sh"
coordinator_repo="$(onlymacs_require_coordinator_repo "$repo_root")"

cd "$coordinator_repo"
go test ./internal/httpapi -run TestCoordinatorScaleEnvelope -v
