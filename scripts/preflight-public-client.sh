#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

fail() {
  printf '[public-preflight] FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() {
  printf '[public-preflight] PASS %s\n' "$1"
}

tracked_path_is_forbidden() {
  local path="$1"
  local base
  base="$(basename "$path")"
  case "$path" in
    .codex/*|.agents/*|.claude/*|.windsurf/*)
      return 0
      ;;
    services/coordinator|services/coordinator/*)
      return 0
      ;;
    *.xcarchive|*.xcarchive/*)
      return 0
      ;;
  esac
  case "$base" in
    .env|.env.*|.envrc|*.env|*.p8|*.p12|*.pem|*.key|*.cer|*.cert|*.developerprofile|*.notarytool|*.mobileprovision|*.provisionprofile|*.dmg|*.pkg|*.ipa|*.xcarchive|*.xcdistributionlogs|*-skill.zip|skills-lock.json|auth.json)
      [[ "$base" == ".env.example" ]] && return 1
      return 0
      ;;
  esac
  return 1
}

forbidden_paths=()
while IFS= read -r -d '' path; do
  if tracked_path_is_forbidden "$path"; then
    forbidden_paths+=("$path")
  fi
done < <(git ls-files -z)

if [[ "${#forbidden_paths[@]}" -gt 0 ]]; then
  printf '%s\n' "${forbidden_paths[@]}" | sed 's/^/[public-preflight] forbidden tracked path: /' >&2
  fail "tracked local env, signing, package, coordinator, or agent artifacts are present"
else
  pass "no tracked env/signing/package/coordinator/agent artifact paths"
fi

sparkle_private_paths="$(git ls-files | rg -i '(sparkle.*private|private.*sparkle)' || true)"
if [[ -n "$sparkle_private_paths" ]]; then
  printf '%s\n' "$sparkle_private_paths" | sed 's/^/[public-preflight] possible Sparkle private key path: /' >&2
  fail "tracked Sparkle private key-looking path is present"
else
  pass "no tracked Sparkle private key-looking paths"
fi

local_path_hits="$(rg -n '/Users/kizzle|flashcard-app-react|onlymacs-coordinator-production|macos-menu-bar-ui-skill|skills-lock\.json' . \
  --glob '!.git/**' \
  --glob '!scripts/preflight-public-client.sh' \
  -S || true)"
if [[ -n "$local_path_hits" ]]; then
  printf '%s\n' "$local_path_hits" >&2
  fail "machine-specific or stale internal strings remain"
else
  pass "no machine-specific or stale internal strings in working tree"
fi

secret_hits="$(rg -n \
  -e 'sk-[A-Za-z0-9][A-Za-z0-9_-]{30,}' \
  -e 'AIza[0-9A-Za-z_-]{35}' \
  -e 'xox[baprs]-[0-9A-Za-z-]{20,}' \
  -e 'gh[pousr]_[A-Za-z0-9_]{30,}' \
  -e 'AKIA[0-9A-Z]{16}' \
  . \
  --glob '!.git/**' \
  --glob '!apps/onlymacs-web/.env.example' \
  -S || true)"
if [[ -n "$secret_hits" ]]; then
  printf '%s\n' "$secret_hits" >&2
  fail "possible committed API key or token literal found"
else
  pass "no high-confidence API key/token literals"
fi

private_key_hits="$(rg -n 'BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY' . \
  --glob '!.git/**' \
  --glob '!apps/onlymacs-macos/Tests/**' \
  -S || true)"
if [[ -n "$private_key_hits" ]]; then
  printf '%s\n' "$private_key_hits" >&2
  fail "private key material appears in non-test files"
else
  pass "no private key material in non-test files"
fi

if find . -maxdepth 1 \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) | grep -q .; then
  pass "license/notice file exists"
elif [[ "${ONLYMACS_ALLOW_MISSING_LICENSE:-0}" == "1" ]]; then
  printf '[public-preflight] WARN license/notice file missing; allowed by ONLYMACS_ALLOW_MISSING_LICENSE=1\n' >&2
else
  fail "missing root LICENSE/COPYING/NOTICE file"
fi

coordinator_history_hit="$(git log --oneline --all -- services/coordinator | sed -n '1p' || true)"
if [[ -n "$coordinator_history_hit" ]]; then
  if [[ "${ONLYMACS_ALLOW_PRIVATE_HISTORY:-0}" == "1" ]]; then
    printf '[public-preflight] WARN current private repo history still contains services/coordinator; public export must use fresh or filtered history\n' >&2
  else
    fail "git history contains services/coordinator; create a fresh public export or filtered history before publishing"
  fi
else
  pass "git history does not contain services/coordinator"
fi

if [[ "$failures" -gt 0 ]]; then
  printf '[public-preflight] %d failure(s)\n' "$failures" >&2
  exit 1
fi

pass "public client preflight passed"
