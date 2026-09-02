"""Background data collector: periodically pulls Mi Fitness data and saves snapshots.

Runs as an asyncio background task inside the FastAPI lifespan.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from datetime import date, datetime, timedelta, timezone
from typing import Any

from zoneinfo import ZoneInfo

from health_day_store import day_store
from xiaomi_auth import XiaomiTokens, login_xiaomi
from xiaomi_fitness import MiFitnessClient
from xiaomi_home import XiaomiHomeClient

logger = logging.getLogger(__name__)

_INTERVAL_MINUTES = int(os.getenv("COLLECT_INTERVAL_MIN", "30"))
_REGION = os.getenv("XIAOMI_REGION", "ru")
_USER_TZ = ZoneInfo(os.getenv("USER_TZ", "Europe/Moscow"))


def user_local_date() -> date:
    """Calendar day for diary/collect (Europe/Moscow by default)."""
    return datetime.now(_USER_TZ).date()


_SPORT_NAMES: dict[int, str] = {
    1: "Бег",
    2: "Ходьба",
    3: "Велосипед",
    4: "Плавание",
    5: "Эллипс",
    6: "Йога",
    7: "Силовая",
    8: "HIIT",
    9: "Тренажёр",
    10: "Футбол",
    11: "Баскетбол",
    12: "Теннис",
    13: "Гребля",
    14: "Скакалка",
    15: "Танцы",
}

_collector_task: asyncio.Task | None = None
_last_result: dict[str, Any] = {}
_last_error: str | None = None
_last_sources: dict[str, Any] = {}
_running = False


def _connection_status() -> dict[str, Any]:
    """Lightweight connected/not flags for hub UI (no secrets)."""
    xiaomi = XiaomiTokens.load()
    xiaomi_ok = bool(xiaomi and xiaomi.service_token)
    fatsecret_ok = False
    try:
        from fatsecret_client import load_tokens

        tokens = load_tokens()
        fatsecret_ok = bool(tokens and tokens[0])
    except Exception:
        fatsecret_ok = False
    medm_ok = False
    try:
        from medm_bp import load_creds

        creds = load_creds()
        medm_ok = bool(creds and creds[0])
    except Exception:
        medm_ok = False
    return {
        "xiaomi": {"connected": xiaomi_ok},
        "fatsecret": {"connected": fatsecret_ok},
        "medm": {"connected": medm_ok},
    }


def collector_status() -> dict[str, Any]:
    return {
        "running": _running,
        "interval_min": _INTERVAL_MINUTES,
        "region": _REGION,
        "last_result": _last_result,
        "last_error": _last_error,
        "last_sources": _last_sources,
        "connections": _connection_status(),
    }


def _parse_value(item: dict[str, Any]) -> dict[str, Any]:
    """Parse nested JSON from the 'value' field of a Mi Fitness data item."""
    val = item.get("value", "")
    if isinstance(val, str):
        try:
            return json.loads(val)
        except (json.JSONDecodeError, ValueError):
            return {}
    if isinstance(val, dict):
        return val
    return {}


def _record_timestamp(record: dict[str, Any]) -> float:
    """Unix seconds from a vendor record (0 if unknown)."""
    for key in ("createTime", "create_time", "time", "timestamp", "measured_at"):
        val = record.get(key)
        if val is None and isinstance(record.get("bodyData"), dict):
            val = record["bodyData"].get(key)
        if val is None:
            continue
        if isinstance(val, (int, float)):
            ts = float(val)
            if ts > 1_000_000_000_000:
                ts /= 1000.0
            return ts
        text = str(val).strip().replace("Z", "")
        if not text:
            continue
        try:
            if "T" in text:
                return datetime.fromisoformat(text[:19]).replace(tzinfo=_USER_TZ).timestamp()
            if len(text) >= 10 and text[4] == "-" and text[7] == "-":
                return datetime.fromisoformat(text[:10]).replace(tzinfo=_USER_TZ).timestamp()
        except ValueError:
            continue
    nested = record.get("data")
    if isinstance(nested, str):
        try:
            nested = json.loads(nested)
        except (json.JSONDecodeError, ValueError):
            nested = None
    if isinstance(nested, dict) and nested.get("time") is not None:
        try:
            ts = float(nested["time"])
            if ts > 1_000_000_000_000:
                ts /= 1000.0
            return ts
        except (TypeError, ValueError):
            pass
    return 0.0


def _record_date_iso(record: dict[str, Any]) -> str | None:
    """Best-effort extract YYYY-MM-DD in the user timezone (Europe/Moscow)."""
    for key in ("measured_at", "date"):
        val = record.get(key)
        if val is None:
            continue
        text = str(val).strip()
        if len(text) >= 10 and text[4] == "-" and text[7] == "-":
            return text[:10]
    ts = _record_timestamp(record)
    if ts > 0:
        try:
            return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone(_USER_TZ).date().isoformat()
        except (OSError, OverflowError, ValueError):
            return None
    return None


def _filter_scale_for_date(records: list[dict[str, Any]], target_date: date) -> list[dict[str, Any]]:
    """Return only scale readings for the target local day. Never fall back to other days."""
    iso = target_date.isoformat()
    matched = [r for r in records if _record_date_iso(r) == iso]
    matched.sort(key=_record_timestamp, reverse=True)
    return matched


def _measured_at_iso(record: dict[str, Any]) -> str | None:
    ts = _record_timestamp(record)
    if ts <= 0:
        return None
    try:
        return (
            datetime.fromtimestamp(ts, tz=timezone.utc)
            .astimezone(_USER_TZ)
            .replace(microsecond=0, tzinfo=None)
            .isoformat()
        )
    except (OSError, OverflowError, ValueError):
        return None


def _item_local_date(item: dict[str, Any], tz_name: str = "Europe/Moscow") -> date | None:
    """Calendar day for a Mi Fitness data_list row (uses zone_offset when set)."""
    ts = item.get("time")
    if ts is None:
        return None
    try:
        ts_i = int(ts)
        if ts_i > 1_000_000_000_000:
            ts_i //= 1000
        instant = datetime.fromtimestamp(ts_i, tz=timezone.utc)
    except (OSError, OverflowError, TypeError, ValueError):
        return None
    zone_offset = item.get("zone_offset")
    if zone_offset is not None:
        try:
            return (instant + timedelta(seconds=int(zone_offset))).date()
        except (TypeError, ValueError, OverflowError):
            pass
    try:
        return instant.astimezone(ZoneInfo(tz_name)).date()
    except Exception:
        return None


def _as_minutes(value: Any, *, total_min: int | None = None) -> int:
    """Normalize a duration that may be seconds or minutes."""
    try:
        n = int(value or 0)
    except (TypeError, ValueError):
        return 0
    if n <= 0:
        return 0
    if total_min and n > max(total_min * 1.2, 90):
        return n // 60
    if n > 16 * 60:
        return n // 60
    return n


def _sleep_session(item: dict[str, Any]) -> dict[str, Any] | None:
    """Parse one Mi Fitness sleep record into minutes for a single night.

    `total_min` matches the Mi Fitness app "sleep duration" (asleep time), not
    bed→wake wall-clock which includes awake-in-bed. Prefer `sleep_duration`,
    then deep+light+REM, then in-bed minutes as last resort.
    """
    v = _parse_value(item)
    bt = v.get("bedtime") or v.get("device_bedtime")
    wt = (
        v.get("wake_up_time")
        or v.get("device_wake_up_time")
        or v.get("end_time")
        or v.get("sleep_end")
    )
    in_bed_min = 0
    wake_date = None
    bed_date = None
    try:
        if bt and wt:
            bt_i = int(bt)
            wt_i = int(wt)
            if bt_i > 1_000_000_000_000:
                bt_i //= 1000
                wt_i //= 1000
            in_bed_min = max(0, (wt_i - bt_i) // 60)
            wake_date = datetime.fromtimestamp(wt_i, tz=timezone.utc).astimezone(_USER_TZ).date()
            bed_date = datetime.fromtimestamp(bt_i, tz=timezone.utc).astimezone(_USER_TZ).date()
    except (OSError, OverflowError, TypeError, ValueError):
        in_bed_min = 0
        wake_date = None
        bed_date = None

    if wake_date is None and wt:
        try:
            wt_i = int(wt)
            if wt_i > 1_000_000_000_000:
                wt_i //= 1000
            wake_date = datetime.fromtimestamp(wt_i, tz=timezone.utc).astimezone(_USER_TZ).date()
        except (OSError, OverflowError, TypeError, ValueError):
            wake_date = None
    if wake_date is None:
        wake_date = _item_local_date(item)
    if bed_date is None and bt:
        try:
            bt_i = int(bt)
            if bt_i > 1_000_000_000_000:
                bt_i //= 1000
            bed_date = datetime.fromtimestamp(bt_i, tz=timezone.utc).astimezone(_USER_TZ).date()
        except (OSError, OverflowError, TypeError, ValueError):
            bed_date = None

    # Provisional scale for seconds→minutes heuristic on stage fields.
    provisional = in_bed_min or 8 * 60
    deep = _as_minutes(v.get("sleep_deep_duration", 0), total_min=provisional)
    light = _as_minutes(v.get("sleep_light_duration", 0), total_min=provisional)
    rem = _as_minutes(v.get("sleep_rem_duration", 0), total_min=provisional)
    stages_sum = deep + light + rem

    # Mi Fitness asleep time ≈ deep+light+REM. `duration` usually matches stages;
    # `sleep_duration` may include in-bed time — only trust it when close to stages.
    duration_field = (
        _as_minutes(v.get("duration"), total_min=provisional)
        if v.get("duration") is not None
        else 0
    )
    sleep_duration_field = (
        _as_minutes(v.get("sleep_duration"), total_min=provisional)
        if v.get("sleep_duration") is not None
        else 0
    )
    total_minutes_field = (
        _as_minutes(v.get("total_minutes"), total_min=provisional)
        if v.get("total_minutes") is not None
        else 0
    )

    asleep_min = 0
    if stages_sum > 0:
        asleep_min = stages_sum
        tol = max(10, int(stages_sum * 0.05))
        for explicit in (duration_field, sleep_duration_field, total_minutes_field):
            if explicit and abs(explicit - stages_sum) <= tol:
                asleep_min = explicit
                break
    elif duration_field:
        asleep_min = duration_field
    elif sleep_duration_field:
        asleep_min = sleep_duration_field
    elif total_minutes_field:
        asleep_min = total_minutes_field
    elif in_bed_min:
        asleep_min = in_bed_min
    if not asleep_min:
        return None

    avg_hr = None
    if v.get("avg_hr") is not None:
        try:
            avg_hr = int(v.get("avg_hr"))
        except (TypeError, ValueError):
            avg_hr = None

    out = {
        "total_min": asleep_min,
        "deep_min": deep,
        "light_min": light,
        "rem_min": rem,
        "avg_hr": avg_hr,
        "wake_date": wake_date,
        "bed_date": bed_date,
    }
    if in_bed_min and in_bed_min != asleep_min:
        out["in_bed_min"] = in_bed_min
    return out


def _pick_sleep_for_day(sleep_list: list[dict[str, Any]], target_date: date) -> dict[str, Any] | None:
    """Choose the night that ends on target_date (wake-up morning). Never sum two nights."""
    sessions = [s for s in (_sleep_session(i) for i in sleep_list) if s]
    if not sessions:
        return None

    def _sleep_output(best: dict[str, Any]) -> dict[str, Any]:
        out = {
            "total_min": int(best["total_min"]),
            "deep_min": int(best.get("deep_min") or 0),
            "light_min": int(best.get("light_min") or 0),
            "rem_min": int(best.get("rem_min") or 0),
        }
        if best.get("avg_hr") is not None:
            out["avg_hr"] = best["avg_hr"]
        if best.get("in_bed_min") is not None:
            out["in_bed_min"] = int(best["in_bed_min"])
        return out

    # Mi Fitness attributes sleep to the wake-up calendar day.
    preferred = [s for s in sessions if s.get("wake_date") == target_date]
    if preferred:
        return _sleep_output(max(preferred, key=lambda s: int(s.get("total_min") or 0)))

    # Wake date missing — fall back to bed starting previous evening (not random naps).
    fallback = [
        s
        for s in sessions
        if s.get("wake_date") is None
        and s.get("bed_date") in {target_date - timedelta(days=1), target_date}
        and int(s.get("total_min") or 0) >= 60
    ]
    if fallback:
        return _sleep_output(max(fallback, key=lambda s: int(s.get("total_min") or 0)))

    # No main night for this morning yet — do not show yesterday's nap or an older night.
    return None


def _step_record_date(item: dict[str, Any], tz_name: str = "Europe/Moscow") -> str | None:
    ts = item.get("time")
    if ts is None:
        return None
    try:
        instant = datetime.fromtimestamp(int(ts), tz=timezone.utc)
    except (OSError, OverflowError, TypeError, ValueError):
        return None
    zone_offset = item.get("zone_offset")
    if zone_offset is not None:
        try:
            return (instant + timedelta(seconds=int(zone_offset))).date().isoformat()
        except (TypeError, ValueError, OverflowError):
            pass
    try:
        return instant.astimezone(ZoneInfo(tz_name)).date().isoformat()
    except Exception:
        return None


def _aggregate_metric_values(values: list[int]) -> int:
    """Sum incremental buckets; use last value when records look like daily cumulative totals."""
    if not values:
        return 0
    if len(values) == 1:
        return values[0]
    total_sum = sum(values)
    non_decreasing = all(values[i] <= values[i + 1] for i in range(len(values) - 1))
    if non_decreasing and values[-1] >= total_sum * 0.45:
        return values[-1]
    return total_sum


def _aggregate_steps_for_day(steps_list: list[dict[str, Any]], target_date: date) -> dict[str, int] | None:
    iso = target_date.isoformat()
    # Dedupe by timestamp — Xiaomi sometimes repeats the same minute bucket.
    by_ts: dict[int, dict[str, int]] = {}
    for item in steps_list:
        if _step_record_date(item) != iso:
            continue
        v = _parse_value(item)
        steps = int(v.get("steps", 0) or 0)
        distance = int(v.get("distance", 0) or 0)
        calories = int(v.get("calories", 0) or 0)
        if steps <= 0 and distance <= 0 and calories <= 0:
            continue
        ts = int(item.get("time") or v.get("time") or 0)
        prev = by_ts.get(ts)
        if prev is None:
            by_ts[ts] = {"steps": steps, "distance": distance, "calories": calories}
        else:
            # Same second: keep the richer sample, never sum duplicates.
            by_ts[ts] = {
                "steps": max(prev["steps"], steps),
                "distance": max(prev["distance"], distance),
                "calories": max(prev["calories"], calories),
            }
    if not by_ts:
        return None
    buckets = [by_ts[ts] for ts in sorted(by_ts)]
    step_vals = [b["steps"] for b in buckets if b["steps"] > 0]
    dist_vals = [b["distance"] for b in buckets if b["distance"] > 0]
    cal_vals = [b["calories"] for b in buckets if b["calories"] > 0]
    return {
        "count": _aggregate_metric_values(step_vals),
        "distance_m": _aggregate_metric_values(dist_vals),
        "calories": _aggregate_metric_values(cal_vals),
        "source": "mi_fitness",
    }


def _meal_type_key(raw: str | None) -> str:
    key = str(raw or "snack").strip().lower()
    if key in {"breakfast", "lunch", "dinner", "snack"}:
        return key
    return "snack"


def _normalize_food_entry(entry: dict[str, Any]) -> dict[str, Any]:
    protein = round(float(entry.get("protein") or 0), 1)
    fat = round(float(entry.get("fat") or 0), 1)
    carbs = round(float(entry.get("carbs") or 0), 1)
    return {
        "name": str(entry.get("name") or "").strip(),
        "grams": round(float(entry.get("grams") or 0), 1),
        "calories": round(float(entry.get("calories") or 0), 1),
        "protein": protein,
        "fat": fat,
        "carbs": carbs,
        "protein_g": protein,
        "fat_g": fat,
        "carbs_g": carbs,
    }


def _filter_medm_for_date(readings: list[dict[str, Any]], target_date: date) -> list[dict[str, Any]]:
    iso = target_date.isoformat()
    return [r for r in readings if str(r.get("measured_at") or "").startswith(iso)]


def _normalize_workout(item: dict[str, Any]) -> dict[str, Any]:
    v = _parse_value(item)
    sport_type = int(v.get("sport_type") or v.get("proto_type") or 0)
    duration_sec = int(v.get("duration") or 0)
    start_ts = v.get("start_time") or v.get("time")
    start_at = None
    if start_ts:
        try:
            start_at = datetime.fromtimestamp(int(start_ts), tz=timezone.utc).replace(microsecond=0).isoformat()
        except (OSError, OverflowError, ValueError):
            start_at = None
    name = _SPORT_NAMES.get(sport_type, "Тренировка")
    if sport_type == 13 or v.get("row_count"):
        name = "Гребля"
    return {
        "sport_type": sport_type,
        "name": name,
        "duration_min": round(duration_sec / 60) if duration_sec else 0,
        "calories": int(v.get("calories") or v.get("total_cal") or 0),
        "avg_hr": int(v.get("avg_hrm") or 0) or None,
        "max_hr": int(v.get("max_hrm") or 0) or None,
        "distance_m": int(v.get("distance") or 0) or None,
        "start_at": start_at,
        "source": "mi_fitness",
    }


def _parse_scale_body(record: dict[str, Any]) -> dict[str, Any]:
    """Parse Xiaomi Home scale record (eco/scale format)."""
    raw = record.get("data")
    if isinstance(raw, str):
        try:
            body = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            body = {}
    elif isinstance(raw, dict):
        body = raw
    else:
        body = record.get("bodyData") or record

    def _num(key: str, alt: str | None = None) -> float | None:
        val = body.get(key)
        if val is None and alt:
            val = body.get(alt)
        if val is None:
            return None
        try:
            return round(float(val), 1)
        except (ValueError, TypeError):
            return None

    out: dict[str, Any] = {}
    weight = _num("weight")
    if weight is not None:
        out["weight"] = weight
    for src, dst in (
        ("bmi", "bmi"),
        ("bfp", "bodyFat"),
        ("bwp", "water"),
        ("bmc", "bone"),
        ("ma", "bodyAge"),
        ("slm", "muscle"),
        ("pm", "protein"),
        ("vfl", "visceralFat"),
        ("bmr", "bmr"),
        ("sbc", "bodyScore"),
        ("heartRate", "heartRate"),
        ("smm", "skeletalMuscle"),
    ):
        val = _num(src)
        if val is not None:
            out[dst] = val
    return out


def _normalize_snapshot(raw: dict[str, Any], target_date: date) -> dict[str, Any]:
    """Convert raw Mi Fitness API items into our day-snapshot format."""
    snap: dict[str, Any] = {"date": target_date.isoformat()}

    # Steps — Mi Fitness uploads incremental buckets or cumulative daily totals.
    steps_list = raw.get("steps") or []
    step_totals = _aggregate_steps_for_day(steps_list, target_date)
    if step_totals:
        snap["steps"] = step_totals
        snap["activity"] = {"steps": step_totals["count"], "source": "mi_fitness"}

    # Sleep — pick the night ending on target_date (do not sum two nights).
    if "sleep" in raw:
        sleep = _pick_sleep_for_day(raw.get("sleep") or [], target_date)
        if sleep:
            snap["sleep"] = sleep
        else:
            snap["sleep"] = None

    # Weight from Xiaomi Home scale (body composition) — newest reading of the day.
    if "weight_home" in raw:
        home_weight = list(raw.get("weight_home") or [])
        home_weight.sort(key=_record_timestamp, reverse=True)
        if home_weight:
            latest_hw = home_weight[0]
            bd = _parse_scale_body(latest_hw)
            w = bd.get("weight")
            if w is not None:
                try:
                    snap["weight"] = {
                        "kg": round(float(w), 1),
                        "source": "xiaomi_home",
                        "measured_at": _measured_at_iso(latest_hw),
                    }
                    for field in (
                        "bmi", "bodyFat", "muscle", "water", "bone", "visceralFat",
                        "bodyAge", "bmr", "bodyScore", "heartRate", "skeletalMuscle", "protein",
                    ):
                        val = bd.get(field)
                        if val is not None:
                            snap["weight"][field] = round(float(val), 1)
                except (ValueError, TypeError):
                    pass
        else:
            # Explicit empty day from scale fetch — clear stale weight on merge.
            snap["weight"] = None

    # Weight from Mi Fitness (fallback if no Xiaomi Home data)
    weight_list = list(raw.get("weight") or [])
    if weight_list and "weight" not in snap:
        weight_list.sort(key=_record_timestamp, reverse=True)
        latest_item = weight_list[0]
        latest_v = _parse_value(latest_item)
        w = latest_v.get("weight")
        if w is not None:
            try:
                snap["weight"] = {
                    "kg": round(float(w), 1),
                    "measured_at": _measured_at_iso(latest_item),
                }
                bmi = latest_v.get("bmi")
                if bmi:
                    snap["weight"]["bmi"] = round(float(bmi), 1)
            except (ValueError, TypeError):
                pass

    # Heart rate — value has {"bpm": 70, "type": 0}
    hr_list = raw.get("heart_rate") or []
    if hr_list:
        vals = []
        for item in hr_list:
            v = _parse_value(item)
            bpm = v.get("bpm")
            if bpm is not None:
                try:
                    vals.append(int(bpm))
                except (ValueError, TypeError):
                    pass
        if vals:
            snap["heart_rate"] = {
                "avg": round(sum(vals) / len(vals)),
                "min": min(vals),
                "max": max(vals),
                "samples": len(vals),
            }

    # Workouts key is always set by Mi Fitness day summary (may be empty).
    if "workouts" in raw:
        snap["workouts"] = [_normalize_workout(w) for w in (raw.get("workouts") or [])]

    # Blood pressure from Mi Fitness (MedM overwrites below when present).
    bp_list = list(raw.get("blood_pressure") or [])
    if bp_list:
        bp_list.sort(key=_record_timestamp, reverse=True)
        latest_item = bp_list[0]
        latest_v = _parse_value(latest_item)
        sys_val = latest_v.get("systolic") or latest_v.get("sys")
        dia_val = latest_v.get("diastolic") or latest_v.get("dia")
        if sys_val and dia_val:
            snap["blood_pressure"] = {
                "latest": {
                    "systolic": int(sys_val),
                    "diastolic": int(dia_val),
                    "measured_at": _measured_at_iso(latest_item),
                    "source": "mi_fitness",
                },
            }

    # FatSecret food diary — empty list clears stale meals when source was collected.
    if "fatsecret_food" in raw:
        food_entries = raw.get("fatsecret_food") or []
        if food_entries:
            normalized_entries = [_normalize_food_entry(e) for e in food_entries if e.get("name")]
            total_cal = sum(e.get("calories", 0) for e in normalized_entries)
            total_p = sum(e.get("protein", 0) for e in normalized_entries)
            total_f = sum(e.get("fat", 0) for e in normalized_entries)
            total_c = sum(e.get("carbs", 0) for e in normalized_entries)
            meals_by_type: dict[str, list] = {}
            for e in food_entries:
                if not e.get("name"):
                    continue
                mt = _meal_type_key(e.get("meal"))
                meals_by_type.setdefault(mt, []).append(_normalize_food_entry(e))
            snap["nutrition"] = {
                "calories": round(total_cal),
                "protein_g": round(total_p, 1),
                "fat_g": round(total_f, 1),
                "carbs_g": round(total_c, 1),
                "meals": [
                    {"meal_type": mt, "items": items}
                    for mt, items in meals_by_type.items()
                ],
                "source": "fatsecret",
            }
        else:
            snap["nutrition"] = {
                "calories": 0,
                "protein_g": 0,
                "fat_g": 0,
                "carbs_g": 0,
                "meals": [],
                "source": "fatsecret",
            }

    # MedM blood pressure — key present means we scraped (may be empty for the day).
    if "medm_bp" in raw:
        medm_bp = list(raw.get("medm_bp") or [])
        if medm_bp:
            medm_bp = sorted(medm_bp, key=lambda r: str(r.get("measured_at") or ""), reverse=True)
            latest_bp = medm_bp[0]
            sys_val = latest_bp.get("systolic")
            dia_val = latest_bp.get("diastolic")
            if sys_val and dia_val:
                bp_data = snap.get("blood_pressure") or {}
                bp_data["latest"] = {
                    "systolic": int(sys_val),
                    "diastolic": int(dia_val),
                    "pulse": latest_bp.get("pulse"),
                    "measured_at": latest_bp.get("measured_at"),
                    "source": "medm_bp",
                }
                bp_data["readings_today"] = [
                    {
                        "systolic": r["systolic"],
                        "diastolic": r["diastolic"],
                        "pulse": r.get("pulse"),
                        "measured_at": r.get("measured_at"),
                        "source": "medm_bp",
                    }
                    for r in medm_bp
                    if r.get("systolic") and r.get("diastolic")
                ]
                bp_data.pop("cleared_medm", None)
                snap["blood_pressure"] = bp_data
        else:
            # No MedM readings for this calendar day — drop stale date-only stubs on merge.
            snap["blood_pressure"] = {
                "readings_today": [],
                "latest": None,
                "cleared_medm": True,
            }

    snap["source"] = "mi_fitness_auto"
    snap["generated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    return snap


async def _get_tokens() -> XiaomiTokens | None:
    """Load cached tokens or login with env credentials."""
    tokens = XiaomiTokens.load()
    if tokens and tokens.service_token:
        return tokens

    username = os.getenv("XIAOMI_USER")
    password = os.getenv("XIAOMI_PASS")
    if not username or not password:
        return None
    try:
        tokens = await login_xiaomi(username, password)
        return tokens
    except Exception as exc:
        logger.error("Xiaomi login failed: %s", exc)
        return None


async def collect_for_date(target_date: date | None = None) -> dict[str, Any]:
    """Collect from each source independently. Xiaomi is optional."""
    global _last_result, _last_error, _last_sources

    day = target_date or user_local_date()
    raw: dict[str, Any] = {}
    sources: dict[str, Any] = {}

    tokens = await _get_tokens()
    if tokens:
        try:
            client = MiFitnessClient(tokens, region=_REGION)
            await client.connect()
            raw = await client.get_day_summary(day) or {}
            sleep_raw = raw.get("sleep") or []
            sources["mi_fitness"] = {
                "ok": True,
                "keys": [k for k in raw.keys() if k != "date"],
                "sleep_items": len(sleep_raw),
                "sleep_picked": _pick_sleep_for_day(sleep_raw, day) is not None,
            }
        except Exception as exc:
            logger.error("Mi Fitness API error: %s", exc)
            sources["mi_fitness"] = {"ok": False, "error": str(exc)}
            raw = {}
        try:
            home_client = XiaomiHomeClient(tokens, region=_REGION)
            await home_client.connect()
            scale_data = await home_client.get_scale_data()
            filtered = _filter_scale_for_date(scale_data or [], day)
            raw["weight_home"] = filtered
            sources["xiaomi_home"] = {"ok": True, "count": len(filtered)}
            logger.info("Xiaomi Home scale (%s): %d records", day.isoformat(), len(filtered))
        except Exception as exc:
            logger.warning("Xiaomi Home scale fetch failed: %s", exc)
            sources["xiaomi_home"] = {"ok": False, "error": str(exc)}
    else:
        sources["mi_fitness"] = {"ok": False, "error": "not_connected"}
        sources["xiaomi_home"] = {"ok": False, "error": "not_connected"}

    try:
        from medm_bp import fetch_bp_readings, load_creds

        if not load_creds():
            sources["medm"] = {"ok": False, "error": "not_connected"}
        else:
            bp_readings = await fetch_bp_readings(limit=50)
            bp_for_day = _filter_medm_for_date(bp_readings, day)
            raw["medm_bp"] = bp_for_day
            try:
                from blood_pressure_store import store as bp_store

                # Replace prior MedM rows for this day (incl. date-only stubs from old parser).
                bp_store.purge_date_only("medm_bp")
                bp_store.remove_source_on_date("medm_bp", day.isoformat())
                if bp_for_day:
                    bp_store.add_many(
                        [
                            {
                                "systolic": r["systolic"],
                                "diastolic": r["diastolic"],
                                "pulse": r.get("pulse"),
                                "measured_at": r.get("measured_at"),
                                "source": "medm_bp",
                            }
                            for r in bp_for_day
                            if r.get("systolic") and r.get("diastolic")
                        ]
                    )
            except Exception as bp_exc:
                logger.warning("MedM BP store persist failed: %s", bp_exc)
            sources["medm"] = {"ok": True, "count": len(bp_for_day)}
            logger.info("MedM BP (%s): %d readings", day.isoformat(), len(bp_for_day))
    except Exception as exc:
        logger.warning("MedM BP fetch failed: %s", exc)
        sources["medm"] = {"ok": False, "error": str(exc)}

    try:
        from fatsecret_client import fetch_food_entries_for_date, load_tokens

        if not load_tokens():
            sources["fatsecret"] = {"ok": False, "error": "not_connected"}
        else:
            food_entries = fetch_food_entries_for_date(day) or []
            raw["fatsecret_food"] = food_entries
            sources["fatsecret"] = {"ok": True, "count": len(food_entries)}
            logger.info("FatSecret (%s): %d food entries", day.isoformat(), len(food_entries))
    except Exception as exc:
        logger.warning("FatSecret fetch failed: %s", exc)
        sources["fatsecret"] = {"ok": False, "error": str(exc)}

    any_ok = any(bool(s.get("ok")) for s in sources.values())
    snapshot = _normalize_snapshot(raw, day)
    snapshot["sources_status"] = sources

    useful_keys = [
        k
        for k in ("steps", "sleep", "weight", "heart_rate", "blood_pressure", "nutrition", "workouts")
        if k in snapshot
    ]
    if not useful_keys and not any_ok:
        msg = "Не удалось собрать данные ни из одного источника"
        _last_error = msg
        _last_sources = sources
        return {"error": msg, "sources_status": sources}

    try:
        saved = day_store.upsert(snapshot, merge=True)
    except ValueError as exc:
        _last_error = f"Store error: {exc}"
        _last_sources = sources
        return {"error": _last_error, "sources_status": sources}

    saved["sources_status"] = sources
    collected_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    _last_sources = sources
    _last_error = None if any_ok else _last_error
    _last_result = {
        "date": day.isoformat(),
        "collected_at": collected_at,
        "keys": useful_keys,
        "sources": sources,
    }
    logger.info("Data collected: %s", _last_result)
    return saved


async def collect_once() -> dict[str, Any]:
    """Run one collection cycle for today (user local timezone)."""
    return await collect_for_date(user_local_date())


async def backfill_days(days: int = 7) -> list[dict[str, Any]]:
    """Collect and store snapshots for today and previous days."""
    results: list[dict[str, Any]] = []
    today = user_local_date()
    for offset in range(days):
        target = today - timedelta(days=offset)
        result = await collect_for_date(target)
        results.append({"date": target.isoformat(), "ok": "error" not in result, "keys": list(result.keys()) if "error" not in result else [], "error": result.get("error")})
    return results


async def _loop() -> None:
    global _running
    _running = True
    while True:
        try:
            await collect_once()
        except Exception as exc:
            logger.exception("Collector loop error: %s", exc)
        await asyncio.sleep(_INTERVAL_MINUTES * 60)


def start_collector() -> None:
    """Start the background collection task (call from FastAPI lifespan)."""
    global _collector_task
    if _collector_task is not None:
        return
    _collector_task = asyncio.create_task(_loop())
    logger.info("Data collector started (every %d min)", _INTERVAL_MINUTES)


def stop_collector() -> None:
    global _collector_task, _running
    if _collector_task:
        _collector_task.cancel()
        _collector_task = None
    _running = False
