@echo off
cd /d C:\Users\msi\develop\podchet_kalloriy
git add README.md backend/DEPLOY-VPS.md mobile/lib/screens/settings_screen.dart
git commit -m "docs: clarify VPS port 80 (nginx) vs local :8000"
git push origin main > C:\Users\msi\develop\podchet_kalloriy\git-push-result.txt 2>&1
git rev-parse HEAD >> C:\Users\msi\develop\podchet_kalloriy\git-push-result.txt 2>&1
