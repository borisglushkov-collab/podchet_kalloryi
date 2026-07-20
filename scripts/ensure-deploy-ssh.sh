#!/usr/bin/env bash
# Готовит SSH-ключ для деплоя на VPS.
# Источники (по приоритету):
#   1) env DEPLOY_SSH_KEY  (Cursor Runtime Secret)
#   2) <repo>/.ssh/id_ed25519
#   3) ~/.ssh/id_ed25519
#
# Usage:
#   source scripts/ensure-deploy-ssh.sh
#   # exports: DEPLOY_SSH_IDENTITY, DEPLOY_SSH_HOST, DEPLOY_SSH_USER
#   ssh -i "$DEPLOY_SSH_IDENTITY" "${DEPLOY_SSH_USER}@${DEPLOY_SSH_HOST}" '...'

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SSH_DIR="$ROOT/.ssh"
IDENTITY=""

DEPLOY_SSH_HOST="${DEPLOY_HOST:-${DEPLOY_SSH_HOST:-5.42.111.122}}"
DEPLOY_SSH_USER="${DEPLOY_USER:-${DEPLOY_SSH_USER:-root}}"

mkdir -p "$PROJECT_SSH_DIR" "$HOME/.ssh"
chmod 700 "$PROJECT_SSH_DIR" "$HOME/.ssh" 2>/dev/null || true

if [[ -n "${DEPLOY_SSH_KEY:-}" ]]; then
  IDENTITY="$PROJECT_SSH_DIR/id_ed25519"
  # Normalize newlines; secret may arrive with literal \n
  printf '%s\n' "${DEPLOY_SSH_KEY//$'\r'/}" | sed 's/\\n/\n/g' > "$IDENTITY"
  chmod 600 "$IDENTITY"
  cp -f "$IDENTITY" "$HOME/.ssh/id_ed25519"
  chmod 600 "$HOME/.ssh/id_ed25519"
  ssh-keygen -y -f "$IDENTITY" > "$PROJECT_SSH_DIR/id_ed25519.pub" 2>/dev/null || true
  echo "[deploy-ssh] ключ из DEPLOY_SSH_KEY → $IDENTITY" >&2
elif [[ -f "$PROJECT_SSH_DIR/id_ed25519" ]]; then
  IDENTITY="$PROJECT_SSH_DIR/id_ed25519"
  chmod 600 "$IDENTITY"
  cp -f "$IDENTITY" "$HOME/.ssh/id_ed25519"
  chmod 600 "$HOME/.ssh/id_ed25519"
  echo "[deploy-ssh] ключ из $IDENTITY" >&2
elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  IDENTITY="$HOME/.ssh/id_ed25519"
  mkdir -p "$PROJECT_SSH_DIR"
  cp -f "$IDENTITY" "$PROJECT_SSH_DIR/id_ed25519"
  chmod 600 "$PROJECT_SSH_DIR/id_ed25519"
  echo "[deploy-ssh] ключ из ~/.ssh/id_ed25519" >&2
else
  echo "[deploy-ssh] Нет ключа. Добавьте Cursor Secret DEPLOY_SSH_KEY или файл .ssh/id_ed25519" >&2
  echo "См. .ssh/README.md" >&2
  return 1 2>/dev/null || exit 1
fi

# Quick sanity: must be a private key
if ! grep -q 'PRIVATE KEY' "$IDENTITY"; then
  echo "[deploy-ssh] Файл не похож на приватный ключ: $IDENTITY" >&2
  return 1 2>/dev/null || exit 1
fi

export DEPLOY_SSH_IDENTITY="$IDENTITY"
export DEPLOY_SSH_HOST
export DEPLOY_SSH_USER

# Helper for callers
deploy_ssh() {
  ssh -i "$DEPLOY_SSH_IDENTITY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=20 \
    "${DEPLOY_SSH_USER}@${DEPLOY_SSH_HOST}" "$@"
}
export -f deploy_ssh 2>/dev/null || true
