#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/onlymacs-cli.sh
source "$SCRIPT_DIR/../common/onlymacs-cli.sh"

onlymacs_cli_main "Claude Code" "onlymacs-claude.sh" "$@"
