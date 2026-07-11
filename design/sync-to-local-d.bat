@echo off
chcp 65001 >nul
setlocal

set "PROJECT=D:\ucheba\podchet_kalloriy"
set "DEST=%PROJECT%\design"
set "SRC=%~dp0"

echo.
echo === Синхронизация design/ на диск D ===
echo %SRC% -^> %DEST%
echo.

if not exist "%PROJECT%" (
  echo [ОШИБКА] Нет папки %PROJECT%
  pause
  exit /b 1
)

if not exist "%DEST%\docs\mockups" mkdir "%DEST%\docs\mockups"
xcopy /E /I /Y /Q "%SRC%docs" "%DEST%\docs\"
xcopy /E /I /Y /Q "%SRC%source" "%DEST%\source\"
copy /Y "%SRC%README.md" "%DEST%\README.md" >nul
copy /Y "%SRC%worktree.json" "%DEST%\worktree.json" >nul

if exist "%DEST%\docs\mockups\profile-health-scale.png" (
  start "" "%DEST%\docs\mockups\profile-health-scale.png"
)
echo Готово: %DEST%
pause
