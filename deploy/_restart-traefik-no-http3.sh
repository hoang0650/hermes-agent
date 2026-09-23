#!/usr/bin/env bash
set -euo pipefail
TR=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1)
echo "TRAEFIK=$TR"
test -n "$TR"
# Ensure http3 gone
grep -n http3 /etc/dokploy/traefik/traefik.yml && exit 1 || echo "http3 absent OK"
docker restart "$TR"
for i in $(seq 1 15); do
  sleep 2
  if curl -sS -m 3 -o /dev/null --resolve 6a69f224e6032a3f00de977f.hermes.aimarkets.vn:443:127.0.0.1 \
      https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login; then
    echo "up after $i"
    break
  fi
  echo "wait $i"
done
echo "=== response headers ==="
curl -sS -D - -o /dev/null --resolve 6a69f224e6032a3f00de977f.hermes.aimarkets.vn:443:127.0.0.1 \
  https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login | head -20
echo "=== cert ==="
echo | openssl s_client -connect 127.0.0.1:443 -servername 6a69f224e6032a3f00de977f.hermes.aimarkets.vn 2>/dev/null \
  | openssl x509 -noout -subject -issuer
ss -ulnp | grep ':443' || echo "no UDP 443 (good — http3 off)"
echo DONE
