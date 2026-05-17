# Codex Learnings

Durable repo lessons that help future Codex sessions avoid repeated investigation.

This is not a changelog. Only add learnings that are likely to save future time.

## Repo-Wide Learnings

### Local Codex Surfaces Are Ignored

**Context:** When adding repo-scoped Codex hooks, local skills, or other agent workspace files for OnlyMacs.
**Learning:** `.codex/` and `.agents/` are intentionally ignored by `.gitignore`; use them for local experiments, but put durable shared guidance in `AGENTS.md`, `CODEX.md`, or `docs/`.
**Use next time:** Verify local hook/skill files with `git status --short --ignored .codex .agents`; change `.gitignore` deliberately before trying to ship those files to other contributors.

### Public Export From A Dirty Private Tree

**Context:** When publishing the public client while unrelated local or user-owned edits are present in the private checkout.
**Learning:** `make public-export` intentionally refuses a dirty working tree, but the public export can still be rebuilt safely from the committed `HEAD` tree with `git archive` without stashing, reverting, or copying unrelated dirty files.
**Use next time:** If the desired source commit is already committed, recreate `.tmp/onlymacs-public-client-export` from `git archive HEAD`, initialize a fresh one-commit repo inside it, run `scripts/preflight-public-client.sh`, then push that export.

### Codex Goal Command Is A Feature Flag

**Context:** When a user asks why `/goal` is missing or how to enable it in Codex Desktop or CLI.
**Learning:** `/goal` is an experimental Codex CLI slash command, not a local skill. Enable it through `/experimental` or `~/.codex/config.toml` with `[features] goals = true`; Codex Desktop may only show it if the desktop build shares that config and supports the feature.
**Use next time:** Check the official Codex docs first, then inspect `~/.codex/config.toml` before creating or suggesting a local `goal` skill.

### Coordinator Scoped Auth Tests

**Context:** When changing coordinator routes that distinguish local/dev open behavior from production scoped-token behavior.
**Learning:** Production-mode auth tests need both `PORT` and `ONLYMACS_COORDINATOR_ADMIN_TOKEN` set. Bootstrap routes such as public swarm join, unlisted private swarm create, and provider register may mint requester/provider credentials without an existing token, while product routes should be exercised with the returned bearer token. Public/listed swarm creation remains admin-only.
**Use next time:** For strict coordinator tests, use `t.Setenv("PORT", "12345")`, set an admin token, bootstrap through `/admin/v1/swarms/join`, `/admin/v1/swarms`, or `/admin/v1/providers/register`, then pass the returned `credentials.*.token` on requester/provider/owner routes.

### Released App Uses Hosted Coordinator Only

**Context:** When touching macOS coordinator settings, recovery UI, setup copy, or stored coordinator migration.
**Learning:** The released app should expose only the hosted coordinator path. Embedded/local coordinator code can remain for future internal work, but public UI and recovery actions should not offer it; persisted local, localhost, or missing coordinator settings should migrate to the packaged hosted URL, or `https://onlymacs.ai` when no packaged URL exists.
**Use next time:** Check `CoordinatorConnectionSettings`, `BridgeStore.resolveStoredCoordinatorSettings`, and `CoordinatorConnectionPanel` together before changing coordinator mode behavior.

### Release Environment Can Poison Runtime State

**Context:** When a release, smoke test, or Codex shell relaunch leaves the installed app showing coordinator token errors or a temp runtime path.
**Learning:** Launching the packaged app from a shell can leak `ONLYMACS_*` release/test variables into the app and helper process. If `ONLYMACS_STATE_DIR` reaches the app, the bridge can read a temp credential store instead of `~/.local/state/onlymacs/runtime.credentials.json`.
**Use next time:** Inspect the bridge environment with `ps eww -p $(pgrep -f onlymacs-local-bridge)` before repairing credentials. The app should ignore production `ONLYMACS_STATE_DIR` overrides and sanitize helper environments.

### Sparkle Updates Can Leave An Old Bridge Running

**Context:** After Sparkle installs a new app build but `/admin/v1/status` still reports an older `sharing.client_build`.
**Learning:** The installed app bundle can update while an orphaned `onlymacs-local-bridge` keeps `127.0.0.1:4318` occupied. The new app process starts, but the stale bridge continues serving status until it is stopped.
**Use next time:** Compare `CFBundleVersion` with `.sharing.client_build.build_number`, then run `ps -axo pid,ppid,command | rg 'OnlyMacsApp|onlymacs-local-bridge'`. If the bridge is an old orphan, kill only that helper PID and let the current app supervisor restart it.

### Plan-File Steps Should Stay Narrow

**Context:** When an extended `--plan:<file>` run produces cross-step or wrong-language artifacts, especially in large locale/content jobs.
**Learning:** Each remote step should receive the current step plus compact plan-level rules, not the whole plan body. If every step prompt embeds the full plan, later source chunks can leak into earlier outputs and validation may pass JSON shape while content is wrong.
**Use next time:** Inspect `onlymacs/inbox/<run>/prompt.txt` and `plan.json` before rerunning. If the prompt contains the full plan under every step, use the 0.3.23+ launcher behavior or patch `integrations/common/onlymacs-cli-orchestration.sh` so per-step prompts are trimmed.
