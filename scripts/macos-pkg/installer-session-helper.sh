#!/bin/sh
set -eu

LAUNCH_AT_LOGIN_LABEL="com.kizzle.onlymacs.launch-at-login"
INSTALLER_LAUNCH_ONCE_LABEL="com.kizzle.onlymacs.installer-launch-once"
CONSOLE_USER=""
CONSOLE_UID=""
CONSOLE_GID=""
CONSOLE_HOME=""
CONSOLE_SHELL=""

console_user() {
  if [ -n "${ONLYMACS_TEST_CONSOLE_USER:-}" ]; then
    printf '%s\n' "$ONLYMACS_TEST_CONSOLE_USER"
    return 0
  fi
  /usr/sbin/scutil <<'EOF' | /usr/bin/awk '/Name :/ && $3 != "loginwindow" { print $3; exit }'
show State:/Users/ConsoleUser
EOF
}

console_uid() {
  if [ -n "${ONLYMACS_TEST_CONSOLE_UID:-}" ]; then
    printf '%s\n' "$ONLYMACS_TEST_CONSOLE_UID"
    return 0
  fi
  /usr/bin/id -u "$1"
}

console_gid() {
  if [ -n "${ONLYMACS_TEST_CONSOLE_GID:-}" ]; then
    printf '%s\n' "$ONLYMACS_TEST_CONSOLE_GID"
    return 0
  fi
  /usr/bin/id -g "$1"
}

console_home() {
  if [ -n "${ONLYMACS_TEST_CONSOLE_HOME:-}" ]; then
    printf '%s\n' "$ONLYMACS_TEST_CONSOLE_HOME"
    return 0
  fi
  /usr/bin/dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{ $1=""; sub(/^ /, ""); print; exit }'
}

console_shell() {
  if [ -n "${ONLYMACS_TEST_CONSOLE_SHELL:-}" ]; then
    printf '%s\n' "$ONLYMACS_TEST_CONSOLE_SHELL"
    return 0
  fi
  /usr/bin/dscl . -read "/Users/$1" UserShell 2>/dev/null | /usr/bin/awk '{ $1=""; sub(/^ /, ""); print; exit }'
}

launch_agents_dir() {
  printf '%s/Library/LaunchAgents' "$1"
}

support_dir() {
  printf '%s/Library/Application Support/OnlyMacs' "$1"
}

ensure_dir() {
  dir_path="$1"
  uid="$2"
  gid="$3"
  mode="$4"
  /bin/mkdir -p "$dir_path"
  /usr/sbin/chown "$uid:$gid" "$dir_path"
  /bin/chmod "$mode" "$dir_path"
}

write_owned_file() {
  file_path="$1"
  uid="$2"
  gid="$3"
  mode="$4"
  tmp_path="${file_path}.tmp.$$"
  /bin/cat > "$tmp_path"
  /usr/sbin/chown "$uid:$gid" "$tmp_path"
  /bin/chmod "$mode" "$tmp_path"
  /bin/mv "$tmp_path" "$file_path"
}

remove_existing_path() {
  existing_path="$1"
  if [ -e "$existing_path" ]; then
    /bin/rm -rf "$existing_path"
  fi
}

copy_owned_file() {
  source_path="$1"
  destination_path="$2"
  uid="$3"
  gid="$4"
  mode="$5"

  ensure_dir "$(dirname "$destination_path")" "$uid" "$gid" 755
  remove_existing_path "$destination_path"
  /usr/bin/ditto "$source_path" "$destination_path"
  /usr/sbin/chown "$uid:$gid" "$destination_path"
  /bin/chmod "$mode" "$destination_path"
}

copy_owned_directory() {
  source_path="$1"
  destination_path="$2"
  uid="$3"
  gid="$4"

  ensure_dir "$(dirname "$destination_path")" "$uid" "$gid" 755
  remove_existing_path "$destination_path"
  /usr/bin/ditto "$source_path" "$destination_path"
  /usr/sbin/chown -R "$uid:$gid" "$destination_path"
}

bootout_agent() {
  uid="$1"
  agent_path="$2"
  /bin/launchctl bootout "gui/$uid" "$agent_path" >/dev/null 2>&1 || true
}

