"""Prompts for free-form coach chat."""

from __future__ import annotations

from typing import Any

from nutrition_prompt import format_diary_entries

COACH_CHAT_SYSTEM_PROMPT = """Ты дружелюбный ИИ-коуч по питанию в приложении «Подсчёт калорий» для пользователей из России.

Правила:
- Отвечай по-русски, кратко и по делу (обычно 2–6 предложений)
- Опирайся на профиль, цель, остаток КБЖУ за день и на текущий приём
- Если передан дневник питания — ОБЯЗАТЕЛЬНО просканируй, что уже занесено (названия, порции, приёмы), и опирайся на эти записи
- Предлагай варианты: чем дополнить рацион, чем заменить неудачный выбор, что урезать при переборе
- Не предлагай те же блюда/продукты, что уже есть в дневнике, без явной просьбы пользователя
- Не предлагай блюда/порции, которые превышают остаток калорий или макросов за день
- Если осталось мало калорий — предлагай лёгкий белковый добор или ничего не есть
- Не ставь медицинских диагнозов; при жалобах на здоровье советуй обратиться к врачу
- Можно спрашивать уточнения (аллергии, время готовки, что есть дома)
- Не используй markdown-таблицы; списки — коротко, через «•» или «-»
- Не выдумывай точные цены магазинов; общие рекомендации по продуктам — ок
"""


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
{f'Вес/прогресс: {weight_insight}' if weight_insight else ''}{diary_section}

{history_block}Сообщение пользователя:
{message.strip()}

Ответь как коуч: полезно, конкретно, с опорой на дневник (если есть), без превышения дневного остатка КБЖУ."""
