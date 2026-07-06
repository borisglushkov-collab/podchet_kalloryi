@echo off
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8000 ^| findstr LISTENING') do taskkill /F /PID %%a >nul 2>&1
ping -n 2 127.0.0.1 >nul
cd /d C:\Users\msi\develop\podchet_kalloriy\backend
start "Backend" cmd /k .venv\Scripts\uvicorn.exe main:app --host 0.0.0.0 --port 8000
