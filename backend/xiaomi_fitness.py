"""Fetch health data from Mi Fitness Cloud using encrypted API.

Uses the same protocol as mi-fitness-mcp: RC4-encrypted requests
with signed nonces against hlth.io.mi.com.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import os
import struct
import time as _time
from datetime import date, datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlencode

import httpx

from xiaomi_auth import XiaomiTokens

logger = logging.getLogger(__name__)

# ── RC4 + crypto (adapted from mi-fitness-mcp xiaomi_crypto.py) ──


def _rc4_crypt(key: bytes, payload: bytes) -> bytes:
    state = list(range(256))
    j = 0
    kl = len(key)
    for i in range(256):
        j = (j + state[i] + key[i % kl]) % 256
        state[i], state[j] = state[j], state[i]
    i = j = 0

    def _next() -> int:
        nonlocal i, j
        i = (i + 1) % 256
        j = (j + state[i]) % 256
        state[i], state[j] = state[j], state[i]
        return state[(state[i] + state[j]) % 256]

    for _ in range(1024):
        _next()
    return bytes(v ^ _next() for v in payload)


def _gen_nonce() -> bytes:
    raw = bytearray(os.urandom(8))
    raw.extend(struct.pack(">I", int(_time.time() // 60)))
    return bytes(raw)


def _signed_nonce(ssecurity: bytes, nonce: bytes) -> bytes:
    return hashlib.sha256(ssecurity + nonce).digest()


def _signature(method: str, path: str, values: dict[str, str], snonce: bytes) -> str:
    base = method + "&" + path + "&data=" + values["data"]
    if "rc4_hash__" in values:
        base += "&rc4_hash__=" + values["rc4_hash__"]
    base += "&" + base64.b64encode(snonce).decode()
    return base64.b64encode(hashlib.sha1(base.encode()).digest()).decode()


def _encrypt_form(
    method: str, path: str, payload: dict[str, Any], ssecurity: bytes, nonce: bytes
) -> str:
    snonce = _signed_nonce(ssecurity, nonce)
    form = {"data": json.dumps(payload, separators=(",", ":"))}
    form["rc4_hash__"] = _signature(method, path, form, snonce)
    encrypted = {
        k: base64.b64encode(_rc4_crypt(snonce, v.encode())).decode()
        for k, v in form.items()
    }
    encrypted["signature"] = _signature(method, path, encrypted, snonce)
    encrypted["_nonce"] = base64.b64encode(nonce).decode()
    return urlencode(encrypted)


# ── Login + API ──

_KNOWN_REGIONS = ["ru", "cn", "de", "i2", "sg", "us"]
_LOGIN_PREFIX = b"&&&START&&&"


def _parse_login(text: str) -> dict[str, Any]:
    raw = text.encode()
    if raw.startswith(_LOGIN_PREFIX):
        raw = raw[len(_LOGIN_PREFIX):]
    return json.loads(raw)


class MiFitnessClient:
    """Async client for Mi Fitness Cloud (encrypted API)."""

    def __init__(self, tokens: XiaomiTokens, *, region: str = "ru"):
        self._user_id = tokens.user_id
        self._pass_token = tokens.pass_token
        self._ssecurity = base64.b64decode(tokens.ssecurity) if tokens.ssecurity else b""
        self._cookies = ""
        self._region = region
        self._connected = False

    def _base_url(self, region: str | None = None) -> str:
        r = region or self._region
        if r in ("", "cn"):
            return "https://hlth.io.mi.com"
        return f"https://{r}.hlth.io.mi.com"

    async def connect(self) -> None:
        """Authenticate using passToken and get session cookies."""
        async with httpx.AsyncClient(timeout=30, follow_redirects=False) as c:
            r = await c.get(
                "https://account.xiaomi.com/pass/serviceLogin?_json=true&sid=miothealth",
                headers={"Cookie": f"userId={self._user_id}; passToken={self._pass_token}"},
            )
            r.raise_for_status()
            j = _parse_login(r.text)

            pt = j.get("passToken")
            uid = j.get("userId")
            ss = j.get("ssecurity")
            loc = j.get("location")
            if not pt or not uid or not ss or not loc:
                raise RuntimeError(f"Mi Fitness login failed: {j.get('description', 'unknown')}")

            self._user_id = str(uid)
            self._pass_token = str(pt)
            self._ssecurity = base64.b64decode(str(ss))

            redir = await c.get(str(loc))
            redir.raise_for_status()
            cookie_parts = [v.split(";", 1)[0] for v in redir.headers.get_list("set-cookie")]
            self._cookies = "; ".join(cookie_parts)
            if not self._cookies:
                raise RuntimeError("Mi Fitness login: no session cookies returned")
            self._connected = True
            logger.info("Mi Fitness connected, userId=%s", self._user_id)

    async def _request(self, path: str, payload: dict[str, Any], *, region: str | None = None) -> dict[str, Any]:
        if not self._connected:
            await self.connect()

        base = self._base_url(region)
        nonce = _gen_nonce()
        snonce = _signed_nonce(self._ssecurity, nonce)
        content = _encrypt_form("POST", path, payload, self._ssecurity, nonce)

        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.post(
                base + path,
                headers={
                    "Cookie": self._cookies,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
                content=content,
            )
            r.raise_for_status()
            plaintext = _rc4_crypt(snonce, base64.b64decode(r.text))
            body = json.loads(plaintext)
            if body.get("code") != 0:
                raise RuntimeError(f"Mi Fitness API error: {body.get('message', body)}")
            return body.get("result", {})

    async def fetch_key(
        self, key: str, start_date: date, end_date: date
    ) -> list[dict[str, Any]]:
        tz = timezone(timedelta(hours=3))  # Moscow
        start_ts = int(datetime.combine(start_date, datetime.min.time(), tzinfo=tz).timestamp())
        end_ts = int(datetime.combine(end_date, datetime.max.time().replace(microsecond=0), tzinfo=tz).timestamp())

        items: list[dict[str, Any]] = []
        next_key: str | None = None

        for _ in range(10):
            payload: dict[str, Any] = {
                "start_time": start_ts,
                "end_time": end_ts,
                "key": key,
            }
            if next_key:
                payload["next_key"] = next_key

            result = await self._request("/app/v1/data/get_fitness_data_by_time", payload)
            items.extend(result.get("data_list", []))
            if not result.get("has_more"):
                break
            next_key = result.get("next_key")
            if not next_key:
                break

        return items

    async def get_today_summary(self) -> dict[str, Any]:
        today = date.today()
        yesterday = today - timedelta(days=1)
        result: dict[str, Any] = {"date": today.isoformat()}

        for key in ("steps", "sleep", "weight", "heart_rate", "blood_pressure"):
            try:
                start = yesterday if key == "sleep" else today
                items = await self.fetch_key(key, start, today)
                result[key] = items
                logger.info("Mi Fitness %s: %d items", key, len(items))
            except Exception as exc:
                logger.warning("Mi Fitness fetch %s failed: %s", key, exc)
                result[key] = []

        return result

    async def get_range_summary(self, start_date: date, end_date: date) -> dict[str, Any]:
        result: dict[str, Any] = {"start": start_date.isoformat(), "end": end_date.isoformat()}
        for key in ("steps", "sleep", "weight", "heart_rate", "blood_pressure"):
            try:
                items = await self.fetch_key(key, start_date, end_date)
                result[key] = items
            except Exception as exc:
                logger.warning("Mi Fitness range fetch %s: %s", key, exc)
                result[key] = []
        return result
