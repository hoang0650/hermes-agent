#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID status=$(docker inspect -f '{{.State.Status}}' "$CID")"
for i in $(seq 1 15); do
  if docker exec "$CID" python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=3)' 2>/dev/null; then
    echo "up try=$i"
    break
  fi
  sleep 2
done
docker exec "$CID" python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=8).status)'
docker logs "$CID" --since 3m 2>&1 | grep -iE 'aimarkets-usage|aimarkets_usage' | tail -15 || echo no_log_yet
# Does discovery see the plugin?
docker exec "$CID" python3 - <<'PY'
from pathlib import Path
p = Path("/opt/hermes/plugins/aimarkets_usage/plugin.yaml")
print("plugin.yaml exists", p.is_file(), "size", p.stat().st_size if p.is_file() else 0)
PY
echo DONE
