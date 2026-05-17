# Contributing to OnlyMacs

OnlyMacs is still moving quickly, but changes should remain easy to review and safe to validate.

## Before you start

1. Read [README.md](README.md) for product context.
2. Read [docs/docs-guide.md](docs/docs-guide.md) for the contributor map.
3. Prefer small, behavior-preserving changes over broad rewrites.
4. Do not bundle refactors, product changes, and release chores into one diff.

## Local setup

Common entry points:

- `make bootstrap`
- `make test`
- `make test-public`
- `make web-check`
- `make macos-app-public`
- `make app-bundle-smoke`

Target-specific validation is usually better than rerunning the whole repo blindly:

- macOS app: `swift test --package-path apps/onlymacs-macos`
- local bridge: `cd apps/local-bridge && go test ./...`
- website/docs: `cd apps/onlymacs-web && npm run lint && npm run build`
- launcher CLI smoke: `bash integrations/common/test-onlymacs-cli-intents.sh`
- remote-work contract: `bash scripts/qa/onlymacs-remote-work-contract-matrix.sh`

Some maintainer-only tests target the hosted coordination service. They are not part of public client validation.

Public-release preflight:

- `ONLYMACS_ALLOW_PRIVATE_HISTORY=1 make public-preflight` in this private working repo
- `make public-export` to create and verify a fresh local one-commit export

The preflight is intentionally stricter than normal CI. It should pass without overrides in the final public export and may fail in private development history until the export is created from a fresh or filtered tree.

## Repo conventions

- Keep product behavior stable unless the change explicitly intends to alter it.
- Prefer extracting by ownership boundary instead of adding new abstractions everywhere.
- Keep `BridgeStore` as the state/effects owner for the macOS app unless you are intentionally carving out a new stable boundary.
- Treat `integrations/` as thin entrypoints. Policy belongs in the app or bridge, not in brand-specific wrappers.
- Add or update docs when you change architecture, setup steps, or operator expectations.

## Testing expectations

- Run the smallest credible validation for the boundary you touched.
- If a change crosses app + bridge boundaries, test both.
- If tests are missing, say so directly in your summary and add the smallest useful coverage you can.
- Do not change tests to normalize a behavior change unless behavior change is the point of the work.

## Security and local data

- Do not commit tokens, private keys, personal credentials, or machine-specific secrets.
- Keep local-only paths, Apple signing details, and maintainer-specific setup out of committed defaults when possible.
- Do not commit `.env*` files except reviewed examples. Never commit App Store Connect keys, Developer ID certificates, Sparkle private keys, notarization profiles, packaged DMGs/PKGs, or generated app archives.
- Read [SECURITY.md](SECURITY.md) before changing file export, trusted swarm, launcher, or network boundaries.

## Pull request shape

Good changes usually include:

- a short problem statement
- the structural improvement
- the validation run
- any follow-up work intentionally left separate

Use the PR template in `.github/pull_request_template.md`.
