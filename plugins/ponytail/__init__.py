"""Ponytail coding ruleset for AI Markets Hermes buyers.

Fetches the rules from the shared Ponytail service (``PONYTAIL_URL``, see
ponytail/deploy/DOKPLOY.md) and injects them through ``pre_llm_call``. Hermes
persists hook context in the user row's ``api_content``, so the rules ride
once per conversation and are re-sent only after compaction drops them or the
level changes.

No ``/ponytail`` command: one gateway serves every buyer, so a runtime mode
switch would be process-global. The level is ``PONYTAIL_MODE`` (ops only).
"""

from __future__ import annotations

import logging
import os
import re
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Optional

logger = logging.getLogger(__name__)

_MODES = {"compact", "lite", "full", "ultra", "off"}
_MARKER_RE = re.compile(r"PONYTAIL MODE ACTIVE — level: ([a-z]+)")
_REFRESH_S = 600
_RETRY_S = 60
_TIMEOUT_S = 3

_lock = threading.Lock()
_state: dict[str, Any] = {"text": "", "etag": "", "next": 0.0, "refreshing": False}


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def _mode() -> str:
    mode = _env("PONYTAIL_MODE").lower()
    return mode if mode in _MODES else "compact"


def _refresh(base: str, mode: str) -> None:
    headers = {"Accept": "text/plain"}
    if _state["etag"]:
        headers["If-None-Match"] = _state["etag"]
    req = urllib.request.Request(f"{base}/v1/rules?mode={mode}", headers=headers)
    retry_in = _REFRESH_S
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT_S) as resp:
            body = resp.read().decode("utf-8").strip()
            if body:
                _state["text"] = body
                _state["etag"] = resp.headers.get("ETag") or ""
    except urllib.error.HTTPError as exc:
        if exc.code != 304:
            logger.warning("ponytail: rules unavailable (HTTP %s)", exc.code)
            retry_in = _RETRY_S
    except Exception as exc:  # network / timeout: keep the last good copy
        logger.warning("ponytail: rules unavailable (%s)", exc)
        retry_in = _RETRY_S
    finally:
        with _lock:
            _state["next"] = time.monotonic() + retry_in
            _state["refreshing"] = False


def get_rules() -> str:
    """Ruleset text, or "" when disabled or never reached. Never raises."""
    base = _env("PONYTAIL_URL").rstrip("/")
    mode = _mode()
    if not base or mode == "off":
        return ""
    with _lock:
        due = time.monotonic() >= _state["next"] and not _state["refreshing"]
        if due:
            _state["refreshing"] = True
        text = _state["text"]
    if due:
        if text:
            # Serve the last good copy; revalidate off the request path.
            threading.Thread(target=_refresh, args=(base, mode), daemon=True).start()
        else:
            _refresh(base, mode)
            text = _state["text"]
    return text


def _injected_level(message: Any) -> Optional[str]:
    if not isinstance(message, dict):
        return None
    for key in ("api_content", "content"):
        value = message.get(key)
        if isinstance(value, str):
            found = _MARKER_RE.findall(value)
            if found:
                return found[-1]
    return None


def _on_pre_llm_call(*, conversation_history: Any = None, **_: Any) -> Optional[dict]:
    rules = get_rules()
    if not rules:
        return None
    match = _MARKER_RE.search(rules)
    level = match.group(1) if match else ""
    for message in reversed(conversation_history or []):
        injected = _injected_level(message)
        if injected:
            return None if injected == level else {"context": rules}
    return {"context": rules}


def register(ctx: Any) -> None:
    if not _env("PONYTAIL_URL") or _mode() == "off":
        logger.debug("ponytail: skipped (set PONYTAIL_URL; PONYTAIL_MODE=%s)", _mode())
        return
    ctx.register_hook("pre_llm_call", _on_pre_llm_call)
    logger.info("ponytail: registered (url=%s mode=%s)", _env("PONYTAIL_URL"), _mode())
