#!/bin/bash
set -euo pipefail
echo "=== hermes containers ==="
docker ps -a --filter name=hermes --format '{{.Names}} {{.Status}} {{.Ports}}' | head -20
echo "=== service ==="
docker service ls --format '{{.Name}} {{.Replicas}} {{.Image}}' | grep -i hermes || true
echo "=== running CID ==="
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1 || true)
echo "CID=${CID:-none}"
if [[ -n "${CID:-}" ]]; then
  echo "=== port 9119 ==="
  docker exec "$CID" python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",9119),3); s.close(); print("open")' 2>&1 || echo closed
  echo "=== last logs ==="
  docker logs "$CID" --tail 80 2>&1 | tail -80
  echo "=== cmd/args ==="
  docker inspect "$CID" --format 'Image={{.Config.Image}} Args={{json .Args}} Cmd={{json .Config.Cmd}}'
  echo "=== env flags ==="
  docker exec "$CID" sh -c 'echo API=${HERMES_AIMARKETS_API_URL:+set}; echo SECRET=${AIMARKETS_SERVICE_SECRET:+set}; echo BASIC_USER=${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-missing}; echo BASIC_PW=${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:+set}'
fi
echo "=== traefik hermes yml ==="
grep -n 'url:\|Host\|hermes' /etc/dokploy/traefik/dynamic/hermes-aimarkets-wildcard.yml 2>/dev/null | head -40 || ls /etc/dokploy/traefik/dynamic/ | grep -i hermes
echo "=== resolve upstream name ==="
getent hosts aimarketplace-hermes-nxdss5 2>/dev/null || docker run --rm --network dokploy-network alpine:3.20 getent hosts aimarketplace-hermes-nxdss5 || true
echo "=== curl via dokploy network ==="
UP=$(docker ps --filter name=aimarketplace-hermes --format '{{.Names}}' | head -1)
echo "UP_NAME=$UP"
if [[ -n "$UP" ]]; then
  docker run --rm --network dokploy-network curlimages/curl:8.5.0 -sS -m 5 -o /dev/null -w '%{http_code}\n' "http://${UP}:9119/api/status" || echo curl_fail
fi
echo DONE
