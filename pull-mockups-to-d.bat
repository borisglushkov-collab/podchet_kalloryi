@echo off
chcp 65001 >nul
cd /d "D:\ucheba\podchet_kalloriy"

echo === git pull + sync на D ===
git pull origin cursor/chat-podchet-kalloryi-a36d
if errorlevel 1 git pull origin main

call "работа с весами\sync-to-local-d.bat"
