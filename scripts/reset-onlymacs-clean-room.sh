#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_ID="com.kizzle.onlymacs"
APP_PATH="/Applications/OnlyMacs.app"
INSTALLER_SELECTIONS_ROOT="/Library/Application Support/OnlyMacs/InstallerSelections"
USER_DEFAULTS_PLIST="$HOME/Library/Preferences/${APP_BUNDLE_ID}.plist"
APP_SUPPORT_DIR="$HOME/Library/Application Support/OnlyMacs"
STATE_DIR="${ONLYMACS_STATE_DIR:-$HOME/.local/state/onlymacs}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.kizzle.onlymacs.launch-at-login.plist"
ONLYMACS_BIN_DIR="$HOME/.local/bin"
CODEX_SKILL_DIR="$HOME/.agents/skills/onlymacs"
CLAUDE_COMMAND="$HOME/.claude/commands/onlymacs.md"
CLAUDE_SKILL="$HOME/.claude/skills/onlymacs"
REMOVE_APP=0
DRY_RUN=1

usage() {
  cat <<'EOF'
Usage: reset-onlymacs-clean-room.sh [--execute] [--remove-app]

By default this script only prints what it would remove.

Options:
  --execute      Actually perform the reset.
  --remove-app   Also remove /Applications/OnlyMacs.app for a truer reinstall test.
  --help         Show this help.

This script intentionally does NOT remove Ollama.app or any downloaded Ollama models.
If Ollama/models already exist on this Mac, your install experience will still be more
ready than a true first-time friend machine.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      DRY_RUN=0
      shift
      ;;
    --remove-app)
      REMOVE_APP=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

note() {
  printf '%s\n' "${1:-}"
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

run_shell() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] %s\n' "$1"
  else
    /bin/bash -lc "$1"
  fi
}

run_sudo_shell() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] sudo %s\n' "$1"
  elif [[ "$(id -u)" == "0" ]]; then
    /bin/bash -lc "$1"
  else
    sudo /bin/bash -lc "$1"
  fi
}

remove_path() {
  local path="$1"
  local system_owned="${2:-0}"
  if [[ ! -e "$path" ]]; then
    return
  fi
  if [[ "$system_owned" == "1" ]]; then
    run_sudo_shell "rm -rf \"$path\""
  else
    run rm -rf "$path"
  fi
}

remove_onlymacs_profile_block() {
  local profile_path="$1"
  [[ -f "$profile_path" ]] || return
  local temp_file
  temp_file="$(mktemp)"
  /usr/bin/awk '
    skip == 1 && /^export PATH="\$HOME\/\.local\/bin:\$PATH"$/ { skip = 0; next }
    skip == 1 && /^set -gx PATH "\$HOME\/\.local\/bin" \$PATH$/ { skip = 0; next }
    /^# Added by OnlyMacs$/ { skip = 1; next }
    { print }
  ' "$profile_path" > "$temp_file"
  if cmp -s "$profile_path" "$temp_file"; then
    rm -f "$temp_file"
    return
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] remove OnlyMacs PATH block from %s\n' "$profile_path"
    rm -f "$temp_file"
  else
    mv "$temp_file" "$profile_path"
  fi
}

note "OnlyMacs clean-room reset"
note
if [[ "$DRY_RUN" == "1" ]]; then
  note "Mode: dry-run"
  note "Re-run with --execute to actually wipe OnlyMacs state."
else
  note "Mode: execute"
fi
note

note "Stopping running OnlyMacs processes..."
run_shell "pkill -f '/Applications/OnlyMacs.app/Contents/MacOS/OnlyMacsApp' >/dev/null 2>&1 || true"
run_shell "pkill -f '/dist/OnlyMacs.app/Contents/MacOS/OnlyMacsApp' >/dev/null 2>&1 || true"
run_shell "pkill -f 'onlymacs-local-bridge' >/dev/null 2>&1 || true"
run_shell "pkill -f 'onlymacs-coordinator' >/dev/null 2>&1 || true"

note "Clearing OnlyMacs user defaults..."
run_shell "defaults delete ${APP_BUNDLE_ID} >/dev/null 2>&1 || true"
remove_path "$USER_DEFAULTS_PLIST"

note "Removing OnlyMacs user state..."
remove_path "$APP_SUPPORT_DIR"
remove_path "$STATE_DIR"

note "Removing launch-at-login registration..."
run_shell "launchctl bootout gui/$(id -u) \"$LAUNCH_AGENT\" >/dev/null 2>&1 || true"
remove_path "$LAUNCH_AGENT"

note "Removing installed OnlyMacs launchers and skills..."
remove_path "$ONLYMACS_BIN_DIR/onlymacs"
remove_path "$ONLYMACS_BIN_DIR/onlymacs-shell"
remove_path "$ONLYMACS_BIN_DIR/onlymacs-codex"
remove_path "$ONLYMACS_BIN_DIR/onlymacs-claude"
remove_path "$CODEX_SKILL_DIR"
remove_path "$CLAUDE_COMMAND"
remove_path "$CLAUDE_SKILL"

note "Removing installer-selection leftovers..."
remove_path "$INSTALLER_SELECTIONS_ROOT" 1

note "Cleaning OnlyMacs PATH injections..."
remove_onlymacs_profile_block "$HOME/.zprofile"
remove_onlymacs_profile_block "$HOME/.zshrc"
remove_onlymacs_profile_block "$HOME/.bash_profile"
remove_onlymacs_profile_block "$HOME/.bashrc"
remove_onlymacs_profile_block "$HOME/.profile"
remove_onlymacs_profile_block "$HOME/.config/fish/config.fish"

if [[ "$REMOVE_APP" == "1" ]]; then
  note "Removing installed app..."
  remove_path "$APP_PATH" 1
fi

note
note "Reset complete."
if [[ "$DRY_RUN" == "1" ]]; then
  note "Nothing was deleted yet."
else
  note "OnlyMacs state for this user was wiped."
fi
note "This script does not remove Ollama.app or downloaded Ollama models."
