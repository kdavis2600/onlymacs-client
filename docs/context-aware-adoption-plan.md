# OnlyMacs Context-Aware Adoption Plan

This document maps the archived context-aware v2 design direction onto the current OnlyMacs codebase and records the adoption status after the current implementation pass.

It is intentionally current-state and technical. It does not describe aspirational UX that is not wired into the product.

## Core Thesis

OnlyMacs should not treat "remote file access" as the primitive.

The current architecture adopts these rules instead:

- `OnlyMacs Public` is prompt-only.
- Trusted/private swarms use an explicit context policy owned by the coordinator.
- Remote workers return artifacts, patches, or bundles; local/direct write remains policy-gated.
- File-aware work is routed by structured intent, not by loose skill prose alone.
- A file-aware result must be grounded in the approved files, or fail honestly.

That means the real unit of work is:

1. classify the request
2. decide whether files are needed
3. decide whether the route is public/private/local
4. request approval if a capsule is required
5. export a bounded capsule
6. run the task against that capsule
7. require evidence in the result

## Current Code Map

### Phase 1: Policy Model

Primary files:

- `apps/local-bridge/internal/httpapi/request_policy.go`
- `apps/local-bridge/internal/httpapi/request_policy_file_access.go`
- `apps/local-bridge/internal/httpapi/context_policy.go`
- `$ONLYMACS_COORDINATOR_REPO/internal/httpapi/context_policy.go`

Current state:

- The bridge classifies requests into:
  - `task_kind`
  - `data_access`
  - `requires_local_files`
  - `wants_write_access`
  - `sensitivity`
  - `complexity`
  - `recommended_route_scope`
- The bridge now also returns a first-class `file_access_plan`, not just the coarse top-level `decision`.
- The coordinator now stores a per-swarm `context_policy`, and the bridge includes the effective swarm policy in classification responses.

`file_access_plan` currently includes:

- `mode`
  - `none`
  - `blocked_public`
  - `capsule_snapshot`
  - `capsule_with_context_requests`
  - `private_project_lease`
  - `local_only`
- `trust_tier`
- `approval_required`
- `public_allowed`
- `private_allowed`
- `local_recommended`
- `suggested_context_packs`
- `suggested_files`
- `suggested_export_level_public`
- `suggested_export_level_private`
- `allow_context_requests`
- `max_context_request_rounds`
- `context_read_mode`
- `context_write_mode`
- `allow_test_execution`
- `allow_dependency_install`
- `require_file_locks`
- `secret_guard_enabled`
- `allow_source_mutation`
- `allow_staged_mutation`
- `allow_output_artifacts`
- `reason`
- `user_facing_warning`

What this means in practice:

- prompt-only work does not need file access planning
- sensitive work is pushed to `local_only`
- public-safe doc/schema/example requests can move through an approved excerpt capsule
- private file-aware work is expressed as a capsule requirement, not a hidden repo mount
- private swarm owners can standardize context-aware read/write behavior for coding-style work

Coordinator context-policy defaults:

- public swarms are normalized to `manual_approval` read, `inbox` write, no test execution, no dependency install, file locks required, secret guard enabled
- private swarms default to `full_project_folder` read, `staged_apply` write, tests allowed, dependency installs blocked, file locks required, secret guard enabled
- admin updates for public swarms are normalized back to the safe public envelope

What is not implemented yet:

- full private lease transport
- full git-backed checkout transport
- the missing-context request loop itself

The policy model now exposes those concepts as coordinator-owned configuration and route advice. The transport is still capsule/artifact based until the lease and checkout execution paths are built end to end.

### Phase 2: Context Capsule v2

Primary files:

- `apps/onlymacs-macos/Sources/OnlyMacsApp/OnlyMacsFileAccess.swift`
- `apps/local-bridge/internal/httpapi/types.go`
- `apps/local-bridge/internal/httpapi/onlymacs_artifact.go`

Current state:

- The app-side export manifest is now a `context_capsule.v2` shape.
- The bridge understands and validates that richer capsule.

The capsule now records:

- schema and capsule identity
- request identity
- route scope and trust tier
- expiry
- whether absolute paths are included
- workspace root label and fingerprint
- export mode
- output contract
- required sections
- grounding rules
- permissions
- budgets
- selected context packs
- approved files
- blocked files
- approval metadata
- byte totals

Bridge validation now checks:

- path traversal
- unsupported tar entry types
- bundle checksum
- capsule expiry
- bundle `manifest.json` presence
- payload-manifest vs bundle-manifest mismatch
- file checksum mismatch
- public capsule path disclosure rules

What this means in practice:

- the app and bridge now share one richer capsule vocabulary
- capsules are no longer treated like just "some files plus warnings"
- the bridge can reject malformed or stale capsules instead of trusting the sender blindly

What is not implemented yet:

- lease expiry enforcement beyond capsule expiry
- direct mutation by workers without source-side apply controls

### Phase 2.5: Coding Artifact Bundles

Primary files:

- `integrations/common/onlymacs-cli.sh`
- `$ONLYMACS_COORDINATOR_REPO/internal/httpapi/types.go`
- `scripts/qa/onlymacs-coding-validator.sh`

Current state:

- the CLI understands a `onlymacs.artifact_bundle.v1` JSON return shape
- bundle validation rejects unsafe paths, duplicate targets, missing file content, malformed patches, and malformed JSON
- bundle validation rejects dangerous command metadata and dependency-install commands unless install execution is explicitly allowed
- `onlymacs apply` previews bundled file writes and bundled patches, then keeps the existing conflict checks before copying anything
- ticket reports now preserve target files, validator/capability hints, dependencies, lock groups, and context read/write mode
- additional artifact checks cover HTML, CSS/SCSS, TSX/JSX/TS brace balance, and common placeholder failure text
- a local coding validator script detects common build/test/lint gates for Node, TypeScript, Go, Swift, static web, and canvas/WebGL render smoke checks

