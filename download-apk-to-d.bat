@echo off
chcp 65001 >nul
setlocal

set "URL=https://github.com/borisglushkov-collab/podchet_kalloryi/releases/download/v1.2.1-health-scale/podchet_kalloriy-1.2.1-health-scale.apk"
set "DST=D:\podchet_kalloriy-1.2.1-health-scale.apk"
set "INSTALL_DIR=D:\ucheba\podchet_kalloriy\работа с весами\install"

echo Скачивание APK...
curl -fsSL -o "%DST%" "%URL%"
if errorlevel 1 (
  echo curl не найден, пробую PowerShell...
  powershell -NoProfile -Command "Invoke-WebRequest -Uri '%URL%' -OutFile '%DST%'"
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%DST%" "%INSTALL_DIR%\podchet_kalloriy-1.2.1-health-scale.apk"

echo.
echo Готово:
echo   %DST%
echo   %INSTALL_DIR%\podchet_kalloriy-1.1.0-health-scale.apk
echo.
start "" "%DST%"
pause
