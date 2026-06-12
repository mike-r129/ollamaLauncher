$RepoRoot = Split-Path -Parent $PSScriptRoot
$SelectorRoot = Join-Path $RepoRoot 'src/OllamaLauncher/Selectors'

# ---------------------------------------------------------------------------
# Harness helpers
# ---------------------------------------------------------------------------

# Extract named function definitions from a selector script via the AST and
# return their source so tests can define and exercise them headlessly
# without running the interactive main loop.
function Get-ScriptFunctionSource {
    param([string]$Path, [string[]]$Names)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $picked = $functions | Where-Object { $Names -contains $_.Name }
    return (($picked | ForEach-Object { $_.Extent.Text }) -join "`n")
}

# Run a selector script as a real child process with stdin redirected, the
# same shape as a headless/CI invocation. The selectors must render one frame
# to stdout and write a cancel/exit result instead of hanging or crashing.
function Invoke-HeadlessSelector {
    param([string]$ScriptPath, [string[]]$Arguments, [string]$WorkDir)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ScriptPath + '"')) + $Arguments) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if (-not $proc.WaitForExit(60000)) {
        try { $proc.Kill() } catch {}
        throw "Headless selector run timed out: $ScriptPath"
    }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function New-TestWorkDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('selector-tests-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# ---------------------------------------------------------------------------
# ModelSelector logic (extracted functions, no console interaction)
# ---------------------------------------------------------------------------
Describe 'ModelSelector rendering and paging logic' {
    $selectorPath = Join-Path $SelectorRoot 'ModelSelector.ps1'
    Invoke-Expression (Get-ScriptFunctionSource -Path $selectorPath -Names @(
        'Limit-Text', 'Get-FitColor', 'Build-NavLine', 'Build-HelpLine', 'Build-StatusLine',
        'Set-PageState', 'Update-Layout', 'Build-PageRows'
    ))

    # Script state the extracted functions read
    $installed = @{}
    $PerPage = 50
    $HasTags = '0'
    $script:vram = 8.0
    $script:ram = 16.0
    $script:disk = 100.0
    $script:contextLength = 4096
    $script:all = @(1..120 | ForEach-Object {
        [pscustomobject]@{ Name = "model$_"; Size = "$_ GB"; Params = "${_}b"; TagCount = ''; Description = "desc $_" }
    })
    $script:totalItems = 120
    $script:TotalPages = 3
    $script:Page = 1
    $script:SelIndex = 1
    $script:pageSize = 0
    $script:viewStart = 0

    It 'truncates long text with an ellipsis' {
        (Limit-Text 'abcdefghij' 8) | Should Be 'abcde...'
        (Limit-Text 'short' 10) | Should Be 'short'
        (Limit-Text $null 10) | Should Be ''
        (Limit-Text 'abc' 0) | Should Be ''
    }

    It 'classifies model fit colours with context overhead' {
        (Get-FitColor '4 GB') | Should Be 'Green'
        (Get-FitColor '12 GB') | Should Be 'Yellow'
        (Get-FitColor '60 GB') | Should Be 'Red'
        (Get-FitColor '500 GB') | Should Be 'Red'    # exceeds disk
        (Get-FitColor 'unknown') | Should Be 'Gray'
        (Get-FitColor '900 MB') | Should Be 'Green'
    }

    It 'clamps page changes and selection into the valid range' {
        Set-PageState 2 60
        $script:Page | Should Be 2
        $script:SelIndex | Should Be 60
        $script:rows.Count | Should Be 50
        $script:rows[0].Idx | Should Be 51

        Set-PageState 99 1
        $script:Page | Should Be 3
        $script:SelIndex | Should Be 101

        Set-PageState 0 7
        $script:Page | Should Be 1
        $script:SelIndex | Should Be 7
    }

    It 'shows prev/next hints only when those pages exist' {
        Set-PageState 1 1
        (Build-NavLine) | Should Not Match '\[Left/P\] Prev'
        (Build-NavLine) | Should Match '\[Right/N\] Next'

        Set-PageState 2 51
        (Build-NavLine) | Should Match '\[Left/P\] Prev'
        (Build-NavLine) | Should Match '\[Right/N\] Next'

        Set-PageState 3 101
        (Build-NavLine) | Should Match '\[Left/P\] Prev'
        (Build-NavLine) | Should Not Match '\[Right/N\] Next'
    }

    It 'only advertises the tag view when the repo supports tags' {
        Set-PageState 1 1

        $HasTags = '0'
        (Build-HelpLine) | Should Not Match 'View Tags'
        (Build-StatusLine) | Should Not Match 'Tab views tags'

        $HasTags = '1'
        (Build-HelpLine) | Should Match '\[Tab/V\] View Tags'
        (Build-StatusLine) | Should Match 'Tab views tags'
    }

    It 'reports an empty catalog instead of a selection counter' {
        $script:all = @()
        $script:totalItems = 0
        $script:TotalPages = 1
        Set-PageState 1 1
        (Build-StatusLine) | Should Match 'No models to display'
    }

    It 'gates the Tab key handler on tag support so tag views cannot recurse' {
        $text = Get-Content -Path $selectorPath -Raw -Encoding UTF8
        $text | Should Match ('''Tab''\s*\{ if \(\$HasTags -eq ''1''')
    }
}

# ---------------------------------------------------------------------------
# LocalSelector logic (extracted functions with a stubbed ollama CLI)
# ---------------------------------------------------------------------------
Describe 'LocalSelector fit estimates and metadata caching' {
    $selectorPath = Join-Path $SelectorRoot 'LocalSelector.ps1'
    Invoke-Expression (Get-ScriptFunctionSource -Path $selectorPath -Names @(
        'Get-SizeGb', 'Get-ModelMetadata', 'Calculate-KvCacheGb', 'Get-TotalMemoryEstimate',
        'Get-FitColor', 'Limit-Text', 'Build-Rows', 'Build-StatusLine'
    ))

    # Stub the ollama CLI: counts invocations so the caching contract is testable.
    $script:ollamaCalls = 0
    function ollama {
        $script:ollamaCalls++
        '  architecture        llama'
        '  num_layers          32'
        '  num_kv_head         8'
        '  embedding_length    4096'
    }

    $script:metadataCache = @{}
    $script:vram = 8.0
    $script:ram = 16.0
    $script:disk = 100.0
    $script:contextLength = 4096

    It 'parses size strings in GB, MB, and sub-GB notations' {
        (Get-SizeGb '4.7 GB') | Should Be 4.7
        [Math]::Round((Get-SizeGb '512 MB'), 2) | Should Be 0.5
        (Get-SizeGb '< 1 GB') | Should Be 0.5
        (Get-SizeGb 'huge') | Should Be (-1.0)
    }

    It 'computes the KV cache size from model metadata' {
        $meta = @{ num_layers = '32'; num_kv_head = '8'; embedding_length = '4096' }
        (Calculate-KvCacheGb $meta 4096) | Should Be 2.0
        (Calculate-KvCacheGb @{} 4096) | Should Be 0.0
    }

    It 'queries ollama show only once per model (cached for navigation)' {
        $script:ollamaCalls = 0
        $script:metadataCache = @{}

        Get-ModelMetadata 'llama3:8b' | Out-Null
        Get-ModelMetadata 'llama3:8b' | Out-Null
        Get-TotalMemoryEstimate 'llama3:8b' '4.7 GB' 4096 | Out-Null
        Get-TotalMemoryEstimate 'llama3:8b' '4.7 GB' 8192 | Out-Null

        $script:ollamaCalls | Should Be 1
    }

    It 'builds one precomputed row per model with fit labels' {
        $script:metadataCache = @{}
        $script:models = @(
            [pscustomobject]@{ Name = 'llama3:8b'; Size = '4.7 GB'; Params = '8b' },
            [pscustomobject]@{ Name = 'big:70b';   Size = '40 GB';  Params = '70b' }
        )

        $script:ollamaCalls = 0
        Build-Rows

        $script:rows.Count | Should Be 2
        $script:rows[0].Fit | Should Be 'Fits VRAM'
        $script:rows[0].Color | Should Be 'Green'
        $script:rows[1].Fit | Should Be 'Too large'
        $script:rows[1].Color | Should Be 'Red'
        # one ollama show per model, never more
        $script:ollamaCalls | Should Be 2
    }

    It 'navigating rows does not spawn further ollama processes' {
        # Build-Rows above already cached everything; a re-render of every row
        # must not invoke ollama again.
        $script:ollamaCalls = 0
        Build-Rows
        $script:ollamaCalls | Should Be 0
    }

    It 'formats the KV cache delta with a correct sign for smaller contexts' {
        $text = Get-Content -Path (Join-Path $SelectorRoot 'LocalSelector.ps1') -Raw -Encoding UTF8
        # regression: shrinking the context used to render as "(+-0.5 GB KV cache)"
        $text | Should Match '\(-\{0:N1\} GB KV cache\)'
        $text | Should Not Match "if \(\`?\$kvDelta -ne 0\)"
    }
}

# ---------------------------------------------------------------------------
# Headless end-to-end runs (stdin redirected, like CI)
# ---------------------------------------------------------------------------
Describe 'headless selector runs render a frame and write a result' {
    It 'ModelSelector renders the full catalog frame and cancels cleanly' {
        $work = New-TestWorkDir
        try {
            $sorted = Join-Path $work 'sorted.txt'
            $local = Join-Path $work 'local.txt'
            $result = Join-Path $work 'result.txt'
            [System.IO.File]::WriteAllLines($sorted, @(
                'llama3|4.7 GB|8b|5 Tags|Meta Llama 3',
                'qwen3|2.0 GB|3b|7 Tags|Qwen model'
            ))
            [System.IO.File]::WriteAllLines($local, @('llama3'))

            $run = Invoke-HeadlessSelector -ScriptPath (Join-Path $SelectorRoot 'ModelSelector.ps1') -WorkDir $work -Arguments @(
                '-SortedFile', ('"' + $sorted + '"'),
                '-LocalFile', ('"' + $local + '"'),
                '-ResultFile', ('"' + $result + '"'),
                '-Repo', 'Ollama',
                '-HasTags', '1'
            )

            $run.ExitCode | Should Be 0
            # The frame must include the model rows even without a console
            # (regression: unguarded [Console]::CursorTop aborted rendering).
            $run.StdOut | Should Match 'llama3'
            $run.StdOut | Should Match 'qwen3'
            # the description column may truncate, so only require the prefix
            $run.StdOut | Should Match '\[Installed'
            $run.StdOut | Should Match 'Showing Models \(Page 1/1\)'

            $lines = Get-Content -Path $result
            $lines[0] | Should Be 'CMD|C'
            ($lines -contains 'SEL_INDEX=1') | Should Be $true
            ($lines -contains 'PAGE=1') | Should Be $true
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'LocalSelector lists installed models via a stubbed ollama CLI' {
        $work = New-TestWorkDir
        $savedPath = $env:Path
        try {
            $fakeBin = Join-Path $work 'bin'
            New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
            [System.IO.File]::WriteAllLines((Join-Path $fakeBin 'ollama.cmd'), @(
                '@echo off',
                'if "%~1"=="list" (',
                '  echo NAME                ID              SIZE      MODIFIED',
                '  echo llama3:8b           111111111111    4.7 GB    2 days ago',
                '  echo tinymodel:1b        222222222222    500 MB    3 weeks ago',
                ')',
                'if "%~1"=="show" (',
                '  echo   num_layers          32',
                '  echo   num_kv_head         8',
                '  echo   embedding_length    4096',
                ')',
                'exit /b 0'
            ))
            $env:Path = $fakeBin + ';' + $env:Path

            $local = Join-Path $work 'local.txt'
            $result = Join-Path $work 'result.txt'
            $run = Invoke-HeadlessSelector -ScriptPath (Join-Path $SelectorRoot 'LocalSelector.ps1') -WorkDir $work -Arguments @(
                '-LocalFile', ('"' + $local + '"'),
                '-ResultFile', ('"' + $result + '"'),
                '-VramGb', '8', '-RamGb', '16', '-DiskGb', '100',
                '-ContextLength', '4096',
                '-CurrentRepo', 'Ollama'
            )

            $run.ExitCode | Should Be 0
            $run.StdOut | Should Match 'llama3:8b'
            $run.StdOut | Should Match 'tinymodel:1b'
            $run.StdOut | Should Match 'Fits VRAM'
            $run.StdOut | Should Match '\[E\] Repository \(Ollama\)'

            # Handoff file for the repo browser's [Installed] markers
            $localNames = Get-Content -Path $local
            ($localNames -contains 'llama3:8b') | Should Be $true

            $lines = Get-Content -Path $result
            $lines[0] | Should Be 'CMD|X'
            ($lines -contains 'CTX=4096') | Should Be $true
        } finally {
            $env:Path = $savedPath
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ContextSelector renders all options and cancels cleanly' {
        $work = New-TestWorkDir
        try {
            $result = Join-Path $work 'result.txt'
            $run = Invoke-HeadlessSelector -ScriptPath (Join-Path $SelectorRoot 'ContextSelector.ps1') -WorkDir $work -Arguments @(
                '-CurrentContext', '8192',
                '-ResultFile', ('"' + $result + '"')
            )

            $run.ExitCode | Should Be 0
            $run.StdOut | Should Match 'Current context length: 8192 tokens'
            foreach ($label in @('4K', '8K', '16K', '32K', '64K', '128K', '256K')) {
                $run.StdOut | Should Match ('\b' + $label + '\b')
            }

            (Get-Content -Path $result -Raw).Trim() | Should Be 'CANCEL'
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Repository list line round-trip (field-shift regression)
# ---------------------------------------------------------------------------
Describe 'repository list lines stay parseable by batch for /f' {
    Import-Module (Join-Path $RepoRoot 'src/OllamaLauncher/RepositoryConfig.psm1') -Force -DisableNameChecking

    It 'never emits an empty field (consecutive | would shift batch tokens)' {
        $bare = [pscustomobject]@{ name = 'Bare'; baseUrl = 'https://example.test/api' }
        $line = RepositoryConfig\ConvertTo-RepositoryListLine -Repo $bare

        $fields = $line -split '\|'
        $fields.Count | Should Be 7
        foreach ($field in $fields) {
            [string]::IsNullOrEmpty($field) | Should Be $false
        }
        $fields[2] | Should Be '(none)'   # description sentinel
    }

    It 'keeps the documented field order for fully populated repos' {
        $repo = [pscustomobject]@{
            name = 'Full'; baseUrl = 'https://example.test/api'; format = 'json'
            description = 'A repo'; pullPrefix = 'x.co/'; defaultLimit = 250
            tagFetch = [pscustomobject]@{ type = 't' }
        }
        $line = RepositoryConfig\ConvertTo-RepositoryListLine -Repo $repo
        $line | Should Be 'Full|json|A repo|x.co/|250|example.test|1'
    }
}

# ---------------------------------------------------------------------------
# Batch launcher polish regressions (static pins)
# ---------------------------------------------------------------------------
Describe 'batch launcher polish contracts' {
    $batchText = Get-Content -Path (Join-Path $RepoRoot 'src/OllamaLauncher/LegacyLauncher.bat') -Raw -Encoding UTF8

    It 'rebuilds the model array from the local list cache before removal' {
        # regression: in the selector flow count=0, so removal never matched
        $batchText | Should Match '(?s):remove_model.*?LOCAL_MODELS_LIST.*?set /p remove_choice'
    }

    It 'suppresses every timeout countdown so it cannot paint over the UI' {
        $bare = [regex]::Matches($batchText, '(?m)timeout /t \d+ /nobreak\s*$')
        $bare.Count | Should Be 0
    }

    It 'maps the (none) sentinels for description and host back to empty' {
        $batchText | Should Match 'if /i "%%c"=="\(none\)" set "repo_desc'
        $batchText | Should Match 'if /i "%%f"=="\(none\)" set "repo_host'
        $batchText | Should Match 'if /i "!CURRENT_REPO_HOST!"=="\(none\)" set "CURRENT_REPO_HOST="'
    }

    It 'prints repo descriptions with echo( so empty values stay blank' {
        # bare "echo  <empty>" would print "ECHO is off." into the repo list
        $batchText | Should Match 'echo\(\s+!repo_desc\[%%i\]!'
    }
}
