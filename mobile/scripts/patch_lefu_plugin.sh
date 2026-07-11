#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get >/dev/null
mapfile -t files < <(ls -d "$HOME/.pub-cache/git/pp_bluetooth_kit_flutter-"*/android/build.gradle 2>/dev/null || true)
if [ "${#files[@]}" -eq 0 ]; then
  echo "LeFu plugin not found in pub cache"
  exit 1
fi
for f in "${files[@]}"; do
  sed -i 's/compileSdk 33/compileSdk 36/' "$f"
  echo "Patched $f"
done
