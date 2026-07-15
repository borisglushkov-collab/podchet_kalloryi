#!/usr/bin/env bash
# Загрузка файла на Яндекс.Диск (REST API)
# По умолчанию кладёт APK в обе папки:
#   disk:/podchet_kalloriy/apk
#   app:/podchet_kalloriy/apk  (= Приложения/Yandex Polygon/podchet_kalloriy/apk)
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

FILENAME="$(basename "$APK_PATH")"

# Primary folder from env + always mirror into the familiar app:/ path.
PRIMARY="${YANDEX_DISK_FOLDER:-disk:/podchet_kalloriy/apk}"
FOLDERS=("$PRIMARY")
if [[ "$PRIMARY" != "app:/podchet_kalloriy/apk" ]]; then
  FOLDERS+=("app:/podchet_kalloriy/apk")
fi
if [[ "$PRIMARY" != "disk:/podchet_kalloriy/apk" ]]; then
  FOLDERS+=("disk:/podchet_kalloriy/apk")
fi

upload_one() {
  local FOLDER="$1"
  local REMOTE_PATH="${FOLDER}/${FILENAME}"

  python3 - "$FOLDER" "$YANDEX_DISK_TOKEN" <<'PY'
import sys
import urllib.error
import urllib.parse
import urllib.request

folder, token = sys.argv[1], sys.argv[2]
if folder.startswith("app:"):
    prefix, rest = "app:", folder[4:].lstrip("/")
elif folder.startswith("disk:"):
    prefix, rest = "disk:", folder[5:].lstrip("/")
else:
    prefix, rest = "disk:", folder.lstrip("/")

acc = f"{prefix}/"
for part in rest.split("/"):
    if not part:
        continue
    acc = f"{acc}{part}" if acc.endswith("/") else f"{acc}/{part}"
    req = urllib.request.Request(
        "https://cloud-api.yandex.net/v1/disk/resources?path="
        + urllib.parse.quote(acc),
        method="PUT",
        headers={"Authorization": f"OAuth {token}"},
    )
    try:
        urllib.request.urlopen(req, timeout=20).read()
    except urllib.error.HTTPError:
        pass
PY

  echo "[yandex] Получаю URL загрузки → ${REMOTE_PATH}"
  UPLOAD_JSON="$(curl -sf -G \
    -H "Authorization: OAuth ${YANDEX_DISK_TOKEN}" \
    --data-urlencode "path=${REMOTE_PATH}" \
    --data-urlencode "overwrite=true" \
    "https://cloud-api.yandex.net/v1/disk/resources/upload")"

  UPLOAD_URL="$(echo "$UPLOAD_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['href'])")"

  echo "[yandex] Загружаю ${FILENAME}..."
  curl -sf -T "$APK_PATH" "$UPLOAD_URL"

  echo "[yandex] Готово: ${REMOTE_PATH}"
  if [[ "$REMOTE_PATH" == disk:/* ]]; then
    echo "[yandex] Открыть: https://disk.yandex.ru/client/disk/${REMOTE_PATH#disk:/}"
  elif [[ "$REMOTE_PATH" == app:/* ]]; then
    echo "[yandex] Открыть: https://disk.yandex.ru/client/disk/Приложения/Yandex%20Polygon/podchet_kalloriy/apk"
  fi
}

# unique folders
declare -A SEEN=()
for FOLDER in "${FOLDERS[@]}"; do
  [[ -n "${SEEN[$FOLDER]:-}" ]] && continue
  SEEN[$FOLDER]=1
  upload_one "$FOLDER"
done