bootstrap_agent() {
  uid="$1"
  agent_path="$2"
  /bin/launchctl bootstrap "gui/$uid" "$agent_path" >/dev/null 2>&1 || true
}

kickstart_agent() {
  uid="$1"
  label="$2"
  /bin/launchctl kickstart -k "gui/$uid/$label" >/dev/null 2>&1 || true
}

launch_app_into_console_session() {
  app_path="$1"
  app_arg="$2"

  if ! load_console_context; then
    return 1
  fi

  current_uid="$(/usr/bin/id -u)"

  if [ "$current_uid" -eq 0 ]; then
    /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/open -a "$app_path" --args "$app_arg" >/dev/null 2>&1
    return $?
  fi

  if [ "$current_uid" -eq "$CONSOLE_UID" ]; then
    /usr/bin/open -a "$app_path" --args "$app_arg" >/dev/null 2>&1
    return $?
  fi

  return 1
}

resolve_console_context() {
  user="$(console_user || true)"
  if [ -z "${user:-}" ]; then
    return 1
  fi

  uid="$(console_uid "$user" || true)"
  gid="$(console_gid "$user" || true)"
  home="$(console_home "$user" || true)"
  shell="$(console_shell "$user" || true)"
  if [ -z "${uid:-}" ] || [ -z "${gid:-}" ] || [ -z "${home:-}" ] || [ -z "${shell:-}" ]; then
    return 1
  fi

  printf '%s\n%s\n%s\n%s\n%s\n' "$user" "$uid" "$gid" "$home" "$shell"
}

load_console_context() {
  if ! context="$(resolve_console_context)"; then
    return 1
  fi

  CONSOLE_USER="$(printf '%s\n' "$context" | /usr/bin/sed -n '1p')"
  CONSOLE_UID="$(printf '%s\n' "$context" | /usr/bin/sed -n '2p')"
  CONSOLE_GID="$(printf '%s\n' "$context" | /usr/bin/sed -n '3p')"
  CONSOLE_HOME="$(printf '%s\n' "$context" | /usr/bin/sed -n '4p')"
  CONSOLE_SHELL="$(printf '%s\n' "$context" | /usr/bin/sed -n '5p')"
  return 0
}

shim_directory() {
  printf '%s/.local/bin' "$CONSOLE_HOME"
}

claude_commands_directory() {
  printf '%s/.claude/commands' "$CONSOLE_HOME"
}

claude_skills_directory() {
  printf '%s/.claude/skills' "$CONSOLE_HOME"
}

preferred_shell_profile_path() {
  case "$CONSOLE_SHELL" in
    */fish)
      printf '%s/.config/fish/config.fish' "$CONSOLE_HOME"
      ;;
    */bash)
      printf '%s/.bash_profile' "$CONSOLE_HOME"
      ;;
    *)
      printf '%s/.zshrc' "$CONSOLE_HOME"
      ;;
  esac
}

path_fix_snippet() {
  profile_path="$1"
  case "$profile_path" in
    */config.fish)
      printf 'set -gx PATH "$HOME/.local/bin" $PATH'
      ;;
    *)
      printf 'export PATH="$HOME/.local/bin:$PATH"'
      ;;
  esac
}

profile_contains_path_fix() {
  profile_path="$1"
  if [ ! -f "$profile_path" ]; then
    return 1
  fi
  /usr/bin/grep -q '\.local/bin' "$profile_path"
}

