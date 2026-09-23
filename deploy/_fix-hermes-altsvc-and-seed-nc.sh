#!/usr/bin/env bash
set -euo pipefail

# 1) Clear Alt-Svc for all Aimarkets hosts (kill cached H3 in Edge/Chrome)
MID=/etc/dokploy/traefik/dynamic/middlewares.yml
python3 - <<'PY'
from pathlib import Path
p = Path("/etc/dokploy/traefik/dynamic/middlewares.yml")
text = p.read_text() if p.exists() else "http:\n  middlewares: {}\n"
if "alt-svc-clear" not in text:
    if "middlewares:" not in text:
        text = "http:\n  middlewares: {}\n"
    # inject after middlewares:
    inject = """
    alt-svc-clear:
      headers:
        customResponseHeaders:
          Alt-Svc: "clear"
"""
    text = text.replace("  middlewares:", "  middlewares:" + inject, 1)
    p.write_text(text)
    print("added alt-svc-clear middleware")
else:
    print("alt-svc-clear already present")
print(p.read_text())
PY

# Attach middleware to hermes/openclaw/nanoclaw https routers in user-certs + wildcards
python3 - <<'PY'
from pathlib import Path
files = [
  Path("/etc/dokploy/traefik/dynamic/aimarkets-user-certs.yml"),
  Path("/etc/dokploy/traefik/dynamic/hermes-aimarkets-wildcard.yml"),
  Path("/etc/dokploy/traefik/dynamic/nanoclaw-aimarkets-wildcard.yml"),
  Path("/etc/dokploy/traefik/dynamic/openclaw-wildcard.yml"),
]
for f in files:
    if not f.exists():
        continue
    text = f.read_text()
    # For every https router block under entryPoints websecure, ensure middleware
    # Simple approach: if middlewares missing on https routers, add alt-svc-clear
    lines = text.splitlines(True)
    out = []
    i = 0
    while i < len(lines):
        out.append(lines[i])
        if "entryPoints: [websecure]" in lines[i] or (
            lines[i].strip() == "- websecure" and i > 0 and "entryPoints:" in lines[i-1]
        ):
            # look ahead for middlewares / service within next 8 lines
            window = "".join(lines[i:i+10])
            if "alt-svc-clear" not in window and "middlewares:" not in window:
                # insert after this entryPoints line
                indent = "      "
                out.append(f"{indent}middlewares: [alt-svc-clear]\n")
            elif "middlewares:" in window and "alt-svc-clear" not in window:
                # patch existing middlewares line in upcoming lines
                pass
        i += 1
    new = "".join(out)
    # Also patch middlewares: [redirect...] style and middlewares:\n - x
    import re
    def add_mw(m):
        block = m.group(0)
        if "alt-svc-clear" in block:
            return block
        if "middlewares: [" in block:
            return block.replace("middlewares: [", "middlewares: [alt-svc-clear, ", 1)
        if "middlewares:" in block and "- " in block:
            return block.replace("middlewares:\n", "middlewares:\n        - alt-svc-clear\n", 1)
        return block
    # For https routers only — rough: any tls: section's preceding middlewares
    new2 = re.sub(
        r"(middlewares:\s*\[[^\]]*\])",
        lambda m: m.group(1) if "alt-svc-clear" in m.group(1) else m.group(1).replace("middlewares: [", "middlewares: [alt-svc-clear, ", 1),
        new,
    )
    f.write_text(new2)
    print("patched", f)
PY

# 2) Stop UDP 443 publish if possible (Traefik service)
TR=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1)
echo TRAEFIK=$TR
# Find swarm service
TSVC=$(docker service ls --format '{{.Name}}' | grep -i traefik | head -1 || true)
echo TSVC=$TSVC
if [[ -n "$TSVC" ]]; then
  docker service inspect "$TSVC" --format '{{json .Endpoint.Ports}}' || true
fi
# Kill host UDP listeners via iptables drop as soft fix (optional) — prefer docker publish remove
# Restart traefik container to reload file provider
docker restart "$TR"
sleep 8

# 3) Seed NanoClaw empty snapshot
NC_SECRET=$(docker service inspect aimarketplace-nanoclaw-hsnvyh \
  --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
  | sed -n 's/^DASHBOARD_SECRET=//p' | head -1)
SNAP='{"timestamp":"2026-09-21T16:30:00.000Z","assistant_name":"NanoClaw","uptime":0,"agent_groups":[],"sessions":[],"channels":[],"users":[],"tokens":{"totals":{"inputTokens":0,"outputTokens":0,"cacheReadTokens":0,"cacheCreationTokens":0},"byModel":{},"byGroup":{}},"context_windows":[],"activity":[],"messages":[]}'
docker run --rm --network dokploy-network curlimages/curl:8.5.0 \
  -sS -m 15 -w 'ingest:%{http_code}\n' \
  -H "Authorization: Bearer ${NC_SECRET}" -H 'Content-Type: application/json' \
  -d "$SNAP" http://aimarketplace-nanoclaw-hsnvyh:3100/api/ingest
docker run --rm --network dokploy-network curlimages/curl:8.5.0 \
  -sS -m 15 -w '\noverview:%{http_code}\n' \
  -H "Authorization: Bearer ${NC_SECRET}" \
  http://aimarketplace-nanoclaw-hsnvyh:3100/api/overview | head -c 500
echo

# 4) Verify headers no longer advertise h3; cert LE
curl -sSI https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login | head -20 || true
echo | openssl s_client -connect 127.0.0.1:443 -servername 6a69f224e6032a3f00de977f.hermes.aimarkets.vn 2>/dev/null \
  | openssl x509 -noout -subject -issuer
ss -ulnp | grep ':443' || echo 'no udp 443'
echo DONE
