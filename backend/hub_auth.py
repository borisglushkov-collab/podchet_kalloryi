"""Hub PIN session: signed cookie required for /api/health/* when HUB_PIN is set."""

from __future__ import annotations

import hashlib
import hmac
import os
import time
from typing import Final

COOKIE_NAME: Final = "hub_session"
TTL_SEC: Final = 60 * 60 * 24 * 14  # 14 days


def pin_configured() -> bool:
    return bool((os.getenv("HUB_PIN") or "").strip())


def _secret() -> bytes:
    raw = (os.getenv("HUB_SESSION_SECRET") or os.getenv("HUB_PIN") or "hub-dev-secret").strip()
    return raw.encode("utf-8")


def expected_pin() -> str:
    return (os.getenv("HUB_PIN") or "").strip()


def issue_token(now: float | None = None) -> str:
    ts = int(now if now is not None else time.time())
    payload = f"hub|{ts}"
    sig = hmac.new(_secret(), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return f"{ts}.{sig}"


def token_valid(token: str | None, now: float | None = None) -> bool:
    if not token or "." not in token:
        return False
    ts_s, sig = token.split(".", 1)
    try:
        ts = int(ts_s)
    except ValueError:
        return False
    current = now if now is not None else time.time()
    if current - ts > TTL_SEC or ts > current + 60:
        return False
    payload = f"hub|{ts}"
    expected = hmac.new(_secret(), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)


def path_is_public(path: str) -> bool:
    return path in {"/api/health/gate", "/api/health/unlock"}
