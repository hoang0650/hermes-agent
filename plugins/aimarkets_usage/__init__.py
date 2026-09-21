"""AI Markets Hermes usage — charge marketplace wallet (COGS + 25%).

Mirrors ``openclaw/extensions/aimarkets-usage`` against Hermes hooks:

* ``pre_llm_call`` — soft wallet / PHHotel-model warning (context inject)
* ``post_api_request`` — report tokens → ``POST /v1/hermes/usage``

Buyer identity comes from the locked profile ``market-{userId}``
(Aimarkets auth) or ``HERMES_HOME`` under ``profiles/market-*``.
"""

from __future__ import annotations

import json
import logging
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

logger = logging.getLogger(__name__)

_USER_ID_RE = re.compile(r"^[a-f0-9]{24}$", re.I)
_MARKET_RE = re.compile(r"(?:^|[/\\_-])market[-_]([a-f0-9]{24})", re.I)

# Keep in sync with openclaw/extensions/aimarkets-usage/audience.ts
_AIMARKETS_PROVIDER_MARKUP = 0.25
_PHHOTEL_MODEL_IDS = {
    "deepseek-ai/DeepSeek-V4-Flash",
    "Qwen/Qwen3.6-35B-A3B",
    "MiniMaxAI/MiniMax-M2.5",
}
_PROVIDER_RATES = {
    "deepseek-ai/DeepSeek-V4-Flash": {"input": 0.14, "output": 0.28},
    "Qwen/Qwen3.6-35B-A3B": {"input": 0.2, "output": 0.4},
    "MiniMaxAI/MiniMax-M2.5": {"input": 0.295, "output": 1.2},
    "default": {"input": 0.15, "output": 0.6},
}


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def _api_base() -> str:
    return (
        _env("HERMES_AIMARKETS_API_URL")
        or _env("AIMARKETS_API_URL")
        or _env("AI_MARKETPLACE_API_URL")
        or "https://api.aimarkets.vn"
    ).rstrip("/")


def _service_secret() -> str:
    return (
        _env("AIMARKETS_SERVICE_SECRET")
        or _env("NEST_SERVICE_AUTH_SECRET")
        or _env("PYTHON_AI_SHARED_SECRET")
    )


def _markup() -> float:
    raw = _env("OPENCLAW_AIMARKETS_MARKUP") or _env("HERMES_AIMARKETS_MARKUP")
    try:
        v = float(raw) if raw else _AIMARKETS_PROVIDER_MARKUP
    except ValueError:
        v = _AIMARKETS_PROVIDER_MARKUP
    return v if v >= 0 else _AIMARKETS_PROVIDER_MARKUP


def _normalize_model(model: str) -> str:
    return re.sub(r"^(featherless|openrouter)/", "", str(model or "").strip(), flags=re.I)


def _is_phhotel_model(model: str) -> bool:
    raw = str(model or "").strip()
    bare = _normalize_model(raw)
    return raw in _PHHOTEL_MODEL_IDS or bare in _PHHOTEL_MODEL_IDS


def _compute_sell_cost(*, model: str, input_tokens: int, output_tokens: int, markup: float) -> float:
    bare = _normalize_model(model)
    if re.search(r":free$", bare, re.I) or re.search(r"openrouter/free", model or "", re.I):
        return 0.0
    rate = _PROVIDER_RATES.get(bare) or _PROVIDER_RATES["default"]
    cogs = (max(0, input_tokens) / 1_000_000) * rate["input"] + (
        max(0, output_tokens) / 1_000_000
    ) * rate["output"]
    return round(cogs * (1 + markup) * 1e6) / 1e6


def _resolve_user_id(*, session_id: str = "") -> str:
    for candidate in (
        _env("AIMARKETS_USER_ID"),
        _env("HERMES_AIMARKETS_USER_ID"),
        session_id,
        _env("HERMES_PROFILE"),
        os.environ.get("HERMES_HOME") or "",
    ):
        m = _MARKET_RE.search(str(candidate or ""))
        if m and _USER_ID_RE.match(m.group(1)):
            return m.group(1).lower()
        raw = str(candidate or "").strip().lower()
        if _USER_ID_RE.match(raw):
            return raw
    try:
        from hermes_constants import get_hermes_home

        m = _MARKET_RE.search(str(get_hermes_home()))
        if m and _USER_ID_RE.match(m.group(1)):
            return m.group(1).lower()
    except Exception:
        pass
    return ""


def _read_tokens(usage: Any) -> tuple[int, int]:
    if not isinstance(usage, dict):
        return 0, 0
    inp = max(
        0,
        int(
            usage.get("input_tokens")
            or usage.get("input")
            or usage.get("prompt_tokens")
            or 0
        ),
    )
    cache_read = max(
        0,
        int(
            usage.get("cache_read_tokens")
            or usage.get("cache_read")
            or usage.get("cache_read_input_tokens")
            or 0
        ),
    )
    out = max(
        0,
        int(
            usage.get("output_tokens")
            or usage.get("output")
            or usage.get("completion_tokens")
            or 0
        ),
    )
    return (inp if inp > 0 else cache_read), out


