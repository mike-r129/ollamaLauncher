$RepoRoot = Split-Path -Parent $PSScriptRoot
$FetchScript = Join-Path $RepoRoot 'fetch_models.ps1'

function New-OllamaLauncherTestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ollamaLauncher-tests-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-OllamaLauncherTestDirectory {
    param([string]$Path)

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-ProcessArgument {
    param([string]$Argument)

    if ($null -eq $Argument) {
        return '""'
    }

    $escaped = $Argument.Replace('"', '\"')
    if ($escaped -match '[\s"]') {
        return '"' + $escaped + '"'
    }

    return $escaped
}

function Invoke-FetchModels {
    param([string[]]$Arguments)

    $powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $powershell) {
        $powershell = Get-Command powershell -ErrorAction Stop
    }

    $fileName = $powershell.Source
    if (-not $fileName) {
        $fileName = $powershell.Definition
    }

    $allArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $FetchScript) + $Arguments

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $fileName
    $psi.Arguments = (($allArguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
        Arguments = $psi.Arguments
    }
}

function Initialize-DefaultRepoConfig {
    param([string]$Directory)

    $config = Join-Path $Directory 'repos.json'
    $repoList = Join-Path $Directory 'repos_list.txt'
    $result = Invoke-FetchModels @('-ListRepos', '-ConfigFile', $config, '-CacheFile', $repoList)

    if ($result.ExitCode -ne 0) {
        throw "Failed to initialize default repo config. stdout: $($result.StdOut) stderr: $($result.StdErr)"
    }

    return $config
}

Describe 'fetch_models.ps1 -ListRepos' {
    It 'materializes the default repository config and pipe-delimited repo list' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Join-Path $dir 'repos.json'
            $repoList = Join-Path $dir 'repos_list.txt'
            $result = Invoke-FetchModels @('-ListRepos', '-ConfigFile', $config, '-CacheFile', $repoList)

            $result.ExitCode | Should Be 0
            (Test-Path -LiteralPath $config) | Should Be $true
            (Test-Path -LiteralPath $repoList) | Should Be $true

            $lines = @(Get-Content -Path $repoList -Encoding UTF8)
            ($lines.Count -ge 2) | Should Be $true
            (($lines | Where-Object { $_ -match '^Ollama\|html\|.*\|\(none\)\|500\|ollama\.com\|1$' }).Count) | Should Be 1
            (($lines | Where-Object { $_ -match '^HuggingFace\|json\|.*\|hf\.co/\|500\|huggingface\.co\|1$' }).Count) | Should Be 1

            $repos = @(Get-Content -Path $config -Raw -Encoding UTF8 | ConvertFrom-Json)
            ($repos.name -contains 'Ollama') | Should Be $true
            ($repos.name -contains 'HuggingFace') | Should Be $true
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }

    It 'rejects repository configs with non-https base URLs' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Join-Path $dir 'repos.json'
            $repoList = Join-Path $dir 'repos_list.txt'
            $badRepo = [PSCustomObject]@{
                name = 'BadRepo'
                description = 'Intentional bad config for tests'
                pullPrefix = ''
                defaultLimit = 1
                format = 'json'
                baseUrl = 'http://example.test/api/models'
                items = [PSCustomObject]@{ path = '$' }
                fields = [PSCustomObject]@{ name = 'id' }
            }
            @($badRepo) | ConvertTo-Json -Depth 5 | Set-Content -Path $config -Encoding UTF8

            $result = Invoke-FetchModels @('-ListRepos', '-ConfigFile', $config, '-CacheFile', $repoList)

            $result.ExitCode | Should Not Be 0
            ($result.StdErr + $result.StdOut) | Should Match 'non-https baseUrl'
            (Test-Path -LiteralPath $repoList) | Should Be $false
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }
}

