#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/onlymacs-release-config.sh"
source "$ROOT_DIR/scripts/coordinator-path.sh"

RAILWAY_CONTEXT_DIR="$(onlymacs_railway_context_dir)"
PROJECT_ID="$(onlymacs_railway_project_id)"
ENVIRONMENT="$(onlymacs_railway_environment)"
SERVICE_NAME="$(onlymacs_railway_coordinator_service)"
COORDINATOR_REPO="$(onlymacs_require_coordinator_repo "$ROOT_DIR")"

if ! command -v railway >/dev/null 2>&1; then
  echo "railway CLI is required" >&2
  exit 1
fi

if [[ ! -d "$RAILWAY_CONTEXT_DIR" ]]; then
  echo "Railway context dir does not exist: $RAILWAY_CONTEXT_DIR" >&2
  exit 1
fi

cd "$RAILWAY_CONTEXT_DIR"

if ! railway status >/dev/null 2>&1; then
  echo "railway CLI is not linked or authenticated in $RAILWAY_CONTEXT_DIR" >&2
  exit 1
fi

if ! railway service "$SERVICE_NAME" status >/dev/null 2>&1; then
  echo "Creating Railway service: $SERVICE_NAME" >&2
  railway add --service "$SERVICE_NAME" >/dev/null
fi

if [[ -n "$PROJECT_ID" ]]; then
  echo "Deploying $SERVICE_NAME to Railway project $PROJECT_ID ($ENVIRONMENT)" >&2
else
  echo "Deploying $SERVICE_NAME to the linked Railway project ($ENVIRONMENT)" >&2
fi
railway_args=(
  up "$COORDINATOR_REPO"
  --path-as-root
  --environment "$ENVIRONMENT"
  --service "$SERVICE_NAME"
  --message "Deploy OnlyMacs coordinator"
  --ci
  --detach
)
if [[ -n "$PROJECT_ID" ]]; then
  railway_args+=(--project "$PROJECT_ID")
fi

railway "${railway_args[@]}"

for _ in $(seq 1 90); do
  DEPLOYMENT_JSON="$(railway deployment list --service "$SERVICE_NAME" --environment "$ENVIRONMENT" --json)"
  DEPLOYMENT_ID="$(printf '%s' "$DEPLOYMENT_JSON" | jq -r '.[0].id // empty')"
  DEPLOYMENT_STATUS="$(printf '%s' "$DEPLOYMENT_JSON" | jq -r '.[0].status // empty')"
  echo "Railway deployment ${DEPLOYMENT_ID:-unknown}: ${DEPLOYMENT_STATUS:-unknown}" >&2
  case "$DEPLOYMENT_STATUS" in
    SUCCESS)
      break
      ;;
    FAILED|CRASHED|REMOVED)
      echo "Railway deployment failed: ${DEPLOYMENT_ID:-unknown} ($DEPLOYMENT_STATUS)" >&2
      exit 1
      ;;
  esac
  sleep 5
done

if [[ "${DEPLOYMENT_STATUS:-}" != "SUCCESS" ]]; then
  echo "Railway deployment did not reach SUCCESS before timeout: ${DEPLOYMENT_ID:-unknown} (${DEPLOYMENT_STATUS:-unknown})" >&2
  exit 1
fi

DOMAIN_JSON="$(railway domain --service "$SERVICE_NAME" --json)"
COORDINATOR_URL="$(printf '%s' "$DOMAIN_JSON" | jq -r '(.domain // .domains[0] // empty)')"

if [[ -z "$COORDINATOR_URL" || "$COORDINATOR_URL" == "null" ]]; then
  echo "Railway did not return a coordinator domain" >&2
  exit 1
fi

echo "Waiting for coordinator health at $COORDINATOR_URL/health" >&2
for _ in $(seq 1 30); do
  if curl -fsS "$COORDINATOR_URL/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "$COORDINATOR_URL/health" >/dev/null
printf '%s\n' "$COORDINATOR_URL"
