"""JSON-file store for daily health snapshots."""

from __future__ import annotations

import json
import shutil
import threading
from datetime import date, datetime, timedelta, timezone
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

    def _backup(self) -> None:
        if not self.path.is_file():
            return
        backup_dir = self.path.parent / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        target = backup_dir / f"health_days_{stamp}.json"
        try:
            shutil.copy2(self.path, target)
        except OSError:
            return
        backups = sorted(backup_dir.glob("health_days_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        for old in backups[14:]:
            try:
                old.unlink()
            except OSError:
                pass

    def _persist(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._backup()
        self.path.write_text(
            json.dumps({"days": self._days}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def upsert(self, snapshot: dict[str, Any], *, merge: bool = False) -> dict[str, Any]:
        date_key = str(snapshot.get("date") or "").strip()
        if not date_key:
            raise ValueError("Нужно поле date (YYYY-MM-DD)")
        payload = dict(snapshot)
        payload["date"] = date_key
        payload["generated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
        with self._lock:
            if merge and date_key in self._days:
                payload = merge_snapshots(self._days[date_key], payload)
                payload["generated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
            self._days[date_key] = payload
            self._persist()
            return payload

    def get(self, date_key: str) -> dict[str, Any] | None:
        with self._lock:
            item = self._days.get(date_key)
            return dict(item) if item else None

    def list_range(self, end: date | None = None, days: int = 7) -> list[dict[str, Any]]:
        """Return snapshots for end-days+1 .. end inclusive (newest last)."""
        if end is None:
            try:
                from data_collector import user_local_date

                end_day = user_local_date()
            except Exception:
                end_day = date.today()
        else:
            end_day = end
        out: list[dict[str, Any]] = []
        with self._lock:
            for offset in range(days - 1, -1, -1):
                key = (end_day - timedelta(days=offset)).isoformat()
                item = self._days.get(key)
                if item:
                    out.append(dict(item))
                else:
                    out.append({"date": key, "generated_at": None})
        return out


day_store = HealthDayStore()
