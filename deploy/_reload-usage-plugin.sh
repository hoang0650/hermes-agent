#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "=== dashboard procs ==="
docker exec "$CID" sh -c 'ps aux | grep "hermes dashboard" | grep -v grep'
echo "=== discover plugin via python ==="
docker exec "$CID" python3 - <<'PY'
import sys
sys.path.insert(0, "/opt/hermes")
from pathlib import Path
# Force import register path
from hermes_cli.plugins import PluginManager
# Minimal: list manifests under plugins/
root = Path("/opt/hermes/plugins")
for y in sorted(root.rglob("plugin.yaml")):
    if "aimarkets" in str(y):
        print("found", y)
PY
# Hard restart dashboard
PID=$(docker exec "$CID" sh -c 'pgrep -f "hermes dashboard" | head -1' || true)
echo "old_pid=$PID"
if [[ -n "$PID" ]]; then
  docker exec "$CID" kill "$PID"
fi
sleep 10
docker exec "$CID" sh -c 'ps aux | grep "hermes dashboard" | grep -v grep | head -2'
docker logs "$CID" --since 1m 2>&1 | grep -iE 'aimarkets-usage|aimarkets_usage|Loaded plugin|aimarkets' | tail -30
echo DONE
