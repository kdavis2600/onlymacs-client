# Current Message Flow

The repo now covers the first honest local-dev flow for exact-model discovery, local share publish, preflight, streamed remote relay, and hosted invite handoff:

1. the app or bridge creates a swarm over `POST /admin/v1/swarms/create`
2. the bridge creates and stores an invite token over `POST /admin/v1/swarms/invite`
3. when the app is targeting a hosted coordinator, the packaged invite link includes both `invite_token` and `coordinator_url` inside `onlymacs://join?...`
4. a second packaged app can open that link, switch itself to the hosted coordinator target, and then join the swarm through the bridge
5. the bridge joins a swarm over `POST /admin/v1/swarms/join`
6. the bridge discovers local Ollama models over `GET <ollama>/v1/models`
7. the bridge publishes `This Mac` into the active swarm over `POST /admin/v1/share/publish`
8. the coordinator stores provider capability state over `POST /admin/v1/providers/register`
9. the bridge selects or updates its runtime mode and active swarm over `POST /admin/v1/runtime`
10. integrations or local tooling ask the bridge for aggregated exact-model visibility over `GET /admin/v1/models`
11. integrations or local tooling ask the bridge to resolve availability over `POST /admin/v1/preflight`
12. the coordinator reserves one slot inside the active swarm over `POST /admin/v1/sessions/reserve`
13. if the reserved provider is `This Mac`, the bridge proxies an OpenAI-compatible chat completion directly to the local Ollama backend using the coordinator-resolved exact model
14. if the reserved provider is remote, the requester bridge enqueues a relay job through `POST /admin/v1/relay/execute`
15. the remote published bridge polls for work through `POST /admin/v1/providers/relay/poll`
16. the remote published bridge executes the request against its local inference backend and pushes stream chunks through `POST /admin/v1/providers/relay/chunk`
17. the remote published bridge finalizes the job through `POST /admin/v1/providers/relay/complete`
18. the requester bridge returns the relayed streamed payload to the local caller as it arrives
19. the coordinator releases the slot over `POST /admin/v1/sessions/release`

Still deferred to later milestones:

1. websocket-based requester/provider sessions
2. download-before-install landing path polish
3. stronger quality/savings/fairness routing policy on top of the streamed relay path
