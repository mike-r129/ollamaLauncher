[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $InstallDir) {
    if ($AllUsers) {
        if (-not (Test-IsAdministrator)) {
            throw 'All-users install requires an elevated PowerShell session.'
        }
        $InstallDir = Join-Path $env:ProgramFiles 'ollamaLauncher'
    } else {
        $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\ollamaLauncher'
    }
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$items = @(
    'ollamaLauncher.bat',
    'fetch_models.ps1',
    'ollama_wrapper.ps1',
    'README.md',
    'config',
    'src'
)

foreach ($item in $items) {
    $source = Join-Path $repoRoot $item
    if (-not (Test-Path -LiteralPath $source)) { continue }
    $destination = Join-Path $InstallDir $item
    if ((Get-Item -LiteralPath $source).PSIsContainer) {
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    } else {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

Write-Host "Installed ollamaLauncher to $InstallDir"
