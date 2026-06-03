param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath,
    [string]$Mode = 'DEFAULT',
    [string]$DescendingValue = '0',
    [string]$SearchTerm = '',
    [string]$FieldRegex = '',
    [string]$FieldNumericValue = '0',
    [string]$HardwareFilterValue = '0',
    [string]$VramGb = '0',
    [string]$RamGb = '0',
    [string]$DiskGb = '0',
    [string]$ContextLength = '4096',
    [switch]$TagRows
)

$ErrorActionPreference = 'Stop'

$ModuleRoot = $PSScriptRoot
Import-Module (Join-Path $ModuleRoot 'RepositoryParse.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'Hardware.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'ModelCatalog.psm1') -Force -DisableNameChecking

$vram = 0.0
$ram = 0.0
$disk = 0.0
$ctx = 4096
[double]::TryParse($VramGb, [ref]$vram) | Out-Null
[double]::TryParse($RamGb, [ref]$ram) | Out-Null
[double]::TryParse($DiskGb, [ref]$disk) | Out-Null
[int]::TryParse($ContextLength, [ref]$ctx) | Out-Null

ModelCatalog\Sort-ModelCatalogFile `
    -SourcePath $SourcePath `
    -DestinationPath $DestinationPath `
    -Mode $Mode `
    -Descending:($DescendingValue -eq '1') `
    -SearchTerm $SearchTerm `
    -FieldRegex $FieldRegex `
    -FieldNumeric:($FieldNumericValue -eq '1') `
    -HardwareFilter:($HardwareFilterValue -eq '1') `
    -VramGb $vram `
    -RamGb $ram `
    -DiskGb $disk `
    -ContextLength $ctx `
    -TagRows:$TagRows
