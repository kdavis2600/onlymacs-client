# Trusted Swarm File Access Plan

## Product rule

- `OnlyMacs Public` is prompt-only.
- Public swarms do not get direct access to local files, repos, or project folders.
- `local-first` is the current safe route for true local-file work.
- Private or trusted swarms are the future route for file-aware work, but they need an explicit export flow instead of live folder access.

## Example: `example-content-project` content pipeline

Example ask:

- "Use my content pipeline for `example-content-project` and generate more JSON files."

### Public swarm

This is only okay if the user provides all needed context inline:

- the pipeline instructions
- the target schema
- the example JSON shape
- any generation rules

This is not okay if the swarm would need to inspect local docs or files on its own.

Good public pattern:

- paste `content-pipeline.md`
- paste the schema or sample JSON
- ask for more entries in the same format

Bad public pattern:

- "look at my project folder and generate the next JSON batch"

### Trusted or private swarm

This is the right long-term route for file-aware work, but the ideal design is still:

- explicit file selection
- explicit repo snapshot selection
- read-only export by default

Not:

- FTP
- SMB or shared-folder mounts
- Google Drive or Dropbox sync
- broad persistent access to the whole project tree

## Best transport model

### Phase 1

Use explicit export bundles.

For a content-pipeline task, the user should export:

- the top-level pipeline guide
- the current step-specific instructions
- the output schema
- one or two example JSON files
- any glossary or reference list needed for generation

That is the safest baseline because it is:

- narrow
- reviewable
- auditable
- easy to explain

### Phase 2

Add git snapshot helpers for versioned repos.

This is useful for:

- tracked code review
- tracked content pipeline docs
- repeatable snapshots

But git alone is not enough for:

- dirty local worktrees
- ad hoc JSON files outside the repo
- generated-but-uncommitted data

So git should be a helper, not the whole security model.

## Why not FTP, folder mounts, or Drive sync

These all fail the least-privilege test.

- They expose far more than the current request needs.
- They are hard to explain to users.
- They are hard to defend in a red-team review.
- They make it difficult to prove exactly what left the Mac.

## Required controls for trusted file-aware work

1. Explicit file or repo-snapshot selection.
2. A manifest that shows exactly what will leave the Mac.
3. Secret scanning before export.
4. Default denylist for `.env`, keys, tokens, credentials, and certificates.
5. Read-only export mode first.
6. Return suggestions or patches, not direct remote writes.
7. Audit logging for exported paths and byte size.

## UX rule

When a request needs files:

- public swarm: stop and explain why
- local-first: allow
- private swarm: allow only after explicit export

## Codex-first flow

The user should stay in Codex or Claude Code.

1. The user types `/onlymacs ...`.
2. OnlyMacs detects that the request needs local files.
3. If the swarm is public, the launcher stops immediately.
4. If the swarm is private, the launcher opens a native OnlyMacs approval surface.
5. The user picks files in the OnlyMacs UI.
6. OnlyMacs writes a read-only export bundle.
7. The launcher resumes the original request automatically.

That keeps Codex or Claude Code as the front door while still using native macOS UI for explicit trust approvals.

## Current state

OnlyMacs now does the following for trusted swarm file-aware work:

- blocks public-swarm file access
- opens a native approval flow for private swarms
- suggests and preselects likely files
- previews a manifest before approval
- blocks obvious secret and credential files
- writes a read-only export manifest plus bundle
- carries the approved bundle through the launcher and bridge path
- hydrates that approved bundle on the executing machine before inference
- records a local audit history of approved exports

What it still does not do yet:

- intentionally snapshot a git repo
- offer chunked multi-part review for very large corpora
- return first-class patch/apply-back workflows
- support true remote tool execution over the exported workspace

That means private swarm file-aware work is now real, but it is still a constrained, read-only export flow rather than a full remote workspace runtime.

## Implementation phases

### Phase A

- Public-swarm hard stop for file-aware prompts.
- Honest launcher and skill messaging.

Status: implemented.

### Phase B

- Export manifest model for trusted swarms.
- User picks files or a repo snapshot before launch.

Status: manifest + explicit file picking implemented. Repo snapshot helper still pending.

### Phase C

- Secret scanner and default denylist.
- Block risky files unless user explicitly overrides.

Status: implemented with default blocking for obvious credential files and credential-like content.

### Phase D

- Git snapshot helper for versioned repos.
- Use tracked-file snapshots where possible.

Status: not implemented yet.

### Phase E

- Review-only return format.
- Suggestions, comments, or patches come back to the requester Mac.

Status: partial. Review output works, but structured patch/apply-back is still pending.

### Phase F

- Auditable history.
- "These files left your Mac for this request" record.

Status: implemented locally.

## Next implementation slices

1. Review-grade full-file mode should never silently trim a core selected file. If the approved review bundle is too large, OnlyMacs should block and ask the user to narrow the scope instead of pretending the review is complete.
2. Repo snapshot helpers should let users approve a clean tracked snapshot without manually picking every file.
3. Structured result handling should return generated files, diffs, or apply-back actions instead of only raw text.
4. Larger review bundles should eventually support chunked or staged analysis so long docs stay reviewable without flattening everything into one giant prompt.
