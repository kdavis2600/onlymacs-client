<div align="center">

<pre>
   ____        __        __  ___
  / __ \____  / /_  __  /  |/  /___ __________
 / / / / __ \/ / / / / / /|_/ / __ `/ ___/ ___/
/ /_/ / / / / / /_/ / / /  / / /_/ / /__(__  )
\____/_/ /_/_/\__, / /_/  /_/\__,_/\___/____/
             /____/
</pre>

<strong>Where idle Macs get busy</strong>

</div>

# OnlyMacs

Your AI agents should not be trapped inside one Mac.

OnlyMacs gives Codex, Claude Code, opencode, and your terminal access to a swarm
of Apple Silicon Macs. That swarm can be your own home army of Mac Studios and
MacBook Pros, a private group of machines you trust, or public remote Macs ready
to pick up safe work. Install the menu bar app, keep using the tools you already
like, and let OnlyMacs route bigger jobs to the right Mac instead of pinning
everything to the laptop in front of you.

No model setup. No screen sharing. No SSH dance. No guessing which machine has
enough memory. Install the Mac app, run `/onlymacs` from your agent, and you are
ready in about 30 seconds.

Start with a plain command:

```text
/onlymacs "send this public README to the swarm and return the three parts that would confuse a first-time user"
```

OnlyMacs is for the moments when one AI session is not enough: long code
reviews, docs rewrites, test plans, research passes, content batches, and work
that keeps bumping into usage limits or cloud queues. Public-safe tasks can go
wide to the broader swarm. Private code can stay on this Mac or on Macs you
trust. Results come back as an answer, an inbox of files, or a patch you can
inspect before anything touches your repo.

**Why this is different.** Most AI tools assume the computer running the chat is
also the computer doing the work. OnlyMacs separates the ask from the worker.
Your daily Mac can stay responsive while other Macs do the heavy lifting, and
your route choice controls where private context is allowed to go.

OnlyMacs is alpha software. The client is open source under Apache-2.0. The
hosted coordination service is managed separately and is described here only at
the product boundary.

## The First Command To Try

The fastest way to feel what OnlyMacs does is the naked `/onlymacs` command. Say
what you need in plain English.

```text
/onlymacs "summarize this repo and tell me the first three files I should understand"
```

```text
/onlymacs "look at my current diff and call out bugs, risky assumptions, and missing tests"
```

```text
/onlymacs "rewrite this docs section so it is clearer, warmer, and shorter"
```

```text
/onlymacs "draft a test plan for the onboarding flow before I touch code"
```

```text
/onlymacs "split this cleanup into safe steps and tell me what to do first"
```

When you need to enforce a safety boundary, use explicit route words:

```text
/onlymacs go trusted-only "review my auth refactor on my trusted Macs only; call out security risks, missing tests, and anything that should not ship"
```

```text
/onlymacs go local-first "review this auth config without leaving This Mac"
```

That is the main habit: ask, let OnlyMacs route safely, review the result, then
decide what to apply.

## Plan Files For Multi-Step Jobs

Some jobs are too big for a single prompt. Write a plan file and let OnlyMacs
execute it step by step.

```markdown
# docs/release-cleanup-plan.md

## Step 1 - Read the release docs
Find stale install, update, and troubleshooting language.

## Step 2 - Rewrite the confusing sections
Keep the meaning, reduce jargon, and preserve command examples.

