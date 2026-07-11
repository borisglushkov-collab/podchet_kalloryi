# Работа с весами

Подпапка для разработки функций, связанных с весами в приложении **Podchet Kalloriy**:

- ввод веса продукта в граммах при добавлении еды;
- интеграция с кухонными весами (Bluetooth / USB, по мере реализации);
- расчёт КБЖУ по весу порции.

## Локальная папка на диске D

Проект на ПК: **`D:\ucheba\podchet_kalloriy`** (см. `move-result.txt` в корне репозитория).

Макет UI с весами после `git pull`:

```
D:\ucheba\podchet_kalloriy\работа с весами\docs\mockups\profile-health-scale.png
```

### Быстрая синхронизация (Windows)

Из корня репозитория на D:

```bat
pull-mockups-to-d.bat
```

Или только папка «работа с весами»:

```bat
работа с весами\sync-to-local-d.bat
```

Скрипт копирует `docs`, `mockups` и открывает PNG в просмотрщике Windows.

## Доступ с основной ветки

Папка входит в **`main`** и видна всем, кто клонировал репозиторий:

```bash
git checkout main
git pull
ls "работа с весами"
```

Ссылка из корня: [README.md](../README.md#рабочие-области-worktree).

## Cloud worktree этого чата

| Параметр | Значение |
|----------|----------|
| Репозиторий | [borisglushkov-collab/podchet_kalloryi](https://github.com/borisglushkov-collab/podchet_kalloryi) |
| Ветка разработки | `cursor/chat-podchet-kalloryi-a36d` |
| Основная ветка | `main` (папка смержена) |
| Cloud-агент | **Работа с весами** ([bc-d08cfe81](https://cursor.com/agents/bc-d08cfe81-8032-42ce-acd9-ee7f66c9a36d)) |
| Рабочая копия | `/workspace` (cloud worktree) |

**Правило:** весь код, документы и черновики из этого cloud-чата сохраняются в `работа с весами/`, а не в корень репозитория.

## Структура

```
работа с весами/
├── README.md          — этот файл
├── worktree.json      — метаданные cloud-чата
├── docs/              — заметки, планы, исследования
└── mobile/            — код Flutter (экраны, сервисы весов)
```

## Связанный код в основном проекте

- `mobile/lib/screens/add_food_screen.dart` — поле «Вес (г)»
- `mobile/lib/screens/profile_screen.dart` — вес пользователя (кг)
- `mobile/lib/models/models.dart` — модели с `weightKg`, граммы порции
