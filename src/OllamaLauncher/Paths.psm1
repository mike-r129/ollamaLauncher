function Get-OllamaLauncherAppRoot {
    [CmdletBinding()]
    param()

    if ($env:OLLAMA_LAUNCHER_APP_ROOT) {
        return [System.IO.Path]::GetFullPath($env:OLLAMA_LAUNCHER_APP_ROOT)
    }

    $srcRoot = Split-Path -Parent $PSScriptRoot
    return Split-Path -Parent $srcRoot
}

function Get-OllamaLauncherConfigDirectory {
    [CmdletBinding()]
    param()

    $base = $env:APPDATA
    if (-not $base) {
        $base = Join-Path ([System.IO.Path]::GetTempPath()) 'ollamaLauncher'
        return $base
    }

    return Join-Path $base 'ollamaLauncher'
}

function Get-OllamaLauncherCacheDirectory {
    [CmdletBinding()]
    param()

    $base = $env:LOCALAPPDATA
    if (-not $base) {
        $base = [System.IO.Path]::GetTempPath()
    }

    return Join-Path (Join-Path $base 'ollamaLauncher') 'Cache'
}

function Get-OllamaLauncherConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    return Join-Path (Get-OllamaLauncherConfigDirectory) $Name
}

function Get-OllamaLauncherCachePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    return Join-Path (Get-OllamaLauncherCacheDirectory) $Name
}

function Get-OllamaLauncherDefaultReposPath {
    [CmdletBinding()]
    param()

    return Join-Path (Join-Path (Get-OllamaLauncherAppRoot) 'config') 'repos.default.json'
}

Export-ModuleMember -Function Get-OllamaLauncherAppRoot,
    Get-OllamaLauncherConfigDirectory,
    Get-OllamaLauncherCacheDirectory,
    Get-OllamaLauncherConfigPath,
    Get-OllamaLauncherCachePath,
    Get-OllamaLauncherDefaultReposPath
