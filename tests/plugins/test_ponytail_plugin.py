"""Tests for the bundled AI Markets ponytail plugin."""
from __future__ import annotations

import importlib.util
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
import yaml

PLUGIN_DIR = Path(__file__).resolve().parents[2] / "plugins" / "ponytail"
RULES = "PONYTAIL MODE ACTIVE — level: compact\n\nYou are a lazy senior developer."


def _load():
    spec = importlib.util.spec_from_file_location("ponytail_plugin_under_test", PLUGIN_DIR / "__init__.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def service():
    hits = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            hits.append((self.path, self.headers.get("If-None-Match")))
            if self.headers.get("If-None-Match") == '"v1"':
                self.send_response(304)
                self.end_headers()
                return
            body = RULES.encode("utf-8")
            self.send_response(200)
            self.send_header("ETag", '"v1"')
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{server.server_address[1]}", hits
    server.shutdown()


def test_manifest_is_an_autoloading_backend_with_one_hook():
    data = yaml.safe_load((PLUGIN_DIR / "plugin.yaml").read_text(encoding="utf-8"))
    assert data["name"] == "ponytail"
    assert data["kind"] == "backend"
    assert data["hooks"] == ["pre_llm_call"]


def test_injects_once_per_conversation_and_caches(service, monkeypatch):
    url, hits = service
    monkeypatch.setenv("PONYTAIL_URL", url + "/")
    monkeypatch.delenv("PONYTAIL_MODE", raising=False)
    mod = _load()

    assert mod._on_pre_llm_call(conversation_history=[]) == {"context": RULES}
    assert hits == [("/v1/rules?mode=compact", None)]

    history = [{"role": "user", "content": "hi", "api_content": "hi\n\n" + RULES}]
    assert mod._on_pre_llm_call(conversation_history=history) is None
    assert len(hits) == 1  # served from cache

    stale = [{"role": "user", "api_content": "PONYTAIL MODE ACTIVE — level: full\n..."}]
    assert mod._on_pre_llm_call(conversation_history=stale) == {"context": RULES}


def test_revalidates_with_etag_after_refresh_window(service, monkeypatch):
    url, hits = service
    monkeypatch.setenv("PONYTAIL_URL", url)
    mod = _load()
    assert mod.get_rules() == RULES

    mod._state["next"] = 0.0
    assert mod.get_rules() == RULES  # stale copy served immediately
    for _ in range(50):
        if len(hits) == 2 and not mod._state["refreshing"]:
            break
        threading.Event().wait(0.05)
    assert hits[1] == ("/v1/rules?mode=compact", '"v1"')
    assert mod.get_rules() == RULES


def test_disabled_or_unreachable_injects_nothing(monkeypatch):
    monkeypatch.setenv("PONYTAIL_URL", "http://127.0.0.1:9")
    monkeypatch.setenv("PONYTAIL_MODE", "off")
    assert _load()._on_pre_llm_call(conversation_history=[]) is None

    monkeypatch.setenv("PONYTAIL_MODE", "compact")
    mod = _load()
    assert mod._on_pre_llm_call(conversation_history=[]) is None
    assert mod._state["next"] > 0  # backs off instead of retrying every turn


def test_register_skips_without_url(monkeypatch):
    monkeypatch.delenv("PONYTAIL_URL", raising=False)
    registered = []

    class Ctx:
        def register_hook(self, name, fn):
            registered.append(name)

    _load().register(Ctx())
    assert registered == []
