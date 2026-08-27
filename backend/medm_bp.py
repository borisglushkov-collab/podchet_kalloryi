"""MedM Blood Pressure integration via web portal scraping.

The MedM REST API requires special app registration, but the web portal
at health.medm.com works with regular email+password login.
We login via the web form, then scrape the timeline / BP history.
"""

from __future__ import annotations

import json
import logging
import re
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import httpx

logger = logging.getLogger(__name__)

_PORTAL = "https://health.medm.com"
_CREDS_PATH = Path(__file__).resolve().parent / "data" / "medm_creds.json"
_USER_TZ = ZoneInfo("Europe/Moscow")


def save_creds(email: str, password: str) -> None:
    _CREDS_PATH.parent.mkdir(parents=True, exist_ok=True)
    _CREDS_PATH.write_text(
        json.dumps({"email": email, "password": password}, indent=2),
        encoding="utf-8",
    )


def load_creds() -> tuple[str, str] | None:
    if not _CREDS_PATH.is_file():
        return None
    data = json.loads(_CREDS_PATH.read_text(encoding="utf-8"))
    return data.get("email", ""), data.get("password", "")


def clear_creds() -> bool:
    if _CREDS_PATH.is_file():
        _CREDS_PATH.unlink()
        return True
    return False


async def medm_login(email: str, password: str) -> str:
    """Login to MedM web portal. Returns the record_id."""
    async with httpx.AsyncClient(follow_redirects=True, timeout=20) as c:
        r = await c.get(f"{_PORTAL}/en/user/login")
        m = re.search(r'name="authenticity_token"[^>]*value="([^"]+)"', r.text)
        if not m:
            raise RuntimeError("Не удалось получить CSRF токен MedM")

        r2 = await c.post(
            f"{_PORTAL}/en/user/login",
            data={
                "authenticity_token": m.group(1),
                "email": email,
                "password": password,
                "commit": "Войти",
            },
        )
        if "login" in str(r2.url) or r2.status_code != 200:
            raise RuntimeError("Неверный email или пароль MedM")

        rm = re.search(r"/records/([a-f0-9-]+)/", str(r2.url))
        record_id = rm.group(1) if rm else ""

        save_creds(email, password)
        logger.info("MedM login OK, record_id=%s", record_id)
        return record_id


