# Установка APK v1.1.0 — Futula Health Scale

Версия: **1.1.0+2**  
Файл: `podchet_kalloriy-1.1.0-health-scale.apk` (~60 MB)

## Что нового

- Синхронизация **Futula Health Scale** (MAC `CF:E7:02:17:03:93`) в профиль
- Карточка «Futula Health Scale» на экране **Профиль**
- SDK LeFu для Bluetooth-весов

## Сборка на Windows (D:)

```bat
cd /d D:\ucheba\podchet_kalloriy
build-apk-to-d.bat
```

APK появится:

- `D:\podchet_kalloriy-1.1.0-health-scale.apk`
- `D:\ucheba\podchet_kalloriy\работа с весами\install\podchet_kalloriy-1.1.0-health-scale.apk`

## Установка на Android

1. Включите **Установка из неизвестных источников** для файлового менеджера.
2. Скопируйте APK на телефон или подключите USB.
3. Через ADB:
   ```bat
   adb install -r D:\podchet_kalloriy-1.1.0-health-scale.apk
   ```
4. Либо откройте APK на телефоне и установите вручную.

## После установки

Профиль → **Futula Health Scale** → **Синхр. вес** (закройте Futula Scale перед подключением).
