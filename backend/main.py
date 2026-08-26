"""FastAPI backend for calorie tracker AI suggestions."""

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from datetime import date as Date
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

import hub_auth
from hub_auth import COOKIE_NAME as HUB_SESSION_COOKIE
from hub_auth import issue_token, path_requires_pin, pin_configured, token_valid


def _read_api_version() -> str:
    """Version from backend/VERSION (synced from root VERSION via scripts/sync-version.sh)."""
    path = Path(__file__).resolve().parent / "VERSION"
    if path.is_file():
        text = path.read_text(encoding="utf-8").strip()
        if text:
            return text.splitlines()[0].strip()
    return "0.0.0"

from ai_food_search_service import (
    AiFoodSearchNotConfiguredError,
    ai_search_food,
    format_ai_error,
)
from barcode_service import lookup_barcode
from blood_pressure_csv import CsvImportError, parse_citizen_csv
from blood_pressure_store import store as bp_store
from health_day_store import day_store
from hub_profile_store import profile_store
from coach_chat_fallback import build_coach_chat_fallback
from coach_chat_prompt import COACH_CHAT_SYSTEM_PROMPT, build_coach_chat_prompt
from coach_health_fallback import build_coach_health_fallback
from coach_health_prompt import COACH_HEALTH_SYSTEM_PROMPT, build_coach_health_prompt
from coach_health_report import format_day_report, format_week_report
from cursor_client import CursorClient
from data_collector import backfill_days, collect_for_date, collect_once, collector_status, start_collector, stop_collector, user_local_date
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
    if os.getenv("XIAOMI_USER") or (Path(__file__).resolve().parent / "data" / "xiaomi_token.json").is_file():
        start_collector()
    yield
    stop_collector()
    cursor_client = None


app = FastAPI(
    title="Podchet Kalloriy API",
    version=_read_api_version(),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def hub_pin_guard(request: Request, call_next):
    path = request.url.path
    if not path_requires_pin(path) or not pin_configured():
        return await call_next(request)
    token = request.cookies.get(HUB_SESSION_COOKIE)
    if token_valid(token):
        return await call_next(request)
    return JSONResponse({"detail": "PIN required"}, status_code=401)


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


class DiaryEntry(BaseModel):
    meal_type: str = "snack"
    name: str = ""
    grams: float = 0
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
    profile_context: ProfileContext | None = None
    weight_context: dict | None = None
    diary_entries: list[DiaryEntry] = Field(default_factory=list)


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


class HealthContext(BaseModel):
    blood_pressure_latest: dict | None = None
    blood_pressure_avg_7d: dict | None = None
    sleep_last_night_min: int | None = None
    steps_today: int | None = None
    weight_latest_kg: float | None = None
    medications: list[str] = Field(default_factory=list)
    coaching_targets: dict | None = None


class BloodPressureReadingIn(BaseModel):
    measured_at: str | None = None
    systolic: int
    diastolic: int
    pulse: int | None = None
    source: str = "manual"
    note: str | None = None


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
    diary_entries: list[DiaryEntry] = Field(default_factory=list)
    health_context: HealthContext | None = None


class CoachHealthChatRequest(BaseModel):
    message: str = "Что улучшить по этому дню?"
    snapshot: dict = Field(default_factory=dict)
    history: list[ChatMessage] = Field(default_factory=list)
    week_report: str | None = None


class HealthSyncRequest(BaseModel):
    snapshot: dict


class HubProfileIn(BaseModel):
    height_cm: int | float | None = None
    weight_kg_latest: float | None = None
    medications: list[str] | str | None = None
    coaching_calorie_target: dict | None = None
    updated_at: str | None = None


class HubUnlockIn(BaseModel):
    pin: str


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
            "blood_pressure": "POST /api/health/blood-pressure",
            "blood_pressure_import": "POST /api/health/blood-pressure/import-csv",
            "blood_pressure_list": "GET /api/health/blood-pressure",
            "blood_pressure_summary": "GET /api/health/blood-pressure/summary",
            "coach_health_chat": "POST /api/coach-health-chat",
            "health_sync": "POST /api/health/sync",
            "health_day": "GET /api/health/day/{date}",
            "health_week": "GET /api/health/week",
            "health_report": "GET /api/health/day/{date}/report",
            "xiaomi_login": "POST /api/health/xiaomi-login",
            "collect_now": "POST /api/health/collect-now",
            "collector_status": "GET /api/health/collector-status",
            "hub": "GET /hub/",
            "reset_session": "POST /api/reset-session",
            "docs": "GET /docs",
        },
        "app_url": "http://127.0.0.1:8080",
        "hub_url": "/hub/",
        "hint": "Приложение сбора данных для коуча: откройте /hub/ . Старое приложение калорий — app_url.",
    }


