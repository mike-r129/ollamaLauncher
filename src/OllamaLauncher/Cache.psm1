function Get-LauncherCacheFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory,
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    return Join-Path $CacheDirectory $Name
}

function Test-CacheExpired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [int]$MaxAgeHours = 24
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    return ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime -gt (New-TimeSpan -Hours $MaxAgeHours))
}

function Write-AtomicTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string[]]$Lines,
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllLines($tmp, $Lines, $Encoding)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

Export-ModuleMember -Function Get-LauncherCacheFile, Test-CacheExpired, Write-AtomicTextFile
