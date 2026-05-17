# Codex Local Guidance

## Continuous Learning

- At the end of a task, run a quick learning gate: preserve only durable repo knowledge that is likely to save future debugging time, prevent repeated mistakes, explain a non-obvious OnlyMacs convention, or reduce repeated file-reading.
- Do not save task logs, ordinary implementation summaries, obvious code behavior, temporary workarounds, low-confidence guesses, or details already documented nearby.
- Save solved setup/build/test/environment failures in `docs/troubleshooting.md`, repo-wide conventions and debugging shortcuts in `docs/codex-learnings.md`, and folder-specific conventions in the closest relevant `README.md`.
- Keep `AGENTS.md` concise. Add to it only when an instruction must be loaded before work starts.
- Before adding a learning, search for overlap, merge or tighten existing entries, and keep the final note concrete enough to point future Codex sessions to the right file, command, or pattern.

## Progress Updates

- Do not paste full file contents or long command output into chat progress updates.
- In the macOS app, terminal, or any uncertain surface, prefer concise status updates.
- Reference a filename, summarize the change, or cite the file path instead of dumping contents inline.
- Only include raw file text when the user explicitly asks for it.
- For normal user-facing chat answers, do not dump file links, code citations, or long path lists unless the user explicitly asks for code references or implementation proof.
- Prefer plain-English product explanations by default.
- If code references are useful but not requested, summarize the behavior first and offer to provide the file-by-file proof only on request.
- Every progress update must make execution state explicit.
- The default assumption is that work continues after an update unless Codex explicitly says it is blocked, stopped, or waiting on input.
- If work is actually paused or blocked, say so directly in plain language, for example: `Work stopped for now, waiting for your input.`
- If Codex needs something from the user, say that plainly instead of implying work is still advancing.
- Do not force every update to begin with a stock phrase like `Status update`.
- Do not spam progress updates while actively working through a slice.
- Prefer one update at the start of a substantial slice, one if genuinely blocked or changing course, and one when the slice is complete or at a meaningful checkpoint.
- Avoid repetitive “still working” updates unless the user explicitly asks for live narration.
- Default to silence while implementing.
- Do not send another unsolicited progress update just because more than a short amount of time passed.
- Failed tool calls, patch retries, or intermediate debugging are not progress checkpoints and should not trigger a user-facing update by themselves.
- If a tool call fails and there is no real blocker for the user, fix it silently and continue.
- Only interrupt work for a progress message if one of these is true:
  - the slice completed
  - there is a real blocker or risk that needs to be surfaced
  - the implementation direction changed in a meaningful way
  - the user explicitly asked for a status update
- When the user asks for status, prefer a delta-focused status format:
  - say what actually landed in the last 30 minutes
  - say what validation ran
  - explicitly say if zero files changed
  - never say "still working" without proving whether code/docs/tests changed
  - if zero files changed and there is no real hard blocker, treat that as a cue to resume the next checkpoint immediately, not as a passive waiting state

## Refactor Discipline

- When working on native OnlyMacs macOS UI, menu bar behavior, popup layout, Control Center, onboarding, or setup windows, inspect the existing SwiftUI/AppKit boundaries before changing them.
- Keep app state/effects in `BridgeStore` unless the change is intentionally carving out a stable ownership boundary.
- When doing a large behavior-preserving refactor, architecture cleanup, repo-wide maintainability pass, public-release hardening, or open-source-readiness cleanup, use the best available refactor/audit workflow in the current Codex environment. If no such workflow is installed, inspect the code directly and keep the change scoped.

## Repository Split

