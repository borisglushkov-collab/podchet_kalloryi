#!/bin/bash
# Обновление backend на VPS из GitHub Release (запускать от root в консоли Timeweb).
# Пример:
#   curl -fsSL https://raw.githubusercontent.com/borisglushkov-collab/podchet_kalloryi/main/backend/deploy/update-from-github.sh | bash
# или:
#   bash update-from-github.sh v1.4.19-backend

set -euo pipefail

REPO="${REPO:-borisglushkov-collab/podchet_kalloryi}"
TAG="${1:-v1.4.21-backend}"
ZIP_URL="${ZIP_URL:-https://github.com/${REPO}/releases/download/${TAG}/podchet_backend_deploy.zip}"
TMP_ZIP=/tmp/podchet_backend_deploy.zip
TMP_DIR=/tmp/podchet_backend_unpack

echo "=== Скачиваю $ZIP_URL ==="
curl -fsSL -o "$TMP_ZIP" "$ZIP_URL"

echo "=== Распаковка ==="
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
apt-get install -y -qq unzip >/dev/null
unzip -oq "$TMP_ZIP" -d "$TMP_DIR"

# Архив может содержать файлы в корне или в подпапке backend/
SRC="$TMP_DIR"
if [ -f "$TMP_DIR/main.py" ]; then
  SRC="$TMP_DIR"
elif [ -f "$TMP_DIR/backend/main.py" ]; then
  SRC="$TMP_DIR/backend"
else
  echo "Не найден main.py в архиве" >&2
  ls -la "$TMP_DIR" >&2
  exit 1
fi

echo "=== Установка из $SRC ==="
# Сохраняем .env
KEEP_ENV=/tmp/podchet_backend.env.bak
if [ -f /opt/podchet_kalloriy/backend/.env ]; then
  cp /opt/podchet_kalloriy/backend/.env "$KEEP_ENV"
fi

mkdir -p /opt/podchet_kalloriy/backend
rsync -a --delete \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.env' \
  --exclude '*.pyc' \
  "$SRC/" /opt/podchet_kalloriy/backend/

if [ -f "$KEEP_ENV" ]; then
  cp "$KEEP_ENV" /opt/podchet_kalloriy/backend/.env
fi

cd /opt/podchet_kalloriy/backend
sed -i 's/\r$//' deploy/install-vps.sh
bash deploy/install-vps.sh

echo ""
echo "=== Проверка новых эндпоинтов ==="
curl -sS http://127.0.0.1/ | head -c 800 || true
echo ""
curl -sS -o /dev/null -w "ai-search-food HTTP %{http_code}\n" \
  -X POST http://127.0.0.1/api/ai-search-food \
  -H 'Content-Type: application/json' \
  -d '{"query":"творог"}' || true
curl -sS -o /dev/null -w "coach-chat HTTP %{http_code}\n" \
  -X POST http://127.0.0.1/api/coach-chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"привет","meal_type":"dinner"}' || true
echo "Готово."
