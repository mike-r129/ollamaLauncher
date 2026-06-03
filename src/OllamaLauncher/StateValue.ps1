param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [switch]$Set,
    [string]$Value = '',
    [string]$Default = ''
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Config.psm1') -Force -DisableNameChecking

if ($Set) {
    Config\Set-LauncherStateValue -Path $Path -Value $Value
    Write-Output $Value
    exit 0
}

Write-Output (Config\Get-LauncherStateValue -Path $Path -Default $Default)
