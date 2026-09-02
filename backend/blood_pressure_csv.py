"""Parse Citizen / «Давление» CSV exports (Дата,Время,Сис,Диа,Пульс)."""

from __future__ import annotations

import csv
import io
import re
from datetime import datetime
from typing import Any


DATE_FORMATS = ("%Y-%m-%d", "%d.%m.%Y", "%d/%m/%Y", "%Y/%m/%d", "%d-%m-%Y")
TIME_FORMATS = ("%H:%M:%S", "%H:%M")

_HEADER_ALIASES = {
    "date": {"дата", "date", "день", "day"},
    "time": {"время", "time", "час"},
    "systolic": {"сис", "систол", "систолическое", "systolic", "sys", "сд"},
    "diastolic": {"диа", "диастол", "диастолическое", "diastolic", "dia", "дд"},
    "pulse": {"пульс", "pulse", "hr", "чсс", "heart rate"},
    "note": {"заметки", "заметка", "примечание", "note", "notes", "комментарий"},
}


class CsvImportError(ValueError):
    """Row-level or file-level CSV problem."""


def _norm_header(value: str) -> str:
    return re.sub(r"\s+", " ", (value or "").replace("\ufeff", "").strip().lower())


def _map_headers(fieldnames: list[str] | None) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for raw in fieldnames or []:
        key = _norm_header(raw)
        for canonical, aliases in _HEADER_ALIASES.items():
            if key in aliases or key.startswith(tuple(aliases)):
                mapping[canonical] = raw
                break
    return mapping


class _SemiColonDialect(csv.Dialect):
    delimiter = ";"
    quotechar = '"'
    doublequote = True
    skipinitialspace = True
    lineterminator = "\n"
    quoting = csv.QUOTE_MINIMAL


def _detect_dialect(sample: str) -> type[csv.Dialect] | csv.Dialect:
    first = sample.splitlines()[0] if sample else ""
    if first.count(";") > first.count(","):
        return _SemiColonDialect
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        return csv.excel


def _parse_int(value: Any) -> int | None:
    if value is None:
        return None
    text = str(value).strip().replace(",", ".")
    if not text or text.lower() in {"nan", "null", "-", "—"}:
        return None
    match = re.search(r"\d+", text)
    if not match:
        return None
    return int(match.group(0))


def _parse_datetime(date_s: str, time_s: str) -> datetime:
    date_s = (date_s or "").strip()
    time_s = (time_s or "").strip() or "00:00"
    last_error: Exception | None = None
    for df in DATE_FORMATS:
        for tf in TIME_FORMATS:
            try:
                return datetime.strptime(f"{date_s} {time_s}", f"{df} {tf}")
            except ValueError as exc:
                last_error = exc
                continue
    combined = f"{date_s} {time_s}".strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(combined, fmt)
        except ValueError as exc:
            last_error = exc
    raise CsvImportError(f"Не удалось разобрать дату/время: {date_s!r} {time_s!r}") from last_error


def validate_reading(
    systolic: int,
    diastolic: int,
    pulse: int | None,
) -> str | None:
    if not (70 <= systolic <= 250):
        return f"систол {systolic} вне диапазона 70–250"
    if not (40 <= diastolic <= 150):
        return f"диастол {diastolic} вне диапазона 40–150"
    if systolic <= diastolic:
        return f"систол {systolic} должен быть больше диастол {diastolic}"
    if pulse is not None and not (30 <= pulse <= 220):
        return f"пульс {pulse} вне диапазона 30–220"
    return None


def parse_citizen_csv(content: str | bytes, *, source: str = "csv") -> dict[str, Any]:
    """Parse Citizen BP CSV. Returns imported rows plus skipped/errors."""
    if isinstance(content, bytes):
        text = content.decode("utf-8-sig")
    else:
        text = content.lstrip("\ufeff")

    text = text.strip()
    if not text:
        raise CsvImportError("Пустой CSV")

    dialect = _detect_dialect(text[:4096])
    reader = csv.DictReader(io.StringIO(text), dialect=dialect)
    mapping = _map_headers(reader.fieldnames)
    missing = [name for name in ("date", "systolic", "diastolic") if name not in mapping]
    if missing:
        raise CsvImportError(
            "Не найдены колонки: "
            + ", ".join(missing)
            + ". Ожидается формат Citizen: Дата,Время,Сис,Диа,Пульс"
        )

    readings: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    seen: set[tuple[str, int, int]] = set()
    skipped_dupes = 0

    for index, row in enumerate(reader, start=2):
        if not any((v or "").strip() for v in row.values()):
            continue
        date_s = (row.get(mapping["date"]) or "").strip()
        time_s = (row.get(mapping["time"]) or "").strip() if "time" in mapping else "00:00"
        try:
            measured_at = _parse_datetime(date_s, time_s)
            systolic = _parse_int(row.get(mapping["systolic"]))
            diastolic = _parse_int(row.get(mapping["diastolic"]))
            pulse = _parse_int(row.get(mapping["pulse"])) if "pulse" in mapping else None
            note = (row.get(mapping["note"]) or "").strip() if "note" in mapping else ""
            if systolic is None or diastolic is None:
                raise CsvImportError("нет систол/диастол")
            problem = validate_reading(systolic, diastolic, pulse)
            if problem:
                raise CsvImportError(problem)
        except CsvImportError as exc:
            errors.append({"row": index, "error": str(exc)})
            continue

        iso = measured_at.replace(microsecond=0).isoformat()
        key = (iso, systolic, diastolic)
        if key in seen:
            skipped_dupes += 1
            continue
        seen.add(key)
        readings.append(
            {
                "measured_at": iso,
                "systolic": systolic,
                "diastolic": diastolic,
                "pulse": pulse,
                "source": source,
                "note": note or None,
            }
        )

    return {
        "readings": readings,
        "imported": len(readings),
        "skipped_duplicates": skipped_dupes,
        "errors": errors,
    }
