# Podchet Kalloriy

Приложение подсчёта калорий (аналог FatSecret) с ИИ-рекомендациями через Cursor API.

## Структура

```
podchet_kalloryi/
├── mobile/                 # Flutter-приложение
├── backend/                # FastAPI сервер
├── design/                 # UI/UX, макеты (ветка cursor/design-a36d)
├── android-сборки/         # APK, сборка, Яндекс.Диск (ветка cursor/android-builds-a36d)
└── работа с весами/        # Bluetooth Health Scale, документация по весам
```

- `mobile/` — Flutter Android-приложение
- `backend/` — Python FastAPI сервер (локально на ПК)

## Рабочие области (worktree)

| Папка | Ветка | Назначение |
|-------|-------|------------|
| [`design/`](design/) | `cursor/design-a36d` | Wellness UI (Yazio), макеты, design-system |
| [`android-сборки/`](android-сборки/) | `cursor/android-builds-a36d` | APK, скрипты сборки, загрузка на Яндекс.Диск |
| [`работа с весами/`](работа%20с%20весами/) | `cursor/chat-podchet-kalloryi-a36d` | Health Scale, Futula, BLE-документация |

## Сборка APK + Яндекс.Диск

```bat
android-сборки\scripts\build-apk.bat
```

Настройка токена: `android-сборки\scripts\yandex-disk.env.example` → `yandex-disk.env`

Скачать APK без GitHub CDN: `android-сборки\pull-apk-from-git.bat`


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

В настройках приложения: `http://5.42.111.122`

Проверка: `curl http://5.42.111.122/health`

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
- Поиск продуктов через Open Food Facts
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
