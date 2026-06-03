$RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoFileText {
    param([string]$RelativePath)

    Get-Content -Path (Join-Path $RepoRoot $RelativePath) -Raw -Encoding UTF8
}

Describe 'PowerShell script syntax' {
    $scripts = @(
        'fetch_models.ps1',
        'model_selector.ps1',
        'local_selector.ps1',
        'context_selector.ps1',
        'ollama_wrapper.ps1'
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
            File = 'model_selector.ps1'
            Parameters = @('SortedFile', 'LocalFile', 'Page', 'PerPage', 'TotalPages', 'SelIndex', 'Repo', 'SearchTerm', 'SortInfo', 'HwFilterLabel', 'VramGb', 'RamGb', 'DiskGb', 'ContextLength', 'HasTags', 'ResultFile')
        },
        [PSCustomObject]@{
            File = 'local_selector.ps1'
            Parameters = @('LocalFile', 'VramGb', 'RamGb', 'DiskGb', 'ContextLength', 'CurrentRepo', 'ResultFile')
        },
        [PSCustomObject]@{
            File = 'context_selector.ps1'
            Parameters = @('CurrentContext', 'ResultFile')
        },
        [PSCustomObject]@{
            File = 'ollama_wrapper.ps1'
            Parameters = @('Command', 'ModelName', 'ContextLength', 'Pull', 'Run')
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

    foreach ($switchName in @('ListRepos', 'ListSortFields', 'ValidatePull', 'DetectHardware', 'FetchTags')) {
        $caseSwitch = $switchName

        It "routes through fetch_models.ps1 -$caseSwitch" {
            $pattern = '-' + [Regex]::Escape($caseSwitch) + '\b'
            $batchText | Should Match $pattern
        }
    }

    It 'routes pull and run commands through ollama_wrapper.ps1' {
        $batchText | Should Match 'ollama_wrapper\.ps1'
    }
}
