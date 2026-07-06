# Публикация проекта и архива деплоя на GitHub
param(
    [string]$RepoName = "podchet_kalloriy",
    [string]$Tag = "v1.0.0-deploy",
    [string]$Gh = "gh"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $Root

if (-not (Get-Command $Gh -ErrorAction SilentlyContinue)) {
    $fallback = "$env:LOCALAPPDATA\Temp\gh-cli\bin\gh.exe"
    if (Test-Path $fallback) { $Gh = $fallback } else { throw "Установите GitHub CLI: winget install GitHub.cli" }
}

Write-Host "=== 1. Архив backend (без .env) ===" -ForegroundColor Cyan
& "$PSScriptRoot\pack-for-vps.ps1"

$zip = Join-Path $Root "releases\podchet_backend_deploy.zip"
if (-not (Test-Path $zip)) { throw "Архив не создан: $zip" }

Write-Host "=== 2. GitHub auth ===" -ForegroundColor Cyan
& $Gh auth status 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "Войдите в GitHub:" -ForegroundColor Yellow
    & $Gh auth login -h github.com -p https -w
}

Write-Host "=== 3. Push репозитория ===" -ForegroundColor Cyan
git add -A
git status
$status = git status --porcelain
if ($status) {
    git commit -m "Add GitHub release scripts and deploy archive path"
}
if (-not (git remote get-url origin 2>$null)) {
    & $Gh repo create $RepoName --public --source=. --remote=origin --push
} else {
    git push -u origin HEAD
}

Write-Host "=== 4. Release с архивом ===" -ForegroundColor Cyan
$existing = & $Gh release view $Tag 2>$null
if ($LASTEXITCODE -eq 0) {
    & $Gh release upload $Tag $zip --clobber
} else {
    & $Gh release create $Tag $zip `
        --title "Backend deploy archive" `
        --notes "ZIP для деплоя на Timeweb VPS (без секретов). См. backend/DEPLOY-VPS.md"
}

$repoUrl = (& $Gh repo view --json url -q .url)
Write-Host ""
Write-Host "Репозиторий: $repoUrl" -ForegroundColor Green
Write-Host "Release:     $repoUrl/releases/tag/$Tag" -ForegroundColor Green
Write-Host ""
Write-Host "Скачать на VPS:" -ForegroundColor Yellow
Write-Host "  curl -L -o /tmp/podchet_backend_deploy.zip $repoUrl/releases/download/$Tag/podchet_backend_deploy.zip"