async def fetch_bp_readings(
    email: str | None = None,
    password: str | None = None,
    *,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Fetch blood pressure readings from MedM web portal."""
    if not email or not password:
        creds = load_creds()
        if not creds:
            return []
        email, password = creds

    async with httpx.AsyncClient(follow_redirects=True, timeout=30) as c:
        r = await c.get(f"{_PORTAL}/en/user/login")
        m = re.search(r'name="authenticity_token"[^>]*value="([^"]+)"', r.text)
        if not m:
            logger.warning("MedM: no CSRF token")
            return []

        r2 = await c.post(
            f"{_PORTAL}/en/user/login",
            data={
                "authenticity_token": m.group(1),
                "email": email,
                "password": password,
                "commit": "Войти",
            },
        )
        if "login" in str(r2.url):
            logger.warning("MedM login failed")
            return []

        rm = re.search(r"/records/([a-f0-9-]+)/", str(r2.url))
        if not rm:
            logger.warning("MedM: no record_id found")
            return []
        record_id = rm.group(1)

        # Prefer dedicated BP history (cleaner rows); fall back to full timeline.
        pages: list[str] = []
        for path in (
            f"/en/records/{record_id}/history/bloodpressures",
            f"/en/records/{record_id}/timeline",
        ):
            resp = await c.get(f"{_PORTAL}{path}")
            if resp.status_code == 200 and resp.text:
                pages.append(resp.text)
                if "Blood Pressure" in resp.text or "bloodpressure" in resp.text.lower():
                    break

        readings: list[dict[str, Any]] = []
        for html in pages:
            readings = _parse_timeline_bp(html, limit=limit)
            if readings:
                break
        return readings


_MONTHS_EN = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}
_MONTHS_RU = {
    "января": 1,
    "февраля": 2,
    "марта": 3,
    "апреля": 4,
    "мая": 5,
    "июня": 6,
    "июля": 7,
    "августа": 8,
    "сентября": 9,
    "октября": 10,
    "ноября": 11,
    "декабря": 12,
}


def _parse_month(token: str) -> int:
    sl = token.lower().strip(".,")
    if sl in _MONTHS_RU:
        return _MONTHS_RU[sl]
    for key, value in _MONTHS_EN.items():
        if sl.startswith(key):
            return value
    return 0


def _local_today() -> date:
    return datetime.now(tz=_USER_TZ).date()


def _parse_date_header(text: str, *, today: date | None = None) -> str | None:
    today = today or _local_today()
    cleaned = re.sub(r"<[^>]+>", " ", text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    low = cleaned.lower()
    if low in {"today", "сегодня"}:
        return today.isoformat()
    if low in {"yesterday", "вчера"}:
        return (today - timedelta(days=1)).isoformat()

    m = re.search(
        r"(\d{1,2})\s+"
        r"(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|"
        r"Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|"
        r"Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"
        r"(?:\s+,?\s*|\s+)(\d{4})",
        cleaned,
        re.I,
    )
    if m:
        month = _parse_month(m.group(2))
        if month:
            return f"{int(m.group(3)):04d}-{month:02d}-{int(m.group(1)):02d}"

    m = re.search(
        r"(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|"
        r"Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2}),\s*(\d{4})",
        cleaned,
        re.I,
    )
    if m:
        month = _parse_month(m.group(1))
        if month:
            return f"{int(m.group(3)):04d}-{month:02d}-{int(m.group(2)):02d}"
    return None


def _parse_time_token(text: str) -> str | None:
    """Return HH:MM:SS 24h from strings like '02:13 PM' / '14:05'."""
    m = re.search(r"(\d{1,2}):(\d{2})\s*([AaPp][Mm])?", text)
    if not m:
        return None
    hour = int(m.group(1))
    minute = int(m.group(2))
    ampm = (m.group(3) or "").lower()
    if ampm == "pm" and hour < 12:
        hour += 12
    if ampm == "am" and hour == 12:
        hour = 0
    if hour > 23 or minute > 59:
        return None
    return f"{hour:02d}:{minute:02d}:00"


def _parse_timeline_bp(html: str, *, limit: int = 50, today: date | None = None) -> list[dict[str, Any]]:
    """Extract BP readings from MedM timeline / bloodpressures HTML."""
    today = today or _local_today()
    readings: list[dict[str, Any]] = []
    current_date = today.isoformat()

    # Walk table rows: date headers and measurement rows with time + value.
    row_re = re.compile(r"<tr\b[^>]*>(.*?)</tr>", re.I | re.S)
    for row_m in row_re.finditer(html):
        row = row_m.group(1)
        date_cell = re.search(r"class=['\"]date[^'\"]*['\"][^>]*>(.*?)</td>", row, re.I | re.S)
        if date_cell:
            parsed = _parse_date_header(date_cell.group(1), today=today)
            if parsed:
                current_date = parsed
            continue

        if not re.search(r"Blood\s*Pressure|bloodpressure", row, re.I):
            continue

        bp_m = re.search(
            r"(\d{2,3})\s*/\s*(\d{2,3})\s*(?:<span[^>]*>\s*mmHg\s*</span>|mmHg)?"
            r"\s*(?:\((\d{2,3}))?",
            row,
            re.I,
        )
        if not bp_m:
            bp_m = re.search(r"(\d{2,3})\s*/\s*(\d{2,3})", row)
        if not bp_m:
            continue

        sys_val = int(bp_m.group(1))
        dia_val = int(bp_m.group(2))
        if sys_val < 60 or sys_val > 260 or dia_val < 30 or dia_val > 160:
            continue

        pulse = None
        if bp_m.lastindex and bp_m.lastindex >= 3 and bp_m.group(3):
            p = int(bp_m.group(3))
            if 30 <= p <= 200:
                pulse = p
        if pulse is None:
            pulse_m = re.search(r"\((\d{2,3})\s*(?:<[^>]+>\s*)*(?:bpm|уд|пульс|pulse)", row, re.I)
            if pulse_m:
                p = int(pulse_m.group(1))
                if 30 <= p <= 200:
                    pulse = p

        time_cell = re.search(r"class=['\"]time['\"][^>]*>(.*?)</td>", row, re.I | re.S)
        time_token = _parse_time_token(re.sub(r"<[^>]+>", " ", time_cell.group(1)) if time_cell else "")
        if not time_token:
            # Fallback: any AM/PM time in the row.
            time_token = _parse_time_token(re.sub(r"<[^>]+>", " ", row))

        measured_at = f"{current_date}T{time_token}" if time_token else current_date

        key = (sys_val, dia_val, measured_at)
        if any((r["systolic"], r["diastolic"], r["measured_at"]) == key for r in readings):
            continue

        readings.append(
            {
                "systolic": sys_val,
                "diastolic": dia_val,
                "pulse": pulse,
                "measured_at": measured_at,
                "source": "medm_bp",
            }
        )
        if len(readings) >= limit:
            break

    readings.sort(key=lambda r: str(r.get("measured_at") or ""), reverse=True)
    return readings
