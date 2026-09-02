"""Offline reply when Cursor is unavailable for the health hub."""

from __future__ import annotations

from typing import Any

from coach_health_report import format_day_report


def build_coach_health_fallback(message: str, snapshot: dict[str, Any]) -> str:
    report = format_day_report(snapshot)
    bp = (snapshot.get("blood_pressure") or {}).get("latest") or {}
    sys = bp.get("systolic")
    dia = bp.get("diastolic")
    sleep_min = (snapshot.get("sleep") or {}).get("duration_min") or 0
    steps = (snapshot.get("activity") or {}).get("steps")
    kcal = (snapshot.get("nutrition") or {}).get("calories")
    protein = (snapshot.get("nutrition") or {}).get("protein_g")
    targets = (snapshot.get("profile") or {}).get("coaching_calorie_target") or {}
    kcal_min = targets.get("kcal_min") or 1900
    protein_goal = targets.get("protein_g") or 130

    tips: list[str] = []
    if sys and dia and (int(sys) >= 140 or int(dia) >= 90):
        tips.append(
            "Диастол/систол сегодня высокие — без диагноза: меньше соли и колбас, "
            "к врачу если так держится несколько дней. Edarbi сам не меняйте."
        )
    if sleep_min and int(sleep_min) < 420:
        tips.append("Сна меньше 7 часов — сегодня без жёсткого дефицита калорий, лучше белок и ранний отбой.")
    if steps is not None and int(steps) < 4000:
        tips.append("Шагов мало — достаточно спокойной прогулки 20–30 минут, не надо «добивать норму».")
    if kcal is not None and float(kcal) < float(kcal_min) * 0.75:
        tips.append(
            f"Еды мало относительно рабочей цели (~{kcal_min} ккал). "
            "Лучше добрать творог/яйца/курицу, чем держать сильный недоедаж."
        )
    elif protein is not None and float(protein) < float(protein_goal) * 0.7:
        tips.append(f"Белка пока мало (цель около {protein_goal} г) — творог 0–5%, яйца, куриное филе.")
    if not tips:
        tips.append("День выглядит ровно. Держите рабочую цель по ккал и белку, соль — без фанатизма.")

    q = (message or "").strip()
    head = "Коуч (офлайн, без ИИ). Вот снимок, который я вижу:\n" + report
    body = "Что сделать:\n" + "\n".join(f"• {t}" for t in tips[:4])
    if q:
        return f"{head}\n\nВопрос: {q}\n\n{body}"
    return f"{head}\n\n{body}"
