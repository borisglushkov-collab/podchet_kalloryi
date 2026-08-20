"""Build a plain-text daily report for the coach (copy-paste / API)."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any


_MEAL_RU = {
    "breakfast": "завтрак",
    "lunch": "обед",
    "dinner": "ужин",
    "snack": "перекус",
}


def _fmt_sleep(minutes: int | None) -> str | None:
    if not minutes:
        return None
    hours, mins = divmod(int(minutes), 60)
    return f"{hours}h{mins:02d}"


def _meal_names(nutrition: dict[str, Any]) -> str:
    meals = nutrition.get("meals") or []
    parts: list[str] = []
    for meal in meals:
        mtype = _MEAL_RU.get(str(meal.get("meal_type") or ""), meal.get("meal_type") or "")
        items = meal.get("items") or []
        names = [str(i.get("name") or "").strip() for i in items if str(i.get("name") or "").strip()]
        if names:
            parts.append(f"{mtype}: {', '.join(names)}")
    return "; ".join(parts)


def format_day_report(snapshot: dict[str, Any]) -> str:
    """Human-readable day card the user can paste into any coach chat."""
    date_s = snapshot.get("date") or "—"
    lines = [f"Дата: {date_s}"]

    bp = snapshot.get("blood_pressure") or {}
    latest = bp.get("latest") or {}
    if latest.get("systolic") and latest.get("diastolic"):
        pulse = latest.get("pulse")
        pulse_s = f", пульс {pulse}" if pulse else ""
        at = str(latest.get("measured_at") or latest.get("at") or "")
        time_s = ""
        if "T" in at:
            time_s = " " + at.split("T", 1)[1][:5]
        line = f"АД: {latest['systolic']}/{latest['diastolic']}{pulse_s}{time_s}"
        avg = bp.get("avg_7d") or {}
        if avg.get("systolic") and avg.get("diastolic"):
            line += f", avg 7d: {avg['systolic']}/{avg['diastolic']}"
        lines.append(line)

    readings = bp.get("readings_today") or []
    if len(readings) > 1:
        bits = []
        for r in readings:
            if not r.get("systolic") or not r.get("diastolic"):
                continue
            t = str(r.get("measured_at") or "")
            t_s = t.split("T", 1)[1][:5] if "T" in t else ""
            bits.append(f"{r['systolic']}/{r['diastolic']}" + (f" {t_s}" if t_s else ""))
        if bits:
            lines.append("АД за день: " + "; ".join(bits))

    sleep = snapshot.get("sleep") or {}
    sleep_s = _fmt_sleep(sleep.get("duration_min") or sleep.get("total_min"))
    if sleep_s:
        stages = []
        if sleep.get("deep_min") is not None:
            stages.append(f"глубокий {sleep['deep_min']}м")
        if sleep.get("light_min") is not None:
            stages.append(f"лёгкий {sleep['light_min']}м")
        if sleep.get("rem_min") is not None:
            stages.append(f"REM {sleep['rem_min']}м")
        line = f"Сон: {sleep_s}"
        if stages:
            line += f" ({', '.join(stages)})"
        lines.append(line)

    steps_count = (snapshot.get("steps") or {}).get("count")
    activity = snapshot.get("activity") or {}
    steps_val = steps_count if steps_count is not None else activity.get("steps")
    if steps_val is not None:
        lines.append(f"Шаги: {steps_val}")

    workouts = snapshot.get("workouts") or []
    if workouts:
        bits = []
        for w in workouts:
            parts = [str(w.get("name") or "Тренировка")]
            if w.get("duration_min"):
                parts.append(f"{w['duration_min']} мин")
            if w.get("calories"):
                parts.append(f"{w['calories']} kcal")
            if w.get("avg_hr"):
                parts.append(f"пульс {w['avg_hr']}")
            bits.append(", ".join(parts))
        lines.append("Тренировки: " + "; ".join(bits))

    body = snapshot.get("body_composition") or {}
    weight_obj = snapshot.get("weight") or {}
    weight = body.get("weight_kg")
    if weight is None:
        weight = weight_obj.get("kg")
    if weight is None:
        profile = snapshot.get("profile") or {}
        weight = profile.get("weight_kg_latest")
    if weight is not None:
        lines.append(f"Вес: {weight} кг")

    comp_bits = []
    mapping = (
        ("bmi", "ИМТ", weight_obj.get("bmi"), body.get("bmi")),
        ("bodyFat", "жир", weight_obj.get("bodyFat"), body.get("body_fat_pct")),
        ("muscle", "мышцы", weight_obj.get("muscle"), body.get("muscle_kg")),
        ("water", "вода", weight_obj.get("water"), body.get("water_pct")),
        ("bone", "кость", weight_obj.get("bone"), body.get("bone_kg")),
        ("visceralFat", "висц. жир", weight_obj.get("visceralFat"), body.get("visceral_fat")),
        ("bodyAge", "возраст тела", weight_obj.get("bodyAge"), body.get("body_age")),
        ("bmr", "BMR", weight_obj.get("bmr"), body.get("bmr_kcal")),
        ("bodyScore", "оценка", weight_obj.get("bodyScore"), body.get("body_score")),
        ("heartRate", "пульс", weight_obj.get("heartRate"), body.get("heart_rate")),
        ("skeletalMuscle", "скел. мышцы", weight_obj.get("skeletalMuscle"), body.get("skeletal_muscle_kg")),
        ("protein", "белок", weight_obj.get("protein"), body.get("protein_kg")),
    )
    for _, label, val1, val2 in mapping:
        val = val1 if val1 is not None else val2
        if val is None:
            continue
        suffix = ""
        if label in ("жир", "вода"):
            suffix = "%"
        elif label in ("мышцы", "кость", "скел. мышцы", "белок"):
            suffix = " кг"
        elif label == "BMR":
            suffix = " kcal"
        elif label == "пульс":
            suffix = " bpm"
        comp_bits.append(f"{label} {val}{suffix}")
    if comp_bits:
        lines.append("Состав тела: " + ", ".join(comp_bits))

    nutrition = snapshot.get("nutrition") or {}
    kcal = nutrition.get("calories")
    meal_s = _meal_names(nutrition)
    profile = snapshot.get("profile") or {}
    targets = profile.get("coaching_calorie_target") or {}
    if kcal is not None or meal_s:
        food = f"Еда: {kcal:.0f} kcal" if kcal is not None else "Еда:"
        if meal_s:
            food += f" ({meal_s})"
        lines.append(food)
        macros = []
        if nutrition.get("protein_g") is not None:
            macros.append(f"Б {nutrition['protein_g']:.0f}")
        if nutrition.get("fat_g") is not None:
            macros.append(f"Ж {nutrition['fat_g']:.0f}")
        if nutrition.get("carbs_g") is not None:
            macros.append(f"У {nutrition['carbs_g']:.0f}")
        if macros:
            lines.append("КБЖУ: " + " · ".join(macros))
        kcal_min = targets.get("kcal_min")
        kcal_max = targets.get("kcal_max")
        if kcal is not None and (kcal_min or kcal_max):
            lo = int(kcal_min or 0)
            hi = int(kcal_max or lo)
            if kcal < lo:
                lines.append(f"Vs цель: ниже на {lo - int(kcal)} ккал (цель {lo}–{hi})")
            elif kcal > hi:
                lines.append(f"Vs цель: выше на {int(kcal) - hi} ккал (цель {lo}–{hi})")
            else:
                lines.append(f"Vs цель: в диапазоне {lo}–{hi} ккал")

    meds = [str(m) for m in (profile.get("medications") or []) if str(m).strip()]
    if meds:
        lines.append("Лекарства: " + ", ".join(meds))
    if targets.get("kcal_min") or targets.get("kcal_max"):
        lines.append(
            f"Рабочая цель: {targets.get('kcal_min', '?')}–{targets.get('kcal_max', '?')} ккал"
            + (f", Б {targets['protein_g']}" if targets.get("protein_g") else "")
        )

    notes = snapshot.get("notes")
    if notes:
        lines.append(f"Заметки: {notes}")

    return "\n".join(lines)


def _day_metric(snapshot: dict[str, Any]) -> dict[str, Any]:
    nutrition = snapshot.get("nutrition") or {}
    sleep = snapshot.get("sleep") or {}
    steps = (snapshot.get("steps") or {}).get("count")
    if steps is None:
        steps = (snapshot.get("activity") or {}).get("steps")
    weight = (snapshot.get("weight") or {}).get("kg")
    if weight is None:
        weight = (snapshot.get("body_composition") or {}).get("weight_kg")
    bp = ((snapshot.get("blood_pressure") or {}).get("latest") or {})
    return {
        "date": snapshot.get("date"),
        "calories": nutrition.get("calories"),
        "protein_g": nutrition.get("protein_g"),
        "steps": steps,
        "sleep_min": sleep.get("total_min") or sleep.get("duration_min"),
        "weight_kg": weight,
        "bp_sys": bp.get("systolic"),
        "bp_dia": bp.get("diastolic"),
    }


def format_week_report(snapshots: list[dict[str, Any]], profile: dict[str, Any] | None = None) -> str:
    """Compact 7-day summary for the coach."""
    if not snapshots:
        return "Неделя: нет данных"
    profile = profile or {}
    targets = profile.get("coaching_calorie_target") or {}
    lines = ["Неделя для коуча"]
    cal_vals = []
    step_vals = []
    weight_vals = []
    for snap in snapshots:
        m = _day_metric(snap)
        bits = [m["date"] or "—"]
        if m["calories"] is not None:
            bits.append(f"{int(m['calories'])} ккал")
            cal_vals.append(float(m["calories"]))
        if m["steps"] is not None:
            bits.append(f"{int(m['steps'])} шагов")
            step_vals.append(float(m["steps"]))
        if m["weight_kg"] is not None:
            bits.append(f"{m['weight_kg']} кг")
            weight_vals.append(float(m["weight_kg"]))
        if m["bp_sys"] and m["bp_dia"]:
            bits.append(f"АД {m['bp_sys']}/{m['bp_dia']}")
        if m["sleep_min"]:
            bits.append(f"сон {_fmt_sleep(int(m['sleep_min']))}")
        lines.append(" · ".join(bits) if len(bits) > 1 else f"{bits[0]}: нет данных")

    if cal_vals:
        avg = sum(cal_vals) / len(cal_vals)
        lines.append(f"Средние ккал: {avg:.0f} ({len(cal_vals)} дн.)")
        lo, hi = targets.get("kcal_min"), targets.get("kcal_max")
        if lo or hi:
            lines.append(f"Цель: {lo or '?'}–{hi or '?'} ккал")
            in_range = 0
            for snap in snapshots:
                kcal = (snap.get("nutrition") or {}).get("calories")
                if kcal is None:
                    continue
                if (lo is None or float(kcal) >= float(lo)) and (hi is None or float(kcal) <= float(hi)):
                    in_range += 1
            lines.append(f"Дней в цели: {in_range} из {len(cal_vals)}")
    if step_vals:
        lines.append(f"Средние шаги: {sum(step_vals) / len(step_vals):.0f}")
    if weight_vals:
        lines.append(f"Вес: {weight_vals[0]:.1f} → {weight_vals[-1]:.1f} кг")
    return "\n".join(lines)
