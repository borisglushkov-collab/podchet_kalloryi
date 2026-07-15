"""AI text search for foods via Cursor API."""

import logging
import os
from functools import lru_cache

from ai_food_search_prompt import AI_FOOD_SEARCH_PROMPT, parse_ai_food_search_response
from cursor_client import CursorClient

logger = logging.getLogger(__name__)


class AiFoodSearchNotConfiguredError(RuntimeError):
    pass


@lru_cache(maxsize=1)
def _search_cursor_client() -> CursorClient:
    model = os.getenv("CURSOR_MODEL", "composer-2.5")
    return CursorClient(model=model)


async def ai_search_food(query: str) -> list[dict]:
    query = (query or "").strip()
    if len(query) < 2:
        return []
    if not os.getenv("CURSOR_API_KEY", "").strip():
        raise AiFoodSearchNotConfiguredError("CURSOR_API_KEY не настроен")

    client = _search_cursor_client()
    text = await client.prompt(
        AI_FOOD_SEARCH_PROMPT,
        f"Запрос пользователя: {query}\nВерни JSON по схеме.",
    )
    items = parse_ai_food_search_response(text)
    logger.info("AI food search for %r → %d items", query, len(items))
    return items
