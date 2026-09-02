"""Prompts for free-form coach chat."""

from __future__ import annotations

from typing import Any

from nutrition_prompt import format_diary_entries

COACH_CHAT_SYSTEM_PROMPT = """Ты дружелюбный ИИ-коуч по питанию в приложении «Подсчёт калорий» для пользователей из России.

Правила:
- Отвечай по-русски, кратко и по делу (обычно 2–6 предложений)
- Опирайся на профиль, цель, остаток КБЖУ за день и на текущий приём
- Если передан дневник питания — ОБЯЗАТЕЛЬНО просканируй, что уже занесено (названия, порции, приёмы), и опирайся на эти записи
- Если передан блок «Здоровье» — учитывай давление, сон, шаги, вес и лекарства
- При гипертонии (лекарства вроде Edarbi) осторожнее с солью, колбасами, очень жирным и алкоголем
- Не ставь медицинских диагнозов и не меняй дозировки лекарств; при стабильном АД ≥140/90 советуй обратиться к врачу
- Рабочие цели калорий из блока здоровья важнее целей сторонних приложений (например Yazio)
- Предлагай варианты: чем дополнить рацион, чем заменить неудачный выбор, что урезать при переборе
- Не предлагай те же блюда/продукты, что уже есть в дневнике, без явной просьбы пользователя
- Не предлагай блюда/порции, которые превышают остаток калорий или макросов за день
- Если осталось мало калорий — предлагай лёгкий белковый добор или ничего не есть
- Можно спрашивать уточнения (аллергии, время готовки, что есть дома)
- Не используй markdown-таблицы; списки — коротко, через «•» или «-»
- Не выдумывай точные цены магазинов; общие рекомендации по продуктам — ок
"""


def _format_health_context(health: dict[str, Any] | None) -> str:
    if not health:
        return ""
    lines: list[str] = []
    latest = health.get("blood_pressure_latest") or {}
    if latest.get("systolic") and latest.get("diastolic"):
        pulse = latest.get("pulse")
        pulse_s = f", пульс {pulse}" if pulse else ""
        at = latest.get("at") or latest.get("measured_at") or ""
        at_s = f" ({at})" if at else ""
        lines.append(
            f"- АД последнее: {latest['systolic']}/{latest['diastolic']}{pulse_s}{at_s}"
        )
    avg = health.get("blood_pressure_avg_7d") or {}
    if avg.get("systolic") and avg.get("diastolic"):
        lines.append(f"- АД среднее 7 дней: {avg['systolic']}/{avg['diastolic']}")
    sleep_min = health.get("sleep_last_night_min")
    if sleep_min:
        hours, mins = divmod(int(sleep_min), 60)
        lines.append(f"- Сон: {hours}ч {mins:02d}мин")
    steps = health.get("steps_today")
    if steps is not None:
        lines.append(f"- Шаги сегодня: {steps}")
    weight = health.get("weight_latest_kg")
    if weight is not None:
        lines.append(f"- Вес: {weight} кг")
    meds = [str(m) for m in (health.get("medications") or []) if str(m).strip()]
    if meds:
        lines.append(f"- Лекарства: {', '.join(meds)}")
    targets = health.get("coaching_targets") or {}
    if targets.get("kcal_min") or targets.get("kcal_max"):
        kcal = f"{targets.get('kcal_min', '?')}–{targets.get('kcal_max', '?')} ккал"
        protein = targets.get("protein_g")
        protein_s = f", Б {protein}" if protein else ""
        lines.append(f"- Рабочие цели коуча: {kcal}{protein_s} (не цель Yazio)")
    if not lines:
        return ""
    return "Здоровье:\n" + "\n".join(lines)


def build_coach_chat_prompt(
    message: str,
    *,
    history: list[dict[str, str]] | None = None,
    meal_type: str | None = None,
    consumed: dict[str, float] | None = None,
    targets: dict[str, float] | None = None,
    daily_deficit: dict[str, float] | None = None,
    meal_deficit: dict[str, float] | None = None,
    preferences: list[str] | None = None,
    profile_context: dict[str, Any] | None = None,
    weight_insight: str = "",
    diary_entries: list[dict[str, Any]] | None = None,
    health_context: dict[str, Any] | None = None,
) -> str:
    meal_names = {
        "breakfast": "завтрак",
        "lunch": "обед",
        "dinner": "ужин",
        "snack": "перекус",
    }
    meal_ru = meal_names.get(meal_type or "", meal_type or "не выбран")
    prefs = ", ".join(preferences or []) if preferences else "нет"
    consumed = consumed or {}
    targets = targets or {}
    daily_deficit = daily_deficit or {}
    meal_deficit = meal_deficit or {}

    profile_lines = []
    if profile_context:
        gender = {"male": "мужчина", "female": "женщина"}.get(
            str(profile_context.get("gender", "")), str(profile_context.get("gender", ""))
        )
        goal = {
            "lose": "похудение",
            "maintain": "поддержание",
            "gain": "набор",
        }.get(str(profile_context.get("goal", "")), str(profile_context.get("goal", "")))
        profile_lines.append(
            f"- {gender}, {profile_context.get('age', '?')} лет, "
            f"{profile_context.get('height_cm', '?')} см, "
            f"{profile_context.get('weight_kg', '?')} кг"
        )
        profile_lines.append(f"- активность: {profile_context.get('activity', '?')}, цель: {goal}")
        if profile_context.get("target_weight_kg") is not None:
            profile_lines.append(f"- целевой вес: {profile_context['target_weight_kg']} кг")

    history_block = ""
    if history:
        lines = []
        for item in history[-12:]:
            role = "Пользователь" if item.get("role") == "user" else "Коуч"
            text = (item.get("content") or "").strip()
            if text:
                lines.append(f"{role}: {text}")
        if lines:
            history_block = "История диалога:\n" + "\n".join(lines) + "\n\n"

    diary_block = format_diary_entries(diary_entries)
    diary_section = f"\n{diary_block.strip()}\n" if diary_block.strip() else ""
    health_section = _format_health_context(health_context)
    health_block = f"\n{health_section}\n" if health_section else ""

    return f"""Контекст дня:
- Текущий приём: {meal_ru}
- Съедено за день: {consumed.get('calories', 0):.0f}/{targets.get('calories', 0):.0f} ккал · \
Б {consumed.get('protein', 0):.0f}/{targets.get('protein', 0):.0f} · \
Ж {consumed.get('fat', 0):.0f}/{targets.get('fat', 0):.0f} · \
У {consumed.get('carbs', 0):.0f}/{targets.get('carbs', 0):.0f}
- Осталось за день: {daily_deficit.get('calories', 0):.0f} ккал · \
Б {daily_deficit.get('protein', 0):.0f} · \
Ж {daily_deficit.get('fat', 0):.0f} · \
У {daily_deficit.get('carbs', 0):.0f}
- Целевой остаток на приём (уже с дневным лимитом): {meal_deficit.get('calories', 0):.0f} ккал · \
Б {meal_deficit.get('protein', 0):.0f} · \
Ж {meal_deficit.get('fat', 0):.0f} · \
У {meal_deficit.get('carbs', 0):.0f}
- Предпочтения: {prefs}
{chr(10).join(['Профиль:'] + profile_lines) if profile_lines else ''}
{f'Вес/прогресс: {weight_insight}' if weight_insight else ''}{health_block}{diary_section}

{history_block}Сообщение пользователя:
{message.strip()}

Ответь как коуч: полезно, конкретно, с опорой на дневник (если есть), без превышения дневного остатка КБЖУ."""
