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

from health_day_store import day_store
from xiaomi_auth import XiaomiTokens, login_xiaomi
from xiaomi_fitness import MiFitnessClient
from xiaomi_home import XiaomiHomeClient

logger = logging.getLogger(__name__)

_INTERVAL_MINUTES = int(os.getenv("COLLECT_INTERVAL_MIN", "30"))
_REGION = os.getenv("XIAOMI_REGION", "ru")

_collector_task: asyncio.Task | None = None
_last_result: dict[str, Any] = {}
_last_error: str | None = None
_running = False


def collector_status() -> dict[str, Any]:
    return {
        "running": _running,
        "interval_min": _INTERVAL_MINUTES,
        "region": _REGION,
        "last_result": _last_result,
        "last_error": _last_error,
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


def _normalize_snapshot(raw: dict[str, Any], target_date: date) -> dict[str, Any]:
    """Convert raw Mi Fitness API items into our day-snapshot format."""
    snap: dict[str, Any] = {"date": target_date.isoformat()}

    # Steps — each item.value is JSON like {"steps":10, "distance":5, "calories":2}
    steps_list = raw.get("steps") or []
    if steps_list:
        total_steps = 0
        total_dist = 0
        total_cal = 0
        for item in steps_list:
            v = _parse_value(item)
            total_steps += int(v.get("steps", 0))
            total_dist += int(v.get("distance", 0))
            total_cal += int(v.get("calories", 0))
        snap["steps"] = {"count": total_steps, "distance_m": total_dist, "calories": total_cal}

    # Sleep — value has bedtime, wake_up_time, sleep_deep_duration, etc.
    sleep_list = raw.get("sleep") or []
    if sleep_list:
        total_min = 0
        deep_min = 0
        light_min = 0
        rem_min = 0
        avg_hr = 0
        count = 0
        for item in sleep_list:
            v = _parse_value(item)
            bt = v.get("bedtime") or v.get("device_bedtime")
            wt = v.get("wake_up_time") or v.get("device_wake_up_time")
            if bt and wt:
                dur = max(0, int(wt) - int(bt)) // 60
                total_min += dur
            deep_min += int(v.get("sleep_deep_duration", 0))
            light_min += int(v.get("sleep_light_duration", 0))
            rem_min += int(v.get("sleep_rem_duration", 0))
            hr = v.get("avg_hr")
            if hr:
                avg_hr += int(hr)
                count += 1
        snap["sleep"] = {
            "total_min": total_min,
            "deep_min": deep_min,
            "light_min": light_min,
            "rem_min": rem_min,
        }
        if count:
            snap["sleep"]["avg_hr"] = round(avg_hr / count)

    # Weight from Xiaomi Home scale (body composition)
    home_weight = raw.get("weight_home") or []
    if home_weight:
        latest_hw = home_weight[-1] if home_weight else {}
        bd = latest_hw.get("bodyData") or latest_hw
        w = bd.get("weight")
        if w is not None:
            try:
                snap["weight"] = {"kg": round(float(w), 1)}
                for field in ("bmi", "bodyFat", "muscle", "water", "bone", "visceralFat", "bodyAge", "bmr"):
                    val = bd.get(field)
                    if val is not None:
                        snap["weight"][field] = round(float(val), 1)
            except (ValueError, TypeError):
                pass

    # Weight from Mi Fitness (fallback if no Xiaomi Home data)
    weight_list = raw.get("weight") or []
    if weight_list and "weight" not in snap:
        latest_v = _parse_value(weight_list[-1])
        w = latest_v.get("weight")
        if w is not None:
            try:
                snap["weight"] = {"kg": round(float(w), 1)}
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

    # Blood pressure
    bp_list = raw.get("blood_pressure") or []
    if bp_list:
        latest_v = _parse_value(bp_list[-1])
        sys_val = latest_v.get("systolic") or latest_v.get("sys")
        dia_val = latest_v.get("diastolic") or latest_v.get("dia")
        if sys_val and dia_val:
            snap["blood_pressure"] = {
                "latest": {"systolic": int(sys_val), "diastolic": int(dia_val)},
            }

    # FatSecret food diary
    food_entries = raw.get("fatsecret_food") or []
    if food_entries:
        total_cal = sum(e.get("calories", 0) for e in food_entries)
        total_p = sum(e.get("protein", 0) for e in food_entries)
        total_f = sum(e.get("fat", 0) for e in food_entries)
        total_c = sum(e.get("carbs", 0) for e in food_entries)
        meals_by_type: dict[str, list] = {}
        for e in food_entries:
            mt = e.get("meal", "snack") or "snack"
            meals_by_type.setdefault(mt, []).append(e)
        snap["nutrition"] = {
            "calories": round(total_cal),
            "protein_g": round(total_p),
            "fat_g": round(total_f),
            "carbs_g": round(total_c),
            "meals": [
                {"meal_type": mt, "items": items}
                for mt, items in meals_by_type.items()
            ],
            "source": "fatsecret",
        }

    # MedM blood pressure
    medm_bp = raw.get("medm_bp") or []
    if medm_bp:
        latest_bp = medm_bp[0]
        sys_val = latest_bp.get("systolic")
        dia_val = latest_bp.get("diastolic")
        if sys_val and dia_val:
            bp_data = snap.get("blood_pressure", {})
            bp_data["latest"] = {
                "systolic": int(sys_val),
                "diastolic": int(dia_val),
                "pulse": latest_bp.get("pulse"),
                "source": "medm_bp",
            }
            bp_data["readings_today"] = [
                {"systolic": r["systolic"], "diastolic": r["diastolic"], "pulse": r.get("pulse"), "measured_at": r.get("measured_at"), "source": "medm_bp"}
                for r in medm_bp if r.get("systolic") and r.get("diastolic")
            ]
            snap["blood_pressure"] = bp_data

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


async def collect_once() -> dict[str, Any]:
    """Run one collection cycle. Returns the saved snapshot or error dict."""
    global _last_result, _last_error

    tokens = await _get_tokens()
    if not tokens:
        _last_error = "No Xiaomi credentials configured"
        return {"error": _last_error}

    client = MiFitnessClient(tokens, region=_REGION)
    try:
        await client.connect()
        raw = await client.get_today_summary()
    except Exception as exc:
        _last_error = f"Mi Fitness API error: {exc}"
        logger.error(_last_error)
        return {"error": _last_error}

    # Try Xiaomi Home for scale data (weight/body composition)
    try:
        home_client = XiaomiHomeClient(tokens, region=_REGION)
        await home_client.connect()
        scale_data = await home_client.get_scale_data(model="yunmai.scales.ms104")
        if scale_data:
            raw["weight_home"] = scale_data
            logger.info("Xiaomi Home scale: %d records", len(scale_data))
    except Exception as exc:
        logger.warning("Xiaomi Home scale fetch failed: %s", exc)

    # Try MedM BP
    try:
        from medm_bp import fetch_bp_readings
        bp_readings = await fetch_bp_readings(limit=20)
        if bp_readings:
            raw["medm_bp"] = bp_readings
            logger.info("MedM BP: %d readings", len(bp_readings))
    except Exception as exc:
        logger.warning("MedM BP fetch failed: %s", exc)

    # Try FatSecret food diary
    try:
        from fatsecret_client import fetch_food_entries_today
        food_entries = fetch_food_entries_today()
        if food_entries:
            raw["fatsecret_food"] = food_entries
            logger.info("FatSecret: %d food entries", len(food_entries))
    except Exception as exc:
        logger.warning("FatSecret fetch failed: %s", exc)

    today = date.today()
    snapshot = _normalize_snapshot(raw, today)
    try:
        saved = day_store.upsert(snapshot)
    except ValueError as exc:
        _last_error = f"Store error: {exc}"
        return {"error": _last_error}

    _last_error = None
    _last_result = {
        "date": today.isoformat(),
        "collected_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "keys": [k for k in ("steps", "sleep", "weight", "heart_rate", "blood_pressure") if k in snapshot],
    }
    logger.info("Data collected: %s", _last_result)
    return saved


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
