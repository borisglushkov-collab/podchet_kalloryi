@echo off
chcp 65001 >nul
setlocal

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "APK_NAME=podchet_kalloriy-1.2.4-health-scale.apk"
set "APK_SRC=%PROJECT%\работа с весами\install\%APK_NAME%"
set "APK_DST=D:\%APK_NAME%"
set "BRANCH=cursor/chat-podchet-kalloryi-a36d"

echo.
echo === Копирование APK из git-репозитория ===
echo.

if not exist "%PROJECT%\.git" (
  echo [ОШИБКА] Репозиторий не найден: %PROJECT%
  pause
  exit /b 1
)

cd /d "%PROJECT%"
echo git pull origin %BRANCH% ...
git fetch origin %BRANCH%
git checkout %BRANCH%
git pull origin %BRANCH%

if not exist "%APK_SRC%" (
  echo [ОШИБКА] APK не найден: %APK_SRC%
  echo Выполните git pull или используйте download-apk-to-d.bat с VPN.
  pause
  exit /b 1
)

copy /Y "%APK_SRC%" "%APK_DST%"
echo.
echo Готово: %APK_DST%
echo.
start "" "%APK_DST%"
pause
