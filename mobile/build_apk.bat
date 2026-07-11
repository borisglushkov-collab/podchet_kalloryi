@echo off
chcp 65001 >nul
cd /d "%~dp0mobile"
bash scripts/patch_lefu_plugin.sh 2>nul
flutter pub get
flutter build apk --release
if errorlevel 1 exit /b 1
bash "%~dp0android-сборки/scripts/post-build.sh"
echo APK: build\app\outputs\flutter-apk\app-release.apk
