# OnlyMacs File Share Strategy

Current-state technical documentation for how OnlyMacs handles targeted file sharing for `/onlymacs` requests.

This is not a roadmap. It describes the behavior in the repo as of `2026-04-19`.

## Scope

This document covers:

- when OnlyMacs decides a request needs local files
- how that differs across public, private, and local routes
- how file selection and approval currently work
- the current bundle format and staging behavior
- security and containment rules
- current limitations

## Short Version

Current rule set:

- `OnlyMacs Public` supports only **public-safe context capsules**
- private swarms are the **full file-aware path**
- both public-safe and private file-aware work use an explicit **approval flow**
- the approved files are packaged into a **bundle + manifest**
- the bridge stages that bundle into a workspace before inference or workspace execution
- OnlyMacs does **not** directly mount your local repo on another machine
- OnlyMacs does **not** directly write changes back into your local repo

## Route Policy: When File Sharing Applies

The bridge classifies requests using structured request policy in `apps/local-bridge/internal/httpapi/request_policy.go`.

Important policy outputs:

- `allow_current_route`
- `public_export_required`
- `private_export_required`
- `blocked_public`
- `local_only_recommended`

### Public swarms

Current behavior:

- open/public swarms can only use explicitly approved **public-safe capsules**
- public-safe capsules are excerpt-oriented, hide absolute paths, and disallow repo browsing or staged mutation
- public-safe capsules are meant for doc/schema/example context, not general codebase access

Current bridge reason text:

- `This request can use an approved public context capsule with excerpts only and no repo browsing.`

### Private swarms

Current behavior:

- private swarms can handle file-aware requests
- they do so only after an explicit read-only export approval
- write-intent requests can stage into a leased private workspace or a git-backed trusted workspace
- write-intent results still return structured suggested output, apply-preview diffs, or patch-like text instead of mutating the source machine directly

Current bridge reason text:

- `This request needs a read-only file export before your private swarm can work on it.`
- for write-intent cases: `OnlyMacs will treat this as approved read-only context and return changes as suggested output or patch text.`

### Local-first / This Mac

Current behavior:

- `local-first` is the current route for sensitive work that should not leave this Mac
- however, `/onlymacs` does not currently provide a full local file-aware mutation workflow for sensitive edit tasks
- the launcher tells the user to do that work directly in Codex on This Mac instead of pretending it is implemented

This is important: local-first is currently a routing/protection decision, not a hidden local file-automation magic mode.

## End-to-End File-Aware Request Flow

### 1. Request classification

The launcher sends the prompt to the bridge classifier.

The bridge derives:

- task kind
- whether local files are required
- whether write access is implied
- whether the request looks sensitive
- recommended route scope

### 2. Public or private export decision

If the request requires local files:

- a public-safe doc/schema/example request can return `public_export_required`
- a private file-aware request returns `private_export_required`
- a sensitive request returns `local_only_recommended`
- a non-public-safe public request returns `blocked_public`

### 3. Native approval request

The launcher writes a file-access request artifact and waits for the app to answer it.

Current request artifact includes:

- request id
- created time
- workspace id
- workspace root
- thread id
- prompt
- optional task kind
- route scope
- tool name
- wrapper name
- swarm name
- file access mode
- trust tier
- context-request settings
- optional seed-selected paths for follow-up rounds
- optional lease id for reusable private workspaces

On macOS, the app reads pending requests from the OnlyMacs state directory and surfaces the approval window.

## Current State Directory Layout

State path defaults:

- `~/.local/state/onlymacs`
- or `$XDG_STATE_HOME/onlymacs`
- or `$ONLYMACS_STATE_DIR` when overridden

File-sharing artifacts live under:

- `file-access/`

Current file artifacts:

- `request-<id>.json`
- `response-<id>.json`
- `claim-<id>.json`
- `manifest-<id>.json`
- `context-<id>.txt`
- `bundle-<id>.tgz`
- `bundle-<id>/` staging directory
- `history.json`

Automation-related UI command receipts live separately under:

- `automation/command-<id>.json`
- `automation/receipt-<id>.json`

## User File Selection: Current Behavior

### Suggestion model

The macOS app builds suggestions using prompt-aware heuristics in `OnlyMacsFileAccess.swift`.

Current important behaviors:

- suggestions are prompt-aware, not random
- the app tries to bias toward the highest-signal files for the task
- the user can still change the selection before approval

### Current task families used for suggestions

The current suggestion logic distinguishes between at least these practical modes:

- content-pipeline / docs review
- code review
- generation from schema/examples/docs
- transform-style requests
- generic trusted context

### What gets prioritized

For content-pipeline style asks, current recommendations prefer things like:

- master docs
- top-level readmes
- pipeline readmes
- schema files
- example files
- glossary/reference docs

For code review style asks, current recommendations prefer things like:

