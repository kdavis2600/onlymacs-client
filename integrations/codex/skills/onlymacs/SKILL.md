---
name: onlymacs
description: Use when the user types /onlymacs or asks Codex to run work through OnlyMacs. Route the request through the installed OnlyMacs launcher, support both explicit verbs and plain-English asks, and report the resolved result without dumping raw JSON unless requested.
---

# OnlyMacs

Use this skill when the user wants to drive the local OnlyMacs product from Codex with `/onlymacs ...`.

## Goal

Make `/onlymacs` feel like the real branded Codex entrypoint:

- prefer the installed shell launcher at `$HOME/.local/bin/onlymacs-shell`
- fall back to the generic installed launcher at `$HOME/.local/bin/onlymacs`
- fall back to `onlymacs ...` when the command is already on PATH
- support both explicit commands and plain-English asks
- show the resolved result, not shell noise

## Runner

Prefer:

```bash
"$HOME/.local/bin/onlymacs-shell" ...
```

Fallback:

```bash
"$HOME/.local/bin/onlymacs" ...
```

Last fallback:

```bash
onlymacs ...
```

## What to pass through

- If the user supplied explicit OnlyMacs verbs such as `check`, `doctor`, `make-ready`, `status`, `runtime`, `swarms`, `sharing`, `models`, `preflight`, `benchmark`, `watch-provider`, `plan`, `start`, `go`, `watch`, `queue`, `jobs`, `job`, `tickets`, `board`, `pause`, `resume`, `resume-run`, `diagnostics`, `support-bundle`, `report`, `inbox`, `open`, `apply`, `cancel`, `stop`, `repair`, `help`, `version`, or `chat`, pass them through directly.
- If the user supplied plain-English work after `/onlymacs`, pass it through as one natural-language OnlyMacs request after adding only obvious safety and output-shape flags. The launcher remains the final authority for routing, approval, export, and policy enforcement.
- For normal non-sensitive prompt work, prefer the standard best-available swarm path. This should let capable remote Macs do the work when available while preserving local fallback. Do not add `remote-first` merely because the prompt is simple.
- Add `remote-first` only when the user clearly asks to use another Mac first, exclude This Mac, use public or remote capacity, or optimize for remote speed over local fallback.
- Add `trusted-only` or `offload-max` when the user asks to use their own Macs, avoid paid usage, use idle owned capacity, or keep work inside a trusted swarm. Add `local-first` when they ask to keep work on This Mac or mention secrets, `.env`, private keys, credentials, or similar sensitive material.
- If the user asks to create, write, generate, or save a script, document, app file, JSON file, Markdown file, or other reusable artifact, use durable inbox output. Prefer `--extended --context-write inbox` and keep the user's request as the prompt. Do not direct-write into the project unless the user explicitly asks.
- If wording can mean either "create a reusable tool" or "process an existing local file", prefer reusable artifact generation unless the user says "this file", names a path, mentions an attachment, or asks to process current local contents.
- If the user asks to review a repo, project, branch, or codebase without requesting a patch, add `--context-read git --context-write inbox`.
- If the user asks to fix code, edit files, apply a patch, or leave changes ready for review, add `--context-read git --context-write staged`. Add `--allow-tests` only when the user asks to run tests, fix failing tests, or validate behavior.
- Preserve `--yes` only when the user clearly asked for unattended launch behavior.
- Preserve `--extended`, `--plan-then-execute`, `--overnight`, and `--plan:<file>` / `--plan <file>` when supplied. These modes let OnlyMacs plan, checkpoint, validate, repair, and resume longer artifact-style work behind the scenes.

### Natural-language examples

For `/onlymacs "Create a .js file that will translate a large JSON file to English"`, treat this as standalone artifact generation. A good invocation shape is:

```bash
/onlymacs --extended --context-write inbox "Create a dependency-free Node.js script file that reads a large JSON file and translates translatable string values to English. Save the generated .js file as an artifact."
```

For `/onlymacs "Translate this local JSON file to English: ./data/messages.json"`, treat this as file-aware work and let OnlyMacs handle approval/export:

```bash
/onlymacs --extended --context-write inbox "Translate this local JSON file to English: ./data/messages.json"
```

For `/onlymacs "Review this repo for confusing auth code"`, keep the result in the inbox unless the user asks for a patch:

```bash
/onlymacs --context-read git --context-write inbox "Review this repo for confusing auth code"
```

For `/onlymacs "Fix the failing auth tests and leave the patch staged"`, route it as staged project work:

```bash
/onlymacs --context-read git --context-write staged --allow-tests "Fix the failing auth tests and leave the patch staged"
```

## Good examples

- `/onlymacs check`
- `/onlymacs status latest`
- `/onlymacs "write a dependency-free JavaScript flashcard app"`
- `/onlymacs go trusted-only "review this private auth flow"`
- `/onlymacs do a code review on my project`
- `/onlymacs what is my latest swarm doing`

## Output rules

- Do not dump raw JSON unless the user asked for JSON.
- Summarize the meaningful result:
  - resolved action or interpretation
  - queue / warning / fallback state if present
  - model/member/provider provenance when the launcher reports it
  - saved inbox paths for returned files or generated work
  - next useful step if the launcher gave one
