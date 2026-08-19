from health_snapshot_merge import merge_snapshots


def test_merge_preserves_fatsecret_when_client_sync_empty():
    existing = {
        "date": "2026-08-19",
        "nutrition": {
            "calories": 1138,
            "source": "fatsecret",
            "meals": [
                {
                    "meal_type": "breakfast",
                    "items": [{"name": "Хлеб", "calories": 66, "protein_g": 1.9, "fat_g": 0.8, "carbs_g": 12.7}],
                }
            ],
        },
        "steps": {"count": 4034},
    }
    incoming = {
        "date": "2026-08-19",
        "nutrition": {"calories": 0, "meals": []},
        "activity": {"steps": 4034, "source": "manual"},
        "notes": "",
    }
    merged = merge_snapshots(existing, incoming)
    assert merged["nutrition"]["source"] == "fatsecret"
    assert len(merged["nutrition"]["meals"][0]["items"]) == 1
    assert merged["steps"]["count"] == 4034


def test_merge_prefers_new_fatsecret_payload():
    existing = {
        "date": "2026-08-19",
        "nutrition": {
            "calories": 500,
            "source": "fatsecret",
            "meals": [{"meal_type": "breakfast", "items": [{"name": "Old"}]}],
        },
    }
    incoming = {
        "date": "2026-08-19",
        "nutrition": {
            "calories": 1138,
            "source": "fatsecret",
            "meals": [
                {"meal_type": "breakfast", "items": [{"name": "A"}, {"name": "B"}]},
                {"meal_type": "lunch", "items": [{"name": "C"}]},
            ],
        },
    }
    merged = merge_snapshots(existing, incoming)
    assert merged["nutrition"]["calories"] == 1138
    assert len(merged["nutrition"]["meals"]) == 2