What this means in practice:

- coding jobs can return multiple files as one structured artifact instead of relying on loose prose
- apply preview can show each target path and patch before any file is copied or applied
- admin job retros can connect tickets to concrete files and policy choices
- generated commands are observable metadata first; dangerous commands are not silently trusted

What is not implemented yet:

- automatic execution of bundle-declared validators as part of distributed ticket completion
- dependency-install tickets beyond metadata and policy flags

### Phase 2.75: Coordinator Job Board For Coding Swarms

Primary files:

- `$ONLYMACS_COORDINATOR_REPO/internal/httpapi/registry_job_board.go`
- `$ONLYMACS_COORDINATOR_REPO/internal/httpapi/job_board_handlers.go`
- `apps/local-bridge/internal/httpapi/router.go`
- `integrations/common/onlymacs-cli.sh`

Current state:

- the coordinator stores swarm jobs with has-many tickets, dependencies, target files, required capabilities, validators, finalizer state, file locks, and write journals
- admin APIs can create/list jobs, add tickets, claim tickets, heartbeat/complete/fail/requeue tickets, list locks, and run finalizer checks
- ticket claims honor dependency readiness, capability hints, stale lease requeue, same-file locks, and swarm context-write policy
- public swarms cannot claim direct-write tickets; test/dependency-install tickets are blocked unless the swarm policy allows them
- the local bridge proxies job-board APIs and enriches create/claim requests with this Mac's swarm/member/provider identity
- the CLI exposes `onlymacs jobs list|create|claim|complete|fail|requeue|heartbeat|finalize`
- the admin console shows active job boards, ticket summaries, live locks, write journal entries, dependency graph counts, finalizer state, and individual tickets

What this means in practice:

- multi-Mac coding work can be represented as a durable ticket board instead of a sequential "generate then review" chain
- idle Macs can claim ready tickets without waiting on unrelated work
- same-file edits are serialized while independent files and validation/review tickets can proceed in parallel
- job retros can be computed from ticket timing, tokens, locks, repairs, validators, and finalizer state even when no manual report is filed

What is not implemented yet:

- a long-running worker daemon that automatically claims and executes coding tickets end to end
- git-backed checkout transport for private trusted direct-write lanes
- automated merge branch/worktree creation after finalizer success

### Phase 3: Context Packs

Primary files:

- `apps/onlymacs-macos/Sources/OnlyMacsApp/OnlyMacsContextPacks.swift`
- `apps/onlymacs-macos/Sources/OnlyMacsApp/OnlyMacsFileAccess.swift`

Current state:

- OnlyMacs now has built-in context packs:
  - `content-pipeline`
  - `docs-review`
  - `code-review-core`
  - `schema-generation`
  - `transform-context`
- The app can also load custom pack config from:
  - `.onlymacs/context-packs.yml`
  - `.onlymacs/context-packs.yaml`

Custom pack config currently supports a constrained `v1` shape:

- `schema: v1`
- `packs:`
- per pack:
  - `id`
  - `description`
  - `scope`
  - `include`
  - `exclude`

Supported scopes:

- `public_safe`
- `private_only`
- `private_trusted`

Selection behavior:

- the prompt profile suggests pack ids based on task family
- matching packs can elevate files that would otherwise be ignored
- selected packs are written into capsule metadata
- invalid public-safe packs are ignored with warnings

Validation rules currently enforced:

- unknown schema is ignored with a warning
- broad public-safe workspace globs are rejected
- public-safe packs cannot target hidden files by default
- excludes override includes

What this means in practice:

- file selection is no longer only a hardcoded prompt-profile heuristic
- repo-local pack config can widen or tighten file suggestion behavior
- the capsule records which pack logic contributed to the export

What is not implemented yet:

- pack-aware approval UI surfaces in the native window
- remembered approvals per pack
- remembered pack defaults for public-safe excerpt export

## QA and Refactor Pass

This adoption slice included a final QA/refactor pass instead of leaving the changes as raw feature additions.

Refactor choices:

- extracted file-access-plan logic into its own bridge file
- extracted context-pack parsing/matching into its own macOS app file
- kept the app/bridge capsule vocabulary aligned instead of inventing separate phase names in each layer

Validation coverage added or extended:

- request-policy corpus and file-access-plan checks
- camelCase and snake_case capsule decoding
- expired capsule rejection
- manifest mismatch rejection
- app-side capsule manifest encoding
- context-pack parsing and matching
- context-pack-driven file suggestion behavior

## Current Product Behavior After This Pass

### Public swarm

- prompt-only is still the default happy path
- approved public-safe doc/schema/example requests can use an excerpt capsule
- general repo browsing and code-review style exports are still blocked

### Private swarm

- context policy defaults to full-project/staged-apply convenience
- app exports approved context capsules until full leases/checkouts are implemented
- bridge validates the capsule
- result shaping stays grounded to approved files and returned artifacts/bundles

### Local

- sensitive work is recommended or forced local by policy
- no capsule export is required

## Remaining High-Value Work

These items are still not implemented in current state:

- public approval UX for excerpt-only capsules
- actual missing-context request rounds
- private project lease transport
- git-backed trusted workspace transport
- distributed worker execution for test/install tickets under swarm policy
- richer admin editing UI for per-swarm context policy

Those are the next architectural slices if OnlyMacs continues down the `context-aware-v2` path.
