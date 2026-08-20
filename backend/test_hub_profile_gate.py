"""Tests for hub profile store, PIN session cookie, and gate endpoints."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from coach_health_report import format_week_report
from hub_auth import COOKIE_NAME, issue_token, token_valid
from hub_profile_store import HubProfileStore


def test_hub_profile_store_roundtrip(tmp_path: Path):
    store = HubProfileStore(tmp_path / "hub_profile.json")
    saved = store.save(
        {
            "height_cm": 165,
            "medications": "Edarbi 80, magnesium",
            "coaching_calorie_target": {"kcal_min": 1800, "kcal_max": 2000, "protein_g": 120},
            "updated_at": "2026-08-20T10:00:00Z",
        }
    )
    assert saved["height_cm"] == 165
    assert saved["medications"] == ["Edarbi 80", "magnesium"]
    assert saved["updated_at"] == "2026-08-20T10:00:00Z"

    again = HubProfileStore(tmp_path / "hub_profile.json")
    loaded = again.get()
    assert loaded["height_cm"] == 165


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


def test_token_roundtrip():
    tok = issue_token(1_700_000_000)
    assert token_valid(tok, now=1_700_000_100)
    assert not token_valid(tok, now=1_700_000_000 + 60 * 60 * 24 * 20)
    assert not token_valid("bad")


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("HUB_PIN", "")
    monkeypatch.delenv("HUB_SESSION_SECRET", raising=False)
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
            "updated_at": "2026-08-20T12:00:00Z",
        },
    )
    assert r2.status_code == 200
    body = r2.json()["profile"]
    assert body["height_cm"] == 170
    assert body["updated_at"] == "2026-08-20T12:00:00Z"


def test_gate_without_pin(client: TestClient):
    r = client.get("/api/health/gate")
    assert r.status_code == 200
    assert r.json()["pin_required"] is False


def test_gate_with_pin_blocks_until_cookie(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    monkeypatch.setenv("HUB_PIN", "4242")
    monkeypatch.setenv("HUB_SESSION_SECRET", "test-secret")
    import hub_profile_store as hps
    import main as main_mod

    store = HubProfileStore(tmp_path / "hub_profile.json")
    monkeypatch.setattr(hps, "profile_store", store)
    monkeypatch.setattr(main_mod, "profile_store", store)
    client = TestClient(main_mod.app)

    assert client.get("/api/health/gate").json()["pin_required"] is True
    assert client.get("/api/health/profile").status_code == 401
    bad = client.post("/api/health/unlock", json={"pin": "0000"})
    assert bad.status_code == 401
    ok = client.post("/api/health/unlock", json={"pin": "4242"})
    assert ok.status_code == 200
    assert COOKIE_NAME in ok.cookies
    # TestClient keeps cookies for subsequent requests
    assert client.get("/api/health/profile").status_code == 200


def test_hub_index_injects_version(client: TestClient):
    r = client.get("/hub/")
    assert r.status_code == 200
    assert "js/main.js?v=" in r.text
    assert "type=\"module\"" in r.text
    assert "{{HUB_VERSION}}" not in r.text
