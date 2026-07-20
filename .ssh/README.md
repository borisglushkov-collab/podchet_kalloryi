# SSH-ключ для деплоя на VPS

Приватный ключ **не коммитится** в git (см. `.gitignore`).

## Локально (Windows)

Положите ключ сюда:

```
.ssh/id_ed25519
.ssh/id_ed25519.pub   # опционально
```

Деплой: `backend\deploy\deploy-to-vps.ps1`

## Cloud Agent (Cursor)

1. Откройте [Cursor Dashboard → Cloud Agents](https://cursor.com/dashboard?tab=cloud-agents)
2. Environments → ваш environment (или создайте)
3. **Secrets** → Add secret:
   - Name: `DEPLOY_SSH_KEY`
   - Type: **Runtime Secret**
   - Value: весь текст `id_ed25519` (включая `BEGIN` / `END`)
4. Опционально:
   - `DEPLOY_HOST` = `5.42.111.122`
   - `DEPLOY_USER` = `root`

В следующем cloud-запуске агент подхватит ключ через `scripts/ensure-deploy-ssh.sh`.

Fingerprint текущего ключа (публичный):

```
256 SHA256:+5DjE6VbtCzqGkcHCFCv6o+tT0SNSrRdJTX+aF4iEqA msi@podchet-kalloriy (ED25519)
```
