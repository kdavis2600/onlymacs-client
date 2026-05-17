> Archived research note: this is the design exploration that informed [../context-aware-adoption-plan.md](../context-aware-adoption-plan.md). It is kept as historical architecture context, not current-state product behavior.

## Bottom line

I would not make “remote file sharing” the core primitive. I would make **scoped, revocable context delivery** the core primitive.

Your current repo is already pointed in the right direction: public swarms are prompt-only, private swarms can do file-aware work only after explicit read-only approval, approved files are packaged into a bundle plus manifest, staged into a temporary workspace, and direct write-back into the user’s local repo is intentionally not implemented. The docs you shared describe that current behavior clearly.

My recommendation is to evolve this into three layers:

1. **Public swarms: “Sealed Context Capsules” only.**  
   A public worker never gets repo access, never gets a live file broker by default, and never gets write access. The user approves a small, explicit, redacted, immutable bundle. If the worker needs more context, it returns a structured “missing context” request that the user can approve or deny.

2. **Private swarms: “Project Context Leases.”**  
   A trusted private worker can get a session-scoped read lease for selected files, folders, globs, or named context packs. It can lazily request additional files through the source Mac’s broker, but every read is policy-checked, logged, revocable, and bounded by time, size, file type, route, swarm, and task.

3. **Optional private magic: Git-backed provider mode.**  
   For repos already on GitHub or another provider, OnlyMacs can use a GitHub App or equivalent integration to fetch a read-only sparse/partial checkout into the worker’s ephemeral workspace. Git’s sparse checkout is explicitly designed to populate only a subset of the working tree, and partial clone is designed to avoid downloading the complete repository. For write-like work, the worker returns a patch or opens a draft branch/PR only after a separate user approval.

The product framing should be:

> “OnlyMacs does not share your repo. It shares the minimum approved context needed for this job.”

---

# The core design principle

There are two very different problems hidden under “file sharing”:

**Problem A: The worker needs knowledge.**  
This should be solved with approved context: bundles, file slices, manifests, context packs, Git snapshots, or brokered reads.

**Problem B: The worker needs to mutate the user’s project.**  
This should not be solved by giving remote machines write access to the user’s folder. Solve it with generated artifacts, patch files, staged changes, or PRs.

That separation is what keeps OnlyMacs safe and understandable.

A public worker can be useful for code review, doc analysis, and content generation, but only if the user understands that approved files are leaving the Mac. Once content is disclosed to an untrusted public worker, cryptography cannot make that worker “unsee” it. So the public UX must make disclosure explicit and narrow.

Private swarms can be more magical, but “magic” should mean “remembered scoped trust,” not “unbounded remote filesystem access.”

---

# Evaluation of 15 file-sharing ideas

## 1. Prompt-only public swarms

**How it works:** Public workers receive only the prompt, no local files.

**Public fit:** Excellent for brainstorming, planning, rewriting pasted text, support replies, prompt-only decomposition, and wide ideation.

**Private fit:** Useful but underpowered.

**Security:** Best possible.

**Magic:** Low for repo-aware work.

**Recommendation:** Keep as the default public behavior and fallback. Do not remove it. Your current docs already define public swarms this way.

---

## 2. Explicit read-only approved bundle

**How it works:** The app suggests files, the user approves, OnlyMacs creates a bundle plus manifest, the bridge stages it into a temporary workspace.

**Public fit:** Good if hardened into a “public context capsule.”

**Private fit:** Excellent baseline.

**Security:** Strong because access is explicit, immutable, and auditable.

**Magic:** Medium. It requires approval, but can become one-click with good suggestions.

**Recommendation:** This should remain the base primitive for both public and private file-aware work. For public, use stricter limits and stronger warnings. For private, allow saved approvals.

Your current implementation already has most of this: approval artifacts, manifest, compressed bundle, checksum verification, temp workspace staging, secret/path blocking, text-first export, and task-specific grounded output contracts.

---

## 3. Sealed Context Capsule for public swarms

**How it works:** A stricter version of the current bundle. It contains only approved files or approved excerpts, a manifest, line maps, file hashes, user consent metadata, route scope, TTL, worker recipients, and output contract.

**Public fit:** Best option for public file-aware work.

**Private fit:** Also useful as the default safe path.

**Security:** Strong. No live access. No repo browsing. No general share. No source writes.

**Magic:** Medium. The user sees what is shared and can approve quickly.

**Recommendation:** Build this first. It is the safest way to let public swarms perform file-aware work without opening a general fileshare.

The public capsule should support three export levels:

| Export level | Public use | Description |
|---|---:|---|
| `summary` | Yes | Only source-side summaries/outlines generated locally. |
| `excerpt` | Yes | Selected line ranges or sections. |
| `full_text` | Cautious | Full approved text files, capped by stricter size/type/sensitivity rules. |

For public swarms, default to `summary` or `excerpt` unless the user explicitly chooses `full_text`.

---

## 4. Lazy “missing context” requests

**How it works:** The worker cannot browse the repo. It can return a structured request saying, “I need `docs/content-style.md` because `README.md` references it.” The user approves or denies.

**Public fit:** Good if human-gated and limited to one or two rounds.

**Private fit:** Excellent. This is the main “magic” unlock.

**Security:** Good if every request is path-scoped, reasoned, logged, and budgeted.

**Magic:** High for private swarms.

**Recommendation:** Build this as `ContextRequest v1`.

For public swarms, the worker should not receive a standing token to query files. It should return a request to the source bridge, and the user should see:

> Public worker requested 2 more files:
>  
> `docs/style-guide.md` — reason: referenced by approved pipeline doc  
> `schemas/post.schema.json` — reason: needed to validate requested content format

