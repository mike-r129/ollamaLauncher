param(
    [int]$Skip=0,
    [int]$Limit=0,
    [switch]$Append,
    [string]$CacheFile,
    [switch]$Local,
    [string]$Repo='Ollama',
    [string]$ConfigFile,
    [switch]$ListRepos,
    [switch]$ListSortFields,
    [switch]$ValidatePull,
    [string]$ModelName,
    [switch]$DetectHardware,
    [switch]$FetchTags,
    [switch]$ExpandTags
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = (Get-Location).Path }

$PathsModule = Join-Path $ScriptRoot 'src\OllamaLauncher\Paths.psm1'
if (Test-Path -LiteralPath $PathsModule) {
    Import-Module $PathsModule -Force -DisableNameChecking
}

$ModuleRoot = Join-Path $ScriptRoot 'src\OllamaLauncher'
foreach ($moduleName in @(
    'RepositoryConfig.psm1',
    'RepositoryFetch.psm1',
    'ModelCatalog.psm1',
    'Cache.psm1',
    'RepositoryParse.psm1',
    'Hardware.psm1'
)) {
    $modulePath = Join-Path $ModuleRoot $moduleName
    if (Test-Path -LiteralPath $modulePath) {
        Import-Module $modulePath -Force -DisableNameChecking
    }
}

function Get-LauncherFallbackConfigDirectory {
    $base = $env:APPDATA
    if (-not $base) {
        return Join-Path ([System.IO.Path]::GetTempPath()) 'ollamaLauncher'
    }
    return Join-Path $base 'ollamaLauncher'
}

function Get-LauncherFallbackCacheDirectory {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = [System.IO.Path]::GetTempPath() }
    return Join-Path (Join-Path $base 'ollamaLauncher') 'Cache'
}

function Get-LauncherConfigPath {
    param([string]$Name)

    if (Get-Command Get-OllamaLauncherConfigPath -ErrorAction SilentlyContinue) {
        return Get-OllamaLauncherConfigPath -Name $Name
    }
    return Join-Path (Get-LauncherFallbackConfigDirectory) $Name
}

function Get-LauncherCachePath {
    param([string]$Name)

    if (Get-Command Get-OllamaLauncherCachePath -ErrorAction SilentlyContinue) {
        return Get-OllamaLauncherCachePath -Name $Name
    }
    return Join-Path (Get-LauncherFallbackCacheDirectory) $Name
}

function Get-LauncherDefaultReposPath {
    if (Get-Command Get-OllamaLauncherDefaultReposPath -ErrorAction SilentlyContinue) {
        return Get-OllamaLauncherDefaultReposPath
    }
    return Join-Path (Join-Path $ScriptRoot 'config') 'repos.default.json'
}

function Initialize-ParentDirectory {
    param([string]$Path)

    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-CacheLines {
    param([string]$Path, [string[]]$Lines, [switch]$Append)

    Initialize-ParentDirectory $Path
    if ($Append) { [System.IO.File]::AppendAllLines($Path, $Lines) }
    elseif (Get-Command Write-AtomicTextFile -ErrorAction SilentlyContinue) {
        Write-AtomicTextFile -Path $Path -Lines $Lines
    } else {
        [System.IO.File]::WriteAllLines($Path, $Lines)
    }
}

if (-not $ConfigFile) {
    $ConfigFile = Get-LauncherConfigPath 'repos.json'
}

try {
    $repos = RepositoryConfig\Get-RepositoryConfig -ConfigFile $ConfigFile -DefaultConfigPath (Get-LauncherDefaultReposPath)
} catch {
    Write-Error ([string]$_.Exception.Message)
    exit 1
}

if ($ListRepos) {
    if (-not $CacheFile) { $CacheFile = Get-LauncherCachePath 'repos_list.txt' }
    $lines = foreach ($r in $repos) { RepositoryConfig\ConvertTo-RepositoryListLine -Repo $r }
    Write-CacheLines -Path $CacheFile -Lines $lines
    foreach ($line in $lines) { Write-Host $line }
    exit 0
}

if ($ListSortFields) {
    $r = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $r) { Write-Error "Repository '$Repo' not found."; exit 1 }
    if (-not $CacheFile) { $CacheFile = Get-LauncherCachePath 'sort_fields.txt' }
    $lines = RepositoryConfig\Get-RepositorySortFieldLines -Repo $r
    Write-CacheLines -Path $CacheFile -Lines $lines
    foreach ($line in $lines) { Write-Host $line }
    exit 0
}

