#!/usr/bin/env bash

shell_quote() {
  printf '%q' "$1"
}

require_installer_resource() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing installer resource: $path" >&2
    exit 1
  fi
}

plist_value() {
  local plist_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path"
}

render_installer_template() {
  local template_path="$1"
  local output_path="$2"
  shift 2
  python3 "$ROOT_DIR/scripts/macos-pkg/render-template.py" "$template_path" "$output_path" "$@"
}

build_script_package() {
  local output_path="$1"
  local package_id="$2"
  local script_template_path="$3"
  shift 3

  local script_dir
  local wrapper_path
  local helper_copy
  local template_name

  script_dir="$(mktemp -d "$TEMP_DIR/scripts.XXXXXX")"
  wrapper_path="$script_dir/postinstall"
  helper_copy="$script_dir/installer-session-helper.sh"
  template_name="$(basename "$script_template_path")"

  cp "$INSTALLER_SESSION_HELPER_PATH" "$helper_copy"
  chmod +x "$helper_copy"
  cp "$script_template_path" "$script_dir/$template_name"
  chmod +x "$script_dir/$template_name"

  {
    echo '#!/bin/sh'
    echo 'set -eu'
    echo
    echo 'SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"'
    echo
    while (($#)); do
      local kv="$1"
      local key="${kv%%=*}"
      local value="${kv#*=}"
      printf 'export %s=%s\n' "$key" "$(shell_quote "$value")"
      shift
    done
    echo
    printf '. "$SCRIPT_DIR/%s"\n' "$template_name"
  } > "$wrapper_path"
  chmod +x "$wrapper_path"

  pkgbuild \
    --nopayload \
    --identifier "$package_id" \
    --version "$VERSION" \
    --install-location / \
    --scripts "$script_dir" \
    "$output_path" >/dev/null
}
