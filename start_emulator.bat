@echo off
setlocal EnableExtensions
set "EMU=C:\Users\msi\AppData\Local\Android\Sdk\emulator\emulator.exe"
set "ADB=C:\Users\msi\AppData\Local\Android\Sdk\platform-tools\adb.exe"
set "OUT=%~dp0emulator-start-result.txt"

> "%OUT%" echo [%DATE% %TIME%] Emulator launcher
>> "%OUT%" echo EMU path: %EMU%
>> "%OUT%" echo EMU exists: 
if exist "%EMU%" (>> "%OUT%" echo YES) else (>> "%OUT%" echo NO & exit /b 1)

>> "%OUT%" echo.
>> "%OUT%" echo AVD list:
"%EMU%" -list-avds >> "%OUT%" 2>&1

for /f "usebackq delims=" %%i in (`"%EMU%" -list-avds 2^>nul`) do (
  >> "%OUT%" echo.
  >> "%OUT%" echo Launching: %%i
  start "Android Emulator" "%EMU%" -avd "%%i"
  ping -n 20 127.0.0.1 >nul
  >> "%OUT%" echo adb devices:
  "%ADB%" devices >> "%OUT%" 2>&1
  exit /b 0
)

>> "%OUT%" echo.
>> "%OUT%" echo ERROR: No AVD. Create device in Android Studio - Device Manager.
exit /b 1
