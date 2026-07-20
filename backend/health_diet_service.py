"""Product search via health-diet.ru table_calorie database."""

from __future__ import annotations

import logging
import re
import time
from typing import Any

import httpx

logger = logging.getLogger(__name__)

TABLE_CALORIE_URL = "https://health-diet.ru/table_calorie/"
LIST_PATH_TEMPLATE = (
    "https://health-diet.ru/jsApp/{version}/modules/BaseOfFoodV2/list2018.json"
)
FALLBACK_LIST_URL = (
    "https://health-diet.ru/jsApp/v8.136.27/modules/BaseOfFoodV2/list2018.json"
)
USER_AGENT = "PodchetKalloriy/1.4 (+https://github.com/borisglushkov-collab/podchet_kalloryi)"
TIMEOUT = 20.0
CACHE_TTL_SEC = 12 * 60 * 60

_cache_items: list[dict[str, Any]] | None = None
_cache_loaded_at: float = 0.0


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
        "Accept": "application/json,text/html,*/*",
        "Referer": TABLE_CALORIE_URL,
    }


def _stem_hit(name_l: str, token: str) -> bool:
    """Match Russian word forms: гречка → гречневая / гречиха."""
    if len(token) < 4:
        return False
    stem = token[:4]
    words = re.split(r"[\s,./\-]+", name_l)
    return any(word.startswith(stem) for word in words if word)


def _relevance_score(name: str, query: str) -> int:
    name_l = name.lower()
    query_l = query.strip().lower()
    if not query_l:
        return 0
    if name_l == query_l:
        return 100
    if name_l.startswith(query_l):
        return 80
    if query_l in name_l:
        return 60
    tokens = [t for t in query_l.replace(",", " ").split() if len(t) >= 2]
    if not tokens:
        return 0
    matched = sum(1 for t in tokens if t in name_l)
    if matched == len(tokens):
        return 40
    if matched > 0:
        return 20
    stem_matched = sum(1 for t in tokens if _stem_hit(name_l, t))
    if stem_matched == len(tokens):
        words = re.split(r"[\s,./\-]+", name_l)
        # Prefer when a leading word matches the stem (гречневая… > йогурт греческий).
        if any(word.startswith(tokens[0][:4]) for word in words[:1] if len(tokens[0]) >= 4):
            return 50
        return 35
    if stem_matched > 0:
        return 25
    return 0


def _product_name(raw: dict[str, Any]) -> str:
    ns = raw.get("ns") or {}
    if isinstance(ns, dict):
        ru = ns.get("ru") or {}
        if isinstance(ru, dict) and ru.get("name"):
            return str(ru["name"]).strip()
        en = ns.get("en") or {}
        if isinstance(en, dict) and en.get("name"):
            return str(en["name"]).strip()
    return ""


def _map_item(raw: dict[str, Any]) -> dict[str, Any] | None:
    name = _product_name(raw)
    if not name:
        return None
    kcal = _num(raw.get("c"))
    if kcal <= 0:
        return None
    food_id = raw.get("i")
    url = (
        f"https://health-diet.ru/base_of_food/sostav/{food_id}.php"
        if food_id is not None
        else TABLE_CALORIE_URL
    )
    return {
        "name": name,
        "brand": None,
        "kcal_per_100g": round(kcal, 1),
        "protein_per_100g": round(_num(raw.get("p")), 1),
        "fat_per_100g": round(_num(raw.get("t")), 1),
        "carbs_per_100g": round(_num(raw.get("h")), 1),
        "source": "health_diet",
        "url": url,
    }


async def _discover_list_url(client: httpx.AsyncClient) -> str:
    try:
        response = await client.get(TABLE_CALORIE_URL, headers=_headers())
        response.raise_for_status()
        versions = re.findall(r"/jsApp/(v[\d.]+)/", response.text)
        if versions:
            version = sorted(set(versions))[-1]
            return LIST_PATH_TEMPLATE.format(version=version)
    except Exception as exc:
        logger.warning("health-diet version discovery failed: %s", exc)
    return FALLBACK_LIST_URL


async def _load_catalog(force: bool = False) -> list[dict[str, Any]]:
    global _cache_items, _cache_loaded_at

    now = time.monotonic()
    if (
        not force
        and _cache_items is not None
        and (now - _cache_loaded_at) < CACHE_TTL_SEC
    ):
        return _cache_items

    async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=True) as client:
        list_url = await _discover_list_url(client)
        response = await client.get(list_url, headers=_headers())
        if response.status_code != 200:
            response = await client.get(FALLBACK_LIST_URL, headers=_headers())
        response.raise_for_status()
        payload = response.json()

    if not isinstance(payload, list):
        raise ValueError("health-diet catalog is not a list")

    items: list[dict[str, Any]] = []
    for raw in payload:
        if not isinstance(raw, dict):
            continue
        mapped = _map_item(raw)
        if mapped:
            items.append(mapped)

    _cache_items = items
    _cache_loaded_at = now
    logger.info("health-diet catalog loaded: %d items from %s", len(items), list_url)
    return items


async def search_health_diet(query: str, page_size: int = 20) -> list[dict]:
    q = query.strip()
    if len(q) < 2:
        return []

    try:
        catalog = await _load_catalog()
    except Exception as exc:
        logger.warning("health-diet catalog unavailable: %s", exc)
        return []

    scored: list[tuple[int, dict]] = []
    for item in catalog:
        score = _relevance_score(item["name"], q)
        if score > 0:
            scored.append((score, item))

    scored.sort(key=lambda pair: (-pair[0], pair[1]["name"].lower()))
    return [item for _, item in scored[:page_size]]