@app.get("/health")
async def health():
    has_key = bool(os.getenv("CURSOR_API_KEY"))
    return {
        "status": "ok",
        "version": app.version,
        "cursor_api_configured": has_key,
    }


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
        diary_entries=[e.model_dump() for e in request.diary_entries],
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

    diary_payload = [e.model_dump() for e in request.diary_entries]
    health_payload = (
        request.health_context.model_dump() if request.health_context else None
    )
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
        diary_entries=diary_payload,
        health_context=health_payload,
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
        diary_entries=diary_payload,
    )
    return CoachChatResponse(reply=reply)


@app.post("/api/health/blood-pressure")
async def add_blood_pressure(reading: BloodPressureReadingIn):
    try:
        item, created = bp_store.add(reading.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"item": item, "created": created}


@app.post("/api/health/blood-pressure/import-csv")
async def import_blood_pressure_csv(request: Request):
    content_type = (request.headers.get("content-type") or "").lower()
    raw = ""
    if "multipart/form-data" in content_type:
        form = await request.form()
        upload = form.get("file")
        if upload is None:
            raise HTTPException(status_code=400, detail="Передайте CSV файл")
        data = await upload.read()
        raw = data.decode("utf-8-sig") if isinstance(data, bytes) else str(data)
    else:
        body = await request.json()
        raw = str((body or {}).get("csv") or "")
    if not raw.strip():
        raise HTTPException(status_code=400, detail="Передайте CSV файл или поле csv")
    try:
        parsed = parse_citizen_csv(raw)
    except CsvImportError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    stored = bp_store.add_many(parsed["readings"])
    return {
        "created": stored["created"],
        "skipped_duplicates": stored["skipped_duplicates"] + parsed["skipped_duplicates"],
        "parse_errors": parsed["errors"],
        "imported": stored["created"],
    }


@app.get("/api/health/blood-pressure")
async def list_blood_pressure(
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
):
    items = bp_store.list(from_date=from_, to_date=to)
    return {"count": len(items), "items": items}


@app.get("/api/health/blood-pressure/summary")
async def blood_pressure_summary(days: int = 7):
    if days not in (7, 30):
        days = 30 if days > 7 else 7
    return bp_store.summary(days)


def _merge_bp_readings(*groups: list[dict] | None) -> list[dict]:
    merged: list[dict] = []
    seen: set[tuple[str, int, int]] = set()
    for group in groups:
        for item in group or []:
            if not item.get("systolic") or not item.get("diastolic"):
                continue
            key = (str(item.get("measured_at") or ""), int(item["systolic"]), int(item["diastolic"]))
            if key in seen:
                continue
            seen.add(key)
            merged.append(item)
    merged.sort(key=lambda r: str(r.get("measured_at") or ""), reverse=True)
    return merged


def _attach_bp(snapshot: dict, date: str) -> dict:
    merged = dict(snapshot)
    bp_snapshot = merged.get("blood_pressure") or {}
    bp_items = bp_store.list(from_date=date, to_date=date)
    snapshot_readings = bp_snapshot.get("readings_today") or []
    readings_today = _merge_bp_readings(snapshot_readings, bp_items)
    summary = bp_store.summary(7)
    latest = bp_snapshot.get("latest") or (readings_today[0] if readings_today else summary.get("latest"))
    if bp_items and not bp_snapshot.get("latest"):
        latest = bp_items[0]
    merged["blood_pressure"] = {
        **bp_snapshot,
        "readings_today": readings_today,
        "latest": latest,
        "avg_7d": summary.get("avg"),
    }
    return merged


@app.post("/api/health/sync")
async def health_sync(request: HealthSyncRequest):
    try:
        saved = day_store.upsert(request.snapshot, merge=True)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    date = saved["date"]
    return {"snapshot": _attach_bp(saved, date), "report": format_day_report(_attach_bp(saved, date))}


@app.get("/api/health/profile")
async def get_hub_profile():
    return {"profile": profile_store.get()}


@app.put("/api/health/profile")
async def put_hub_profile(payload: HubProfileIn):
    saved = profile_store.save(payload.model_dump(exclude_unset=True))
    return {"profile": saved}


@app.get("/api/health/gate")
async def hub_gate():
    return {"pin_required": pin_configured()}


@app.post("/api/health/unlock")
async def hub_unlock(payload: HubUnlockIn):
    if not pin_configured():
        response = JSONResponse({"ok": True, "pin_required": False})
        response.delete_cookie(HUB_SESSION_COOKIE)
        return response
    if (payload.pin or "").strip() != hub_auth.expected_pin():
        raise HTTPException(status_code=401, detail="Неверный PIN")
    response = JSONResponse({"ok": True, "pin_required": True})
    response.set_cookie(
        key=HUB_SESSION_COOKIE,
        value=issue_token(),
        httponly=True,
        samesite="lax",
        max_age=hub_auth.TTL_SEC,
        path="/",
    )
    return response


