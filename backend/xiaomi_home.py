"""Fetch device data from Xiaomi Home (Mi Home / Mijia) cloud.

Uses the same userId + passToken as Mi Fitness, but authenticates
against the `xiaomiio` service to access IoT device data (scales, BP monitors, etc.).
Uses RC4-encrypted requests (same protocol as Mi Fitness).
"""

from __future__ import annotations

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

# ── Same RC4 crypto as xiaomi_fitness.py ──


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
    base = method + "&" + path
    for k, v in sorted(values.items()):
        base += f"&{k}={v}"
    base += "&" + base64.b64encode(snonce).decode()
    return base64.b64encode(hashlib.sha1(base.encode()).digest()).decode()


def _encrypt_form(
    method: str, path: str, payload: dict[str, str], ssecurity: bytes, nonce: bytes
) -> str:
    snonce = _signed_nonce(ssecurity, nonce)
    form = dict(payload)
    form["rc4_hash__"] = _signature(method, path, form, snonce)
    encrypted = {
        k: base64.b64encode(_rc4_crypt(snonce, v.encode())).decode()
        for k, v in form.items()
    }
    encrypted["signature"] = _signature(method, path, encrypted, snonce)
    encrypted["_nonce"] = base64.b64encode(nonce).decode()
    return urlencode(encrypted)


_LOGIN_PREFIX = b"&&&START&&&"
_IOT_REGIONS = {
    "ru": "https://ru.api.io.mi.com/app",
    "cn": "https://api.io.mi.com/app",
    "de": "https://de.api.io.mi.com/app",
    "us": "https://us.api.io.mi.com/app",
    "sg": "https://sg.api.io.mi.com/app",
    "i2": "https://i2.api.io.mi.com/app",
}


def _parse_login(text: str) -> dict[str, Any]:
    raw = text.encode()
    if raw.startswith(_LOGIN_PREFIX):
        raw = raw[len(_LOGIN_PREFIX):]
    return json.loads(raw)


