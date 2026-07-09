@echo off
setlocal
echo === Cleanup remaining project copies on C: ===
echo Run this after closing Cursor completely.

set "TARGET=C:\Users\msi\.cursor\worktrees\podchet_kalloriy"

taskkill /F /IM python.exe /FI "WINDOWTITLE eq *" 2>nul

timeout /t 2 /nobreak >nul

if exist "%TARGET%" (
  echo Removing %TARGET% ...
  rmdir /s /q "%TARGET%" 2>nul
  if exist "%TARGET%" (
    takeown /f "%TARGET%" /r /d y >nul
    icacls "%TARGET%" /grant %USERNAME%:F /t /c >nul
    rmdir /s /q "%TARGET%" 2>nul
  )
)

cd /d "D:\ucheba\podchet_kalloriy"
git worktree prune -v

if exist "%TARGET%" (
  echo FAILED: %TARGET% still locked. Restart PC and run again.
) else (
  echo SUCCESS: C worktree removed.
)

echo.
echo D project check:
if exist "D:\ucheba\podchet_kalloriy\README.md" (echo   D:\ucheba\podchet_kalloriy OK) else (echo   D project MISSING!)
pause
