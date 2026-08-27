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


def test_merge_replaces_prior_medm_day_when_timed_scrape_arrives():
    existing = {
        "latest": {"systolic": 136, "diastolic": 94, "measured_at": "2026-08-27"},
        "readings_today": [
            {"systolic": 136, "diastolic": 94, "measured_at": "2026-08-27", "source": "medm_bp"},
            {"systolic": 134, "diastolic": 94, "measured_at": "2026-08-27", "source": "medm_bp"},
            {"systolic": 120, "diastolic": 80, "measured_at": "2026-08-27T09:00:00", "source": "manual"},
        ],
    }
    incoming = {
        "latest": {"systolic": 147, "diastolic": 91, "measured_at": "2026-08-27T14:13:00"},
        "readings_today": [
            {"systolic": 147, "diastolic": 91, "pulse": 65, "measured_at": "2026-08-27T14:13:00", "source": "medm_bp"},
            {"systolic": 140, "diastolic": 93, "pulse": 56, "measured_at": "2026-08-27T08:05:00", "source": "medm_bp"},
        ],
    }
    merged = _merge_blood_pressure(existing, incoming)
    assert len(merged["readings_today"]) == 3
    assert merged["latest"]["measured_at"] == "2026-08-27T14:13:00"
    assert all(
        "T" in str(r["measured_at"]) for r in merged["readings_today"] if r.get("source") == "medm_bp"
    )
    assert any(r.get("source") == "manual" for r in merged["readings_today"])
