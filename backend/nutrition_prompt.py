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
Главная задача — помочь сформировать диету для человека из профиля по параметрам профиля, анализировать оставшийся дефицит КБЖУ на конкретный приём пищи и добивать до нужного результата. Применять «работающие» практики до достижения цели по указанным параметрам и целям в профиле.

Правила:
- Строй рекомендации от профиля: возраст, пол, рост, вес, активность, цель, предпочтения и динамика веса
- Подбирай блюда и продукты, которые закрывают НЕДОСТАЮЩИЕ калории и макросы на этот приём
- Опирайся на проверенные практики: достаточный белок, клетчатка, регулярность, контроль порций, сон и вода — без экстремальных ограничений
- КБЖУ каждого рецепта должно быть близко к остатку на приём (обычно 70–100% дефицита, не больше 110%)
- Если не хватает белка — предлагай белковые блюда; если жиров — с орехами/авокадо/рыбой; если углеводов — с крупами/хлебом
- Если пользователь уже что-то съел в этом приёме — предлагай ДОПОЛНЕНИЕ, а не полноценный обед с нуля
- Рецепты простые: до 30 минут, до 7 ингредиентов, без экзотики
- Продукты доступны в обычных российских супермаркетах (Перекрёсток, Пятёрочка и т.д.)
- Если на предыдущих приёмах норма не закрыта — недобранное КБЖУ ПЕРЕНОСИТСЯ на следующий приём
- На последнем приёме (перекус) нужно добить ВЕСЬ остаток дня с учётом переноса
- Если есть данные графика веса — учти тренд (снижение/набор/плато) при выборе продуктов и в top_up_summary
- Если есть профиль (возраст, пол, рост, активность) — учти их при подборе продуктов и порций
- В top_up_summary связывай совет с целью из профиля и текущим прогрессом по КБЖУ
- Не ставь медицинских диагнозов, добавь disclaimer
- Ответь ТОЛЬКО валидным JSON без markdown и без пояснений вне JSON

