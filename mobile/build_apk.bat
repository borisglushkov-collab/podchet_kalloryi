@echo off
where flutter >nul 2>&1
if errorlevel 1 (
    echo Flutter SDK не найден. Установите: https://docs.flutter.dev/get-started/install/windows
    exit /b 1
)
cd /d "%~dp0"
flutter pub get
flutter build apk --release
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
