from coach_health_report import format_day_report, format_week_report


def test_format_day_report_includes_bp_sleep_food():
    text = format_day_report(
        {
            "date": "2026-08-19",
            "blood_pressure": {
                "latest": {"systolic": 133, "diastolic": 90, "pulse": 72, "measured_at": "2026-08-19T07:32:00"},
                "avg_7d": {"systolic": 136, "diastolic": 91},
                "readings_today": [
                    {"systolic": 133, "diastolic": 90, "measured_at": "2026-08-19T07:32:00"},
                    {"systolic": 128, "diastolic": 84, "measured_at": "2026-08-19T19:00:00"},
                ],
            },
            "sleep": {"duration_min": 419, "deep_min": 80, "light_min": 250, "rem_min": 89},
            "activity": {"steps": 871},
            "body_composition": {"weight_kg": 109},
            "nutrition": {
                "calories": 385,
                "protein_g": 28,
                "fat_g": 22,
                "carbs_g": 18,
                "meals": [
                    {
                        "meal_type": "breakfast",
                        "items": [{"name": "омлет"}, {"name": "колбаса"}],
                    }
                ],
            },
            "profile": {
                "medications": ["Edarbi 80"],
                "coaching_calorie_target": {"kcal_min": 1900, "kcal_max": 2100, "protein_g": 130},
            },
        }
    )
    assert "Дата: 2026-08-19" in text
    assert "133/90" in text
    assert "avg 7d: 136/91" in text
    assert "АД за день:" in text
    assert "Сон: 6h59" in text
    assert "глубокий 80м" in text
    assert "Шаги: 871" in text
    assert "омлет" in text
    assert "Edarbi 80" in text
    assert "1900–2100" in text
    assert "ниже на" in text


def test_format_week_report_averages():
    text = format_week_report(
        [
            {"date": "2026-08-18", "nutrition": {"calories": 2000}, "activity": {"steps": 5000}, "weight": {"kg": 110}},
            {"date": "2026-08-19", "nutrition": {"calories": 1800}, "steps": {"count": 7000}, "weight": {"kg": 109.5}},
        ],
        {"coaching_calorie_target": {"kcal_min": 1900, "kcal_max": 2100}},
    )
    assert "Неделя для коуча" in text
    assert "Средние ккал: 1900" in text
    assert "Дней в цели: 1 из 2" in text
    assert "110.0 → 109.5" in text
