# Protocol Source

This directory holds machine-oriented protocol assets:

- JSON schemas under `proto/schemas/`
- future generated code under `proto/generated/`

Sprint 1 currently includes:

- envelope/auth handshake placeholders for the later websocket flow
- mock provider registration for local development
- exact-model preflight request/response schemas for bridge and coordinator admin APIs
- session reservation/release schemas for dynamic slot accounting
- early swarm and bridge-runtime schemas for the single-app development flow
- the local proof-of-concept chat path now uses the same OpenAI-compatible request shape when proxying into Ollama
