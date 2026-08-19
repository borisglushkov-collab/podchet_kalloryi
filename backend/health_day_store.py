"""JSON-file store for daily health snapshots."""

from __future__ import annotations

import json
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from health_snapshot_merge import merge_snapshots


class HealthDayStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or Path(__file__).resolve().parent / "data" / "health_days.json"
        self._lock = threading.Lock()
        self._days: dict[str, dict[str, Any]] = {}
        self._load()

    def reset(self) -> None:
        with self._lock:
            self._days = {}
            self._persist()

    def _load(self) -> None:
        if not self.path.is_file():
            return
        raw = json.loads(self.path.read_text(encoding="utf-8"))
        self._days = dict(raw.get("days") or {})

    def _persist(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(
            json.dumps({"days": self._days}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def upsert(self, snapshot: dict[str, Any], *, merge: bool = False) -> dict[str, Any]:
        date = str(snapshot.get("date") or "").strip()
        if not date:
            raise ValueError("Нужно поле date (YYYY-MM-DD)")
        payload = dict(snapshot)
        payload["date"] = date
        payload["generated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
        with self._lock:
            if merge and date in self._days:
                payload = merge_snapshots(self._days[date], payload)
                payload["generated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
            self._days[date] = payload
            self._persist()
            return payload

    def get(self, date: str) -> dict[str, Any] | None:
        with self._lock:
            item = self._days.get(date)
            return dict(item) if item else None


day_store = HealthDayStore()
