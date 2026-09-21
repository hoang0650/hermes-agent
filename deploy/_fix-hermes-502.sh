#!/bin/bash
# Fix Hermes 502 crash-loop:
# - Empty CMD runs interactive hermes → exits without TTY → container dies
# - Dashboard only stays up when CMD stays alive (sleep infinity) + HERMES_DASHBOARD=1
set -euo pipefail
SVC=aimarketplace-hermes-nxdss5
PATCHED=aimarkets/hermes-aimarkets:autofill-202609210517

if ! docker image inspect "$PATCHED" >/dev/null 2>&1; then
  PATCHED=aimarketplace-hermes-nxdss5:latest
  echo "WARN: autofill image missing, using $PATCHED"
fi

API=$(docker ps --filter name=aimarketplace-api -q | head -1 || true)
SECRET=""
if [[ -n "${API:-}" ]]; then
  SECRET=$(docker exec "$API" sh -c 'printenv AIMARKETS_SERVICE_SECRET || printenv NEST_SERVICE_AUTH_SECRET || true')
fi

OPTS=(
  --image "$PATCHED"
  --args "sleep infinity"
  --env-add "HERMES_DASHBOARD=1"
  --env-add "HERMES_DASHBOARD_HOST=0.0.0.0"
  --env-add "HERMES_DASHBOARD_PORT=9119"
  --env-add "HERMES_AIMARKETS_API_URL=https://api.aimarkets.vn"
)
if [[ -n "$SECRET" ]]; then
  OPTS+=(--env-add "AIMARKETS_SERVICE_SECRET=${SECRET}")
  echo "SECRET=from_api"
fi

echo "Updating $SVC → image=$PATCHED args='sleep infinity' HERMES_DASHBOARD=1"
docker service update "${OPTS[@]}" --force "$SVC"

echo "waiting..."
for i in $(seq 1 45); do
  NEW=$(docker ps --filter name=aimarketplace-hermes -q | head -1 || true)
  if [[ -n "${NEW:-}" ]]; then
    if docker exec "$NEW" python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=3)' 2>/dev/null; then
      echo "healthy NEW=$NEW try=$i"
      docker inspect "$NEW" --format 'Image={{.Config.Image}} Args={{json .Args}}'
      break
    fi
  fi
  # show crash reason periodically
  if (( i % 5 == 0 )); then
    echo "--- try $i ---"
    docker ps -a --filter name=aimarketplace-hermes --format '{{.Status}}' | head -3
    NEW2=$(docker ps -aq --filter name=aimarketplace-hermes | head -1 || true)
    [[ -n "${NEW2:-}" ]] && docker logs "$NEW2" --tail 15 2>&1 | tail -15
  fi
  sleep 3
done

NEW=$(docker ps --filter name=aimarketplace-hermes -q | head -1 || true)
if [[ -z "${NEW:-}" ]]; then
  echo "FAILED: still no running container"
  docker service ps "$SVC" --no-trunc | head -8
  exit 1
fi

# If stock image, re-apply autofill files
if [[ "$PATCHED" == *nxdss5* && -f /tmp/hermes-autofill/login_page.py ]]; then
  docker cp /tmp/hermes-autofill/login_page.py "$NEW:/opt/hermes/hermes_cli/dashboard_auth/login_page.py"
  docker cp /tmp/hermes-autofill/routes.py "$NEW:/opt/hermes/hermes_cli/dashboard_auth/routes.py"
  docker cp /tmp/hermes-autofill/middleware.py "$NEW:/opt/hermes/hermes_cli/dashboard_auth/middleware.py"
  docker exec "$NEW" mkdir -p /opt/hermes/plugins/dashboard_auth/aimarkets
  docker cp /tmp/hermes-autofill/aimarkets/__init__.py "$NEW:/opt/hermes/plugins/dashboard_auth/aimarkets/__init__.py"
  docker cp /tmp/hermes-autofill/aimarkets/plugin.yaml "$NEW:/opt/hermes/plugins/dashboard_auth/aimarkets/plugin.yaml"
  SVC_DIR=$(docker exec "$NEW" sh -c 'ls -d /run/s6/services/dashboard /var/run/s6/services/dashboard 2>/dev/null | head -1')
  [[ -n "$SVC_DIR" ]] && docker exec "$NEW" s6-svc -r "$SVC_DIR" || true
  sleep 5
fi

echo "=== providers ==="
docker exec "$NEW" python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:9119/api/auth/providers", timeout=8).read().decode())'

echo "=== VIP curl ==="
docker run --rm --network dokploy-network curlimages/curl:8.5.0 -sS -m 8 -o /dev/null -w 'vip:%{http_code}\n' http://aimarketplace-hermes-nxdss5:9119/api/status

echo "=== public ==="
curl -sk -o /dev/null -w 'login:%{http_code}\n' 'https://6a69f224e6037a3f00de977f.hermes.aimarkets.vn/login'
curl -sk -o /dev/null -w 'status:%{http_code}\n' 'https://6a69f224e6037a3f00de977f.hermes.aimarkets.vn/api/status'

# stability check — must stay up 20s
sleep 20
STILL=$(docker ps --filter name=aimarketplace-hermes -q | head -1 || true)
echo "still_running=${STILL:-NO}"
docker ps -a --filter name=aimarketplace-hermes --format '{{.Names}} {{.Status}}' | head -3
echo DONE
