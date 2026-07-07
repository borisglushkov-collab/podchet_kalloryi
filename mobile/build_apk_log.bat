@echo off
cd /d D:\ucheba\podchet_kalloriy\mobile
set "LOG=D:\ucheba\podchet_kalloriy\mobile\build-log.txt"
> "%LOG%" echo [%DATE% %TIME%] Build started

where flutter >>"%LOG%" 2>&1
if errorlevel 1 (
  for %%F in (
    "C:\Users\msi\develop\flutter\bin\flutter.bat"
    "D:\flutter\bin\flutter.bat"
    "C:\flutter\bin\flutter.bat"
  ) do if exist %%F set "FLUTTER=%%~F"
  if not defined FLUTTER (
    echo FLUTTER_NOT_FOUND>>"%LOG%"
    exit /b 1
  )
) else (
  set "FLUTTER=flutter"
)

echo Using: %FLUTTER%>>"%LOG%"
"%FLUTTER%" pub get >>"%LOG%" 2>&1
"%FLUTTER%" build apk --release >>"%LOG%" 2>&1
echo EXIT_CODE=%ERRORLEVEL%>>"%LOG%"
if exist build\app\outputs\flutter-apk\app-release.apk (
  echo APK_OK>>"%LOG%"
  dir build\app\outputs\flutter-apk\app-release.apk >>"%LOG%"
) else (
  echo APK_MISSING>>"%LOG%"
)
exit /b %ERRORLEVEL%
