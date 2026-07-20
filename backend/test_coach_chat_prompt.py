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


def test_build_coach_chat_prompt_includes_diary():
    prompt = build_coach_chat_prompt(
        "Что добавить?",
        meal_type="dinner",
        consumed={"calories": 900, "protein": 40, "fat": 30, "carbs": 90},
        targets={"calories": 2000, "protein": 120, "fat": 65, "carbs": 250},
        daily_deficit={"calories": 1100, "protein": 80, "fat": 35, "carbs": 160},
        meal_deficit={"calories": 500, "protein": 40, "fat": 20, "carbs": 60},
        diary_entries=[
            {
                "meal_type": "breakfast",
                "name": "Творог 5%",
                "grams": 150,
                "calories": 180,
                "protein": 24,
                "fat": 7,
                "carbs": 5,
            }
        ],
    )
    assert "Творог 5%" in prompt
    assert "дневник" in prompt.lower()
    assert "с опорой на дневник" in prompt.lower()
