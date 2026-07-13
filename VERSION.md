# Podchet Kalloriy — единая версия 1.4.14

Синхронизировано: **2026-07-13**

| Компонент | Версия | Ветки |
|-----------|--------|-------|
| Mobile APK | 1.4.14+25 | `cursor/food-photo-cursor-a36d` |
| Backend ИИ | v1.2 (develop) | calorizator, top-up suggestions |
| Health Scale | LeFu SDK 1.2.5+ | mobile/lib/services/health_scale/ |
| Design | Wellness UI A | Analytics / Coach / Profile / Weight |
| Android сборки | android-сборки/install/ | + Яндекс.Диск |

## v1.4.14

- Анализ фото еды через **CURSOR_API_KEY** (тот же ключ, что у коуча)
- Fallback: Gemini / OpenAI при `FOOD_VISION_PROVIDER=auto`

## v1.4.13

- Добавление продуктов по **штрихкоду** (Open Food Facts)
- **Анализ фото** еды с оценкой БЖУ и порции (Gemini/OpenAI на сервере)
- Кнопки «Штрихкод» и «Фото» на экране добавления продукта

## v1.4.12

- Вкладка «Вес» — дизайн A (Yazio Wellness Progress): кольцо к цели, честная дельта, мягкая история

## v1.4.11

- Анализ веса для коуча (если было на main)

## v1.4.7

- Коуч: emoji-значки блюд у рецептов

## v1.4.6

- Коуч A + Профиль A
