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

        # Timeline has "147 / 91" rows; dedicated BP history uses column layout.
        # Try both and keep the richest timed result (nav text alone is not enough).
        best: list[dict[str, Any]] = []
        for path in (
            f"/en/records/{record_id}/timeline",
            f"/en/records/{record_id}/history/bloodpressures",
        ):
            resp = await c.get(f"{_PORTAL}{path}")
            if resp.status_code != 200 or not resp.text:
                continue
            parsed = _parse_timeline_bp(resp.text, limit=limit)
            if _bp_parse_score(parsed) > _bp_parse_score(best):
                best = parsed
        return best


def _bp_parse_score(readings: list[dict[str, Any]]) -> tuple[int, int]:
    timed = sum(1 for r in readings if "T" in str(r.get("measured_at") or ""))
    return (timed, len(readings))


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
    by_key: dict[tuple[int, int, str], dict[str, Any]] = {}
    current_date = today.isoformat()

    def _remember(sys_val: int, dia_val: int, pulse: int | None, measured_at: str) -> None:
        if sys_val < 60 or sys_val > 260 or dia_val < 30 or dia_val > 160:
            return
        key = (sys_val, dia_val, measured_at)
        prev = by_key.get(key)
        if prev and prev.get("pulse") is not None and pulse is None:
            return
        by_key[key] = {
            "systolic": sys_val,
            "diastolic": dia_val,
            "pulse": pulse,
            "measured_at": measured_at,
            "source": "medm_bp",
        }

    row_re = re.compile(r"<tr\b[^>]*>(.*?)</tr>", re.I | re.S)
    for row_m in row_re.finditer(html):
        row = row_m.group(1)

        # Timeline date header: <td class='date ...'>Today</td>
        date_cell = re.search(r"class=['\"]date(?![^'\"]*time)[^'\"]*['\"][^>]*>(.*?)</td>", row, re.I | re.S)
        if date_cell and "measurements_table__time" not in row:
            parsed = _parse_date_header(date_cell.group(1), today=today)
            if parsed:
                current_date = parsed
            # Pure date-header rows have no values.
            if not re.search(r"\d{2,3}\s*/\s*\d{2,3}", row) and "measurements_table__time" not in row:
                continue

        # History BP table date cell (may share the measurement row via rowspan).
        hist_date = re.search(
            r"class=['\"][^'\"]*measurements_table__date[^'\"]*['\"][^>]*rowspan[^>]*>(.*?)</td>",
            row,
            re.I | re.S,
        )
        if not hist_date:
            hist_date = re.search(
                r"class=['\"][^'\"]*measurements_table__date(?![^'\"]*time)[^'\"]*['\"][^>]*>"
                r"(?![\s\S]*measurements_table__time)(.*?)</td>",
                row,
                re.I | re.S,
            )
        if hist_date:
            # Only treat as date if text looks like a date header, not a clock.
            header = re.sub(r"<[^>]+>", " ", hist_date.group(1))
            if not re.search(r"\d{1,2}:\d{2}", header):
                parsed = _parse_date_header(header, today=today)
                if parsed:
                    current_date = parsed

        time_token = None
        time_cell = re.search(
            r"class=['\"][^'\"]*(?:measurements_table__time|\btime\b)[^'\"]*['\"][^>]*>(.*?)</td>",
            row,
            re.I | re.S,
        )
        if time_cell:
            time_token = _parse_time_token(re.sub(r"<[^>]+>", " ", time_cell.group(1)))
        if not time_token:
            time_token = _parse_time_token(re.sub(r"<[^>]+>", " ", row))

        # History page: separate numeric columns (sys / dia / pulse).
        if "measurements_table__" in row:
            nums = [
                int(n)
                for n in re.findall(
                    r"<td class=['\"]measurements_table__column['\"]>\s*<span[^>]*>\s*(\d{2,3})\s*</span>",
                    row,
                    re.I,
                )
            ]
            if len(nums) >= 2:
                pulse = nums[2] if len(nums) >= 3 and 30 <= nums[2] <= 200 else None
                measured_at = f"{current_date}T{time_token}" if time_token else current_date
                _remember(nums[0], nums[1], pulse, measured_at)
                if len(by_key) >= limit:
                    break
                continue

        # Timeline page: "Blood Pressure" + "147 / 91 (65 bpm)"
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

        measured_at = f"{current_date}T{time_token}" if time_token else current_date
        _remember(int(bp_m.group(1)), int(bp_m.group(2)), pulse, measured_at)
        if len(by_key) >= limit:
            break

    readings = list(by_key.values())
    readings.sort(key=lambda r: str(r.get("measured_at") or ""), reverse=True)
    return readings[:limit]
