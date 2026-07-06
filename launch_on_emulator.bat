@echo off
set "SDK=C:\Users\msi\AppData\Local\Android\Sdk"
set "EMU=%SDK%\emulator\emulator.exe"
set "ADB=%SDK%\platform-tools\adb.exe"
set "LOG=%~dp0launch-app.log"

> "%LOG%" echo [%DATE% %TIME%] Launch sequence

>> "%LOG%" echo.
>> "%LOG%" echo === adb devices ===
"%ADB%" devices >> "%LOG%" 2>&1

for /f "tokens=1" %%d in ('"%ADB%" devices ^| findstr "device$"') do (
  >> "%LOG%" echo Device already online: %%d
  goto start_backend
)

>> "%LOG%" echo Starting emulator Pixel_7...
start "Android Emulator" "%EMU%" -avd Pixel_7 -gpu host

>> "%LOG%" echo Waiting for boot...
ping -n 50 127.0.0.1 >nul
"%ADB%" wait-for-device >> "%LOG%" 2>&1
ping -n 20 127.0.0.1 >nul

:start_backend
>> "%LOG%" echo.
>> "%LOG%" echo === adb devices after boot ===
"%ADB%" devices >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo === backend health ===
curl -s http://127.0.0.1:8000/health >> "%LOG%" 2>&1 || (
  >> "%LOG%" echo Starting backend...
  start "Backend" cmd /c "cd /d %~dp0backend && .venv\Scripts\uvicorn.exe main:app --host 0.0.0.0 --port 8000"
  ping -n 8 127.0.0.1 >nul
)

>> "%LOG%" echo.
>> "%LOG%" echo === flutter run ===
cd /d %~dp0mobile
C:\Users\msi\develop\flutter\bin\flutter.bat run -d emulator-5554 >> "%LOG%" 2>&1
