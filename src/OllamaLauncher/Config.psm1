function Get-LauncherStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$Default = ''
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    $value = (Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Set-LauncherStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Value
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $Path -Value $Value -Encoding ASCII
}

function Get-SelectedRepositoryName {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$StatePath)

    return Get-LauncherStateValue -Path $StatePath -Default 'Ollama'
}

function Set-SelectedRepositoryName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$StatePath,
        [Parameter(Mandatory=$true)]
        [string]$RepositoryName
    )

    Set-LauncherStateValue -Path $StatePath -Value $RepositoryName
}

Export-ModuleMember -Function Get-LauncherStateValue,
    Set-LauncherStateValue,
    Get-SelectedRepositoryName,
    Set-SelectedRepositoryName
