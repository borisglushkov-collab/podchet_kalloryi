#!/usr/bin/env bash
# Синхронизирует версии из корневого файла VERSION во все места проекта.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Не найден $VERSION_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source <(grep -E '^(MOBILE_VERSION|MOBILE_BUILD|BACKEND_VERSION)=' "$VERSION_FILE")

: "${MOBILE_VERSION:?}"
: "${MOBILE_BUILD:?}"
: "${BACKEND_VERSION:?}"

MOBILE_FULL="${MOBILE_VERSION}+${MOBILE_BUILD}"
BACKEND_TAG="v${BACKEND_VERSION}-backend"
SYNC_DATE="$(date -u +%Y-%m-%d)"

echo "Mobile:  $MOBILE_FULL"
echo "Backend: $BACKEND_TAG"

# 1) Flutter pubspec
PUBSPEC="$ROOT/mobile/pubspec.yaml"
if [[ -f "$PUBSPEC" ]]; then
  sed -i -E "s/^version: .*/version: ${MOBILE_FULL}/" "$PUBSPEC"
  echo "OK  mobile/pubspec.yaml → version: ${MOBILE_FULL}"
fi

# 2) Backend VERSION file (читается FastAPI)
printf '%s\n' "$BACKEND_VERSION" > "$ROOT/backend/VERSION"
echo "OK  backend/VERSION → ${BACKEND_VERSION}"

# 3) Default tag in VPS update script
UPDATE_SH="$ROOT/backend/deploy/update-from-github.sh"
if [[ -f "$UPDATE_SH" ]]; then
  python3 - "$UPDATE_SH" "$BACKEND_TAG" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
tag = sys.argv[2]
text = path.read_text(encoding="utf-8")
new, n = re.subn(
    r'^TAG="\$\{1:-v[0-9.]+-backend\}"',
    f'TAG="${{1:-{tag}}}"',
    text,
    count=1,
    flags=re.M,
)
if n == 0:
    new, n = re.subn(
        r'^TAG="\$\{1:-[^"]+\}"',
        f'TAG="${{1:-{tag}}}"',
        text,
        count=1,
        flags=re.M,
    )
if n == 0:
    raise SystemExit(f"Не удалось обновить TAG в {path}")
path.write_text(new, encoding="utf-8")
print(f"OK  backend/deploy/update-from-github.sh → default {tag}")
PY
fi

# 4) VERSION.md — обновить шапку, changelog сохранить
VERSION_MD="$ROOT/VERSION.md"
CHANGELOG=""
if [[ -f "$VERSION_MD" ]]; then
  # всё после первой строки вида "## v..."
  CHANGELOG="$(awk '/^## v/{found=1} found{print}' "$VERSION_MD" || true)"
fi

# Убедиться, что текущая версия есть в changelog
if ! grep -q "^## v${MOBILE_VERSION}\$" <<<"$CHANGELOG" 2>/dev/null; then
  CHANGELOG="## v${MOBILE_VERSION}

- Mobile ${MOBILE_FULL}, backend ${BACKEND_TAG}
- Версии синхронизированы из корневого \`VERSION\`

${CHANGELOG}"
fi

cat > "$VERSION_MD" <<EOF
# Podchet Kalloriy — единая версия ${MOBILE_VERSION}

> Источник правды: файл [\`VERSION\`](VERSION). После правки запускайте \`bash scripts/sync-version.sh\`.

Синхронизировано: **${SYNC_DATE}**

| Компонент | Версия | Где используется |
|-----------|--------|------------------|
| Mobile APK | ${MOBILE_FULL} | \`mobile/pubspec.yaml\` |
| Backend API | ${BACKEND_VERSION} | \`backend/VERSION\` → FastAPI \`version\` |
| Backend deploy tag | \`${BACKEND_TAG}\` | \`backend/deploy/update-from-github.sh\` / GitHub Release |

${CHANGELOG}
EOF

echo "OK  VERSION.md"

echo
echo "Готово. Проверка:"
grep -E '^version:' "$PUBSPEC" || true
cat "$ROOT/backend/VERSION"
grep -E '^TAG=' "$UPDATE_SH" || true