Then the user can approve, approve excerpts only, deny, or reroute to private/local.

---

## 5. Source-side file broker with scoped capability tokens

**How it works:** The user’s Mac runs a broker API. Workers request files through OnlyMacs, not through SMB/FTP/SSH. The broker enforces a job-specific lease.

**Public fit:** Only as a human-gated request queue. No standing live broker for arbitrary public workers.

**Private fit:** Excellent.

**Security:** Strong if implemented as capability-based access with per-job, per-worker, per-path, TTL-bound tokens.

**Magic:** High.

**Recommendation:** This should be the private swarm “magic” layer.

The broker should never mean “remote worker can browse my folder.” It should mean:

> This worker may read these approved paths, through this lease, for this task, until this time, under these budgets.

Suggested permission model:

```json
{
  "lease_id": "ctx_01J...",
  "route_scope": "private",
  "trust_tier": "private_trusted",
  "workspace_root_fingerprint": "sha256:...",
  "pool_id": "friends",
  "worker_ids": ["worker_ed25519_..."],
  "expires_at": "2026-04-19T15:00:00Z",
  "permissions": ["read:approved", "create:output"],
  "denied_permissions": ["update:source", "delete:source", "list:unapproved"],
  "grants": [
    {
      "selector": "docs/**/*.md",
      "mode": "full_text",
      "max_bytes_per_file": 180000,
      "max_total_bytes": 1000000,
      "public_allowed": false
    },
    {
      "selector": "schemas/**/*.json",
      "mode": "full_text",
      "max_bytes_per_file": 160000,
      "max_total_bytes": 160000,
      "public_allowed": true
    }
  ]
}
```

---

## 6. Named context packs

**How it works:** A repo can define reusable context packs in `.onlymacs/context-packs.yml`.

**Public fit:** Excellent if packs are explicitly marked `public_safe`.

**Private fit:** Excellent.

**Security:** Good if packs are validated and previewed.

**Magic:** Very high. This is probably the best UX improvement.

**Recommendation:** Build this early.

Example:

```yaml
version: 1

packs:
  content-pipeline:
    description: "Files needed to generate content from the markdown pipeline."
    public_safe: true
    include:
      - README.md
      - docs/content/**/*.md
      - docs/style-guide.md
      - schemas/content.schema.json
      - examples/content/**/*.md
    exclude:
      - "**/.env"
      - "**/secrets/**"
      - "**/*credential*"
      - "**/*.pem"
      - "**/*.key"
    max_total_bytes_public: 350000
    max_total_bytes_private: 1500000
    default_export_public: excerpt
    default_export_private: full_text

  code-review-core:
    description: "Core code review context."
    public_safe: false
    include:
      - README.md
      - package.json
      - tsconfig.json
      - src/**/*.ts
      - tests/**/*.ts
    exclude:
      - "**/.env"
      - "**/node_modules/**"
      - "**/dist/**"
      - "**/secrets/**"
```

Then the user can type:

```text
/onlymacs public use content-pipeline to generate 5 new draft posts
/onlymacs trusted use code-review-core to review the architecture
```

Private swarms can remember:

> Always allow my “friends” swarm to use `content-pipeline` for this repo for 30 days.

Public swarms should still show a preview unless the user has explicitly enabled a very clear “allow public-safe packs without prompting” setting.

---

## 7. Source-side context compiler

**How it works:** Before sharing files, the source Mac compiles context: summaries, outlines, symbol maps, table of contents, schema snippets, or selected line ranges.

**Public fit:** Excellent.

**Private fit:** Useful for large repos.

**Security:** Stronger than full-file sharing because less raw content leaves the Mac.

**Magic:** Medium-high.

**Recommendation:** Build as an export mode, not as a replacement for bundles.

Modes:

| Mode | Description |
|---|---|
| `full_text` | Full approved file. |
| `line_slice` | Specific line ranges. |
| `section_slice` | Markdown heading sections, JSON schema parts, function/class spans. |
| `summary` | Source-side summary generated locally. |
| `symbol_map` | Function/class/type names plus signatures, no bodies. |
| `manifest_only` | File names, sizes, hashes, categories, no content. |

For public code review, this lets you start with `manifest_only + symbol_map + selected excerpts`, then ask for more if needed.

---

## 8. GitHub App read-only checkout

**How it works:** User connects GitHub. OnlyMacs installs a GitHub App with read-only contents access. Workers fetch from GitHub into an ephemeral workspace.

**Public fit:** Usually no. Public swarms should not get repo provider credentials.

**Private fit:** Excellent for trusted swarms.

**Security:** Good if using a GitHub App rather than broad user PATs. GitHub’s docs specifically say long-lived/org integrations should use GitHub Apps, and fine-grained tokens can be limited to specific repos and permissions. GitHub’s repository contents API distinguishes read permissions for reading content/archive download from write permissions for create/update/delete operations.

**Magic:** Very high.

**Recommendation:** Build as an optional private mode.

This solves the “not on the same network” problem elegantly. The source of truth is the remote repo, not the user’s laptop. For uncommitted local changes, OnlyMacs can attach a small approved patch bundle on top of the Git checkout.

Private flow:

1. Worker creates sparse/partial checkout of repo at commit SHA.
2. OnlyMacs overlays approved uncommitted files or patches.
3. Worker does work in ephemeral workspace.
4. Worker returns patch/artifacts.
5. User approves local apply or draft PR.

---

## 9. Git sparse checkout / partial clone

**How it works:** Worker fetches only relevant paths/blobs instead of the whole repo.

**Public fit:** Not by itself. It still requires repo access.

**Private fit:** Excellent when paired with provider auth or a private broker.