class XiaomiHomeClient:
    """Async client for Xiaomi Home / Mijia IoT cloud (encrypted API)."""

    def __init__(self, tokens: XiaomiTokens, *, region: str = "ru"):
        self._user_id = tokens.user_id
        self._pass_token = tokens.pass_token
        self._ssecurity = b""
        self._cookies = ""
        self._region = region
        self._connected = False

    def _base_url(self) -> str:
        return _IOT_REGIONS.get(self._region, _IOT_REGIONS["ru"])

    async def connect(self) -> None:
        """Authenticate using passToken for the xiaomiio service."""
        async with httpx.AsyncClient(timeout=30, follow_redirects=False) as c:
            r = await c.get(
                "https://account.xiaomi.com/pass/serviceLogin?_json=true&sid=xiaomiio",
                headers={"Cookie": f"userId={self._user_id}; passToken={self._pass_token}"},
            )
            r.raise_for_status()
            j = _parse_login(r.text)

            if not j.get("ssecurity") or not j.get("location"):
                raise RuntimeError(f"Xiaomi Home login failed: {j.get('description', 'unknown')}")

            self._ssecurity = base64.b64decode(str(j["ssecurity"]))
            loc = str(j["location"])

            redir = await c.get(loc)
            redir.raise_for_status()
            cookie_parts = [v.split(";", 1)[0] for v in redir.headers.get_list("set-cookie")]
            self._cookies = "; ".join(cookie_parts)
            if not self._cookies:
                raise RuntimeError("Xiaomi Home login: no session cookies")
            self._connected = True
            logger.info("Xiaomi Home connected, userId=%s, region=%s", self._user_id, self._region)

    async def _request(self, path: str, params: dict[str, str], *, extra_headers: dict[str, str] | None = None) -> dict[str, Any]:
        if not self._connected:
            await self.connect()

        base = self._base_url()
        nonce = _gen_nonce()
        snonce = _signed_nonce(self._ssecurity, nonce)
        content = _encrypt_form("POST", path, params, self._ssecurity, nonce)

        headers: dict[str, str] = {
            "Cookie": self._cookies,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept-Encoding": "identity",
            "x-xiaomi-protocal-flag-cli": "PROTOCAL-HTTP2",
            "MIOT-ENCRYPT-ALGORITHM": "ENCRYPT-RC4",
        }
        if extra_headers:
            headers.update(extra_headers)

        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.post(base + path, headers=headers, content=content)
            r.raise_for_status()
            plaintext = _rc4_crypt(snonce, base64.b64decode(r.text))
            body = json.loads(plaintext)
            return body

    async def get_homes(self) -> list[dict[str, Any]]:
        result = await self._request(
            "/v2/homeroom/gethome",
            {"data": json.dumps({"fg": True, "fetch_share": True, "fetch_share_dev": True, "limit": 300, "app_ver": 7}, separators=(",", ":"))},
        )
        return result.get("result", {}).get("homelist", [])

    async def get_devices(self, home_id: int, owner_id: int) -> list[dict[str, Any]]:
        result = await self._request(
            "/v2/home/home_device_list",
            {"data": json.dumps({"home_owner": owner_id, "home_id": home_id, "limit": 200, "get_split_device": True, "support_smart_home": True}, separators=(",", ":"))},
        )
        return result.get("result", {}).get("device_info", []) or []

    async def get_all_devices(self) -> list[dict[str, Any]]:
        """Get all devices across all homes."""
        homes = await self.get_homes()
        all_devices: list[dict[str, Any]] = []
        for home in homes:
            try:
                devices = await self.get_devices(home["id"], int(self._user_id))
                all_devices.extend(devices)
            except Exception as exc:
                logger.warning("Failed to get devices for home %s: %s", home.get("id"), exc)
        return all_devices

    async def get_scale_data(self, model: str = "", *, page_size: int = 200) -> list[dict[str, Any]]:
        """Fetch weight/body composition from eco/scale subsystem.
        
        The eco/scale API uses the same RC4 encryption as other MIoT
        endpoints, but the model is passed as an unencrypted form param
        appended after the encrypted payload.
        """
        if not self._connected:
            await self.connect()

        base = self._base_url()
        path = "/eco/common/scale/getUserDataByPage"

        payload = {
            "uid": self._user_id,
            "pageNum": 1,
            "pageSize": page_size,
            "startTime": 0,
        }

        nonce = _gen_nonce()
        snonce = _signed_nonce(self._ssecurity, nonce)

        data_json = json.dumps(payload, separators=(",", ":"))
        form = {"data": data_json}
        sig_base = "POST&" + path + "&data=" + form["data"]
        if "rc4_hash__" in form:
            sig_base += "&rc4_hash__=" + form["rc4_hash__"]
        sig_base += "&" + base64.b64encode(snonce).decode()
        form["rc4_hash__"] = base64.b64encode(hashlib.sha1(sig_base.encode()).digest()).decode()

        encrypted = {
            k: base64.b64encode(_rc4_crypt(snonce, v.encode())).decode()
            for k, v in form.items()
        }
        sig_base2 = "POST&" + path
        for k, v in sorted(encrypted.items()):
            sig_base2 += f"&{k}={v}"
        sig_base2 += "&" + base64.b64encode(snonce).decode()
        encrypted["signature"] = base64.b64encode(hashlib.sha1(sig_base2.encode()).digest()).decode()
        encrypted["_nonce"] = base64.b64encode(nonce).decode()

        content = urlencode(encrypted)
        if model:
            content += f"&model={model}"

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
            logger.warning("Scale API: %s", body.get("message", body))
            return []

        data = body.get("result", {})
        if isinstance(data, dict):
            return data.get("dataList") or data.get("list") or []
        if isinstance(data, list):
            return data
        return []

    async def get_device_data(self, did: str, *, data_type: str = "", limit: int = 50) -> list[dict[str, Any]]:
        """Generic device data fetch via MIoT endpoint."""
        result = await self._request(
            "/user/get_user_device_data",
            {
                "data": json.dumps({
                    "did": did,
                    "type": data_type,
                    "key": "",
                    "time_start": 0,
                    "time_end": int(_time.time()),
                    "limit": limit,
                }, separators=(",", ":")),
            },
        )
        return result.get("result", [])
