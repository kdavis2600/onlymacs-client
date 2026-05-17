# OnlyMacs Reviewer Guide

This guide is for technical reviewers who want to understand the public client without reading the whole repository first.

## What This Repo Is

This repository contains the installable client surface:

- `apps/onlymacs-macos`: Swift macOS menu bar app, setup flow, file approval, launcher install, support bundles, and update UI.
- `apps/local-bridge`: Go localhost bridge on `127.0.0.1:4318`; this is the local control plane for request policy, local API compatibility, model discovery, and swarm session handoff.
- `apps/onlymacs-web`: public website and docs source.
- `integrations`: thin compatibility launchers for Codex, Claude Code, and terminal use.
- `scripts`: packaging, QA, release, and public-export helpers.
- `docs`: architecture, trust model, QA, and operations notes.

The hosted coordinator implementation is intentionally outside this public client repo. The client talks to that service at the product boundary, but contributors should be able to build and test the public client without a coordinator checkout.

## Architecture Expectations

Durable product policy should live in Swift or Go:

- Swift owns user-facing state, setup, privacy surfaces, and file-approval UX.
- Go owns localhost API behavior, request validation, bridge security, and coordinator/client transport.
- Bash under `integrations` is compatibility glue for existing agent and terminal workflows. It can coordinate smoke tests and legacy launcher behavior, but it should not become the long-term home for app security or hosted-service policy.

Historical content-pipeline validators are opt-in under `integrations/content-pipeline`. They are kept for regression coverage of old large-batch QA runs and are not sourced by the default launcher path.

## First Commands

From a fresh clone:

```bash
make test-public
```

That runs the self-contained public client checks: Swift tests, Go bridge tests, shell syntax and contracts, reporting contracts, web lint, and web build.
It also installs web dependencies with `npm ci` when the web `node_modules` directory is absent.

For targeted slices:

```bash
swift test --package-path apps/onlymacs-macos
cd apps/local-bridge && go test ./...
cd apps/onlymacs-web && npm run lint && npm run build
bash integrations/common/test-onlymacs-cli-intents.sh
```

## Public Export Check

Do not make the private working repository public with its full history. Create a fresh public export:

```bash
make public-export
```

The export is written to `.tmp/onlymacs-public-client-export` as a one-commit Git repo, then runs `scripts/preflight-public-client.sh` without a history override. That preflight checks for tracked env files, signing/package artifacts, private coordinator paths, local machine paths, token-looking strings, and old private-service history.

Inside the export, a reviewer can run:

```bash
make test-public
```

## What To Inspect First

For product behavior:

- `apps/onlymacs-macos/Sources/OnlyMacsApp`
- `apps/local-bridge/internal/httpapi`
- `docs/architecture-overview.md`
- `docs/fileshare-strategy.md`

For public-release hygiene:

- `scripts/preflight-public-client.sh`
- `scripts/export-public-client.sh`
- `docs/open-source-readiness-plan.md`
- `.gitignore`

For integration behavior:

- `integrations/README.md`
- `integrations/common/onlymacs-cli.sh`
- `integrations/common/onlymacs-cli-orchestration.sh`

When reviewing `integrations/common/onlymacs-cli-orchestration.sh`, treat it as launcher compatibility code. It exists to preserve command behavior across agent surfaces while the app and bridge remain the authoritative product layers.
