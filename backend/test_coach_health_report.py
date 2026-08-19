from coach_health_report import format_day_report


def test_format_day_report_includes_bp_sleep_food():
    text = format_day_report(
        {
            "date": "2026-08-19",
            "blood_pressure": {
                "latest": {"systolic": 133, "diastolic": 90, "pulse": 72, "measured_at": "2026-08-19T07:32:00"},
                "avg_7d": {"systolic": 136, "diastolic": 91},
            },
            "sleep": {"duration_min": 419},
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
    assert "Сон: 6h59" in text
    assert "Шаги: 871" in text
    assert "омлет" in text
    assert "Edarbi 80" in text
    assert "1900–2100" in text
