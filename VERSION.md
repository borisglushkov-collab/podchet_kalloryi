# Podchet Kalloriy — единая версия 1.4.15

Синхронизировано: **2026-07-13**

| Компонент | Версия | Ветки |
|-----------|--------|-------|
| Mobile APK | 1.4.15+26 | `cursor/fix-nav-safearea-a3bf` |
| Backend ИИ | v1.2 (develop) | calorizator, top-up suggestions |
| Health Scale | LeFu SDK 1.2.5+ | mobile/lib/services/health_scale/ |
| Design | Wellness UI A | Analytics / Coach / Profile / Weight |
| Android сборки | android-сборки/install/ | + Яндекс.Диск |

## v1.4.15

- Фикс: нижнее меню больше не наезжает на системные кнопки Android (Назад / Домой / Недавние)

## v1.4.14

- Анализ фото еды через **CURSOR_API_KEY** (тот же ключ, что у коуча)
- Fallback: Gemini / OpenAI при `FOOD_VISION_PROVIDER=auto`

## v1.4.13

- Добавление продуктов по **штрихкоду** (Open Food Facts)
- **Анализ фото** еды с оценкой БЖУ и порции (Gemini/OpenAI на сервере)

## v1.4.12

- Вкладка «Вес» — дизайн A (Yazio Wellness Progress)
