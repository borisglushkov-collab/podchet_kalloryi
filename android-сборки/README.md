# Android-сборки

APK, скрипты сборки и загрузка на **Яндекс.Диск**.

**Git-ветка:** `cursor/android-builds-a36d`

## Структура

```
android-сборки/
├── README.md
├── worktree.json
├── install/                         # Готовые APK
│   └── podchet_kalloriy-1.2.5-health-scale.apk
├── scripts/
│   ├── build-apk.bat                # Сборка release APK
│   ├── post-build.sh                # Копирование + Яндекс.Диск
│   ├── upload-yandex-disk.sh
│   └── yandex-disk.env.example
├── build-apk-to-d.bat
├── download-apk-to-d.bat
└── pull-apk-from-git.bat
```

## Сборка + Яндекс.Диск

### 1. Подключить Яндекс.Диск (один раз)

1. Получите OAuth-токен: https://oauth.yandex.ru/authorize?response_type=token&client_id=23cab1bc7b6e431ea8b9f7c0a8c8c8c8  
   (или создайте приложение на https://oauth.yandex.ru/client/new)
2. Скопируйте пример конфига:
   ```bat
   copy android-сборки\scripts\yandex-disk.env.example android-сборки\scripts\yandex-disk.env
   ```
3. Вставьте токен в `yandex-disk.env`:
   ```
   YANDEX_DISK_TOKEN=ваш_токен
   YANDEX_DISK_FOLDER=app:/podchet_kalloriy/apk
   ```

### 2. Сборка

```bat
cd /d D:\ucheba\podchet_kalloriy\mobile
call ..\android-сборки\scripts\build-apk.bat
```

После сборки APK:
- копируется в `android-сборки/install/`
- загружается на Яндекс.Диск (если настроен токен)

### 3. Скачать без GitHub CDN

```bat
android-сборки\pull-apk-from-git.bat
```

## Последняя версия

**1.2.5** — исправлен краш LeFu SDK (ClassCastException).
