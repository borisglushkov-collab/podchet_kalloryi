#!/bin/bash
# Установка/обновление backend на Ubuntu VPS (Timeweb и др.)
# Запуск от root из папки backend:
#   bash deploy/install-vps.sh

set -euo pipefail

APP_USER=podchet
APP_DIR=/opt/podchet_kalloriy
BACKEND_DIR="$APP_DIR/backend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Зависимости системы ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip nginx curl rsync

echo "=== Пользователь $APP_USER ==="
id -u "$APP_USER" &>/dev/null || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"

echo "=== Копирование backend ==="
mkdir -p "$APP_DIR"
rsync -a --delete \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.env' \
  --exclude '*.pyc' \
  "$SOURCE_DIR/" "$BACKEND_DIR/"

chown -R "$APP_USER:$APP_USER" "$APP_DIR"

if [ ! -f "$BACKEND_DIR/.env" ]; then
  cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
  echo ""
  echo "!!! Создан $BACKEND_DIR/.env — укажите CURSOR_API_KEY и перезапустите:"
  echo "    systemctl restart podchet-kalloriy"
  echo ""
fi
chown "$APP_USER:$APP_USER" "$BACKEND_DIR/.env" 2>/dev/null || true
chmod 600 "$BACKEND_DIR/.env" 2>/dev/null || true

echo "=== Python venv ==="
sudo -u "$APP_USER" python3 -m venv "$BACKEND_DIR/.venv"
sudo -u "$APP_USER" "$BACKEND_DIR/.venv/bin/pip" install --upgrade pip -q
sudo -u "$APP_USER" "$BACKEND_DIR/.venv/bin/pip" install -r "$BACKEND_DIR/requirements.txt" -q

echo "=== systemd ==="
cp "$BACKEND_DIR/deploy/podchet.service" /etc/systemd/system/podchet-kalloriy.service
systemctl daemon-reload
systemctl enable podchet-kalloriy
systemctl restart podchet-kalloriy

# Старый foodcontrol (если был) — останавливаем, чтобы не занимал порт 8000
if systemctl is-active --quiet foodcontrol 2>/dev/null; then
  echo "=== Остановка старого foodcontrol ==="
  systemctl stop foodcontrol
  systemctl disable foodcontrol 2>/dev/null || true
fi

echo "=== nginx ==="
cp "$BACKEND_DIR/deploy/nginx-podchet.conf" /etc/nginx/sites-available/podchet-kalloriy
ln -sf /etc/nginx/sites-available/podchet-kalloriy /etc/nginx/sites-enabled/podchet-kalloriy
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/foodcontrol 2>/dev/null || true
nginx -t
systemctl reload nginx

echo ""
echo "=== Готово ==="
sleep 2
curl -s http://127.0.0.1/health || curl -s http://127.0.0.1:8000/health || true
echo ""
PUBLIC_IP="$(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "Внешний health: http://${PUBLIC_IP}/health"
echo "В приложении:   http://${PUBLIC_IP}"
echo ""
echo "Логи: journalctl -u podchet-kalloriy -f"
