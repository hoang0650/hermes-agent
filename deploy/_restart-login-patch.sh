#!/usr/bin/env bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo CID=$CID
docker cp /tmp/login_page.py "$CID:/opt/hermes/hermes_cli/dashboard_auth/login_page.py"
docker exec "$CID" sh -c 'rm -rf /opt/hermes/hermes_cli/dashboard_auth/__pycache__ /opt/hermes/hermes_cli/dashboard_auth/*.pyc 2>/dev/null; find /opt/hermes -path "*dashboard_auth*login_page*" 2>/dev/null'
# Hard restart via s6 if present, else kill port
for d in /run/s6-rc/servicedirs/dashboard /run/s6/services/dashboard /var/run/s6/services/dashboard /run/service/dashboard; do
  if docker exec "$CID" test -d "$d" 2>/dev/null; then
    docker exec "$CID" s6-svc -r "$d" && echo "s6-svc -r $d"
    break
  fi
done
docker exec "$CID" sh -c 'pkill -f "hermes dashboard" 2>/dev/null || true; fuser -k 9119/tcp 2>/dev/null || true' || true
for i in $(seq 1 20); do
  sleep 2
  if docker exec "$CID" python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",9119),2); s.close()' 2>/dev/null; then
    echo "up after $i"
    break
  fi
  echo "wait $i"
done
docker exec "$CID" python3 -c '
import urllib.request, re
html = urllib.request.urlopen("http://127.0.0.1:9119/login", timeout=10).read().decode()
print("titles=", re.findall(r"class=\"form-title\">(.*?)</div>", html))
print("providers=", re.findall(r"data-provider=\"([^\"]+)\"", html))
print("form_count=", html.count("class=\"provider-form\""))
# prove runtime code source
import hermes_cli.dashboard_auth.login_page as lp
import inspect
src = inspect.getsource(lp.render_login_html)
print("has_aimarkets_filter=", "Aimarkets multi-buyer host" in src)
print("file=", lp.__file__)
'
