"""FastAPI backend for calorie tracker AI suggestions."""

import logging
import os
from contextlib import asynccontextmanager
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from cursor_client import CursorClient
from food_search_service import search_food
from nutrition_prompt import (
    SYSTEM_PROMPT,
    build_top_up_summary_fallback,
    build_user_prompt,
    meal_plan_for_type,
    parse_ai_response,
    priority_macros,
)
from perekrestok_service import enrich_products

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

cursor_client: Optional[CursorClient] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global cursor_client
    cursor_client = CursorClient()
    yield
    cursor_client = None


app = FastAPI(title="Podchet Kalloriy API", version="1.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Macros(BaseModel):
    calories: float = 0
    protein: float = 0
    fat: float = 0
    carbs: float = 0


class SuggestMealRequest(BaseModel):
    meal_type: str = Field(description="breakfast, lunch, dinner, snack")
    consumed: Macros
    targets: Macros
    meal_consumed: Macros = Field(default_factory=Macros)
    meals_consumed: dict[str, Macros] = Field(default_factory=dict)
    preferences: list[str] = Field(default_factory=list)
    city: str = "Москва"


class SuggestMealResponse(BaseModel):
    deficit: Macros
    daily_deficit: Macros = Field(default_factory=Macros)
    effective_target: Macros = Field(default_factory=Macros)
    rollover_in: Macros = Field(default_factory=Macros)
    top_up_summary: str = ""
    priority_macros: list[str] = Field(default_factory=list)
    disclaimer: str = ""
    recipes: list[dict] = Field(default_factory=list)
    products: list[dict] = Field(default_factory=list)


@app.get("/")
async def root():
    has_key = bool(os.getenv("CURSOR_API_KEY"))
    return {
        "name": "Podchet Kalloriy API",
        "status": "running",
        "cursor_api_configured": has_key,
        "endpoints": {
            "health": "GET /health",
            "search_food": "GET /api/search-food?query=...",
            "suggest_meal": "POST /api/suggest-meal",
            "reset_session": "POST /api/reset-session",
            "docs": "GET /docs",
        },
        "app_url": "http://127.0.0.1:8080",
        "hint": "Это backend для ИИ. Откройте app_url — там приложение «Подсчёт калорий».",
    }


@app.get("/health")
async def health():
    has_key = bool(os.getenv("CURSOR_API_KEY"))
    return {"status": "ok", "cursor_api_configured": has_key}


@app.get("/api/search-food")
async def search_food_endpoint(query: str):
    try:
        result = await search_food(query)
        return result
    except Exception as e:
        logger.exception("Food search error")
        raise HTTPException(status_code=502, detail=f"Ошибка поиска продуктов: {e}") from e


@app.post("/api/suggest-meal", response_model=SuggestMealResponse)
async def suggest_meal(request: SuggestMealRequest):
    if not cursor_client or not os.getenv("CURSOR_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="CURSOR_API_KEY не настроен. Создайте backend/.env из .env.example",
        )

    daily_deficit = Macros(
        calories=max(0, request.targets.calories - request.consumed.calories),
        protein=max(0, request.targets.protein - request.consumed.protein),
        fat=max(0, request.targets.fat - request.consumed.fat),
        carbs=max(0, request.targets.carbs - request.consumed.carbs),
    )

    meals_consumed = {
        meal: macros.model_dump()
        for meal, macros in request.meals_consumed.items()
    }
    if not meals_consumed:
        meals_consumed = {request.meal_type: request.meal_consumed.model_dump()}

    plan = meal_plan_for_type(
        request.targets.model_dump(), meals_consumed, request.meal_type
    )
    meal_deficit = Macros(**plan["deficit"])
    effective_target = Macros(**plan["effective"])
    rollover_in = Macros(**plan["rollover_in"])

    meal_names = {
        "breakfast": "завтрак",
        "lunch": "обед",
        "dinner": "ужин",
        "snack": "перекус",
    }
    meal_ru = meal_names.get(request.meal_type, request.meal_type)

    user_prompt = build_user_prompt(
        meal_type=request.meal_type,
        consumed=request.consumed.model_dump(),
        targets=request.targets.model_dump(),
        meal_consumed=request.meal_consumed.model_dump(),
        preferences=request.preferences,
        city=request.city,
        meals_consumed=meals_consumed,
    )

    try:
        result_text = await cursor_client.prompt(SYSTEM_PROMPT, user_prompt)
        parsed = parse_ai_response(result_text)
    except Exception as e:
        logger.exception("Cursor API error")
        detail = str(e)
        if hasattr(e, "response") and getattr(e, "response", None) is not None:
            try:
                body = e.response.json()
                detail = body.get("error", {}).get("message", detail)
            except Exception:
                pass
        raise HTTPException(status_code=502, detail=f"Ошибка ИИ: {detail}") from e

    raw_products = parsed.get("products", [])
    try:
        enriched_products = await enrich_products(raw_products, request.city)
    except Exception as e:
        logger.warning("Product enrichment failed: %s", e)
        from perekrestok_service import search_url

        enriched_products = [
            {
                "name": p.get("name", ""),
                "store": "Перекрёсток",
                "reason": p.get("reason", ""),
                "price_rub": None,
                "url": search_url(p.get("name", "")),
                "image_url": None,
            }
            for p in raw_products
        ]

    top_up_summary = parsed.get("top_up_summary") or build_top_up_summary_fallback(
        meal_ru,
        meal_deficit.model_dump(),
        rollover_in=rollover_in.model_dump(),
        is_last=plan["is_last"],
    )

    return SuggestMealResponse(
        deficit=meal_deficit,
        daily_deficit=daily_deficit,
        effective_target=effective_target,
        rollover_in=rollover_in,
        top_up_summary=top_up_summary,
        priority_macros=priority_macros(meal_deficit.model_dump()),
        disclaimer=parsed.get("disclaimer", "Рекомендации носят информационный характер."),
        recipes=parsed.get("recipes", []),
        products=enriched_products,
    )


@app.post("/api/reset-session")
async def reset_session():
    if cursor_client:
        cursor_client.reset_session()
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host=host, port=port, reload=True)
