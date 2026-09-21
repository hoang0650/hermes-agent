#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo CID=$CID
docker cp /tmp/debug_usage_plugin.py "$CID:/tmp/debug_usage_plugin.py"
docker exec "$CID" python3 /tmp/debug_usage_plugin.py
