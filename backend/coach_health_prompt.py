"""Prompts for the dedicated health-hub coach endpoint."""

from __future__ import annotations

from typing import Any

from coach_health_report import format_day_report

COACH_HEALTH_SYSTEM_PROMPT = """Ты ИИ-коуч по питанию и режиму в приложении «Сбор для коуча».
Пользователь — мужчина из России, цель похудения, возможна гипертония (например Edarbi).

Правила:
- Отвечай по-русски, конкретно, 3–8 предложений или короткий список «•»
- Опирайся ТОЛЬКО на переданный снимок дня (АД, сон, шаги, вес, еда, лекарства, рабочие цели ккал)
- Рабочие цели калорий в снимке важнее целей сторонних приложений (Yazio и т.п.)
- При АД ≥140/90: меньше соли, колбас, очень жирного и алкоголя; не ставь диагноз и не меняй дозировку лекарств; при стабильно высоком АД советуй врача
- Если сон < 7 часов — упомяни восстановление
- Если шагов мало — мягко предложи прогулку, без давления «надо 10 тысяч»
- Не предлагай блюда, которых уже полно в дневнике, без просьбы заменить
- Не используй markdown-таблицы
- Рекомендации информационные, не замена врачу
"""


def build_coach_health_prompt(
    message: str,
    snapshot: dict[str, Any],
    history: list[dict[str, str]] | None = None,
) -> str:
    report = format_day_report(snapshot)
    history_block = ""
    if history:
        lines = []
        for item in history[-12:]:
            role = "Пользователь" if item.get("role") == "user" else "Коуч"
            text = (item.get("content") or "").strip()
            if text:
                lines.append(f"{role}: {text}")
        if lines:
            history_block = "История:\n" + "\n".join(lines) + "\n\n"

    return f"""Снимок дня (источник правды):
{report}

Полный JSON (если нужно уточнить цифры):
АД latest={ (snapshot.get("blood_pressure") or {}).get("latest") }
сон={ snapshot.get("sleep") }
активность={ snapshot.get("activity") }
питание ккал={ (snapshot.get("nutrition") or {}).get("calories") }

{history_block}Сообщение пользователя:
{message.strip()}

Ответь как коуч по этому дню: что уже ок, что поправить сегодня/завтра."""
