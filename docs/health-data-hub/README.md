# Health Data Hub

Инструмент сбора данных здоровья для **Podchet Kalloriy** и AI-коуча.

| Документ | Назначение |
|----------|------------|
| [PLAN.md](./PLAN.md) | Roadmap по фазам, MVP, критерии готовности |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Схема, SQLite, API, Health Connect |
| [CLOUD_AGENT_BRIEF.md](./CLOUD_AGENT_BRIEF.md) | Промпт для **следующего Cloud Agent** (Фаза 2) |
| [schemas/daily_health_snapshot.json](./schemas/daily_health_snapshot.json) | JSON-схема дневного снимка |
| [fixtures/citizen-sample.csv](./fixtures/citizen-sample.csv) | Пример CSV Citizen |

## Фаза 1 (готово)

- Экран **Аналитика → АД** и **Профиль → Давление**
- Импорт CSV Citizen (`Дата,Время,Сис,Диа,Пульс`)
- API: `POST/GET /api/health/blood-pressure`, `POST .../import-csv`, `GET .../summary`
- Чат коуча получает `health_context` (последнее АД и среднее за 7 дней)

## Быстрый старт для разработки

```bash
git checkout cursor/health-data-hub-985a
# Фаза 2: Health Connect (шаги, сон)
```