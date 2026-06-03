function Get-AllowedContextLengths {
    [CmdletBinding()]
    param()

    return @(4096, 8192, 16384, 32768, 65536, 131072, 262144)
}

function Test-ContextLength {
    [CmdletBinding()]
    param([int]$ContextLength)

    return (Get-AllowedContextLengths) -contains $ContextLength
}

function Get-ContextLength {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [int]$Default = 4096
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    $raw = (Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue).Trim()
    $value = 0
    if ([int]::TryParse($raw, [ref]$value) -and (Test-ContextLength $value)) {
        return $value
    }
    return $Default
}

function Set-ContextLength {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [int]$ContextLength
    )

    if (-not (Test-ContextLength $ContextLength)) {
        throw "Invalid context length: $ContextLength"
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $Path -Value $ContextLength -Encoding ASCII
}

Export-ModuleMember -Function Get-AllowedContextLengths,
    Test-ContextLength,
    Get-ContextLength,
    Set-ContextLength
