# Integrations

Local wrappers for Codex and Claude-facing workflows.

These wrappers are intentionally thin. Policy and state belong to the
OnlyMacs app and the localhost bridge.
Bash code here should stay limited to launcher compatibility, agent adapters,
and smoke-test harnesses.

Current wrapper entrypoints:

- `integrations/onlymacs/onlymacs.sh`
- `integrations/codex/onlymacs-shell.sh`
- `integrations/claude/onlymacs-claude.sh`

User-facing brand direction:

- teach `/onlymacs ...` as the primary command surface inside Codex and Claude whenever the host tool supports it
- treat `onlymacs-shell.sh` and `onlymacs-claude.sh` as compatibility plumbing and local test harnesses, not the thing normal users should memorize
- let the OnlyMacs app install branded launcher shims so users can type `onlymacs ...` without digging through repo paths

Friendly commands right now:

- `check` / `doctor` / `make-ready`
- `demo`
- `go [quick|balanced|wide|local-first] [agents] [prompt]`
- `watch [session-id|latest|current|queue]`
- `pause <session-id|latest|current>`
- `resume <session-id|latest|current>`
- `stop <session-id|latest|current>`

Direct actions also available:

- `status [session-id|latest|current]`
- `runtime`
- `swarms`
- `models`
- `preflight <exact-model>`
- `plan [model|best-available] [agents] [prompt]`
- `start [model|best-available] [agents] [prompt]`
- `queue [session-id|latest|current]`
- `pause <session-id|latest|current>`
- `resume <session-id|latest|current>`
- `cancel <session-id|latest|current>`
- `repair`
- `chat <exact-model> <prompt>`

OpenClaw / OpenAI-compatible local provider setup:

- Base URL: `http://127.0.0.1:4318/v1`
- API key: any non-empty placeholder for tools that require one
- Chat endpoint: `POST /v1/chat/completions`
- Model discovery: `GET /v1/models`
- Suggested default model id: `best-available`
- Exact models are also exposed by their real model ids, such as `qwen2.5-coder:32b`, when visible in the active swarm

Example OpenClaw provider config:

```js
{
  agents: {
    defaults: { model: { primary: "onlymacs/best-available" } },
  },
  models: {
    providers: {
      onlymacs: {
        baseUrl: "http://127.0.0.1:4318/v1",
        apiKey: "onlymacs-local",
        api: "openai-completions",
        models: [
          {
            id: "best-available",
            name: "OnlyMacs best available",
            contextWindow: 200000,
            maxTokens: 8192,
          },
        ],
      },
    },
  },
}
```

For exact-model pinning, run `curl http://127.0.0.1:4318/v1/models`, copy the model id, and use `onlymacs/<model-id>` as the OpenClaw primary model. OnlyMacs resolves `best-available` through the active swarm at request time, so a 64 GB requester can route to a 128 GB or 256 GB sharer when that Mac is joined, publishing the model, and has an open slot.

Default behavior:

- pretty human-readable output is the default
- `--json` switches any command back to raw JSON for automation
- `--yes` skips the safety confirmation when a requested swarm is wider than current safe capacity
- `--title "..."` sets a friendly session title instead of relying on the generated swarm id

Model aliases:

- `best` / `best-available`
- `coder`
- `fast`
- `local-first`

If `<exact-model>` is omitted for `preflight` or `chat`, or if the wrapper is asked for `best-available`, it will prefer `qwen2.5-coder:32b`, then any visible model containing `coder`, then the first visible model from `GET /admin/v1/models`.

For `plan`, `start`, and `go`, the wrappers default `workspace_id` to the current working directory, `thread_id` to `default-thread`, derive a friendly title from the prompt unless one is passed explicitly, and generate an idempotency key from workspace, thread, model, width, title, and prompt unless `ONLYMACS_IDEMPOTENCY_KEY` is set explicitly.

Target resilient skill/wrapper contract for real swarm use:

- `plan`: ask the app what width, model, queue state, and fallback policy would actually be admitted before launching.
- `start`: launch from a plan or with explicit `requested_agents`, `max_agents`, `best available` or exact model, and fallback policy.
- `status`: inspect running or queued swarm sessions by stable session handle.
- `pause` / `cancel` / `resume`: control long-lived sessions instead of treating swarm work as fire-and-forget.
- `queue`: show queue position, waiting reason, and ETA when the swarm is saturated.
- `models`: show exact visible model names and current availability, not hidden aliases.
- `preflight`: estimate missing capacity, exact-model availability, and likely context-budget problems before launch.
- `repair`: surface version/app-state mismatch and point the user back to the OnlyMacs app when reopen or repair is required.
- `dedupe`: attach workspace/thread identity plus idempotency keys so accidental reruns do not double-spend swarm capacity.
- `tool-boundary`: keep tool execution requester-side only and expose structured result envelopes for partial results, checkpoints, and degraded-local fallback.
- `latest/current`: let users ask for `status latest`, `watch current`, or `pause latest` instead of hunting swarm ids by hand.
- `why`: expose resolved-model and route explanations so the CLI tells the user why OnlyMacs picked a model/provider instead of just echoing ids.
- `fairness`: surface uploaded/downloaded estimates and a human-readable `Community Boost` band instead of a raw ratio.

Ergonomic V1 direction now locked in the product plan:

