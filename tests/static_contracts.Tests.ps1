$RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoFileText {
    param([string]$RelativePath)

    Get-Content -Path (Join-Path $RepoRoot $RelativePath) -Raw -Encoding UTF8
}

Describe 'PowerShell script syntax' {
    $scripts = @(
        'src/OllamaLauncher.ps1',
        'fetch_models.ps1',
        'src/OllamaLauncher/SortCatalog.ps1',
        'src/OllamaLauncher/ContextValue.ps1',
        'src/OllamaLauncher/StateValue.ps1',
        'src/OllamaLauncher/TrustHost.ps1',
        'scripts/Install.ps1',
        'scripts/Uninstall.ps1',
        'scripts/SmokeTest.ps1',
        'src/OllamaLauncher/Selectors/ModelSelector.ps1',
        'src/OllamaLauncher/Selectors/LocalSelector.ps1',
        'src/OllamaLauncher/Selectors/ContextSelector.ps1',
        'ollama_wrapper.ps1',
        'src/OllamaLauncher/Paths.psm1',
        'src/OllamaLauncher/RepositoryConfig.psm1',
        'src/OllamaLauncher/RepositoryParse.psm1',
        'src/OllamaLauncher/RepositoryFetch.psm1',
        'src/OllamaLauncher/Hardware.psm1',
        'src/OllamaLauncher/ModelCatalog.psm1',
        'src/OllamaLauncher/OllamaCli.psm1',
        'src/OllamaLauncher/Context.psm1',
        'src/OllamaLauncher/Cache.psm1',
        'src/OllamaLauncher/Config.psm1',
        'src/OllamaLauncher/Trust.psm1',
        'src/OllamaLauncher/Ui.psm1'
    )

    foreach ($relativePath in $scripts) {
        $caseName = $relativePath
        $scriptPath = Join-Path $RepoRoot $relativePath

        It "$caseName parses without errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null

            if ($errors -and $errors.Count -gt 0) {
                Write-Host (($errors | ForEach-Object { $_.Message }) -join "`n")
            }

            @($errors).Count | Should Be 0
        }
    }
}

Describe 'fetch_models.ps1 public parameter contract' {
    $fetchText = Get-RepoFileText 'fetch_models.ps1'

    foreach ($switchName in @('Append', 'Local', 'ListRepos', 'ListSortFields', 'ValidatePull', 'DetectHardware', 'FetchTags', 'ExpandTags')) {
        $caseSwitch = $switchName

        It "declares -$caseSwitch" {
            $pattern = '\[switch\]\$' + [Regex]::Escape($caseSwitch) + '\b'
            $fetchText | Should Match $pattern
        }
    }

    foreach ($parameterName in @('CacheFile', 'Repo', 'ConfigFile', 'ModelName')) {
        $caseParameter = $parameterName

        It "declares string parameter -$caseParameter" {
            $pattern = '\[string\]\$' + [Regex]::Escape($caseParameter) + '\b'
            $fetchText | Should Match $pattern
        }
    }

    foreach ($parameterName in @('Skip', 'Limit')) {
        $caseParameter = $parameterName

        It "declares int parameter -$caseParameter" {
            $pattern = '\[int\]\$' + [Regex]::Escape($caseParameter) + '\b'
            $fetchText | Should Match $pattern
        }
    }
}

Describe 'selector script parameter contracts' {
    $contracts = @(
        [PSCustomObject]@{
            File = 'src/OllamaLauncher/Selectors/ModelSelector.ps1'
            Parameters = @('SortedFile', 'LocalFile', 'Page', 'PerPage', 'TotalPages', 'SelIndex', 'Repo', 'SearchTerm', 'SortInfo', 'HwFilterLabel', 'VramGb', 'RamGb', 'DiskGb', 'ContextLength', 'HasTags', 'ResultFile')
        },
        [PSCustomObject]@{
            File = 'src/OllamaLauncher/Selectors/LocalSelector.ps1'
            Parameters = @('LocalFile', 'VramGb', 'RamGb', 'DiskGb', 'ContextLength', 'CurrentRepo', 'ResultFile')
        },
        [PSCustomObject]@{
            File = 'src/OllamaLauncher/Selectors/ContextSelector.ps1'
            Parameters = @('CurrentContext', 'ResultFile')
        },
        [PSCustomObject]@{
            File = 'ollama_wrapper.ps1'
            Parameters = @('ModelName', 'ContextLength', 'Pull', 'Run')
        }
    )

    foreach ($contract in $contracts) {
        $caseFile = $contract.File
        $text = Get-RepoFileText $contract.File

        foreach ($parameter in $contract.Parameters) {
            $caseParameter = $parameter

            It "$caseFile declares -$caseParameter" {
                $pattern = '\$' + [Regex]::Escape($caseParameter) + '\b'
                $text | Should Match $pattern
            }
        }
    }
}

