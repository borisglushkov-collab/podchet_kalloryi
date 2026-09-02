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
    assert "Неделя" in response.text
    assert "js/main.js?v=" in response.text
    assert 'type="module"' in response.text
    assert "Сбор" in response.text


def test_week_endpoint_returns_report():
    health_day_store.day_store.upsert(
        {
            "date": "2026-08-19",
            "nutrition": {"calories": 1551, "meals": []},
            "activity": {"steps": 7000},
            "profile": {"coaching_calorie_target": {"kcal_min": 1900, "kcal_max": 2100}},
        }
    )
    response = client.get("/api/health/week?days=7&end=2026-08-19")
    assert response.status_code == 200
    data = response.json()
    assert len(data["days"]) == 7
    assert data["days"][-1]["date"] == "2026-08-19"
    assert "Неделя для коуча" in data["report"]
    assert "1551" in data["report"]


def test_collector_status_includes_connections():
    response = client.get("/api/health/collector-status")
    assert response.status_code == 200
    data = response.json()
    assert "connections" in data
    assert "xiaomi" in data["connections"]
    assert "fatsecret" in data["connections"]
    assert "medm" in data["connections"]
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


def test_day_endpoint_keeps_snapshot_bp_when_store_empty():
    health_day_store.day_store.upsert(
        {
            "date": "2026-08-20",
            "blood_pressure": {
                "latest": {"systolic": 130, "diastolic": 85, "source": "medm_bp"},
                "readings_today": [
                    {
                        "systolic": 130,
                        "diastolic": 85,
                        "pulse": 72,
                        "measured_at": "2026-08-20T08:00:00",
                        "source": "medm_bp",
                    },
                    {
                        "systolic": 128,
                        "diastolic": 82,
                        "pulse": 70,
                        "measured_at": "2026-08-20T12:00:00",
                        "source": "medm_bp",
                    },
                ],
            },
        }
    )
    response = client.get("/api/health/day/2026-08-20")
    assert response.status_code == 200
    readings = response.json()["snapshot"]["blood_pressure"]["readings_today"]
    assert len(readings) == 2
    assert readings[0]["systolic"] == 128


def test_sync_keeps_existing_fatsecret_when_client_sends_empty_meals():
    health_day_store.day_store.upsert(
        {
            "date": "2026-08-19",
            "nutrition": {
                "calories": 1138,
                "source": "fatsecret",
                "meals": [
                    {
                        "meal_type": "breakfast",
                        "items": [{"name": "Хлеб", "calories": 66, "protein_g": 1.9, "fat_g": 0.8, "carbs_g": 12.7}],
                    }
                ],
            },
        }
    )
    response = client.post(
        "/api/health/sync",
        json={
            "snapshot": {
                "date": "2026-08-19",
                "nutrition": {"calories": 0, "meals": []},
                "activity": {"steps": 100, "source": "manual"},
            }
        },
    )
    assert response.status_code == 200
    day = client.get("/api/health/day/2026-08-19")
    nutrition = day.json()["snapshot"]["nutrition"]
    assert nutrition["source"] == "fatsecret"
    assert nutrition["calories"] == 1138


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


def test_manual_bp_goes_to_store():
    response = client.post(
        "/api/health/blood-pressure",
        json={"systolic": 125, "diastolic": 80, "pulse": 70, "measured_at": "2026-08-20T10:00:00", "source": "manual"},
    )
    assert response.status_code == 200
    listed = client.get("/api/health/blood-pressure?from=2026-08-20&to=2026-08-20")
    assert listed.status_code == 200
    assert listed.json()["count"] >= 1


def test_disconnect_unknown_source():
    response = client.post("/api/health/disconnect/twitter")
    assert response.status_code == 400
