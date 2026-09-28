# Downloads the meal plan to E: without a local git clone.
$ErrorActionPreference = 'Stop'
$dir = 'E:\Работа и ИИ\Лечение, уменьшение веса\лекарства'
$url = 'https://raw.githubusercontent.com/borisglushkov-collab/podchet_kalloryi/cursor/palette-local-card-730a/palette/meal-plan.xlsx'
$out = Join-Path $dir 'питание-завтрак-обед-ужин.xlsx'

if (-not (Test-Path 'E:\')) {
    Write-Host 'Disk E: not found. Run this on your Windows PC.'
    exit 1
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
Write-Host "Saved: $out"
Invoke-Item $dir
