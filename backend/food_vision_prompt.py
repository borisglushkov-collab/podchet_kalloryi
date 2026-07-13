"""Prompt and JSON parsing for food photo analysis."""

import json
import re
from typing import Any

FOOD_VISION_PROMPT = """Ты диетолог-помощник. По фото еды определи блюдо или продукт и оцени КБЖУ.

Правила:
- Название на русском языке
- КБЖУ на 100 г продукта (оценка, если точных данных нет)
- suggested_grams — оценка веса порции на фото в граммах
- confidence от 0 до 1 — насколько уверен в распознавании
- notes — 1 короткое предложение: что видишь и как оценил порцию
- Если на фото упаковка со штрихкодом — укажи это в notes
- Ответь ТОЛЬКО валидным JSON без markdown

Схема:
{
  "name": "название блюда",
  "brand": null,
  "kcal_per_100g": 0,
  "protein_per_100g": 0,
  "fat_per_100g": 0,
  "carbs_per_100g": 0,
  "suggested_grams": 250,
  "confidence": 0.7,
  "notes": "краткое пояснение"
}"""


def parse_food_vision_response(text: str) -> dict[str, Any]:
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

    return {
        "name": str(data.get("name", "Блюдо")).strip() or "Блюдо",
        "brand": data.get("brand"),
        "kcal_per_100g": float(data.get("kcal_per_100g") or 0),
        "protein_per_100g": float(data.get("protein_per_100g") or 0),
        "fat_per_100g": float(data.get("fat_per_100g") or 0),
        "carbs_per_100g": float(data.get("carbs_per_100g") or 0),
        "suggested_grams": float(data.get("suggested_grams") or 100),
        "confidence": float(data.get("confidence") or 0.5),
        "notes": str(data.get("notes") or "").strip(),
        "source": "ai_vision",
    }
