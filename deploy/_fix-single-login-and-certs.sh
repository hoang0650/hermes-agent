#!/usr/bin/env bash
set -euo pipefail

sed -i 's/\r$//' /tmp/login_page.py /tmp/_apply-aimarkets-user-certs.py 2>/dev/null || true
python3 /tmp/_apply-aimarkets-user-certs.py \
  6a69f224e6037a3f00de977f \
  6a69f224e6032a3f00de977f \
  6a69f224e5032a3f00de977f

CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo "CID=$CID"
docker cp /tmp/login_page.py "$CID:/opt/hermes/hermes_cli/dashboard_auth/login_page.py"

# Restart dashboard listener
docker exec "$CID" sh -c 'fuser -k 9119/tcp 2>/dev/null || true' || true
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 2
  if docker exec "$CID" python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",9119),2); s.close()' 2>/dev/null; then
    echo "dashboard up after ${i}"
    break
  fi
  echo "wait $i..."
done

echo "=== login form titles ==="
docker exec "$CID" python3 - <<'PY'
import urllib.request
html = urllib.request.urlopen("http://127.0.0.1:9119/login", timeout=10).read().decode("utf-8", "replace")
import re
titles = re.findall(r'class="form-title">(.*?)</div>', html)
providers = re.findall(r'data-provider="([^"]+)"', html)
print("titles=", titles)
print("providers=", providers)
print("has_basic_label=", "Username & Password" in html)
print("form_count=", html.count('class="provider-form"'))
PY

echo "=== wait ACME ==="
sleep 25
for h in \
  6a69f224e6037a3f00de977f.hermes.aimarkets.vn \
  6a69f224e5032a3f00de977f.hermes.aimarkets.vn
do
  echo "-- $h"
  echo | openssl s_client -connect 127.0.0.1:443 -servername "$h" 2>/dev/null \
    | openssl x509 -noout -subject -issuer || true
done
echo DONE
