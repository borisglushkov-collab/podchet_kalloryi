# Health Data Hub

Отдельное приложение **«Сбор для коуча»**: вы складываете день (АД, сон, шаги, вес, еда) и одной кнопкой отдаёте коучу.

Это не экран внутри «Подсчёта калорий». Открывается по адресу:

```
http://201.51.22.29/hub/
```

На Android: Chrome → «Добавить на главный экран».

| Документ | Назначение |
|----------|------------|
| [PLAN.md](./PLAN.md) | Roadmap по фазам |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | SQLite, API, Health Connect |
| [CLOUD_AGENT_BRIEF.md](./CLOUD_AGENT_BRIEF.md) | Промпт для следующей фазы |
| [fixtures/citizen-sample.csv](./fixtures/citizen-sample.csv) | Пример CSV Citizen |

## Как пользоваться

1. Откройте `/hub/`
2. Вкладка **Добавить**: АД, сон (минуты), шаги, вес, еда
3. **Ещё**: импорт CSV из Citizen
4. Вкладка **Коучу**: «Скопировать этот текст» или «Передать коучу»

Коуч получает снимок дня, без скриншотов из четырёх приложений.

## Код

- UI: `backend/hub/`
- API: `POST /api/health/sync`, `GET /api/health/day/{date}`, `POST /api/coach-health-chat`
