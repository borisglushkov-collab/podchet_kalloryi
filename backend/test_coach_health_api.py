from fastapi.testclient import TestClient

import blood_pressure_store
import health_day_store
from main import app

client = TestClient(app)


def setup_function() -> None:
    blood_pressure_store.store.reset()
    health_day_store.day_store.reset()


def test_hub_app_is_served():
    response = client.get("/hub/")
    assert response.status_code == 200
    assert "Сбор для коуча" in response.text


def test_sync_and_report():
    snapshot = {
        "date": "2026-08-19",
        "nutrition": {"calories": 385, "protein_g": 28, "meals": []},
        "sleep": {"duration_min": 419},
        "activity": {"steps": 871},
        "body_composition": {"weight_kg": 109},
        "profile": {"medications": ["Edarbi 80"]},
    }
    synced = client.post("/api/health/sync", json={"snapshot": snapshot})
    assert synced.status_code == 200
    assert "385" in synced.json()["report"]

    day = client.get("/api/health/day/2026-08-19")
    assert day.status_code == 200
    assert day.json()["snapshot"]["activity"]["steps"] == 871


def test_coach_health_chat_fallback_without_api_key(monkeypatch):
    monkeypatch.delenv("CURSOR_API_KEY", raising=False)
    response = client.post(
        "/api/coach-health-chat",
        json={
            "message": "Что улучшить?",
            "snapshot": {
                "date": "2026-08-19",
                "blood_pressure": {"latest": {"systolic": 142, "diastolic": 95}},
                "sleep": {"duration_min": 360},
                "nutrition": {"calories": 900, "protein_g": 40},
                "profile": {
                    "medications": ["Edarbi 80"],
                    "coaching_calorie_target": {"kcal_min": 1900, "kcal_max": 2100, "protein_g": 130},
                },
            },
        },
    )
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "142/95" in reply or "Диастол" in reply or "соли" in reply