## Step 3 - Return a patch plan
List every proposed file change and the validation command to run.
```

Execute the plan from your usual tool:

```text
/onlymacs --plan docs/release-cleanup-plan.md
```

```bash
onlymacs --plan docs/release-cleanup-plan.md
```

Results land in your inbox as proposed files, a status manifest, and a resume
point. They do not become direct repo changes until you decide to apply them.

## What Should Run Where?

OnlyMacs uses three route classes instead of treating every prompt equally.

**local-first:** Work never leaves the machine you are on. Use it for secrets, credentials,
private configs, auth flows, and anything you do not want crossing a network
boundary.

**trusted-only:** Work stays on your trusted Macs or private swarm. Use it for private repos,
internal docs, code review, test planning, and file-aware jobs where you still
want help from machines you control.

**remote-first:** Work goes to the broader swarm. Use it for public documentation, launch copy,
open-source examples, sanitized snippets, and brainstorming that carries no
private context.

When a request needs files, file-aware remote work is designed to ask before
exporting them. Public workers never get broad repo access. Trusted workers
receive an approved bundle or staged workspace, not a live mount of your source
directory. Every answer comes back to you first.

## The Everyday Loop

Install the menu bar app, open it, and leave it running. It keeps the local
bridge alive, watches the runtime, installs or repairs launchers, and shows what
your current swarm can do.

Then work from the tool you already use:

```text
/onlymacs "find the risky parts of this refactor"
```

OnlyMacs classifies the request, picks a safe route, asks for file approval when
needed, and returns a result you can review. For quick answers you get a chat
response. For larger work you get an inbox folder with generated files, status
JSON, validation notes, and a resume point.

The habit is **review before apply**. OnlyMacs is designed to hand you grounded
output, proposed files, or patches. Directly changing your checkout is a
deliberate step you take, not the default first move.

## How OnlyMacs Keeps Private Work Private

- **Route-bound design.** Public-safe work is separate from private work from
  the first classification pass.
- **Explicit file approval.** Before a remote worker sees any file, you are
  asked to approve it. Broad repo access is not granted.
- **No live mounts.** Trusted workers receive a staged workspace, not a live
  view of your filesystem.
- **Inbox-mediated results.** Output appears under `onlymacs/inbox/`. You
  inspect, then apply.
- **Local-first for secrets.** Auth configs, tokens, and local credentials stay
  on your machine unless you deliberately choose a wider route.

## What Lives In This Repo

This is the public client repo. It contains the native app, local bridge,
website/docs source, and assistant integrations.

| Path | What lives there |
| --- | --- |
| `apps/onlymacs-macos` | Swift macOS menu bar app, setup UI, launcher installer, file approval, support bundles, update UI. |
| `apps/local-bridge` | Localhost bridge on `127.0.0.1:4318`, request policy, local API, model discovery, swarm session handoff. |
| `apps/onlymacs-web` | Public website and docs source. |
| `integrations` | `/onlymacs` launchers and shared CLI behavior for Codex, Claude Code, and terminal use. |
| `scripts` | Build, packaging, QA, release, and public-export helpers. |
| `docs` | Contributor architecture notes, trust design, QA checklists, publication notes, and documentation voice guidance. |

The hosted coordination layer is **not** part of this repo. Public client work
should not require access to its private service implementation.

## For Technical Reviewers

Start with [docs/reviewer-guide.md](docs/reviewer-guide.md). It gives the
public-client map, the first validation command, the clean public-export path,
and the intended architecture boundary between Swift, Go, and shell
compatibility code.

The shortest architecture read is:

1. `apps/onlymacs-macos` for the user-facing app and file-approval surfaces.
2. `apps/local-bridge` for localhost API policy and coordinator transport.
3. `integrations` for compatibility launchers, not long-term product policy.
4. `scripts/preflight-public-client.sh` and `scripts/export-public-client.sh`
   for public-source hygiene.

## Build From Source

For normal use, start from the app installer. For contributors, the repo can be
tested in slices.

Run the core checks:

```bash
make bootstrap
swift test --package-path apps/onlymacs-macos
cd apps/local-bridge && go test ./...
cd apps/onlymacs-web && npm run lint && npm run build
bash integrations/common/test-onlymacs-cli-intents.sh
bash scripts/qa/onlymacs-remote-work-contract-matrix.sh
bash scripts/qa/onlymacs-reporting-contract-matrix.sh
```

Or run the public client test target:

```bash
make test-public
```

`make test-public` installs web dependencies with `npm ci` when
`apps/onlymacs-web/node_modules` is missing, so it works from a fresh export.

Build a local app bundle:

```bash
make macos-app-public
```

Smoke-test the app bundle:

```bash
make app-bundle-smoke
```

Public client validation does not require access to the hosted coordination
service. Maintainer-only checks for the managed service are kept outside the
normal contributor flow.

## Local Bridge

The app-managed bridge listens at:

```text
http://127.0.0.1:4318
```

Useful local checks:

```bash
curl http://127.0.0.1:4318/health
onlymacs check
onlymacs models
onlymacs status latest
```

OpenAI-compatible local clients can point at:

```text
Base URL: http://127.0.0.1:4318/v1
API key: any non-empty placeholder
Model: best-available
```

Most users will never need these details; they are here for contributors,
debugging, and tool integration work.

## Inbox Results

Longer or artifact-heavy work is saved under:

```text
onlymacs/inbox/<run-id>/
onlymacs/inbox/latest.json
```

Common files include:

| File | Meaning |
| --- | --- |
| `status.json` | Run status, provider/model provenance, artifacts, and next step. |
| `RESULT.md` | Full result when the run completed. |
| `RESULT.partial.md` | Partial result when the run stopped early. |
| `plan.json` | Extended run state for plan-file jobs. |
| `steps/` | Per-step outputs, validation logs, retry state, and chunk files. |
| `files/` | Generated files intended for review. |

Resume the latest interrupted plan:

```bash
onlymacs resume-run latest
```

Preview output that can be applied:

```bash
onlymacs apply latest
```

Applying is intentionally separate from generating. That separation keeps the
tool useful without turning every remote answer into an automatic local change.

## Public Export

This repo was prepared for a clean public client export. The private working
repo should not be made public with its old history.

Run the private-tree preflight:

```bash
ONLYMACS_ALLOW_PRIVATE_HISTORY=1 make public-preflight
```

Create a fresh local public export:

```bash
make public-export
```

That writes a one-commit Git repo to:

```text
.tmp/onlymacs-public-client-export
```

The export preflight checks for tracked `.env` files, signing keys, package
artifacts, local agent workspaces, stale machine paths, token-looking strings,
and old private-service history.

## For Contributors

OnlyMacs is alpha software. The client is open source under Apache-2.0. See
[LICENSE](LICENSE).

Contributions that fit the public client layer are welcome: the native app,
local bridge, integrations, docs, and website. Questions about the managed
coordination service can be discussed at the product boundary, but its service
implementation lives outside this public client repo.

Start with the build-from-source steps above, then open an issue or draft PR.
Keep the review-before-apply safety model intact, and prefer route-explicit
examples when proposing new behavior.
