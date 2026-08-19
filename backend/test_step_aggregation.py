from datetime import date

from data_collector import _aggregate_metric_values, _aggregate_steps_for_day


def test_aggregate_metric_values_incremental():
    assert _aggregate_metric_values([1500, 1300, 1234]) == 4034


def test_aggregate_metric_values_cumulative():
    assert _aggregate_metric_values([1500, 2800, 4034]) == 4034


def test_aggregate_steps_for_day_filters_by_local_date():
    target = date(2026, 8, 19)
    items = [
        {"time": 1787122800, "value": '{"steps":1500,"distance":800,"calories":90}'},
        {"time": 1787130000, "value": '{"steps":1300,"distance":700,"calories":80}'},
        {"time": 1787036400, "value": '{"steps":9999,"distance":1,"calories":1}'},
    ]
    result = _aggregate_steps_for_day(items, target)
    assert result is not None
    assert result["count"] == 2800
