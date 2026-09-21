#!/bin/bash
set -euo pipefail
echo "=== images used by running containers ==="
docker ps --format '{{.Image}}' | sort -u
echo "=== swarm service images ==="
docker service ls --format '{{.Name}} {{.Image}}' 2>/dev/null || true
echo "=== try remove unused tags ==="
# dokploy old
USED=$(docker ps --format '{{.Image}}'; docker service ls --format '{{.Image}}' 2>/dev/null)
if echo "$USED" | grep -q 'dokploy/dokploy:v0.30.6'; then
  echo "keep dokploy:v0.30.6 (in use)"
else
  docker rmi dokploy/dokploy:v0.30.6 2>&1 || true
fi
# hermes: keep whichever the service uses
HERMES_IMG=$(docker service inspect aimarketplace-hermes-nxdss5 --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || true)
echo "hermes service image=$HERMES_IMG"
if [[ "$HERMES_IMG" == *"autofill"* ]]; then
  docker rmi aimarketplace-hermes-nxdss5:latest 2>&1 || true
elif [[ -n "$HERMES_IMG" ]]; then
  docker rmi aimarkets/hermes-aimarkets:autofill-202609210517 2>&1 || true
fi
# alpine/curl leftover from probes
docker rmi alpine:3.20 curlimages/curl:8.5.0 2>&1 || true
docker image prune -f
echo "=== AFTER2 ==="
df -h / | tail -1
docker system df
docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}' | sort -hr | head -12
echo DONE
