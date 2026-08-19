"""Xiaomi Cloud authentication for Mi Fitness (miothealth).

Supports:
  1. Full email+password login with 2FA verification
  2. Direct userId+passToken setup (if user gets tokens from browser cookies)
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
from pathlib import Path
from typing import Any

import httpx

logger = logging.getLogger(__name__)

TOKEN_PATH = Path(__file__).resolve().parent / "data" / "xiaomi_token.json"

_HEALTH_SID = "miothealth"


def _agent() -> str:
    letters = [chr(random.randint(65, 69)) for _ in range(13)]
    rand = [chr(random.randint(97, 122)) for _ in range(18)]
    return f"{''.join(rand)}-{''.join(letters)} APP/com.xiaomi.mihome APPV/10.5.201"


def _device_id() -> str:
    return "".join(chr(random.randint(97, 122)) for _ in range(6))


def _parse(text: str) -> dict[str, Any]:
    return json.loads(text.replace("&&&START&&&", ""))


class XiaomiTokens:
    def __init__(
        self,
        user_id: str,
        pass_token: str,
        ssecurity: str = "",
        service_token: str | None = None,
        obtained_at: float | None = None,
    ):
        self.user_id = user_id
        self.pass_token = pass_token
        self.ssecurity = ssecurity
        self.service_token = service_token
        self.obtained_at = obtained_at or time.time()

    def save(self, path: Path | None = None) -> None:
        p = path or TOKEN_PATH
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(
            json.dumps(
                {
                    "user_id": self.user_id,
                    "pass_token": self.pass_token,
                    "ssecurity": self.ssecurity,
                    "service_token": self.service_token,
                    "obtained_at": self.obtained_at,
                },
                indent=2,
            ),
            encoding="utf-8",
        )

    @classmethod
    def load(cls, path: Path | None = None) -> XiaomiTokens | None:
        p = path or TOKEN_PATH
        if not p.is_file():
            return None
        data = json.loads(p.read_text(encoding="utf-8"))
        return cls(**data)

    def to_dict(self) -> dict[str, Any]:
        return {
            "user_id": self.user_id,
            "pass_token": self.pass_token,
            "ssecurity": self.ssecurity,
            "service_token": self.service_token,
            "obtained_at": self.obtained_at,
        }


# ── Pending 2FA sessions (in-memory; single-server is fine here) ──

_pending_2fa: dict[str, dict[str, Any]] = {}


class TwoFactorRequired(Exception):
    """Login succeeded but 2FA verification is needed."""

    def __init__(self, session_id: str, notification_url: str):
        self.session_id = session_id
        self.notification_url = notification_url
        super().__init__("2FA required")


async def login_xiaomi_step1(
    username: str,
    password: str,
) -> XiaomiTokens:
    """Steps 1-2 of Xiaomi login. Returns tokens or raises TwoFactorRequired."""
    agent = _agent()
    dev_id = _device_id()
    sid = _HEALTH_SID

    async with httpx.AsyncClient(follow_redirects=False, timeout=30) as client:
        r1 = await client.get(
            f"https://account.xiaomi.com/pass/serviceLogin?sid={sid}&_json=true",
            headers={"User-Agent": agent},
            cookies={"userId": username, "sdkVersion": "accountsdk-18.8.15", "deviceId": dev_id},
        )
        j1 = _parse(r1.text)
        sign = j1.get("_sign")
        callback = j1.get("callback", f"https://sts-hlth.io.mi.com/healthapp/sts")

        if not sign:
            if "ssecurity" in j1:
                tokens = XiaomiTokens(
                    user_id=str(j1["userId"]),
                    pass_token=j1.get("passToken", ""),
                    ssecurity=j1["ssecurity"],
                )
                loc = j1.get("location")
                if loc:
                    r3 = await client.get(loc, headers={"User-Agent": agent})
                    tokens.service_token = r3.cookies.get("serviceToken")
                tokens.save()
                return tokens
            raise RuntimeError(f"Xiaomi login step 1 failed: {j1}")

        pwd_hash = hashlib.md5(password.encode()).hexdigest().upper()
        r2 = await client.post(
            "https://account.xiaomi.com/pass/serviceLoginAuth2",
            headers={"User-Agent": agent, "Content-Type": "application/x-www-form-urlencoded"},
            params={
                "sid": sid,
                "hash": pwd_hash,
                "callback": callback,
                "qs": f"%3Fsid%3D{sid}%26_json%3Dtrue",
                "user": username,
                "_sign": sign,
                "_json": "true",
            },
            cookies={"sdkVersion": "accountsdk-18.8.15", "deviceId": dev_id},
        )
        j2 = _parse(r2.text)

        if j2.get("captchaUrl"):
            raise RuntimeError(
                "Xiaomi требует CAPTCHA. Попробуйте позже или введите userId + passToken вручную."
            )

        if "notificationUrl" in j2:
            session_id = dev_id
            _pending_2fa[session_id] = {
                "notification_url": j2["notificationUrl"],
                "agent": agent,
                "dev_id": dev_id,
                "cookies": dict(r2.cookies),
                "sid": sid,
                "sign": sign,
                "username": username,
                "pwd_hash": pwd_hash,
                "callback": callback,
            }
            raise TwoFactorRequired(session_id, j2["notificationUrl"])

        ssec = j2.get("ssecurity", "")
        if not ssec or len(str(ssec)) < 4:
            raise RuntimeError(f"Xiaomi login failed: {j2.get('description', j2)}")

        tokens = XiaomiTokens(
            user_id=str(j2["userId"]),
            pass_token=j2.get("passToken", ""),
            ssecurity=ssec,
        )
        loc = j2.get("location")
        if loc:
            r3 = await client.get(loc, headers={"User-Agent": agent})
            tokens.service_token = r3.cookies.get("serviceToken")
        tokens.save()
        logger.info("Xiaomi login OK (no 2FA), userId=%s", tokens.user_id)
        return tokens


async def login_xiaomi_verify(session_id: str, code: str) -> XiaomiTokens:
    """Complete 2FA verification with the code sent by email/SMS."""
    pending = _pending_2fa.pop(session_id, None)
    if not pending:
        raise RuntimeError("Сессия 2FA не найдена или истекла. Повторите вход.")

    notify_url = pending["notification_url"]
    agent = pending["agent"]

    async with httpx.AsyncClient(follow_redirects=True, timeout=30) as client:
        # Get identity_session cookie
        r_list = await client.get(notify_url.replace("identity/authStart", "identity/list"))
        identity_session = r_list.cookies.get("identity_session")
        if not identity_session:
            raise RuntimeError("Не удалось получить identity_session")

        data = {}
        try:
            data = _parse(r_list.text)
        except Exception:
            pass
        flag = data.get("flag", 4)
        options = data.get("options", [flag])

        result_data = None
        for f in options:
            api = {4: "/identity/auth/verifyPhone", 8: "/identity/auth/verifyEmail"}.get(f)
            if not api:
                continue
            r_verify = await client.post(
                "https://account.xiaomi.com" + api,
                params={"_dc": str(int(time.time() * 1000))},
                data={
                    "_flag": str(f),
                    "ticket": code,
                    "trust": "true",
                    "_json": "true",
                },
                cookies={"identity_session": identity_session},
            )
            try:
                vdata = _parse(r_verify.text)
            except Exception:
                continue
            if vdata.get("code") == 0:
                result_data = vdata
                break

        if not result_data:
            raise RuntimeError("Неверный код 2FA или истёк срок")

        location = result_data.get("location")
        if not location:
            raise RuntimeError("2FA прошла, но нет location для завершения входа")

        await client.get(location)

        # Re-do step 1 to get tokens (session should now be trusted)
        r_final = await client.get(
            f"https://account.xiaomi.com/pass/serviceLogin?sid={pending['sid']}&_json=true",
            headers={"User-Agent": agent},
            cookies={"sdkVersion": "accountsdk-18.8.15", "deviceId": pending["dev_id"]},
        )
        j_final = _parse(r_final.text)

        if "ssecurity" not in j_final:
            raise RuntimeError(f"После 2FA не удалось получить токен: {j_final.get('description', '')}")

        tokens = XiaomiTokens(
            user_id=str(j_final["userId"]),
            pass_token=j_final.get("passToken", ""),
            ssecurity=j_final["ssecurity"],
        )
        loc = j_final.get("location")
        if loc:
            r3 = await client.get(loc, headers={"User-Agent": agent})
            tokens.service_token = r3.cookies.get("serviceToken")
        tokens.save()
        logger.info("Xiaomi login OK (after 2FA), userId=%s", tokens.user_id)
        return tokens


async def login_xiaomi(username: str, password: str) -> XiaomiTokens:
    """Convenience wrapper — raises TwoFactorRequired if 2FA needed."""
    return await login_xiaomi_step1(username, password)


async def setup_tokens_direct(user_id: str, pass_token: str) -> XiaomiTokens:
    """Set up tokens directly from userId + passToken (from browser cookies).
    
    Obtains a serviceToken for miothealth using the passToken.
    """
    agent = _agent()
    async with httpx.AsyncClient(follow_redirects=False, timeout=30) as client:
        r = await client.get(
            f"https://account.xiaomi.com/pass/serviceLogin?sid={_HEALTH_SID}&_json=true",
            headers={"User-Agent": agent},
            cookies={
                "userId": user_id,
                "passToken": pass_token,
                "sdkVersion": "accountsdk-18.8.15",
            },
        )
        j = _parse(r.text)
        ssec = j.get("ssecurity", "")
        loc = j.get("location")
        st = None
        if loc:
            r2 = await client.get(loc, headers={"User-Agent": agent})
            st = r2.cookies.get("serviceToken")

    tokens = XiaomiTokens(
        user_id=user_id,
        pass_token=pass_token,
        ssecurity=ssec,
        service_token=st,
    )
    tokens.save()
    logger.info("Xiaomi tokens set directly, userId=%s, serviceToken=%s", user_id, bool(st))
    return tokens