- source files
- config files
- package manifests
- readmes when they help explain setup or expected behavior

### User control

The approval window is not auto-share.

The user can:

- accept the recommended set
- add more files
- deselect files
- cancel the request

### Current preview states

Each selected file is currently evaluated into one of:

- `ready`
- `trimmed`
- `blocked`
- `missing`

The app also shows:

- selected count
- exportable count
- blocked count
- total selected bytes
- total export bytes
- warnings

## Export Modes and Limits

OnlyMacs currently uses four export modes.

### `public_excerpt_capsule`

Used for public-safe file-aware work.

Current settings:

- max file bytes: `72_000`
- max total export bytes: `180_000`
- max scan bytes: `90_000`
- trimming: `true`
- full file required: `false`

Meaning:

- public-safe requests are excerpt-oriented
- absolute paths stay hidden
- this path is for doc/schema/example context, not general repo browsing or codebase review

### `trusted_review_full`

Used for review-grade requests.

Current settings:

- max file bytes: `180_000`
- max total export bytes: `480_000`
- max scan bytes: `200_000`
- trimming: `false`
- full file required: `true`

Meaning:

- review tasks do not silently trim core files
- if a selected review file is too large for the current budget, it is blocked
- the user must narrow scope instead of getting a misleading partial review

### `trusted_context_flexible`

Used for generation, transform, and general trusted-context cases.

Current settings:

- max file bytes: `160_000`
- max total export bytes: `420_000`
- max scan bytes: `180_000`
- trimming: `true`
- full file required: `false`

Meaning:

- supporting context can be trimmed
- this is acceptable for some generation/transform tasks, but not for full review-grade confidence

### `private_project_lease` and `git_backed_checkout`

Used for heavier private write-intent and reusable-workspace cases.

Current behavior:

- the capsule can include a lease id so follow-up context rounds or workspace runs reuse the same staged private workspace
- git-backed mode initializes a temporary git repo from the approved files
- workspace execution can return structured apply-preview diffs based on that staged repo
- OnlyMacs still returns suggested output or patch-like results instead of mutating the source machine directly

## Security Controls: Current State

OnlyMacs currently uses a fail-closed, explicit-export model.

### What OnlyMacs blocks by path

Current blocked path fragments include:

- `.env`
- `id_rsa`
- `.pem`
- `.p12`
- `.key`
- `credentials`
- `credential`
- `secret`
- `secrets`

### What OnlyMacs blocks by content

Current content checks look for obvious secrets such as:

- private key headers
- bearer-token headers
- common cloud key patterns
- common API key prefixes

### What files are considered exportable text

The current text-first extension list explicitly includes:

- `md`, `markdown`, `txt`
- `json`, `yaml`, `yml`
- `ts`, `tsx`, `js`, `jsx`, `mjs`, `cjs`
- `swift`, `py`, `sh`
- `csv`
- `html`, `css`, `scss`, `sass`
- `xml`, `toml`, `ini`, `conf`

This matters because one real bug in the repo was that `.ts` could be misread as a media transport format; the current code now explicitly treats common code extensions as text-first.

### What OnlyMacs does not do

Current non-behaviors are just as important:

- no raw repo mount
- no background folder sync
- no FTP/SMB-style access
- no arbitrary public-swarm repo export
- no automatic direct write-back into the user’s local repo

## Bundle Format: Current State

After approval, OnlyMacs writes:

- a response JSON
- a manifest JSON
- a gzipped tar bundle
- a context text file

The bundle includes staged copies of the approved files. The manifest includes metadata for each approved file.

Current manifest fields include:

- request id
- created time
- workspace root
- workspace root label
- route scope
- swarm name
- tool name
- prompt summary
- request intent
- export mode
- trust tier
- output contract
- required sections
- grounding rules
- context request rules
- lease metadata
- workspace metadata
- file list
- warnings
- selected bytes
- export bytes

Current per-file metadata includes:

- absolute path
- relative path
- category
- selection reason
- recommended flag
- review priority
- evidence hints
- evidence anchors
- original bytes
- exported bytes
- status
- reason
- sha256

### Bundle integrity

The launcher reads the bundle path from the approval response, base64-encodes it, and attaches it to the request as `onlymacs_artifact`.

The bridge verifies:

- the bundle exists
- the bundle decodes
- the bundle checksum matches, when provided
- bundle paths do not escape the staging workspace

## Staging and Execution: Current State

### Staging

The bridge unpacks the approved bundle into a staged workspace.

Current safety checks during extraction include:

- reject empty bundle
- reject invalid paths
- reject path traversal
- reject unsupported tar entry types
- keep extracted files inside a temp root

Current staging modes:

