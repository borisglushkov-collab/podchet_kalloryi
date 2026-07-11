@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "APK_NAME=podchet_kalloriy-1.2.5-health-scale.apk"
set "LOCAL_APK=%PROJECT%\работа с весами\install\%APK_NAME%"
set "DST=D:\%APK_NAME%"
set "INSTALL_DIR=%PROJECT%\работа с весами\install"
set "BRANCH=cursor/chat-podchet-kalloryi-a36d"
set "URL=https://github.com/borisglushkov-collab/podchet_kalloryi/releases/download/v1.2.5-health-scale/%APK_NAME%"

echo.
echo === Установка APK v1.2.4 (Health Scale) ===
echo.

rem --- Способ 1: APK уже в репозитории (git pull) ---
if exist "%LOCAL_APK%" (
  echo [OK] Найден локальный APK в репозитории.
  goto :copy_apk
)

if exist "%PROJECT%\.git" (
  echo Обновляю репозиторий (git pull)...
  cd /d "%PROJECT%"
  git fetch origin %BRANCH% 2>nul
  git checkout %BRANCH% 2>nul
  git pull origin %BRANCH% 2>nul
  if exist "%LOCAL_APK%" (
    echo [OK] APK получен через git pull.
    goto :copy_apk
  )
)

rem --- Способ 2: скачивание с GitHub Releases ---
echo Пробую скачать с GitHub Releases...
echo URL: %URL%
echo.
echo Если появится ERR_CONNECTION_RESET — GitHub CDN заблокирован.
echo Используйте VPN или способ 1 (git pull) выше.
echo.

curl -fsSL --retry 3 --retry-delay 5 -o "%DST%" "%URL%"
if errorlevel 1 (
  echo curl не удался, пробую PowerShell...
  powershell -NoProfile -Command ^
    "try { Invoke-WebRequest -Uri '%URL%' -OutFile '%DST%' -UseBasicParsing } catch { exit 1 }"
)

if exist "%DST%" (
  echo [OK] Скачано в %DST%
  if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
  copy /Y "%DST%" "%INSTALL_DIR%\%APK_NAME%"
  goto :done
)

rem --- Способ 3: инструкции ---
echo.
echo [ОШИБКА] Не удалось получить APK.
echo.
echo Варианты:
echo   1. VPN включить и запустить этот скрипт снова
echo   2. В папке %PROJECT% выполнить:
echo        git pull origin %BRANCH%
echo      Затем скопировать:
echo        %LOCAL_APK%
echo   3. Открыть в браузере (страница Releases, не прямая ссылка):
echo        https://github.com/borisglushkov-collab/podchet_kalloryi/releases/tag/v1.2.5-health-scale
echo   4. Собрать локально: build-apk-to-d.bat
echo.
pause
exit /b 1

:copy_apk
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%LOCAL_APK%" "%DST%"
copy /Y "%LOCAL_APK%" "%INSTALL_DIR%\%APK_NAME%"

:done
echo.
echo Готово:
echo   %DST%
echo   %INSTALL_DIR%\%APK_NAME%
echo.
echo Установка на телефон:
echo   adb install -r "%DST%"
echo.
start "" "%DST%"
pause
exit /b 0
