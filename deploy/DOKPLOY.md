# Hermes on AI Markets (Dokploy)

Parallel to OpenClaw: per-user host `{userId}.hermes.aimarkets.vn` → Hermes web dashboard.

## DNS (Mắt Bão)

| Host | Type | Value |
|------|------|-------|
| `hermes` | A | `72.62.72.165` |
| `*.hermes` | A | `72.62.72.165` |

## Traefik

Paste `deploy/dokploy-dynamic-hermes-aimarkets-wildcard.yml` into Dokploy Traefik File System as `dynamic/hermes-aimarkets-wildcard.yml`.

Update `hermes-wildcard-svc` URL to your Hermes dashboard container (default port **9119**).

## Conventions

| Piece | Value |
|--------|--------|
| Public URL | `https://{userId}.hermes.aimarkets.vn` |
| Session | `market-{userId}` |
| Audience | `aimarkets` |
| Marketplace API | `POST /v1/hermes/launch`, SSH `/v1/hermes/ssh/*`, usage `/v1/hermes/usage` |

OpenClaw stays on `*.openclaw.aimarkets.vn` — do not route Hermes to the OpenClaw Control UI service.
