# Бриф для отдельного Cloud Agent — Health Data Hub

Скопируйте текст ниже в **новый Cloud Agent** в репозитории `podchet_kalloryi` (ветка `cursor/health-data-hub-985a` или `main`).

---

## Промпт для нового агента

```
Задача: Health Data Hub, Фаза 2 — Health Connect (Android).

Фаза 1 уже в ветке cursor/health-data-hub-985a:
- SQLite blood_pressure_readings, CSV Citizen, экран АД, API /api/health/blood-pressure
- coach health_context (АД)

Сделай Фазу 2 по docs/health-data-hub/PLAN.md и ARCHITECTURE.md:
1. pub package health (или health_connect), разрешения Android 14+
2. Читать шаги и сон из Health Connect (Mi Fitness → HC)
3. Таблицы sleep_sessions / activity_daily уже есть — заполнять их
4. Показать шаги/сон на экране АД или отдельном блоке
5. Передавать sleep_last_night_min и steps_today в health_context коуча
6. Онбординг: «В Mi Fitness включите Health Connect: шаги, сон, пульс»

Не делать: прямой API Xiaomi/Mi Fit, интеграцию Yazio, POST /api/coach-health-chat.

Коммиты на cursor/health-data-hub-985a, PR в main.
```

---

## Как запустить отдельный чат в Cursor Cloud

1. Откройте репозиторий на GitHub / в Cursor
2. **Agents → New Cloud Agent**
3. Выберите репозиторий и ветку `cursor/health-data-hub-985a`
4. Вставьте промпт выше
5. Агент работает автonomously; следите за PR

Текущий коучинг-чат (еда, скрины) можно вести **параллельно** — этот агент только про **код инструмента**.

---

## Связь с ручным коучингом

**Baseline и месячные карточки:** `docs/health-data-hub/coaching/`

- [COACHING_BASELINE.md](./coaching/COACHING_BASELINE.md) — цели, чеклист сверки перед рекомендациями
- [AUGUST_2026_CARD.md](./coaching/AUGUST_2026_CARD.md) — итоги августа, паттерны, цели на сентябрь

Коуч-агент: перед ответами по питанию/весу/АД читай baseline + последнюю карточку месяца.

После MVP кнопка **«Экспорт дня»** генерирует текст:

```
Дата: 2026-08-19
АД утро: 133/90, avg 7d: 136/91
Сон: 6h59
Шаги: 871
Вес: 109.0
Еда: 385 kcal (завтрак: омлет, колбаса, хлеб)
```

Его можно вставлять в любой Cloud Agent без скринов.
