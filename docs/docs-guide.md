# Docs Guide

Start here if you are new to the repository.

## Core references

- [../README.md](../README.md): current-state technical summary of product behavior and `/onlymacs`
- [architecture-overview.md](architecture-overview.md): system map and contributor orientation
- [fileshare-strategy.md](fileshare-strategy.md): current-state technical behavior for targeted file sharing, approval, export, and private/public route differences
- [codex-learnings.md](codex-learnings.md): durable repo lessons and debugging shortcuts for future Codex sessions
- [troubleshooting.md](troubleshooting.md): solved setup, build, test, dependency, and environment failures
- [context-aware-adoption-plan.md](context-aware-adoption-plan.md): current mapping from the context-aware v2 design direction into OnlyMacs code, with phase 1-3 adoption status
- [archive/context-aware-v2-research.md](archive/context-aware-v2-research.md): archived research/design reference that informed the adoption plan
- [trusted-swarm-file-access-plan.md](trusted-swarm-file-access-plan.md): trusted file export roadmap and constraints
- [trusted-swarm-file-access-qa-checklist.md](trusted-swarm-file-access-qa-checklist.md): file-aware flow QA checklist
- [onlymacs-hardening-principles.md](onlymacs-hardening-principles.md): generalized rules for improving `/onlymacs` without one-off prompt hacks
- [onlymacs-ui-automation-playbook.md](onlymacs-ui-automation-playbook.md): automation tactics for driving the macOS app during contributor QA

## Protocol and wire behavior

- [protocol/README.md](protocol/README.md)
- [protocol/message-flow.md](protocol/message-flow.md)

## How to read the codebase

1. Start with [architecture-overview.md](architecture-overview.md).
2. Read `apps/onlymacs-macos/Package.swift` to understand the Swift package boundary.
3. Read `integrations/README.md` for launcher/skill intent.
4. Then move into the app, bridge, or coordinator component you actually need.
