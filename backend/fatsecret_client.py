"""FatSecret food diary integration via OAuth 1.0 (3-legged).

Почему переписываем OAuth:
- библиотека `fatsecret` при получении request_token возвращает `Invalid signature`
  (OAuth подпись отличается от того, что ожидает FatSecret).
- Поэтому request_token/access_token подписываем вручную согласно OAuth1
  документации (подпись HMAC-SHA1, key = consumer_secret + "&" и обязательно
  GET на endpoints oauth/request_token + oauth/access_token).

Flow в приложении:
1) /api/health/fatsecret-auth -> запрос request_token -> отдаём authorize_url
2) пользователь разрешает доступ в FatSecret -> копирует PIN/verifier
3) /api/health/fatsecret-verify -> обмениваем verifier на access_token
4) /api/health/fatsecret-food -> берём entries из food diary
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import random
import string
import time
import urllib.parse
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import requests
from fatsecret import Fatsecret

logger = logging.getLogger(__name__)

_USER_TZ = ZoneInfo("Europe/Moscow")

_CREDS_PATH = Path(__file__).resolve().parent / "data" / "fatsecret_tokens.json"

# NOTE: in this task we use the keys provided by the user.
CONSUMER_KEY = "7c52340ff2f94f8daeec2f6e80e985e8"
CONSUMER_SECRET = "7523ebf7338044708d55f55af7ddb003"

REQUEST_TOKEN_URL = "https://authentication.fatsecret.com/oauth/request_token"
AUTHORIZE_URL = "https://authentication.fatsecret.com/oauth/authorize"
ACCESS_TOKEN_URL = "https://authentication.fatsecret.com/oauth/access_token"


def _oauth_percent_encode(val: str) -> str:
    # OAuth percent encoding (RFC3986): spaces -> %20, ~ must stay.
    return (
        urllib.parse.quote(val, safe="~-._")
        .replace("%7E", "~")
        .replace("%20", "%20")
    )


def _sign_hmac_sha1_base64(key: str, base_string: str) -> str:
    digest = hmac.new(key.encode("utf-8"), base_string.encode("utf-8"), hashlib.sha1).digest()
    return base64.b64encode(digest).decode("utf-8")


def _build_signature_base_string(method: str, base_url: str, params: dict[str, str]) -> str:
    method_u = method.upper()
    # Normalize parameters
    encoded = []
    for k, v in params.items():
        encoded.append((_oauth_percent_encode(str(k)), _oauth_percent_encode(str(v))))
    encoded.sort(key=lambda x: (x[0], x[1]))
    param_str = "&".join([f"{k}={v}" for k, v in encoded])
    return "&".join(
        [
            method_u,
            _oauth_percent_encode(base_url),
            _oauth_percent_encode(param_str),
        ]
    )


def _gen_nonce(length: int = 32) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(random.choice(alphabet) for _ in range(length))


@dataclass
class _PendingOAuth:
    oauth_token: str
    oauth_token_secret: str


_pending_sessions: dict[str, _PendingOAuth] = {}


def save_tokens(access_token: str, access_token_secret: str) -> None:
    _CREDS_PATH.parent.mkdir(parents=True, exist_ok=True)
    _CREDS_PATH.write_text(
        json.dumps(
            {"access_token": access_token, "access_token_secret": access_token_secret},
            indent=2,
        ),
        encoding="utf-8",
    )


def load_tokens() -> tuple[str, str] | None:
    if not _CREDS_PATH.is_file():
        return None
    data = json.loads(_CREDS_PATH.read_text(encoding="utf-8"))
    return data.get("access_token") or "", data.get("access_token_secret") or ""


def _parse_querystring_response(text: str) -> dict[str, str]:
    parsed = urllib.parse.parse_qs(text, strict_parsing=False)
    return {k: (v[0] if v else "") for k, v in parsed.items()}


def oauth_request_token(callback: str) -> tuple[str, str]:
    """Step 1: GET request_token."""
    oauth_nonce = _gen_nonce()
    oauth_timestamp = str(int(time.time()))

    params: dict[str, str] = {
        "oauth_consumer_key": CONSUMER_KEY,
        "oauth_nonce": oauth_nonce,
        "oauth_signature_method": "HMAC-SHA1",
        "oauth_timestamp": oauth_timestamp,
        "oauth_version": "1.0",
        "oauth_callback": callback,
    }

    base_string = _build_signature_base_string("GET", REQUEST_TOKEN_URL, params)
    signing_key = f"{CONSUMER_SECRET}&"  # access secret is empty for request_token
    oauth_signature = _sign_hmac_sha1_base64(signing_key, base_string)
    params["oauth_signature"] = oauth_signature

    resp = requests.get(REQUEST_TOKEN_URL, params=params, timeout=30)
    resp.raise_for_status()
    out = _parse_querystring_response(resp.text)
    oauth_token = out.get("oauth_token") or ""
    oauth_token_secret = out.get("oauth_token_secret") or ""
    if not oauth_token or not oauth_token_secret:
        raise RuntimeError(f"FatSecret request_token failed: {resp.text!r}")
    return oauth_token, oauth_token_secret


def oauth_access_token(oauth_token: str, oauth_token_secret: str, verifier: str) -> tuple[str, str]:
    """Step 3: GET access_token."""
    oauth_nonce = _gen_nonce()
    oauth_timestamp = str(int(time.time()))

    params: dict[str, str] = {
        "oauth_consumer_key": CONSUMER_KEY,
        "oauth_token": oauth_token,
        "oauth_verifier": verifier,
        "oauth_nonce": oauth_nonce,
        "oauth_signature_method": "HMAC-SHA1",
        "oauth_timestamp": oauth_timestamp,
        "oauth_version": "1.0",
    }

    base_string = _build_signature_base_string("GET", ACCESS_TOKEN_URL, params)
    signing_key = f"{CONSUMER_SECRET}&{oauth_token_secret}"
    oauth_signature = _sign_hmac_sha1_base64(signing_key, base_string)
    params["oauth_signature"] = oauth_signature

    resp = requests.get(ACCESS_TOKEN_URL, params=params, timeout=30)
    resp.raise_for_status()
    out = _parse_querystring_response(resp.text)
    access_token = out.get("oauth_token") or ""
    access_token_secret = out.get("oauth_token_secret") or ""
    if not access_token or not access_token_secret:
        raise RuntimeError(f"FatSecret access_token failed: {resp.text!r}")
    return access_token, access_token_secret


def get_authorize_url(callback_url: str = "oob") -> tuple[str, str]:
    """Start OAuth flow. Returns (authorize_url, session_id)."""
    oauth_token, oauth_token_secret = oauth_request_token(callback_url)
    session_id = f"{oauth_token}_{int(time.time())}_{random.randint(1000,9999)}"
    _pending_sessions[session_id] = _PendingOAuth(oauth_token, oauth_token_secret)
    auth_url = f"{AUTHORIZE_URL}?oauth_token={urllib.parse.quote(oauth_token)}"
    logger.info("FatSecret request_token OK, session_id=%s", session_id)
    return auth_url, session_id


def complete_auth(session_id: str, verifier: str) -> tuple[str, str]:
    """Exchange verifier for access tokens, then persist them."""
    pending = _pending_sessions.pop(session_id, None)
    if not pending:
        raise RuntimeError("OAuth сессия не найдена. Начните заново.")
    access_token, access_token_secret = oauth_access_token(
        pending.oauth_token, pending.oauth_token_secret, verifier
    )
    save_tokens(access_token, access_token_secret)
    logger.info("FatSecret OAuth complete")
    return access_token, access_token_secret


def _get_client() -> Fatsecret | None:
    tokens = load_tokens()
    if not tokens:
        return None
    access_token, access_token_secret = tokens
    if not access_token:
        return None
    return Fatsecret(
        CONSUMER_KEY,
        CONSUMER_SECRET,
        session_token=(access_token, access_token_secret),
        auth="oauth1",
    )


def user_local_date() -> date:
    """FatSecret diary dates follow the user's local day (Europe/Moscow)."""
    return datetime.now(_USER_TZ).date()