@app.get("/api/health/day/{date}")
async def health_day(date: str):
    snapshot = day_store.get(date) or {"date": date, "generated_at": None}
    merged = _attach_bp(snapshot, date)
    return {"snapshot": merged, "report": format_day_report(merged)}


@app.get("/api/health/day/{date}/report")
async def health_day_report(date: str):
    snapshot = day_store.get(date) or {"date": date}
    merged = _attach_bp(snapshot, date)
    return {"report": format_day_report(merged)}


@app.get("/api/health/week")
async def health_week(days: int = Query(7, ge=1, le=31), end: str | None = Query(None)):
    end_day = user_local_date()
    if end:
        try:
            end_day = Date.fromisoformat(end)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="end must be YYYY-MM-DD") from exc
    snaps = day_store.list_range(end=end_day, days=days)
    merged = [_attach_bp(s, str(s.get("date") or "")) for s in snaps]
    profile = profile_store.get()
    for s in reversed(merged):
        if s.get("profile"):
            # prefer explicit day profile fields when present, else server profile
            day_profile = dict(profile)
            day_profile.update(s["profile"])
            profile = day_profile
            break
    return {
        "days": merged,
        "profile": profile,
        "report": format_week_report(merged, profile),
    }


@app.post("/api/health/collect-now")
async def collect_now(target_date: str | None = Query(None, alias="date")):
    day = None
    if target_date:
        try:
            day = Date.fromisoformat(target_date)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD") from exc
    result = await collect_for_date(day)
    if "error" in result:
        raise HTTPException(status_code=502, detail=result["error"])
    date_s = str(result.get("date") or (day.isoformat() if day else user_local_date().isoformat()))
    return _attach_bp(result, date_s)


@app.post("/api/health/backfill")
async def backfill(days: int = 7):
    if days < 1 or days > 31:
        raise HTTPException(status_code=400, detail="days must be between 1 and 31")
    return {"results": await backfill_days(days)}


@app.get("/api/health/collector-status")
async def get_collector_status():
    return collector_status()


@app.post("/api/coach-health-chat", response_model=CoachChatResponse)
async def coach_health_chat(request: CoachHealthChatRequest):
    message = (request.message or "").strip() or "Что улучшить по этому дню?"
    if len(message) > 2000:
        raise HTTPException(status_code=400, detail="Сообщение слишком длинное")
    snapshot = dict(request.snapshot or {})
    date = str(snapshot.get("date") or "")
    if date:
        try:
            day_store.upsert(snapshot, merge=True)
        except ValueError:
            pass
        snapshot = _attach_bp(snapshot, date)
    history = [
        {"role": m.role if m.role in {"user", "assistant"} else "user", "content": m.content}
        for m in request.history
        if m.content.strip()
    ]
    user_prompt = build_coach_health_prompt(
        message,
        snapshot,
        history=history,
        week_report=request.week_report,
    )

    if cursor_client and os.getenv("CURSOR_API_KEY"):
        try:
            reply = await asyncio.wait_for(
                cursor_client.prompt(COACH_HEALTH_SYSTEM_PROMPT, user_prompt),
                timeout=50.0,
            )
            reply = (reply or "").strip()
            if reply:
                return CoachChatResponse(reply=reply)
        except Exception as e:
            logger.exception("Coach health chat error: %s", format_ai_error(e))
            if cursor_client is not None:
                cursor_client.reset_session()

    reply = build_coach_health_fallback(message, snapshot)
    return CoachChatResponse(reply=reply)


class XiaomiLoginRequest(BaseModel):
    username: str
    password: str
    region: str = "ru"


class XiaomiVerifyRequest(BaseModel):
    session_id: str
    code: str


class XiaomiTokensRequest(BaseModel):
    user_id: str
    pass_token: str


@app.post("/api/health/xiaomi-login")
async def xiaomi_login(request: XiaomiLoginRequest):
    from xiaomi_auth import TwoFactorRequired, login_xiaomi
    try:
        tokens = await login_xiaomi(request.username, request.password)
    except TwoFactorRequired as e:
        return {
            "status": "2fa_required",
            "session_id": e.session_id,
            "message": "Код подтверждения отправлен на email/телефон. Введите его.",
        }
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    start_collector()
    return {
        "status": "ok",
        "user_id": tokens.user_id,
        "has_service_token": bool(tokens.service_token),
    }


@app.post("/api/health/xiaomi-verify")
async def xiaomi_verify(request: XiaomiVerifyRequest):
    from xiaomi_auth import login_xiaomi_verify
    try:
        tokens = await login_xiaomi_verify(request.session_id, request.code)
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    start_collector()
    return {
        "status": "ok",
        "user_id": tokens.user_id,
        "has_service_token": bool(tokens.service_token),
    }


