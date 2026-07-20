# Подпись APK

Чтобы обновление на телефоне ставилось **поверх** предыдущей версии, все release-сборки
должны быть подписаны **одним и тем же** keystore.

## Если установщик пишет «конфликт подписи» / «разные файлы»

На телефоне стоит сборка со **старым** ключом. Один раз:

1. Удалите приложение «Подсчёт калорий»
2. Установите новый APK с Яндекс.Диска / GitHub Release

Дневник на устройстве при удалении сбросится.

## Для сборки (cloud / ПК)

```bash
bash scripts/ensure-signing-keystore.sh
cd mobile && flutter build apk --release
bash android-сборки/scripts/post-build.sh
```

Keystore хранится на Яндекс.Диске: `disk:/podchet_kalloriy/keystore/upload-keystore.jks`  
(не в папке `apk/`). Локально: `mobile/android/keystore/` + `key.properties` (в `.gitignore`).
