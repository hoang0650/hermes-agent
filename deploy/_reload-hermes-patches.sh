#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
# Re-copy latest from /tmp if present
if [[ -f /tmp/hermes-autofill/middleware.py ]]; then
  docker cp /tmp/hermes-autofill/middleware.py "$CID:/opt/hermes/hermes_cli/dashboard_auth/middleware.py"
fi
if [[ -f /tmp/hermes-autofill/aimarkets/__init__.py ]]; then
  docker cp /tmp/hermes-autofill/aimarkets/__init__.py "$CID:/opt/hermes/plugins/dashboard_auth/aimarkets/__init__.py"
fi

echo "=== markers on disk ==="
docker exec "$CID" grep -n 'default", locked\|"default", locked' /opt/hermes/hermes_cli/dashboard_auth/middleware.py | head -3 || echo 'middleware: default allow MISSING'
docker exec "$CID" grep -n '_mirror_inference_credentials' /opt/hermes/plugins/dashboard_auth/aimarkets/__init__.py | head -3 || echo 'plugin: mirror MISSING'

# Find dashboard PID and HUP/kill so s6 respawns with new code
docker exec "$CID" sh -c 'ps aux' | grep -iE 'hermes|uvicorn|gunicorn|9119|dashboard' | grep -v grep | head -20 || true

# Prefer s6-svc
for d in /run/s6-rc/servicedirs/dashboard /run/s6/services/dashboard /var/run/s6/services/dashboard /run/service/dashboard; do
  if docker exec "$CID" test -d "$d" 2>/dev/null; then
    docker exec "$CID" s6-svc -r "$d" && echo "s6-svc -r $d" && break
  fi
done

# Fallback: send TERM to process listening on 9119
docker exec "$CID" sh -c 'fuser -k 9119/tcp 2>/dev/null || true'
sleep 6

docker exec "$CID" python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=8).read()[:120])'
echo "OPENROUTER process=${OPENROUTER:+}" 
docker exec "$CID" sh -c 'echo OPENROUTER_in_container=${OPENROUTER_API_KEY:+SET}'
echo DONE
