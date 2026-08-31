@echo off
chcp 65001 >nul
setlocal

set "DEST=E:\Работа и ИИ\Лечение, уменьшение веса\лекарства"
set "SRC=%~dp0выгрузка-чата\питание-завтрак-обед-ужин.xlsx"

echo.
echo Копирую Excel-меню в:
echo   %DEST%
echo.

if not exist "E:\" (
  echo Диск E: не найден. Запустите этот файл на своём ПК.
  pause
  exit /b 1
)

if not exist "%SRC%" (
  echo Не найден файл:
  echo   %SRC%
  pause
  exit /b 1
)

mkdir "%DEST%" 2>nul
copy /Y "%SRC%" "%DEST%\питание-завтрак-обед-ужин.xlsx"
if errorlevel 1 (
  echo Копирование не удалось. Проверьте, что диск E: доступен и папка не защищена.
  pause
  exit /b 1
)

echo Готово:
echo   %DEST%\питание-завтрак-обед-ужин.xlsx
echo.
start "" "%DEST%"
pause
