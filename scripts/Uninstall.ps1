[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$AllUsers,
    [switch]$RemoveUserData,
    [switch]$RemoveCache
)

$ErrorActionPreference = 'Stop'

if (-not $InstallDir) {
    if ($AllUsers) {
        $InstallDir = Join-Path $env:ProgramFiles 'ollamaLauncher'
    } else {
        $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\ollamaLauncher'
    }
}

$resolved = if (Test-Path -LiteralPath $InstallDir) {
    (Resolve-Path -LiteralPath $InstallDir).Path
} else {
    $InstallDir
}

if ((Split-Path -Leaf $resolved) -ne 'ollamaLauncher') {
    throw "Refusing to remove unexpected install directory: $resolved"
}

if (Test-Path -LiteralPath $resolved) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Write-Host "Removed install directory $resolved"
}

if ($RemoveUserData) {
    $configDir = Join-Path $env:APPDATA 'ollamaLauncher'
    if (Test-Path -LiteralPath $configDir) {
        Remove-Item -LiteralPath $configDir -Recurse -Force
        Write-Host "Removed user config $configDir"
    }
}

if ($RemoveCache) {
    $cacheDir = Join-Path $env:LOCALAPPDATA 'ollamaLauncher\Cache'
    if (Test-Path -LiteralPath $cacheDir) {
        Remove-Item -LiteralPath $cacheDir -Recurse -Force
        Write-Host "Removed cache $cacheDir"
    }
}
