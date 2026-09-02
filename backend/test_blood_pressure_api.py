"""API tests for blood-pressure endpoints."""

from datetime import datetime, timedelta

from fastapi.testclient import TestClient

import blood_pressure_store
from main import app

client = TestClient(app)


def setup_function() -> None:
    blood_pressure_store.store.reset()


def test_post_and_get_blood_pressure():
    measured = datetime.now().replace(hour=7, minute=32, second=0, microsecond=0)
    iso = measured.isoformat()
    day = measured.strftime("%Y-%m-%d")
    response = client.post(
        "/api/health/blood-pressure",
        json={
            "measured_at": iso,
            "systolic": 133,
            "diastolic": 90,
            "pulse": 72,
            "source": "manual",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["created"] is True
    assert body["item"]["systolic"] == 133

    listed = client.get("/api/health/blood-pressure", params={"from": day, "to": day})
    assert listed.status_code == 200
    assert listed.json()["count"] == 1


def test_duplicate_post_is_idempotent():
    payload = {
        "measured_at": datetime.now().replace(microsecond=0).isoformat(),
        "systolic": 133,
        "diastolic": 90,
        "pulse": 72,
    }
    first = client.post("/api/health/blood-pressure", json=payload)
    second = client.post("/api/health/blood-pressure", json=payload)
    assert first.json()["created"] is True
    assert second.json()["created"] is False
    assert client.get("/api/health/blood-pressure").json()["count"] == 1


def test_import_csv_and_summary():
    today = datetime.now()
    yesterday = today - timedelta(days=1)
    csv_text = (
        "Дата,Время,Сис,Диа,Пульс\n"
        f"{today.strftime('%Y-%m-%d')},07:32,133,90,72\n"
        f"{yesterday.strftime('%Y-%m-%d')},07:15,142,95,80\n"
    )
    imported = client.post(
        "/api/health/blood-pressure/import-csv",
        json={"csv": csv_text},
    )
    assert imported.status_code == 200
    assert imported.json()["created"] == 2

    summary = client.get("/api/health/blood-pressure/summary", params={"days": 7})
    assert summary.status_code == 200
    data = summary.json()
    assert data["count"] == 2
    assert data["avg"]["systolic"] == 137.5
    assert data["high_count"] == 2


def test_rejects_invalid_reading():
    response = client.post(
        "/api/health/blood-pressure",
        json={"systolic": 40, "diastolic": 90},
    )
    assert response.status_code == 400
