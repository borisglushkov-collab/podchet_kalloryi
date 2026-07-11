#!/usr/bin/env bash
# Скачать APK с Яндекс.Диска
set -euo pipefail

FILENAME="${1:?filename.apk}"
DST="${2:-./$FILENAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${YANDEX_DISK_ENV:-$SCRIPT_DIR/yandex-disk.env}"

source "$ENV_FILE"
FOLDER="${YANDEX_DISK_FOLDER:-app:/podchet_kalloriy/apk}"
REMOTE_PATH="${FOLDER}/${FILENAME}"

META="$(curl -sf -G \
  -H "Authorization: OAuth ${YANDEX_DISK_TOKEN}" \
  --data-urlencode "path=${REMOTE_PATH}" \
  "https://cloud-api.yandex.net/v1/disk/resources/download")"

HREF="$(echo "$META" | python3 -c "import sys,json; print(json.load(sys.stdin)['href'])")"
curl -sf -L -o "$DST" "$HREF"
echo "[yandex] Скачано: $DST"
