$RepoRoot = Split-Path -Parent $PSScriptRoot
$Entrypoint = Join-Path $RepoRoot 'src/OllamaLauncher.ps1'

function New-OllamaLauncherEntrypointTestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ollamaLauncher-entrypoint-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-OllamaLauncherEntrypointTestDirectory {
    param([string]$Path)

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'src/OllamaLauncher.ps1' {
    It 'initializes launcher paths without entering the interactive batch flow' {
        $dir = New-OllamaLauncherEntrypointTestDirectory
        $oldConfig = $env:OLLAMA_LAUNCHER_CONFIG_DIR
        $oldCache = $env:OLLAMA_LAUNCHER_CACHE_DIR

        try {
            $configDir = Join-Path $dir 'Config'
            $cacheDir = Join-Path $dir 'Cache'
            $env:OLLAMA_LAUNCHER_CONFIG_DIR = $configDir
            $env:OLLAMA_LAUNCHER_CACHE_DIR = $cacheDir

            $output = powershell -NoProfile -ExecutionPolicy Bypass -File $Entrypoint -InitializeOnly 2>&1
            $LASTEXITCODE | Should Be 0

            (Test-Path -LiteralPath $configDir) | Should Be $true
            (Test-Path -LiteralPath $cacheDir) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $configDir 'repos.json')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $configDir 'fetch_models.ps1')) | Should Be $true
            ($output -join "`n") | Should Match 'ollamaLauncher initialized'
            ($output -join "`n") | Should Match 'ReposConfig='
        }
        finally {
            if ($null -eq $oldConfig) {
                Remove-Item Env:\OLLAMA_LAUNCHER_CONFIG_DIR -ErrorAction SilentlyContinue
            } else {
                $env:OLLAMA_LAUNCHER_CONFIG_DIR = $oldConfig
            }

            if ($null -eq $oldCache) {
                Remove-Item Env:\OLLAMA_LAUNCHER_CACHE_DIR -ErrorAction SilentlyContinue
            } else {
                $env:OLLAMA_LAUNCHER_CACHE_DIR = $oldCache
            }

            Remove-OllamaLauncherEntrypointTestDirectory $dir
        }
    }
}
