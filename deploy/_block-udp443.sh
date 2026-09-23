#!/usr/bin/env bash
set -euo pipefail
# Find what publishes UDP/443 and stop H3 path completely
echo "=== listeners ==="
ss -tulnp | grep ':443' || true
echo "=== docker publish ==="
docker ps --format '{{.Names}} {{.Ports}}' | grep -i 443 || true
echo "=== iptables drop udp 443 (host) ==="
# Soft-block QUIC so Edge falls back to TCP TLS with LE cert
iptables -C INPUT -p udp --dport 443 -j DROP 2>/dev/null \
  || iptables -I INPUT -p udp --dport 443 -j DROP
ip6tables -C INPUT -p udp --dport 443 -j DROP 2>/dev/null \
  || ip6tables -I INPUT -p udp --dport 443 -j DROP || true
echo "udp 443 DROP installed"
iptables -L INPUT -n | grep 443 || true

# Verify public overview nanoclaw + hermes headers
curl -sS -m 15 -w '\nnc_overview:%{http_code}\n' \
  -H "Authorization: Bearer $(docker service inspect aimarketplace-nanoclaw-hsnvyh --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | sed -n 's/^DASHBOARD_SECRET=//p')" \
  https://6a69f224e6032a3f00de977f.nanoclaw.aimarkets.vn/api/overview | head -c 300
echo
curl -sSI https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login 2>/dev/null | head -15 || \
  curl -sS -D - -o /dev/null https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login | head -15
echo DONE
