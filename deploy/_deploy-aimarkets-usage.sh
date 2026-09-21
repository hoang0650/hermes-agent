#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
SRC=/tmp/hermes-autofill/aimarkets_usage
docker exec "$CID" mkdir -p /opt/hermes/plugins/aimarkets_usage
docker cp "$SRC/__init__.py" "$CID:/opt/hermes/plugins/aimarkets_usage/__init__.py"
docker cp "$SRC/plugin.yaml" "$CID:/opt/hermes/plugins/aimarkets_usage/plugin.yaml"
docker exec "$CID" ls -la /opt/hermes/plugins/aimarkets_usage
docker exec "$CID" sh -c 'echo API=${HERMES_AIMARKETS_API_URL:+set}; echo SECRET=${AIMARKETS_SERVICE_SECRET:+set}'
# Soft kill dashboard only inside container; don't kill this shell
docker exec "$CID" sh -c 'kill $(pgrep -f "hermes dashboard" | head -1) 2>/dev/null || true'
echo "signalled dashboard"
echo DONE