**Security:** Good for minimizing exposure, but still only as safe as the auth scope.

**Magic:** High.

**Recommendation:** Use this under Git-backed private mode. Sparse checkout lets the working tree contain only selected directories/patterns, and partial clone avoids needing a complete copy of the repo.

Do not sell this as a public swarm solution unless the repo is public or the user has explicitly approved a public-safe exported snapshot.

---

## 10. Git bundle / archive snapshot

**How it works:** The source machine creates a portable Git bundle or archive and sends it to the worker.

**Public fit:** Usually too broad unless heavily path-filtered or archive-only.

**Private fit:** Useful for private swarms, especially offline/relay flows.

**Security:** Medium. A Git bundle can include history, which may contain old secrets. Git’s bundle docs describe bundles as offline transfer of Git objects and refs, so they are powerful but easy to overshare.

**Magic:** Medium.

**Recommendation:** Use carefully. Prefer `git archive`-style working-tree snapshots for context, not full Git history. Avoid sending `.git` history to public workers.

Good private variant:

```text
tracked working tree snapshot at commit SHA
+ approved uncommitted patch
+ manifest
+ no .git directory
+ no history
```

---

## 11. Presigned object-store URLs for bundles/artifacts

**How it works:** OnlyMacs uploads a capsule or output artifact to object storage and gives workers short-lived URLs.

**Public fit:** Good as transport, not as policy.

**Private fit:** Good as transport.

**Security:** Medium-good if URLs are short-lived, single-purpose, and encrypted client-side. AWS describes presigned URLs as bearer tokens whose capabilities are limited by the creator’s permissions and whose validity is time-bound.

**Magic:** High because it avoids direct peer networking.

**Recommendation:** Use for transport only. Do not treat a presigned URL as authorization by itself. Wrap it in OnlyMacs lease policy, encryption, recipient binding, checksums, and audit logs.

---

## 12. Tailscale / WireGuard private overlay

**How it works:** Trusted machines join a private network overlay and talk directly.

**Public fit:** No.

**Private fit:** Good for power users and friend groups.

**Security:** Good when configured tightly. Tailscale ACLs/grants follow least-privilege/deny-by-default ideas, and sharing can expose a specific machine to a specific external user without exposing it publicly. WireGuard’s core model associates public keys with tunnel IPs through cryptokey routing.

**Magic:** Medium. Setup can be intimidating.

**Recommendation:** Do not require this. Offer it as an advanced private swarm accelerator. Even with Tailscale/WireGuard, still expose the OnlyMacs file broker, not SMB/SSH access to the repo.

---

## 13. rclone / cloud-drive mount

**How it works:** User connects Google Drive, Dropbox, S3, etc.; workers mount or fetch files.

**Public fit:** No.

**Private fit:** Sometimes.

**Security:** Mixed. rclone can mount cloud storage as a filesystem on macOS/Linux/Windows, but mounted drives tend to blur the boundary between “needed files” and “everything in this folder.”

**Magic:** Medium-high for users who already work from cloud drives.

**Recommendation:** Avoid as core architecture. Support as an import/source provider later, where OnlyMacs still creates a scoped capsule or broker lease.

---

## 14. Syncthing-style sync folder

**How it works:** A shared folder syncs to private workers.

**Public fit:** No.

**Private fit:** Possible for trusted teams.

**Security:** Mixed. Syncthing supports untrusted encrypted devices where data sent to an untrusted device is encrypted, but trusted devices still see plaintext. Sync systems also tend to create persistent state and bidirectional edge cases.

**Magic:** High once configured.

**Recommendation:** Not core. Could be a private “advanced workspace cache” later, but OnlyMacs should still use read-only input and output artifacts.

---

## 15. Direct SSH/FTP/SMB/remote mount into the user’s Mac

**How it works:** Worker mounts or logs into the user’s machine.

**Public fit:** Absolutely no.

**Private fit:** Tempting but risky.

**Security:** Poor as a default. Hard to scope, audit, and explain. Often grants broader read/list/write powers than intended.

**Magic:** High until something goes wrong.

**Recommendation:** Do not build as a first-class OnlyMacs experience. At most, allow advanced users to bring their own transport underneath the OnlyMacs broker. The public product should never say “let your friend’s worker SSH into your repo.”

---

# Recommended architecture

## The architecture in one sentence

Build **OnlyMacs Context Access v2**: a unified system where every file-aware job receives either an immutable sealed capsule, a scoped private read lease, or a Git-backed ephemeral checkout, and every result comes back as generated artifacts or patches rather than direct source mutation.

---

# Public swarm strategy

Public swarms should support file-aware work, but only through **Sealed Context Capsules**.

## Public allowed tasks

Good public candidates:

| Task | Public support | File strategy |
|---|---:|---|
| Code review of selected files | Yes, cautious | Approved capsule, full files or excerpts. |
| Documentation review | Yes | Approved markdown/text capsule. |
| Content generation from `.md` pipeline | Yes | Public-safe context pack. |
| JSON/content generation from schema/examples | Yes | Approved schema/examples capsule. |
| Architecture critique | Yes | README/docs excerpts first. |
| “Fix my repo” | No direct fix | Return patch proposal only. |
| Secret/auth/security-sensitive code | Usually no | Reroute local/private. |
| Test execution requiring repo | No public default | Private/local only. |

## Public file-sharing policy

Public workers get:

| Permission | Public worker |
|---|---|
| Read source files | Only approved capsule contents. |
| List repo files | No, except approved manifest. |
| Ask for more files | Yes, as structured request only. |
| Create files | Yes, only in worker output artifact. |
| Update source files | No. |
| Delete source files | No. |
| Run project code | No by default. |
| See absolute local paths | No. Use sanitized relative paths. |
| See hidden files | No by default. |
| See `.env`, keys, credentials | Never. |
| Persist access after job | No. |

