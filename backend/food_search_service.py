"""Food search: local database + optional Open Food Facts."""

import asyncio
import logging

import httpx

from local_foods import LOCAL_FOODS

logger = logging.getLogger(__name__)

OFF_ENDPOINTS = (
    "https://ru.openfoodfacts.org",
    "https://world.openfoodfacts.org",
)
USER_AGENT = "PodchetKalloriy/1.0"
OFF_TIMEOUT = 5.0


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
    return 0


def _product_name(raw: dict) -> str | None:
    for key in ("product_name_ru", "product_name", "generic_name_ru", "generic_name"):
        value = raw.get(key)
        if value and str(value).strip():
            return str(value).strip()
    return None


def _parse_product(raw: dict) -> dict | None:
    name = _product_name(raw)
    if not name:
        return None
    nutriments = raw.get("nutriments") or {}
    kcal = _num(nutriments.get("energy-kcal_100g"))
    if kcal <= 0:
        return None
    return {
        "name": name,
        "brand": raw.get("brands"),
        "kcal_per_100g": kcal,
        "protein_per_100g": _num(nutriments.get("proteins_100g")),
        "fat_per_100g": _num(nutriments.get("fat_100g")),
        "carbs_per_100g": _num(nutriments.get("carbohydrates_100g")),
        "source": "openfoodfacts",
    }


def _search_local(query: str, page_size: int) -> list[dict]:
    scored: list[tuple[int, dict]] = []
    for item in LOCAL_FOODS:
        score = _relevance_score(item["name"], query)
        if score > 0:
            scored.append((score, {**item, "source": "local"}))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [item for _, item in scored[:page_size]]


async def _fetch_off_cgi(client: httpx.AsyncClient, query: str) -> list[dict]:
    for base_url in OFF_ENDPOINTS:
        try:
            response = await client.get(
                f"{base_url}/cgi/search.pl",
                headers={"User-Agent": USER_AGENT},
                params={
                    "search_terms": query,
                    "search_simple": 1,
                    "action": "process",
                    "json": 1,
                    "page_size": 30,
                    "lc": "ru",
                },
            )
            response.raise_for_status()
            products = response.json().get("products", [])
            if products:
                return products
        except Exception as exc:
            logger.warning("OFF CGI search failed on %s: %s", base_url, exc)
    return []


async def _fetch_off_v2(client: httpx.AsyncClient, query: str) -> list[dict]:
    for base_url in OFF_ENDPOINTS:
        try:
            response = await client.get(
                f"{base_url}/api/v2/search",
                headers={"User-Agent": USER_AGENT},
                params={
                    "search_terms": query,
                    "lc": "ru",
                    "page_size": 30,
                    "fields": "product_name,product_name_ru,generic_name,generic_name_ru,brands,nutriments",
                },
            )
            response.raise_for_status()
            products = response.json().get("products", [])
            if products:
                return products
        except Exception as exc:
            logger.warning("OFF v2 search failed on %s: %s", base_url, exc)
    return []


async def _fetch_off_products(query: str) -> list[dict]:
    async with httpx.AsyncClient(timeout=OFF_TIMEOUT) as client:
        for fetcher in (_fetch_off_cgi, _fetch_off_v2):
            try:
                products = await fetcher(client, query)
                if products:
                    return products
            except Exception as exc:
                logger.warning("OFF search failed: %s", exc)
    return []


def _merge_results(local: list[dict], remote: list[dict], query: str, page_size: int) -> list[dict]:
    seen: set[str] = set()
    merged: list[tuple[int, dict]] = []

    for item in local:
        key = item["name"].lower()
        if key in seen:
            continue
        seen.add(key)
        merged.append((_relevance_score(item["name"], query) + 5, item))

    scored_remote: list[tuple[int, dict]] = []
    fallback_remote: list[dict] = []
    for raw in remote:
        item = _parse_product(raw)
        if not item:
            continue
        key = item["name"].lower()
        if key in seen:
            continue
        score = _relevance_score(item["name"], query)
        if score > 0:
            scored_remote.append((score, item))
        else:
            fallback_remote.append(item)

    scored_remote.sort(key=lambda x: x[0], reverse=True)
    for score, item in scored_remote:
        key = item["name"].lower()
        if key in seen:
            continue
        seen.add(key)
        merged.append((score, item))

    merged.sort(key=lambda x: x[0], reverse=True)
    results = [item for _, item in merged[:page_size]]

    if len(results) < page_size:
        for item in fallback_remote:
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

    off_raw: list[dict] = []
    try:
        off_raw = await asyncio.wait_for(_fetch_off_products(q), timeout=OFF_TIMEOUT)
    except Exception as exc:
        logger.warning("Open Food Facts unavailable: %s", exc)

    items = _merge_results(local_items, off_raw, q, page_size)
    source = "mixed" if off_raw and local_items else "openfoodfacts" if off_raw else "local"
    return {"items": items, "source": source}


def _num(value) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0
