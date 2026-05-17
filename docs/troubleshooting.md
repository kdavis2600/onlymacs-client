# Troubleshooting

Known issues, symptoms, causes, and fixes.

## Solved Issues

### Next Build Fails After Security Upgrade

**Trigger:** Upgrading `apps/onlymacs-web` Next packages or refreshing a partially installed `node_modules`.
**Symptom:** `npm run build` fails with SWC `segment '__TEXT' load command content extends beyond end of file`, or Turbopack errors while resolving Google font internals.
**Cause:** A flaky registry download can leave `node_modules/@next/swc-darwin-arm64` truncated. With Next 16, the default Turbopack build path can also fail on the generated `next/font/google` module when font fetches reset.
**Fix:** Reinstall or re-extract `@next/swc-darwin-arm64` and build with Webpack: `npm run build` should invoke `next build --webpack`.
**Future shortcut:** After any Next bump, run `npm run lint`, `npm audit --omit=dev`, and `npm run build`; if SWC is corrupt, remove `node_modules/@next/swc-darwin-arm64` and reinstall that exact locked version before testing again.

### Go Security Scan Requires Patched Toolchain

**Trigger:** Running `govulncheck` against the local bridge or coordinator with Go `1.26.2`.
**Symptom:** `govulncheck` reports reachable standard-library vulnerabilities fixed in Go `1.26.3`, including `net`, `net/http`, or `html/template` findings.
**Cause:** These are toolchain-level standard-library issues, not ordinary module dependency issues.
**Fix:** Keep the Go modules pinned to `toolchain go1.26.3`. If the patched toolchain is not installed, run `GOTOOLCHAIN=local go install golang.org/dl/go1.26.3@latest` and `go1.26.3 download`, then validate with the downloaded Go toolchain first on `PATH`.
**Future shortcut:** Run coordinator checks from the sibling coordinator checkout and local bridge checks from `apps/local-bridge`. If the Go toolchain download fails because `proxy.golang.org` resets the connection, `GOTOOLCHAIN=local go test ./...` is acceptable only as a temporary compile/test check; do not treat it as security signoff.

### Gitleaks Is Outside The Default Shell Path

**Trigger:** Running secret scans from Codex shell commands.
**Symptom:** `gitleaks` reports `command not found`, or a full `apps/onlymacs-web` directory scan spends a long time walking generated/dependency output.
**Cause:** The local `gitleaks` binary may be installed outside the non-interactive shell `PATH`; web working directories can also contain generated assets that are slower and noisier than the source files we ship.
**Fix:** Call the absolute path to the local `gitleaks` binary when needed. For source signoff, scan the actual coordinator/client subtrees that need untracked files, and for web source create a temporary copy from `git ls-files` plus a separate `--pipe` scan of ignored local env files.
**Future shortcut:** If a web scan hangs in generated output, stop it and run a tracked-source temp scan instead, then separately scan `apps/onlymacs-web/.env.local` when it exists.

### Railway Deploy Fails After Coordinator Auth Hardening

**Trigger:** Deploying the coordinator after enabling the production startup guard for scoped coordinator auth.
**Symptom:** Railway build succeeds, but the deployment never becomes healthy and logs `ONLYMACS_COORDINATOR_ADMIN_TOKEN is required in production`.
**Cause:** The production Railway service is linked and authenticated, but its environment is missing the required admin token variable. The coordinator now exits instead of booting with an open admin plane.
**Fix:** Set a new secret token in the linked coordinator checkout without printing it: `openssl rand -hex 32 | railway variable set ONLYMACS_COORDINATOR_ADMIN_TOKEN --stdin --skip-deploys`, then rerun `scripts/deploy-railway-coordinator.sh` from the main repo.
**Future shortcut:** Before a signed release deploy, run `railway status` from the coordinator checkout and confirm the production service has `ONLYMACS_COORDINATOR_ADMIN_TOKEN` configured.

### Local Bridge Token Repair Uses Runtime State Path

**Trigger:** Repairing a local public-swarm token error after coordinator scoped auth changes.
**Symptom:** Writing `coordinator-state.credentials.json` under `~/Library/Application Support/OnlyMacs` does not change the running bridge; `/admin/v1/status` still reports `valid coordinator token is required`.
**Cause:** The packaged app launches the bridge with `ONLYMACS_RUNTIME_STATE_PATH=$HOME/.local/state/onlymacs/runtime.json`, so the credential store is `$HOME/.local/state/onlymacs/runtime.credentials.json`.
**Fix:** Repair or inspect the credential file beside the active runtime state path, then restart OnlyMacs so the bridge reloads it.
**Future shortcut:** Check `ps eww -p $(pgrep -f onlymacs-local-bridge)` for `ONLYMACS_RUNTIME_STATE_PATH` before editing any local credential file.

### Requester Token Mismatch On Public Swarm

**Trigger:** A Mac joins or rejoins the public swarm after scoped coordinator auth changes, then requester work, relay execution, or session release returns `REQUESTER_TOKEN_REQUIRED`.
**Symptom:** The app shows `coordinator returned 403` with `requester token does not match this swarm member or session`.
**Cause:** The coordinator binds requester credentials to an exact `(swarm_id, member_id)` pair. A client can hit this when it sends a fallback requester token for the wrong member, or when the public-swarm member record is still bound on the coordinator but the local credential file is missing.
**Fix:** The bridge should use the exact active swarm/member requester token for reserve, relay, stream relay, and release. For public-swarm bootstrap only, a missing bound credential can recover by rotating the local node id and upserting a fresh member.
**Future shortcut:** Check `apps/local-bridge/internal/httpapi/coordinator_client.go` before using `firstRequesterToken()` on session-bound endpoints, and reproduce with a credential store containing two requester tokens.

### GitHub Actions Bash Nounset Failures

**Trigger:** Running launcher or orchestration shell contract tests in GitHub Actions.
**Symptom:** CI fails with `integrations/common/onlymacs-cli-orchestration.sh: line N: <name>: unbound variable` even though the same matrix passes locally on macOS.
**Cause:** GitHub's Ubuntu runner uses Bash 5 with `set -u`, so metadata locals that are read on failure paths must be initialized before remote calls can fail. macOS Bash 3/local scenarios may not expose the same path.
**Fix:** Initialize any local field that status, failure, or handoff logging can read, for example `local provider_name=""`, before invoking bridge/coordinator work.
**Future shortcut:** For CI-only `unbound variable` failures, inspect the function's `local` declarations first, then rerun `bash scripts/qa/onlymacs-remote-work-contract-matrix.sh` and `bash scripts/qa/onlymacs-reporting-contract-matrix.sh`.