if ($ValidatePull) {
    $r = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $r) { Write-Error "Repository '$Repo' not found."; exit 1 }
    try {
        $null = RepositoryConfig\Test-RepositoryPullTarget -Repo $r -RepoName $Repo -ModelName $ModelName
    } catch {
        [Console]::Error.WriteLine([string]$_.Exception.Message)
        exit 1
    }
    Write-Host 'OK'
    exit 0
}

if ($DetectHardware) {
    if (-not $CacheFile) { $CacheFile = Get-LauncherCachePath 'hardware.txt' }
    $line = Hardware\Convert-HardwareInfoToLine -HardwareInfo (Hardware\Get-OllamaLauncherHardwareInfo)
    Write-CacheLines -Path $CacheFile -Lines @($line)
    Write-Host $line
    exit 0
}

if (-not $CacheFile) {
    $CacheFile = Get-LauncherCachePath 'models_cache.txt'
}

if ($FetchTags) {
    if (-not $ModelName) { Write-Error '-ModelName is required for -FetchTags.'; exit 1 }
    $r = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $r) { Write-Error "Repository '$Repo' not found."; exit 1 }
    $tfCfg = RepositoryParse\Get-RepoProperty $r 'tagFetch' $null
    $repoHost = ''
    try { $repoHost = ([uri]$r.baseUrl).Host } catch { $repoHost = '' }
    if (-not $tfCfg -and $repoHost -ne 'ollama.com') {
        Write-Error "Tag listing is not configured for repository '$Repo' (add a 'tagFetch' block to repos.json)."
        exit 1
    }

    $base = ($ModelName -split ':')[0].Trim()
    if ($base.Length -eq 0)   { Write-Error 'Model base name is empty.'; exit 1 }
    if ($base.Length -gt 256) { Write-Error 'Model base name too long.'; exit 1 }
    if ($base -notmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$') {
        Write-Error "Invalid model base name '$base' (only A-Z, 0-9, dot, underscore, hyphen, and a single '/' allowed)."
        exit 1
    }

    Write-Host "Fetching tags for '$base' from $($r.name)..." -ForegroundColor Gray
    $tags = RepositoryFetch\Get-RepoTags -Repo $r -Base $base
    if (-not $tags -or $tags.Count -eq 0) {
        Write-Error "No tags found for '$base'."
        exit 1
    }
    $lines = foreach ($t in $tags) { "$($t.Name)|$($t.SizeGB)|$($t.Params)|$($t.Description)" }
    Write-CacheLines -Path $CacheFile -Lines $lines
    Write-Host "Wrote $($tags.Count) tags to $CacheFile" -ForegroundColor Cyan
    exit 0
}

if ($Local) {
    try {
        $models = ModelCatalog\Get-InstalledOllamaModels
        if ($models.Count -eq 0) { exit 1 }
        Write-CacheLines -Path $CacheFile -Lines @($models.Name)
        try { $width = $Host.UI.RawUI.WindowSize.Width } catch { $width = 80 }
        if ($width -lt 60) { $width = 60 }
        $descWidth = $width - 53
        if ($descWidth -lt 5) { $descWidth = 5 }
        Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f 'Num','Model Name','Size','Params','Description')
        Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f ('-'*4),('-'*25),('-'*10),('-'*8),('-'*$descWidth))
        $index = 0
        foreach ($m in $models) {
            $index++
            $name = $m.Name
            if ($name.Length -gt 25) { $name = $name.Substring(0,22) + '...' }
            Write-Host ('{0,3}. {1,-25} {2,-10} {3,-8}  {4}' -f $index,$name,$m.Size,$m.Params,$m.Description)
        }
        exit 0
    } catch {
        Write-Error $_
        exit 1
    }
}

$activeRepo = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
if (-not $activeRepo) {
    Write-Error "Repository '$Repo' not found in '$ConfigFile'. Available: $($repos.name -join ', ')"
    exit 1
}

if ($Limit -le 0) {
    $Limit = [int](RepositoryParse\Get-RepoProperty $activeRepo 'defaultLimit' 100)
}

Write-Host "Using repository: $($activeRepo.name) [$($activeRepo.format)]  (limit=$Limit, skip=$Skip, expand=$ExpandTags)" -ForegroundColor Cyan
$models = RepositoryFetch\Invoke-RepoFetch -Repo $activeRepo -Skip $Skip -Limit $Limit -ExpandTags ([bool]$ExpandTags)

$lines = foreach ($model in $models) {
    $tagCount = ''
    if ($model.PSObject.Properties['TagCount']) { $tagCount = [string]$model.TagCount }
    "$($model.Name)|$($model.SizeGB)|$($model.Params)|$tagCount|$($model.Description)"
}
Write-CacheLines -Path $CacheFile -Lines $lines -Append:$Append
Write-Host "Successfully fetched $($models.Count) models from $($activeRepo.name)."
