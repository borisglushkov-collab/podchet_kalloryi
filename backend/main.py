"""FastAPI backend for calorie tracker AI suggestions."""

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from ai_food_search_service import (
    AiFoodSearchNotConfiguredError,
    ai_search_food,
    format_ai_error,
)
from barcode_service import lookup_barcode
from coach_chat_fallback import build_coach_chat_fallback
from coach_chat_prompt import COACH_CHAT_SYSTEM_PROMPT, build_coach_chat_prompt
from cursor_client import CursorClient
from food_search_service import search_food
from food_vision_service import FoodVisionNotConfiguredError, analyze_food_image
from nutrition_prompt import (
    SYSTEM_PROMPT,
    analyze_weight_context,
    build_top_up_summary_fallback,
    build_user_prompt,
    cap_macros_by_daily,
    meal_plan_for_type,
    parse_ai_response,
    priority_macros,
    profile_insight_short,
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


class ProfileContext(BaseModel):
    gender: str = "male"
    age: int = 30
    height_cm: float = 170
    weight_kg: float = 70
    activity: str = "moderate"
    goal: str = "maintain"
    use_custom_targets: bool = False
    target_weight_kg: float | None = None


class SuggestMealRequest(BaseModel):
    meal_type: str = Field(description="breakfast, lunch, dinner, snack")
    consumed: Macros
    targets: Macros
    meal_consumed: Macros = Field(default_factory=Macros)
    meals_consumed: dict[str, Macros] = Field(default_factory=dict)
    preferences: list[str] = Field(default_factory=list)
    city: str = "Москва"
    profile_context: ProfileContext | None = None
    weight_context: dict | None = None


class SuggestMealResponse(BaseModel):
    deficit: Macros
    daily_deficit: Macros = Field(default_factory=Macros)
    effective_target: Macros = Field(default_factory=Macros)
    rollover_in: Macros = Field(default_factory=Macros)
    top_up_summary: str = ""
    priority_macros: list[str] = Field(default_factory=list)
    disclaimer: str = ""
    weight_insight: str = ""
    recipes: list[dict] = Field(default_factory=list)
    products: list[dict] = Field(default_factory=list)


class ChatMessage(BaseModel):
    role: str = Field(description="user or assistant")
    content: str


class CoachChatRequest(BaseModel):
    message: str
    history: list[ChatMessage] = Field(default_factory=list)
    meal_type: str = "dinner"
    consumed: Macros = Field(default_factory=Macros)
    targets: Macros = Field(default_factory=Macros)
    meal_consumed: Macros = Field(default_factory=Macros)
    meals_consumed: dict[str, Macros] = Field(default_factory=dict)
    preferences: list[str] = Field(default_factory=list)
    profile_context: ProfileContext | None = None
    weight_context: dict | None = None


class CoachChatResponse(BaseModel):
    reply: str
    disclaimer: str = "Рекомендации носят информационный характер и не заменяют консультацию врача."


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
            "ai_search_food": "POST /api/ai-search-food",
            "search_barcode": "GET /api/search-barcode?barcode=...",
            "analyze_food_image": "POST /api/analyze-food-image",
            "suggest_meal": "POST /api/suggest-meal",
            "coach_chat": "POST /api/coach-chat",
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


class AiSearchFoodRequest(BaseModel):
    query: str


@app.post("/api/ai-search-food")
async def ai_search_food_endpoint(request: AiSearchFoodRequest):
    query = request.query.strip()
    if len(query) < 2:
        raise HTTPException(status_code=400, detail="Введите название продукта (минимум 2 символа)")
    if not cursor_client or not os.getenv("CURSOR_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="CURSOR_API_KEY не настроен. Создайте backend/.env из .env.example",
        )
    try:
        items = await ai_search_food(query, client=cursor_client)
        return {"items": items, "source": "ai_search"}
    except AiFoodSearchNotConfiguredError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    except Exception as e:
        ai_err = format_ai_error(e)
        logger.exception("AI food search error: %s", ai_err)
        # Don't block the user: fall back to calorizator/local search.
        try:
            fallback = await search_food(query)
            items = fallback.get("items") or []
            if items:
                src = fallback.get("source") or "local"
                logger.warning(
                    "AI search failed (%s); returning %d items from %s",
                    ai_err,
                    len(items),
                    src,
                )
                return {
                    "items": items,
                    "source": f"fallback_{src}",
                    "ai_error": ai_err,
                    "warning": (
                        "ИИ не ответил вовремя — показаны результаты обычного поиска. "
                        f"({ai_err})"
                    ),
                }
        except Exception as fallback_exc:
            logger.warning("Fallback food search also failed: %s", fallback_exc)
        raise HTTPException(
            status_code=502, detail=f"Ошибка ИИ-поиска: {ai_err}"
        ) from e


@app.get("/api/search-barcode")
async def search_barcode_endpoint(barcode: str):
    try:
        item = await lookup_barcode(barcode)
        if not item:
            raise HTTPException(
                status_code=404,
                detail="Продукт по штрихкоду не найден в Open Food Facts",
            )
        return {"item": item, "source": "openfoodfacts"}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Barcode search error")
        raise HTTPException(status_code=502, detail=f"Ошибка поиска по штрихкоду: {e}") from e


@app.post("/api/analyze-food-image")
async def analyze_food_image_endpoint(file: UploadFile = File(...)):
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Загрузите файл изображения (JPEG/PNG)")

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Пустой файл")
    if len(image_bytes) > 8 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Файл больше 8 МБ")

    try:
        item = await analyze_food_image(image_bytes, file.content_type)
        return {"item": item, "source": item.get("source", "ai_vision")}
    except FoodVisionNotConfiguredError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    except Exception as e:
        logger.exception("Food vision error")
        raise HTTPException(status_code=502, detail=f"Ошибка анализа фото: {e}") from e


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
    meal_deficit = Macros(
        **cap_macros_by_daily(plan["deficit"], daily_deficit.model_dump())
    )
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
        weight_context=request.weight_context,
        profile_context=(
            request.profile_context.model_dump() if request.profile_context else None
        ),
    )

    try:
        result_text = await asyncio.wait_for(
            cursor_client.prompt(SYSTEM_PROMPT, user_prompt),
            timeout=90.0,
        )
        parsed = parse_ai_response(result_text)
    except Exception as e:
        logger.exception("Cursor API error")
        if cursor_client is not None:
            cursor_client.reset_session()
        raise HTTPException(
            status_code=502, detail=f"Ошибка ИИ: {format_ai_error(e)}"
        ) from e

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

    weight_insight_parts = []
    if request.profile_context:
        profile_note = profile_insight_short(request.profile_context.model_dump())
        if profile_note:
            weight_insight_parts.append(profile_note)
    weight_note = analyze_weight_context(request.weight_context)
    if weight_note:
        weight_insight_parts.append(weight_note)
    weight_insight = " ".join(weight_insight_parts)

    return SuggestMealResponse(
        deficit=meal_deficit,
        daily_deficit=daily_deficit,
        effective_target=effective_target,
        rollover_in=rollover_in,
        top_up_summary=top_up_summary,
        priority_macros=priority_macros(meal_deficit.model_dump()),
        disclaimer=parsed.get("disclaimer", "Рекомендации носят информационный характер."),
        weight_insight=weight_insight,
        recipes=parsed.get("recipes", []),
        products=enriched_products,
    )


