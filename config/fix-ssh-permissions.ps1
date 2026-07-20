# Права на приватный SSH-ключ (OpenSSH на Windows требует доступ только владельцу)
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$key = Join-Path $ProjectRoot ".ssh\id_ed25519"
$dir = Join-Path $ProjectRoot ".ssh"

if (-not (Test-Path $key)) {
    Write-Warning "Ключ не найден: $key"
    exit 1
}

icacls $key /inheritance:r | Out-Null
icacls $key /grant:r "${env:USERNAME}:R" | Out-Null
icacls $dir /inheritance:r | Out-Null
icacls $dir /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
Write-Host "Права на SSH-ключ настроены: $key"
