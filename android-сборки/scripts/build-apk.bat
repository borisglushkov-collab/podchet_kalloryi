@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0..\.."
cd /d "%ROOT%\mobile"

echo === Сборка APK (release) ===
where flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter SDK не найден
  exit /b 1
)

bash scripts/patch_lefu_plugin.sh 2>nul
flutter pub get
flutter build apk --release
if errorlevel 1 exit /b 1

echo.
echo === post-build: install/ + Яндекс.Диск ===
bash "%ROOT%\android-сборки\scripts\post-build.sh"
if errorlevel 1 (
  echo post-build завершился с предупреждением
)

echo.
echo APK: %ROOT%\mobile\build\app\outputs\flutter-apk\app-release.apk
pause
