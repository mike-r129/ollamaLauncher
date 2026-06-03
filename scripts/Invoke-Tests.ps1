[CmdletBinding()]
param(
    [string]$Path,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path) {
    $Path = Join-Path $repoRoot 'tests'
}

$pester = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
if (-not $pester) {
    throw "Pester is required to run tests. Install Pester or run in a PowerShell environment where Invoke-Pester is available."
}

$result = Invoke-Pester -Path $Path -PassThru

if ($PassThru) {
    $result
}

$failedCount = 0
if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'FailedCount') {
    $failedCount = [int]$result.FailedCount
}

if ($failedCount -gt 0) {
    exit 1
}

exit 0
