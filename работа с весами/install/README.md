# Установка APK — Health Scale

**Последняя версия:** 1.2.4+7  
**Файл:** `podchet_kalloriy-1.2.4-health-scale.apk` (~62 MB)

## Если не скачивается (ERR_CONNECTION_RESET)

GitHub CDN (`release-assets.githubusercontent.com`) часто блокируется. **Используйте один из способов:**

### Способ 1 — из git (рекомендуется, без VPN)

APK лежит в репозитории: `работа с весами/install/podchet_kalloriy-1.2.4-health-scale.apk`

```bat
cd /d D:\ucheba\podchet_kalloriy
git pull origin cursor/chat-podchet-kalloryi-a36d
copy "работа с весами\install\podchet_kalloriy-1.2.4-health-scale.apk" D:\
```

Или запустите **`pull-apk-from-git.bat`** из корня репозитория.

### Способ 2 — скрипт download-apk-to-d.bat

Сначала пробует локальный файл / git pull, потом GitHub.

### Способ 3 — страница Releases в браузере

Откройте (не прямую ссылку на CDN):

https://github.com/borisglushkov-collab/podchet_kalloryi/releases/tag/v1.2.4-health-scale

Скачайте файл вручную. При блокировке — VPN.

### Способ 4 — собрать локально

```bat
build-apk-to-d.bat
```

## Подключение весов (v1.2.4)

1. Закройте **Futula Scale**
2. Разрешите **Bluetooth** и **геолокацию (GPS)**
3. **Встаньте на весы босиком**
4. Профиль → **Найти весы** → выберите **Health Scale** или **CF:E7…**
5. **Взвеситься**
