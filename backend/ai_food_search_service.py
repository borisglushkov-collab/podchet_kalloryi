"""AI text search for foods via Cursor API."""

import logging
import os
from typing import Optional

import httpx

from ai_food_search_prompt import AI_FOOD_SEARCH_PROMPT, parse_ai_food_search_response
from cursor_client import CursorClient

logger = logging.getLogger(__name__)


class AiFoodSearchNotConfiguredError(RuntimeError):
    pass


def format_ai_error(exc: BaseException) -> str:
    """Human-readable Cursor/httpx error (never empty)."""
    if isinstance(exc, httpx.HTTPStatusError):
        status = exc.response.status_code if exc.response is not None else "?"
        body = ""
        try:
            data = exc.response.json()
            err = data.get("error", data)
            if isinstance(err, dict):
                body = str(err.get("message") or err)
            else:
                body = str(err)
        except Exception:
            body = (exc.response.text or "")[:300] if exc.response is not None else ""
        return f"HTTP {status}: {body}".strip()
    if isinstance(exc, httpx.TimeoutException):
        return "таймаут запроса к Cursor API"
    text = str(exc).strip()
    if text:
        return text
    return f"{type(exc).__name__}: без текста ошибки"


async def ai_search_food(
    query: str,
    *,
    client: Optional[CursorClient] = None,
) -> list[dict]:
    query = (query or "").strip()
    if len(query) < 2:
        return []
    if not os.getenv("CURSOR_API_KEY", "").strip():
        raise AiFoodSearchNotConfiguredError("CURSOR_API_KEY не настроен")

    # Prefer shared client from FastAPI lifespan to avoid competing Cursor agents.
    active = client or CursorClient()
    try:
        text = await active.prompt(
            AI_FOOD_SEARCH_PROMPT,
            f"Запрос пользователя: {query}\nВерни JSON по схеме.",
        )
        items = parse_ai_food_search_response(text)
    except Exception as exc:
        raise RuntimeError(format_ai_error(exc)) from exc

    logger.info("AI food search for %r → %d items", query, len(items))
    return items
