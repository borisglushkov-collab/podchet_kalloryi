# Design — Wellness UI (Yazio-стиль)

Отдельная рабочая область для дизайна приложения **Подсчёт калорий**.

**Git-ветка:** `cursor/design-a36d`  
**Исходная ветка дизайна:** `origin/cursor/new-design-apk-a3bf`

## Структура

```
design/
├── README.md
├── worktree.json
├── sync-to-local-d.bat
├── pull-mockups-to-d.bat
├── docs/
│   ├── design-system.md
│   └── mockups/
│       └── profile-health-scale.png
└── source/                    # Зеркало ключевых UI-файлов (эталон для ветки)
    ├── theme/app_theme.dart
    ├── widgets/wellness_widgets.dart
    └── screens/
        ├── main_shell.dart
        ├── diary_screen.dart
        └── analytics_screen.dart
```

## Где живёт «боевой» код

Изменения вносятся в **`mobile/lib/`** — папка `design/source/` — копия для обзора и ветки дизайна.

| Компонент | Путь в приложении |
|-----------|-------------------|
| Тема, цвета, Nunito | `mobile/lib/theme/app_theme.dart` |
| Виджеты (кольца КБЖУ, карточки) | `mobile/lib/widgets/wellness_widgets.dart` |
| Нижняя навигация | `mobile/lib/screens/main_shell.dart` |
| Дневник | `mobile/lib/screens/diary_screen.dart` |
| Аналитика | `mobile/lib/screens/analytics_screen.dart` |
| Профиль | `mobile/lib/screens/profile_screen.dart` |

## Синхронизация на D:

```bat
cd /d D:\ucheba\podchet_kalloriy
git pull origin cursor/design-a36d
design\sync-to-local-d.bat
```

## Макеты

`design\docs\mockups\profile-health-scale.png` — экран профиля с Health Scale.
