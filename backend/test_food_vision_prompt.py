from food_vision_prompt import parse_food_vision_response


def test_parse_food_vision_response():
    raw = """
    {
      "name": "Гречка с курицей",
      "brand": null,
      "kcal_per_100g": 145,
      "protein_per_100g": 12,
      "fat_per_100g": 4,
      "carbs_per_100g": 16,
      "suggested_grams": 280,
      "confidence": 0.82,
      "notes": "Тарелка с гарниром и курицей"
    }
    """
    item = parse_food_vision_response(raw)
    assert item["name"] == "Гречка с курицей"
    assert item["suggested_grams"] == 280
    assert item["source"] == "ai_vision"
