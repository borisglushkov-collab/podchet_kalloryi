# Бриф для отдельного Cloud Agent — Health Data Hub

Скопируйте текст ниже в **новый Cloud Agent** в репозитории `podchet_kalloryi` (ветка `cursor/health-data-hub-985a` или `main`).

---

## Промпт для нового агента

```
Задача: реализовать Health Data Hub в приложении Podchet Kalloriy.

Контекст:
- Flutter mobile/ + Python backend/
- Уже есть: дневник еды, coach-chat (/api/coach-chat), весы LeFu BLE
- Нужно: сбор АД, сна, шагов, веса в одном месте для коучинга

Прочитай план:
- docs/health-data-hub/PLAN.md
- docs/health-data-hub/ARCHITECTURE.md
- docs/health-data-hub/schemas/daily_health_snapshot.json

Начни с Фазы 1 (MVP):
1. SQLite таблицы blood_pressure_readings (+ миграция)
2. Парсер CSV Citizen (формат: Дата,Время,Сис,Диа,Пульс,...)
3. Backend endpoints POST/GET blood-pressure
4. Flutter экран списка + импорт CSV + мини-график 7 дней
5. Расширить coach_chat_prompt.py — health_context (АД, сон когда появится)

Пользователь: мужчина 41–42, 165 см, ~109 кг, гипертония Edarbi 80,
рабочие цели: 1900–2100 kcal, Б 120–140, соль/диастол критичны.

Не делать: прямой API Mi Fit/Xiaomi, интеграцию Yazio.

После Фазы 1 — Health Connect на Android (шаги, сон из Mi Fitness).

Коммиты на ветку cursor/health-data-hub-985a, PR в main.
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
