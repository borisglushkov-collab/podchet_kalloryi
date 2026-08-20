"""Collector source independence tests."""

from __future__ import annotations

import asyncio
from datetime import date

import data_collector
import health_day_store


def test_collect_works_without_xiaomi(monkeypatch):
    health_day_store.day_store.reset()

    async def no_tokens():
        return None

    def fake_food(_day):
        return [
            {
                "name": "Омлет",
                "meal": "Breakfast",
                "calories": 200,
                "protein": 14,
                "fat": 12,
                "carbs": 2,
                "grams": 1,
            }
        ]

    monkeypatch.setattr(data_collector, "_get_tokens", no_tokens)
    monkeypatch.setattr("fatsecret_client.load_tokens", lambda: ("tok", "sec"))
    monkeypatch.setattr("fatsecret_client.fetch_food_entries_for_date", fake_food)
    monkeypatch.setattr("medm_bp.load_creds", lambda: None)

    result = asyncio.run(data_collector.collect_for_date(date(2026, 8, 19)))
    assert "error" not in result
    assert result["nutrition"]["source"] == "fatsecret"
    assert result["sources_status"]["mi_fitness"]["ok"] is False
    assert result["sources_status"]["fatsecret"]["ok"] is True
    assert result["sources_status"]["fatsecret"]["count"] == 1
