# Деплой backend на VPS (Timeweb)

## Быстрый деплой с Windows

```powershell
cd backend
.\deploy\deploy-to-vps.ps1
```

По умолчанию сервер: `root@5.42.111.122`

Перед деплоем убедитесь, что в `backend\.env` указан `CURSOR_API_KEY`.

## Проверка

```powershell
curl http://5.42.111.122/health
curl "http://5.42.111.122/api/search-food?query=омлет"
```

В приложении: **Настройки → Адрес сервера → `http://5.42.111.122`**

## Если SSH не работает (консоль Timeweb)

1. Создайте архив на ПК:
   ```powershell
   cd backend
   .\deploy\pack-for-vps.ps1
   ```
   Файл: `podchet_backend_deploy.zip` в корне проекта.

2. Загрузите zip на VPS в `/tmp/` (SFTP или файловый менеджер Timeweb).

3. В **веб-консоли** Timeweb (root) выполните:

   ```bash
   apt-get update -qq && apt-get install -y unzip
   mkdir -p /opt/podchet_kalloriy/backend
   unzip -o /tmp/podchet_backend_deploy.zip -d /opt/podchet_kalloriy/backend
   cd /opt/podchet_kalloriy/backend
   bash deploy/install-vps.sh
   ```

4. Если ключ не скопировался — отредактируйте `.env`:
   ```bash
   nano /opt/podchet_kalloriy/backend/.env
   systemctl restart podchet-kalloriy
   ```

5. Проверка (должно быть `cursor_api_configured`):
   ```bash
   curl -s http://127.0.0.1/health
   ```

## Управление на сервере

```bash
systemctl status podchet-kalloriy
systemctl restart podchet-kalloriy
journalctl -u podchet-kalloriy -f
```

## HTTPS (опционально)

```bash
apt install certbot python3-certbot-nginx -y
certbot --nginx -d yourdomain.ru
```

В приложении: `https://yourdomain.ru`
