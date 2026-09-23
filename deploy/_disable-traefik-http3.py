#!/usr/bin/env python3
"""Disable Traefik HTTP/3 so browsers use TCP TLS with the ACME leaf cert."""
from pathlib import Path

p = Path("/etc/dokploy/traefik/traefik.yml")
text = p.read_text()
bak = p.with_suffix(p.suffix + ".bak.http3")
if not bak.exists():
    bak.write_text(text)

old = (
    "  websecure:\n"
    "    address: :443\n"
    "    http3:\n"
    "      advertisedPort: 443\n"
    "    http:\n"
    "      tls:\n"
    "        certResolver: letsencrypt\n"
)
new = (
    "  websecure:\n"
    "    address: :443\n"
    "    http:\n"
    "      tls:\n"
    "        certResolver: letsencrypt\n"
)
if old not in text:
    raise SystemExit(f"expected http3 block missing; file is:\n{text}")
p.write_text(text.replace(old, new, 1))
print("OK: http3 disabled")
print(p.read_text())
