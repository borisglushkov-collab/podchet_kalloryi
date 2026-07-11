@echo off
chcp 65001 >nul
cd /d "D:\ucheba\podchet_kalloriy"

echo === git pull design + sync mockups ===
git pull origin cursor/design-a36d
if errorlevel 1 git pull origin cursor/chat-podchet-kalloryi-a36d

call "design\sync-to-local-d.bat"