@app.post("/api/coach-chat", response_model=CoachChatResponse)
async def coach_chat(request: CoachChatRequest):
    if not cursor_client or not os.getenv("CURSOR_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="CURSOR_API_KEY не настроен. Создайте backend/.env из .env.example",
        )

    message = request.message.strip()
    if len(message) < 1:
        raise HTTPException(status_code=400, detail="Пустое сообщение")
    if len(message) > 2000:
        raise HTTPException(status_code=400, detail="Сообщение слишком длинное")

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
    meal_deficit = Macros(
        **cap_macros_by_daily(plan["deficit"], daily_deficit.model_dump())
    )

    weight_insight_parts = []
    if request.profile_context:
        profile_note = profile_insight_short(request.profile_context.model_dump())
        if profile_note:
            weight_insight_parts.append(profile_note)
    weight_note = analyze_weight_context(request.weight_context)
    if weight_note:
        weight_insight_parts.append(weight_note)

    history = [
        {"role": m.role if m.role in {"user", "assistant"} else "user", "content": m.content}
        for m in request.history
        if m.content.strip()
    ]

    user_prompt = build_coach_chat_prompt(
        message,
        history=history,
        meal_type=request.meal_type,
        consumed=request.consumed.model_dump(),
        targets=request.targets.model_dump(),
        daily_deficit=daily_deficit.model_dump(),
        meal_deficit=meal_deficit.model_dump(),
        preferences=request.preferences,
        profile_context=(
            request.profile_context.model_dump() if request.profile_context else None
        ),
        weight_insight=" ".join(weight_insight_parts),
    )

    # Fail over quickly: Cursor agents often hang ~60s on this VPS.
    try:
        reply = await asyncio.wait_for(
            cursor_client.prompt(COACH_CHAT_SYSTEM_PROMPT, user_prompt),
            timeout=50.0,
        )
        reply = (reply or "").strip()
        if reply:
            return CoachChatResponse(reply=reply)
        logger.warning("Coach chat returned empty reply; using fallback")
    except Exception as e:
        ai_err = format_ai_error(e)
        logger.exception("Coach chat error: %s — using offline fallback", ai_err)
        if cursor_client is not None:
            cursor_client.reset_session()

    reply = build_coach_chat_fallback(
        message,
        meal_type=request.meal_type,
        daily_deficit=daily_deficit.model_dump(),
        meal_deficit=meal_deficit.model_dump(),
        preferences=request.preferences,
        profile_context=(
            request.profile_context.model_dump() if request.profile_context else None
        ),
    )
    return CoachChatResponse(reply=reply)


@app.post("/api/reset-session")
async def reset_session():
    if cursor_client:
        cursor_client.reset_session()
    return {"status": "ok", "hint": "Сессия Cursor сброшена. Повторите запрос через несколько секунд."}


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host=host, port=port, reload=True)
