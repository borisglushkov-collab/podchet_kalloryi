#!/usr/bin/env bash
# Готовит SSH для деплоя на VPS.
# Приоритет:
#   1) env DEPLOY_SSH_KEY — полный OpenSSH private key (Cursor Runtime Secret)
#   2) env root_pass или DEPLOY_SSH_PASSWORD — пароль root + sshpass
#   3) файл <repo>/.ssh/deploy_key
#   4) файл ~/.ssh/deploy_key
#
# Usage:
#   source scripts/ensure-deploy-ssh.sh
#   deploy_ssh 'hostname'

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SSH_DIR="$ROOT/.ssh"
KEY_NAME="deploy_key"
IDENTITY=""
AUTH_MODE=""

DEPLOY_SSH_HOST="${DEPLOY_HOST:-${DEPLOY_SSH_HOST:-}}"
DEPLOY_SSH_USER="${DEPLOY_USER:-${DEPLOY_SSH_USER:-root}}"

if [[ -z "${DEPLOY_SSH_HOST}" ]]; then
  echo "[deploy-ssh] Задайте DEPLOY_HOST (runtime secret / env)." >&2
  return 1 2>/dev/null || exit 1
fi

mkdir -p "$PROJECT_SSH_DIR" "$HOME/.ssh"
chmod 700 "$PROJECT_SSH_DIR" "$HOME/.ssh" 2>/dev/null || true

_looks_like_private_key() {
  local f="$1"
  [[ -f "$f" ]] && grep -q 'PRIVATE KEY' "$f"
}

_write_key_from_env() {
  local raw="$1"
  # Reject filename fragments / placeholders mistaken for key material.
  if [[ ${#raw} -lt 80 ]] || [[ "$raw" != *"PRIVATE KEY"* && "$raw" != *"BEGIN"* ]]; then
    echo "[deploy-ssh] DEPLOY_SSH_KEY не похож на private key (нужен полный текст BEGIN…END)." >&2
    return 1
  fi
  IDENTITY="$PROJECT_SSH_DIR/$KEY_NAME"
  printf '%s\n' "${raw//$'\r'/}" | sed 's/\\n/\n/g' > "$IDENTITY"
  chmod 600 "$IDENTITY"
  cp -f "$IDENTITY" "$HOME/.ssh/$KEY_NAME"
  chmod 600 "$HOME/.ssh/$KEY_NAME"
  ssh-keygen -y -f "$IDENTITY" > "$PROJECT_SSH_DIR/${KEY_NAME}.pub" 2>/dev/null || true
  AUTH_MODE="key"
  echo "[deploy-ssh] ключ из DEPLOY_SSH_KEY → $IDENTITY" >&2
}

if [[ -n "${DEPLOY_SSH_KEY:-}" ]] && _write_key_from_env "$DEPLOY_SSH_KEY"; then
  :
elif [[ -f "$PROJECT_SSH_DIR/$KEY_NAME" ]] && _looks_like_private_key "$PROJECT_SSH_DIR/$KEY_NAME"; then
  IDENTITY="$PROJECT_SSH_DIR/$KEY_NAME"
  chmod 600 "$IDENTITY"
  cp -f "$IDENTITY" "$HOME/.ssh/$KEY_NAME"
  chmod 600 "$HOME/.ssh/$KEY_NAME"
  AUTH_MODE="key"
  echo "[deploy-ssh] ключ из $IDENTITY" >&2
elif [[ -f "$HOME/.ssh/$KEY_NAME" ]] && _looks_like_private_key "$HOME/.ssh/$KEY_NAME"; then
  IDENTITY="$HOME/.ssh/$KEY_NAME"
  cp -f "$IDENTITY" "$PROJECT_SSH_DIR/$KEY_NAME"
  chmod 600 "$PROJECT_SSH_DIR/$KEY_NAME"
  AUTH_MODE="key"
  echo "[deploy-ssh] ключ из ~/.ssh/$KEY_NAME" >&2
elif [[ -n "${root_pass:-}${DEPLOY_SSH_PASSWORD:-}" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "[deploy-ssh] Нужен sshpass для пароля (apt/yum install sshpass)." >&2
    return 1 2>/dev/null || exit 1
  fi
  export SSHPASS="${root_pass:-$DEPLOY_SSH_PASSWORD}"
  AUTH_MODE="password"
  echo "[deploy-ssh] пароль из root_pass/DEPLOY_SSH_PASSWORD → sshpass" >&2
else
  echo "[deploy-ssh] Нет доступа. Добавьте Cursor Secret:" >&2
  echo "  - DEPLOY_SSH_KEY = полный private key, или" >&2
  echo "  - root_pass / DEPLOY_SSH_PASSWORD = пароль root VPS" >&2
  echo "См. .ssh/README.md" >&2
  return 1 2>/dev/null || exit 1
fi

if [[ "$AUTH_MODE" == "key" ]] && ! _looks_like_private_key "$IDENTITY"; then
  echo "[deploy-ssh] Файл не похож на приватный ключ: $IDENTITY" >&2
  return 1 2>/dev/null || exit 1
fi

export DEPLOY_SSH_IDENTITY="${IDENTITY:-}"
export DEPLOY_SSH_HOST
export DEPLOY_SSH_USER
export DEPLOY_SSH_AUTH_MODE="$AUTH_MODE"

deploy_ssh() {
  if [[ "${DEPLOY_SSH_AUTH_MODE}" == "password" ]]; then
    sshpass -e ssh \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=20 \
      "${DEPLOY_SSH_USER}@${DEPLOY_SSH_HOST}" "$@"
  else
    ssh -i "$DEPLOY_SSH_IDENTITY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=20 \
      "${DEPLOY_SSH_USER}@${DEPLOY_SSH_HOST}" "$@"
  fi
}
export -f deploy_ssh 2>/dev/null || true
