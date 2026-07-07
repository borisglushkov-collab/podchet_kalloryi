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
$ProjectRoot = Split-Path $BackendRoot -Parent
. (Join-Path $ProjectRoot "config\project-paths.ps1") -ProjectRoot $ProjectRoot

$Staging = Join-Path $ProjectStaging "podchet_backend_staging"
$SshArgs = { param([string[]]$Extra = @()) Get-ProjectSshArgs -Extra $Extra }

Write-Host "=== Podchet Kalloriy: деплой на $Server ===" -ForegroundColor Cyan
Write-Host "SSH-ключ: $ProjectSshDir" -ForegroundColor DarkGray

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw "ssh не найден. Установите OpenSSH Client (Параметры Windows -> Приложения -> Дополнительные компоненты)."
}

if (-not (Test-Path (Join-Path $ProjectSshDir "id_ed25519"))) {
    throw "Нет SSH-ключа: $ProjectSshDir\id_ed25519"
}

# Проверка .env локально (ключ уйдёт на сервер)
$envFile = Join-Path $BackendRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Warning "Нет backend\.env — на сервере останется .env.example. Создайте .env с CURSOR_API_KEY."
}

Write-Host "Подготовка файлов..." -ForegroundColor Yellow
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging | Out-Null

Get-ChildItem $BackendRoot -Force | Where-Object {
    $_.Name -notin @('.venv', '__pycache__')
} | ForEach-Object {
    Copy-Item $_.FullName -Destination $Staging -Recurse -Force
}
# dot-файлы вроде .env.example иногда не попадают в scp с Windows — копируем явно
foreach ($dot in @('.env.example', '.env')) {
    $p = Join-Path $BackendRoot $dot
    if (Test-Path $p) { Copy-Item $p -Destination $Staging -Force }
}

Write-Host "Копирование на сервер (scp)..." -ForegroundColor Yellow
$sshBase = & $SshArgs @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15")
$sshTest = & ssh @sshBase $Server "echo ok" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "SSH недоступен: $sshTest" -ForegroundColor Red
    Write-Host "Используйте pack-for-vps.ps1 и консоль Timeweb (см. DEPLOY-VPS.md)" -ForegroundColor Yellow
    exit 1
}
$sshRun = & $SshArgs @("-o", "ConnectTimeout=20")
& ssh @sshRun $Server "mkdir -p $RemoteDir"
& scp @sshRun -r "$Staging\*" "${Server}:${RemoteDir}/"

Write-Host "Установка на сервере..." -ForegroundColor Yellow
$remoteCmd = (@"
set -e
rsync -a --delete --exclude '.venv' --exclude '__pycache__' $RemoteDir/ /opt/podchet_kalloriy/backend/ 2>/dev/null || {
  mkdir -p /opt/podchet_kalloriy
  rsync -a --delete --exclude '.venv' --exclude '__pycache__' $RemoteDir/ /opt/podchet_kalloriy/backend/
}
cd /opt/podchet_kalloriy/backend
sed -i 's/\r$//' deploy/install-vps.sh
bash deploy/install-vps.sh
"@) -replace "`r`n", "`n"

$remoteCmd | & ssh @sshRun "bash -s"

Write-Host ""
Write-Host "=== Деплой завершён ===" -ForegroundColor Green
Write-Host "Проверка: curl http://5.42.111.122/health"
Write-Host "В приложении: http://5.42.111.122"

Remove-Item $Staging -Recurse -Force -ErrorAction SilentlyContinue
