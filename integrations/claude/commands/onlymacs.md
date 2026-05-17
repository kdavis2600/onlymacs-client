---
name: onlymacs
description: Route this request through the installed OnlyMacs launcher.
user_invocable: true
---

When the user invokes `/onlymacs`, treat any text after the command as the OnlyMacs request.

Use the installed launcher first:

```bash
"$HOME/.local/bin/onlymacs" ...
```

If that launcher is missing but `onlymacs` already works on PATH, use:

```bash
onlymacs ...
```

Support both explicit verbs such as `check`, `go`, `plan`, `status`, `watch`, `pause`, `resume`, `stop`, `queue`, `models`, or `chat`, and plain-English asks such as:

- `/onlymacs do a code review on my project`
- `/onlymacs what is my latest swarm doing`

Summarize the meaningful result instead of dumping raw JSON unless the user asked for JSON. Include model/member/provider provenance and saved inbox paths when the launcher reports them.

Preserve `--extended`, `--plan-then-execute`, `--overnight`, and `--plan:<file>` / `--plan <file>` when supplied. These modes let OnlyMacs plan, checkpoint, validate, repair, and resume longer artifact-style work behind the scenes.

Returned files and full remote answers are expected under `onlymacs/inbox/<run-id>/`; `onlymacs/inbox/latest.json` points at the newest run. Extended or artifact-heavy runs may also include `plan.json` and per-step folders under `onlymacs/inbox/<run-id>/steps/step-XX/`. Plan-file runs use the supplied Markdown plan as the source of truth for step count, current-step prompts, expected artifacts, and resume points. Large exact-count artifact jobs may be split into remote data chunks plus a local assembly step; intermediate JSON chunks stay under `steps/step-XX/files/`, while the user-facing artifact is the named file under `onlymacs/inbox/<run-id>/files/`. Orchestrated runs may retry a dropped stream once, repair validation failures, reroute around a failing provider when another eligible Mac is available, or stop as `blocked`/`churn` when continuing would just burn time. Read that local inbox before asking the user where returned work went.

When the user is testing OnlyMacs itself, provide the exact `$onlymacs ...` skill invocation they should paste into Codex or Claude, including flags such as `--extended`. Treat direct bridge calls, curl calls, and raw terminal launcher runs as diagnostics only, not user-facing acceptance proof.

Respect OnlyMacs confirmation warnings. Do not add `--yes` unless the user clearly asked for unattended behavior.

Public swarms are prompt-only. If the request clearly depends on local files, a repo, or project-folder access, do not pretend the swarm can see those files. If OnlyMacs rejects that request on `OnlyMacs Public`, tell the user to switch to `local-first` or a private swarm.

Even on private swarms, do not imply that OnlyMacs auto-mounts the user's project folder today. Be explicit that file-aware work still needs an intentional file or repo export path.

If the launcher is unavailable, tell the user to open OnlyMacs and install or repair the launchers.