## Public UX

When the user types:

```text
/onlymacs public review my content pipeline and suggest improvements
```

OnlyMacs should respond with an approval sheet:

```text
This public swarm job needs project context.

Files proposed for public sharing:
✓ README.md
✓ docs/content-pipeline.md
✓ docs/style-guide.md
✓ schemas/article.schema.json
✓ examples/articles/example-01.md

Blocked:
✕ .env — blocked secret path
✕ private-notes.md — not in public-safe context pack

Sharing mode:
○ Summaries only
● Excerpts and selected full text
○ Full text for all approved files

Public workers can read these approved files but cannot access your repo,
browse other files, or write back to your Mac.

[Approve once] [Edit files] [Use private swarm instead] [Cancel]
```

The key is that public file access is an **intentional disclosure event**.

## Public context capsule manifest

Add `capsule-manifest.v2.json`:

```json
{
  "schema": "onlymacs.context_capsule.v2",
  "capsule_id": "cap_01J...",
  "request_id": "req_01J...",
  "route_scope": "public",
  "created_at": "2026-04-19T09:00:00Z",
  "expires_at": "2026-04-19T11:00:00Z",
  "workspace_root_label": "OnlyMacs Project",
  "absolute_paths_included": false,
  "source_permissions": {
    "read": "approved_snapshot_only",
    "create": "output_artifact_only",
    "update": "denied",
    "delete": "denied"
  },
  "export_mode": "public_capsule",
  "output_contract": "grounded_review",
  "required_sections": ["Findings", "Open Questions", "Referenced Files"],
  "budgets": {
    "max_files": 20,
    "max_total_bytes": 350000,
    "max_context_rounds": 1
  },
  "files": [
    {
      "relative_path": "docs/content-pipeline.md",
      "display_path": "docs/content-pipeline.md",
      "export_level": "full_text",
      "sha256": "abc...",
      "original_bytes": 42000,
      "exported_bytes": 42000,
      "line_count": 380,
      "selection_reason": "Pipeline doc referenced by prompt",
      "secret_scan": "passed"
    }
  ],
  "blocked": [
    {
      "relative_path": ".env",
      "reason": "blocked_secret_path"
    }
  ],
  "audit": {
    "approved_by_user": true,
    "approval_surface": "macos_file_approval",
    "pool_name": "OnlyMacs Public"
  }
}
```

---

# Private swarm strategy

Private swarms should optimize for “magic,” but through trust tiers.

## Private trust tiers

| Tier | UX | File model | Best for |
|---|---|---|---|
| `private_prompt_only` | No files | Prompt only | General work. |
| `private_capsule` | Approve files per job | Sealed capsule | First-time or cautious use. |
| `private_remembered_pack` | One-click or auto | Named context pack | Repeated content/doc/code workflows. |
| `private_project_lease` | Session approval | Lazy broker reads | Trusted friends/devices. |
| `private_git_backed` | Connect GitHub | Ephemeral checkout | Larger repos, no same-network assumption. |
| `private_apply_assist` | Review patch locally | Output patch/artifacts | Write-like jobs. |

## Private file-sharing policy

Private workers get:

| Permission | Private standard | Private trusted lease | Git-backed private |
|---|---:|---:|---:|
| Read approved files | Yes | Yes | Yes |
| Read additional files | Approval required | Allowed if within lease | Allowed if within repo/provider scope |
| List approved tree | Manifest only | Lease-scoped tree only | Sparse checkout scope |
| Create output files | Yes | Yes | Yes |
| Update staged workspace | Yes | Yes | Yes |
| Update user’s local repo | No | No | No |
| Delete user’s local files | No | No | No |
| Open draft PR | Optional | Optional | Yes, with separate approval |
| Apply patch locally | User approval | User approval | User approval |

The important rule:

> Private workers may mutate their own ephemeral workspace, but they do not mutate the user’s source workspace.

## Private UX

For trusted swarms, make approval durable and friendly:

```text
Allow “Friends Swarm” to read files from this project for this job?

Recommended scope:
✓ README.md
✓ docs/**
✓ schemas/**
✓ src/**/*.ts
✓ package.json
✓ tsconfig.json

Excluded automatically:
✕ .env
✕ secrets/**
✕ *.pem
✕ *.key
✕ node_modules/**
✕ .git/**

Duration:
● This job only
○ 2 hours
○ 7 days for this private swarm
○ Always ask

Permissions:
✓ Read approved files
✓ Create output artifacts
✓ Modify staged copy
✕ Modify this local repo
✕ Delete local files

[Approve] [Edit scope] [Cancel]
```

---

# The missing abstraction: Context Leases

A **Context Lease** is the core object that unifies public capsules, private broker reads, and Git-backed checkouts.

## Lease fields

```go
type ContextLease struct {
    LeaseID              string
    RequestID            string
    RouteScope           RouteScope // public, private, local
    TrustTier            TrustTier
    PoolID               string
    WorkerIDs            []string
    WorkspaceRoot        string // source-side only; never sent raw to public workers
    WorkspaceFingerprint string
    CreatedAt            time.Time
    ExpiresAt            time.Time

    Permissions          Permissions
    Grants               []FileGrant
    DenyRules            []DenyRule
    Budgets              LeaseBudgets
    OutputPolicy         OutputPolicy
    AuditPolicy          AuditPolicy
}
```

```go
type Permissions struct {
    ReadApprovedFiles      bool
    RequestMoreContext     bool
    ListApprovedTree       bool
    CreateOutputArtifacts  bool
    ModifyStagedWorkspace  bool
    ModifySourceWorkspace  bool // always false for remote workers
    DeleteSourceFiles      bool // always false for remote workers
    OpenDraftPR            bool
}
```

