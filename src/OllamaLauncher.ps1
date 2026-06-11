param(
    [switch]$InitializeOnly,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$LauncherArguments
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = (Get-Location).Path }

$AppRoot = Split-Path -Parent $ScriptRoot
$env:OLLAMA_LAUNCHER_APP_ROOT = $AppRoot

$PathsModule = Join-Path $ScriptRoot 'OllamaLauncher\Paths.psm1'
Import-Module $PathsModule -Force
Import-Module (Join-Path $ScriptRoot 'OllamaLauncher\RepositoryConfig.psm1') -Force -DisableNameChecking

function Initialize-Directory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Resolve-LauncherHelper {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [string]$SourceRelativePath = $Name,
        [switch]$Required
    )

    $sourcePath = Join-Path $AppRoot $SourceRelativePath
    $legacyPath = Join-Path $ConfigDirectory $Name

    if (Test-Path -LiteralPath $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination $legacyPath -Force
        return $sourcePath
    }

    if (Test-Path -LiteralPath $legacyPath) {
        return $legacyPath
    }

    if ($Required) {
        throw "Required launcher helper is missing: $sourcePath"
    }

    return $legacyPath
}

$ConfigDirectory = Get-OllamaLauncherConfigDirectory
$CacheDirectory = Get-OllamaLauncherCacheDirectory
foreach ($directory in @($ConfigDirectory, $CacheDirectory)) {
    Initialize-Directory $directory
}

$DefaultRepos = Get-OllamaLauncherDefaultReposPath
if (-not (Test-Path -LiteralPath $DefaultRepos)) {
    throw "Default repository config is missing: $DefaultRepos"
}

$ReposConfig = Get-OllamaLauncherConfigPath 'repos.json'
Initialize-RepoConfig -ConfigFile $ReposConfig -DefaultConfigPath $DefaultRepos

$FetchScript = Resolve-LauncherHelper -Name 'fetch_models.ps1' -Required
$ModelSelectorScript = Resolve-LauncherHelper -Name 'model_selector.ps1' -SourceRelativePath 'src\OllamaLauncher\Selectors\ModelSelector.ps1'
$ContextSelectorScript = Resolve-LauncherHelper -Name 'context_selector.ps1' -SourceRelativePath 'src\OllamaLauncher\Selectors\ContextSelector.ps1'
$LocalSelectorScript = Resolve-LauncherHelper -Name 'local_selector.ps1' -SourceRelativePath 'src\OllamaLauncher\Selectors\LocalSelector.ps1'

$env:OLLAMA_LAUNCHER_CONFIG_DIR = $ConfigDirectory
$env:OLLAMA_LAUNCHER_CACHE_DIR = $CacheDirectory
$env:OLLAMA_LAUNCHER_REPOS_CONFIG = $ReposConfig
$env:OLLAMA_LAUNCHER_FETCH_SCRIPT = $FetchScript
$env:OLLAMA_LAUNCHER_MODEL_SELECTOR_SCRIPT = $ModelSelectorScript
$env:OLLAMA_LAUNCHER_CONTEXT_SELECTOR_SCRIPT = $ContextSelectorScript
$env:OLLAMA_LAUNCHER_LOCAL_SELECTOR_SCRIPT = $LocalSelectorScript
$env:OLLAMA_LAUNCHER_SETUP_DONE = '1'

if ($InitializeOnly) {
    Write-Host "ollamaLauncher initialized"
    Write-Host "AppRoot=$AppRoot"
    Write-Host "ConfigDirectory=$ConfigDirectory"
    Write-Host "CacheDirectory=$CacheDirectory"
    Write-Host "ReposConfig=$ReposConfig"
    exit 0
}

$LegacyBatch = Join-Path $ScriptRoot 'OllamaLauncher\LegacyLauncher.bat'
if (-not (Test-Path -LiteralPath $LegacyBatch)) {
    throw "Legacy launcher batch file is missing: $LegacyBatch"
}

& $LegacyBatch @LauncherArguments
if ($null -ne $global:LASTEXITCODE) {
    exit $global:LASTEXITCODE
}
exit 0
