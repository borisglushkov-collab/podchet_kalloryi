"""Basic tests for nutrition prompt utilities."""

import json

from nutrition_prompt import (
    analyze_weight_context,
    build_top_up_summary_fallback,
    build_user_prompt,
    compute_meal_plan,
    format_profile_context,
    parse_ai_response,
    priority_macros,
)


def test_build_user_prompt():
    prompt = build_user_prompt(
        "dinner",
        {"calories": 1200, "protein": 45, "fat": 40, "carbs": 130},
        {"calories": 2000, "protein": 120, "fat": 65, "carbs": 250},
        {"calories": 200, "protein": 10, "fat": 8, "carbs": 20},
        ["без свинины"],
        "Москва",
        meals_consumed={
            "breakfast": {"calories": 331, "protein": 20, "fat": 21, "carbs": 13},
            "lunch": {"calories": 700, "protein": 45, "fat": 25, "carbs": 60},
            "dinner": {"calories": 200, "protein": 10, "fat": 8, "carbs": 20},
            "snack": {"calories": 0, "protein": 0, "fat": 0, "carbs": 0},
        },
    )
    assert "ужин" in prompt.lower()
    assert "добить" in prompt.lower()
    assert "перенос" in prompt.lower()
    assert "без свинины" in prompt


def test_meal_plan_rollover_to_last_meal():
    plan = compute_meal_plan(
        {"calories": 2000, "protein": 150, "fat": 90, "carbs": 158},
        {
            "breakfast": {"calories": 331, "protein": 20, "fat": 21, "carbs": 13},
            "lunch": {"calories": 700, "protein": 45, "fat": 25, "carbs": 60},
            "dinner": {"calories": 600, "protein": 40, "fat": 20, "carbs": 50},
            "snack": {"calories": 156, "protein": 44, "fat": 10, "carbs": 20},
        },
    )
    assert plan["breakfast"]["deficit"]["calories"] == 169
    assert plan["lunch"]["rollover_in"]["calories"] == 169
    assert plan["snack"]["deficit"]["calories"] == 213
    assert plan["snack"]["is_last"] is True


def test_top_up_summary_fallback_last_meal():
    summary = build_top_up_summary_fallback(
        "перекус",
        {"calories": 113, "protein": 1, "fat": 14, "carbs": 15},
        rollover_in={"calories": 69, "protein": 0, "fat": 5, "carbs": 3},
        is_last=True,
    )
    assert "переноса" in summary.lower()
    assert "113" in summary


def test_priority_macros():
    result = priority_macros({"calories": 100, "protein": 40, "fat": 5, "carbs": 10})
    assert result[0] == "калории"
    assert "белки" in result


def test_parse_ai_response_plain_json():
    data = {"recipes": [], "products": [], "disclaimer": "test"}
    result = parse_ai_response(json.dumps(data))
    assert result["disclaimer"] == "test"


def test_build_user_prompt_with_weight():
    prompt = build_user_prompt(
        "lunch",
        {"calories": 800, "protein": 40, "fat": 30, "carbs": 80},
        {"calories": 2000, "protein": 120, "fat": 65, "carbs": 250},
        {"calories": 0, "protein": 0, "fat": 0, "carbs": 0},
        [],
        "Москва",
        weight_context={
            "current_kg": 78.5,
            "target_kg": 72.0,
            "goal": "lose",
            "entry_count": 5,
            "change_7d_kg": -0.4,
            "trend": "losing",
            "remaining_kg": 6.5,
            "recent_entries": [
                {"date": "2026-07-01", "weight_kg": 79.0},
                {"date": "2026-07-08", "weight_kg": 78.5},
            ],
        },
    )
    assert "график веса" in prompt.lower()
    assert "снижение" in prompt.lower() or "losing" in prompt.lower()


def test_analyze_weight_context_plateau():
    insight = analyze_weight_context(
        {
            "current_kg": 80,
            "target_kg": 75,
            "goal": "lose",
            "entry_count": 4,
            "trend": "plateau",
            "change_7d_kg": 0.1,
        }
    )
    assert insight is not None
    assert "плато" in insight.lower()


def test_format_profile_context():
    block = format_profile_context(
        {
            "gender": "female",
            "age": 52,
            "height_cm": 165,
            "weight_kg": 72,
            "activity": "moderate",
            "goal": "lose",
            "use_custom_targets": False,
        }
    )
    assert "52" in block
    assert "женщина" in block
    assert "50+" in block or "белок" in block.lower()


def test_build_user_prompt_with_profile():
    prompt = build_user_prompt(
        "dinner",
        {"calories": 1200, "protein": 45, "fat": 40, "carbs": 130},
        {"calories": 2000, "protein": 120, "fat": 65, "carbs": 250},
        {"calories": 200, "protein": 10, "fat": 8, "carbs": 20},
        [],
        "Москва",
        profile_context={
            "gender": "male",
            "age": 28,
            "height_cm": 180,
            "weight_kg": 82,
            "activity": "active",
            "goal": "lose",
        },
    )
    assert "профиль пользователя" in prompt.lower()
    assert "28" in prompt
    assert "мужчина" in prompt


def test_goal_practices_in_profile_block():
    block = format_profile_context(
        {
            "gender": "male",
            "age": 40,
            "height_cm": 175,
            "weight_kg": 85,
            "activity": "moderate",
            "goal": "lose",
        }
    )
    assert "рабочие практики" in block.lower()
    assert "белок" in block.lower()
    assert "похудение" in block.lower()


def test_build_user_prompt_requires_goal_linked_fields():
    prompt = build_user_prompt(
        "lunch",
        {"calories": 800, "protein": 40, "fat": 30, "carbs": 80},
        {"calories": 2000, "protein": 120, "fat": 65, "carbs": 250},
        {"calories": 0, "protein": 0, "fat": 0, "carbs": 0},
        [],
        "Москва",
        profile_context={
            "gender": "female",
            "age": 35,
            "height_cm": 165,
            "weight_kg": 68,
            "activity": "light",
            "goal": "maintain",
        },
    )
    assert "why_fits" in prompt
    assert "reason" in prompt
    assert "цели из профиля" in prompt.lower()


def test_analyze_weight_context_empty():
    assert analyze_weight_context(None) is None
    assert analyze_weight_context({"entry_count": 0}) is None


def test_parse_ai_response_markdown():
    data = {"recipes": [{"name": "Омлет"}], "products": []}
    wrapped = f"```json\n{json.dumps(data)}\n```"
    result = parse_ai_response(wrapped)
    assert result["recipes"][0]["name"] == "Омлет"
