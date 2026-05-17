#!/usr/bin/env bash

onlymacs_increment_patch_version() {
  local version="${1:-}"
  if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    printf '%s.%s.%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$((10#${BASH_REMATCH[3]} + 1))"
    return 0
  fi
  return 1
}

onlymacs_release_notice_url() {
  local channel="${1:-public}"
  local base_url="${ONLYMACS_UPDATE_SERVER_BASE_URL:-https://onlymacs.ai}"
  printf '%s/onlymacs/updates/latest-%s.json' "${base_url%/}" "$channel"
}

onlymacs_latest_published_version() {
  local channel="${1:-public}"
  local url="${ONLYMACS_RELEASE_VERSION_SOURCE_URL:-$(onlymacs_release_notice_url "$channel")}"
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  curl --fail --silent --show-error --max-time 5 "$url" 2>/dev/null | jq -r '.version // empty' 2>/dev/null
}

onlymacs_next_build_version() {
  local channel="${1:-public}"
  local fallback="${ONLYMACS_INITIAL_BUILD_VERSION:-0.1.1}"
  local latest_version next_version
  latest_version="$(onlymacs_latest_published_version "$channel" || true)"
  if next_version="$(onlymacs_increment_patch_version "$latest_version")"; then
    printf '%s' "$next_version"
    return 0
  fi
  printf '%s' "$fallback"
}

onlymacs_resolve_build_version() {
  local channel="${1:-public}"
  if [[ -n "${ONLYMACS_BUILD_VERSION:-}" ]]; then
    printf '%s' "$ONLYMACS_BUILD_VERSION"
    return 0
  fi
  onlymacs_next_build_version "$channel"
}
