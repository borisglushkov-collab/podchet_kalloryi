# SSH / пароль для деплоя на VPS

Секреты **не коммитятся** в git (см. `.gitignore`).

## Cloud Agent (Cursor) — рекомендуется

1. [Cursor Dashboard → Cloud Agents](https://cursor.com/dashboard?tab=cloud-agents)
2. Environments → ваш environment → **Secrets**

Добавьте **один** из вариантов:

| Secret | Значение |
|--------|----------|
| `root_pass` или `DEPLOY_SSH_PASSWORD` | пароль root VPS |
| `DEPLOY_SSH_KEY` | **полный** текст private key (`BEGIN` … `END`), не имя файла |

Опционально можно задать пользователя SSH (`DEPLOY_USER`, обычно `root`) и хост отдельным runtime secret.

Скрипт `scripts/ensure-deploy-ssh.sh` поддерживает и ключ, и пароль (`sshpass`).

## Локально

Положите ключ как:

```
.ssh/deploy_key
.ssh/deploy_key.pub   # опционально
```

Или экспортируйте `root_pass` / `DEPLOY_SSH_PASSWORD` и используйте `scripts/deploy-backend-vps.sh`.

## GitHub Actions

В secrets репозитория:

- `DEPLOY_SSH_PASSWORD` — пароль root, **или**
- `DEPLOY_SSH_PRIVATE_KEY` — полный private key

Workflow: `.github/workflows/deploy-backend.yml`
