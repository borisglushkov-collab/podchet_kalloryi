from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from data_collector import _filter_scale_for_date, _pick_sleep_for_day


MSK = ZoneInfo("Europe/Moscow")


def _ts(year, month, day, hour, minute=0):
    return int(datetime(year, month, day, hour, minute, tzinfo=MSK).timestamp())


def test_pick_sleep_does_not_sum_two_nights():
    # Night ending Aug 19 (~7h) and night ending Aug 20 (~8h)
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 18, 23, 0),
                "wake_up_time": _ts(2026, 8, 19, 6, 0),
                "sleep_deep_duration": 90,
                "sleep_light_duration": 250,
                "sleep_rem_duration": 80,
                "avg_hr": 62,
            }
        },
        {
            "value": {
                "bedtime": _ts(2026, 8, 19, 23, 30),
                "wake_up_time": _ts(2026, 8, 20, 7, 30),
                "sleep_deep_duration": 100,
                "sleep_light_duration": 280,
                "sleep_rem_duration": 100,
                "avg_hr": 65,
            }
        },
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 20))
    assert sleep is not None
    # Asleep = stages sum (matches Mi Fitness), not longer in-bed window.
    assert sleep["total_min"] == 480
    assert sleep["deep_min"] == 100
    assert sleep["avg_hr"] == 65


def test_pick_sleep_prefers_asleep_over_in_bed():
    """Mi Fitness shows asleep time; bed→wake includes awake-in-bed."""
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 25, 23, 0),
                "wake_up_time": _ts(2026, 8, 26, 5, 8),  # 368 min in bed
                "sleep_deep_duration": 70,
                "sleep_light_duration": 217,
                "sleep_rem_duration": 65,  # 352 asleep
                "avg_hr": 59,
            }
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 26))
    assert sleep["total_min"] == 352
    assert sleep["in_bed_min"] == 368
    assert sleep["deep_min"] == 70


def test_pick_sleep_prefers_explicit_sleep_duration():
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 25, 23, 0),
                "wake_up_time": _ts(2026, 8, 26, 7, 0),
                "sleep_duration": 350,
                "sleep_deep_duration": 70,
                "sleep_light_duration": 200,
                "sleep_rem_duration": 80,  # stages 350
            }
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 26))
    assert sleep["total_min"] == 350
    assert sleep["in_bed_min"] == 8 * 60


def test_pick_sleep_ignores_bogus_short_sleep_duration():
    """Some Mi payloads put a short unrelated value in sleep_duration."""
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 25, 23, 0),
                "wake_up_time": _ts(2026, 8, 26, 5, 8),
                "sleep_duration": 23,
                "sleep_deep_duration": 70,
                "sleep_light_duration": 217,
                "sleep_rem_duration": 65,
            }
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 26))
    assert sleep["total_min"] == 352
    assert sleep["in_bed_min"] == 368


def test_pick_sleep_ignores_stale_sleep_duration_when_duration_matches_stages():
    """sleep_duration may be in-bed; duration + stages are the asleep total."""
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 28, 1, 15),
                "wake_up_time": _ts(2026, 8, 28, 7, 26),
                "sleep_duration": 420,
                "duration": 356,
                "sleep_deep_duration": 50,
                "sleep_light_duration": 213,
                "sleep_rem_duration": 93,
            }
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 28))
    assert sleep["total_min"] == 356
    assert sleep["in_bed_min"] == 371


def test_pick_sleep_never_prefers_in_bed_over_stages():
    """Even if sleep_duration equals in-bed, keep stages as asleep time."""
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 25, 23, 0),
                "wake_up_time": _ts(2026, 8, 26, 7, 0),  # 480 in bed
                "sleep_duration": 480,
                "sleep_deep_duration": 70,
                "sleep_light_duration": 217,
                "sleep_rem_duration": 65,  # 352 asleep
            }
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 26))
    assert sleep["total_min"] == 352
    assert sleep["in_bed_min"] == 480


def test_pick_sleep_converts_stage_seconds():
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 19, 23, 0),
                "wake_up_time": _ts(2026, 8, 20, 7, 0),
                "sleep_deep_duration": 90 * 60,
                "sleep_light_duration": 250 * 60,
                "sleep_rem_duration": 80 * 60,
            }
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 8, 20))
    assert sleep["total_min"] == 90 + 250 + 80
    assert sleep["deep_min"] == 90
    assert sleep["light_min"] == 250
    assert sleep["rem_min"] == 80
    assert sleep["in_bed_min"] == 8 * 60


