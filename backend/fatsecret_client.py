"""FatSecret food diary integration via OAuth 1.0.

Flow:
1. User clicks "Connect FatSecret" → server generates authorize URL
2. User authorizes on FatSecret → redirected back with verifier
3. Server exchanges verifier for permanent access tokens
4. Server fetches food diary data automatically
"""

from __future__ import annotations

import json
import logging
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

from fatsecret import Fatsecret

logger = logging.getLogger(__name__)

_CREDS_PATH = Path(__file__).resolve().parent / "data" / "fatsecret_tokens.json"

CONSUMER_KEY = "7c52340ff2f94f8daeec2f6e80e985e8"
CONSUMER_SECRET = "96cd21e15d514bcabe38c27dc305bae5"

# In-memory pending OAuth sessions
_pending_sessions: dict[str, Fatsecret] = {}


def save_tokens(access_token: str, access_token_secret: str) -> None:
    _CREDS_PATH.parent.mkdir(parents=True, exist_ok=True)
    _CREDS_PATH.write_text(
        json.dumps({
            "access_token": access_token,
            "access_token_secret": access_token_secret,
        }, indent=2),
        encoding="utf-8",
    )


def load_tokens() -> tuple[str, str] | None:
    if not _CREDS_PATH.is_file():
        return None
    data = json.loads(_CREDS_PATH.read_text(encoding="utf-8"))
    return data.get("access_token", ""), data.get("access_token_secret", "")


def get_authorize_url(callback_url: str) -> tuple[str, str]:
    """Start OAuth flow. Returns (authorize_url, session_id)."""
    fs = Fatsecret(CONSUMER_KEY, CONSUMER_SECRET)
    url = fs.get_authorize_url(callback_url=callback_url)
    session_id = fs.request_token
    _pending_sessions[session_id] = fs
    logger.info("FatSecret OAuth started, session=%s", session_id)
    return url, session_id


def complete_auth(session_id: str, verifier: str) -> tuple[str, str]:
    """Complete OAuth flow with verifier. Returns (access_token, access_token_secret)."""
    fs = _pending_sessions.pop(session_id, None)
    if not fs:
        raise RuntimeError("OAuth сессия не найдена. Начните заново.")
    access_token, access_token_secret = fs.authenticate(verifier)
    save_tokens(access_token, access_token_secret)
    logger.info("FatSecret OAuth complete")
    return access_token, access_token_secret


def _get_client() -> Fatsecret | None:
    """Get authenticated FatSecret client."""
    tokens = load_tokens()
    if not tokens:
        return None
    access_token, access_token_secret = tokens
    if not access_token:
        return None
    fs = Fatsecret(CONSUMER_KEY, CONSUMER_SECRET, access_token=access_token, access_token_secret=access_token_secret)
    return fs


def fetch_food_entries_today() -> list[dict[str, Any]]:
    """Fetch today's food diary entries."""
    fs = _get_client()
    if not fs:
        return []
    try:
        entries = fs.food_entries_get()
        if not entries:
            return []
        if isinstance(entries, dict):
            entries = [entries]
        return [_normalize_entry(e) for e in entries]
    except Exception as exc:
        logger.warning("FatSecret food_entries_get failed: %s", exc)
        return []


def fetch_food_month(target_date: date | None = None) -> list[dict[str, Any]]:
    """Fetch monthly food diary summary (calories/macros per day)."""
    fs = _get_client()
    if not fs:
        return []
    try:
        d = target_date or date.today()
        dt = datetime(d.year, d.month, d.day)
        days = fs.food_entries_get_month(date=dt)
        if not days:
            return []
        if isinstance(days, dict):
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
