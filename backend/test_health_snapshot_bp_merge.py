from health_snapshot_merge import _merge_blood_pressure, _merge_bp_reading_lists


def test_merge_blood_pressure_unions_and_picks_newest():
    existing = {
        "latest": {"systolic": 130, "diastolic": 85, "measured_at": "2026-08-27T08:00:00"},
        "readings_today": [
            {"systolic": 130, "diastolic": 85, "measured_at": "2026-08-27T08:00:00", "source": "medm_bp"},
        ],
    }
    incoming = {
        "latest": {"systolic": 140, "diastolic": 90, "measured_at": "2026-08-27T14:13:00"},
        "readings_today": [
            {"systolic": 140, "diastolic": 90, "measured_at": "2026-08-27T14:13:00", "source": "medm_bp"},
            {"systolic": 130, "diastolic": 85, "measured_at": "2026-08-27T08:00:00", "source": "medm_bp"},
        ],
    }
    merged = _merge_blood_pressure(existing, incoming)
    assert len(merged["readings_today"]) == 2
    assert merged["latest"]["systolic"] == 140
    assert merged["latest"]["measured_at"] == "2026-08-27T14:13:00"


def test_merge_drops_date_only_when_timed_exists():
    merged = _merge_bp_reading_lists(
        [
            {"systolic": 147, "diastolic": 91, "measured_at": "2026-08-27", "source": "medm_bp"},
            {"systolic": 147, "diastolic": 91, "measured_at": "2026-08-27T14:13:00", "source": "medm_bp"},
            {"systolic": 120, "diastolic": 80, "measured_at": "2026-08-27", "source": "manual"},
        ]
    )
    assert len(merged) == 2
    assert merged[0]["measured_at"] == "2026-08-27T14:13:00"
    assert any(r["systolic"] == 120 and r["measured_at"] == "2026-08-27" for r in merged)