Describe 'fetch_models.ps1 -ListSortFields' {
    It 'lists configured HuggingFace sort fields' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Initialize-DefaultRepoConfig $dir
            $sortFields = Join-Path $dir 'sort_fields.txt'

            $result = Invoke-FetchModels @('-ListSortFields', '-Repo', 'HuggingFace', '-ConfigFile', $config, '-CacheFile', $sortFields)

            $result.ExitCode | Should Be 0
            (Test-Path -LiteralPath $sortFields) | Should Be $true

            $lines = @(Get-Content -Path $sortFields -Encoding UTF8)
            ($lines -contains 'Downloads|Downloads:\s*(\d+)|1') | Should Be $true
            ($lines -contains 'Likes|Likes:\s*(\d+)|1') | Should Be $true
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }

    It 'fails for an unknown repository' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Initialize-DefaultRepoConfig $dir
            $sortFields = Join-Path $dir 'sort_fields.txt'

            $result = Invoke-FetchModels @('-ListSortFields', '-Repo', 'NoSuchRepo', '-ConfigFile', $config, '-CacheFile', $sortFields)

            $result.ExitCode | Should Not Be 0
            ($result.StdErr + $result.StdOut) | Should Match "Repository 'NoSuchRepo' not found"
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }
}

Describe 'fetch_models.ps1 -ValidatePull' {
    It 'accepts safe Ollama model names' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Initialize-DefaultRepoConfig $dir

            $plain = Invoke-FetchModels @('-ValidatePull', '-Repo', 'Ollama', '-ModelName', 'llama3:8b', '-ConfigFile', $config)
            $namespaced = Invoke-FetchModels @('-ValidatePull', '-Repo', 'Ollama', '-ModelName', 'library/llama3:latest', '-ConfigFile', $config)

            $plain.ExitCode | Should Be 0
            $plain.StdOut | Should Match 'OK'
            $namespaced.ExitCode | Should Be 0
            $namespaced.StdOut | Should Match 'OK'
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }

    It 'rejects unsafe Ollama model names' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Initialize-DefaultRepoConfig $dir

            $metachar = Invoke-FetchModels @('-ValidatePull', '-Repo', 'Ollama', '-ModelName', 'llama3:8b;calc', '-ConfigFile', $config)
            $remoteHost = Invoke-FetchModels @('-ValidatePull', '-Repo', 'Ollama', '-ModelName', 'registry.example.com/model:latest', '-ConfigFile', $config)

            $metachar.ExitCode | Should Not Be 0
            ($metachar.StdErr + $metachar.StdOut) | Should Match 'shell metacharacters'
            $remoteHost.ExitCode | Should Not Be 0
            ($remoteHost.StdErr + $remoteHost.StdOut) | Should Match 'remote registry host'
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }

    It 'accepts safe HuggingFace pull targets with the required prefix' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Initialize-DefaultRepoConfig $dir

            $result = Invoke-FetchModels @('-ValidatePull', '-Repo', 'HuggingFace', '-ModelName', 'hf.co/meta-llama/Llama-3-8B:Q4_K_M', '-ConfigFile', $config)

            $result.ExitCode | Should Be 0
            $result.StdOut | Should Match 'OK'
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }

    It 'rejects HuggingFace pull targets without the required shape' {
        $dir = New-OllamaLauncherTestDirectory

        try {
            $config = Initialize-DefaultRepoConfig $dir

            $missingPrefix = Invoke-FetchModels @('-ValidatePull', '-Repo', 'HuggingFace', '-ModelName', 'meta-llama/Llama-3-8B:Q4_K_M', '-ConfigFile', $config)
            $missingRepo = Invoke-FetchModels @('-ValidatePull', '-Repo', 'HuggingFace', '-ModelName', 'hf.co/meta-llama', '-ConfigFile', $config)

            $missingPrefix.ExitCode | Should Not Be 0
            ($missingPrefix.StdErr + $missingPrefix.StdOut) | Should Match 'must start with required prefix'
            $missingRepo.ExitCode | Should Not Be 0
            ($missingRepo.StdErr + $missingRepo.StdOut) | Should Match '<owner>/<model>'
        }
        finally {
            Remove-OllamaLauncherTestDirectory $dir
        }
    }
}