Схема ответа:
{
  "top_up_summary": "Краткий совет: как добить норму на этот приём с учётом профиля и цели (1-2 предложения)",
  "disclaimer": "строка",
  "recipes": [
    {
      "name": "название",
      "cooking_time_min": 15,
      "difficulty": "легко",
      "why_fits": "Почему это помогает добить норму и приблизиться к цели из профиля",
      "ingredients": [{"name": "яйца", "amount": "2 шт"}],
      "steps": ["шаг 1", "шаг 2"],
      "nutrition": {"calories": 320, "protein": 24, "fat": 22, "carbs": 2}
    }
  ],
  "products": [
    {"name": "название продукта для покупки", "reason": "что именно добьёт: белки/жиры/углеводы/калории и как связано с целью"}
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


def analyze_weight_context(weight: dict[str, Any] | None) -> str | None:
    """Build human-readable weight insight from client weight_context payload."""
    if not weight or weight.get("entry_count", 0) < 1:
        return None

    trend = weight.get("trend", "unknown")
    trend_ru = {
        "losing": "снижение веса",
        "gaining": "набор веса",
        "stable": "стабильный вес",
        "plateau": "плато (вес не меняется)",
        "unknown": "недостаточно данных",
    }.get(trend, trend)

    current = weight.get("current_kg")
    target = weight.get("target_kg")
    change_7 = weight.get("change_7d_kg")
    change_30 = weight.get("change_30d_kg")
    remaining = weight.get("remaining_kg")
    goal = weight.get("goal", "")

    parts: list[str] = []
    if current is not None:
        parts.append(f"Текущий вес: {current} кг")
    if target is not None:
        parts.append(f"цель: {target} кг")
    if remaining is not None:
        parts.append(f"до цели: {remaining} кг")
    if change_7 is not None:
        sign = "+" if change_7 > 0 else ""
        parts.append(f"за 7 дней: {sign}{change_7} кг")
    elif change_30 is not None:
        sign = "+" if change_30 > 0 else ""
        parts.append(f"за 30 дней: {sign}{change_30} кг")
    parts.append(f"тренд: {trend_ru}")

    summary = ". ".join(parts).capitalize() + "."

    if trend == "plateau" and goal == "lose":
        recommendation = (
            "Вес на плато — добавьте белок и клетчатку, сократите скрытые калории "
            "(соусы, напитки), проверьте порции."
        )
    elif trend == "gaining" and goal == "lose":
        recommendation = (
            "Вес растёт при цели похудения — урежьте перекусы и простые углеводы, "
            "увеличьте овощи и белок."
        )
    elif trend == "losing" and goal == "lose":
        recommendation = (
            "Вес снижается — сохраняйте белок, чтобы не терять мышцы; "
            "продукты ниже подобраны под текущий темп."
        )
    elif trend == "gaining" and goal == "gain":
        recommendation = (
            "Набор идёт по плану — выбирайте калорийные продукты с белком "
            "и сложными углеводами."
        )
    elif trend == "stable":
        recommendation = "Вес стабилен — сбалансируйте БЖУ и следите за порциями."
    else:
        recommendation = "Записывайте вес регулярно — коуч точнее подстроит продукты."

    return f"{summary} {recommendation}"


_GENDER_RU = {"male": "мужчина", "female": "женщина"}
_ACTIVITY_RU = {
    "sedentary": "минимальная",
    "light": "лёгкая",
    "moderate": "умеренная",
    "active": "высокая",
    "veryActive": "очень высокая",
}
_GOAL_RU = {
    "lose": "похудение",
    "maintain": "поддержание веса",
    "gain": "набор массы",
}


def _age_nutrition_hint(age: int, gender: str) -> str:
    if age < 18:
        return "Подросток — не урезайте калории слишком сильно, нужны белок и кальций."
    if age >= 65:
        return (
            "Возраст 65+ — достаточный белок для мышц, клетчатка, умеренная соль; "
            "простые в приготовлении блюда."
        )
    if age >= 50:
        return (
            "Возраст 50+ — упор на белок, овощи и клетчатку; умеренно с солью и насыщенными жирами."
        )
    if age >= 35:
        return "Возраст 35+ — следите за белком и сложными углеводами, избегайте пустых калорий."
    if gender == "female" and 18 <= age <= 45:
        return "Учти потребность в железе и кальции (бобовые, творог, зелень)."
    return ""


def _goal_practices_hint(goal: str) -> str:
    hints = {
        "lose": (
            "Похудение: умеренный дефицит калорий, белок в каждом приёме, овощи и клетчатка, "
            "контроль порций — без голодовок и экстремальных диет."
        ),
        "maintain": (
            "Поддержание: стабильные калории, баланс БЖУ, регулярные приёмы, "
            "белок и клетчатка для сытости."
        ),
        "gain": (
            "Набор массы: профицит калорий, белок и сложные углеводы, плотные перекусы — "
            "без избытка фастфуда."
        ),
    }
    return hints.get(goal, "")


def format_profile_context(profile: dict[str, Any] | None) -> str:
    """Human-readable profile block for the AI prompt."""
    if not profile:
        return ""

    gender = profile.get("gender", "")
    age = int(profile.get("age") or 30)
    height = profile.get("height_cm")
    weight = profile.get("weight_kg")
    activity = profile.get("activity", "")
    goal = profile.get("goal", "")
    custom = profile.get("use_custom_targets", False)
    target_weight = profile.get("target_weight_kg")

    gender_ru = _GENDER_RU.get(gender, gender)
    activity_ru = _ACTIVITY_RU.get(activity, activity)
    goal_ru = _GOAL_RU.get(goal, goal)
    age_hint = _age_nutrition_hint(age, gender)

    bmi_line = ""
    if height and weight and height > 0:
        bmi = weight / ((height / 100) ** 2)
        bmi_line = f"\n- ИМТ: {bmi:.1f}"

    target_line = ""
    if target_weight is not None:
        target_line = f"\n- Желаемый вес: {target_weight} кг"

    custom_line = "\n- Норма КБЖУ задана вручную в профиле" if custom else ""

    hint_line = f"\n- Учти при подборе: {age_hint}" if age_hint else ""
    practices = _goal_practices_hint(goal)
    practices_line = f"\n- Рабочие практики для цели: {practices}" if practices else ""

    return f"""
Профиль пользователя:
- Пол: {gender_ru}
- Возраст: {age} лет
- Рост: {height} см
- Вес: {weight} кг{bmi_line}{target_line}
- Активность: {activity_ru}
- Цель: {goal_ru}{custom_line}{hint_line}{practices_line}
Строй рекомендации от этого профиля: возраст, пол, вес, активность и цель."""


def profile_insight_short(profile: dict[str, Any] | None) -> str:
    """One-line profile summary for API response / UI."""
    if not profile:
        return ""

    gender = _GENDER_RU.get(profile.get("gender", ""), profile.get("gender", ""))
    age = int(profile.get("age") or 30)
    activity = _ACTIVITY_RU.get(profile.get("activity", ""), profile.get("activity", ""))
    goal = _GOAL_RU.get(profile.get("goal", ""), profile.get("goal", ""))

    parts = [f"{gender.capitalize()}, {age} лет", activity, f"цель: {goal}"]
    hint = _age_nutrition_hint(age, profile.get("gender", ""))
    text = " · ".join(parts)
    if hint:
        text = f"{text}. {hint}"
    return text


def build_user_prompt(
    meal_type: str,
    consumed: dict[str, float],
    targets: dict[str, float],
    meal_consumed: dict[str, float],
    preferences: list[str],
    city: str,
    meals_consumed: dict[str, dict[str, float]] | None = None,
    weight_context: dict[str, Any] | None = None,
    profile_context: dict[str, Any] | None = None,
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
    weight_block = ""
    if weight_context and weight_context.get("entry_count", 0) > 0:
        insight = analyze_weight_context(weight_context)
        if insight:
            recent = weight_context.get("recent_entries") or []
            recent_lines = ""
            if recent:
                points = [
                    f"{e.get('date', '?')}: {e.get('weight_kg', '?')} кг"
                    for e in recent[-5:]
                ]
                recent_lines = "\nПоследние записи: " + ", ".join(points)
            weight_block = f"""
График веса (анализ приложения):
- {insight}{recent_lines}
Учти динамику веса при подборе продуктов — в reason укажи связь с трендом веса."""
    profile_block = format_profile_context(profile_context)
    return f"""Подбери, ЧТО СЪЕСТЬ, чтобы ДОБИТЬ норму на приём пищи: {meal_ru} (базовая доля ~{share_pct}%).
Город: {city}
{profile_block}{last_meal_note}
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

Предпочтения и ограничения: {prefs}{weight_block}

Верни JSON по схеме из системного промпта.
Обязательно:
- top_up_summary — совет с привязкой к цели из профиля и остатку КБЖУ на {meal_ru}
- why_fits в каждом рецепте — как блюдо помогает цели из профиля и добивает норму
- reason у каждого продукта — что добивает по макросам и как связано с целью из профиля"""


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
