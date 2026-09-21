#!/bin/bash
set -euo pipefail
docker ps --filter name=aimarketplace-hermes --format '{{.Names}} {{.Status}}'
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
# Ensure dashboard is running (pkill may have left it down briefly)
if ! docker exec "$CID" python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",9119),2); s.close()' 2>/dev/null; then
  echo "dashboard down — waiting for s6 respawn..."
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 2
    if docker exec "$CID" python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",9119),2); s.close()' 2>/dev/null; then
      echo "up after ${i}"
      break
    fi
  done
fi
docker exec "$CID" python3 -c 'import urllib.request; print("status", urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=10).status)'
docker exec "$CID" grep -n '"default", locked' /opt/hermes/hermes_cli/dashboard_auth/middleware.py | head -1
docker exec "$CID" grep -c _mirror_inference_credentials /opt/hermes/plugins/dashboard_auth/aimarkets/__init__.py
docker exec "$CID" sh -c 'ps aux | grep "hermes dashboard" | grep -v grep | head -2' || echo 'no dashboard proc'
echo DONE
