"""System prompt and JSON parsing for nutrition AI suggestions."""

import json
import re
from typing import Any

MEAL_SHARES: dict[str, float] = {
    "breakfast": 0.25,
    "lunch": 0.35,
    "dinner": 0.30,
    "snack": 0.10,
}

MEAL_ORDER: list[str] = ["breakfast", "lunch", "dinner", "snack"]

_MACRO_KEYS = ("calories", "protein", "fat", "carbs")

SYSTEM_PROMPT = """Ты диетолог-помощник для пользователей из России.
Главная задача — помочь ДОБИТЬ оставшийся дефицит КБЖУ на КОНКРЕТНЫЙ приём пищи (завтрак, обед, ужин или перекус).

Правила:
- Подбирай блюда и продукты, которые закрывают НЕДОСТАЮЩИЕ калории и макросы на этот приём
- КБЖУ каждого рецепта должно быть близко к остатку на приём (обычно 70–100% дефицита, не больше 110%)
- Если не хватает белка — предлагай белковые блюда; если жиров — с орехами/авокадо/рыбой; если углеводов — с крупами/хлебом
- Если пользователь уже что-то съел в этом приёме — предлагай ДОПОЛНЕНИЕ, а не полноценный обед с нуля
- Рецепты простые: до 30 минут, до 7 ингредиентов, без экзотики
- Продукты доступны в обычных российских супермаркетах (Перекрёсток, Пятёрочка и т.д.)
- Если на предыдущих приёмах норма не закрыта — недобранное КБЖУ ПЕРЕНОСИТСЯ на следующий приём
- На последнем приёме (перекус) нужно добить ВЕСЬ остаток дня с учётом переноса
- Не ставь медицинских диагнозов, добавь disclaimer
- Ответь ТОЛЬКО валидным JSON без markdown и без пояснений вне JSON

Схема ответа:
{
  "top_up_summary": "Краткий совет: что съесть, чтобы добить норму на этот приём (1-2 предложения)",
  "disclaimer": "строка",
  "recipes": [
    {
      "name": "название",
      "cooking_time_min": 15,
      "difficulty": "легко",
      "why_fits": "Почему это помогает добить норму, например: покрывает недостающие белки и ~85% калорий на ужин",
      "ingredients": [{"name": "яйца", "amount": "2 шт"}],
      "steps": ["шаг 1", "шаг 2"],
      "nutrition": {"calories": 320, "protein": 24, "fat": 22, "carbs": 2}
    }
  ],
  "products": [
    {"name": "название продукта для покупки", "reason": "что именно добьёт: белки/жиры/углеводы/калории"}
  ]
}

Предложи 2-3 рецепта и 3-5 продуктов для покупки."""


def _scale_macros(macros: dict[str, float], share: float) -> dict[str, float]:
    return {key: macros.get(key, 0) * share for key in ("calories", "protein", "fat", "carbs")}


def meal_targets_from_daily(targets: dict[str, float], meal_type: str) -> dict[str, float]:
    share = MEAL_SHARES.get(meal_type, 0.25)
    return _scale_macros(targets, share)


def _zero_macros() -> dict[str, float]:
    return {key: 0.0 for key in _MACRO_KEYS}


def _add_macros(a: dict[str, float], b: dict[str, float]) -> dict[str, float]:
    return {key: a.get(key, 0) + b.get(key, 0) for key in _MACRO_KEYS}


def _deficit_macros(target: dict[str, float], consumed: dict[str, float]) -> dict[str, float]:
    return {
        key: max(0, target.get(key, 0) - consumed.get(key, 0)) for key in _MACRO_KEYS
    }


def compute_meal_plan(
    targets: dict[str, float],
    meals_consumed: dict[str, dict[str, float]],
) -> dict[str, dict[str, Any]]:
    rollover = _zero_macros()
    plan: dict[str, dict[str, Any]] = {}

    for index, meal_type in enumerate(MEAL_ORDER):
        base = meal_targets_from_daily(targets, meal_type)
        consumed = meals_consumed.get(meal_type, _zero_macros())
        effective = _add_macros(base, rollover)
        deficit = _deficit_macros(effective, consumed)
        plan[meal_type] = {
            "base": base,
            "rollover_in": dict(rollover),
            "effective": effective,
            "consumed": consumed,
            "deficit": deficit,
            "is_last": index == len(MEAL_ORDER) - 1,
        }
        rollover = deficit

    return plan


def meal_plan_for_type(
    targets: dict[str, float],
    meals_consumed: dict[str, dict[str, float]],
    meal_type: str,
) -> dict[str, Any]:
    return compute_meal_plan(targets, meals_consumed)[meal_type]


_MACRO_LABELS = {
    "calories": "калории",
    "protein": "белки",
    "fat": "жиры",
    "carbs": "углеводы",
}


def priority_macros(deficit: dict[str, float], limit: int = 2) -> list[str]:
    scored = sorted(
        ((key, deficit.get(key, 0)) for key in _MACRO_LABELS),
        key=lambda item: item[1],
        reverse=True,
    )
    return [_MACRO_LABELS[key] for key, value in scored if value > 0][:limit]


