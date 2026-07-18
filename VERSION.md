# Podchet Kalloriy — единая версия 1.4.23

> Источник правды: файл [`VERSION`](VERSION). После правки запускайте `bash scripts/sync-version.sh`.

Синхронизировано: **2026-07-18**

| Компонент | Версия | Где используется |
|-----------|--------|------------------|
| Mobile APK | 1.4.23+34 | `mobile/pubspec.yaml` |
| Backend API | 1.4.23 | `backend/VERSION` → FastAPI `version` |
| Backend deploy tag | `v1.4.23-backend` | `backend/deploy/update-from-github.sh` / GitHub Release |

## v1.4.23

- Чат коуча: поле ввода больше не перекрывает ответ
- ИИ-поиск / чат: fallback при таймауте Cursor
- Единый источник версии: корневой `VERSION` + `scripts/sync-version.sh`

## v1.4.22

- Backend: offline fallback чата, таймауты Cursor
- Mobile: понятные ошибки ИИ-поиска

## v1.4.21

- Сборка для телефона после merge коуча: дневной лимит, чат, ИИ-поиск
- Все ветки синхронизированы на tip `main`

## v1.4.20

- Клиентский лимит коуча при старом backend
- Понятная ошибка Not Found / shared Cursor client для ИИ-поиска

## v1.4.19

- Коуч: цель рецепта ограничена дневным остатком КБЖУ
- Чат с коучем
- ИИ-поиск продукта