```go
type FileGrant struct {
    Selector        string // path or glob
    ExportMode      string // full_text, excerpt, summary, symbol_map
    MaxBytesPerFile int64
    MaxTotalBytes   int64
    AllowPublic     bool
    RequirePrompt   bool
    Reason          string
}
```

## Lease enforcement rules

1. Default deny.
2. No absolute paths to public workers.
3. No path traversal.
4. No symlinks escaping root.
5. No hidden files unless explicitly allowed.
6. No secret-like paths or content.
7. No `.git` directory.
8. No credentials from environment.
9. No source writes.
10. Every file read is logged.
11. Lease expires automatically.
12. User can revoke lease mid-job.
13. Worker can only create output artifacts.
14. Worker mutations happen only in staged workspace.
15. Applying output to source is a separate local approval.

---

# Public vs private CRUD strategy

## Source workspace permissions

| Operation | Public swarm | Private swarm | Local / This Mac |
|---|---:|---:|---:|
| Create source file | No | No | Maybe, if local agent path exists |
| Read source file | Approved snapshot only | Approved snapshot or lease | Direct local access if user is running local tool |
| Update source file | No | No | Maybe, with local tool permissions |
| Delete source file | No | No | Maybe, with local tool permissions |

## Staged worker workspace permissions

| Operation | Public swarm | Private swarm | Local / This Mac |
|---|---:|---:|---:|
| Create staged file | Yes | Yes | Yes |
| Read staged input | Yes | Yes | Yes |
| Update staged file | Yes, output area only or staged copy | Yes | Yes |
| Delete staged file | Yes, staged copy only | Yes, staged copy only | Yes |

## Returned artifact permissions

| Operation | Public swarm | Private swarm | Local / This Mac |
|---|---:|---:|---:|
| Create artifact | Yes | Yes | Yes |
| Return patch | Yes | Yes | Yes |
| Apply patch automatically | No | No by default | Possible with explicit local approval |
| Open PR | No by default | Optional | Optional |

My strong recommendation: **remote workers never get direct update/delete permissions on the user’s local files.** They can create artifacts and modify staged copies. Only the user’s Mac can apply changes.

---

# How write-like jobs should work

When the user says:

```text
/onlymacs fix the docs pipeline and generate the missing files
```

OnlyMacs should internally translate this to:

1. Approve/read context.
2. Worker writes to ephemeral output directory.
3. Worker returns:
   - `changes.patch`
   - `new-files.tgz`
   - `summary.md`
   - `apply-plan.json`
4. Source Mac shows an apply preview.
5. User selects:
   - apply all
   - apply selected files
   - save artifacts only
   - open in Codex
   - discard

Suggested `apply-plan.json`:

```json
{
  "schema": "onlymacs.apply_plan.v1",
  "request_id": "req_01J...",
  "base_revision": "git:abc123",
  "operations": [
    {
      "op": "create",
      "path": "content/posts/new-lesson-01.md",
      "source": "artifacts/new-lesson-01.md",
      "risk": "low"
    },
    {
      "op": "update",
      "path": "docs/content-pipeline.md",
      "patch": "patches/docs-content-pipeline.patch",
      "risk": "medium"
    }
  ],
  "requires_user_approval": true
}
```

---

# Route decision logic

Update the classifier so it returns not just `private_export_required` or `blocked_public`, but an explicit file-access plan.

## Proposed policy output

```json
{
  "task_kind": "grounded_code_review",
  "requires_local_files": true,
  "wants_write_access": false,
  "sensitivity": "medium",
  "recommended_route_scope": "private",
  "file_access_plan": {
    "mode": "capsule_snapshot",
    "public_allowed": true,
    "private_allowed": true,
    "local_recommended": false,
    "approval_required": true,
    "suggested_context_packs": ["code-review-core"],
    "suggested_export_level_public": "excerpt",
    "suggested_export_level_private": "full_text",
    "max_context_rounds_public": 1,
    "max_context_rounds_private": 5
  }
}
```

## Modes

| Mode | Meaning |
|---|---|
| `none` | Prompt-only. |
| `blocked_public` | Public cannot run this safely. |
| `capsule_snapshot` | Use sealed bundle. |
| `capsule_with_context_requests` | Bundle plus limited missing-context loop. |
| `private_project_lease` | Brokered private read lease. |
| `git_backed_checkout` | Provider-backed ephemeral checkout. |
| `local_only` | Must stay on this Mac. |

---

# Worker-side execution model

Every worker should see the same filesystem shape:

```text
/onlymacs-job/
  input/
    manifest.json
    context.md
    files/
      README.md
      docs/content-pipeline.md
      schemas/article.schema.json
  output/
    result.md
    patches/
    generated-files/
    apply-plan.json
  scratch/
```

Rules:

```text
input/   read-only
output/  write-only or read-write
scratch/ read-write, deleted after job
source/  never mounted
```

For public workers, avoid tool execution by default. Public jobs should be “read context, produce output.” The risk is not just malicious workers; repo files themselves can contain malicious instructions or configurations. The right trust model is similar to how untrusted workspaces are treated in other tools: restricted by default.

---

# What to do when a worker needs more files

Add a structured protocol instead of ad hoc text.

## Worker response

