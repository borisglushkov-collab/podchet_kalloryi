@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "APK_NAME=podchet_kalloriy-1.4.16-27-health-scale.apk"
set "LOCAL_APK=%PROJECT%\android-сборки\install\%APK_NAME%"
set "DST=D:\%APK_NAME%"
set "INSTALL_DIR=%PROJECT%\android-сборки\install"
set "BRANCH=cursor/chat-podchet-kalloryi-a36d"
set "URL=https://github.com/borisglushkov-collab/podchet_kalloryi/raw/cursor/chat-podchet-kalloryi-a36d/android-%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B8/install/%APK_NAME%"

echo.
echo === Установка APK v1.4.16 (status SafeArea)
echo.

if exist "%LOCAL_APK%" (
  echo [OK] Найден локальный APK.
  goto :copy_apk
)

if exist "%PROJECT%\.git" (
  echo git pull origin %BRANCH% ...
  cd /d "%PROJECT%"
  git fetch origin %BRANCH% 2>nul
  git pull origin %BRANCH% 2>nul
  if exist "%LOCAL_APK%" goto :copy_apk
)

echo Пробую GitHub Releases...
curl -fsSL --retry 3 --retry-delay 5 -o "%DST%" "%URL%"
if errorlevel 1 (
  powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%URL%' -OutFile '%DST%' -UseBasicParsing } catch { exit 1 }"
)

if exist "%DST%" (
  if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
  copy /Y "%DST%" "%INSTALL_DIR%\%APK_NAME%"
  goto :done
)

echo.
echo [ОШИБКА] APK не получен.
echo   git pull origin %BRANCH%
echo   или Яндекс.Диск: app:/podchet_kalloriy/apk/
echo   или android-сборки\scripts\build-apk.bat
pause
exit /b 1

:copy_apk
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%LOCAL_APK%" "%DST%"
copy /Y "%LOCAL_APK%" "%INSTALL_DIR%\%APK_NAME%"

:done
echo Готово: %DST%
start "" "%DST%"
pause
