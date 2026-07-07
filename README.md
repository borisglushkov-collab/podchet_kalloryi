# Podchet Kalloriy

Приложение подсчёта калорий (аналог FatSecret) с ИИ-рекомендациями через Cursor API.

## Структура

- `mobile/` — Flutter Android-приложение
- `backend/` — Python FastAPI сервер (локально на ПК)

## Быстрый старт

### 1. Backend

```bash
cd backend
py -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Отредактируйте `.env` — укажите ваш `CURSOR_API_KEY` из [Cursor Dashboard](https://cursor.com/dashboard/cloud-agents).

```bash
py main.py
```

Сервер запустится на `http://0.0.0.0:8000`.

### 2. Flutter-приложение

Требуется [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
cd mobile
flutter pub get
flutter run
```

### 3. Сборка APK

```bash
cd mobile
flutter build apk --release
```

APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`

### 4. Подключение телефона к backend

**Облако (Timeweb VPS, по умолчанию):**

После `install-vps.sh` backend доступен через nginx на порту **80** (без `:8000` в URL):

- В настройках приложения: `http://5.42.111.122`
- Проверка: `curl http://5.42.111.122/health`

> Порт `:8000` указывайте только при локальном запуске `uvicorn` без nginx.

**Локально (ПК в той же Wi‑Fi):**

1. Узнайте IP вашего ПК в локальной сети (`ipconfig` → IPv4, например `192.168.1.10`)
2. В приложении: Настройки → Адрес сервера → `http://192.168.1.10:8000`
3. Телефон и ПК должны быть в одной Wi‑Fi сети

**Отладка по USB:**
```bash
adb reverse tcp:8000 tcp:8000
```
В настройках приложения: `http://127.0.0.1:8000`

## Функции

- Дневник питания (завтрак, обед, ужин, перекус)
- Расчёт дневной нормы по формуле Миффлина — Сан Жеора
- Поиск продуктов через Calorizator.ru (российская база продуктов)
- ИИ-рекомендации рецептов и продуктов (Cursor Cloud Agents API)
- Ссылки на товары в Перекрёстке

## Безопасность

- **Никогда** не храните `CURSOR_API_KEY` в мобильном приложении
- Ключ только в `backend/.env` (файл в `.gitignore`)

## API

| Endpoint | Описание |
|----------|----------|
| `GET /health` | Проверка доступности |
| `POST /api/suggest-meal` | ИИ-рекомендации для приёма пищи |
| `POST /api/reset-session` | Сброс сессии Cursor-агента |

## Деплой на VPS

См. [backend/DEPLOY-VPS.md](backend/DEPLOY-VPS.md)

```powershell
cd backend
.\deploy\deploy-to-vps.ps1
```
