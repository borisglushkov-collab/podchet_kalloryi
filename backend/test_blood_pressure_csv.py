"""Tests for Citizen blood-pressure CSV import."""

from blood_pressure_csv import CsvImportError, parse_citizen_csv
import pytest


SAMPLE = """Дата,Время,Сис,Диа,Пульс,Заметки
2026-08-19,07:32,133,90,72,утро
2026-08-18,07:15,136,91,75,
2026-08-17,21:40,128,84,,вечер
"""


def test_parse_citizen_headers_and_empty_pulse():
    result = parse_citizen_csv(SAMPLE)
    assert result["imported"] == 3
    assert result["skipped_duplicates"] == 0
    assert result["errors"] == []
    first = result["readings"][0]
    assert first["measured_at"] == "2026-08-19T07:32:00"
    assert first["systolic"] == 133
    assert first["diastolic"] == 90
    assert first["pulse"] == 72
    assert first["note"] == "утро"
    assert result["readings"][2]["pulse"] is None


def test_parse_semicolon_and_dot_dates():
    csv_text = "Дата;Время;Сис;Диа;Пульс\n19.08.2026;07:32;133;90;72\n"
    result = parse_citizen_csv(csv_text)
    assert result["imported"] == 1
    assert result["readings"][0]["measured_at"] == "2026-08-19T07:32:00"


def test_parse_skips_duplicates_in_file():
    csv_text = SAMPLE + "2026-08-19,07:32,133,90,72,\n"
    result = parse_citizen_csv(csv_text)
    assert result["imported"] == 3
    assert result["skipped_duplicates"] == 1


def test_parse_rejects_bad_values():
    result = parse_citizen_csv("Дата,Время,Сис,Диа,Пульс\n2026-08-19,07:32,40,90,72\n")
    assert result["imported"] == 0
    assert result["errors"][0]["row"] == 2


def test_parse_empty_raises():
    with pytest.raises(CsvImportError):
        parse_citizen_csv("   ")


def test_parse_missing_columns():
    with pytest.raises(CsvImportError):
        parse_citizen_csv("foo,bar\n1,2\n")
