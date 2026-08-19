# Health Data Hub

Инструмент сбора данных здоровья для **Podchet Kalloriy** и AI-коуча.

| Документ | Назначение |
|----------|------------|
| [PLAN.md](./PLAN.md) | Roadmap по фазам, MVP, критерии готовности |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Схема, SQLite, API, Health Connect |
| [CLOUD_AGENT_BRIEF.md](./CLOUD_AGENT_BRIEF.md) | Промпт для **отдельного Cloud Agent** |
| [schemas/daily_health_snapshot.json](./schemas/daily_health_snapshot.json) | JSON-схема дневного снимка |

## Быстрый старт для разработки

```bash
git checkout cursor/health-data-hub-985a
# читать PLAN.md → Фаза 1
```

## Быстрый старт для коучинга (пока нет приложения)

Экспорт CSV давления из приложения Citizen → прислать агенту или положить в `uploads/`.
