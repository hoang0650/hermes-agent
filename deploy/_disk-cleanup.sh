#!/bin/bash
# Safe VPS disk cleanup — keeps images referenced by running containers / swarm services.
set -euo pipefail

echo "=== BEFORE ==="
df -h / | tail -1
docker system df

echo "=== prune build cache ==="
docker builder prune -af

echo "=== prune exited containers ==="
docker container prune -f

echo "=== prune dangling images ==="
docker image prune -f

echo "=== prune dangling volumes ==="
docker volume prune -f

echo "=== remove unused dokploy old tag (if not used) ==="
# Keep current dokploy; drop previous patch if idle
if docker ps -a --format '{{.Image}}' | grep -q 'dokploy/dokploy:v0.30.6'; then
  echo "v0.30.6 still referenced by a container — skip rmi"
else
  docker rmi dokploy/dokploy:v0.30.6 2>/dev/null && echo "removed dokploy:v0.30.6" || echo "dokploy:v0.30.6 already gone / in use"
fi

echo "=== remove unused alpine/curl pull leftovers if dangling ==="
docker image prune -f

echo "=== journal vacuum ==="
journalctl --vacuum-size=100M 2>/dev/null || true

echo "=== apt clean ==="
apt-get clean 2>/dev/null || true
rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true

echo "=== tmp hermes patch leftovers ==="
rm -rf /tmp/hermes-autofill /tmp/*.sh /tmp/debug_usage_plugin.py /tmp/fix-*.sh 2>/dev/null || true

echo "=== containerd leftovers (unused content) ==="
if command -v ctr >/dev/null 2>&1; then
  # Default docker namespace
  ctr -n moby content ls 2>/dev/null | wc -l || true
  # Prune unreferenced blobs — careful, only if dockerd uses containerd
  ctr -n moby content prune -l 0 2>/dev/null && echo "ctr content prune ok" || echo "ctr prune skipped/unsupported"
fi

# BuildKit / containerd snapshot clutter under docker rootfs
if [[ -d /var/lib/docker/buildkit ]]; then
  echo "buildkit dir before: $(du -sh /var/lib/docker/buildkit | awk '{print $1}')"
fi

echo "=== swarm: remove old completed task containers already pruned above ==="

echo "=== AFTER ==="
df -h / | tail -1
docker system df
echo "=== largest images remaining ==="
docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}' | sort -hr | head -15
du -sh /var/lib/containerd /var/lib/docker /var/log 2>/dev/null || true
echo DONE
