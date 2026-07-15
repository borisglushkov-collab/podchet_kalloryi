"""Tests for coach chat prompt builder."""

from coach_chat_prompt import build_coach_chat_prompt


def test_build_coach_chat_prompt_includes_limits():
    prompt = build_coach_chat_prompt(
        "Что съесть на ужин?",
        history=[{"role": "user", "content": "Привет"}, {"role": "assistant", "content": "Здравствуйте!"}],
        meal_type="dinner",
        consumed={"calories": 1800, "protein": 80, "fat": 70, "carbs": 200},
        targets={"calories": 2000, "protein": 150, "fat": 70, "carbs": 200},
        daily_deficit={"calories": 200, "protein": 70, "fat": 0, "carbs": 0},
        meal_deficit={"calories": 200, "protein": 70, "fat": 0, "carbs": 0},
        preferences=["без свинины"],
        profile_context={
            "gender": "male",
            "age": 30,
            "height_cm": 180,
            "weight_kg": 82,
            "activity": "moderate",
            "goal": "lose",
        },
    )
    assert "200" in prompt
    assert "ужин" in prompt.lower()
    assert "без свинины" in prompt
    assert "Что съесть на ужин?" in prompt
    assert "История диалога" in prompt
