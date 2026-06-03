[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$tests = @(
    @{
        Name = 'Entrypoint initialization'
        Command = {
            powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'src\OllamaLauncher.ps1') -InitializeOnly | Out-Null
        }
    },
    @{
        Name = 'Repository listing'
        Command = {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('ollamaLauncher-smoke-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            try {
                powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'fetch_models.ps1') -ListRepos -ConfigFile (Join-Path $dir 'repos.json') -CacheFile (Join-Path $dir 'repos_list.txt') | Out-Null
            } finally {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = 'Pull target validation'
        Command = {
            powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'fetch_models.ps1') -ValidatePull -Repo Ollama -ModelName 'llama3:8b' | Out-Null
        }
    }
)

foreach ($test in $tests) {
    Write-Host "Smoke: $($test.Name)"
    & $test.Command
}

Write-Host 'Smoke tests passed.'
