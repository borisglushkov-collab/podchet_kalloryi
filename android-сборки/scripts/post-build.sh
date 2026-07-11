#!/usr/bin/env bash
# После flutter build apk: копировать в install/ и на Яндекс.Диск
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_DIR="$ROOT/android-сборки/install"
SCRIPTS="$ROOT/android-сборки/scripts"
APK_SRC="$ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk"
VERSION="$(grep '^version:' "$ROOT/mobile/pubspec.yaml" | sed 's/version: //;s/+/-/')"
APK_NAME="podchet_kalloriy-${VERSION}-health-scale.apk"
APK_DST="$INSTALL_DIR/$APK_NAME"

if [[ ! -f "$APK_SRC" ]]; then
  echo "[post-build] APK не найден: $APK_SRC"
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "$APK_SRC" "$APK_DST"
echo "[post-build] Скопировано: $APK_DST"

chmod +x "$SCRIPTS/upload-yandex-disk.sh" 2>/dev/null || true
"$SCRIPTS/upload-yandex-disk.sh" "$APK_DST" || echo "[post-build] Яндекс.Диск: пропуск или ошибка"

echo "[post-build] Готово."
