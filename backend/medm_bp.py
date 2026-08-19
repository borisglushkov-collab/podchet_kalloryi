"""MedM Blood Pressure integration via web portal scraping.

The MedM REST API requires special app registration, but the web portal
at health.medm.com works with regular email+password login.
We login via the web form, then scrape the timeline for BP readings.
"""

from __future__ import annotations

import json
import logging
import re
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import httpx

logger = logging.getLogger(__name__)

_PORTAL = "https://health.medm.com"
_CREDS_PATH = Path(__file__).resolve().parent / "data" / "medm_creds.json"


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

        # Extract record_id from redirect URL
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
    """Fetch blood pressure readings from MedM web portal timeline."""
    if not email or not password:
        creds = load_creds()
        if not creds:
            return []
        email, password = creds

    async with httpx.AsyncClient(follow_redirects=True, timeout=30) as c:
        # Login
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

        # Get record_id
        rm = re.search(r"/records/([a-f0-9-]+)/", str(r2.url))
        if not rm:
            logger.warning("MedM: no record_id found")
            return []
        record_id = rm.group(1)

        # Fetch timeline page
        r3 = await c.get(f"{_PORTAL}/en/records/{record_id}/timeline")
        if r3.status_code != 200:
            logger.warning("MedM timeline: %d", r3.status_code)
            return []

        return _parse_timeline_bp(r3.text, limit=limit)


def _parse_timeline_bp(html: str, *, limit: int = 50) -> list[dict[str, Any]]:
    """Extract BP readings from MedM timeline HTML."""
    readings: list[dict[str, Any]] = []

    # Find all BP patterns: systolic/diastolic (optionally with pulse)
    # The timeline shows them in measurement blocks
    bp_pattern = re.compile(
        r'(\d{2,3})\s*/\s*(\d{2,3})',
    )

    # Find dates in the timeline
    date_pattern = re.compile(
        r'(\d{1,2})\s+'
        r'(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|'
        r'Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)'
        r'\s+(\d{4})',
        re.I,
    )

    _MONTHS_RU = {
        "января": 1, "февраля": 2, "марта": 3, "апреля": 4,
        "мая": 5, "июня": 6, "июля": 7, "августа": 8,
        "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12,
    }
    _MONTHS_EN = {
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    }

    def _parse_month(s: str) -> int:
        sl = s.lower()
        if sl in _MONTHS_RU:
            return _MONTHS_RU[sl]
        for k, v in _MONTHS_EN.items():
            if sl.startswith(k):
                return v
        return 0

    # Track current date context
    current_date = date.today().isoformat()

    # Split by date headers and extract BP from each section
    parts = date_pattern.split(html)

    # Process sequentially, tracking current date
    pos = 0
    text = html
    date_matches = list(date_pattern.finditer(text))
    bp_matches = list(bp_pattern.finditer(text))

    # For each BP match, find the nearest preceding date
    for bp_m in bp_matches:
        sys_val = int(bp_m.group(1))
        dia_val = int(bp_m.group(2))

        if sys_val < 60 or sys_val > 260 or dia_val < 30 or dia_val > 160:
            continue

        # Find nearest date before this BP
        nearest_date = current_date
        for dm in date_matches:
            if dm.start() < bp_m.start():
                day_num = int(dm.group(1))
                month_num = _parse_month(dm.group(2))
                year_num = int(dm.group(3))
                if month_num:
                    nearest_date = f"{year_num}-{month_num:02d}-{day_num:02d}"

        # Find time near this BP (within 200 chars)
        context = text[max(0, bp_m.start() - 200): bp_m.end() + 200]
        time_m = re.search(r'(\d{2}):(\d{2})', context)
        measured_at = nearest_date
        if time_m:
            measured_at = f"{nearest_date}T{time_m.group(1)}:{time_m.group(2)}:00"

        # Find pulse near this BP
        pulse = None
        pulse_m = re.search(r'(\d{2,3})\s*(?:уд|bpm|пульс|pulse)', context, re.I)
        if pulse_m:
            p = int(pulse_m.group(1))
            if 30 <= p <= 200:
                pulse = p

        # Avoid duplicates
        key = f"{sys_val}/{dia_val}/{measured_at}"
        if any(f"{r['systolic']}/{r['diastolic']}/{r['measured_at']}" == key for r in readings):
            continue

        readings.append({
            "systolic": sys_val,
            "diastolic": dia_val,
            "pulse": pulse,
            "measured_at": measured_at,
            "source": "medm_bp",
        })

        if len(readings) >= limit:
            break

    return readings
