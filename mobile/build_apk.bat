@echo off
setlocal
set "PROJECT_ROOT=%~dp0.."
set "PUB_CACHE=%PROJECT_ROOT%.cache\pub"
set "GRADLE_USER_HOME=%PROJECT_ROOT%.cache\gradle"
if exist "D:\flutter\bin\flutter.bat" set "PATH=D:\flutter\bin;%PATH%"

if not exist "%PUB_CACHE%" mkdir "%PUB_CACHE%"
if not exist "%GRADLE_USER_HOME%" mkdir "%GRADLE_USER_HOME%"

where flutter >nul 2>&1
if errorlevel 1 (
    echo Flutter SDK не найден. Ожидается: D:\flutter
    echo Установите: https://docs.flutter.dev/get-started/install/windows
    exit /b 1
)
cd /d "%~dp0"
flutter pub get
flutter build apk --release
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
echo Кэш pub/gradle: %PROJECT_ROOT%.cache\
