param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [switch]$Set,
    [int]$Value,
    [int]$Default = 4096
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Context.psm1') -Force -DisableNameChecking

if ($Set) {
    Context\Set-ContextLength -Path $Path -ContextLength $Value
    Write-Output $Value
    exit 0
}

Write-Output (Context\Get-ContextLength -Path $Path -Default $Default)
