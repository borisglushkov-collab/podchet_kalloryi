"""Tests for offline coach chat fallback."""

from coach_chat_fallback import build_coach_chat_fallback


def test_fallback_breakfast_suggestions():
    reply = build_coach_chat_fallback(
        "что съесть на завтрак ?",
        meal_type="breakfast",
        daily_deficit={"calories": 500, "protein": 40, "fat": 20, "carbs": 50},
        meal_deficit={"calories": 400, "protein": 30, "fat": 15, "carbs": 40},
        preferences=[],
        profile_context={"goal": "lose"},
    )
    assert "завтрак" in reply.lower()
    assert "500" in reply or "400" in reply
    assert "•" in reply
    assert "медленн" in reply.lower() or "быстрый" in reply.lower()


def test_fallback_respects_low_calories():
    reply = build_coach_chat_fallback(
        "можно ещё поесть?",
        meal_type="dinner",
        daily_deficit={"calories": 50, "protein": 10, "fat": 0, "carbs": 0},
        meal_deficit={"calories": 400, "protein": 30, "fat": 15, "carbs": 40},
    )
    assert "50" in reply
    assert "почти не осталось" in reply.lower() or "лёгк" in reply.lower()


def test_fallback_mentions_diary():
    reply = build_coach_chat_fallback(
        "что ещё съесть?",
        meal_type="dinner",
        daily_deficit={"calories": 600, "protein": 40, "fat": 20, "carbs": 50},
        meal_deficit={"calories": 500, "protein": 35, "fat": 15, "carbs": 40},
        diary_entries=[
            {"meal_type": "lunch", "name": "Борщ", "grams": 300, "calories": 250},
            {"meal_type": "breakfast", "name": "Овсянка", "grams": 200, "calories": 280},
        ],
    )
    assert "дневник" in reply.lower()
    assert "Борщ" in reply
    assert "Овсянка" in reply