- Codex and Claude-facing integrations should converge on one canonical branded `/onlymacs` command/skill surface, even if the packaging remains tool-specific.
- `go` should be the normal happy path and should run a hidden preflight first; users should only see a confirm step when there is a real choice such as clamp, queue, fallback, or repair.
- Friendly presets such as `quick`, `balanced`, `wide`, `precise`, `local-first`, and `remote-preferred` should map to explicit bridge policy and always echo the resolved plan.
- Friendly session references such as `latest`, `current`, `current workspace`, and titled sessions should work anywhere the user would otherwise need a session id.
- Workspace defaults and last-known-good settings now make repeat swarm launches easier over time: explicit `go` presets can seed a per-workspace default, and later unqualified launches echo when that default was reused.
- The app should be able to install launcher shims, open the supported tool, copy a starter command, and show recent sessions so users do not need to memorize wrapper paths.
- Wrapper output should stay human-readable by default and always end with one useful next step, while `--json` remains available for automation.
- Queue, promotion, completion, failure, and degraded-local continuation should be visible both in the terminal and in the OnlyMacs app through a shared lifecycle event model.
- The packaged app should teach the CLI directly with copyable `onlymacs "your task"`, `onlymacs check`, `onlymacs status latest`, and `onlymacs watch current` examples.

The wrappers now implement the core resilient control loop above for local testing. They still remain thin shells over the localhost bridge, and they do not yet execute arbitrary tools remotely or provide full production-ready swarm orchestration.

The repo now also ships a local Codex `/onlymacs` skill that fronts this same wrapper surface, so the branded command path is no longer limited to shell aliases or copied starter commands.

Desired branded examples:

1. `/onlymacs check`
2. `/onlymacs demo`
3. `/onlymacs "review this patch"`
4. `/onlymacs watch latest`

Natural-language `/onlymacs` routing should also be a first-class path, not just explicit verbs. The intended behavior is:

The shared wrapper now implements a first-wave of this routing directly for common asks such as code review, summarize, latest-status, pause/resume, exact-model requests, and local-first cost-saving prompts.

- `/onlymacs do a code review on my project`
  resolves to `chat trusted-only` because repo-aware asks should not silently leave the trusted route
- `/onlymacs brainstorm three launch taglines`
  resolves to `chat remote-first` so prompt-only work uses another Mac first when available
- `/onlymacs split this refactor into parallel workstreams`
  resolves to `plan wide` first, or `go wide` when the wording clearly asks to start
- `/onlymacs use my Macs first to save tokens on this analysis`
  resolves to `chat offload-max`
- `/onlymacs use the swarm for this review if that is the best available route`
  resolves to `chat best-available` with an explicit broader-swarm allowance instead of silently staying on a sticky narrower default
- `/onlymacs use the exact qwen2.5-coder:32b model for this audit`
  resolves to `chat qwen2.5-coder:32b`
- `/onlymacs what is my latest swarm doing`
  resolves to `status latest`
- `/onlymacs pause the current swarm`
  resolves to `pause current`

Suggested auto-routing rules:

- obvious health/setup asks map to `check`, `models`, or `repair`
- clear planning asks such as `make a plan`, `plan this`, `estimate`, `how many agents`, or `before you start` map to `plan`
- direct task asks such as `review`, `debug`, `summarize`, `analyze`, `classify`, `translate`, `write`, `build`, or `create` map to `chat`
- progress asks map to `watch` or `status`
- lifecycle verbs map directly to `pause`, `resume`, `stop`, or `cancel`
- strong cost language maps to `offload-max`
- strong quality continuity language maps to `precise` or exact-model policy
- strong parallelism language maps to `wide`
- sensitive-looking natural-language asks auto-bias to `local-first` when the user did not already choose a route explicitly
- explicit trust language maps to route scopes:
  - `local-first` / `local only` -> `local_only`
  - `trusted-only` / `my Macs only` / `offload-max` -> `trusted_only`
  - `use the swarm` / `public swarm allowed` / `best available` -> explicit balanced swarm routing
  - normal balanced/wide/precise flows stay on the active swarm
- reused workspace defaults should stay explicit: if the wrapper reuses a saved preset, it should echo that interpretation instead of silently hijacking the route

That routing is no longer limited to swarm planning. The shared wrapper and direct bridge chat path now carry the same scope rules for plain `chat` requests and self-tests too:

- `onlymacs chat "reply with ONLYMACS_SMOKE_OK exactly"` keeps the prompt-only path simple and hard-prefers another Mac first
- `onlymacs chat local-first "review this private auth flow"` keeps the request on `This Mac only`
- `onlymacs chat trusted-only "use my Macs only for this repo review"` keeps the request inside the requester's own Macs
- `offload-max` now behaves as a trusted-route policy, not as a literal model identifier

The wrapper should only ask a follow-up when the intent is truly ambiguous; otherwise it should choose the most likely command, show the resolved interpretation, and continue.

The wrapper now also treats two warning classes as explicit confirmation moments instead of silent launch behavior:

- sensitive-looking requests that are still about to leave the trusted/local route
- lightweight asks that appear to be consuming a scarce premium or beast-capacity slot

Those warnings can still be bypassed with `--yes` for unattended use, but the default interactive path is now to show the plan, explain the warning, and ask before launch. Direct `onlymacs chat ...` now follows the same confirmation rule for those warning classes instead of silently sending the request into the broader swarm.

Current repo test path:

1. `onlymacs check`
2. `onlymacs demo`
3. `onlymacs "review this patch"`
4. `onlymacs status latest`
5. `onlymacs watch current`

The packaged app now owns the launcher path too:

- it bundles the integration scripts into `OnlyMacs.app`
- it can install or refresh launcher shims into `~/.local/bin`
- it can copy a starter `onlymacs ...` command directly from the menu bar app or Settings
- the `onlymacs status` surface now also shows `Tokens saved`, `Downloaded`, `Uploaded`, and `Community Boost`

For contributor validation, start with the repository-level `make test-public` and the focused integration checks in this directory.
