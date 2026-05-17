#!/usr/bin/env bash

# Shared defaults for OnlyMacs release, update publishing, and coordinator deploy scripts.

onlymacs_default_coordinator_url() {
  printf '%s' "${ONLYMACS_DEFAULT_COORDINATOR_URL:-https://onlymacs.ai}"
}

onlymacs_release_require_nonlocal_coordinator_url() {
  local action_label="${1:-release OnlyMacs}"
  local url="${2:-}"
  if [[ -z "$url" || "$url" == http://127.0.0.1:* || "$url" == https://127.0.0.1:* || "$url" == http://localhost:* || "$url" == https://localhost:* ]]; then
    echo "Refusing to $action_label with a local embedded coordinator URL: $url" >&2
    return 1
  fi
}

onlymacs_railway_context_dir() {
  printf '%s' "${ONLYMACS_RAILWAY_CONTEXT_DIR:-${ONLYMACS_COORDINATOR_REPO:-../OnlyMacs-coordinator}}"
}

onlymacs_railway_project_id() {
  printf '%s' "${ONLYMACS_RAILWAY_PROJECT_ID:-}"
}

onlymacs_railway_environment() {
  printf '%s' "${ONLYMACS_RAILWAY_ENVIRONMENT:-production}"
}

onlymacs_railway_coordinator_service() {
  printf '%s' "${ONLYMACS_RAILWAY_COORDINATOR_SERVICE:-onlymacs-coordinator}"
}

onlymacs_update_server_base_url() {
  printf '%s' "${ONLYMACS_UPDATE_SERVER_BASE_URL:-https://onlymacs.ai}"
}

onlymacs_update_upload_base_url() {
  local server_base_url="${1:-$(onlymacs_update_server_base_url)}"
  local default_upload_base_url="$server_base_url"
  if [[ -n "${ONLYMACS_UPDATE_ORIGIN_BASE_URL:-}" ]]; then
    default_upload_base_url="$ONLYMACS_UPDATE_ORIGIN_BASE_URL"
  fi
  printf '%s' "${ONLYMACS_UPDATE_UPLOAD_BASE_URL:-$default_upload_base_url}"
}

onlymacs_update_server_service() {
  printf '%s' "${ONLYMACS_UPDATE_SERVER_SERVICE:-onlymacs-coordinator}"
}

onlymacs_update_server_environment() {
  printf '%s' "${ONLYMACS_UPDATE_SERVER_ENVIRONMENT:-production}"
}
