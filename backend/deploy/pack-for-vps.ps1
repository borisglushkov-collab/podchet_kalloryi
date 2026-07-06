# Упаковка backend для GitHub Release / загрузки на VPS
$BackendRoot = Split-Path $PSScriptRoot -Parent
$ProjectRoot = Split-Path $BackendRoot -Parent
$ReleasesDir = Join-Path $ProjectRoot "releases"
$OutZip = Join-Path $ReleasesDir "podchet_backend_deploy.zip"
$Staging = Join-Path $env:TEMP "podchet_pack_$(Get-Random)"

Write-Host "Упаковка backend -> $OutZip"

New-Item -ItemType Directory -Path $ReleasesDir -Force | Out-Null
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
Write-Host "(без .env — только .env.example)"
