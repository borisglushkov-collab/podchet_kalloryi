# Health Data Hub — архитектура

## Общая схема

```
┌─────────────────────────────────────────────────────────────────┐
│                        MOBILE (Flutter)                          │
├──────────────┬──────────────┬──────────────┬────────────────────┤
│ Food Diary   │ Health       │ BLE Scales   │ Health Connect     │
│ (SQLite)     │ Manual/CSV   │ LeFu SDK     │ Reader (Android)   │
└──────┬───────┴──────┬───────┴──────┬───────┴─────────┬──────────┘
       │              │              │                 │
       └──────────────┴──────────────┴─────────────────┘
                              │
                    HealthRepository (local)
                              │
              ┌───────────────┴───────────────┐
              │     DailyHealthSnapshot       │
              │  (aggregate per calendar day) │
              └───────────────┬───────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
   HealthDayScreen      CoachChatScreen     POST /api/health/sync
   (dashboard)          (+ health_context)   (optional backup)
```

## Слои mobile

| Слой | Путь (план) | Ответственность |
|------|-------------|-----------------|
| UI | `lib/screens/health_day_screen.dart` | Дашборд дня |
| UI | `lib/screens/blood_pressure_screen.dart` | АД, график, импорт |
| Service | `lib/services/health_connect_reader.dart` | Чтение HC (Android) |
| Service | `lib/services/blood_pressure_csv_import.dart` | Парсинг Citizen CSV |
| Repository | `lib/services/health_repository.dart` | CRUD + агрегация |
| DB | `lib/db/database.dart` | Миграции v2+ |

## Таблицы SQLite (новые)

```sql
-- blood_pressure_readings
CREATE TABLE blood_pressure_readings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  measured_at TEXT NOT NULL,  -- ISO8601 local
  systolic INTEGER NOT NULL,
  diastolic INTEGER NOT NULL,
  pulse INTEGER,
  source TEXT DEFAULT 'manual',  -- manual | csv | device
  note TEXT,
  UNIQUE(measured_at, systolic, diastolic)
);

-- sleep_sessions (from Health Connect or manual)
CREATE TABLE sleep_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,           -- YYYY-MM-DD (wake date)
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  duration_min INTEGER NOT NULL,
  quality_label TEXT,           -- poor | ok | good
  source TEXT DEFAULT 'health_connect'
);

-- activity_daily
CREATE TABLE activity_daily (
  date TEXT PRIMARY KEY,
  steps INTEGER,
  active_minutes INTEGER,
  calories_burned REAL,
  synced_at TEXT
);

-- body_composition (optional, from smart scale)
CREATE TABLE body_composition (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  measured_at TEXT NOT NULL,
  weight_kg REAL NOT NULL,
  body_fat_pct REAL,
  visceral_fat REAL,
  muscle_kg REAL,
  bmr_kcal INTEGER,
  source TEXT
);
```

## Backend API (новые endpoints)

```
POST   /api/health/blood-pressure
POST   /api/health/blood-pressure/import-csv
GET    /api/health/blood-pressure?from=&to=
GET    /api/health/summary?date=YYYY-MM-DD

POST   /api/health/sync          # bulk DailyHealthSnapshot (backup)
GET    /api/health/day/{date}     # merged snapshot

POST   /api/coach-health-chat     # фаза 5: полный контекст здоровья
```

Расширение существующего `CoachChatRequest`:

```python
class HealthContext(BaseModel):
    blood_pressure_latest: dict | None = None   # {systolic, diastolic, pulse, at}
    blood_pressure_avg_7d: dict | None = None
    sleep_last_night_min: int | None = None
    steps_today: int | None = None
    weight_latest_kg: float | None = None
    medications: list[str] = []                   # ["Edarbi 80"]
    coaching_targets: dict | None = None          # рабочие 1900-2100, не Yazio 2402
```

### Альтернатива для MVP коучинга: читать snapshot напрямую из hub

Так как внешний `hub` уже умеет хранить/агрегировать параметры за день, backend Podchet Kalloriy может:
1) сделать `GET http://201.51.22.29/api/health/day/{date}`
2) взять `snapshot` + (опционально) `report`
3) встроить “здоровье” в промпт коуча (в `weight_insight` / отдельный блок)

Это уменьшает объём работ в MVP: меньше зависимостей от Citizen CSV / Health Connect, если hub уже подключён к источникам.

## Health Connect — настройка Mi Fitness

Пользователь (Android):

1. Установить **Health Connect** (Google Play), если нет
2. **Mi Fitness** → Профиль → Подключённые приложения / Health Connect
3. Включить: **Шаги**, **Сон**, **Пульс**, **SpO₂** (что доступно)
4. В Podchet: Настройки → Разрешения Health Connect → синхронизация

Код (план):

```yaml
# pubspec.yaml
dependencies:
  health: ^11.0.0   # или health_connect — проверить совместимость SDK 3.2
```

```dart
// health_connect_reader.dart — псевдокод
Future<ActivityDaily> fetchToday() async {
  final types = [HealthDataType.STEPS, HealthDataType.SLEEP_ASLEEP, ...];
  final granted = await health.requestAuthorization(types);
  // read intervals for today 00:00 - now
}
```

## Агрегация дня

`HealthRepository.buildDailySnapshot(String date)`:

1. `food_entries` → totals (existing NutritionCalculator)
2. `blood_pressure_readings` → latest + avg for date / rolling 7d
3. `sleep_sessions` where wake `date` matches
4. `activity_daily` for `date`
5. `weight_entries` / `body_composition` → latest on or before date

Output: JSON по схеме `schemas/daily_health_snapshot.json`.

## Безопасность

- Данные здоровья **только локально** + опциональный sync на свой VPS
- Не отправлять в third-party без согласия
- `.env` на backend — без PII в логах
- CSV импорт — валидация, без выполнения произвольного кода

## Порядок PR

1. `docs/health-data-hub/*` + schema (этот PR)
2. DB migration + blood pressure CRUD + CSV
3. Health Connect reader + activity/sleep
4. Health day screen + coach prompt extension
5. coach-health-chat endpoint
