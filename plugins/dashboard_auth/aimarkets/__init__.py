"""Aimarkets multi-buyer dashboard auth.

Each marketplace buyer has a unique username/password stored in
ai-marketplace-api (HermesAccount). This provider verifies against
``POST {HERMES_AIMARKETS_API_URL}/v1/hermes/auth/verify`` and mints a
session whose ``org_id`` is the locked Hermes profile ``market-{userId}``.

The auth middleware then forces ``HERMES_HOME`` to that profile for the
request lifetime so buyer A cannot read buyer B's chats/files.

Admin/operator access remains on the bundled ``basic`` provider
(``HERMES_DASHBOARD_BASIC_AUTH_*``) — do not share those credentials with buyers.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

from hermes_cli.dashboard_auth import (
    DashboardAuthProvider,
    InvalidCredentialsError,
    LoginStart,
    RefreshExpiredError,
    Session,
)

logger = logging.getLogger(__name__)

_DEFAULT_TTL_SECONDS = 12 * 60 * 60
_REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60
_SIG_LEN = hashlib.sha256().digest_size

LAST_SKIP_REASON: str = ""


def _sign(payload: dict, secret: bytes) -> str:
    raw = json.dumps(payload, separators=(",", ":")).encode()
    sig = hmac.new(secret, raw, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(raw + sig).decode()


def _unsign(token: str, secret: bytes) -> Optional[dict]:
    try:
        blob = base64.urlsafe_b64decode(token.encode())
        if len(blob) <= _SIG_LEN:
            return None
        raw, sig = blob[:-_SIG_LEN], blob[-_SIG_LEN:]
        expected = hmac.new(secret, raw, hashlib.sha256).digest()
        if not hmac.compare_digest(sig, expected):
            return None
        return json.loads(raw)
    except Exception:
        return None


def _resolve_secret() -> bytes:
    raw = (os.environ.get("HERMES_AIMARKETS_AUTH_SECRET") or "").strip()
    if not raw:
        raw = (os.environ.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET") or "").strip()
    if not raw:
        # Per-process secret — sessions die on restart (acceptable for MVP).
        raw = base64.urlsafe_b64encode(os.urandom(32)).decode()
        logger.warning(
            "dashboard-auth-aimarkets: no HERMES_AIMARKETS_AUTH_SECRET; "
            "using ephemeral secret (sessions reset on restart)."
        )
    try:
        if len(raw) >= 32 and all(c in "0123456789abcdefABCDEF" for c in raw):
            secret = bytes.fromhex(raw)
        else:
            secret = base64.urlsafe_b64decode(raw + "==")
    except Exception:
        secret = raw.encode("utf-8")
    if len(secret) < 16:
        secret = hashlib.sha256(secret).digest()
    return secret


def _verify_remote(*, username: str, password: str) -> dict[str, Any]:
    api = (os.environ.get("HERMES_AIMARKETS_API_URL") or "").rstrip("/")
    secret = (os.environ.get("AIMARKETS_SERVICE_SECRET") or "").strip()
    if not api or not secret:
        raise InvalidCredentialsError("aimarkets auth not configured")

    url = f"{api}/v1/hermes/auth/verify"
    body = json.dumps({"username": username, "password": password}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Service-Secret": secret,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise InvalidCredentialsError("invalid username or password") from exc
        raise InvalidCredentialsError("aimarkets verify failed") from exc
    except Exception as exc:
        logger.warning("dashboard-auth-aimarkets: verify unreachable: %s", exc)
        raise InvalidCredentialsError("aimarkets verify unreachable") from exc

    if not data.get("ok") or not data.get("profile") or not data.get("userId"):
        raise InvalidCredentialsError("invalid username or password")
    return data


class AimarketsAuthProvider(DashboardAuthProvider):
    """Password provider backed by AI Markets HermesAccount records."""

    name = "aimarkets"
    display_name = "AI Markets"
    supports_password = True

    def __init__(self, *, secret: bytes, ttl_seconds: int = _DEFAULT_TTL_SECONDS) -> None:
        if len(secret) < 16:
            raise ValueError("secret must be at least 16 bytes")
        self._secret = secret
        self._ttl = max(60, int(ttl_seconds))

    def start_login(self, *, redirect_uri: str) -> LoginStart:
        raise NotImplementedError("AimarketsAuthProvider is password-only")

    def complete_login(
        self, *, code: str, state: str, code_verifier: str, redirect_uri: str
    ) -> Session:
        raise NotImplementedError("AimarketsAuthProvider is password-only")

    def complete_password_login(self, *, username: str, password: str) -> Session:
        data = _verify_remote(username=username, password=password)
        user_id = str(data["userId"])
        profile = str(data["profile"])
        uname = str(data.get("username") or username)
        self._ensure_profile(profile)
        return self._mint_session(user_id=user_id, username=uname, profile=profile)

    @staticmethod
    def _ensure_profile(profile: str) -> None:
        try:
            from hermes_cli import profiles as profiles_mod

            canon = profiles_mod.normalize_profile_name(profile)
            profiles_mod.validate_profile_name(canon)
            created = False
            if not profiles_mod.profile_exists(canon):
                profiles_mod.create_profile(canon, no_skills=False)
                created = True
                logger.info("dashboard-auth-aimarkets: created profile %s", canon)
            # Platform keys stay out of this profile. Only the buyer's BYOK
            # selection is written, and previously copied platform keys are removed.
            AimarketsAuthProvider._apply_buyer_credentials(canon)
            if created:
                logger.info(
                    "dashboard-auth-aimarkets: prepared profile %s",
                    canon,
                )
        except Exception as exc:
            logger.warning(
                "dashboard-auth-aimarkets: profile ensure failed for %s: %s",
                profile,
                exc,
            )

    _PLATFORM_KEY_NAMES = (
        "OPENROUTER_API_KEY",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "ANTHROPIC_API_KEY",
        "FEATHERLESS_API_KEY",
        "GOOGLE_API_KEY",
        "GEMINI_API_KEY",
        "DEEPSEEK_API_KEY",
        "GROQ_API_KEY",
        "TOGETHER_API_KEY",
        "FIREWORKS_API_KEY",
        "MISTRAL_API_KEY",
        "COHERE_API_KEY",
        "XAI_API_KEY",
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_ENDPOINT",
    )
    _BUYER_ENV = {
        "openai": "OPENAI_API_KEY",
        "anthropic": "ANTHROPIC_API_KEY",
        "google": "GEMINI_API_KEY",
        "openrouter": "OPENROUTER_API_KEY",
        "deepseek": "DEEPSEEK_API_KEY",
        "groq": "GROQ_API_KEY",
        "xai": "XAI_API_KEY",
        "byok-custom": "OPENAI_API_KEY",
    }

    @staticmethod
    def _read_env_file(path) -> dict[str, str]:
        out: dict[str, str] = {}
        if not path.is_file():
            return out
        try:
            raw = path.read_text(encoding="utf-8-sig", errors="replace")
        except Exception:
            return out
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.startswith("export "):
                line = line[7:]
            k, _, v = line.partition("=")
            k = k.strip()
            v = v.strip().strip("'").strip('"')
            if k and v:
                out[k] = v
        return out

    @staticmethod
    def _fetch_buyer_connection(user_id: str) -> Optional[dict[str, Any]]:
        """The buyer's own provider key. Never a platform key."""
        api = (os.environ.get("HERMES_AIMARKETS_API_URL") or "").rstrip("/")
        secret = (os.environ.get("AIMARKETS_SERVICE_SECRET") or "").strip()
        if not api or not secret or not user_id:
            return None
        url = f"{api}/v1/hermes/provider/resolve?user_id={urllib.parse.quote(user_id)}"
        req = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "X-Service-Secret": secret},
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode() or "{}")
        except Exception as exc:
            logger.warning("dashboard-auth-aimarkets: byok resolve failed: %s", exc)
            return None
        conn = data.get("connection") if isinstance(data, dict) else None
        return conn if isinstance(conn, dict) else None

    @staticmethod
    def _apply_buyer_credentials(profile: str) -> None:
        """Drop platform keys copied into this profile and write the buyer's BYOK key."""
        from pathlib import Path

        from hermes_cli import profiles as profiles_mod
        from hermes_cli.config import load_config, save_config
        from hermes_constants import reset_hermes_home_override, set_hermes_home_override

        import json
        import tempfile

        user_id = profile[len("market-") :] if profile.startswith("market-") else ""
        if not re.fullmatch(r"[a-f0-9]{24}", user_id):
            raise ValueError("Invalid buyer profile")
        connection = AimarketsAuthProvider._fetch_buyer_connection(user_id)
        profile_dir = Path(profiles_mod.get_profile_dir(profile))
        profile_dir.mkdir(parents=True, exist_ok=True)
        env_path = profile_dir / ".env"
        existing = AimarketsAuthProvider._read_env_file(env_path)
        # Never use save_env_value/remove_env_value: both mutate os.environ,
        # which is shared by all buyer sessions in this dashboard process.
        for name in AimarketsAuthProvider._PLATFORM_KEY_NAMES:
            existing.pop(name, None)
        if connection:
            name = AimarketsAuthProvider._BUYER_ENV.get(str(connection.get("provider") or ""))
            if name and connection.get("apiKey"):
                existing[name] = str(connection["apiKey"])
            if connection.get("provider") == "byok-custom":
                existing["OPENAI_BASE_URL"] = str(connection.get("baseUrl") or "")
        fd, tmp = tempfile.mkstemp(prefix=".byok-", dir=profile_dir)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as out:
                for name, value in existing.items():
                    out.write(name + "=" + json.dumps(value, ensure_ascii=False) + "\n")
                out.flush()
                os.fsync(out.fileno())
            os.chmod(tmp, 0o600)
            os.replace(tmp, env_path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        token = set_hermes_home_override(str(profile_dir))
        try:
            cfg = load_config() or {}
            model = dict(cfg.get("model") or {}) if isinstance(cfg.get("model"), dict) else {}
            for name in ("api_key", "base_url"):
                model.pop(name, None)
            cfg["model"] = model
            save_config(cfg)
            if not connection:
                return
            provider = str(connection.get("provider") or "")
            api_key = str(connection.get("apiKey") or "").strip()
            base_url = str(connection.get("baseUrl") or "").strip()
            model_id = str(connection.get("model") or "").strip()
            if not api_key or not base_url:
                return
            hermes_provider = (
                "anthropic" if provider == "anthropic" else "openrouter" if provider == "openrouter" else "custom"
            )
            cfg = load_config() or {}
            model = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
            model = dict(model or {})
            model["provider"] = hermes_provider
            model["base_url"] = base_url
            model["api_key"] = api_key
            if model_id:
                model["default"] = model_id
            cfg["model"] = model
            save_config(cfg)
            logger.info("dashboard-auth-aimarkets: wrote buyer BYOK provider %s into %s", provider, profile)
        finally:
            reset_hermes_home_override(token)

    def _mint_session(self, *, user_id: str, username: str, profile: str) -> Session:
        now = int(time.time())
        access_payload = {
            "kind": "access",
            "sub": user_id,
            "username": username,
            "profile": profile,
            "exp": now + self._ttl,
        }
        refresh_payload = {
            "kind": "refresh",
            "sub": user_id,
            "username": username,
            "profile": profile,
            "exp": now + _REFRESH_TTL_SECONDS,
        }
        access = _sign(access_payload, self._secret)
        refresh = _sign(refresh_payload, self._secret)
        return Session(
            user_id=user_id,
            email=f"{username}@aimarkets.local",
            display_name=username,
            org_id=profile,  # locked Hermes profile name
            provider=self.name,
            expires_at=access_payload["exp"],
            access_token=access,
            refresh_token=refresh,
        )

    def verify_session(self, *, access_token: str) -> Optional[Session]:
        payload = _unsign(access_token, self._secret)
        if (
            payload is None
            or payload.get("kind") != "access"
            or payload.get("exp", 0) <= int(time.time())
        ):
            return None
        return Session(
            user_id=str(payload.get("sub") or ""),
            email=f"{payload.get('username') or 'buyer'}@aimarkets.local",
            display_name=str(payload.get("username") or payload.get("sub") or ""),
            org_id=str(payload.get("profile") or ""),
            provider=self.name,
            expires_at=int(payload.get("exp") or 0),
            access_token=access_token,
            refresh_token="",
        )

    def refresh_session(self, *, refresh_token: str) -> Session:
        if not refresh_token:
            raise RefreshExpiredError("no refresh token")
        payload = _unsign(refresh_token, self._secret)
        if (
            payload is None
            or payload.get("kind") != "refresh"
            or payload.get("exp", 0) <= int(time.time())
        ):
            raise RefreshExpiredError("refresh expired")
        return self._mint_session(
            user_id=str(payload.get("sub") or ""),
            username=str(payload.get("username") or ""),
            profile=str(payload.get("profile") or ""),
        )

    def revoke_session(self, *, access_token: str, refresh_token: str) -> None:
        return None


def register(ctx: Any) -> None:
    global LAST_SKIP_REASON
    LAST_SKIP_REASON = ""

    api = (os.environ.get("HERMES_AIMARKETS_API_URL") or "").strip()
    secret = (os.environ.get("AIMARKETS_SERVICE_SECRET") or "").strip()
    if not api or not secret:
        LAST_SKIP_REASON = (
            "HERMES_AIMARKETS_API_URL and AIMARKETS_SERVICE_SECRET are required "
            "for multi-buyer Hermes auth."
        )
        logger.debug("dashboard-auth-aimarkets: %s", LAST_SKIP_REASON)
        return

    ttl_raw = (os.environ.get("HERMES_AIMARKETS_AUTH_TTL_SECONDS") or "").strip()
    try:
        ttl = int(ttl_raw) if ttl_raw else _DEFAULT_TTL_SECONDS
    except ValueError:
        ttl = _DEFAULT_TTL_SECONDS

    provider = AimarketsAuthProvider(secret=_resolve_secret(), ttl_seconds=ttl)
    ctx.register_dashboard_auth_provider(provider)
    logger.info(
        "dashboard-auth-aimarkets: registered multi-buyer password provider "
        "(api=%s)",
        api,
    )
