@echo off
chcp 65001 >nul
setlocal

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "APK_NAME=podchet_kalloriy-1.4.13-24-health-scale.apk"
set "DST=D:\%APK_NAME%"
set "ENV=%PROJECT%\android-сборки\scripts\yandex-disk.env"

if not exist "%ENV%" (
  echo Сначала настройте %ENV%
  call "%PROJECT%\android-сборки\scripts\setup-yandex-disk.bat"
  exit /b 1
)

cd /d "%PROJECT%"
bash android-сборки/scripts/download-yandex-disk.sh "%APK_NAME%" "%DST%"
if exist "%DST%" start "" "%DST%"
pause
