@echo off
cd /d "%~dp0.."
echo === Деплой Podchet Kalloriy на VPS 5.42.111.122 ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-to-vps.ps1"
if errorlevel 1 (
    echo.
    echo SSH не удался. Создаю ZIP для консоли Timeweb...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack-for-vps.ps1"
    echo.
    echo Загрузите podchet_backend_deploy.zip на VPS в /tmp/
    echo В консоли Timeweb: bash /tmp/console-from-zip.sh
    pause
    exit /b 1
)
pause