def build_top_up_summary_fallback(
    meal_ru: str,
    meal_deficit: dict[str, float],
    *,
    rollover_in: dict[str, float] | None = None,
    is_last: bool = False,
) -> str:
    rollover_in = rollover_in or _zero_macros()
    calories_left = meal_deficit.get("calories", 0)
    if calories_left < 50:
        return (
            f"Норма на {meal_ru} почти закрыта. Можно взять лёгкий перекус "
            "или ничего не добавлять."
        )
    priorities = priority_macros(meal_deficit)
    joined = " и ".join(priorities) if priorities else "сбалансированно"
    rollover_cal = rollover_in.get("calories", 0)
    if is_last and rollover_cal > 0:
        return (
            f"Последний приём — добейте {calories_left:.0f} ккал, включая "
            f"{rollover_cal:.0f} ккал переноса с предыдущих приёмов. "
            f"Упор на {joined}."
        )
    if rollover_cal > 0:
        return (
            f"Чтобы закрыть {meal_ru}, съешьте ~{calories_left:.0f} ккал "
            f"(в т.ч. {rollover_cal:.0f} ккал переноса) с упором на {joined}."
        )
    return (
        f"Чтобы добить {meal_ru}, съешьте блюдо примерно на {calories_left:.0f} ккал "
        f"с упором на {joined}."
    )


def build_user_prompt(
    meal_type: str,
    consumed: dict[str, float],
    targets: dict[str, float],
    meal_consumed: dict[str, float],
    preferences: list[str],
    city: str,
    meals_consumed: dict[str, dict[str, float]] | None = None,
) -> str:
    if meals_consumed is None:
        meals_consumed = {meal_type: meal_consumed}

    plan = meal_plan_for_type(targets, meals_consumed, meal_type)
    meal_targets = plan["base"]
    meal_effective = plan["effective"]
    meal_deficit = plan["deficit"]
    rollover_in = plan["rollover_in"]
    is_last = plan["is_last"]

    daily_deficit = _deficit_macros(targets, consumed)
    meal_names = {
        "breakfast": "завтрак",
        "lunch": "обед",
        "dinner": "ужин",
        "snack": "перекус",
    }
    meal_ru = meal_names.get(meal_type, meal_type)
    share_pct = int(MEAL_SHARES.get(meal_type, 0.25) * 100)
    prefs = ", ".join(preferences) if preferences else "нет"
    priorities = priority_macros(meal_deficit)
    priority_text = ", ".join(priorities) if priorities else "сбалансированно"
    rollover_block = ""
    if rollover_in.get("calories", 0) > 0 or rollover_in.get("protein", 0) > 0:
        rollover_block = (
            f"\nПеренос с предыдущих приёмов (не закрыли раньше):\n"
            f"- Калории: {rollover_in['calories']:.0f} ккал\n"
            f"- Белки: {rollover_in['protein']:.1f} г\n"
            f"- Жиры: {rollover_in['fat']:.1f} г\n"
            f"- Углеводы: {rollover_in['carbs']:.1f} г\n"
        )
    last_meal_note = (
        "\nЭто ПОСЛЕДНИЙ приём дня — добей весь остаток дневной нормы с учётом переноса.\n"
        if is_last
        else ""
    )
    return f"""Подбери, ЧТО СЪЕСТЬ, чтобы ДОБИТЬ норму на приём пищи: {meal_ru} (базовая доля ~{share_pct}%).
Город: {city}
{last_meal_note}
Базовая цель на {meal_ru}:
- Калории: {meal_targets['calories']:.0f} ккал
- Белки: {meal_targets['protein']:.1f} г
- Жиры: {meal_targets['fat']:.1f} г
- Углеводы: {meal_targets['carbs']:.1f} г
{rollover_block}
Цель с учётом переноса на {meal_ru}:
- Калории: {meal_effective['calories']:.0f} ккал
- Белки: {meal_effective['protein']:.1f} г
- Жиры: {meal_effective['fat']:.1f} г
- Углеводы: {meal_effective['carbs']:.1f} г

Уже съедено в этом приёме ({meal_ru}):
- Калории: {meal_consumed.get('calories', 0):.0f} ккал
- Белки: {meal_consumed.get('protein', 0):.1f} г
- Жиры: {meal_consumed.get('fat', 0):.1f} г
- Углеводы: {meal_consumed.get('carbs', 0):.1f} г

ОСТАЛОСЬ ДОБИТЬ на этот приём ({meal_ru}) — подбирай рецепты именно под этот остаток:
- Калории: {meal_deficit['calories']:.0f} ккал
- Белки: {meal_deficit['protein']:.1f} г
- Жиры: {meal_deficit['fat']:.1f} г
- Углеводы: {meal_deficit['carbs']:.1f} г

Приоритет при подборе: {priority_text}

Справочно, за весь день уже съедено:
- Калории: {consumed.get('calories', 0):.0f} / {targets.get('calories', 0):.0f} ккал
- Белки: {consumed.get('protein', 0):.1f} / {targets.get('protein', 0):.1f} г
- Жиры: {consumed.get('fat', 0):.1f} / {targets.get('fat', 0):.1f} г
- Углеводы: {consumed.get('carbs', 0):.1f} / {targets.get('carbs', 0):.1f} г

Осталось добить за день:
- Калории: {daily_deficit['calories']:.0f} ккал
- Белки: {daily_deficit['protein']:.1f} г
- Жиры: {daily_deficit['fat']:.1f} г
- Углеводы: {daily_deficit['carbs']:.1f} г

Предпочтения и ограничения: {prefs}

Верни JSON по схеме из системного промпта. В top_up_summary объясни, как добить норму на {meal_ru}."""


def parse_ai_response(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", text)
        if match:
            return json.loads(match.group())
        raise ValueError("AI response is not valid JSON") from None
