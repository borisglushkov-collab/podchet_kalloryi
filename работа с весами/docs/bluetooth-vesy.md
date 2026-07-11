# Подключение Bluetooth-весов к Podchet Kalloriy

> Статус: **не реализовано** в основном приложении. Экран `add_food_screen.dart` принимает вес только вручную.

## 1. Какой тип весов у вас

| Тип | Пример | Сложность |
|-----|--------|-----------|
| Дешёвые кухонные BLE | Many no-name на AliExpress | Средняя — часто один и тот же чип, но UUID различаются |
| Брендовые «умные» | Xiaomi, Renpho, Withings | Высокая — закрытый протокол, нужен reverse engineering |
| USB / проводные | — | Не для телефона |
| Только через своё приложение | Etekcity, Greater Goods | Обычно нельзя без их SDK |
| **Futula Scale (LeFu)** | Kitchen Scale 3 (CK811BLE) | ✅ Официальный SDK — см. [futula-scale.md](futula-scale.md) |

**Если весы настроены в Futula Scale:** см. подробную инструкцию → **[futula-scale.md](futula-scale.md)**.

**Первый шаг (для прочих моделей):** узнайте модель весов и проверьте, видны ли они в приложении **nRF Connect** (Android) как BLE-устройство с характеристикой, куда приходит вес.

## 2. Общая схема в приложении

```
[Bluetooth-весы] --BLE notify--> [ScaleBleService] --> [grams] --> AddFoodScreen
                                      ↑
                              flutter_blue_plus
```

1. Пользователь нажимает «Подключить весы» на экране добавления продукта.
2. Приложение сканирует BLE, показывает список (или подключается к сохранённым).
3. Подписка на notify-характеристику → парсинг байтов/строки → граммы.
4. Поле «Вес (г)» обновляется автоматически; пользователь нажимает «Добавить».

## 3. Зависимости (Flutter)

В `mobile/pubspec.yaml`:

```yaml
dependencies:
  flutter_blue_plus: ^1.35.0
  permission_handler: ^11.3.1
```

## 4. Разрешения Android

В `AndroidManifest.xml` (Android 12+):

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
```

На Android 6–11 для сканирования часто нужен `ACCESS_FINE_LOCATION` — особенность платформы.

## 5. Минимальный сервис (черновик)

Файл: `работа с весами/mobile/scale_ble_service.dart` (потом перенести в `mobile/lib/services/`).

```dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ScaleBleService {
  BluetoothDevice? _device;
  StreamSubscription? _sub;
  final _weightController = StreamController<double>.broadcast();
  Stream<double> get weights => _weightController.stream;

  Future<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    final results = <ScanResult>[];
    await FlutterBluePlus.startScan(timeout: timeout);
    await for (final batch in FlutterBluePlus.scanResults) {
      results.addAll(batch);
    }
    return results;
  }

  Future<void> connect(BluetoothDevice device) async {
    await _sub?.cancel();
    _device = device;
    await device.connect(autoConnect: false);
    final services = await device.discoverServices();
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.properties.notify) {
          await c.setNotifyValue(true);
          _sub = c.onValueReceived.listen(_parseWeight);
        }
      }
    }
  }

  void _parseWeight(List<int> data) {
    // Зависит от модели! Пример для ASCII "123.4g":
    final text = String.fromCharCodes(data).trim();
    final match = RegExp(r'([\d.]+)').firstMatch(text);
    if (match != null) {
      final g = double.tryParse(match.group(1)!);
      if (g != null && g > 0) _weightController.add(g);
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _device?.disconnect();
    await _weightController.close();
  }
}
```

**Важно:** `_parseWeight` нужно подстроить под **ваши** весы после просмотра данных в nRF Connect.

## 6. Как узнать протокол своих весов

1. Установите **nRF Connect for Mobile**.
2. Включите весы, положите продукт, нажмите «Scan».
3. Подключитесь к устройству → **Services** → найдите характеристику с **Notify**.
4. Смотрите сырые байты при изменении веса.
5. Запишите Service UUID, Characteristic UUID и формат (часто 4–6 байт: старший/младший байт, единицы 0.1 г).

Типичные UUID у китайских кухонных весов (не гарантия):

- `0000fff0-0000-1000-8000-00805f9b34fb`
- `0000ffb0-0000-1000-8000-00805f9b34fb`

## 7. UI на экране добавления продукта

Рядом с полем «Вес (г)»:

- кнопка **Bluetooth** → диалог выбора устройства;
- индикатор «Подключено: Kitchen Scale»;
- live-обновление `_gramsController`;
- кнопка «Зафиксировать» (если вес «прыгает»).

## 8. Ограничения

- **iOS** — нужен `Info.plist` с `NSBluetoothAlwaysUsageDescription`; App Store строже к BLE.
- Весы должны быть **не привязаны** только к другому приложению (некоторые блокируют второе подключение).
- **Тара (TARE)** на весах — локальная функция весов; приложение получает уже «чистый» вес.
- Без модели весов универсальный парсер **не существует**.

## 9. План внедрения в проект

1. [ ] Определить модель весов + дамп nRF Connect.
2. [ ] Добавить `flutter_blue_plus` и разрешения.
3. [ ] Реализовать `ScaleBleService` с парсером под модель.
4. [ ] Экран/диалог подключения в `AddFoodScreen`.
5. [ ] Сохранение `deviceId` в `shared_preferences` для автоподключения.
6. [ ] Тест на реальном телефоне (эмулятор BLE не подходит).

## 10. Альтернатива без BLE в коде

Если весы **не отдают BLE** (только своё приложение):

- ввод вручную (как сейчас);
- или весы с **NFC/QR** (редко);
- или покупка BLE-весов с известным протоколом / open-source проектом (например, весы на ESP32 с прошивкой под openScale).
