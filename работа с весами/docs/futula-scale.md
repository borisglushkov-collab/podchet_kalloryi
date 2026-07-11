# Futula Scale → Podchet Kalloriy

> Ваши весы уже настроены в приложении **Futula Scale** (`com.lefu.futula.healthu`, производитель LeFu / Shenzhen Unique Scales).

## Какая у вас модель

| Модель | Для чего | Подходит для Podchet Kalloriy |
|--------|----------|-------------------------------|
| **Futula Kitchen Scale 3** (LeFu CK811 / CK811BLE) | Кухонные, граммы, калории продуктов | ✅ **Да** — основной сценарий |
| Futula Kitchen Scale 5 | Кухонные | ✅ Да (тот же SDK LeFu) |
| Futula Scale 4 / 5 (напольные) | Состав тела, BIA | ❌ Не для взвешивания еды |

Если на весах написано **Kitchen Scale 3** или это компактные кухонные весы с Bluetooth — всё верно.

## Важно: настройка в Futula Scale ≠ подключение в Podchet

Приложение **Futula Scale** и **Podchet Kalloriy** — разные программы. Пара «весы ↔ телефон» в Futula Scale **не переносится** автоматически.

Но это нормально:
- весы можно подключать к другому приложению (закройте Futula Scale или отключите весы там);
- протокол один и тот же — **LeFu PPBluetoothKit**.

## Рекомендуемый путь: официальный SDK LeFu

Futula Scale построено на SDK производителя. Для Podchet Kalloriy (Flutter) используйте тот же стек:

| Компонент | Ссылка |
|-----------|--------|
| Flutter SDK | [pp_bluetooth_kit_flutter](https://github.com/LefuHengqi/pp_bluetooth_kit_flutter) |
| Пример | [pp_bluetooth_kit_demo](https://github.com/LefuHengqi/pp_bluetooth_kit_demo) |
| Документация (кухонные весы) | [Flutter SDK — kitchen scale](https://xinzhiyun.feishu.cn/wiki/EJIdwA9dcimGjvkYE4UcaVrDnpb) |
| Открытая платформа LeFu | [uniquehealth.lefuenergy.com](https://uniquehealth.lefuenergy.com/unique-open-web/#/home) |

### Шаг 1. Получить ключи разработчика

1. Зарегистрироваться на [LeFu Open Platform](https://uniquehealth.lefuenergy.com/unique-open-web/#/home).
2. Заполнить данные компании → получить **AppKey** и **AppSecret**.
3. Скачать файл **`lefu.config`** (обязателен для инициализации SDK).

> Ключи Futula Scale внутри их приложения недоступны — нужны **свои** ключи вашего приложения на платформе LeFu.

### Шаг 2. Подключить SDK в Podchet Kalloriy

`mobile/pubspec.yaml`:

```yaml
dependencies:
  pp_bluetooth_kit_flutter:
    git:
      url: https://github.com/LefuHengqi/pp_bluetooth_kit_flutter.git
```

Инициализация в `main.dart`:

```dart
final content = await rootBundle.loadString('assets/lefu.config');
PPBluetoothKitManager.initSDK(appKey, appSecret, content);
```

Разрешения Android — как в [документации SDK](https://github.com/LefuHengqi/pp_bluetooth_kit_flutter): `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`.

### Шаг 3. Сканирование и вес

Логика из demo-проекта:
1. `scan` → найти устройство (имя часто содержит `CK811`, `LF`, `Futula`).
2. `connect` → подписка на поток веса.
3. Получить **граммы** → записать в поле «Вес (г)» на `AddFoodScreen`.

SDK уже умеет парсить протокол LeFu — **не нужен** ручной разбор байтов через nRF Connect.

## Альтернатива: open-source без SDK

Если не хотите регистрироваться на платформе LeFu:

- [FutulaCoffeeScale](https://github.com/wdrs/FutulaCoffeeScale) — reverse engineering **Kitchen Scale 3** (кофейное приложение, но тот же железо).
- [Kofezavr Scale](https://coffeescaleapp.kofezavr.ru/) — работает с CK811 / CK811BLE.

Можно взять оттуда логику BLE, но поддержка сложнее, чем у официального SDK.

## Как пользоваться сейчас (без доработки приложения)

1. Взвесьте продукт в **Futula Scale** (или на дисплее весов).
2. Посмотрите граммы на экране весов или в Futula Scale.
3. В **Podchet Kalloriy** → «Добавить продукт» → введите вес вручную.

## План внедрения в Podchet Kalloriy

1. [ ] Подтвердить модель: Kitchen Scale 3 / 5 или напольные.
2. [ ] Зарегистрироваться на LeFu Open Platform, получить AppKey + `lefu.config`.
3. [ ] Добавить `pp_bluetooth_kit_flutter` в `работа с весами/mobile/`, протестировать demo.
4. [ ] Кнопка «Подключить Futula» на экране добавления продукта.
5. [ ] Автоподстановка граммов + сохранение `deviceId` в `shared_preferences`.

## Связанные файлы проекта

- `mobile/lib/screens/add_food_screen.dart` — поле «Вес (г)»
- `работа с весами/docs/bluetooth-vesy.md` — общая схема BLE
