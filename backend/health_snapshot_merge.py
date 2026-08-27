"""Merge daily health snapshots without losing auto-collected source data."""

from __future__ import annotations

from typing import Any


def _nutrition_item_count(nutrition: dict[str, Any] | None) -> int:
    if not nutrition:
        return 0
    total = 0
    for meal in nutrition.get("meals") or []:
        if isinstance(meal, dict):
            total += len(meal.get("items") or [])
    return total


def _merge_nutrition(
    existing: dict[str, Any] | None,
    incoming: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not incoming:
        return existing
    if not existing:
        return incoming

    incoming_count = _nutrition_item_count(incoming)
    existing_count = _nutrition_item_count(existing)
    incoming_source = incoming.get("source")
    existing_source = existing.get("source")

    if incoming_source == "fatsecret":
        return incoming
    if existing_source == "fatsecret" and incoming_count < existing_count:
        return existing
    if incoming_count >= existing_count:
        return incoming
    return existing


def _merge_bp_reading_lists(*groups: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    seen: set[tuple[str, int, int]] = set()
    for group in groups:
        for item in group or []:
            if not item.get("systolic") or not item.get("diastolic"):
                continue
            key = (str(item.get("measured_at") or ""), int(item["systolic"]), int(item["diastolic"]))
            if key in seen:
                continue
            seen.add(key)
            merged.append(dict(item))
    # Drop date-only MedM stubs when a timed reading exists for the same day+values.
    timed_keys = {
        (str(r.get("measured_at") or "")[:10], int(r["systolic"]), int(r["diastolic"]))
        for r in merged
        if "T" in str(r.get("measured_at") or "")
    }
    if timed_keys:
        merged = [
            r
            for r in merged
            if "T" in str(r.get("measured_at") or "")
            or (str(r.get("measured_at") or "")[:10], int(r["systolic"]), int(r["diastolic"])) not in timed_keys
        ]
    merged.sort(key=lambda r: str(r.get("measured_at") or ""), reverse=True)
    return merged


def _bp_latest(readings: list[dict[str, Any]], fallback: dict[str, Any] | None = None) -> dict[str, Any] | None:
    if readings:
        return readings[0]
    return fallback


def _merge_blood_pressure(
    existing: dict[str, Any] | None,
    incoming: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not incoming:
        return existing
    if not existing:
        return incoming

    existing_list = list(existing.get("readings_today") or [])
    incoming_list = list(incoming.get("readings_today") or [])

    # Timed MedM scrape is authoritative for that calendar day — drop prior MedM
    # rows for the same dates (including date-only stubs from the old parser).
    medm_dates = {
        str(r.get("measured_at") or "")[:10]
        for r in incoming_list
        if str(r.get("source") or "") == "medm_bp" and "T" in str(r.get("measured_at") or "")
    }
    if medm_dates:
        existing_list = [
            r
            for r in existing_list
            if not (
                str(r.get("source") or "") == "medm_bp"
                and str(r.get("measured_at") or "")[:10] in medm_dates
            )
        ]

    readings = _merge_bp_reading_lists(existing_list, incoming_list)
    latest = _bp_latest(readings, incoming.get("latest") or existing.get("latest"))
    merged = {**existing, **incoming, "readings_today": readings}
    if latest:
        merged["latest"] = latest
    return merged


def _merge_steps(existing: dict[str, Any] | None, incoming: dict[str, Any] | None) -> dict[str, Any] | None:
    if not incoming:
        return existing
    if not existing:
        return incoming
    incoming_count = (incoming.get("count") if isinstance(incoming, dict) else None) or 0
    existing_count = (existing.get("count") if isinstance(existing, dict) else None) or 0
    if incoming_count >= existing_count:
        return incoming
    return existing


def _merge_activity(
    existing: dict[str, Any] | None,
    incoming: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not incoming:
        return existing
    if not existing:
        return incoming
    if incoming.get("source") == "mi_fitness":
        return incoming
    if existing.get("source") == "mi_fitness" and incoming.get("source") == "manual":
        return existing
    incoming_steps = incoming.get("steps")
    existing_steps = existing.get("steps")
    if incoming_steps is None:
        return existing
    if existing_steps is None:
        return incoming
    if int(incoming_steps) >= int(existing_steps):
        return incoming
    return existing


def merge_snapshots(existing: dict[str, Any] | None, incoming: dict[str, Any]) -> dict[str, Any]:
    """Merge incoming snapshot into existing without dropping richer auto-collected fields."""
    if not existing:
        return dict(incoming)

    out = dict(existing)
    for key, value in incoming.items():
        if key == "date":
            out["date"] = value
            continue
        if value is None:
            continue
        if key == "nutrition":
            merged = _merge_nutrition(existing.get("nutrition"), value if isinstance(value, dict) else None)
            if merged is not None:
                out["nutrition"] = merged
        elif key == "blood_pressure":
            merged = _merge_blood_pressure(existing.get("blood_pressure"), value if isinstance(value, dict) else None)
            if merged is not None:
                out["blood_pressure"] = merged
        elif key == "steps":
            merged = _merge_steps(existing.get("steps"), value if isinstance(value, dict) else None)
            if merged is not None:
                out["steps"] = merged
        elif key == "activity":
            merged = _merge_activity(existing.get("activity"), value if isinstance(value, dict) else None)
            if merged is not None:
                out["activity"] = merged
        elif key == "notes" and not str(value).strip():
            continue
        else:
            out[key] = value

    if incoming.get("generated_at"):
        out["generated_at"] = incoming["generated_at"]
    if incoming.get("source"):
        out["source"] = incoming["source"]
    return out
