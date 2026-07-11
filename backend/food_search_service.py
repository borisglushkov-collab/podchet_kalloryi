"""Food search: local database + Calorizator.ru."""

import logging

from calorizator_service import search_calorizator
from local_foods import LOCAL_FOODS

logger = logging.getLogger(__name__)


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


def _search_local(query: str, page_size: int) -> list[dict]:
    scored: list[tuple[int, dict]] = []
    for item in LOCAL_FOODS:
        score = _relevance_score(item["name"], query)
        if score > 0:
            scored.append((score, {**item, "source": "local"}))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [item for _, item in scored[:page_size]]


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
    for item in remote:
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

    remote_items: list[dict] = []
    try:
        remote_items = await search_calorizator(q, page_size)
    except Exception as exc:
        logger.warning("Calorizator unavailable: %s", exc)

    if local_items or remote_items:
        items = _merge_results(local_items, remote_items, q, page_size)
    else:
        items = []

    if local_items and remote_items:
        source = "mixed"
    elif remote_items:
        source = "calorizator"
    else:
        source = "local"

    return {"items": items, "source": source}
