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

Dokploy → **hermes** → Advanced → **Run Command** (screenshot hiện `/bin/sh` = sai, container không chạy dashboard):

| Field | Value |
|-------|--------|
| Command | `dashboard` |
| Args (Add Argument ×4) | `--host` → `0.0.0.0` → `--port` → `9119` → `--no-open` |

Không để Command = `/bin/sh` và không để trống Args.

Environment:

```env
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<strong-password>
```

Advanced → **Ports** → Add Port:

| | |
|--|--|
| Published / container | `9119` |
| Protocol | `tcp` (hoặc HTTPS domain trong Domains tab) |

**Không** dựa vào Advanced → Traefik của app này cho `{userId}.hermes…` — dùng **Traefik File System** (sidebar) + file `hermes-aimarkets-wildcard.yml` (upstream `http://aimarketplace-hermes-nxdss5:9119`).

Save → **Redeploy**.

### Alternate (s6-supervised dashboard)

```text
Command: sleep infinity
Env: HERMES_DASHBOARD=1
     HERMES_DASHBOARD_HOST=0.0.0.0
     HERMES_DASHBOARD_PORT=9119
     HERMES_DASHBOARD_BASIC_AUTH_USERNAME=…
     HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=…
```

## Usage billing (wallet debit — same as OpenClaw)

| | OpenClaw | Hermes |
|---|---|---|
| Check | `GET /v1/openclaw/usage/check` | `GET /v1/hermes/usage/check` |
| Charge | `POST /v1/openclaw/usage` | `POST /v1/hermes/usage` |
| Plugin | `extensions/aimarkets-usage` | `plugins/aimarkets_usage` |
| Markup | provider COGS × 1.25 | same (`OPENCLAW_AIMARKETS_MARKUP` / `HERMES_AIMARKETS_MARKUP`) |
| Auth | `X-Service-Secret: AIMARKETS_SERVICE_SECRET` | same |
| Buyer id | `market-{userId}` session | Hermes profile `market-{userId}` |

Hermes Dokploy env (required for billing):

```env
HERMES_AIMARKETS_API_URL=https://api.aimarkets.vn
AIMARKETS_SERVICE_SECRET=<same as marketplace-api and OpenClaw>
# optional override of default 0.25:
# HERMES_AIMARKETS_MARKUP=0.25
```

The bundled ``aimarkets_usage`` backend plugin auto-loads when those env vars
are set. Each LLM API call reports tokens; API creates a wallet ``debit`` with
``meta.channel=hermes``.

## Inference API keys (OpenRouter / OpenAI / …)

Hermes reads provider keys from **profile** ``.env`` under ``HERMES_HOME``
(``OPENROUTER_API_KEY`` is **not** treated as a process-global secret).
Aimarkets buyers run as profile ``market-{userId}``, so:

1. Set keys in Dokploy → Application → **Environment** (compose passes them into the container).
2. On buyer login the ``aimarkets`` auth plugin **mirrors** those keys into
   ``/opt/data/profiles/market-{userId}/.env`` (and seeds ``model.provider``).

Dokploy Environment (example — pick the provider you use):

```env
# Required for dashboard to stay up
HERMES_DASHBOARD=1
HERMES_DASHBOARD_HOST=0.0.0.0
HERMES_DASHBOARD_PORT=9119
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<ops-only>

# Multi-buyer auth
HERMES_AIMARKETS_API_URL=https://api.aimarkets.vn
AIMARKETS_SERVICE_SECRET=<same as marketplace-api>

# Inference — at least ONE of these
OPENROUTER_API_KEY=sk-or-v1-...
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# FEATHERLESS_API_KEY=...
```

**Command** must stay ``sleep infinity`` (empty Command → interactive hermes exits → Traefik 502).

After adding keys: **Redeploy** (or `docker service update --env-add OPENROUTER_API_KEY=…`), then Launch again so the plugin re-mirrors into the buyer profile.

Optional one-shot seed into root ``/opt/data/.env`` (survives profile create before first login):

```bash
docker exec -u hermes $(docker ps -qf name=aimarketplace-hermes) \
  sh -c 'grep -q OPENROUTER_API_KEY /opt/data/.env 2>/dev/null || echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> /opt/data/.env'
```

## Multi-buyer isolation (AI Markets)

Shared `HERMES_DASHBOARD_BASIC_AUTH_*` is **operator-only**. Buyers get unique
accounts (`HermesAccount` in marketplace API) via Launch.

Hermes Dokploy env (in addition to dashboard Command):

```env
HERMES_AIMARKETS_API_URL=https://api.aimarkets.vn
AIMARKETS_SERVICE_SECRET=<same as marketplace-api>
HERMES_AIMARKETS_AUTH_SECRET=<32+ random bytes, base64>
# Keep admin basic auth for operators — different password, never share with buyers:
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<ops-only>
```

Enable the `aimarkets` dashboard-auth plugin (bundled under
`plugins/dashboard_auth/aimarkets`). On login, session locks to Hermes profile
`market-{userId}` so buyer A cannot open buyer B’s chats/files.

## DNS (Mắt Bão)

| Host | Type | Value |
|------|------|-------|
| `hermes` | A | `72.62.72.165` |
| `*.hermes` | A | `72.62.72.165` |

## Traefik File System

Paste `deploy/dokploy-dynamic-hermes-aimarkets-wildcard.yml` as `dynamic/hermes-aimarkets-wildcard.yml`.

File **must** include `services.hermes-aimarkets-svc` → `http://aimarketplace-hermes-nxdss5:9119` (or real container name). Missing `services:` → Traefik **404**.

TLS = same as denglish `ai.aimarkets.vn`: apex uses `Host()` + `domains.main`; each buyer needs exact Host in `dynamic/aimarkets-user-certs.yml` (HTTP-01). `HostRegexp` alone → **DEFAULT CERT**.

```bash
python3 openclaw/deploy/_apply-aimarkets-user-certs.py <userId>
```

### 404 + “Không bảo mật”

| Symptom | Cause | Fix |
|---------|--------|-----|
| Plain `404 page not found` | No router / no service / wrong Host | Re-paste yml with `services:`; confirm DNS `*.hermes` A → VPS |
| Red “Không bảo mật” | No LE for `{userId}.hermes…` | Add exact `Host()` in `aimarkets-user-certs.yml` (like `ai.aimarkets.vn`) |
| Connection refused / blank | Dashboard not running | Command `dashboard --host 0.0.0.0 --port 9119 --no-open` + basic-auth env |

```bash
# On VPS
docker ps --format "{{.Names}}" | grep -i hermes
curl -sI http://127.0.0.1:9119/api/status
ls /etc/dokploy/traefik/dynamic/
# Confirm hermes-aimarkets-wildcard.yml has both routers AND services
```

## Conventions

| Piece | Value |
|--------|--------|
| Public URL | `https://{userId}.hermes.aimarkets.vn` |
| Session | `market-{userId}` |
| Audience | `aimarkets` |
| Marketplace API | `POST /v1/hermes/launch` |

OpenClaw stays on `*.openclaw.aimarkets.vn`.
