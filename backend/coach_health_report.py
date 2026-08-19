"""Build a plain-text daily report for the coach (copy-paste / API)."""

from __future__ import annotations

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
    date = snapshot.get("date") or "—"
    lines = [f"Дата: {date}"]

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

    sleep = snapshot.get("sleep") or {}
    sleep_s = _fmt_sleep(sleep.get("duration_min"))
    if sleep_s:
        lines.append(f"Сон: {sleep_s}")

    activity = snapshot.get("activity") or {}
    if activity.get("steps") is not None:
        lines.append(f"Шаги: {activity['steps']}")

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

    profile = snapshot.get("profile") or {}
    meds = [str(m) for m in (profile.get("medications") or []) if str(m).strip()]
    if meds:
        lines.append("Лекарства: " + ", ".join(meds))
    targets = profile.get("coaching_calorie_target") or {}
    if targets.get("kcal_min") or targets.get("kcal_max"):
        lines.append(
            f"Рабочая цель: {targets.get('kcal_min', '?')}–{targets.get('kcal_max', '?')} ккал"
            + (f", Б {targets['protein_g']}" if targets.get("protein_g") else "")
        )

    notes = snapshot.get("notes")
    if notes:
        lines.append(f"Заметки: {notes}")

    return "\n".join(lines)
