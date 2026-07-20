#!/usr/bin/env bash
# Восстанавливает upload-keystore для подписи APK (чтобы обновления ставились поверх).
# Источники:
#   1) уже есть mobile/android/keystore/upload-keystore.jks
#   2) Яндекс.Диск disk:/podchet_kalloriy/keystore/upload-keystore.jks
#   3) ~/.android/debug.keystore (fallback)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/mobile/android"
KS_DIR="$ANDROID_DIR/keystore"
KS_FILE="$KS_DIR/upload-keystore.jks"
PROPS="$ANDROID_DIR/key.properties"
ENV_FILE="${YANDEX_DISK_ENV:-$ROOT/android-сборки/scripts/yandex-disk.env}"

mkdir -p "$KS_DIR"

if [[ ! -f "$KS_FILE" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
  fi
  if [[ -n "${YANDEX_DISK_TOKEN:-}" ]]; then
    echo "[signing] Скачиваю keystore с Яндекс.Диска..."
    REMOTE="disk:/podchet_kalloriy/keystore/upload-keystore.jks"
    HREF="$(curl -sf -G -H "Authorization: OAuth ${YANDEX_DISK_TOKEN}" \
      --data-urlencode "path=${REMOTE}" \
      "https://cloud-api.yandex.net/v1/disk/resources/download" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["href"])')"
    curl -sfL "$HREF" -o "$KS_FILE"
  elif [[ -f "$HOME/.android/debug.keystore" ]]; then
    echo "[signing] Копирую ~/.android/debug.keystore (временный fallback)"
    cp -f "$HOME/.android/debug.keystore" "$KS_FILE"
  else
    echo "[signing] Нет keystore. Положите upload-keystore.jks или настройте Yandex token." >&2
    exit 1
  fi
fi

chmod 600 "$KS_FILE"

if [[ ! -f "$PROPS" ]]; then
  cat > "$PROPS" <<'EOF'
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=keystore/upload-keystore.jks
EOF
  chmod 600 "$PROPS"
fi

echo "[signing] OK → $KS_FILE"
