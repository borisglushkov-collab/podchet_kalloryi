"""Basic tests for nutrition prompt utilities."""

import json

from nutrition_prompt import build_user_prompt, parse_ai_response


def test_build_user_prompt():
    prompt = build_user_prompt(
        "dinner",
        {"calories": 1200, "protein": 45, "fat": 40, "carbs": 130},
        {"calories": 2000, "protein": 120, "fat": 65, "carbs": 250},
        ["без свинины"],
        "Москва",
    )
    assert "ужин" in prompt.lower()
    assert "1200" in prompt
    assert "без свинины" in prompt


def test_parse_ai_response_plain_json():
    data = {"recipes": [], "products": [], "disclaimer": "test"}
    result = parse_ai_response(json.dumps(data))
    assert result["disclaimer"] == "test"


def test_parse_ai_response_markdown():
    data = {"recipes": [{"name": "Омлет"}], "products": []}
    wrapped = f"```json\n{json.dumps(data)}\n```"
    result = parse_ai_response(wrapped)
    assert result["recipes"][0]["name"] == "Омлет"