def _http_json(method: str, url: str, *, body: Optional[dict] = None, timeout: float = 12.0) -> tuple[int, dict]:
    secret = _service_secret()
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if secret:
        headers["X-Service-Secret"] = secret
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8") or "{}"
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = {}
            return int(resp.status), parsed if isinstance(parsed, dict) else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else "{}"
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"message": raw[:200]}
        return int(exc.code), parsed if isinstance(parsed, dict) else {}
    except Exception as exc:
        logger.warning("aimarkets-usage: HTTP %s %s failed: %s", method, url, exc)
        return 0, {"message": str(exc)}


def _check_wallet(user_id: str) -> dict[str, Any]:
    if not user_id or not _api_base():
        return {"allowed": False, "reason": "missing_user_or_api"}
    qs = urllib.parse.urlencode({"user_id": user_id})
    status, data = _http_json("GET", f"{_api_base()}/v1/hermes/usage/check?{qs}")
    if status == 0:
        return {"allowed": True, "reason": "check_unreachable"}
    if status >= 400:
        return {"allowed": False, "reason": data.get("message") or f"http_{status}"}
    return {
        "allowed": data.get("allowed") is not False,
        "available": data.get("available"),
        "reason": data.get("message"),
    }


def _report_usage(
    *,
    user_id: str,
    input_tokens: int,
    output_tokens: int,
    model: str,
    cost: float,
    markup: float,
) -> None:
    if not user_id or not _api_base():
        return
    if input_tokens <= 0 and output_tokens <= 0 and cost <= 0:
        return
    status, data = _http_json(
        "POST",
        f"{_api_base()}/v1/hermes/usage",
        body={
            "user_id": user_id,
            "userId": user_id,
            "inputTokens": input_tokens,
            "outputTokens": output_tokens,
            "model": model,
            "cost": cost,
            "markup": markup,
            "channel": "hermes",
            "audience": "aimarkets",
        },
    )
    if status == 402:
        logger.warning(
            "aimarkets-usage: insufficient wallet for %s: %s",
            user_id,
            data.get("message"),
        )
    elif status and status >= 400:
        logger.warning(
            "aimarkets-usage: charge failed status=%s user=%s msg=%s",
            status,
            user_id,
            data.get("message"),
        )
    else:
        logger.info(
            "aimarkets-usage: charged user=%s model=%s in=%s out=%s cost=%s",
            user_id,
            model,
            input_tokens,
            output_tokens,
            data.get("charged", cost),
        )


def _on_pre_llm_call(*, session_id: str = "", model: str = "", **_: Any) -> Optional[dict]:
    if _is_phhotel_model(model):
        return {
            "context": (
                "[AI Markets] This model is reserved for PHHotel. "
                "Pick an OpenRouter/Featherless model instead."
            )
        }
    user_id = _resolve_user_id(session_id=session_id)
    if not user_id:
        return None  # admin / non-aimarkets profile
    check = _check_wallet(user_id)
    if not check.get("allowed"):
        reason = check.get("reason") or "Insufficient AI Markets wallet balance."
        return {
            "context": (
                f"[AI Markets] Wallet check failed for buyer {user_id}: {reason} "
                "Top up at https://aimarkets.vn then retry."
            )
        }
    avail = check.get("available")
    if isinstance(avail, (int, float)) and avail <= 0:
        return {
            "context": (
                f"[AI Markets] Wallet balance is ${float(avail):.4f}. "
                "Top up at https://aimarkets.vn before heavy usage."
            )
        }
    return None


def _on_post_api_request(
    *,
    session_id: str = "",
    model: str = "",
    response_model: Any = None,
    usage: Any = None,
    **_: Any,
) -> None:
    user_id = _resolve_user_id(session_id=session_id)
    if not user_id:
        return
    resolved_model = (
        str(response_model).strip()
        if isinstance(response_model, str) and response_model.strip()
        else str(model or "unknown")
    )
    if _is_phhotel_model(resolved_model):
        logger.warning(
            "aimarkets-usage: skip charge for blocked PHHotel model %s",
            resolved_model,
        )
        return
    inp, out = _read_tokens(usage)
    if inp <= 0 and out <= 0:
        return
    markup = _markup()
    cost = _compute_sell_cost(
        model=resolved_model, input_tokens=inp, output_tokens=out, markup=markup
    )
    _report_usage(
        user_id=user_id,
        input_tokens=inp,
        output_tokens=out,
        model=resolved_model,
        cost=cost,
        markup=markup,
    )


def register(ctx: Any) -> None:
    api = _api_base()
    secret = _service_secret()
    if not api or not secret:
        logger.debug(
            "aimarkets-usage: skipped (need HERMES_AIMARKETS_API_URL + AIMARKETS_SERVICE_SECRET)"
        )
        return
    ctx.register_hook("pre_llm_call", _on_pre_llm_call)
    ctx.register_hook("post_api_request", _on_post_api_request)
    logger.info("aimarkets-usage: registered (api=%s markup=%s)", api, _markup())
