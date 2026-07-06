# Упаковка backend для загрузки на VPS (если SSH не работает)
$BackendRoot = Split-Path $PSScriptRoot -Parent
$OutZip = Join-Path (Split-Path $BackendRoot -Parent) "podchet_backend_deploy.zip"
$Staging = Join-Path $env:TEMP "podchet_pack_$(Get-Random)"

Write-Host "Упаковка backend -> $OutZip"

if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging | Out-Null

Get-ChildItem $BackendRoot -Force | Where-Object {
    $_.Name -notin @('.venv', '__pycache__', '.env')
} | ForEach-Object {
    Copy-Item $_.FullName -Destination $Staging -Recurse -Force
}

if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
Compress-Archive -Path "$Staging\*" -DestinationPath $OutZip -Force
Remove-Item $Staging -Recurse -Force

Write-Host "Готово: $OutZip"
Write-Host ""
Write-Host "Дальше:"
Write-Host "  1. Загрузите zip на VPS (SFTP / файловый менеджер Timeweb) в /tmp/"
Write-Host "  2. В веб-консоли Timeweb выполните:"
Write-Host "     bash /opt/podchet_kalloriy/backend/deploy/console-from-zip.sh"
