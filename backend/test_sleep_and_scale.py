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


def test_filter_scale_never_falls_back_to_other_days():
    records = [
        {"measured_at": "2026-08-18T08:00:00", "weight": 110},
        {"measured_at": "2026-08-19T08:00:00", "weight": 109},
    ]
    assert _filter_scale_for_date(records, date(2026, 8, 20)) == []
    matched = _filter_scale_for_date(records, date(2026, 8, 19))
    assert len(matched) == 1
    assert matched[0]["weight"] == 109
