# Деплой backend на VPS Timeweb с Windows
# Использование:
#   .\deploy\deploy-to-vps.ps1
#   .\deploy\deploy-to-vps.ps1 -Server root@5.42.111.122

param(
    [string]$Server = "root@5.42.111.122",
    [string]$RemoteDir = "/tmp/podchet_deploy"
)

$ErrorActionPreference = "Stop"
$BackendRoot = Split-Path $PSScriptRoot -Parent
$Staging = Join-Path $env:TEMP "podchet_backend_staging"

Write-Host "=== Podchet Kalloriy: деплой на $Server ===" -ForegroundColor Cyan

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw "ssh не найден. Установите OpenSSH Client (Параметры Windows -> Приложения -> Дополнительные компоненты)."
}

# Проверка .env локально (ключ уйдёт на сервер)
$envFile = Join-Path $BackendRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Warning "Нет backend\.env — на сервере останется .env.example. Создайте .env с CURSOR_API_KEY."
}

Write-Host "Подготовка файлов..." -ForegroundColor Yellow
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging | Out-Null

$exclude = @('.venv', '__pycache__', '*.pyc')
Get-ChildItem $BackendRoot -Force | Where-Object {
    $_.Name -notin @('.venv', '__pycache__')
} | ForEach-Object {
    Copy-Item $_.FullName -Destination $Staging -Recurse -Force
}

Write-Host "Копирование на сервер (scp)..." -ForegroundColor Yellow
$sshTest = ssh -o BatchMode=yes -o ConnectTimeout=15 $Server "echo ok" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "SSH недоступен: $sshTest" -ForegroundColor Red
    Write-Host "Используйте pack-for-vps.ps1 и консоль Timeweb (см. DEPLOY-VPS.md)" -ForegroundColor Yellow
    exit 1
}
ssh -o ConnectTimeout=20 $Server "mkdir -p $RemoteDir"
scp -r -o ConnectTimeout=20 "$Staging\*" "${Server}:${RemoteDir}/"

Write-Host "Установка на сервере..." -ForegroundColor Yellow
$remoteCmd = @"
set -e
rsync -a --delete --exclude '.venv' --exclude '__pycache__' $RemoteDir/ /opt/podchet_kalloriy/backend/ 2>/dev/null || {
  mkdir -p /opt/podchet_kalloriy
  rsync -a --delete --exclude '.venv' --exclude '__pycache__' $RemoteDir/ /opt/podchet_kalloriy/backend/
}
cd /opt/podchet_kalloriy/backend
bash deploy/install-vps.sh
"@

ssh -o ConnectTimeout=20 $Server $remoteCmd

Write-Host ""
Write-Host "=== Деплой завершён ===" -ForegroundColor Green
Write-Host "Проверка: curl http://5.42.111.122/health"
Write-Host "В приложении: http://5.42.111.122"

Remove-Item $Staging -Recurse -Force -ErrorAction SilentlyContinue
