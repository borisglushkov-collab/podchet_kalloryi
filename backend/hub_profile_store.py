"""Persistent hub profile (medications, targets, height) for the coach PWA."""

from __future__ import annotations

import json
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


_DEFAULT = {
    "height_cm": None,
    "weight_kg_latest": None,
    "medications": [],
    "coaching_calorie_target": {
        "kcal_min": 1900,
        "kcal_max": 2100,
        "protein_g": 130,
    },
    "updated_at": None,
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


class HubProfileStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or Path(__file__).resolve().parent / "data" / "hub_profile.json"
        self._lock = threading.Lock()
        self._profile: dict[str, Any] = dict(_DEFAULT)
        self._load()

    def _load(self) -> None:
        if not self.path.is_file():
            return
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                merged = dict(_DEFAULT)
                merged.update(raw)
                target = dict(_DEFAULT["coaching_calorie_target"])
                if isinstance(raw.get("coaching_calorie_target"), dict):
                    target.update(raw["coaching_calorie_target"])
                merged["coaching_calorie_target"] = target
                self._profile = merged
        except (json.JSONDecodeError, OSError, TypeError):
            pass

    def _persist(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self._profile, ensure_ascii=False, indent=2), encoding="utf-8")

    def get(self) -> dict[str, Any]:
        with self._lock:
            return json.loads(json.dumps(self._profile))

    def save(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            next_profile = dict(self._profile)
            if "height_cm" in payload:
                height = payload.get("height_cm")
                next_profile["height_cm"] = None if height in (None, "") else int(height)
            if "weight_kg_latest" in payload:
                w = payload.get("weight_kg_latest")
                next_profile["weight_kg_latest"] = None if w in (None, "") else float(w)
            if "medications" in payload:
                meds = payload.get("medications") or []
                if isinstance(meds, str):
                    meds = [s.strip() for s in meds.split(",") if s.strip()]
                next_profile["medications"] = [str(m).strip() for m in meds if str(m).strip()]
            if isinstance(payload.get("coaching_calorie_target"), dict):
                target = dict(next_profile.get("coaching_calorie_target") or {})
                incoming = payload["coaching_calorie_target"]
                for key in ("kcal_min", "kcal_max", "protein_g"):
                    if key in incoming and incoming[key] not in (None, ""):
                        target[key] = int(incoming[key])
                next_profile["coaching_calorie_target"] = target
            # Last-write-wins: client may send updated_at; otherwise stamp now.
            client_ts = payload.get("updated_at")
            if client_ts:
                next_profile["updated_at"] = str(client_ts)
            else:
                next_profile["updated_at"] = _now_iso()
            self._profile = next_profile
            self._persist()
            return json.loads(json.dumps(self._profile))


profile_store = HubProfileStore()
