# Hermes on AI Markets (Dokploy)

Parallel to OpenClaw: per-user host `{userId}.hermes.aimarkets.vn` → Hermes web dashboard.

## Log you just hit

```
Welcome to Hermes Agent!
Warning: Input is not a terminal (fd=0).
Shutting down… (finalizing session)
s6-rc: … dashboard successfully stopped
```

**Cause:** Dokploy ran the default interactive `hermes` CLI (no TTY). That process exits → s6 stops the whole container (including dashboard).

**Fix:** set the container **Command** to dashboard (not empty / not bare `hermes`):

```text
dashboard --host 0.0.0.0 --port 9119 --no-open
```

And set env:

```env
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<strong-password>
```

Without basic-auth env, `dashboard --host 0.0.0.0` also exits immediately (auth gate).

## Recommended Dokploy setup

1. Application type: **Docker Compose**
2. Compose file: `deploy/docker-compose.dokploy.yml`
3. Prefer image `nousresearch/hermes-agent:latest` (do **not** build the heavy root `Dockerfile` on the VPS)
4. Env as above
5. Port **9119**

### If you keep “Dockerfile” provider instead of Compose

Dokploy → General → **Command**:

```text
dashboard --host 0.0.0.0 --port 9119 --no-open
```

Same basic-auth env vars. Redeploy.

### Alternate (s6-supervised dashboard)

```text
Command: sleep infinity
Env: HERMES_DASHBOARD=1
     HERMES_DASHBOARD_HOST=0.0.0.0
     HERMES_DASHBOARD_PORT=9119
     HERMES_DASHBOARD_BASIC_AUTH_USERNAME=…
     HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=…
```

## DNS (Mắt Bão)

| Host | Type | Value |
|------|------|-------|
| `hermes` | A | `72.62.72.165` |
| `*.hermes` | A | `72.62.72.165` |

## Traefik File System

Paste `deploy/dokploy-dynamic-hermes-aimarkets-wildcard.yml` as `dynamic/hermes-aimarkets-wildcard.yml`.

Point the service URL at the real Dokploy container name on port **9119**.

## Conventions

| Piece | Value |
|--------|--------|
| Public URL | `https://{userId}.hermes.aimarkets.vn` |
| Session | `market-{userId}` |
| Audience | `aimarkets` |
| Marketplace API | `POST /v1/hermes/launch` |

OpenClaw stays on `*.openclaw.aimarkets.vn`.
