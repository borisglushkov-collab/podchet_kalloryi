@echo off
chcp 65001 >nul
setlocal

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "APK_NAME=podchet_kalloriy-1.4.6-17-health-scale.apk"
set "APK_SRC=%PROJECT%\android-сборки\install\%APK_NAME%"
set "APK_DST=D:\%APK_NAME%"
set "BRANCH=cursor/chat-podchet-kalloryi-a36d"

echo === APK из git (ветка android-builds) ===
cd /d "%PROJECT%"
git fetch origin %BRANCH%
git pull origin %BRANCH%

if not exist "%APK_SRC%" (
  echo APK не найден: %APK_SRC%
  pause
  exit /b 1
)

copy /Y "%APK_SRC%" "%APK_DST%"
echo Готово: %APK_DST%
start "" "%APK_DST%"
pause
