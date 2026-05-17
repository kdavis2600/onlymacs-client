# Security Policy

OnlyMacs handles local prompts, swarm routing, launcher installation, and optional file export. Security-sensitive changes should be treated as release blockers.

## Supported code

Security fixes should target the current `main` branch unless a release branch explicitly exists.

## Reporting a vulnerability

- Do not open a public issue for credential leaks, file export bypasses, authentication problems, or code-execution bugs.
- If the repository host supports private vulnerability reporting, use that path.
- Otherwise, open a minimal public issue asking for a security contact without including exploit details, secrets, private logs, or affected file contents.

When reporting, include:

- affected component (`apps/onlymacs-macos`, `apps/local-bridge`, coordinator service, website/docs, packaging, or `integrations`)
- reproduction steps
- impact
- whether local files, prompts, or trusted swarm traffic are involved

## Areas that deserve extra scrutiny

- trusted file export and approval flows
- launcher-to-app handoff
- localhost bridge admin and chat routes
- coordinator invite, join, and reservation paths
- runtime/tool execution over staged workspaces
- support bundle export and redaction
- anything that changes route scope defaults or secrecy guarantees

## Hard rules for contributors

- Never commit secrets, signing identities, or private endpoints that are not already intended as public defaults.
- Never commit `.env*` files except reviewed examples. Never commit Apple Developer certificates, App Store Connect API keys, notarization profiles, Sparkle private keys, DMGs, PKGs, or `.xcarchive` bundles.
- Keep developer credentials in the macOS keychain, ignored local env files, or a private release environment outside the public client repo.
- Prefer explicit denylists and approval gates over silent best-effort handling for local file access.
- If a path cannot safely uphold a privacy/security claim, fail closed and document the gap.
