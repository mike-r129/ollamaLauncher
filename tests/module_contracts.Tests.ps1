$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'src/OllamaLauncher'

Import-Module (Join-Path $ModuleRoot 'RepositoryConfig.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'ModelCatalog.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'Context.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'Config.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'Cache.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'Trust.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'RepositoryParse.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ModuleRoot 'Hardware.psm1') -Force -DisableNameChecking

Describe 'repository modules' {
    It 'loads and validates default repository config' {
        $repos = RepositoryConfig\New-DefaultRepoConfig -DefaultConfigPath (Join-Path $RepoRoot 'config/repos.default.json')

        ($repos.name -contains 'Ollama') | Should Be $true
        ($repos.name -contains 'HuggingFace') | Should Be $true
        { RepositoryConfig\Test-RepositoryConfig -Repos $repos -ConfigFile 'repos.default.json' } | Should Not Throw
    }

    It 'formats repository list lines with stable fields' {
        $repo = (RepositoryConfig\New-DefaultRepoConfig -DefaultConfigPath (Join-Path $RepoRoot 'config/repos.default.json') | Where-Object { $_.name -eq 'Ollama' } | Select-Object -First 1)
        $line = RepositoryConfig\ConvertTo-RepositoryListLine -Repo $repo

        $line | Should Match '^Ollama\|html\|.*\|\(none\)\|500\|ollama\.com\|1$'
    }
}

Describe 'catalog and hardware helpers' {
    It 'extracts params and estimates model size' {
        (RepositoryParse\Get-ModelParamsFromName 'llama3:8b') | Should Be '8b'
        (RepositoryParse\Get-ModelSizeEstimate '8b') | Should Match 'GB$'
    }

    It 'sorts catalog rows by size' {
        $rows = @(
            [pscustomobject]@{ Name='small'; Size='1 GB'; Params='1b'; TagCount=''; Description='' },
            [pscustomobject]@{ Name='large'; Size='8 GB'; Params='8b'; TagCount=''; Description='' }
        )

        $sorted = ModelCatalog\Sort-ModelCatalogRows -Rows $rows -Mode SIZE -Descending:$true -VramGb 0 -RamGb 0 -DiskGb 0
        $sorted[0].Name | Should Be 'large'
    }

    It 'classifies fit tiers deterministically' {
        (Hardware\Get-ModelFitTier -SizeGb 2 -VramGb 4 -RamGb 8 -DiskGb 100 -ContextLength 4096) | Should Be 0
        (Hardware\Get-ModelFitTier -SizeGb 20 -VramGb 4 -RamGb 8 -DiskGb 100 -ContextLength 4096) | Should Be 2
    }
}

Describe 'context and trust helpers' {
    It 'validates supported context lengths' {
        (Context\Test-ContextLength 4096) | Should Be $true
        (Context\Test-ContextLength 12345) | Should Be $false
    }

    It 'persists context length through the context module' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ('context-' + [guid]::NewGuid().ToString('N') + '.txt')
        try {
            Context\Set-ContextLength -Path $path -ContextLength 8192
            (Context\Get-ContextLength -Path $path -Default 4096) | Should Be 8192
        } finally {
            Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
    }

    It 'defaults trust to the built-in safe hosts' {
        $missing = Join-Path ([System.IO.Path]::GetTempPath()) ('missing-trust-' + [guid]::NewGuid().ToString('N') + '.txt')
        (Trust\Test-TrustedHost -Path $missing -HostName 'ollama.com') | Should Be $true
    }
}

Describe 'config and cache helpers' {
    It 'persists selected repository state through Config.psm1' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ('state-' + [guid]::NewGuid().ToString('N') + '.txt')
        try {
            Config\Set-SelectedRepositoryName -StatePath $path -RepositoryName 'HuggingFace'
            (Config\Get-SelectedRepositoryName -StatePath $path) | Should Be 'HuggingFace'
        } finally {
            Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
    }

    It 'performs atomic cache writes' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('cache-' + [guid]::NewGuid().ToString('N'))
        $path = Cache\Get-LauncherCacheFile -CacheDirectory $dir -Name 'models.txt'
        try {
            Cache\Write-AtomicTextFile -Path $path -Lines @('a', 'b')
            (Get-Content -Path $path -Raw).Trim() | Should Be "a`r`nb"
            (Cache\Test-CacheExpired -Path $path -MaxAgeHours 24) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
