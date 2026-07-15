"""Prompt and JSON parsing for AI text food lookup."""

import json
import re
from typing import Any

AI_FOOD_SEARCH_PROMPT = """Ты справочник КБЖУ для пользователей из России.
По текстовому запросу пользователя найди или оцени продукт/блюдо и верни КБЖУ.

Правила:
- Название на русском
- КБЖУ на 100 г (если в запросе порция — всё равно дай per 100g и suggested_grams)
- Если указана порция («200 г курицы», «2 яйца») — оцени suggested_grams
- Можно вернуть 1–5 вариантов (разные бренды/способы приготовления), от более точного к менее
- confidence 0–1
- notes — коротко: откуда оценка / что учёл
- Если запрос не про еду — items: []
- Ответь ТОЛЬКО валидным JSON без markdown

Схема:
{
  "items": [
    {
      "name": "Куриная грудка варёная",
      "brand": null,
      "kcal_per_100g": 137,
      "protein_per_100g": 29.8,
      "fat_per_100g": 1.8,
      "carbs_per_100g": 0.5,
      "suggested_grams": 200,
      "confidence": 0.85,
      "notes": "Типичные значения для варёной грудки"
    }
  ]
}"""


def parse_ai_food_search_response(text: str) -> list[dict[str, Any]]:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", text)
        if not match:
            raise ValueError("Ответ ИИ не является JSON") from None
        data = json.loads(match.group())

    raw_items = data.get("items") if isinstance(data, dict) else data
    if not isinstance(raw_items, list):
        raise ValueError("В ответе ИИ нет списка items")

    items: list[dict[str, Any]] = []
    for raw in raw_items[:5]:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name", "")).strip()
        if not name:
            continue
        items.append(
            {
                "name": name,
                "brand": raw.get("brand"),
                "kcal_per_100g": float(raw.get("kcal_per_100g") or 0),
                "protein_per_100g": float(raw.get("protein_per_100g") or 0),
                "fat_per_100g": float(raw.get("fat_per_100g") or 0),
                "carbs_per_100g": float(raw.get("carbs_per_100g") or 0),
                "suggested_grams": float(raw.get("suggested_grams") or 100),
                "confidence": float(raw.get("confidence") or 0.5),
                "notes": str(raw.get("notes") or "").strip(),
                "source": "ai_search",
            }
        )
    return items
