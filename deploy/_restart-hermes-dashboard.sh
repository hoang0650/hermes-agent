#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
docker exec "$CID" sh -c 'pkill -f "hermes dashboard" || true'
sleep 8
echo "=== procs ==="
docker exec "$CID" sh -c 'ps aux | grep -E "hermes dashboard|tui_gateway" | grep -v grep | head -10' || true
echo "=== status ==="
docker exec "$CID" python3 -c 'import urllib.request; r=urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=10); print(r.status)'
echo "=== patch markers ==="
docker exec "$CID" grep -n '"default", locked' /opt/hermes/hermes_cli/dashboard_auth/middleware.py | head -1
docker exec "$CID" grep -c _mirror_inference_credentials /opt/hermes/plugins/dashboard_auth/aimarkets/__init__.py
echo DONE
