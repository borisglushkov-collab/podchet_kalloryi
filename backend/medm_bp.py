"""MedM Blood Pressure cloud API integration.

Login with email+password → fetch blood pressure measurements.
API docs: https://health.medm.com/docs/api/v3/
"""

from __future__ import annotations

import json
import logging
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import httpx

logger = logging.getLogger(__name__)

_API_BASE = "https://health.medm.com/api/v3"
_TOKEN_PATH = Path(__file__).resolve().parent / "data" / "medm_token.json"


class MedMTokens:
    def __init__(
        self,
        auth_token: str,
        refresh_token: str,
        obtained_at: float | None = None,
    ):
        self.auth_token = auth_token
        self.refresh_token = refresh_token
        self.obtained_at = obtained_at or time.time()

    def save(self) -> None:
        _TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        _TOKEN_PATH.write_text(
            json.dumps({
                "auth_token": self.auth_token,
                "refresh_token": self.refresh_token,
                "obtained_at": self.obtained_at,
            }, indent=2),
            encoding="utf-8",
        )

    @classmethod
    def load(cls) -> MedMTokens | None:
        if not _TOKEN_PATH.is_file():
            return None
        data = json.loads(_TOKEN_PATH.read_text(encoding="utf-8"))
        return cls(**data)

    @property
    def is_expired(self) -> bool:
        return (time.time() - self.obtained_at) > 25 * 60  # 25 min (token lasts 30)


async def medm_login(email: str, password: str) -> MedMTokens:
    """Login to MedM and get auth + refresh tokens."""
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(
            f"{_API_BASE}/user/login",
            json={"email": email, "password": password},
            headers={"Accept": "application/json", "Content-Type": "application/json"},
        )
        r.raise_for_status()
        data = r.json()

    auth = data.get("auth-token") or data.get("auth_token")
    refresh = data.get("refresh-token") or data.get("refresh_token")
    if not auth:
        raise RuntimeError(f"MedM login failed: {data}")

    tokens = MedMTokens(auth_token=auth, refresh_token=refresh or "")
    tokens.save()
    logger.info("MedM login OK")
    return tokens


async def medm_refresh(tokens: MedMTokens) -> MedMTokens:
    """Refresh expired auth token."""
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(
            f"{_API_BASE}/user/refresh_token",
            json={"refresh_token": tokens.refresh_token},
            headers={"Accept": "application/json", "Content-Type": "application/json"},
        )
        r.raise_for_status()
        data = r.json()

    auth = data.get("auth-token") or data.get("auth_token")
    refresh = data.get("refresh-token") or data.get("refresh_token")
    if not auth:
        raise RuntimeError(f"MedM refresh failed: {data}")

    new_tokens = MedMTokens(auth_token=auth, refresh_token=refresh or tokens.refresh_token)
    new_tokens.save()
    return new_tokens


async def _get_valid_tokens() -> MedMTokens | None:
    """Load tokens and refresh if expired."""
    tokens = MedMTokens.load()
    if not tokens:
        return None
    if tokens.is_expired and tokens.refresh_token:
        try:
            tokens = await medm_refresh(tokens)
        except Exception as exc:
            logger.warning("MedM refresh failed: %s", exc)
            return None
    return tokens


async def fetch_bp_readings(
    *,
    since: date | None = None,
    limit: int = 100,
) -> list[dict[str, Any]]:
    """Fetch blood pressure readings from MedM cloud.
    
    Returns list of dicts with systolic, diastolic, pulse, measured_at.
    """
    tokens = await _get_valid_tokens()
    if not tokens:
        return []

    params: dict[str, str] = {"per_page": str(limit)}
    if since:
        params["measured_after"] = since.isoformat() + "T00:00:00Z"

    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.get(
            f"{_API_BASE}/patient/measurements/bloodpressures",
            params=params,
            headers={
                "Authorization": f"Bearer {tokens.auth_token}",
                "Accept": "application/json",
            },
        )
        if r.status_code == 401:
            # Try refresh
            if tokens.refresh_token:
                try:
                    tokens = await medm_refresh(tokens)
                    r = await c.get(
                        f"{_API_BASE}/patient/measurements/bloodpressures",
                        params=params,
                        headers={
                            "Authorization": f"Bearer {tokens.auth_token}",
                            "Accept": "application/json",
                        },
                    )
                except Exception:
                    return []
        r.raise_for_status()
        data = r.json()

    # MedM returns XML-style keys in JSON
    items = data if isinstance(data, list) else data.get("measurements-bloodpressures") or data.get("measurements") or []
    
    readings = []
    for item in items:
        if isinstance(item, dict):
            bp = item.get("measurements-bloodpressure") or item
            readings.append({
                "systolic": bp.get("systolic"),
                "diastolic": bp.get("diastolic"),
                "pulse": bp.get("pulse"),
                "measured_at": bp.get("measured-at") or bp.get("measured_at") or bp.get("measured-at-local"),
                "source": "medm_bp",
                "note": bp.get("note") or bp.get("comment") or "",
            })
    return readings