@app.post("/api/health/xiaomi-tokens")
async def xiaomi_set_tokens(request: XiaomiTokensRequest):
    from xiaomi_auth import setup_tokens_direct
    try:
        tokens = await setup_tokens_direct(request.user_id, request.pass_token)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    start_collector()
    return {
        "status": "ok",
        "user_id": tokens.user_id,
        "has_service_token": bool(tokens.service_token),
    }


class MedMLoginRequest(BaseModel):
    email: str
    password: str


@app.post("/api/health/medm-login")
async def medm_login_endpoint(request: MedMLoginRequest):
    from medm_bp import medm_login
    try:
        record_id = await medm_login(request.email, request.password)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"status": "ok", "record_id": record_id}


@app.get("/api/health/medm-bp")
async def medm_bp_list(limit: int = 50):
    from medm_bp import fetch_bp_readings
    readings = await fetch_bp_readings(limit=limit)
    return {"count": len(readings), "readings": readings}


@app.get("/api/health/fatsecret-auth")
async def fatsecret_auth_start():
    from fatsecret_client import get_authorize_url
    url, session_id = get_authorize_url("oob")
    return {"authorize_url": url, "session_id": session_id}


class FatSecretVerifyRequest(BaseModel):
    session_id: str
    pin: str


@app.post("/api/health/fatsecret-verify")
async def fatsecret_verify(request: FatSecretVerifyRequest):
    from fatsecret_client import complete_auth
    try:
        complete_auth(request.session_id, request.pin)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"status": "ok"}


@app.get("/api/health/fatsecret-food")
async def fatsecret_food():
    from fatsecret_client import fetch_food_entries_today, fetch_food_month, load_tokens
    has_tokens = load_tokens() is not None
    entries = fetch_food_entries_today() if has_tokens else []
    month = fetch_food_month() if has_tokens else []
    return {"connected": has_tokens, "today": entries, "month": month}


@app.post("/api/health/disconnect/{source}")
async def disconnect_source(source: str):
    key = (source or "").strip().lower()
    if key in {"xiaomi", "mi_fitness", "mi"}:
        from xiaomi_auth import XiaomiTokens

        cleared = XiaomiTokens.clear()
        return {"status": "ok", "source": "xiaomi", "cleared": cleared}
    if key in {"fatsecret", "food"}:
        from fatsecret_client import clear_tokens

        cleared = clear_tokens()
        return {"status": "ok", "source": "fatsecret", "cleared": cleared}
    if key in {"medm", "bp"}:
        from medm_bp import clear_creds

        cleared = clear_creds()
        return {"status": "ok", "source": "medm", "cleared": cleared}
    raise HTTPException(status_code=400, detail="source must be xiaomi|fatsecret|medm")


@app.get("/api/health/xiaomi-devices")
async def xiaomi_devices():
    from xiaomi_auth import XiaomiTokens
    from xiaomi_home import XiaomiHomeClient
    tokens = XiaomiTokens.load()
    if not tokens:
        raise HTTPException(status_code=400, detail="Xiaomi не подключён")
    client = XiaomiHomeClient(tokens, region=os.getenv("XIAOMI_REGION", "ru"))
    await client.connect()
    devices = await client.get_all_devices()
    return {
        "count": len(devices),
        "devices": [
            {"name": d.get("name"), "model": d.get("model"), "did": d.get("did"), "online": d.get("isOnline")}
            for d in devices
        ],
    }


@app.get("/hub")
async def hub_redirect():
    return RedirectResponse(url="/hub/")


def _hub_index_html() -> str:
    path = Path(__file__).resolve().parent / "hub" / "index.html"
    raw = path.read_text(encoding="utf-8")
    version = app.version
    return (
        raw.replace("{{HUB_VERSION}}", version)
        .replace("styles.css?v=ASSET", f"styles.css?v={version}")
        .replace("js/main.js?v=ASSET", f"js/main.js?v={version}")
    )


@app.get("/hub/", response_class=HTMLResponse)
@app.get("/hub/index.html", response_class=HTMLResponse)
async def hub_index():
    return HTMLResponse(_hub_index_html())


@app.post("/api/reset-session")
async def reset_session():
    if cursor_client:
        cursor_client.reset_session()
    return {"status": "ok", "hint": "Сессия Cursor сброшена. Повторите запрос через несколько секунд."}


HUB_DIR = Path(__file__).resolve().parent / "hub"
if HUB_DIR.is_dir():
    app.mount("/hub", StaticFiles(directory=str(HUB_DIR), html=False), name="hub")


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host=host, port=port, reload=True)
