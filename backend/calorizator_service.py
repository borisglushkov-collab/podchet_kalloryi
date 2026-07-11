"""Product search via calorizator.ru (Russian food database)."""

import asyncio
import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)

CALORIZATOR_BASE = "https://calorizator.ru"
AUTOCOMPLETE_URL = f"{CALORIZATOR_BASE}/widgets/c_ac.php"
PRODUCT_URL = f"{CALORIZATOR_BASE}/widgets/c_ap.php"
USER_AGENT = "PodchetKalloriy/1.0"
TIMEOUT = 8.0


def _num(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip().replace(",", "."))
    except (TypeError, ValueError):
        return 0.0


def _headers() -> dict[str, str]:
    return {
        "User-Agent": USER_AGENT,
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer": f"{CALORIZATOR_BASE}/analyzer/products",
    }


async def _post_list(client: httpx.AsyncClient, url: str, value: str) -> list[dict[str, Any]]:
    response = await client.post(url, data={"value": value}, headers=_headers())
    response.raise_for_status()
    data = response.json()
    return data if isinstance(data, list) else []


def _parse_product(name: str, raw: dict[str, Any]) -> dict | None:
    kcal = _num(raw.get("k"))
    if kcal <= 0:
        return None
    return {
        "name": name,
        "brand": None,
        "kcal_per_100g": kcal,
        "protein_per_100g": _num(raw.get("p")),
        "fat_per_100g": _num(raw.get("f")),
        "carbs_per_100g": _num(raw.get("c")),
        "source": "calorizator",
    }


async def search_calorizator(query: str, page_size: int = 20) -> list[dict]:
    q = query.strip()
    if len(q) < 2:
        return []

    async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=True) as client:
        try:
            suggestions = await _post_list(client, AUTOCOMPLETE_URL, q)
        except Exception as exc:
            logger.warning("Calorizator autocomplete failed: %s", exc)
            return []

        if not suggestions:
            return []

        kcal_by_name = {
            str(item.get("v", "")).strip(): _num(item.get("d"))
            for item in suggestions
            if str(item.get("v", "")).strip()
        }
        names = list(kcal_by_name.keys())[:page_size]

        async def fetch_one(name: str) -> dict | None:
            try:
                details = await _post_list(client, PRODUCT_URL, name)
                if details:
                    parsed = _parse_product(name, details[0])
                    if parsed:
                        return parsed
            except Exception as exc:
                logger.warning("Calorizator details failed for %s: %s", name, exc)

            kcal = kcal_by_name.get(name, 0.0)
            if kcal > 0:
                return {
                    "name": name,
                    "brand": None,
                    "kcal_per_100g": kcal,
                    "protein_per_100g": 0.0,
                    "fat_per_100g": 0.0,
                    "carbs_per_100g": 0.0,
                    "source": "calorizator",
                }
            return None

        results = await asyncio.gather(*(fetch_one(name) for name in names))
        return [item for item in results if item]
