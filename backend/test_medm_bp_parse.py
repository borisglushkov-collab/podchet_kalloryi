"""Unit tests for MedM timeline / bloodpressures HTML parsing."""

from datetime import date

from medm_bp import _parse_timeline_bp, _parse_time_token, _parse_date_header


SAMPLE_TIMELINE = """
<table>
<tr><td class='date'>Today</td></tr>
<tr>
  <td class='time'> 02:13 PM </td>
  <td>Blood Pressure</td>
  <td>147 / 91 <span class="units">mmHg</span> (65 <span class="units">bpm</span>)</td>
</tr>
<tr>
  <td class='time'> 09:05 AM </td>
  <td>Blood Pressure</td>
  <td>133 / 88 <span class="units">mmHg</span> (72 <span class="units">bpm</span>)</td>
</tr>
<tr><td class='date'>August 24, 2026</td></tr>
<tr>
  <td class='time'> 08:40 PM </td>
  <td>Blood Pressure</td>
  <td>128 / 84 mmHg (70 bpm)</td>
</tr>
</table>
"""

SAMPLE_HISTORY = """
<table>
<tr class='measurement'>
<td class='measurements_table__column measurements_table__date' rowspan='2'>Today</td>
<td class='measurements_table__time measurements_table__column measurements_table__date'>
02:13 PM
</td>
<td class='measurements_table__column'><span class=''>147</span></td>
<td class='measurements_table__column'><span class=''>91</span></td>
<td class='measurements_table__column'><span class=''>65</span></td>
</tr>
<tr class='measurement'>
<td class='measurements_table__time measurements_table__column measurements_table__date'>
08:05 AM
</td>
<td class='measurements_table__column'><span class=''>140</span></td>
<td class='measurements_table__column'><span class=''>93</span></td>
<td class='measurements_table__column'><span class=''>56</span></td>
</tr>
</table>
"""


def test_parse_time_ampm():
    assert _parse_time_token("02:13 PM") == "14:13:00"
    assert _parse_time_token("09:05 AM") == "09:05:00"
    assert _parse_time_token("12:00 AM") == "00:00:00"
    assert _parse_time_token("12:00 PM") == "12:00:00"
    assert _parse_time_token("14:05") == "14:05:00"


def test_parse_date_headers():
    today = date(2026, 8, 27)
    assert _parse_date_header("Today", today=today) == "2026-08-27"
    assert _parse_date_header("Yesterday", today=today) == "2026-08-26"
    assert _parse_date_header("August 24, 2026", today=today) == "2026-08-24"


def test_parse_timeline_with_times():
    readings = _parse_timeline_bp(SAMPLE_TIMELINE, today=date(2026, 8, 27))
    assert len(readings) == 3
    assert readings[0]["measured_at"] == "2026-08-27T14:13:00"
    assert readings[0]["systolic"] == 147
    assert readings[0]["diastolic"] == 91
    assert readings[0]["pulse"] == 65
    assert readings[1]["measured_at"] == "2026-08-27T09:05:00"
    assert readings[2]["measured_at"] == "2026-08-24T20:40:00"
    assert readings[2]["systolic"] == 128


def test_parse_history_columns_with_times():
    readings = _parse_timeline_bp(SAMPLE_HISTORY, today=date(2026, 8, 27))
    assert len(readings) == 2
    assert readings[0] == {
        "systolic": 147,
        "diastolic": 91,
        "pulse": 65,
        "measured_at": "2026-08-27T14:13:00",
        "source": "medm_bp",
    }
    assert readings[1]["measured_at"] == "2026-08-27T08:05:00"
    assert readings[1]["systolic"] == 140
    assert readings[1]["pulse"] == 56