def test_pick_sleep_uses_item_time_as_wake_when_value_has_no_wake():
    items = [
        {
            "time": _ts(2026, 9, 2, 7, 15),
            "zone_offset": 10800,
            "value": {
                "bedtime": _ts(2026, 9, 1, 23, 30),
                "sleep_deep_duration": 70,
                "sleep_light_duration": 200,
                "sleep_rem_duration": 75,
            },
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 9, 2))
    assert sleep is not None
    assert sleep["total_min"] == 345


def test_pick_sleep_uses_item_time_when_wake_missing():
    """Some Mi payloads only put wake day on the data_list row, not in value JSON."""
    items = [
        {
            "time": _ts(2026, 9, 2, 7, 15),
            "zone_offset": 10800,
            "value": {
                "sleep_deep_duration": 70,
                "sleep_light_duration": 200,
                "sleep_rem_duration": 75,
            },
        }
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 9, 2))
    assert sleep is not None
    assert sleep["total_min"] == 345
    assert sleep["deep_min"] == 70


def test_pick_sleep_ignores_yesterday_nap_when_no_wake_today():
    """Do not show a prior-day nap when the main night for today is not synced yet."""
    items = [
        {
            "value": {
                "bedtime": _ts(2026, 8, 26, 23, 57),
                "wake_up_time": _ts(2026, 8, 27, 7, 44),
                "sleep_deep_duration": 87,
                "sleep_light_duration": 222,
                "sleep_rem_duration": 85,
            }
        },
        {
            "value": {
                "bedtime": _ts(2026, 8, 27, 18, 55),
                "wake_up_time": _ts(2026, 8, 27, 19, 52),
                "sleep_deep_duration": 0,
                "sleep_light_duration": 0,
                "sleep_rem_duration": 0,
            }
        },
    ]
    assert _pick_sleep_for_day(items, date(2026, 8, 28)) is None
    sleep = _pick_sleep_for_day(items, date(2026, 8, 27))
    assert sleep is not None
    assert sleep["total_min"] == 394


def test_pick_sleep_does_not_reuse_yesterday_staged_night():
    """If today's night is not synced yet, do not show yesterday's wake-day sleep."""
    items = [
        {
            "time": _ts(2026, 9, 10, 7, 21),
            "value": {
                "bedtime": _ts(2026, 9, 10, 1, 12),
                "wake_up_time": _ts(2026, 9, 10, 7, 21),
                "device_bedtime": _ts(2026, 9, 10, 1, 12),
                "device_wake_up_time": _ts(2026, 9, 10, 7, 21),
                "duration": 340,
                "sleep_deep_duration": 80,
                "sleep_light_duration": 219,
                "sleep_rem_duration": 41,
                "avg_hr": 65,
            },
        }
    ]
    assert _pick_sleep_for_day(items, date(2026, 9, 10))["total_min"] == 340
    assert _pick_sleep_for_day(items, date(2026, 9, 11)) is None