- This repo owns the native macOS app, local bridge, public docs/source website, CLI integrations, release scripts, package build inputs, and app-side tests.
- Hosted coordinator service changes live outside this public client checkout. Maintainer scripts find that checkout through `ONLYMACS_COORDINATOR_REPO`, defaulting to `../OnlyMacs-coordinator`.
- Public contributor validation must not require a coordinator checkout. Use `make test` or `make test-public` for self-contained checks.
- Coordinator validation belongs behind explicit maintainer targets such as `make coordinator-test` or `make test-private`.
- Do not edit generated coordinator static output by hand. Edit website/docs source in `apps/onlymacs-web`, build it, then sync generated static into the coordinator checkout as a maintainer deploy step.
- App or bridge behavior changes belong in this repo. Hosted package, Sparkle, and coordinator deployment changes must be committed in the coordinator repo when maintainers publish a release.
- Product vocabulary is `swarm`, `member`, `sharing Mac`, `requester`, and `provider` for implementation detail. Do not reintroduce user-facing `pool` language except in legacy migration code, historical notes, or generic concepts like Apple's unified memory pool.

## Documentation Voice

- Before writing or rewriting README files, website docs, launch copy, onboarding docs, or product explanations, read `docs/onlymacs-documentation-voice.md`.
- OnlyMacs docs should explain the user pain, the action the user takes, what happens behind the scenes, why the workflow is trustworthy, and a concrete example.
- Do not default to terse engineering reference copy unless the user explicitly asks for a terse technical reference.

## Release Builds

- When the user asks Codex to make a new OnlyMacs app build for someone else to install or update from, treat it as a release build unless they explicitly say artifact-only, local-only, dry-run, or no publish.
- A release build must include the full path: build the app with the production `https://onlymacs.ai` coordinator default, sign it, notarize and staple the app/PKG/DMG as applicable, verify the artifacts, then publish the Sparkle update feed with `scripts/publish-onlymacs-update.sh`.
- Do not stop after creating a signed/notarized DMG when the user expects friends to receive updates through the app. The Sparkle publish step is part of the default release handoff.
- Static website-only changes do not require a new app build, PKG, DMG, signing, notarization, or new Sparkle version. For website copy/layout/static asset changes, rebuild/sync/deploy the web static output only. Because the website and Sparkle endpoints share the coordinator service, verify the existing Sparkle appcast and existing DMG URL after a coordinator deploy; if the deploy cleared runtime update metadata, republish the same already-signed/notarized release metadata without rebuilding the app.
- The docs/web deployment path is: edit `apps/onlymacs-web`, run its build, run `scripts/sync-onlymacs-web-static.sh`, run coordinator tests, deploy the coordinator, and verify `https://onlymacs.ai/docs`.
- After every OnlyMacs app release build, package publish, Sparkle/appcast publish, or local PKG install, relaunch the installed app before handing back to the user. This is mandatory even if Codex did not intentionally quit OnlyMacs during the flow.
- Use `open -a OnlyMacs` after the final release verification step, then confirm the app process, helper process, installed `CFBundleShortVersionString`/`CFBundleVersion`, and local bridge health on `127.0.0.1:4318`. If the installed app is behind the newly published build, say so directly and leave OnlyMacs running so Sparkle can detect/apply the update.

## OnlyMacs QA Automation

- When iterating on the trusted file-approval flow, prefer the repo-local autonomous harness at `scripts/qa/onlymacs-autonomous-trusted-review.sh` before asking the user to rerun the same manual command.
- Fold every new UI automation selector, window-control trick, or state-prep requirement back into the public QA docs when it is useful to future contributors.
- Keep generated QA logs and recursive-loop notes out of git. Use `.tmp/` or a local ignored automation directory when a harness needs durable scratch state.

## Product Vocabulary

- `Community Boost` user-facing bands currently use this label set: `Cold`, `Warming Up`, `Steady`, `Hot`, `Headliner`.
- `Community Boost` supporting trait copy currently uses: `Fresh Face`, `Backbone Mac`, `Heavy Hitter`, `Deep Bench`, `In The Mix`.
- Do not reintroduce the older user-facing band/trait vocabulary such as `Low`, `Building`, `Standard`, `Strong`, `Top`, `Reliable Backbone`, or `Premium Host` unless the user explicitly asks to roll back or revise the naming.
- When touching app copy, scripts, docs, backlog tickets, or checkpoint notes, keep this vocabulary aligned across all of them rather than updating only the runtime strings.
