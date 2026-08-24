@echo off
chcp 65001 >nul
setlocal

set "DEST=C:\Users\glushkov.v\Desktop\МХ2000\учеба\обучение ИИ\подбор цвета"
set "SRC=%~dp0"

echo.
echo Копирую проект палитры и чат в:
echo   %DEST%
echo.

if not exist "C:\Users\glushkov.v\Desktop\" (
  echo Папка пользователя не найдена: C:\Users\glushkov.v\Desktop
  echo Запустите этот файл на своём ПК, не на сервере.
  pause
  exit /b 1
)

mkdir "%DEST%" 2>nul
mkdir "%DEST%\выгрузка-чата" 2>nul

xcopy /E /I /Y "%SRC%*" "%DEST%\"
if errorlevel 1 (
  echo Копирование не удалось.
  pause
  exit /b 1
)

echo.
echo Готово. Открываю папку.
start "" "%DEST%"
pause