def test_pick_sleep_sums_same_night_fragments_not_evening_nap():
    """Mi Fitness may split one night into bout rows sharing device bedtime/wake."""
    device_bed = _ts(2026, 9, 9, 1, 28)
    device_wake = _ts(2026, 9, 9, 8, 0)
    items = [
        {
            "time": _ts(2026, 9, 8, 7, 51),
            "value": {
                "bedtime": _ts(2026, 9, 8, 0, 55),
                "wake_up_time": _ts(2026, 9, 8, 7, 51),
                "device_bedtime": _ts(2026, 9, 8, 0, 55),
                "device_wake_up_time": _ts(2026, 9, 8, 7, 51),
                "duration": 362,
                "sleep_deep_duration": 83,
                "sleep_light_duration": 261,
                "sleep_rem_duration": 18,
            },
        },
        {
            "time": _ts(2026, 9, 9, 2, 24),
            "value": {
                "bedtime": _ts(2026, 9, 9, 1, 28),
                "wake_up_time": _ts(2026, 9, 9, 2, 24),
                "device_bedtime": device_bed,
                "device_wake_up_time": device_wake,
                "duration": 56,
                "sleep_duration": 180,
                "sleep_deep_duration": 0,
                "sleep_light_duration": 0,
            },
        },
        {
            "time": _ts(2026, 9, 9, 3, 52),
            "value": {
                "bedtime": _ts(2026, 9, 9, 2, 36),
                "wake_up_time": _ts(2026, 9, 9, 3, 52),
                "device_bedtime": device_bed,
                "device_wake_up_time": device_wake,
                "duration": 76,
                "sleep_duration": 180,
            },
        },
        {
            "time": _ts(2026, 9, 9, 5, 35),
            "value": {
                "bedtime": _ts(2026, 9, 9, 4, 4),
                "wake_up_time": _ts(2026, 9, 9, 5, 35),
                "device_bedtime": device_bed,
                "device_wake_up_time": device_wake,
                "duration": 91,
                "sleep_duration": 180,
            },
        },
        {
            "time": _ts(2026, 9, 9, 8, 0),
            "value": {
                "bedtime": _ts(2026, 9, 9, 5, 48),
                "wake_up_time": _ts(2026, 9, 9, 8, 0),
                "device_bedtime": device_bed,
                "device_wake_up_time": device_wake,
                "duration": 132,
                "sleep_duration": 180,
            },
        },
        {
            "time": _ts(2026, 9, 9, 20, 2),
            "value": {
                "bedtime": _ts(2026, 9, 9, 19, 15),
                "wake_up_time": _ts(2026, 9, 9, 20, 2),
                "device_bedtime": _ts(2026, 9, 9, 19, 15),
                "device_wake_up_time": _ts(2026, 9, 9, 20, 2),
                "duration": 47,
            },
        },
    ]
    sleep = _pick_sleep_for_day(items, date(2026, 9, 9))
    assert sleep is not None
    assert sleep["total_min"] == 56 + 76 + 91 + 132
    assert sleep["in_bed_min"] == 392
    # Prior staged night must stay on its own day.
    prior = _pick_sleep_for_day(items, date(2026, 9, 8))
    assert prior is not None
    assert prior["total_min"] == 362


def test_filter_scale_never_falls_back_to_other_days():
    records = [
        {"measured_at": "2026-08-18T08:00:00", "weight": 110},
        {"measured_at": "2026-08-19T08:00:00", "weight": 109},
    ]
    assert _filter_scale_for_date(records, date(2026, 8, 20)) == []
    matched = _filter_scale_for_date(records, date(2026, 8, 19))
    assert len(matched) == 1
    assert matched[0]["weight"] == 109


def test_filter_scale_sorts_newest_first_and_uses_user_tz():
    from data_collector import _normalize_snapshot, _record_date_iso

    # 01:30 MSK on Aug 20 == 22:30 UTC Aug 19 — must count as Aug 20 local.
    morning_msk = int(datetime(2026, 8, 19, 22, 30, tzinfo=timezone.utc).timestamp() * 1000)
    evening_msk = int(datetime(2026, 8, 20, 18, 0, tzinfo=timezone.utc).timestamp() * 1000)
    assert _record_date_iso({"createTime": morning_msk}) == "2026-08-20"
    records = [
        {"createTime": morning_msk, "weight": 80.5, "bmi": 30},
        {"createTime": evening_msk, "weight": 81.2, "bmi": 30.2},
    ]
    matched = _filter_scale_for_date(records, date(2026, 8, 20))
    assert [r["weight"] for r in matched] == [81.2, 80.5]
    snap = _normalize_snapshot({"weight_home": matched}, date(2026, 8, 20))
    assert snap["weight"]["kg"] == 81.2
    assert snap["weight"]["source"] == "xiaomi_home"
    assert str(snap["weight"]["measured_at"]).startswith("2026-08-20T")


def test_normalize_empty_fatsecret_and_workouts_clear_stale():
    from data_collector import _normalize_snapshot

    snap = _normalize_snapshot(
        {"fatsecret_food": [], "workouts": [], "weight_home": []},
        date(2026, 8, 20),
    )
    assert snap["nutrition"]["source"] == "fatsecret"
    assert snap["nutrition"]["meals"] == []
    assert snap["workouts"] == []
    assert snap["weight"] is None
