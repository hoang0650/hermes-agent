#!/usr/bin/env bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
echo CID=$CID
docker exec "$CID" grep -n 'Aimarkets multi-buyer host' /opt/hermes/hermes_cli/dashboard_auth/login_page.py | head -3
docker exec "$CID" python3 -c '
import urllib.request, re
html = urllib.request.urlopen("http://127.0.0.1:9119/login", timeout=10).read().decode()
print("titles=", re.findall(r"class=\"form-title\">(.*?)</div>", html))
print("providers=", re.findall(r"data-provider=\"([^\"]+)\"", html))
print("has_basic_label=", "Username & Password" in html)
print("form_count=", html.count("class=\"provider-form\""))
'
