@echo off
set "SDK=C:\Users\msi\AppData\Local\Android\Sdk"
set "SDKMGR=%SDK%\cmdline-tools\latest\bin\sdkmanager.bat"
set "LOG=C:\Users\msi\develop\podchet_kalloriy\hypervisor-install.log"

echo Installing hypervisor driver... > "%LOG%"
echo y | "%SDKMGR%" "extras;google;Android_Emulator_Hypervisor_Driver" >> "%LOG%" 2>&1

set "INSTALLER=%SDK%\extras\google\Android_Emulator_Hypervisor_Driver\silent_install.bat"
if exist "%INSTALLER%" (
  echo Running silent_install.bat... >> "%LOG%"
  call "%INSTALLER%" >> "%LOG%" 2>&1
) else (
  echo Installer not found at %INSTALLER% >> "%LOG%"
  dir /s /b "%SDK%\extras" >> "%LOG%" 2>&1
)

echo Done. >> "%LOG%"
