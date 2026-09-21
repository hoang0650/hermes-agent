#!/bin/bash
set -euo pipefail
echo "=== disk ==="
df -h / /var /var/lib/docker 2>/dev/null || df -h /
echo "=== top dirs /var ==="
du -xh /var --max-depth=2 2>/dev/null | sort -hr | head -20
echo "=== docker disk ==="
docker system df 2>/dev/null || true
echo "=== large images ==="
docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}' | sort -hr | head -25
echo "=== exited containers ==="
docker ps -a --filter status=exited --format '{{.ID}} {{.Names}} {{.Status}}' | head -30
echo "=== dangling volumes count ==="
docker volume ls -qf dangling=true | wc -l
echo "=== journal size ==="
journalctl --disk-usage 2>/dev/null || true
echo "=== /tmp ==="
du -sh /tmp 2>/dev/null || true
echo "=== dokploy ==="
du -sh /etc/dokploy /var/lib/dokploy 2>/dev/null || true
ls -lah /var/lib/docker 2>/dev/null | head -15
echo DONE
