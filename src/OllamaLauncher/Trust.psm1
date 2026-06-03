function Get-TrustedHosts {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @('huggingface.co', 'ollama.com')
    }

    $raw = (Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $raw) { return @() }
    return @($raw -split ';' | Where-Object { $_ })
}

function Test-TrustedHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$HostName
    )

    return ((Get-TrustedHosts -Path $Path) -contains $HostName)
}

function Add-TrustedHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$HostName
    )

    $hosts = @(Get-TrustedHosts -Path $Path)
    if ($hosts -notcontains $HostName) { $hosts += $HostName }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $Path -Value ($hosts -join ';') -Encoding ASCII
}

Export-ModuleMember -Function Get-TrustedHosts, Test-TrustedHost, Add-TrustedHost
