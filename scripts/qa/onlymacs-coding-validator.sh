#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ONLYMACS_VALIDATE_ROOT:-$(pwd)}"
MODE="run"
ALLOW_INSTALLS="${ONLYMACS_ALLOW_VALIDATOR_INSTALLS:-0}"
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="${2:-}"
      shift 2
      ;;
    --root=*)
      ROOT_DIR="${1#--root=}"
      shift
      ;;
    --plan)
      MODE="plan"
      shift
      ;;
    --run)
      MODE="run"
      shift
      ;;
    --allow-installs)
      ALLOW_INSTALLS=1
      shift
      ;;
    --json)
      JSON=1
      shift
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ROOT_DIR" || ! -d "$ROOT_DIR" ]]; then
  printf 'validation root does not exist: %s\n' "$ROOT_DIR" >&2
  exit 2
fi

cd "$ROOT_DIR"

has_file() {
  [[ -f "$1" ]]
}

has_local_bin() {
  [[ -x "node_modules/.bin/$1" ]]
}

find_project_files() {
  find . \
    \( -path './.git' -o -path './.tmp' -o -path '*/.tmp' -o -path './node_modules' -o -path '*/node_modules' -o -path './dist' -o -path '*/dist' -o -path './build' -o -path '*/build' -o -path './onlymacs/inbox' -o -path '*/onlymacs/inbox' -o -path './vendor' -o -path '*/vendor' \) -prune \
    -o "$@" -type f -print
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

shell_quote() {
  printf '%q' "$1"
}

detect_validators() {
  local validators=()
  if has_file package.json; then
    if jq -e '.scripts.build? // empty' package.json >/dev/null 2>&1; then
      validators+=("npm run build")
    fi
    if jq -e '.scripts.test? // empty' package.json >/dev/null 2>&1; then
      validators+=("npm test -- --runInBand")
    fi
    if jq -e '.scripts.lint? // empty' package.json >/dev/null 2>&1; then
      validators+=("npm run lint")
    fi
  fi
  if compgen -G 'tsconfig*.json' >/dev/null; then
    if has_local_bin tsc; then
      validators+=("./node_modules/.bin/tsc --noEmit")
    elif command -v tsc >/dev/null 2>&1; then
      validators+=("tsc --noEmit")
    fi
  fi
  while IFS= read -r go_mod; do
    dir="$(dirname "$go_mod")"
    validators+=("cd $(shell_quote "$dir") && go test ./...")
  done < <(find_project_files -name go.mod | sort)
  if has_file Package.swift; then
    validators+=("swift test")
  fi
  if find_project_files \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.ts' -o -name '*.tsx' \) | head -1 | grep -q .; then
    validators+=("html-css-js-smoke")
  fi
  if rg -qi 'THREE\.|BABYLON\.|PIXI\.|PlayCanvas|pc\.Application|regl\(|WebGLRenderer|WebGLRenderingContext|webgl|<canvas|document\.createElement\(["'\'']canvas|requestAnimationFrame' . --glob '!**/node_modules/**' --glob '!**/dist/**' --glob '!**/build/**' --glob '!onlymacs/inbox/**' --glob '!scripts/qa/onlymacs-coding-validator.sh' 2>/dev/null; then
    validators+=("canvas-webgl-render-smoke")
  fi
  printf '%s\n' "${validators[@]}" | awk 'NF && !seen[$0]++'
}

emit_plan() {
  detect_validators | jq -R -s '
    split("\n") | map(select(length > 0)) |
    {
      validators: map({
        command: .,
        kind: (
          if test("canvas-webgl") then "canvas_webgl_render"
          elif test("html-css-js") then "static_smoke"
          elif test("tsc") then "typescript"
          elif test("lint") then "lint"
          elif test("go test") then "go"
          elif test("swift test") then "swift"
          elif test("build") then "build"
          else "test"
          end
        )
      })
    }'
}

run_static_smoke() {
  local failed=0
  while IFS= read -r file; do
    case "$file" in
      *.html|*.htm)
        if ! rg -qi '<(html|body|main|section|article|div|canvas|script|style)[^>]*>' "$file"; then
          printf 'HTML smoke failed: %s has no recognizable app markup\n' "$file" >&2
          failed=1
        fi
        ;;
      *.css|*.scss)
        python3 - "$file" <<'PY' || failed=1
import sys
text=open(sys.argv[1], encoding="utf-8", errors="ignore").read()
if text.count("{") != text.count("}"):
    raise SystemExit(f"stylesheet braces are unbalanced: {sys.argv[1]}")
PY
        ;;
      *.js|*.mjs|*.cjs)
        node --check "$file" >/dev/null || failed=1
        ;;
    esac
  done < <(find_project_files \( -name '*.html' -o -name '*.htm' -o -name '*.css' -o -name '*.scss' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \))
  return "$failed"
}

run_canvas_webgl_smoke() {
  if has_local_bin playwright && find_project_files -name '*.html' | head -1 | grep -q .; then
    node <<'NODE'
const { chromium } = require('./node_modules/playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const html = fs.readdirSync(process.cwd()).find((name) => name.endsWith('.html')) || 'index.html';
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto('file://' + path.join(process.cwd(), html));
  await page.waitForTimeout(1000);
  const result = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    if (!canvas) return { ok: false, reason: 'no canvas' };
    const w = canvas.width || canvas.clientWidth;
    const h = canvas.height || canvas.clientHeight;
    if (w < 8 || h < 8) return { ok: false, reason: 'canvas too small' };
    let ctx;
    try { ctx = canvas.getContext('2d'); } catch (_) {}
    if (!ctx) return { ok: true, reason: 'webgl canvas present; pixel read unavailable' };
    const data = ctx.getImageData(0, 0, Math.min(w, 64), Math.min(h, 64)).data;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i] || data[i+1] || data[i+2] || data[i+3]) return { ok: true };
    }
    return { ok: false, reason: 'blank canvas pixels' };
  });
  await browser.close();
  if (!result.ok) {
    console.error('Canvas/WebGL render smoke failed:', result.reason);
    process.exit(1);
  }
})().catch((error) => { console.error(error); process.exit(1); });
NODE
    return
  fi
  if ! rg -qi 'THREE\.|BABYLON\.|PIXI\.|PlayCanvas|pc\.Application|regl\(|WebGLRenderer|WebGLRenderingContext|webgl|<canvas|requestAnimationFrame' . --glob '!**/node_modules/**' --glob '!**/dist/**' --glob '!**/build/**' --glob '!onlymacs/inbox/**' --glob '!scripts/qa/onlymacs-coding-validator.sh'; then
    printf 'Canvas/WebGL render smoke failed: no renderer/canvas/render loop evidence found\n' >&2
    return 1
  fi
}

run_validator_command() {
  local command="$1"
  case "$command" in
    html-css-js-smoke)
      run_static_smoke
      ;;
    canvas-webgl-render-smoke|threejs-canvas-nonblank-smoke)
      run_canvas_webgl_smoke
      ;;
    npm\ install*|pnpm\ install*|yarn\ add*|brew\ install*|pip\ install*|pip3\ install*)
      if [[ "$ALLOW_INSTALLS" == "1" ]]; then
        bash -lc "$command"
      else
        printf 'blocked install validator without --allow-installs: %s\n' "$command" >&2
        return 1
      fi
      ;;
    *)
      bash -lc "$command"
      ;;
  esac
}

if [[ "$MODE" == "plan" ]]; then
  emit_plan
  exit 0
fi

failures=0
results=()
while IFS= read -r command; do
  [[ -n "$command" ]] || continue
  start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  started_epoch="$(date +%s)"
  if output="$(run_validator_command "$command" 2>&1)"; then
    status="passed"
    exit_code=0
	  else
	    status="failed"
	    exit_code=1
	    failures=$((failures + 1))
	  fi
  completed="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  duration=$(( $(date +%s) - started_epoch ))
  item="$(jq -n \
    --arg command "$command" \
    --arg status "$status" \
    --arg message "$(printf '%s' "$output" | tail -20 | sed -E 's/[[:space:]]+/ /g' | cut -c 1-1200)" \
    --arg started_at "$start" \
    --arg completed_at "$completed" \
    --argjson exit_code "$exit_code" \
    --argjson duration "$duration" \
    '{command:$command,status:$status,message:$message,exit_code:$exit_code,started_at:$started_at,completed_at:$completed_at,duration_seconds:$duration}')"
  results+=("$item")
  if [[ "$JSON" -ne 1 ]]; then
    printf '%s: %s\n' "$status" "$command"
    [[ -n "$output" ]] && printf '%s\n' "$output" | tail -20
  fi
done < <(detect_validators)

if [[ "$JSON" -eq 1 ]]; then
  printf '%s\n' "${results[@]}" | jq -s --argjson failures "$failures" '{status:(if $failures == 0 then "passed" else "failed" end), failures:$failures, validators:.}'
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
