"""JSON-file store for blood-pressure readings (optional VPS backup)."""

from __future__ import annotations

import json
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from blood_pressure_csv import validate_reading


def _parse_iso(value: str) -> datetime:
    text = value.strip().replace("Z", "")
    if "T" in text:
        for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
            try:
                return datetime.strptime(text[:19] if len(text) >= 19 else text, fmt)
            except ValueError:
                continue
    return datetime.strptime(text[:10], "%Y-%m-%d")


class BloodPressureStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or Path(__file__).resolve().parent / "data" / "blood_pressure.json"
        self._lock = threading.Lock()
        self._items: list[dict[str, Any]] = []
        self._next_id = 1
        self._load()

    def reset(self) -> None:
        with self._lock:
            self._items = []
            self._next_id = 1
            self._persist()

    def _load(self) -> None:
        if not self.path.is_file():
            return
        raw = json.loads(self.path.read_text(encoding="utf-8"))
        self._items = list(raw.get("items") or [])
        self._next_id = int(raw.get("next_id") or 1)
        if self._items:
            self._next_id = max(self._next_id, max(int(i.get("id") or 0) for i in self._items) + 1)

    def _persist(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"next_id": self._next_id, "items": self._items}
        self.path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def _dedupe_key(self, item: dict[str, Any]) -> tuple[str, int, int]:
        return (str(item["measured_at"]), int(item["systolic"]), int(item["diastolic"]))

    def add(self, reading: dict[str, Any]) -> tuple[dict[str, Any], bool]:
        """Insert one reading. Returns (stored, created)."""
        systolic = int(reading["systolic"])
        diastolic = int(reading["diastolic"])
        pulse = reading.get("pulse")
        pulse_i = int(pulse) if pulse is not None else None
        problem = validate_reading(systolic, diastolic, pulse_i)
        if problem:
            raise ValueError(problem)

        measured_at = reading.get("measured_at") or datetime.now().replace(microsecond=0).isoformat()
        item = {
            "id": 0,
            "measured_at": measured_at,
            "systolic": systolic,
            "diastolic": diastolic,
            "pulse": pulse_i,
            "source": reading.get("source") or "manual",
            "note": reading.get("note") or None,
        }
        with self._lock:
            existing = {self._dedupe_key(x): x for x in self._items}
            key = self._dedupe_key(item)
            if key in existing:
                return existing[key], False
            item["id"] = self._next_id
            self._next_id += 1
            self._items.append(item)
            self._persist()
            return item, True

    def add_many(self, readings: list[dict[str, Any]]) -> dict[str, Any]:
        created = 0
        skipped = 0
        stored: list[dict[str, Any]] = []
        for row in readings:
            item, is_new = self.add(row)
            stored.append(item)
            if is_new:
                created += 1
            else:
                skipped += 1
        return {"created": created, "skipped_duplicates": skipped, "items": stored}

    def list(
        self,
        *,
        from_date: str | None = None,
        to_date: str | None = None,
    ) -> list[dict[str, Any]]:
        with self._lock:
            items = list(self._items)
        if from_date:
            start = _parse_iso(from_date)
            items = [i for i in items if _parse_iso(i["measured_at"]) >= start]
        if to_date:
            end = _parse_iso(to_date)
            if len(to_date) <= 10:
                end = end.replace(hour=23, minute=59, second=59)
            items = [i for i in items if _parse_iso(i["measured_at"]) <= end]
        items.sort(key=lambda i: i["measured_at"], reverse=True)
        return items

    def summary(self, days: int = 7) -> dict[str, Any]:
        days = 30 if days >= 30 else 7
        cutoff = datetime.now() - timedelta(days=days)
        items = [
            i
            for i in self.list()
            if _parse_iso(i["measured_at"]) >= cutoff
        ]
        if not items:
            return {
                "days": days,
                "count": 0,
                "latest": None,
                "avg": None,
                "high_count": 0,
            }

        sys_vals = [int(i["systolic"]) for i in items]
        dia_vals = [int(i["diastolic"]) for i in items]
        pulse_vals = [int(i["pulse"]) for i in items if i.get("pulse") is not None]
        latest = max(items, key=lambda i: i["measured_at"])
        high_count = sum(1 for i in items if int(i["systolic"]) >= 140 or int(i["diastolic"]) >= 90)
        avg = {
            "systolic": round(sum(sys_vals) / len(sys_vals), 1),
            "diastolic": round(sum(dia_vals) / len(dia_vals), 1),
        }
        if pulse_vals:
            avg["pulse"] = round(sum(pulse_vals) / len(pulse_vals), 1)
        return {
            "days": days,
            "count": len(items),
            "latest": latest,
            "avg": avg,
            "min_systolic": min(sys_vals),
            "max_systolic": max(sys_vals),
            "min_diastolic": min(dia_vals),
            "max_diastolic": max(dia_vals),
            "high_count": high_count,
        }


store = BloodPressureStore()
