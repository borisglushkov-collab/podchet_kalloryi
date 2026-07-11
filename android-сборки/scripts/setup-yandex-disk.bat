@echo off
chcp 65001 >nul
setlocal

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "ENV=%PROJECT%\android-сборки\scripts\yandex-disk.env"
set "EXAMPLE=%PROJECT%\android-сборки\scripts\yandex-disk.env.example"

echo === Настройка Яндекс.Диск для сборок ===
echo.

if exist "%ENV%" (
  echo Файл уже есть: %ENV%
  goto :done
)

copy /Y "%EXAMPLE%" "%ENV%"
echo.
echo 1. Откройте в блокноте:
echo    %ENV%
echo 2. Вставьте YANDEX_DISK_TOKEN=...
echo 3. Сохраните и запустите android-сборки\scripts\build-apk.bat
echo.

:done
pause
