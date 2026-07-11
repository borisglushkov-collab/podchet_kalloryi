#!/usr/bin/env bash
# Загрузка файла на Яндекс.Диск (REST API)
set -euo pipefail

APK_PATH="${1:?Usage: upload-yandex-disk.sh <file.apk>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${YANDEX_DISK_ENV:-$SCRIPT_DIR/yandex-disk.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[yandex] Пропуск: нет $ENV_FILE (скопируйте yandex-disk.env.example)"
  exit 0
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ -z "${YANDEX_DISK_TOKEN:-}" ]]; then
  echo "[yandex] Пропуск: YANDEX_DISK_TOKEN не задан"
  exit 0
fi

FOLDER="${YANDEX_DISK_FOLDER:-app:/podchet_kalloriy/apk}"
FILENAME="$(basename "$APK_PATH")"
REMOTE_PATH="${FOLDER}/${FILENAME}"
ENCODED_PATH="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REMOTE_PATH}'))")"

echo "[yandex] Создаю папку ${FOLDER}..."
curl -sf -X PUT \
  -H "Authorization: OAuth ${YANDEX_DISK_TOKEN}" \
  "https://cloud-api.yandex.net/v1/disk/resources?path=${ENCODED_PATH%/*}&" \
  >/dev/null 2>&1 || true

echo "[yandex] Получаю URL загрузки..."
UPLOAD_JSON="$(curl -sf -G \
  -H "Authorization: OAuth ${YANDEX_DISK_TOKEN}" \
  --data-urlencode "path=${REMOTE_PATH}" \
  --data-urlencode "overwrite=true" \
  "https://cloud-api.yandex.net/v1/disk/resources/upload")"

UPLOAD_URL="$(echo "$UPLOAD_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['href'])")"

echo "[yandex] Загружаю ${FILENAME}..."
curl -sf -T "$APK_PATH" "$UPLOAD_URL"

echo "[yandex] Готово: ${REMOTE_PATH}"
echo "[yandex] Открыть: https://disk.yandex.ru/client/disk${REMOTE_PATH#app:}"
