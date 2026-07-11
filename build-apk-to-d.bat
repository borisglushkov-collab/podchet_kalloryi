@echo off
chcp 65001 >nul
setlocal

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "APK_SRC=%PROJECT%\mobile\build\app\outputs\flutter-apk\app-release.apk"
set "APK_DST=D:\podchet_kalloriy-1.1.0-health-scale.apk"
set "INSTALL_DIR=%PROJECT%\работа с весами\install"

echo.
echo === Сборка APK v1.1.0 (Health Scale) ===
cd /d "%PROJECT%\mobile"
call build_apk.bat
if errorlevel 1 exit /b 1

if not exist "%APK_SRC%" (
  echo [ОШИБКА] APK не найден: %APK_SRC%
  exit /b 1
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%APK_SRC%" "%INSTALL_DIR%\podchet_kalloriy-1.1.0-health-scale.apk"
copy /Y "%APK_SRC%" "%APK_DST%"

echo.
echo Готово:
echo   %INSTALL_DIR%\podchet_kalloriy-1.1.0-health-scale.apk
echo   %APK_DST%
echo.
echo Установка на телефон (USB + отладка):
echo   adb install -r "%APK_DST%"
echo.
pause
