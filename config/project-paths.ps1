# Пути проекта на диске D: — подключать в скриптах: . "$ProjectRoot\config\project-paths.ps1"
param(
    [string]$ProjectRoot = ""
)

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
}

$script:ProjectRoot = $ProjectRoot
$script:ProjectSshDir = Join-Path $ProjectRoot ".ssh"
$script:ProjectSshConfig = Join-Path $ProjectSshDir "config"
$script:ProjectSshKey = Join-Path $ProjectSshDir "id_ed25519"
$script:ProjectCache = Join-Path $ProjectRoot ".cache"
$script:ProjectStaging = Join-Path $ProjectCache "staging"

$env:PROJECT_ROOT = $ProjectRoot
$env:PUB_CACHE = Join-Path $ProjectCache "pub"
$env:GRADLE_USER_HOME = Join-Path $ProjectCache "gradle"

if (Test-Path "D:\flutter\bin\flutter.bat") {
    $env:FLUTTER_ROOT = "D:\flutter"
    if ($env:Path -notlike "*D:\flutter\bin*") {
        $env:Path = "D:\flutter\bin;$env:Path"
    }
}

New-Item -ItemType Directory -Path $ProjectSshDir, $env:PUB_CACHE, $env:GRADLE_USER_HOME, $ProjectStaging -Force | Out-Null

function Get-ProjectSshArgs {
    param([string[]]$Extra = @())
    $args = @()
    if (Test-Path $ProjectSshKey) {
        $args += @("-i", $ProjectSshKey)
    }
    if (Test-Path $ProjectSshConfig) {
        $args += @("-F", $ProjectSshConfig)
    }
    return $args + $Extra
}
