#!/bin/bash
# Деплой с GitHub Release (консоль Timeweb)
# Замените USER на ваш GitHub-логин:
#   bash deploy-from-github.sh YOUR_GITHUB_USER

set -euo pipefail

GITHUB_USER="${1:-}"
TAG="v1.0.0-deploy"
REPO="podchet_kalloriy"
ZIP="/tmp/podchet_backend_deploy.zip"

if [ -z "$GITHUB_USER" ]; then
  echo "Использование: bash deploy-from-github.sh YOUR_GITHUB_USER"
  exit 1
fi

URL="https://github.com/${GITHUB_USER}/${REPO}/releases/download/${TAG}/podchet_backend_deploy.zip"

echo "=== Скачивание $URL ==="
apt-get update -qq
apt-get install -y -qq curl unzip
curl -fsSL -o "$ZIP" "$URL"

echo "=== Установка ==="
mkdir -p /opt/podchet_kalloriy/backend
unzip -o "$ZIP" -d /opt/podchet_kalloriy/backend
cd /opt/podchet_kalloriy/backend
bash deploy/install-vps.sh

echo ""
echo "Укажите CURSOR_API_KEY:"
echo "  nano /opt/podchet_kalloriy/backend/.env"
echo "  systemctl restart podchet-kalloriy"
