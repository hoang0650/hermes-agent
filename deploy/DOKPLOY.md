# Hermes on AI Markets (Dokploy)

Parallel to OpenClaw: per-user host `{userId}.hermes.aimarkets.vn` → Hermes web dashboard.

## Why the first Dokploy deploy often Errors

The root `Dockerfile` is a **heavy** multi-stage build (compile SQLite, Playwright, `web` + `ui-tui` npm builds). On a normal VPS it commonly fails with:

- build timeout / OOM killed
- network blips downloading SQLite / s6 / Playwright browsers

**Do not build from source on Dokploy.** Pull the published image instead.

## Recommended Dokploy setup

1. Application type: **Docker Compose**
2. Compose file: `deploy/docker-compose.dokploy.yml`
3. Repo: `hoang0650/hermes-agent` branch `main` (or mount the compose only)
4. Environment (Dokploy → Environment):

```env
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<strong-password>
```

5. Exposed port: **9119**
6. Domain (Dokploy UI) optional: `hermes.aimarkets.vn` → `9119`

Without `HERMES_DASHBOARD_BASIC_AUTH_*`, `dashboard --host 0.0.0.0` **exits immediately** (auth gate fail-closed).

## DNS (Mắt Bão)

| Host | Type | Value |
|------|------|-------|
| `hermes` | A | `72.62.72.165` |
| `*.hermes` | A | `72.62.72.165` |

## Traefik File System

Paste `deploy/dokploy-dynamic-hermes-aimarkets-wildcard.yml` as `dynamic/hermes-aimarkets-wildcard.yml`.

Update the service URL to match the running container on the Dokploy Docker network, e.g.:

```yaml
servers:
  - url: "http://hermes-hermes-dashboard-1:9119"
# or whatever `docker ps` / Dokploy shows for the compose service
```

## Conventions

| Piece | Value |
|--------|--------|
| Public URL | `https://{userId}.hermes.aimarkets.vn` |
| Session | `market-{userId}` |
| Audience | `aimarkets` |
| Marketplace API | `POST /v1/hermes/launch`, SSH `/v1/hermes/ssh/*`, usage `/v1/hermes/usage` |

OpenClaw stays on `*.openclaw.aimarkets.vn` — do not route Hermes to the OpenClaw Control UI service.

## After fix

Redeploy → open `https://hermes.aimarkets.vn` → login with basic-auth user/password → then test marketplace **Launch Hermes**.
