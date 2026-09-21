#!/bin/bash
set -euo pipefail
CID=$(docker ps --filter name=aimarketplace-hermes -q | head -1)
docker exec "$CID" python3 - <<'PY'
import logging, os, sys
logging.basicConfig(level=logging.DEBUG)
sys.path.insert(0, "/opt/hermes")
os.chdir("/opt/hermes")

# Simulate plugin load
from hermes_cli.plugins import PluginManager
mgr = PluginManager()
# discover
try:
    mgr.discover_and_load()
except Exception as e:
    print("discover_and_load error", type(e), e)

for key, loaded in sorted(mgr._plugins.items()):
    if "aimarkets" in key.lower() or "usage" in key.lower():
        print("PLUGIN", key, "enabled=", loaded.enabled, "error=", getattr(loaded, "error", None), "source=", loaded.manifest.source, "kind=", loaded.manifest.kind)
print("total plugins", len(mgr._plugins))
hooks = getattr(mgr, "_hooks", {})
print("post_api_request hooks", len(hooks.get("post_api_request", [])))
print("pre_llm_call hooks", len(hooks.get("pre_llm_call", [])))
for name, cbs in hooks.items():
    if cbs and ("llm" in name or "api" in name or "session" in name):
        print(" hook", name, len(cbs))
PY
