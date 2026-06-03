param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [string]$HostName = '',
    [switch]$Add,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Trust.psm1') -Force -DisableNameChecking

if ($List) {
    Write-Output ((Trust\Get-TrustedHosts -Path $Path) -join ';')
    exit 0
}

if ([string]::IsNullOrWhiteSpace($HostName)) {
    throw 'HostName is required unless -List is used.'
}

if ($Add) {
    Trust\Add-TrustedHost -Path $Path -HostName $HostName
    Write-Output ((Trust\Get-TrustedHosts -Path $Path) -join ';')
    exit 0
}

$trusted = Trust\Get-TrustedHosts -Path $Path
Write-Output ($trusted -join ';')
if ($trusted -contains $HostName) {
    exit 0
}

exit 1