install_path_fix() {
  profile_path="$(preferred_shell_profile_path)"
  if profile_contains_path_fix "$profile_path"; then
    return 0
  fi

  parent_dir="$(dirname "$profile_path")"
  case "$profile_path" in
    */.config/fish/*)
      ensure_dir "$CONSOLE_HOME/.config" "$CONSOLE_UID" "$CONSOLE_GID" 755
      ;;
  esac
  ensure_dir "$parent_dir" "$CONSOLE_UID" "$CONSOLE_GID" 755
  if [ ! -f "$profile_path" ]; then
    write_owned_file "$profile_path" "$CONSOLE_UID" "$CONSOLE_GID" 644 <<'EOF'
EOF
  fi

  if [ -s "$profile_path" ]; then
    /bin/printf '\n' >> "$profile_path"
  fi
  {
    printf '\n'
    printf '# Added by OnlyMacs\n'
    path_fix_snippet "$profile_path"
    printf '\n'
  } >> "$profile_path"
  /usr/sbin/chown "$CONSOLE_UID:$CONSOLE_GID" "$profile_path"
  /bin/chmod 644 "$profile_path"
}

write_wrapper_script() {
  wrapper_name="$1"
  wrapper_source_path="$2"
  shim_dir="$(shim_directory)"
  shim_path="$shim_dir/$wrapper_name"

  ensure_dir "$CONSOLE_HOME/.local" "$CONSOLE_UID" "$CONSOLE_GID" 755
  ensure_dir "$shim_dir" "$CONSOLE_UID" "$CONSOLE_GID" 755
  write_owned_file "$shim_path" "$CONSOLE_UID" "$CONSOLE_GID" 755 <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec /usr/bin/env bash '$wrapper_source_path' "\$@"
EOF
}

install_codemacs_core() {
  integration_root="$1"
  write_wrapper_script "onlymacs" "$integration_root/onlymacs/onlymacs.sh"
}

install_codex_surfaces() {
  integration_root="$1"
  codex_source="$integration_root/codex/skills/onlymacs"
  codex_destination="$CONSOLE_HOME/.agents/skills/onlymacs"

  ensure_dir "$CONSOLE_HOME/.agents" "$CONSOLE_UID" "$CONSOLE_GID" 755
  ensure_dir "$CONSOLE_HOME/.agents/skills" "$CONSOLE_UID" "$CONSOLE_GID" 755
  write_wrapper_script "onlymacs-shell" "$integration_root/codex/onlymacs-shell.sh"
  remove_existing_path "$(shim_directory)/onlymacs-codex"
  remove_existing_path "$CONSOLE_HOME/.codex/skills/onlymacs"
  if [ -d "$codex_source" ]; then
    copy_owned_directory "$codex_source" "$codex_destination" "$CONSOLE_UID" "$CONSOLE_GID"
  fi
}

install_claude_surfaces() {
  integration_root="$1"
  claude_commands_destination="$(claude_commands_directory)/onlymacs.md"
  claude_skills_destination="$(claude_skills_directory)/onlymacs/SKILL.md"

  ensure_dir "$CONSOLE_HOME/.claude" "$CONSOLE_UID" "$CONSOLE_GID" 755
  ensure_dir "$(claude_commands_directory)" "$CONSOLE_UID" "$CONSOLE_GID" 755
  ensure_dir "$(claude_skills_directory)" "$CONSOLE_UID" "$CONSOLE_GID" 755
  write_wrapper_script "onlymacs-claude" "$integration_root/claude/onlymacs-claude.sh"
  if [ -f "$integration_root/claude/commands/onlymacs.md" ]; then
    copy_owned_file "$integration_root/claude/commands/onlymacs.md" "$claude_commands_destination" "$CONSOLE_UID" "$CONSOLE_GID" 644
  fi
  if [ -f "$integration_root/claude/skills/onlymacs.md" ]; then
    copy_owned_file "$integration_root/claude/skills/onlymacs.md" "$claude_skills_destination" "$CONSOLE_UID" "$CONSOLE_GID" 644
  fi
}

install_integrations() {
  integration_root="$1"
  shift

  if ! load_console_context; then
    exit 0
  fi
  if [ ! -d "$integration_root" ]; then
    exit 0
  fi

  install_codemacs_core "$integration_root"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      codex)
        install_codex_surfaces "$integration_root"
        ;;
      claude)
        install_claude_surfaces "$integration_root"
        ;;
    esac
    shift
  done
  install_path_fix
}

prepare_app_for_sparkle_updates() {
  app_path="$1"
  if [ ! -d "$app_path" ]; then
    exit 0
  fi
  if ! load_console_context; then
    exit 0
  fi

  /usr/sbin/chown -R "$CONSOLE_UID:$CONSOLE_GID" "$app_path"
  /bin/chmod -R u+rwX,go+rX "$app_path"
}

reset_install_state() {
  if ! load_console_context; then
    exit 0
  fi

  agents_dir="$(launch_agents_dir "$CONSOLE_HOME")"
  support_root="$(support_dir "$CONSOLE_HOME")"
  launch_at_login_path="$agents_dir/$LAUNCH_AT_LOGIN_LABEL.plist"
  launch_once_path="$agents_dir/$INSTALLER_LAUNCH_ONCE_LABEL.plist"
  launch_once_script="$support_root/installer-launch-once.sh"

  bootout_agent "$CONSOLE_UID" "$launch_at_login_path"
  bootout_agent "$CONSOLE_UID" "$launch_once_path"
  /bin/rm -f "$launch_at_login_path" "$launch_once_path" "$launch_once_script"
  if [ -d "$agents_dir" ]; then
    /usr/sbin/chown "$CONSOLE_UID:$CONSOLE_GID" "$agents_dir" >/dev/null 2>&1 || true
  fi
}

install_launch_at_login() {
  app_path="$1"
  if ! load_console_context; then
    exit 0
  fi

  agents_dir="$(launch_agents_dir "$CONSOLE_HOME")"
  agent_path="$agents_dir/$LAUNCH_AT_LOGIN_LABEL.plist"

  ensure_dir "$agents_dir" "$CONSOLE_UID" "$CONSOLE_GID" 755
  write_owned_file "$agent_path" "$CONSOLE_UID" "$CONSOLE_GID" 644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCH_AT_LOGIN_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$app_path</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
</dict>
</plist>
EOF

  bootout_agent "$CONSOLE_UID" "$agent_path"
  bootstrap_agent "$CONSOLE_UID" "$agent_path"
}

install_launch_once() {
  app_path="$1"
  app_arg="$2"
  launch_app_into_console_session "$app_path" "$app_arg" >/dev/null 2>&1 || true

  if ! load_console_context; then
    exit 0
  fi

  agents_dir="$(launch_agents_dir "$CONSOLE_HOME")"
  support_root="$(support_dir "$CONSOLE_HOME")"
  agent_path="$agents_dir/$INSTALLER_LAUNCH_ONCE_LABEL.plist"
  script_path="$support_root/installer-launch-once.sh"

  ensure_dir "$agents_dir" "$CONSOLE_UID" "$CONSOLE_GID" 755
  ensure_dir "$support_root" "$CONSOLE_UID" "$CONSOLE_GID" 755

  write_owned_file "$script_path" "$CONSOLE_UID" "$CONSOLE_GID" 755 <<EOF
#!/bin/sh
set -eu

cleanup() {
  /bin/rm -f "$agent_path" "$script_path"
}

tries=0
while [ "\$tries" -lt 5 ]; do
  if /usr/bin/pgrep -qx "OnlyMacsApp" >/dev/null 2>&1; then
    cleanup
    exit 0
  fi

  /usr/bin/open -a "$app_path" --args "$app_arg" >/dev/null 2>&1 || true
  tries=\$((tries + 1))
  /bin/sleep 2
done

cleanup

exit 0
EOF

  write_owned_file "$agent_path" "$CONSOLE_UID" "$CONSOLE_GID" 644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$INSTALLER_LAUNCH_ONCE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$script_path</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LaunchOnlyOnce</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
</dict>
</plist>
EOF

  bootout_agent "$CONSOLE_UID" "$agent_path"
  bootstrap_agent "$CONSOLE_UID" "$agent_path"
  kickstart_agent "$CONSOLE_UID" "$INSTALLER_LAUNCH_ONCE_LABEL"
}

command="${1:-}"
case "$command" in
  reset-install-state)
    reset_install_state
    ;;
  install-launch-at-login)
    install_launch_at_login "$2"
    ;;
  install-launch-once)
    install_launch_once "$2" "$3"
    ;;
  prepare-app-for-sparkle-updates)
    prepare_app_for_sparkle_updates "$2"
    ;;
  install-integrations)
    shift
    install_integrations "$@"
    ;;
  *)
    echo "usage: $0 {reset-install-state|install-launch-at-login <appPath>|install-launch-once <appPath> <appArg>|prepare-app-for-sparkle-updates <appPath>|install-integrations <integrationRoot> [codex] [claude]}" >&2
    exit 64
    ;;
esac