```json
{
  "schema": "onlymacs.context_request.v1",
  "request_id": "req_01J...",
  "worker_id": "worker_ed25519_...",
  "needed": [
    {
      "path": "docs/style-guide.md",
      "reason": "The approved pipeline doc references this as the source of formatting rules.",
      "minimum_access": "section_slice",
      "fallback_if_denied": "I can provide a generic review but cannot verify style compliance."
    },
    {
      "path": "examples/articles/example-02.md",
      "reason": "Needed to compare generated structure against existing examples.",
      "minimum_access": "full_text",
      "fallback_if_denied": "I will use only example-01."
    }
  ]
}
```

## Source-side options

The user can choose:

```text
Approve full file
Approve excerpt only
Approve summary only
Deny
Reroute to private
Reroute to local
```

For public swarms, limit this to one or two rounds. If the worker keeps asking for more, route private/local.

---

# Handling uncommitted local changes

This matters because GitHub-backed mode only sees committed remote state.

Use a layered snapshot:

```text
base = remote repo at commit SHA
overlay = approved local uncommitted files or patch
worker workspace = base + overlay
```

Approval UI:

```text
Your local repo has uncommitted changes.

Include in worker context?
✓ docs/content-pipeline.md — modified
✓ schemas/article.schema.json — modified
✕ .env — blocked
✕ scratch/private-notes.md — not selected

[Include selected changes] [Use committed GitHub state only] [Cancel]
```

Do not send the entire working tree diff by default.

---

# Recommended default behavior by route

## Public swarm default

```text
prompt-only unless:
  task is low/medium sensitivity
  files are text-first
  user approves public context capsule
  no secrets detected
  no broad repo glob
  no code execution required
  output is artifact/patch only
```

Public hard blocks:

```text
.env / credentials / keys
auth/security-sensitive code unless user explicitly reroutes private/local
requests to run tests/builds/scripts
requests needing entire repo
requests needing dependency install
requests asking for direct edits
binary/private data
```

## Private swarm default

```text
allow file-aware work through:
  approved capsule, or
  remembered context pack, or
  project context lease, or
  Git-backed checkout
```

Private hard blocks:

```text
direct source mutation
delete source files
share secrets
export credentials
silent broad repo mount
silent GitHub write token use
```

## Local-first default

```text
sensitive work stays local
OnlyMacs may invoke local tool path in future
but should not pretend remote file-aware mutation is happening
```

This aligns with your current docs, where local-first is a protection route, not a hidden local mutation runtime.

---

# Build recommendation

## Build order

I would build in this order:

1. **Context Access v2 schema**
2. **Sealed Context Capsules for public and private**
3. **Context packs**
4. **Structured missing-context request loop**
5. **Private project leases and broker**
6. **Patch/artifact apply preview**
7. **GitHub App read-only provider mode**
8. **Optional private overlay transports**
9. **Optional PR creation**

This gives you useful public file-aware work without sacrificing the security model, while making private swarms feel much more magical.

---

# Detailed implementation checklist for Codex

## Phase 1 — Policy model

Update `apps/local-bridge/internal/httpapi/request_policy.go`.

Add enums:

```go
type FileAccessMode string

const (
    FileAccessNone                    FileAccessMode = "none"
    FileAccessBlockedPublic           FileAccessMode = "blocked_public"
    FileAccessCapsuleSnapshot         FileAccessMode = "capsule_snapshot"
    FileAccessCapsuleWithRequests     FileAccessMode = "capsule_with_context_requests"
    FileAccessPrivateProjectLease     FileAccessMode = "private_project_lease"
    FileAccessGitBackedCheckout       FileAccessMode = "git_backed_checkout"
    FileAccessLocalOnly               FileAccessMode = "local_only"
)
```

```go
type TrustTier string

const (
    TrustPublicUntrusted      TrustTier = "public_untrusted"
    TrustPrivateStandard      TrustTier = "private_standard"
    TrustPrivateTrusted       TrustTier = "private_trusted"
    TrustPrivateGitBacked     TrustTier = "private_git_backed"
    TrustLocal                TrustTier = "local"
)
```

Add to policy response:

```go
type FileAccessPlan struct {
    Mode                         FileAccessMode `json:"mode"`
    TrustTier                    TrustTier      `json:"trust_tier"`
    ApprovalRequired             bool           `json:"approval_required"`
    PublicAllowed                bool           `json:"public_allowed"`
    PrivateAllowed               bool           `json:"private_allowed"`
    LocalRecommended             bool           `json:"local_recommended"`

    SuggestedContextPacks        []string       `json:"suggested_context_packs"`
    SuggestedFiles               []string       `json:"suggested_files"`
    SuggestedExportLevelPublic   string         `json:"suggested_export_level_public"`
    SuggestedExportLevelPrivate  string         `json:"suggested_export_level_private"`

    AllowContextRequests         bool           `json:"allow_context_requests"`
    MaxContextRequestRounds      int            `json:"max_context_request_rounds"`

    AllowSourceMutation          bool           `json:"allow_source_mutation"` // must be false for remote
    AllowStagedMutation          bool           `json:"allow_staged_mutation"`
    AllowOutputArtifacts         bool           `json:"allow_output_artifacts"`

    Reason                       string         `json:"reason"`
    UserFacingWarning            string         `json:"user_facing_warning"`
}
```

Classifier rules:

```text
public + prompt-only => none
public + file-aware + low/medium sensitivity => capsule_snapshot approval required
public + file-aware + high sensitivity => blocked_public or local_only
public + wants_write_access => capsule output/patch only, no source mutation
private + first-time file-aware => capsule_snapshot
private + remembered pack => capsule_snapshot or private_project_lease
private + trusted swarm + broad context => private_project_lease
private + connected Git provider => git_backed_checkout
local + sensitive => local_only
```

---

## Phase 2 — Context capsule v2

Update `apps/local-bridge/internal/httpapi/onlymacs_artifact.go` and macOS export code.

Add `context_capsule.v2` manifest fields:

