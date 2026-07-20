"""Rule-based coach chat reply when Cursor API is unavailable."""

from __future__ import annotations

from typing import Any


_MEAL_RU = {
    "breakfast": "завтрак",
    "lunch": "обед",
    "dinner": "ужин",
    "snack": "перекус",
}


def _ideas_for_meal(meal_type: str, kcal: float, protein: float) -> list[str]:
    """Concrete dish ideas that roughly fit the remaining budget."""
    meal = meal_type if meal_type in _MEAL_RU else "snack"
    light = kcal < 250
    high_protein = protein >= 25

    breakfast = [
        "овсянка на воде + яйцо всмятку",
        "творог 0–5% с ягодами",
        "омлет из 2 яиц + овощи",
        "греческий йогурт + яблоко",
    ]
    lunch = [
        "куриная грудка + гречка + овощи",
        "индейка + булгур + салат",
        "рыбное филе + рис + огурцы",
        "чечевичный суп + хлебец",
    ]
    dinner = [
        "запечённая рыба + овощи",
        "творог/йогурт + овощной салат",
        "куриное филе на пару + капуста",
        "омлет + салат без масла",
    ]
    snack = [
        "творог 0–5% (100–150 г)",
        "греческий йогурт",
        "яйцо + огурец",
        "протеиновый коктейль на воде",
    ]

    pool = {
        "breakfast": breakfast,
        "lunch": lunch,
        "dinner": dinner,
        "snack": snack,
    }[meal]

    if light:
        pool = [p for p in pool if any(k in p for k in ("творог", "йогурт", "яйцо", "омлет", "салат", "овощ"))] or pool[:2]
    if high_protein:
        pool = sorted(
            pool,
            key=lambda s: 0 if any(k in s for k in ("творог", "яйц", "кури", "индей", "рыб", "йогурт", "протеин")) else 1,
        )
    return pool[:3]


def build_coach_chat_fallback(
    message: str,
    *,
    meal_type: str = "dinner",
    daily_deficit: dict[str, float] | None = None,
    meal_deficit: dict[str, float] | None = None,
    preferences: list[str] | None = None,
    profile_context: dict[str, Any] | None = None,
    diary_entries: list[dict[str, Any]] | None = None,
) -> str:
    """Build a short Russian coach reply without calling an LLM."""
    daily = daily_deficit or {}
    meal = meal_deficit or {}
    meal_ru = _MEAL_RU.get(meal_type, meal_type or "приём пищи")
    d_kcal = max(0.0, float(daily.get("calories", 0) or 0))
    d_p = max(0.0, float(daily.get("protein", 0) or 0))
    d_f = max(0.0, float(daily.get("fat", 0) or 0))
    d_c = max(0.0, float(daily.get("carbs", 0) or 0))
    m_kcal = max(0.0, float(meal.get("calories", 0) or 0))
    m_p = max(0.0, float(meal.get("protein", 0) or 0))
    m_f = max(0.0, float(meal.get("fat", 0) or 0))
    m_c = max(0.0, float(meal.get("carbs", 0) or 0))
    # Never exceed daily remaining.
    budget_kcal = min(m_kcal, d_kcal) if d_kcal > 0 else m_kcal
    budget_p = min(m_p, d_p) if d_p > 0 else m_p
    budget_f = min(m_f, d_f) if d_f > 0 else m_f
    budget_c = min(m_c, d_c) if d_c > 0 else m_c

    prefs = [p.strip() for p in (preferences or []) if p and p.strip()]
    pref_note = f" Учту предпочтения: {', '.join(prefs)}." if prefs else ""

    goal = ""
    if profile_context:
        goal = {
            "lose": "похудение",
            "maintain": "поддержание",
            "gain": "набор",
        }.get(str(profile_context.get("goal", "")), "")

    diary_names: list[str] = []
    for raw in (diary_entries or [])[:8]:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name") or "").strip()
        if name and name not in diary_names:
            diary_names.append(name)

    parts: list[str] = []
    parts.append(
        "ИИ сейчас отвечает медленно, поэтому даю быстрый расчёт по вашей норме."
    )
    if diary_names:
        shown = ", ".join(diary_names[:5])
        more = f" и ещё {len(diary_names) - 5}" if len(diary_names) > 5 else ""
        parts.append(
            f"В дневнике уже есть: {shown}{more}. "
            "Ниже — варианты дополнения/замены, без повтора того же."
        )
    parts.append(
        f"На {meal_ru} ориентир: ~{budget_kcal:.0f} ккал · "
        f"Б {budget_p:.0f} · Ж {budget_f:.0f} · У {budget_c:.0f} "
        f"(не больше остатка за день: {d_kcal:.0f} ккал)."
    )

    if budget_kcal < 80:
        parts.append(
            "Калорий почти не осталось — лучше ограничиться водой/чаем "
            "или очень лёгким белковым добором (например, 50–80 г творога 0%), "
            "если белок ещё нужен."
        )
    else:
        ideas = _ideas_for_meal(meal_type, budget_kcal, budget_p)
        blocked: list[str] = []
        for p in prefs:
            pl = p.lower()
            if "без свини" in pl or "не ем свини" in pl:
                blocked.append("свини")
            if "без молока" in pl or "безлактоз" in pl:
                blocked.extend(["творог", "йогурт", "молоч"])
            if "вегетариан" in pl:
                blocked.extend(["кури", "индей", "рыб", "мяс"])
        if blocked:
            ideas = [i for i in ideas if not any(b in i for b in blocked)] or ideas
        bullet = "\n".join(f"• {idea}" for idea in ideas)
        parts.append(f"Варианты в этот бюджет:{pref_note}\n{bullet}")
        if budget_p >= 20:
            parts.append("Сделайте упор на белок — его ещё не хватает до дневной нормы.")
        if goal == "lose":
            parts.append("Для похудения: больше белка и овощей, без лишнего масла и соусов.")
        elif goal == "gain":
            parts.append("Для набора: можно добавить сложные углеводы (гречка/рис) в пределах бюджета.")

    parts.append("Если нужно уточнить продукты или граммы — напишите, что уже есть дома.")
    return "\n\n".join(parts)
