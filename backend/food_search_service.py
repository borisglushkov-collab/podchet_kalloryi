"""Food search: local + health-diet.ru + calorizator.ru + Open Food Facts."""

import asyncio
import logging
import re

from barcode_service import search_openfoodfacts
from calorizator_service import search_calorizator
from health_diet_service import search_health_diet
from local_foods import LOCAL_FOODS

logger = logging.getLogger(__name__)


def _stem_hit(name_l: str, token: str) -> bool:
    if len(token) < 4:
        return False
    stem = token[:4]
    words = re.split(r"[\s,./\-]+", name_l)
    return any(word.startswith(stem) for word in words if word)


def _relevance_score(name: str, query: str, brand: str | None = None) -> int:
    haystack = name
    if brand:
        haystack = f"{name} {brand}"
    name_l = haystack.lower()
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
        if any(word.startswith(tokens[0][:4]) for word in words[:1] if len(tokens[0]) >= 4):
            return 50
        return 35
    if stem_matched > 0:
        return 25
    return 0


def _search_local(query: str, page_size: int) -> list[dict]:
    scored: list[tuple[int, dict]] = []
    for item in LOCAL_FOODS:
        score = _relevance_score(item["name"], query, item.get("brand"))
        if score > 0:
            scored.append((score, {**item, "source": "local"}))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [item for _, item in scored[:page_size]]


def _source_bonus(source: str) -> int:
    # Prefer curated local, then OFF brands, health-diet tables, then calorizator.
    if source == "local":
        return 5
    if source == "openfoodfacts":
        return 4
    if source == "health_diet":
        return 3
    if source == "calorizator":
        return 1
    return 0


def _merge_results(parts: list[list[dict]], query: str, page_size: int) -> list[dict]:
    seen: set[str] = set()
    merged: list[tuple[int, dict]] = []
    fallback: list[dict] = []

    for group in parts:
        for item in group:
            key = item["name"].lower()
            if key in seen:
                continue
            score = _relevance_score(item["name"], query, item.get("brand"))
            if score > 0:
                seen.add(key)
                merged.append((score + _source_bonus(item.get("source", "")), item))
            else:
                fallback.append(item)

    merged.sort(key=lambda x: x[0], reverse=True)
    results = [item for _, item in merged[:page_size]]

    if len(results) < page_size:
        for item in fallback:
            key = item["name"].lower()
            if key in seen:
                continue
            seen.add(key)
            results.append(item)
            if len(results) >= page_size:
                break

    return results


async def search_food(query: str, page_size: int = 20) -> dict:
    q = query.strip()
    if len(q) < 2:
        return {"items": [], "source": "local"}

    local_items = _search_local(q, page_size)

    async def _safe_calorizator() -> list[dict]:
        try:
            return await search_calorizator(q, page_size)
        except Exception as exc:
            logger.warning("Calorizator unavailable: %s", exc)
            return []

    async def _safe_health_diet() -> list[dict]:
        try:
            return await search_health_diet(q, page_size)
        except Exception as exc:
            logger.warning("health-diet unavailable: %s", exc)
            return []

    async def _safe_openfoodfacts() -> list[dict]:
        try:
            return await search_openfoodfacts(q, page_size)
        except Exception as exc:
            logger.warning("Open Food Facts unavailable: %s", exc)
            return []

    calorizator_items, health_diet_items, off_items = await asyncio.gather(
        _safe_calorizator(),
        _safe_health_diet(),
        _safe_openfoodfacts(),
    )

    remote_parts = [off_items, health_diet_items, calorizator_items]
    items = _merge_results([local_items, *remote_parts], q, page_size)

    sources = set()
    if local_items:
        sources.add("local")
    if off_items:
        sources.add("openfoodfacts")
    if health_diet_items:
        sources.add("health_diet")
    if calorizator_items:
        sources.add("calorizator")

    if len(sources) > 1:
        source = "mixed"
    elif sources:
        source = next(iter(sources))
    else:
        source = "local"

    return {"items": items, "source": source}
