#!/usr/bin/env bash
set -euo pipefail
sed -i 's/\r$//' /tmp/_disable-traefik-http3.py
python3 /tmp/_disable-traefik-http3.py
TR=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1)
echo TRAEFIK=$TR
docker restart "$TR"
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 2
  if curl -sS -m 3 -o /dev/null -w '' --resolve 6a69f224e6032a3f00de977f.hermes.aimarkets.vn:443:127.0.0.1 \
      https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login; then
    echo up after $i
    break
  fi
  echo wait $i
done
echo "=== headers (Alt-Svc should be gone) ==="
curl -sSI --resolve 6a69f224e6032a3f00de977f.hermes.aimarkets.vn:443:127.0.0.1 \
  https://6a69f224e6032a3f00de977f.hermes.aimarkets.vn/login | head -20
echo "=== cert ==="
echo | openssl s_client -connect 127.0.0.1:443 -servername 6a69f224e6032a3f00de977f.hermes.aimarkets.vn 2>/dev/null \
  | openssl x509 -noout -subject -issuer
echo DONE
