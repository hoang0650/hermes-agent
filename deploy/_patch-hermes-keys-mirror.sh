#!/bin/bash
# Patch running Hermes with profile=default allow + inference key mirror.
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
test -n "$CID"

if [[ -f /tmp/hermes-autofill/middleware.py ]]; then
  docker cp /tmp/hermes-autofill/middleware.py "$CID:/opt/hermes/hermes_cli/dashboard_auth/middleware.py"
fi
if [[ -f /tmp/hermes-autofill/aimarkets/__init__.py ]]; then
  docker exec "$CID" mkdir -p /opt/hermes/plugins/dashboard_auth/aimarkets
  docker cp /tmp/hermes-autofill/aimarkets/__init__.py "$CID:/opt/hermes/plugins/dashboard_auth/aimarkets/__init__.py"
  docker cp /tmp/hermes-autofill/aimarkets/plugin.yaml "$CID:/opt/hermes/plugins/dashboard_auth/aimarkets/plugin.yaml"
fi

# Soft-restart dashboard so Python reloads plugins (keep sleep infinity CMD).
SVC_DIR=$(docker exec "$CID" sh -c 'ls -d /run/s6/services/dashboard /var/run/s6/services/dashboard 2>/dev/null | head -1' || true)
if [[ -n "${SVC_DIR:-}" ]]; then
  docker exec "$CID" s6-svc -r "$SVC_DIR"
  echo "restarted $SVC_DIR"
  sleep 5
fi

echo "=== keys in process? ==="
docker exec "$CID" sh -c 'echo OPENROUTER=${OPENROUTER_API_KEY:+SET}; echo OPENAI=${OPENAI_API_KEY:+SET}'

echo "=== root .env API lines ==="
docker exec "$CID" sh -c 'grep -E "API_KEY" /opt/data/.env 2>/dev/null | sed "s/=.*/=***/" || echo none'

echo "=== market profiles ==="
docker exec "$CID" sh -c 'ls /opt/data/profiles 2>/dev/null'

echo "=== note ==="
echo "If OPENROUTER is unset: add OPENROUTER_API_KEY in Dokploy Environment, Redeploy,"
echo "then buyer Launch again (plugin mirrors into profiles/market-*/.env)."
echo DONE
