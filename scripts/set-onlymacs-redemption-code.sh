#!/usr/bin/env bash
set -euo pipefail

RAILWAY_CONTEXT_DIR="${ONLYMACS_RAILWAY_CONTEXT_DIR:-${ONLYMACS_COORDINATOR_REPO:-../OnlyMacs-coordinator}}"
SERVICE_NAME="${ONLYMACS_RAILWAY_COORDINATOR_SERVICE:-onlymacs-coordinator}"
ENVIRONMENT="${ONLYMACS_RAILWAY_ENVIRONMENT:-production}"
CODE="${1:-}"
DOWNLOADS_REMAINING="${2:-4}"
REVOKE_CODE="${ONLYMACS_REVOKE_CODE:-}"
DRY_RUN=0

usage() {
  cat >&2 <<'EOF'
Usage: scripts/set-onlymacs-redemption-code.sh CODE [DOWNLOADS_REMAINING] [--dry-run]

Creates or updates a website/package redemption code on the live coordinator.

Rules:
  - CODE must use the existing two-word convention, e.g. MINT-CODE.
  - The first word must be one of: MINT FIG MAC SWIFT SPARK NOVA BYTE PIXEL ORBIT LOCAL.
  - The second word must be one of: APPLE DESK BUILD FOCUS PILOT ATLAS BRIDGE RIVER CLOUD CODE.
  - DOWNLOADS_REMAINING must be a positive integer.

Set ONLYMACS_REVOKE_CODE=OLD-CODE to remove a previous code in the same update.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

normalize_code() {
  printf '%s' "$1" \
    | tr '[:lower:]_' '[:upper:]-' \
    | sed -E 's/[^A-Z0-9]+/-/g; s/^-+//; s/-+$//'
}

contains_word() {
  local needle="$1"
  shift
  local current
  for current in "$@"; do
    [[ "$current" == "$needle" ]] && return 0
  done
  return 1
}

PREFIXES=(MINT FIG MAC SWIFT SPARK NOVA BYTE PIXEL ORBIT LOCAL)
SUFFIXES=(APPLE DESK BUILD FOCUS PILOT ATLAS BRIDGE RIVER CLOUD CODE)

CODE="$(normalize_code "$CODE")"
REVOKE_CODE="$(normalize_code "$REVOKE_CODE")"

if [[ -z "$CODE" ]]; then
  usage
  exit 1
fi

if [[ ! "$CODE" =~ ^[A-Z]+-[A-Z]+$ ]]; then
  echo "Redemption code must be exactly two words, like MINT-CODE: $CODE" >&2
  exit 1
fi

PREFIX="${CODE%%-*}"
SUFFIX="${CODE#*-}"
if ! contains_word "$PREFIX" "${PREFIXES[@]}" || ! contains_word "$SUFFIX" "${SUFFIXES[@]}"; then
  echo "Redemption code must use the seeded wordlist convention, like MINT-CODE: $CODE" >&2
  exit 1
fi

if [[ ! "$DOWNLOADS_REMAINING" =~ ^[1-9][0-9]*$ ]]; then
  echo "DOWNLOADS_REMAINING must be a positive integer: $DOWNLOADS_REMAINING" >&2
  exit 1
fi

for tool in railway jq base64; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required" >&2
    exit 1
  fi
done

if [[ ! -d "$RAILWAY_CONTEXT_DIR" ]]; then
  echo "Railway context dir does not exist: $RAILWAY_CONTEXT_DIR" >&2
  exit 1
fi

cd "$RAILWAY_CONTEXT_DIR"

if ! railway status >/dev/null 2>&1; then
  echo "railway CLI is not linked or authenticated in $RAILWAY_CONTEXT_DIR" >&2
  exit 1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  printf 'would set code=%s downloads_remaining=%s revoke=%s\n' "$CODE" "$DOWNLOADS_REMAINING" "${REVOKE_CODE:-none}"
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

STORE_JSON="$WORK_DIR/onlymacs-invites.json"
UPDATED_JSON="$WORK_DIR/onlymacs-invites.updated.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

railway ssh --service "$SERVICE_NAME" --environment "$ENVIRONMENT" \
  'cat ${ONLYMACS_INVITE_STORE_PATH:-/data/onlymacs-invites.json}' > "$STORE_JSON"

jq \
  --arg code "$CODE" \
  --arg revoke "$REVOKE_CODE" \
  --arg now "$NOW" \
  --argjson downloads_remaining "$DOWNLOADS_REMAINING" \
  '
  .codes |= (if $revoke == "" then . else del(.[$revoke]) end)
  | .codes[$code] = {
      code: $code,
      downloads_remaining: $downloads_remaining,
      purpose: "manual",
      created_at: $now
    }
  | .saved_at = $now
  ' "$STORE_JSON" > "$UPDATED_JSON"

jq -e \
  --arg code "$CODE" \
  --argjson downloads_remaining "$DOWNLOADS_REMAINING" \
  '.codes[$code] | select(.downloads_remaining == $downloads_remaining and .purpose == "manual")' \
  "$UPDATED_JSON" >/dev/null

PAYLOAD="$(base64 < "$UPDATED_JSON" | tr -d '\n')"
REMOTE_SCRIPT="$(cat <<'EOS'
set -eu
path=${ONLYMACS_INVITE_STORE_PATH:-/data/onlymacs-invites.json}
stamp=$(date -u +%Y%m%d%H%M%S)
backup="$path.bak-$stamp"
tmp="$path.tmp-$stamp"
cp "$path" "$backup"
printf '%s' "$ONLYMACS_INVITE_STORE_PAYLOAD" | base64 -d > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$path"
printf 'backup=%s\n' "$backup"
EOS
)"
REMOTE_SCRIPT_B64="$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n')"

railway ssh --service "$SERVICE_NAME" --environment "$ENVIRONMENT" \
  "ONLYMACS_INVITE_STORE_PAYLOAD='$PAYLOAD' sh -c 'printf %s \"$REMOTE_SCRIPT_B64\" | base64 -d >/tmp/onlymacs-set-redemption-code.sh && sh /tmp/onlymacs-set-redemption-code.sh && rm -f /tmp/onlymacs-set-redemption-code.sh'"

railway restart --service "$SERVICE_NAME" --yes --json >/dev/null
curl -fsS https://onlymacs.ai/health >/dev/null

printf 'code=%s\ndownloads_remaining=%s\nrevoked=%s\n' "$CODE" "$DOWNLOADS_REMAINING" "${REVOKE_CODE:-none}"
