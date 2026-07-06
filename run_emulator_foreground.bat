@echo off
set "EMU=C:\Users\msi\AppData\Local\Android\Sdk\emulator\emulator.exe"
set "LOG=C:\Users\msi\develop\podchet_kalloriy\emulator-boot.log"

echo Starting Pixel_API_37 at %DATE% %TIME% > "%LOG%"
"%EMU%" -avd Pixel_API_37 -no-snapshot-load >> "%LOG%" 2>&1