Describe 'batch launcher integration contract' {
    $batchText = Get-RepoFileText 'ollamaLauncher.bat'
    $legacyBatchText = Get-RepoFileText 'src/OllamaLauncher/LegacyLauncher.bat'

    It 'is a thin shim through the PowerShell entrypoint' {
        $batchText | Should Match 'src\\OllamaLauncher\.ps1'
        $batchText | Should Not Match ':start'
        $batchText | Should Not Match 'fetch_models\.ps1'
    }

    It 'keeps transitional launcher logic in the legacy batch implementation' {
        $legacyBatchText | Should Match ':start'
        $legacyBatchText | Should Match 'OLLAMA_LAUNCHER_SETUP_DONE'
        $legacyBatchText | Should Match 'OLLAMA_LAUNCHER_APP_ROOT'
        $legacyBatchText | Should Match 'src\\OllamaLauncher\\Selectors\\ModelSelector\.ps1'
    }

    foreach ($switchName in @('ListRepos', 'ListSortFields', 'ValidatePull', 'DetectHardware', 'FetchTags')) {
        $caseSwitch = $switchName

        It "routes through fetch_models.ps1 -$caseSwitch" {
            $pattern = '-' + [Regex]::Escape($caseSwitch) + '\b'
            $legacyBatchText | Should Match $pattern
        }
    }

    It 'routes pull and run commands through ollama_wrapper.ps1' {
        $legacyBatchText | Should Match 'ollama_wrapper\.ps1'
    }

    It 'routes state, context, and trust persistence through module bridges' {
        $legacyBatchText | Should Match 'ContextValue\.ps1'
        $legacyBatchText | Should Match 'StateValue\.ps1'
        $legacyBatchText | Should Match 'TrustHost\.ps1'
    }

    It 'routes cache expiry through Cache.psm1' {
        $legacyBatchText | Should Match 'Test-CacheExpired'
    }

    It 'uses LocalAppData cache root for generated launcher files' {
        $legacyBatchText | Should Match 'OLLAMA_LAUNCHER_CACHE_DIR'
        $legacyBatchText | Should Match 'MODELS_CACHE=%CACHE_OLLAMA%\\ollama-models-'
        $legacyBatchText | Should Match 'REPOS_LIST=%CACHE_OLLAMA%\\repos_list\.txt'
    }

    It 'does not delete source-adjacent fetch_models.ps1 during setup' {
        $legacyBatchText | Should Not Match 'del\s+".*fetch_models\.ps1"'
        $legacyBatchText | Should Match 'FETCH_MODELS_SCRIPT=%APP_ROOT%\\fetch_models\.ps1'
    }
}

Describe 'ollama wrapper module integration' {
    $wrapperText = Get-RepoFileText 'ollama_wrapper.ps1'

    It 'delegates pull and run to OllamaCli with a direct ollama fallback' {
        $wrapperText | Should Match 'OllamaCli\.psm1'
        $wrapperText | Should Match 'Invoke-OllamaPull'
        $wrapperText | Should Match 'Invoke-OllamaRun'
    }

    It 'streams ollama output directly instead of redirecting it to files' {
        $wrapperText | Should Not Match 'Start-Process'
        $wrapperText | Should Not Match 'RedirectStandardOutput'
    }

    It 'still honors the launcher context length contract' {
        $wrapperText | Should Match 'OLLAMA_CONTEXT_LENGTH'
    }
}

Describe 'default repository config artifact' {
    It 'is valid JSON with the expected default repositories' {
        $configPath = Join-Path $RepoRoot 'config/repos.default.json'
        (Test-Path -LiteralPath $configPath) | Should Be $true

        $repos = @(Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        ($repos.name -contains 'Ollama') | Should Be $true
        ($repos.name -contains 'HuggingFace') | Should Be $true
    }
}

Describe 'release hygiene artifacts' {
    It 'includes installer, uninstaller, smoke test, and release checklist' {
        foreach ($relativePath in @('scripts/Install.ps1', 'scripts/Uninstall.ps1', 'scripts/SmokeTest.ps1', 'RELEASE_CHECKLIST.md')) {
            (Test-Path -LiteralPath (Join-Path $RepoRoot $relativePath)) | Should Be $true
        }
    }
}
