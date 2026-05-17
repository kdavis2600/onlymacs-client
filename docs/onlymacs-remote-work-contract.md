# OnlyMacs Remote Work Contract

Scope: expectations for prompt work and generated files returned from another Mac.

## User Questions And Current Answers

1. Did it actually start?
   - Code-backed now: direct chat creates a visible run folder under `onlymacs/inbox/<run-id>/`, writes `status.json` as `running`, and updates `onlymacs/inbox/latest.json`.
   - Remaining change: make swarm `go/start` sessions write the same local inbox status immediately, not only direct chat.

2. Which Mac is doing it?
   - Code-backed now: completed direct chat writes `provider_id`, `provider_name`, `owner_member_name`, `model`, `session_id`, `swarm_id`, and `route_scope` in `result.json` and `status.json` when response headers include them.
   - Code-backed now: running status is refreshed with provider/member/model/session provenance once response headers arrive.

3. Is it stuck?
   - Code-backed now: provider relay streams heartbeat comments every 30 seconds while a remote stream is alive but silent; the coordinator no longer has a fixed 45 second total stream cap and instead waits for continued progress.
   - Code-backed now: the CLI emits periodic progress with elapsed time, approximate token rate, selected Mac/model, heartbeat count, and updates local `status.json`.

4. Can I close this terminal?
   - Partially code-backed: swarm sessions are already inspectable through `status latest` and `watch latest`.
   - Code-backed now: if a direct chat stream fails after a session id is known, the CLI asks the local bridge for coordinator relay activity and can recover a completed or partial result from stored job state.
   - Remaining change: direct chat should become a first-class durable job before it starts streaming so a terminal can close intentionally and later reattach without treating that close as an error.

5. Where did the file go?
   - Code-backed now: returned chat files land in `onlymacs/inbox/<run-id>/files/`; `onlymacs/inbox/latest.json` points to the newest artifact.
   - Remaining change: add an `onlymacs open latest` or `onlymacs inbox` helper for humans.

6. Was anything applied to my repo?
   - Code-backed now: generated output is saved to the inbox, not applied to project source files.
   - Remaining change: add an explicit `onlymacs apply latest` flow with preview and confirmation.

7. How do I apply it?
   - Not code-backed yet.
   - Needed change: implement `onlymacs apply latest` for single-file artifacts and `patch.diff`, with a dry-run preview by default.

8. What if the output is huge?
   - Code-backed now: CLI saves full returned content to `RESULT.md` and the extracted artifact file; terminal output is capped to a preview by default and points to the inbox for the complete answer.

9. What if it fails halfway?
   - Code-backed now: direct chat writes `status.json` as `failed`, preserves partial stream content as `RESULT.partial.md`, marks the run partial, and includes retry guidance.
   - Code-backed now: if the stream fails before any output and no exported workspace artifact is attached, the CLI retries once because the prompt is safe to replay.

10. What data left my Mac?
   - Partially code-backed: `result.json` records route scope, swarm, provider/member, model, and prompt.
   - Remaining change: include file-access manifest IDs, approved paths, bundle checksums, and trust tier in every returned run manifest.

## Reliability Requirements

- Remote streaming must not have a short fixed total timeout.
- Providers must send progress or heartbeat at least every 30 seconds while work is alive.
- The coordinator must keep a job record separate from the HTTP client connection.
- Returned work must always be discoverable through a stable project-local path.
- Applying returned work must be an explicit action, never a side effect of receiving it.
- Model downloads, model imports, and app maintenance must be isolated from serving. A member can report `installing_model` or similar maintenance state for new work, but that state must not steal capacity from or invalidate an already assigned active job.
