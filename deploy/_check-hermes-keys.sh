#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
docker exec "$CID" sh -c 'echo OPENROUTER=${OPENROUTER_API_KEY:+SET}; echo OPENAI=${OPENAI_API_KEY:+SET}; echo ANTHROPIC=${ANTHROPIC_API_KEY:+SET}; echo FEATHERLESS=${FEATHERLESS_API_KEY:+SET}'
echo "=== /opt/data ==="
docker exec "$CID" sh -c 'ls -la /opt/data/.env /opt/data/config.yaml 2>&1 | head -20'
echo "=== root .env key names ==="
docker exec "$CID" sh -c 'if [ -f /opt/data/.env ]; then grep -E "^[A-Z0-9_]*(API_KEY|TOKEN)=" /opt/data/.env | sed "s/=.*/=***/"; else echo NO_ROOT_ENV; fi'
echo "=== profiles ==="
docker exec "$CID" sh -c 'ls -la /opt/data/profiles 2>/dev/null || echo no_profiles_dir; find /opt/data -maxdepth 4 -name ".env" 2>/dev/null'
echo "=== market profile env sample ==="
docker exec "$CID" sh -c 'for f in $(find /opt/data -maxdepth 4 -path "*market*" -name ".env" 2>/dev/null); do echo FILE=$f; grep -E "^[A-Z0-9_]*(API_KEY|TOKEN|PROVIDER)=" "$f" | sed "s/=.*/=***/" || echo empty; done'
echo "=== service env names (no values) ==="
docker service inspect aimarketplace-hermes-nxdss5 --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | sed -E 's/=.*/=***/' | grep -iE 'API_KEY|TOKEN|AIMARKETS|HERMES_DASHBOARD|OPEN' || true