- If the launcher is unavailable, say that plainly and tell the user to open OnlyMacs and repair the launchers.
- Returned files and full remote answers are expected under `onlymacs/inbox/<run-id>/`; `onlymacs/inbox/latest.json` points at the newest run. Prefer reading that local inbox before asking the user where the file went.
- Extended or artifact-heavy runs may also include `plan.json` and per-step folders under `onlymacs/inbox/<run-id>/steps/step-XX/`. Treat those as the source of truth for progress, retries, validation state, and resume point.
- For interrupted extended inbox runs, `onlymacs resume-run latest` resumes from the saved `resume_step` instead of starting the whole job over.
- Plan-file runs use the supplied Markdown plan as the source of truth for step count, current-step prompts, expected artifacts, and resume points. The user-facing invocation should pass the plan file through OnlyMacs rather than asking the assistant to manually remember the plan.
- Large exact-count artifact jobs may be split by OnlyMacs into remote data chunks plus a local assembly step. In those runs, intermediate JSON chunk files live under `steps/step-XX/files/`, while the user-facing artifact is the named file under `onlymacs/inbox/<run-id>/files/`.
- Orchestrated runs may retry a dropped stream once, repair validation failures, reroute around a failing provider when another eligible Mac is available, or stop as `blocked`/`churn` when continuing would just burn time.

## Acceptance Testing

- When the user is testing OnlyMacs itself, give the exact `/onlymacs ...` skill invocation they should paste into Codex or Claude, including flags such as `--extended`.
- Treat direct bridge calls, curl calls, or raw terminal launcher runs as diagnostics only. Do not count them as a successful user-facing acceptance test.
- After the user runs the exact skill call, summarize the observed inbox/status/result files and any local sanity checks.

## Default Post-Run Handoff

Do this automatically after any OnlyMacs command that returns generated work, saved files, or an inbox path. The user should not have to ask for it.

- If the command is still running and emits OnlyMacs progress lines, relay concise progress updates with elapsed time, provider/member/model when available, heartbeat count, step X/Y, percent complete when reported, and whether output is still arriving.
- When progress reports `first_token_wait` or shows no output bytes yet, describe that as model warmup / waiting for the first token. This is expected on cold models and large plan-file steps; do not call it malformed output, stuck, or failed unless the launcher reports a failure or validation error.
- After completion, read `onlymacs/inbox/latest.json` when it exists.
- Read the referenced `status.json`; read `result.json` when present.
- If `plan_path` exists in latest/status/result metadata, read it before summarizing the run.
- Report the run outcome in plain language:
  - which Mac/member/provider and model handled the work, if known
  - whether the run completed, failed, retried, or returned partial output
  - how many planned steps completed and which step is the resume point if the run stopped
  - remote token estimates from `token_accounting` when present, clearly labeling them as rough estimates
  - the saved artifact path, full remote answer path, and status path
  - the recommended next step from `status.json` when present
- If a saved artifact path exists and is readable, do a quick local sanity check on that file before finalizing. Keep this review lightweight unless the user asks for deeper review.
- Use safe checks by file type. For `.js`, run `node --check file.js` when Node is available. For `.json`, parse it with `jq` or another local JSON parser. For `.md` and `.txt`, confirm the file exists and is non-empty. Do not run generated programs unless the user explicitly asks.
- Do not move, apply, commit, or integrate returned files unless the user explicitly asks.

## Automatic Public Swarm Feedback

- Public swarm runs submit bounded feedback to the coordinator automatically by default. Do not ask for user attention before this happens.
- The report is for improving OnlyMacs coordination: redacted invocation shape, outcome, provider/member/model provenance, ticket-board snapshots when available, event counts, validation/repair/reroute signals, throughput/downtime notes, and a short Markdown summary.
- The launcher must not submit full prompts, `RESULT.md`, raw artifacts, or raw local file paths in the automatic report.
- If the user wants to opt out, run `onlymacs report disable` through the same launcher preference order. To turn it back on, run `onlymacs report enable`. Use `onlymacs report status` to check the setting.
- If the user gives explicit post-run feedback, pass it through with `onlymacs report latest --report "..."` or `onlymacs report latest --report-file path/to/report.md`.

## Safety

- Respect the launcher's confirmation model for sensitive-route and premium-misuse warnings.
- Public swarms are prompt-only. If the request clearly depends on local files, a repo, or project-folder access, do not pretend the swarm can see those files.
- If the launcher rejects a file-aware request on `OnlyMacs Public`, report that plainly and tell the user to switch to `local-first` or a private swarm.
- Even on private swarms, do not imply that OnlyMacs auto-mounts the user's project folder today. Be explicit that file-aware work still needs an intentional file or repo export path.
- Do not silently add `--yes` unless the user explicitly asked for unattended or non-interactive execution.

## File-aware execution rule

- If the user explicitly invoked `/onlymacs` for a task that needs local files or repo context, do **not** inspect the workspace locally first.
- Run the launcher with the user's actual request first and let OnlyMacs decide whether it can proceed, block on public scope, or open the trusted file approval/export flow.
- On a private swarm, if OnlyMacs opens the native file approval flow, wait for that result and continue with the launcher outcome instead of substituting a local review.
- Only fall back to a local-only review if the user explicitly asks for a local fallback or if the OnlyMacs launcher is unavailable or hard-fails before it can handle the request.
