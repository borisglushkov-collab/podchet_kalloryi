@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo === Карточка мягкое лето ===
echo Папка: %CD%
echo.

if not "%~1"=="" (
  if exist "%~1" (
    copy /Y "%~1" "photo.jpg" >nul
    echo Скопировал: %~1
    goto :build
  ) else (
    echo Файл не найден: %~1
    pause
    exit /b 1
  )
)

if exist "photo.jpg" goto :build
if exist "photo.jpeg" goto :build
if exist "photo.jfif" goto :build
if exist "photo.png" goto :build
if exist "фото.jpg" goto :build

call :copy_newest "D:\загрузки(d)" && goto :build
call :copy_newest "%USERPROFILE%\Downloads" && goto :build
call :copy_newest "D:\Downloads" && goto :build

echo Фото не найдено.
echo Положите снимок в эту папку как photo.jpg
echo или запустите:
echo   собрать-карточку.bat "D:\загрузки^(d^)\ваш-файл.jfif"
echo.
pause
exit /b 1

:build
where py >nul 2>&1 && (set PY=py& goto :pip)
where python >nul 2>&1 && (set PY=python& goto :pip)
echo Нужен Python: https://www.python.org/downloads/
echo При установке отметьте "Add python.exe to PATH"
pause
exit /b 1

:pip
%PY% -m pip install -q -r requirements.txt
%PY% make_card.py
if errorlevel 1 (
  echo Сборка не удалась.
  pause
  exit /b 1
)
echo.
echo Открываю карточку.png
start "" "карточка.png"
pause
exit /b 0

:copy_newest
if not exist "%~1\" exit /b 1
echo Ищу снимок в %~1
for /f "delims=" %%F in ('dir /b /a-d /o-d "%~1\*.jfif" 2^>nul') do (
  copy /Y "%~1\%%F" "photo.jpg" >nul
  echo Скопировал: %%F
  exit /b 0
)
for /f "delims=" %%F in ('dir /b /a-d /o-d "%~1\*.jpg" 2^>nul') do (
  copy /Y "%~1\%%F" "photo.jpg" >nul
  echo Скопировал: %%F
  exit /b 0
)
exit /b 1