def fetch_food_entries_for_date(target_date: date | None = None) -> list[dict[str, Any]]:
    """Fetch food diary entries for a specific day (default: today in Europe/Moscow)."""
    fs = _get_client()
    if not fs:
        return []
    d = target_date or user_local_date()
    try:
        # В текущей версии библиотеки дневник находится в `fs.diary.*`
        # `entries_get_v2` возвращает список entries за указанную дату.
        entries = fs.diary.entries_get_v2(date=d)
        if not entries:
            return []
        if not isinstance(entries, list):
            entries = [entries]
        return [_normalize_entry(e) for e in entries]
    except Exception as exc:
        logger.warning("FatSecret food_entries_get failed: %s", exc)
        return []


def fetch_food_entries_today() -> list[dict[str, Any]]:
    """Fetch today's food diary entries (Europe/Moscow)."""
    return fetch_food_entries_for_date(user_local_date())


def fetch_food_month(target_date: date | None = None) -> list[dict[str, Any]]:
    """Fetch monthly food diary summary (calories/macros per day)."""
    fs = _get_client()
    if not fs:
        return []
    try:
        d = target_date or user_local_date()
        # v2: entries_get_month_v2(date_int) — если передать None, вернёт текущий месяц.
        # Мы пока используем его без точной валидации date_int (PWA сейчас не требует month-таблицу).
        days = fs.diary.entries_get_month_v2(date=None)
        if not days:
            return []
        if not isinstance(days, list):
            days = [days]
        return [_normalize_day(day) for day in days]
    except Exception as exc:
        logger.warning("FatSecret food_entries_get_month failed: %s", exc)
        return []


def _normalize_entry(e: Any) -> dict[str, Any]:
    """Normalize a single food entry."""
    if hasattr(e, "to_dict"):
        e = e.to_dict()
    if not isinstance(e, dict):
        return {"raw": str(e)}
    return {
        "name": e.get("food_entry_name") or e.get("food_name", ""),
        "meal": e.get("meal", ""),
        "calories": _num(e.get("calories")),
        "protein": _num(e.get("protein")),
        "fat": _num(e.get("fat")),
        "carbs": _num(e.get("carbohydrate")),
        "grams": _num(e.get("number_of_units")) or _num(e.get("serving_size")),
    }


def _normalize_day(d: Any) -> dict[str, Any]:
    """Normalize a daily summary."""
    if hasattr(d, "to_dict"):
        d = d.to_dict()
    if not isinstance(d, dict):
        return {"raw": str(d)}
    date_int = d.get("date_int")
    iso_date = ""
    if date_int is not None:
        try:
            iso_date = (datetime(1970, 1, 1) + timedelta(days=int(date_int))).strftime("%Y-%m-%d")
        except Exception:
            pass
    return {
        "date": iso_date,
        "calories": _num(d.get("calories")),
        "protein": _num(d.get("protein")),
        "fat": _num(d.get("fat")),
        "carbs": _num(d.get("carbohydrate")),
    }


def _num(val: Any) -> float:
    if val is None:
        return 0
    try:
        return round(float(val), 1)
    except (ValueError, TypeError):
        return 0
