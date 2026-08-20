"""Tests for hub profile store and PIN gate endpoints."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from hub_profile_store import HubProfileStore
from coach_health_report import format_week_report


def test_hub_profile_store_roundtrip(tmp_path: Path):
    store = HubProfileStore(tmp_path / "hub_profile.json")
    saved = store.save(
        {
            "height_cm": 165,
            "medications": "Edarbi 80, magnesium",
            "coaching_calorie_target": {"kcal_min": 1800, "kcal_max": 2000, "protein_g": 120},
        }
    )
    assert saved["height_cm"] == 165
    assert saved["medications"] == ["Edarbi 80", "magnesium"]
    assert saved["coaching_calorie_target"]["kcal_min"] == 1800

    again = HubProfileStore(tmp_path / "hub_profile.json")
    loaded = again.get()
    assert loaded["height_cm"] == 165
    assert loaded["medications"] == ["Edarbi 80", "magnesium"]


def test_format_week_report_days_in_goal():
    text = format_week_report(
        [
            {"date": "2026-08-18", "nutrition": {"calories": 2000}, "activity": {"steps": 5000}},
            {"date": "2026-08-19", "nutrition": {"calories": 2200}, "activity": {"steps": 6000}},
            {"date": "2026-08-20", "nutrition": {"calories": 1950}, "activity": {"steps": 7000}},
        ],
        {"coaching_calorie_target": {"kcal_min": 1900, "kcal_max": 2100}},
    )
    assert "Дней в цели: 2 из 3" in text


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("HUB_PIN", "")
    import hub_profile_store as hps
    import main as main_mod

    store = HubProfileStore(tmp_path / "hub_profile.json")
    monkeypatch.setattr(hps, "profile_store", store)
    monkeypatch.setattr(main_mod, "profile_store", store)
    return TestClient(main_mod.app)


def test_profile_api_get_put(client: TestClient):
    r = client.get("/api/health/profile")
    assert r.status_code == 200
    assert "profile" in r.json()

    r2 = client.put(
        "/api/health/profile",
        json={
            "height_cm": 170,
            "medications": ["A", "B"],
            "coaching_calorie_target": {"kcal_min": 1900, "kcal_max": 2100, "protein_g": 130},
        },
    )
    assert r2.status_code == 200
    body = r2.json()["profile"]
    assert body["height_cm"] == 170
    assert body["medications"] == ["A", "B"]

    r3 = client.get("/api/health/profile")
    assert r3.json()["profile"]["height_cm"] == 170


def test_gate_without_pin(client: TestClient):
    r = client.get("/api/health/gate")
    assert r.status_code == 200
    assert r.json()["pin_required"] is False


def test_gate_with_pin(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    monkeypatch.setenv("HUB_PIN", "4242")
    import hub_profile_store as hps
    import main as main_mod

    store = HubProfileStore(tmp_path / "hub_profile.json")
    monkeypatch.setattr(hps, "profile_store", store)
    monkeypatch.setattr(main_mod, "profile_store", store)
    client = TestClient(main_mod.app)

    assert client.get("/api/health/gate").json()["pin_required"] is True
    bad = client.post("/api/health/unlock", json={"pin": "0000"})
    assert bad.status_code == 401
    ok = client.post("/api/health/unlock", json={"pin": "4242"})
    assert ok.status_code == 200
    assert ok.json()["ok"] is True
