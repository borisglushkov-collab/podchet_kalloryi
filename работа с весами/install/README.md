# Установка APK — Health Scale

**Последняя версия:** 1.2.2+5  
**Файл:** `podchet_kalloriy-1.2.2-health-scale.apk` (~59 MB)

## Что нового в 1.2.2

- Кнопка **«Найти весы»** — сканирование BLE и выбор устройства из списка
- Поиск по имени **Health Scale**, не только по MAC
- Повторное подключение без лишнего сканирования, если весы уже найдены
- Подсказки при ошибках (закрыть Futula Scale, разрешения Bluetooth)

## Скачать на Windows (D:)

```bat
download-apk-to-d.bat
```

Или вручную:  
https://github.com/borisglushkov-collab/podchet_kalloryi/releases/download/v1.2.2-health-scale/podchet_kalloriy-1.2.2-health-scale.apk

## Установка на Android

1. Включите **Установка из неизвестных источников**.
2. Установите APK (USB + ADB или файл на телефоне):
   ```bat
   adb install -r D:\podchet_kalloriy-1.2.2-health-scale.apk
   ```

## Подключение весов

1. **Закройте приложение Futula Scale** (оно держит Bluetooth).
2. Включите Bluetooth и геолокацию, разрешите доступ для «Подсчёт калорий».
3. Откройте **Профиль** → блок **Health Scale**.
4. Нажмите **«Найти весы»** → выберите **Health Scale** (MAC `CF:E7:02:17:03:93`).
5. Нажмите **«Взвеситься»** и встаньте на платформу босиком.
