Import-Module (Join-Path $PSScriptRoot 'RepositoryParse.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Hardware.psm1') -Force

function Get-InstalledOllamaModels {
    [CmdletBinding()]
    param()

    $output = ollama list | Select-Object -Skip 1
    $models = @()
    foreach ($line in $output) {
        if ($line -match '^(\S+)\s+\S+\s+(\S+\s+\S+)') {
            $name = $Matches[1]
            $size = $Matches[2]
            $params = Get-ModelParamsFromName $name
            $models += [PSCustomObject]@{
                Name = $name
                Size = $size
                Params = $params
                Description = 'Installed'
            }
        }
    }
    return $models
}

function Get-CatalogSizeGb {
    param([string]$Size)

    return ConvertTo-ModelSizeGb $Size
}

function Sort-ModelCatalogRows {
    param(
        [object[]]$Rows,
        [string]$Mode = 'DEFAULT',
        [bool]$Descending,
        [string]$SearchTerm = '',
        [string]$FieldRegex = '',
        [bool]$FieldNumeric,
        [bool]$HardwareFilter,
        [double]$VramGb,
        [double]$RamGb,
        [double]$DiskGb,
        [int]$ContextLength = 4096,
        [switch]$TagRows
    )

    $data = @($Rows)
    if ($SearchTerm) {
        $data = @($data | Where-Object { $_.Name -like ('*' + $SearchTerm + '*') })
    }
    if ($HardwareFilter) {
        $data = @($data | Where-Object {
            $sz = Get-CatalogSizeGb $_.Size
            if ($sz -lt 0) { return $true }
            if ($DiskGb -gt 0 -and $sz -gt $DiskGb) { return $false }
            return ($sz -le ($VramGb + $RamGb))
        })
    }

    if ($Mode -eq 'SIZE') {
        return @($data | Sort-Object -Property @{ Expression = { Get-CatalogSizeGb $_.Size } } -Descending:$Descending)
    }
    if ($Mode -eq 'BEST') {
        $g = @($data | Where-Object { (Get-ModelFitTier (Get-CatalogSizeGb $_.Size) $VramGb $RamGb $DiskGb $ContextLength) -eq 0 } | Sort-Object { Get-CatalogSizeGb $_.Size } -Descending)
        $y = @($data | Where-Object { (Get-ModelFitTier (Get-CatalogSizeGb $_.Size) $VramGb $RamGb $DiskGb $ContextLength) -eq 1 } | Sort-Object { Get-CatalogSizeGb $_.Size })
        $r = @($data | Where-Object { (Get-ModelFitTier (Get-CatalogSizeGb $_.Size) $VramGb $RamGb $DiskGb $ContextLength) -eq 2 } | Sort-Object { Get-CatalogSizeGb $_.Size })
        $u = @($data | Where-Object { (Get-ModelFitTier (Get-CatalogSizeGb $_.Size) $VramGb $RamGb $DiskGb $ContextLength) -eq 3 })
        return @($g) + @($y) + @($r) + @($u)
    }
    if ($Mode -eq 'FIELD' -and $FieldRegex) {
        return @($data | Sort-Object -Property @{ Expression = {
            $v = $null
            if ($_.Description -match $FieldRegex) { $v = $Matches[1] }
            if ($FieldNumeric) {
                if ($v) { try { [double]$v } catch { -1 } } else { -1 }
            } else {
                if ($v) { $v } else { '' }
            }
        }} -Descending:$Descending)
    }
    return @($data)
}

function Read-ModelCatalogFile {
    param([string]$Path, [switch]$TagRows)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    if ($TagRows) {
        return @(Import-Csv $Path -Delimiter '|' -Header 'Name','Size','Params','Description' -Encoding UTF8)
    }
    return @(Import-Csv $Path -Delimiter '|' -Header 'Name','Size','Params','TagCount','Description' -Encoding UTF8)
}

function Write-ModelCatalogFile {
    param([string]$Path, [object[]]$Rows, [switch]$TagRows)

    $lines = @()
    foreach ($row in @($Rows)) {
        if ($TagRows) {
            $lines += "$($row.Name)|$($row.Size)|$($row.Params)|$($row.Description)"
        } else {
            $lines += "$($row.Name)|$($row.Size)|$($row.Params)|$($row.TagCount)|$($row.Description)"
        }
    }
    if ($lines.Count -gt 0) {
        [System.IO.File]::WriteAllLines($Path, $lines)
    } else {
        Set-Content -Path $Path -Value '' -Encoding UTF8
    }
}

function Sort-ModelCatalogFile {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$Mode = 'DEFAULT',
        [bool]$Descending,
        [string]$SearchTerm = '',
        [string]$FieldRegex = '',
        [bool]$FieldNumeric,
        [bool]$HardwareFilter,
        [double]$VramGb,
        [double]$RamGb,
        [double]$DiskGb,
        [int]$ContextLength = 4096,
        [switch]$TagRows
    )

    $rows = Read-ModelCatalogFile -Path $SourcePath -TagRows:$TagRows
    $sorted = Sort-ModelCatalogRows -Rows $rows -Mode $Mode -Descending:$Descending -SearchTerm $SearchTerm -FieldRegex $FieldRegex -FieldNumeric:$FieldNumeric -HardwareFilter:$HardwareFilter -VramGb $VramGb -RamGb $RamGb -DiskGb $DiskGb -ContextLength $ContextLength -TagRows:$TagRows
    Write-ModelCatalogFile -Path $DestinationPath -Rows $sorted -TagRows:$TagRows
}

Export-ModuleMember -Function Get-InstalledOllamaModels,
    Get-CatalogSizeGb,
    Sort-ModelCatalogRows,
    Read-ModelCatalogFile,
    Write-ModelCatalogFile,
    Sort-ModelCatalogFile
