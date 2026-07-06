"""System prompt and JSON parsing for nutrition AI suggestions."""

import json
import re
from typing import Any

SYSTEM_PROMPT = """Ты диетолог-помощник для пользователей из России.
Твоя задача — предложить простые блюда и продукты для следующего приёма пищи.

Правила:
- Рецепты простые: до 30 минут, до 7 ингредиентов, без экзотики
- Продукты доступны в обычных российских супермаркетах (Перекрёсток, Пятёрочка и т.д.)
- Учитывай дефицит калорий и БЖУ от дневной нормы
- Не ставь медицинских диагнозов, добавь disclaimer
- Ответь ТОЛЬКО валидным JSON без markdown и без пояснений вне JSON

Схема ответа:
{
  "disclaimer": "строка",
  "recipes": [
    {
      "name": "название",
      "cooking_time_min": 15,
      "difficulty": "легко",
      "ingredients": [{"name": "яйца", "amount": "2 шт"}],
      "steps": ["шаг 1", "шаг 2"],
      "nutrition": {"calories": 320, "protein": 24, "fat": 22, "carbs": 2}
    }
  ],
  "products": [
    {"name": "название продукта для покупки", "reason": "зачем нужен"}
  ]
}

Предложи 2-3 рецепта и 3-5 продуктов для покупки."""


def build_user_prompt(
    meal_type: str,
    consumed: dict[str, float],
    targets: dict[str, float],
    preferences: list[str],
    city: str,
) -> str:
    deficit = {
        "calories": max(0, targets.get("calories", 0) - consumed.get("calories", 0)),
        "protein": max(0, targets.get("protein", 0) - consumed.get("protein", 0)),
        "fat": max(0, targets.get("fat", 0) - consumed.get("fat", 0)),
        "carbs": max(0, targets.get("carbs", 0) - consumed.get("carbs", 0)),
    }
    meal_names = {
        "breakfast": "завтрак",
        "lunch": "обед",
        "dinner": "ужин",
        "snack": "перекус",
    }
    meal_ru = meal_names.get(meal_type, meal_type)
    prefs = ", ".join(preferences) if preferences else "нет"
    return f"""Подбери блюда для приёма пищи: {meal_ru}.
Город: {city}

Уже съедено сегодня:
- Калории: {consumed.get('calories', 0):.0f} ккал
- Белки: {consumed.get('protein', 0):.1f} г
- Жиры: {consumed.get('fat', 0):.1f} г
- Углеводы: {consumed.get('carbs', 0):.1f} г

Дневная норма:
- Калории: {targets.get('calories', 0):.0f} ккал
- Белки: {targets.get('protein', 0):.1f} г
- Жиры: {targets.get('fat', 0):.1f} г
- Углеводы: {targets.get('carbs', 0):.1f} г

Осталось до нормы:
- Калории: {deficit['calories']:.0f} ккал
- Белки: {deficit['protein']:.1f} г
- Жиры: {deficit['fat']:.1f} г
- Углеводы: {deficit['carbs']:.1f} г

Предпочтения и ограничения: {prefs}

Верни JSON по схеме из системного промпта."""


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
