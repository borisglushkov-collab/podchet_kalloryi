@echo off
chcp 65001 >nul
setlocal

rem Локальный проект на диске D (см. move-result.txt)
set "PROJECT=D:\ucheba\podchet_kalloriy"
set "DEST=%PROJECT%\работа с весами"
set "SRC=%~dp0"

echo.
echo === Синхронизация «работа с весами» на диск D ===
echo Источник: %SRC%
echo Назначение: %DEST%
echo.

if not exist "%PROJECT%" (
  echo [ОШИБКА] Папка проекта не найдена: %PROJECT%
  echo Откройте репозиторий: File -^> Open Folder -^> D:\ucheba\podchet_kalloriy
  pause
  exit /b 1
)

if not exist "%DEST%\docs\mockups" mkdir "%DEST%\docs\mockups"

xcopy /E /I /Y /Q "%SRC%docs" "%DEST%\docs\"
xcopy /E /I /Y /Q "%SRC%mobile" "%DEST%\mobile\" 2>nul
copy /Y "%SRC%README.md" "%DEST%\README.md" >nul
copy /Y "%SRC%worktree.json" "%DEST%\worktree.json" >nul
copy /Y "%SRC%.branch-visible" "%DEST%\.branch-visible" 2>nul

echo.
echo Готово. Файлы на D:
echo   %DEST%
echo   %DEST%\docs\mockups\profile-health-scale.png
echo.

if exist "%DEST%\docs\mockups\profile-health-scale.png" (
  echo Открываю макет...
  start "" "%DEST%\docs\mockups\profile-health-scale.png"
) else (
  echo [ВНИМАНИЕ] Макет не найден. Выполните git pull в %PROJECT%
)

endlocal
