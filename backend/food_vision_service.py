"""Food photo analysis via Cursor, Gemini or OpenAI vision APIs."""

import logging
import os
from functools import lru_cache
from typing import Any

import httpx

from cursor_client import CursorClient
from food_vision_prompt import FOOD_VISION_PROMPT, parse_food_vision_response

logger = logging.getLogger(__name__)


class FoodVisionNotConfiguredError(RuntimeError):
    pass


@lru_cache(maxsize=1)
def _vision_cursor_client() -> CursorClient:
    model = os.getenv("CURSOR_VISION_MODEL") or os.getenv("CURSOR_MODEL", "composer-2.5")
    return CursorClient(model=model)


async def _analyze_with_cursor(image_bytes: bytes, mime_type: str) -> str:
    if not os.getenv("CURSOR_API_KEY", "").strip():
        raise FoodVisionNotConfiguredError("CURSOR_API_KEY не настроен")

    client = _vision_cursor_client()
    return await client.prompt_with_images(
        FOOD_VISION_PROMPT,
        "Проанализируй фото еды и верни JSON по схеме из системного промпта.",
        [(image_bytes, mime_type)],
    )


async def _analyze_with_gemini(image_bytes: bytes, mime_type: str) -> str:
    import base64

    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise FoodVisionNotConfiguredError("GEMINI_API_KEY не настроен")

    model = os.getenv("GEMINI_VISION_MODEL", "gemini-2.0-flash")
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": FOOD_VISION_PROMPT},
                    {
                        "inline_data": {
                            "mime_type": mime_type,
                            "data": base64.b64encode(image_bytes).decode("ascii"),
                        }
                    },
                ]
            }
        ],
        "generationConfig": {"temperature": 0.2},
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(url, json=payload)
        response.raise_for_status()
        data = response.json()

    candidates = data.get("candidates") or []
    if not candidates:
        raise RuntimeError("Gemini не вернул результат")
    parts = candidates[0].get("content", {}).get("parts") or []
    texts = [p.get("text", "") for p in parts if p.get("text")]
    result = "\n".join(texts).strip()
    if not result:
        raise RuntimeError("Gemini вернул пустой ответ")
    return result


async def _analyze_with_openai(image_bytes: bytes, mime_type: str) -> str:
    import base64

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise FoodVisionNotConfiguredError("OPENAI_API_KEY не настроен")

    model = os.getenv("OPENAI_VISION_MODEL", "gpt-4o-mini")
    b64 = base64.b64encode(image_bytes).decode("ascii")
    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": FOOD_VISION_PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:{mime_type};base64,{b64}"},
                    },
                ],
            }
        ],
        "max_tokens": 800,
        "temperature": 0.2,
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json=payload,
        )
        response.raise_for_status()
        data = response.json()

    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("OpenAI не вернул результат")
    content = choices[0].get("message", {}).get("content", "")
    if not content:
        raise RuntimeError("OpenAI вернул пустой ответ")
    return content


def _provider_chain() -> list[str]:
    provider = os.getenv("FOOD_VISION_PROVIDER", "auto").lower()
    if provider == "cursor":
        return ["cursor"]
    if provider == "gemini":
        return ["gemini"]
    if provider == "openai":
        return ["openai"]

    chain: list[str] = []
    if os.getenv("CURSOR_API_KEY", "").strip():
        chain.append("cursor")
    chain.extend(["gemini", "openai"])
    return chain


async def analyze_food_image(image_bytes: bytes, mime_type: str) -> dict[str, Any]:
    mime_type = mime_type or "image/jpeg"
    errors: list[str] = []

    for name in _provider_chain():
        try:
            if name == "cursor":
                raw = await _analyze_with_cursor(image_bytes, mime_type)
            elif name == "gemini":
                raw = await _analyze_with_gemini(image_bytes, mime_type)
            else:
                raw = await _analyze_with_openai(image_bytes, mime_type)
            parsed = parse_food_vision_response(raw)
            parsed["vision_provider"] = name
            return parsed
        except FoodVisionNotConfiguredError as exc:
            errors.append(str(exc))
        except Exception as exc:
            logger.warning("Food vision provider %s failed: %s", name, exc)
            errors.append(f"{name}: {exc}")

    if errors:
        raise FoodVisionNotConfiguredError(
            "Анализ фото недоступен. Настройте CURSOR_API_KEY (рекомендуется), "
            "GEMINI_API_KEY или OPENAI_API_KEY на сервере. "
            + "; ".join(errors)
        )
    raise FoodVisionNotConfiguredError("Анализ фото не настроен")
