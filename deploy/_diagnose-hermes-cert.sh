#!/usr/bin/env bash
set -euo pipefail
H=6a69f224e6032a3f00de977f.hermes.aimarkets.vn
DYNAMIC=/etc/dokploy/traefik/dynamic

echo "=== routers mentioning hermes / e6032a3f ==="
grep -RIn --include='*.yml' -E 'hermes|e6032a3f' "$DYNAMIC" | head -80

echo "=== aimarkets-user-certs hermes block ==="
awk '/hermes-user-6a69f224e6032a3f00de977f/,/^[[:space:]]*$/' "$DYNAMIC/aimarkets-user-certs.yml" || true
sed -n '/hermes-user-6a69f224e6032a3f00de977f/,/openclaw-user-6a69f224e6032a3f00de977f-http/p' "$DYNAMIC/aimarkets-user-certs.yml" | head -40

echo "=== hermes wildcard ==="
cat "$DYNAMIC/hermes-aimarkets-wildcard.yml"

echo "=== openssl full chain ==="
echo | openssl s_client -connect 127.0.0.1:443 -servername "$H" -showcerts 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print} /subject=|issuer=/{print}' | head -80

echo "=== verify against system CA ==="
echo | openssl s_client -connect 127.0.0.1:443 -servername "$H" 2>&1 | tail -20

echo "=== acme.json hosts for hermes e6032 ==="
python3 - <<'PY'
import json
from pathlib import Path
p=Path('/etc/dokploy/traefik/dynamic/acme.json')
raw=p.read_text()
# acme.json may be large; search domain strings
for needle in [
  '6a69f224e6032a3f00de977f.hermes.aimarkets.vn',
  'hermes.aimarkets.vn',
  'TRAEFIK DEFAULT',
]:
  print(needle, 'count=', raw.count(needle))
PY

echo "=== public curl via host IP with SNI ==="
curl -sS -m 15 -o /dev/null -w "code:%{http_code} verify:%{ssl_verify_result}\n" \
  --resolve "${H}:443:127.0.0.1" "https://${H}/login" || true

TR=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1)
echo TRAEFIK=$TR
docker logs "$TR" --since 2h 2>&1 | grep -iE "e6032a3f\.hermes|Unable to obtain|ACME|certificate" | tail -40 || true
