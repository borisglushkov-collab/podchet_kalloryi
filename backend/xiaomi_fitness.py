"""Fetch health data from Mi Fitness Cloud (hlth.io.mi.com).

Uses userId + serviceToken obtained via xiaomi_auth.
Supports: steps, sleep, weight, heart_rate, blood_pressure.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import random
import time
from datetime import date, datetime, timedelta, timezone
from typing import Any

import httpx

from xiaomi_auth import XiaomiTokens

logger = logging.getLogger(__name__)

_REGIONS = {
    "ru": "https://api-mifit-ru.huami.com",
    "us": "https://api-mifit-us2.huami.com",
    "de": "https://api-mifit-de.huami.com",
    "cn": "https://hlth.io.mi.com",
    "sg": "https://api-mifit-sg.huami.com",
}

_DATA_KEYS = {
    "steps": "steps",
    "sleep": "sleep",
    "weight": "weight",
    "heart_rate": "heart_rate",
    "blood_pressure": "blood_pressure",
    "calories": "calories",
    "spo2": "spo2",
}

_PROFILE_URL = "/api/v1/user/me"
_DATA_URL = "/app/v1/data/get_fitness_data_by_time"


class MiFitnessClient:
    """Thin async wrapper around Mi Fitness HTTP API."""

    def __init__(self, tokens: XiaomiTokens, *, region: str = "ru"):
        self.tokens = tokens
        base = _REGIONS.get(region)
        if not base:
            base = _REGIONS["ru"]
        self._base = base

    def _headers(self) -> dict[str, str]:
        h: dict[str, str] = {
            "User-Agent": "MiFit/6.5.0 (Android; SDK 33; arm64-v8a)",
            "Content-Type": "application/x-www-form-urlencoded",
        }
        if self.tokens.service_token:
            h["apptoken"] = self.tokens.service_token
        return h

    def _cookies(self) -> dict[str, str]:
        c: dict[str, str] = {"userId": str(self.tokens.user_id)}
        if self.tokens.service_token:
            c["serviceToken"] = self.tokens.service_token
        if self.tokens.pass_token:
            c["passToken"] = self.tokens.pass_token
        return c

    async def get_profile(self) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.get(
                self._base + _PROFILE_URL,
                headers=self._headers(),
                cookies=self._cookies(),
            )
            r.raise_for_status()
            return r.json()

    async def get_data(
        self,
        key: str,
        start_date: date | None = None,
        end_date: date | None = None,
    ) -> list[dict[str, Any]]:
        """Fetch fitness data by key for a date range.

        Returns raw items list from the API.
        """
        if key not in _DATA_KEYS:
            raise ValueError(f"Unknown key: {key}. Valid: {list(_DATA_KEYS)}")

        end = end_date or date.today()
        start = start_date or (end - timedelta(days=7))

        start_ts = int(datetime.combine(start, datetime.min.time(), tzinfo=timezone.utc).timestamp())
        end_ts = int(datetime.combine(end, datetime.max.time().replace(microsecond=0), tzinfo=timezone.utc).timestamp())

        payload = {
            "start_time": str(start_ts),
            "end_time": str(end_ts),
            "key": _DATA_KEYS[key],
        }

        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.post(
                self._base + _DATA_URL,
                headers=self._headers(),
                cookies=self._cookies(),
                data=payload,
            )
            r.raise_for_status()
            body = r.json()

        items = body.get("data", {}).get("items") or body.get("items") or []
        if not items and isinstance(body.get("data"), list):
            items = body["data"]
        return items

    async def get_today_summary(self) -> dict[str, Any]:
        """Convenience: fetch steps, sleep, weight, heart_rate, bp for today."""
        today = date.today()
        yesterday = today - timedelta(days=1)
        result: dict[str, Any] = {"date": today.isoformat()}
        for key in ("steps", "sleep", "weight", "heart_rate", "blood_pressure"):
            try:
                start = yesterday if key == "sleep" else today
                items = await self.get_data(key, start_date=start, end_date=today)
                result[key] = items
            except Exception as exc:
                logger.warning("Mi Fitness: failed to fetch %s: %s", key, exc)
                result[key] = []
        return result

    async def get_range_summary(
        self, start_date: date, end_date: date
    ) -> dict[str, Any]:
        result: dict[str, Any] = {
            "start": start_date.isoformat(),
            "end": end_date.isoformat(),
        }
        for key in ("steps", "sleep", "weight", "heart_rate", "blood_pressure"):
            try:
                items = await self.get_data(key, start_date=start_date, end_date=end_date)
                result[key] = items
            except Exception as exc:
                logger.warning("Mi Fitness range: failed %s: %s", key, exc)
                result[key] = []
        return result
