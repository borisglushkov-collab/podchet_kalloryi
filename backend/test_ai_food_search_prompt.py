"""Tests for AI food search JSON parsing."""

from ai_food_search_prompt import parse_ai_food_search_response


def test_parse_ai_food_search_plain():
    text = """
    {
      "items": [
        {
          "name": "Творог 0%",
          "brand": null,
          "kcal_per_100g": 71,
          "protein_per_100g": 16.5,
          "fat_per_100g": 0.2,
          "carbs_per_100g": 1.8,
          "suggested_grams": 150,
          "confidence": 0.9,
          "notes": "типичные значения"
        }
      ]
    }
    """
    items = parse_ai_food_search_response(text)
    assert len(items) == 1
    assert items[0]["name"] == "Творог 0%"
    assert items[0]["suggested_grams"] == 150
    assert items[0]["source"] == "ai_search"


def test_parse_ai_food_search_markdown():
    text = """```json
{"items":[{"name":"Курица","kcal_per_100g":137,"protein_per_100g":30,"fat_per_100g":2,"carbs_per_100g":0}]}
```"""
    items = parse_ai_food_search_response(text)
    assert items[0]["name"] == "Курица"
