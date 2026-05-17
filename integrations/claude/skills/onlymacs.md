---
name: onlymacs
description: Route OnlyMacs requests through the installed OnlyMacs launcher.
user_invocable: true
---

Use this when the user wants to run swarm work through OnlyMacs from Claude Code.

Prefer the installed launcher:

```bash
"$HOME/.local/bin/onlymacs" ...
```

Fallback to `onlymacs ...` only when it is already on PATH.

Pass through explicit OnlyMacs verbs directly, including `check`, `status`, `runtime`, `sharing`, `swarms`, `models`, `preflight`, `plan`, `start`, `go`, `watch`, `queue`, `pause`, `resume`, `resume-run`, `diagnostics`, `support-bundle`, `report`, `inbox`, `open`, `apply`, `cancel`, `stop`, `repair`, `help`, `version`, and `chat`.

For plain-English asks, pass the request through after adding only obvious safety and output-shape flags. Normal prompt-only work should use the best-available swarm path so capable remote Macs can help without hard-excluding This Mac. Add `remote-first` only when the user clearly asks to use another Mac first, exclude This Mac, or optimize for remote capacity. Add `trusted-only`, `offload-max`, or `local-first` when the user asks for owned Macs, trusted capacity, paid-token avoidance, This Mac, or sensitive material.

If the user asks to create, write, generate, or save a script, document, app file, JSON file, Markdown file, or other reusable artifact, prefer `--extended --context-write inbox`. If the wording can mean either "create a reusable tool" or "process an existing local file", treat it as reusable artifact generation unless the user says "this file", names a path, mentions an attachment, or asks to process current local contents. For repo reviews, prefer `--context-read git --context-write inbox`; for code fixes, patches, or staged changes, prefer `--context-read git --context-write staged`. Add `--allow-tests` only when the user asks to run tests or fix failing tests.

Preserve `--extended`, `--plan-then-execute`, `--overnight`, and `--plan:<file>` / `--plan <file>` when supplied; these modes let OnlyMacs plan, checkpoint, validate, repair, and resume longer artifact-style work behind the scenes.

Summarize the result, avoid raw JSON unless asked, and respect the launcher's confirmation model.

Returned files and full remote answers are expected under `onlymacs/inbox/<run-id>/`; `onlymacs/inbox/latest.json` points at the newest run. Extended or artifact-heavy runs may also include `plan.json` and per-step folders under `onlymacs/inbox/<run-id>/steps/step-XX/`. Plan-file runs use the supplied Markdown plan as the source of truth for step count, current-step prompts, expected artifacts, and resume points. Large exact-count artifact jobs may be split into remote data chunks plus a local assembly step; intermediate JSON chunks stay under `steps/step-XX/files/`, while the user-facing artifact is the named file under `onlymacs/inbox/<run-id>/files/`. Orchestrated runs may retry a dropped stream once, repair validation failures, reroute around a failing provider when another eligible Mac is available, or stop as `blocked`/`churn` when continuing would just burn time. When the launcher reports model, member, provider, plan, resume point, or saved paths, include those details in the summary instead of asking the user where the work went.

When the user is testing OnlyMacs itself, provide the exact `/onlymacs ...` skill invocation they should paste into Codex or Claude, including flags such as `--extended`. Treat direct bridge calls, curl calls, and raw terminal launcher runs as diagnostics only, not user-facing acceptance proof.

After any OnlyMacs command that returns generated work, saved files, or an inbox path, automatically read `onlymacs/inbox/latest.json`, the referenced `status.json`, `result.json`, and `plan.json` when present. Report which Mac/member/provider and model handled the work, whether it completed/failed/retried/returned partial output, how many planned steps completed, the resume point if any, the saved artifact path, the full remote answer path, and the recommended next step from `status.json` when present. If the saved artifact is readable, do a lightweight local sanity check before finalizing: `node --check` for `.js`, JSON parsing for `.json`, and non-empty checks for `.md` or `.txt`. Do not run generated programs, move, apply, commit, or integrate returned files unless the user explicitly asks.

If the command is still running and emits OnlyMacs progress lines, relay concise progress updates with elapsed time, provider/member/model when available, heartbeat count, and whether output is still arriving.

Public swarms are prompt-only. If the request clearly depends on local files, a repo, or project-folder access, do not pretend the swarm can see those files. If OnlyMacs rejects that request on `OnlyMacs Public`, tell the user to switch to `local-first` or a private swarm.

Even on private swarms, do not imply that OnlyMacs auto-mounts the user's project folder today. Be explicit that file-aware work still needs an intentional file or repo export path.
