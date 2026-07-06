@echo off
cd /d "%~dp0"
if not exist .venv (
    py -m venv .venv
    call .venv\Scripts\pip install -r requirements.txt
)
if not exist .env (
    copy .env.example .env
    echo.
    echo Создан файл .env — укажите CURSOR_API_KEY и перезапустите.
    pause
    exit /b 1
)
call .venv\Scripts\uvicorn main:app --host 0.0.0.0 --port 8000 --reload
