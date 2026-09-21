print("start")
from pathlib import Path
print("aimarkets dirs", list(Path("/opt/hermes/plugins").glob("aimarkets*")))
import sys
sys.path.insert(0, "/opt/hermes")
from hermes_cli.plugins import PluginManager
mgr = PluginManager()
try:
    mgr.discover_and_load()
    print("discover_ok")
except Exception as e:
    print("discover_err", type(e).__name__, e)
for key, loaded in sorted(mgr._plugins.items()):
    if "aimarkets" in key.lower() or "usage" in key.lower():
        print(
            "PLUGIN",
            key,
            "enabled=",
            loaded.enabled,
            "error=",
            getattr(loaded, "error", None),
            "source=",
            loaded.manifest.source,
            "kind=",
            loaded.manifest.kind,
        )
print("total", len(mgr._plugins))
hooks = getattr(mgr, "_hooks", {})
print("post_api_request", len(hooks.get("post_api_request", [])))
print("pre_llm_call", len(hooks.get("pre_llm_call", [])))