```go
type CapsuleManifestV2 struct {
    Schema                 string
    CapsuleID              string
    RequestID              string
    RouteScope             string
    TrustTier              string
    CreatedAt              time.Time
    ExpiresAt              time.Time

    AbsolutePathsIncluded  bool
    WorkspaceRootLabel     string
    WorkspaceFingerprint   string

    ExportMode             string
    OutputContract         string
    RequiredSections       []string
    GroundingRules         []string

    Permissions            CapsulePermissions
    Budgets                CapsuleBudgets
    Files                  []CapsuleFile
    Blocked                []BlockedFile
    Warnings               []string
    Approval               ApprovalMetadata
}
```

Public-specific requirements:

```text
absolute_paths_included = false
route_scope = public
trust_tier = public_untrusted
source update/delete permissions = false
max context rounds <= 1 by default
manifest includes public disclosure warning
```

Add extraction tests:

```text
reject path traversal
reject absolute paths
reject symlink escape
reject unsupported tar types
reject hidden blocked paths
reject manifest/capsule mismatch
reject sha mismatch
reject expired capsule
```

---

## Phase 3 — Context packs

Add parser:

```text
apps/local-bridge/internal/contextpacks/
  parser.go
  validate.go
  match.go
  defaults.go
```

Supported config locations:

```text
.onlymacs/context-packs.yml
.onlymacs/context-packs.yaml
```

Validation rules:

```text
unknown schema version => ignore with warning
public_safe pack cannot include blocked patterns
public_safe pack cannot include broad "**/*" unless capped and previewed
excludes always override includes
hidden files require explicit include and cannot be public_safe by default
```

Add built-in pack suggestions:

```text
content-pipeline
docs-review
code-review-core
schema-generation
transform-context
```

Add UI preview to `OnlyMacsFileAccess.swift`:

```text
pack name
description
included files
blocked files
estimated bytes
public/private export mode
remember approval checkbox for private swarms
```

---

## Phase 4 — Public approval UX

In the macOS app, create a distinct approval mode:

```text
Public Context Approval
```

Required UI copy:

```text
These files will leave your Mac and may be read by public swarm workers.
Only approved files are shared. Workers cannot browse your repo or write
back to your files.
```

Buttons:

```text
Approve selected
Approve excerpts only
Edit selection
Use private swarm instead
Keep local
Cancel
```

Do not reuse private wording for public disclosure. Public approval needs to be more explicit.

Add warnings:

```text
large file
generated file
lockfile
minified file
contains email/address-like data
contains token-like data
hidden file
outside workspace root
not tracked by git
uncommitted local changes
```

---

## Phase 5 — Missing-context request loop

Add worker output detector in bridge:

```go
type ContextRequestV1 struct {
    Schema    string `json:"schema"`
    RequestID string `json:"request_id"`
    WorkerID  string `json:"worker_id"`
    Needed    []NeededContext `json:"needed"`
}
```

```go
type NeededContext struct {
    Path              string `json:"path"`
    Reason            string `json:"reason"`
    MinimumAccess     string `json:"minimum_access"` // summary, excerpt, full_text
    FallbackIfDenied  string `json:"fallback_if_denied"`
}
```

Bridge behavior:

```text
If public:
  allow only if capsule allowed context requests
  cap at max_context_request_rounds
  write new approval request artifact
  wait for app response
  create supplemental capsule
  rerun or resume worker

If private:
  if lease allows path, serve through broker
  otherwise ask user
```

Add denial object:

```json
{
  "schema": "onlymacs.context_denial.v1",
  "path": "docs/private-notes.md",
  "reason": "User denied public sharing"
}
```

Workers should receive denials so they can proceed honestly.

---

## Phase 6 — Private project lease broker

Add source-side broker module:

```text
apps/local-bridge/internal/filebroker/
  lease.go
  authorize.go
  broker_http.go
  relay.go
  audit.go
```

Broker endpoints:

```http
POST /v1/context-leases
GET  /v1/context-leases/{lease_id}/manifest
POST /v1/context-leases/{lease_id}/request-file
POST /v1/context-leases/{lease_id}/request-glob
POST /v1/context-leases/{lease_id}/revoke
```

`request-file` input:

```json
{
  "worker_id": "worker_ed25519_...",
  "path": "docs/content-pipeline.md",
  "minimum_access": "full_text",
  "reason": "Needed for grounded review"
}
```

Authorization checks:

```text
lease exists
lease not expired
worker is allowed
pool matches
route matches
path is inside workspace root
path matches grant
path does not match deny rule
file type exportable
secret scan passes
budget remains
read count remains
```

Broker output:

```json
{
  "path": "docs/content-pipeline.md",
  "export_level": "full_text",
  "sha256": "abc...",
  "bytes": 42000,
  "content_base64": "..."
}
```

Audit every read:

```json
{
  "event": "file_read",
  "lease_id": "ctx_01J...",
  "worker_id": "worker_ed25519_...",
  "path": "docs/content-pipeline.md",
  "bytes": 42000,
  "time": "2026-04-19T09:22:00Z",
  "decision": "allowed"
}
```

Revocation behavior:

```text
mark lease revoked
deny future reads
notify coordinator
tell worker context no longer available
keep audit history
```

---

## Phase 7 — Worker sandbox contract

Update `onlymacs_tool_exec.go`.

Create directories:

```text
input/ read-only
output/ read-write
scratch/ read-write
```

Before running worker tools:

```text
strip env vars except explicit allowlist
remove SSH_AUTH_SOCK
remove GITHUB_TOKEN unless provider mode explicitly needs a scoped token
remove cloud credentials
disable inherited git credential helpers where possible
set HOME to temp directory
set working directory to staged workspace
```

