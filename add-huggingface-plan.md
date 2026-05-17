# Add Hugging Face Model Import Plan

## Goal

Add an advanced "Add model from Hugging Face" path to OnlyMacs where a user can paste a Hugging Face URL, have OnlyMacs validate that the artifact is compatible with this Mac and the local runtime, download it safely, warm it up, and then offer it in the model list.

This should be a power-user import path, not the default onboarding path. The default product promise should stay curated: OnlyMacs recommends known-good models that fit the Mac.

## Product Framing

- Keep curated model recommendations as the primary first-run and normal model setup experience.
- Put Hugging Face imports under `Models -> Add Model -> From Hugging Face URL`.
- Treat custom imports as explicit and inspectable. Show exact model names, source repo, file, size, quantization, license, and validation status.
- Do not silently route swarm jobs to custom models until they pass warm-up and have enough metadata to classify their role.
- Store custom models in a separate `Custom` group in the model list, collapsed if the user has no custom models.

## Version 1 Compatibility Contract

Support only:

- Hugging Face URLs from `https://huggingface.co/...`
- Public model repos
- Single-file `.gguf` artifacts
- Text-generation models compatible with the current local runtime
- Explicit user confirmation before download

Reject or defer:

- Safetensors, PyTorch, ONNX, MLX, Core ML, and Transformers repos without GGUF files
- Multi-file split GGUFs
- Multimodal models until OnlyMacs has a real multimodal request path
- Arbitrary non-Hugging Face download URLs
- Gated/private repos until Keychain-backed Hugging Face token support exists

## User Flow

1. User clicks `Add Model` in the model library.
2. User pastes a Hugging Face repo URL or direct file URL.
3. OnlyMacs inspects the URL and repo metadata.
4. If the URL is a repo with multiple GGUF files, OnlyMacs shows a file picker with recommended quantizations first.
5. OnlyMacs shows a preflight result:
   - model file
   - download size
   - estimated installed size
   - estimated RAM requirement
   - free disk after install
   - license
   - validation warnings
6. User confirms.
7. Model enters the existing one-at-a-time download queue.
8. OnlyMacs downloads, imports/registers with the runtime, and runs a warm-up prompt.
9. Only after warm-up passes, the model appears as installed and optionally shareable.

## Validation Pipeline

### 1. URL Normalization

Accept these shapes:

- `https://huggingface.co/org/repo`
- `https://huggingface.co/org/repo/tree/main`
- `https://huggingface.co/org/repo/blob/main/file.gguf`
- `https://huggingface.co/org/repo/resolve/main/file.gguf`

Normalize into:

- `repoID`: `org/repo`
- `revision`: branch, tag, or commit SHA
- `filePath`: optional selected file

Pin the final download to an immutable commit SHA whenever possible.

### 2. Hugging Face Metadata Fetch

Fetch:

- repo existence
- repo visibility
- gated/private state
- sibling file list
- `.gguf` candidates
- LFS file size
- license metadata
- model card URL
- latest commit SHA

Use official Hugging Face API responses where possible. Use `HEAD` only as a fallback for file sizes.

### 3. Artifact Selection

If the pasted URL points directly to a `.gguf`, use that file.

If the pasted URL points to a repo, rank GGUF candidates:

1. Known practical quants: `Q4_K_M`, `Q5_K_M`, `Q6_K`, `Q8_0`
2. Smaller RAM fit before larger RAM fit
3. Non-split files before split files
4. Instruct/chat variants before base variants

If multiple files still look plausible, require the user to choose.

### 4. Hardware And Disk Fit

Preflight should calculate:

- download bytes
- expected local model bytes
- possible runtime import copy bytes
- temp/resume bytes
- required reserve floor
- estimated RAM requirement
- estimated KV cache overhead based on intended context and slot count

Do not say "guaranteed to work" before warm-up. Use labels like:

- `Fits this Mac`
- `Likely fits, needs warm-up`
- `Needs more disk space`
- `Too large for this Mac`
- `Unknown, advanced import`

### 5. Download

Use a resumable, cancellable download queue:

- one active model download at a time
- no interruption of active serving jobs
- progress by bytes, percent, and transfer rate
- retry after network failure
- checksum or ETag validation when available
- atomic move from temporary file to final storage

### 6. Runtime Registration

Current runtime path:

- Download GGUF to an OnlyMacs-managed location.
- Create a stable runtime model ID like `onlymacs/custom/{slug}`.
- Register it with Ollama via a generated Modelfile that references the GGUF.
- Account for possible duplicate storage if Ollama imports/copies the file.

Future runtime path:

- If OnlyMacs moves to bundled `llama-server`, load the GGUF directly from OnlyMacs-managed storage and avoid duplicate copies.

### 7. Warm-Up Validation

Run a small warm-up after import:

- load model
- send a tiny prompt
- require first token within a timeout
- record TTFT
- record tokens/sec
- detect runtime OOM or crash
- detect unsupported architecture or tokenizer errors

Only publish the model to the shareable model list after warm-up passes.

## Data Model

Persist custom model records in Application Support.

Suggested fields:

