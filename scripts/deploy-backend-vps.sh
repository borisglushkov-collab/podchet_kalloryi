#!/usr/bin/env bash
# Обновить backend на VPS из GitHub Release.
# Usage:
#   bash scripts/deploy-backend-vps.sh
#   bash scripts/deploy-backend-vps.sh v1.4.25-backend

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/ensure-deploy-ssh.sh"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  VER="$(tr -d '[:space:]' < "$ROOT/backend/VERSION")"
  TAG="v${VER}-backend"
fi

echo "=== Deploy $TAG → ${DEPLOY_SSH_USER}@${DEPLOY_SSH_HOST} ==="

deploy_ssh bash -s <<REMOTE
set -euo pipefail
curl -fsSL -o /tmp/update-from-github.sh \\
  https://raw.githubusercontent.com/borisglushkov-collab/podchet_kalloryi/main/backend/deploy/update-from-github.sh \\
  || curl -fsSL -o /tmp/update-from-github.sh \\
  https://raw.githubusercontent.com/borisglushkov-collab/podchet_kalloryi/cursor/coach-diary-scan-a36d/backend/deploy/update-from-github.sh
sed -i 's/\\r\$//' /tmp/update-from-github.sh
bash /tmp/update-from-github.sh ${TAG}
systemctl restart podchet-kalloriy 2>/dev/null || systemctl restart podchet 2>/dev/null || true
sleep 1
echo '=== HEALTH ==='
curl -sS http://127.0.0.1/health
echo
cat /opt/podchet_kalloriy/backend/VERSION
REMOTE

echo "=== Готово ==="
