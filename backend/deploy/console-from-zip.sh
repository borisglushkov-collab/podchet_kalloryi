#!/bin/bash
# После загрузки podchet_backend_deploy.zip в /tmp/ на VPS (консоль Timeweb):
#   apt install -y unzip
#   bash /tmp/console-from-zip.sh
#
# Или если backend уже распакован в /opt/podchet_kalloriy/backend:
#   cd /opt/podchet_kalloriy/backend && bash deploy/install-vps.sh

set -euo pipefail

ZIP="${1:-/tmp/podchet_backend_deploy.zip}"
TARGET="/opt/podchet_kalloriy/backend"

echo "=== Распаковка $ZIP ==="
apt-get update -qq
apt-get install -y -qq unzip python3 python3-venv nginx rsync curl

mkdir -p /opt/podchet_kalloriy
rm -rf "$TARGET"
mkdir -p "$TARGET"
unzip -o "$ZIP" -d "$TARGET"

if [ ! -f "$TARGET/deploy/install-vps.sh" ]; then
  echo "Ошибка: в архиве нет deploy/install-vps.sh"
  exit 1
fi

chmod +x "$TARGET/deploy/install-vps.sh"
cd "$TARGET"
bash deploy/install-vps.sh

if ! grep -q 'CURSOR_API_KEY=crsr_' "$TARGET/.env" 2>/dev/null; then
  echo ""
  echo "!!! Укажите ключ: nano $TARGET/.env"
  echo "    systemctl restart podchet-kalloriy"
fi
