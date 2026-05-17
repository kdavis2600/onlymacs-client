#!/usr/bin/env bash

require_build_asset() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing required build asset: $path" >&2
    exit 1
  fi
}

copy_if_present() {
  local source_path="$1"
  local target_path="$2"
  if [[ -f "$source_path" ]]; then
    cp "$source_path" "$target_path"
  fi
}

create_app_icon_icns() {
  local source_path="$1"
  local output_path="$2"
  local temp_dir
  local iconset_dir
  local base_png

  require_build_asset "$source_path"
  if ! command -v iconutil >/dev/null 2>&1; then
    echo "missing required app icon tool: iconutil" >&2
    exit 1
  fi

  temp_dir="$(mktemp -d)"
  iconset_dir="$temp_dir/OnlyMacs.iconset"
  base_png="$temp_dir/OnlyMacs-1024.png"
  mkdir -p "$iconset_dir"

  sips -s format png -Z 1024 -p 1024 1024 --padColor FFFFFF "$source_path" --out "$base_png" >/dev/null 2>&1
  for icon_spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    set -- $icon_spec
    sips -z "$1" "$1" "$base_png" --out "$iconset_dir/$2" >/dev/null
  done

  iconutil --convert icns --output "$output_path" "$iconset_dir"
  rm -rf "$temp_dir"
}

sparkle_plist_snippet() {
  local feed_url="$1"
  local public_key="$2"
  local scheduled_check_interval="${ONLYMACS_SPARKLE_CHECK_INTERVAL_SECONDS:-3600}"

  if [[ -z "$public_key" ]]; then
    return 0
  fi

  cat <<EOF
	<key>SUFeedURL</key>
	<string>$feed_url</string>
	<key>SUPublicEDKey</key>
	<string>$public_key</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUAutomaticallyUpdate</key>
	<true/>
	<key>SUAllowsAutomaticUpdates</key>
	<true/>
	<key>SUScheduledCheckInterval</key>
	<integer>$scheduled_check_interval</integer>
EOF
}

string_plist_key_snippet() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    return 0
  fi

  cat <<EOF
	<key>$key</key>
	<string>$value</string>
EOF
}

render_app_info_plist() {
  local template_path="$1"
  local output_path="$2"
  shift 2
  python3 "$ROOT_DIR/scripts/macos-pkg/render-template.py" "$template_path" "$output_path" "$@"
}

maybe_ad_hoc_sign_app() {
  local app_dir="$1"
  local enabled="$2"

  if [[ "$enabled" == "1" ]]; then
    codesign --force --deep --sign - "$app_dir" >/dev/null
  fi
}
