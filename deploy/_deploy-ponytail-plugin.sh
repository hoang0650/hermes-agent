#!/bin/bash
# Copy plugins/ponytail into the running Hermes container (same flow as
# _deploy-aimarkets-usage.sh). Upload first:
#   scp -r plugins/ponytail root@VPS:/tmp/hermes-autofill/ponytail
# Requires PONYTAIL_URL in the Hermes app env (Dokploy → Environment).
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
if [[ -z "$CID" ]]; then echo "NO_HERMES"; exit 1; fi
SRC=/tmp/hermes-autofill/ponytail
docker exec "$CID" mkdir -p /opt/hermes/plugins/ponytail
docker cp "$SRC/__init__.py" "$CID:/opt/hermes/plugins/ponytail/__init__.py"
docker cp "$SRC/plugin.yaml" "$CID:/opt/hermes/plugins/ponytail/plugin.yaml"
docker exec "$CID" sh -c 'echo PONYTAIL_URL=${PONYTAIL_URL:-unset} PONYTAIL_MODE=${PONYTAIL_MODE:-compact}'
docker exec "$CID" python3 -c 'import os, urllib.request; print(urllib.request.urlopen(os.environ["PONYTAIL_URL"] + "/healthz", timeout=5).read().decode())' || echo "PONYTAIL_UNREACHABLE"
docker exec "$CID" sh -c 'kill $(pgrep -f "hermes dashboard" | head -1) 2>/dev/null || true'
echo "signalled dashboard"
echo DONE