- `id`
- `source`: `hugging_face`
- `repo_id`
- `revision`
- `commit_sha`
- `file_path`
- `file_size_bytes`
- `local_path`
- `runtime_model_id`
- `display_name`
- `role`
- `quant_label`
- `format`
- `license_id`
- `license_display_name`
- `license_url`
- `imported_at`
- `validation_status`
- `validation_detail`
- `warmup_ttft_ms`
- `warmup_tokens_per_second`
- `estimated_ram_gb`
- `estimated_installed_gb`
- `sharing_enabled`

Default `sharing_enabled` should be false until the model has passed warm-up and the user has acknowledged the license.

## Traps And Elegant Solutions

### Trap: A Hugging Face URL is often a repo, not a runnable model file.

Solution: Treat the URL as an entry point for inspection. If there are multiple GGUFs, show an explicit artifact picker instead of guessing silently.

### Trap: Most Hugging Face repos are not compatible with the current runtime.

Solution: Version 1 is GGUF only. Give a clear rejection reason and optionally say "OnlyMacs currently imports GGUF files only."

### Trap: File size alone does not prove the model will fit in memory.

Solution: Combine file size, quant label, context size, slot count, and unified memory. Label the result as an estimate, then require warm-up before publishing.

### Trap: Disk checks undercount because runtime import can duplicate the file.

Solution: Budget pessimistically: download size plus final storage plus possible runtime copy plus reserve floor. If later measurements prove Ollama does not duplicate in a specific path, reduce the estimate then.

### Trap: Ollama may not cleanly support every arbitrary GGUF.

Solution: Keep imports in `Validating` state until `ollama create` and a test prompt both succeed. Failed imports stay visible with retry/delete actions but are not published.

### Trap: License metadata can be missing, nonstandard, or gated.

Solution: Show license as first-class UI. If missing, mark as `Unknown license` and keep sharing disabled unless the user explicitly accepts local-only responsibility. Add gated/private support only after HF token handling is implemented in Keychain.

### Trap: Custom models could pollute "best available" routing.

Solution: Do not include custom models in automatic best-route selection until OnlyMacs has role classification, warm-up metrics, and a compatibility score. Exact-model requests can use them after validation.

### Trap: Direct file URLs can enable arbitrary downloads or SSRF-like behavior through the bridge.

Solution: Parse and validate on the client. Allowlist `huggingface.co` only. Do not let the local bridge fetch arbitrary user-provided URLs.

### Trap: Branches move, so the same URL can download different weights later.

Solution: Resolve the selected artifact to a commit SHA and persist that SHA. Add a separate "Check for newer revision" action later.

### Trap: Huge files make partial downloads and app quits painful.

Solution: Use resumable downloads and persist queue state. On next launch, resume or cleanly restart from the temp file state.

### Trap: Model names can collide.

Solution: Generate runtime IDs from repo, file path, and commit SHA. Keep the human display name separate from the stable internal ID.

### Trap: Local paths and storage details should not leak to other Macs.

Solution: Publish only model ID, display name, role, quant, validation status, and capability metrics. Never publish local file paths or HF auth details.

### Trap: Downloading executable components would change distribution risk.

Solution: Enforce "weights only" for this feature. Do not download runtimes, plugins, Python packages, or conversion scripts through the model import flow.

### Trap: The menu bar popup can become overloaded.

Solution: Keep import in the companion Models window. The menu bar should only show high-level download/validation status and a shortcut to open Models.

## Implementation Phases

### Phase 1: Local Planning And Parsing

- Add URL parser and tests.
- Add `CustomModelRecord`.
- Add validation result model.
- Add UI sheet for pasted URL and preflight output.
- No download yet.

### Phase 2: Public GGUF Metadata And Disk Preflight

- Call Hugging Face metadata API.
- List candidate GGUF files.
- Estimate disk and RAM.
- Show license and warnings.
- Add tests for repo URL, file URL, no-GGUF repo, and ambiguous GGUF repo.

### Phase 3: Download Queue Integration

- Add resumable download task.
- Store temp files atomically.
- Reuse the existing model queue presentation.
- Add cancel, retry, and delete.
- Prove active serving is not interrupted.

### Phase 4: Runtime Import And Warm-Up

- Generate runtime model ID.
- Register with Ollama.
- Run warm-up prompt.
- Persist metrics and validation status.
- Publish only passed models to the local model list.

### Phase 5: Advanced Support

- Hugging Face token in Keychain.
- Gated/private repo support.
- Split GGUF support.
- Model update checks.
- Optional role classification.
- Bundled `llama-server` direct-file path to remove duplicate runtime storage.

## Acceptance Criteria

- A public direct `.gguf` Hugging Face URL can be imported, downloaded, warmed up, and shown in the model list.
- A public repo URL with multiple GGUF files shows a clear file picker.
- Non-GGUF repos fail with a clear, non-scary reason.
- Insufficient disk space blocks before download.
- Failed warm-up does not publish the model for sharing.
- Custom model metadata survives app restart.
- Deleting a custom model removes OnlyMacs storage and attempts runtime cleanup.
- No local file paths, HF tokens, or private repo metadata are published to the coordinator.

## Recommended First Slice

Build the parser, metadata preflight, and UI sheet first. That gives the product shape without risking large downloads or runtime churn. Once the preflight feels clear, wire it into the queue and warm-up path.
