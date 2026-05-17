# OnlyMacs Architecture Overview

This is the shortest useful map for a new engineer.

## Top-level system

OnlyMacs has four primary runtime pieces:

1. `apps/onlymacs-macos`
   The packaged macOS product shell. It owns the popup-first menu bar UI, the dedicated file-approval window, launcher installation, model/setup guidance, and operator-facing recovery surfaces.
2. `apps/local-bridge`
   The localhost control plane. It accepts launcher requests, applies request policy, talks to the coordinator, and handles local or relayed execution.
3. Separate coordinator checkout
   The shared relay and membership service for swarms. By default,
   maintainer scripts look for this at `../OnlyMacs-coordinator`; set
   `ONLYMACS_COORDINATOR_REPO` if it lives elsewhere.
4. `integrations`
   Thin user-facing command surfaces for Codex and Claude Code. These should stay light; policy belongs in the app or bridge.

Keep Bash as compatibility launchers and smoke-test harnesses. Durable routing policy, security decisions, and long-lived orchestration belong in the Go bridge or Swift app, with shell code only adapting agent and terminal surfaces.

## macOS app structure

The macOS app is a Swift package with two targets:

- `OnlyMacsCore`
- `OnlyMacsApp`

After the refactor, the main app target is split by ownership:

- `OnlyMacsApp.swift`
  `BridgeStore` state, high-level presentation, and user-facing command entry points
- `BridgeStore+RuntimeOperations.swift`
  runtime, networking, bootstrap, refresh, and persistence operations
- `BridgeStore+ModelSetup.swift`
  model library, installer recommendation, and starter-model setup presentation logic
- `OnlyMacsShell.swift`
  app delegate, window identity, activation policy, and app-shell helpers
- `OnlyMacsPopupViews.swift`
  popup-first menu bar shell composition
- `OnlyMacsShellViews.swift`
  advanced/settings surfaces, automation windows, and file-approval window composition
- `OnlyMacsModelPanels.swift`
  model/setup-specific reusable panels
- `OnlyMacsSurfaceViews.swift`
  reusable non-model UI panels and detailed surfaces
- `OnlyMacsBridgeModels.swift`
  decoded bridge/coordinator-facing transport and presentation models
- `OnlyMacsFileAccess*.swift`
  trusted file export models, approvals, and bundle-building logic

Rule of thumb:

- state ownership and effects in `BridgeStore`
- window/app lifecycle in `OnlyMacsShell.swift`
- top-level app surfaces in `OnlyMacsShellViews.swift`
- reusable view pieces in `OnlyMacsSurfaceViews.swift`

## Local bridge structure

Key files under `apps/local-bridge/internal/httpapi`:

- `router.go`
  HTTP surface and route wiring
- `request_policy.go`
  semantic request classification and route/policy decisions
- `inference_chat.go`
  chat/inference path orchestration
- `swarm.go`
  swarm lifecycle, scheduling-facing admin logic, and queue state
- `provider_relay.go`
  remote relay execution
- `swarm_execution.go`
  swarm execution helpers
- `onlymacs_artifact.go`
  staged artifact/workspace support
- `onlymacs_tool_exec.go`
  tool-execution-related bridge helpers

## Coordinator repo boundary

The coordinator source is intentionally kept outside this client repo:

- `cmd/coordinator/main.go`
- `internal/httpapi/router.go`
- `internal/httpapi/registry.go`
- `internal/httpapi/types.go`

It handles membership, shared-capacity registration, reservations, and relay coordination. It should not absorb app-shell policy that belongs in the bridge.

## Integrations and skills

The branded user surface is `/onlymacs`.

Under the repo you will still see tool-specific wrappers such as:

- `integrations/codex/onlymacs-shell.sh`
- `integrations/claude/onlymacs-claude.sh`
- `integrations/common/onlymacs-cli.sh`

Treat those as packaging and compatibility layers. The intended product mental model is one branded OnlyMacs command surface.

## Build and validation map

Common starting points:

- `make test`
- `make macos-app-public`
- `make app-bundle-smoke`
- `swift test --package-path apps/onlymacs-macos`
- `cd apps/local-bridge && go test ./...`
- `make coordinator-test`
- `bash integrations/common/test-onlymacs-cli-intents.sh`

Use the smallest meaningful validation for the subsystem you changed.

## Contributor traps

- The repo contains product docs, contributor docs, and implementation code side by side. Do not treat every document as active engineering source-of-truth.
- `OnlyMacsApp.swift` is still large because `BridgeStore` owns a wide surface area. Refactor by carving out clear boundaries, not by moving random helpers around.
- The launcher wrappers should not become policy brains.
- File-aware trusted swarm work is security-sensitive. Prefer explicit approval and fail-closed behavior.

## Good next refactors

- continue shrinking `BridgeStore` by extracting stable services, not by creating thin forwarding types
- split large bridge files by execution/policy boundary
- keep docs in sync whenever contributor flow or trust guarantees change
