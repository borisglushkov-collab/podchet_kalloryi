@echo off
setlocal
set "SDK=C:\Users\msi\AppData\Local\Android\Sdk"
set "AVDMGR=%SDK%\cmdline-tools\latest\bin\avdmanager.bat"
set "EMU=%SDK%\emulator\emulator.exe"
set "PKG=system-images;android-37.1;google_apis_playstore_ps16k;x86_64"
set "LOG=%~dp0avd-create.log"

echo Creating AVD Pixel_API_37... > "%LOG%"
(echo n) | "%AVDMGR%" create avd -n Pixel_API_37 -k "%PKG%" -d pixel_7 -f >> "%LOG%" 2>&1

echo. >> "%LOG%"
echo AVD list: >> "%LOG%"
"%EMU%" -list-avds >> "%LOG%" 2>&1

for /f "usebackq delims=" %%i in (`"%EMU%" -list-avds 2^>nul`) do (
  echo Starting emulator: %%i >> "%LOG%"
  start "Android Emulator" "%EMU%" -avd "%%i"
  exit /b 0
)

echo Failed to create or start AVD >> "%LOG%"
exit /b 1
