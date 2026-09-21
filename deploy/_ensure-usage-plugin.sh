#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
if [[ -z "$CID" ]]; then echo "NO_HERMES"; exit 1; fi
docker exec "$CID" ls -la /opt/hermes/plugins/aimarkets_usage 2>&1 || echo MISSING_PLUGIN
docker exec "$CID" sh -c 'echo API=${HERMES_AIMARKETS_API_URL:+set}; echo SECRET=${AIMARKETS_SERVICE_SECRET:+set}'
# re-copy if missing
if ! docker exec "$CID" test -f /opt/hermes/plugins/aimarkets_usage/__init__.py; then
  echo "re-deploying plugin"
  if [[ -d /tmp/hermes-autofill/aimarkets_usage ]]; then
    docker exec "$CID" mkdir -p /opt/hermes/plugins/aimarkets_usage
    docker cp /tmp/hermes-autofill/aimarkets_usage/__init__.py "$CID:/opt/hermes/plugins/aimarkets_usage/__init__.py"
    docker cp /tmp/hermes-autofill/aimarkets_usage/plugin.yaml "$CID:/opt/hermes/plugins/aimarkets_usage/plugin.yaml"
    PID=$(docker exec "$CID" sh -c 'pgrep -f "hermes dashboard" | head -1' || true)
    [[ -n "$PID" ]] && docker exec "$CID" kill "$PID" || true
    echo "signalled reload"
  else
    echo "NO_LOCAL_SRC"
  fi
fi
docker exec "$CID" test -f /opt/hermes/plugins/aimarkets_usage/__init__.py && echo PLUGIN_OK
echo DONE