After running:

```text
collect output/result.md
collect patches
collect generated files
compute changed-file summary against baseline
delete scratch
preserve audit artifacts
```

Add result contract:

```json
{
  "schema": "onlymacs.worker_result.v1",
  "summary": "...",
  "referenced_files": [],
  "created_files": [],
  "modified_staged_files": [],
  "deleted_staged_files": [],
  "patches": [],
  "apply_plan": "output/apply-plan.json"
}
```

---

## Phase 8 — Apply preview

Add local apply assistant.

Never auto-apply remote changes. Instead:

```text
Show changed files
Show generated files
Show patch hunks
Show risk flags
Let user apply selected changes
```

Risk flags:

```text
modifies package manager scripts
modifies CI config
modifies auth/security code
modifies lockfiles
deletes files
adds binary
adds executable bit
adds hidden file
touches secrets path
```

Commands:

```bash
onlymacs apply latest
onlymacs apply <session-id>
onlymacs save-artifacts <session-id>
onlymacs open-patch <session-id>
```

Apply flow:

```text
verify base revision
verify patch applies cleanly
write backup or use git worktree
apply selected operations
show final git diff
```

---

## Phase 9 — GitHub provider mode

Add provider abstraction:

```text
apps/local-bridge/internal/providers/git/
  github.go
  checkout.go
  sparse.go
  overlay.go
```

Authentication recommendation:

```text
Use GitHub App for long-lived integration.
Avoid broad classic PATs.
Fine-grained PAT only as fallback.
```

GitHub supports repository contents read permissions separately from write permissions for create/update/delete operations, so OnlyMacs should request read-only contents by default and request write only for an explicit PR/apply feature.

Provider flow:

```text
resolve repo remote
resolve current branch + commit SHA
create ephemeral checkout
apply sparse patterns from context pack or lease
partial clone where supported
overlay approved uncommitted patch
run worker
return patch/artifacts
```

Optional PR flow:

```text
ask user for permission to create branch
request/write with provider token only for this operation
push branch
create draft PR
show URL
```

---

## Phase 10 — State and audit history

Extend current state directory under `file-access/`.

Add:

```text
leases/
  lease-<id>.json
  audit-<id>.jsonl
capsules/
  capsule-<id>.manifest.json
  capsule-<id>.tgz
context-requests/
  request-<id>-round-<n>.json
  response-<id>-round-<n>.json
apply/
  apply-plan-<id>.json
  apply-result-<id>.json
```

History entry should include:

```text
route
pool
worker IDs
approved files
blocked files
export mode
bytes shared
context request rounds
lease expiration
revocation time
output artifacts
apply status
```

Do not log file contents in audit history unless the user opts into debug mode.

---

## Phase 11 — Scenario matrix additions

Add scenarios to `scripts/qa/onlymacs-scenario-matrix.sh`.

Public scenarios:

```text
public prompt-only still works
public repo review suggests capsule approval
public content-pipeline pack approval succeeds
public secret file blocked
public broad repo request blocked
public context request asks user
public context request denied produces honest degraded answer
public write request returns patch only
public sensitive auth code reroutes local/private
public no absolute paths in manifest
```

Private scenarios:

```text
private first-time file-aware uses capsule
private remembered context pack skips repeated selection
private project lease allows approved lazy read
private project lease denies unapproved path
private project lease revocation stops reads
private worker can modify staged workspace
private worker cannot mutate source workspace
private output apply preview created
private GitHub provider sparse checkout works
private uncommitted overlay included only after approval
```

Security scenarios:

```text
path traversal rejected
symlink escape rejected
.env blocked
.pem blocked
bearer token blocked
hidden file public blocked
oversized review file blocked
capsule checksum mismatch rejected
expired lease rejected
wrong worker ID rejected
```

---

# What I would not build

Do not make any of these the default OnlyMacs solution:

1. Public live file broker.
2. Public repo mount.
3. Direct SSH/FTP/SMB into the user’s Mac.
4. Background sync of whole repos to workers.
5. Direct write-back from remote worker into local checkout.
6. Broad GitHub PAT access.
7. Full Git history bundles for public work.
8. Silent auto-sharing based only on prompt classification.
9. Worker access to source absolute paths.
10. Worker access to user credentials, SSH agent, Git credentials, or env vars.

---

# Final recommended product behavior

## Public swarm

**Positioning:**  
“Use public swarms for prompt-only work or explicitly approved context capsules.”

**UX:**  
Secure, transparent, consent-heavy.

**Implementation:**  
Sealed capsules, public-safe context packs, no direct broker, structured missing-context requests, no source writes.

## Private swarm

**Positioning:**  
“Use private swarms for magical file-aware work with trusted machines.”

**UX:**  
One-time trust setup, remembered context packs, lazy project leases, Git-backed checkouts.

**Implementation:**  
Context leases, source-side broker, saved approvals, GitHub App read-only mode, output apply preview.

## Local-first

**Positioning:**  
“Use This Mac for sensitive work or direct local mutation.”

**UX:**  
Safe handoff to Codex/local tools.

**Implementation:**  
No pretending. If OnlyMacs does not yet own a safe local mutation workflow, keep redirecting users honestly.

---

# The strategy I would ship

Ship this as the new mental model:

```text
Public = approved capsule only.
Private = approved capsule, remembered pack, or revocable project lease.
Git-backed private = ephemeral checkout plus optional local overlay.
Remote workers = read approved context, create artifacts.
Only the user’s Mac = applies changes.
```

That preserves the trust posture you already built, adds a viable public file-aware path, and gives private swarms the “it just works” feel without ever turning OnlyMacs into a general-purpose remote fileshare.
