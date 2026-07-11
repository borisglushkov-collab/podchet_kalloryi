@echo off
where flutter >nul 2>&1
if errorlevel 1 (
    echo Flutter SDK не найден. Установите: https://docs.flutter.dev/get-started/install/windows
    exit /b 1
)
cd /d "%~dp0"
bash scripts/patch_lefu_plugin.sh 2>nul
if errorlevel 1 (
    echo Примечание: patch_lefu_plugin.sh пропущен ^(нужен Git Bash^)
)
flutter pub get
flutter build apk --release
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
echo Скопируйте на D: install\podchet_kalloriy-1.1.0-health-scale.apk