- public-safe capsules stage into a temporary workspace with no absolute-path disclosure
- standard private capsules stage into a temporary workspace
- lease-backed private capsules can reuse a persistent staged workspace under a sanitized lease id
- git-backed private capsules can initialize a temporary git repo for diff/apply-preview quality

### Inference path

For standard grounded file-aware requests, the bridge:

1. stages the bundle
2. renders grounded artifact context into the user message
3. removes the raw artifact before upstream inference

That means the model sees approved files as structured context, not as an opaque hidden side channel.

### Workspace execution path

The bridge also has a workspace execution path for staged artifacts.

Current behavior:

- recognizes Codex and Claude-style worker tools
- stages the bundle into a working directory
- runs the tool in that staged workspace
- captures textual output
- computes changed-file summaries relative to the staged baseline
- can render structured apply-preview diffs for changed text files

Current important limitation:

- this is staged workspace execution, not direct mutation of the user’s live local checkout

## What the User Gets Back

Current private file-aware requests return one of:

- grounded review output
- grounded code review output
- grounded generation output
- grounded transform output
- workspace execution result plus staged change summary

For write-intent or transform requests, the important current truth is:

- OnlyMacs returns suggestions or patch-like text
- it does not directly apply those changes to the originating local repo

## Public vs Private Capability Summary

### Public swarm

Current file-sharing policy:

- supported only through explicit public-safe approval
- excerpt-oriented capsule export
- no repo browsing or live mount
- no staged mutation
- not every file-aware ask qualifies for public export

Good fit today:

- doc review from approved excerpts
- schema/example-grounded generation or transforms that stay excerpt-safe
- prompt-only ideation
- summaries
- rewrites
- support reply drafts
- prompt-only plan/go routing

### Private swarm

Current file-sharing policy:

- supported with explicit approval
- read-only bundle export
- grounded outputs based on approved files
- no live mount
- no direct apply-back into local repo
- supports private leased workspaces and git-backed staged workspaces for richer review/edit proposals

Good fit today:

- repo review
- doc review
- code review
- schema/example-driven generation
- transform proposals based on approved files
- staged private workspace runs with apply-preview diffs

### Local-first

Current file-sharing policy:

- preferred for sensitive requests
- not the full file-aware mutation path for `/onlymacs`

Good fit today:

- sensitive prompt-only work
- keeping risky work on This Mac

Not the current happy path for:

- “use `/onlymacs` to directly edit my sensitive local files end to end”

## Concrete Current Examples

### Works well on private swarms

```text
/onlymacs review the pipeline docs in this project and tell me what is unclear, inconsistent, or likely to break
/onlymacs compare package.json, tsconfig, and source files in this repo and tell me what configuration drift matters most
/onlymacs generate 5 new JSON lessons from the glossary, schema, and examples in this repo
/onlymacs rearrange this legacy example so it matches the current schema
```

### Blocked on public swarms

```text
/onlymacs review this repo
/onlymacs fix package.json in this repo
/onlymacs refactor this source tree to remove duplicate helpers
/onlymacs rewrite the failing test files in this repo
```

### Redirected for safety/local execution

```text
/onlymacs go local-first edit this auth helper and fix secret handling
```

Current result:

- the wrapper keeps the request local and tells the user to do the real file edit directly in Codex on This Mac

## Current Failure Modes the User Can See

Current visible failure classes include:

- public route rejected because the request is not public-safe
- private swarm not verified
- approval timed out
- approval rejected
- approved bundle missing or incomplete
- selected files blocked by secret/text rules
- review-grade file too large for full-file export budget

The current launcher/app flow is explicit about these outcomes rather than pretending the request succeeded.

## Current Auditability

OnlyMacs currently records:

- request artifacts
- approval response artifacts
- claim artifacts
- export manifest
- export bundle
- audit history entries

That gives the system a local trail of what was approved and exported for a trusted request.

## Current Limitations

These are real current-state limits, not roadmap placeholders:

- public swarms only support public-safe capsules, not arbitrary repo access
- private swarms require explicit approval for file-aware work
- file-aware work is read-only from the source machine’s perspective
- direct apply-back into the user’s live repo is not implemented
- sensitive local file-aware edits are not completed end to end through `/onlymacs`
- export budgets still exist
- success quality depends on selecting enough source-of-truth files

## Code References

Main current source files for this behavior:

- `apps/local-bridge/internal/httpapi/request_policy.go`
- `apps/local-bridge/internal/httpapi/onlymacs_artifact.go`
- `apps/local-bridge/internal/httpapi/onlymacs_tool_exec.go`
- `apps/onlymacs-macos/Sources/OnlyMacsApp/OnlyMacsFileAccess.swift`
- `apps/onlymacs-macos/Sources/OnlyMacsApp/OnlyMacsStatePaths.swift`
- `integrations/common/onlymacs-cli.sh`

If the behavior described here changes, these files are the first places to re-check.
