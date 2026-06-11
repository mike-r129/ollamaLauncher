function New-DefaultRepoConfig {
    param([string]$DefaultConfigPath)

    if (-not (Test-Path -LiteralPath $DefaultConfigPath)) {
        throw "Default repository config is missing: $DefaultConfigPath"
    }

    $defaults = Get-Content -Path $DefaultConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($defaults -isnot [System.Array]) { $defaults = @($defaults) }
    return $defaults
}

function Initialize-RepoConfig {
    param(
        [string]$ConfigFile,
        [string]$DefaultConfigPath
    )

    $dir = Split-Path -Parent $ConfigFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        New-DefaultRepoConfig -DefaultConfigPath $DefaultConfigPath |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $ConfigFile -Encoding UTF8
    }
}

function Get-RepositoryConfig {
    param(
        [string]$ConfigFile,
        [string]$DefaultConfigPath
    )

    Initialize-RepoConfig -ConfigFile $ConfigFile -DefaultConfigPath $DefaultConfigPath
    try {
        $repos = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($repos -isnot [System.Array]) { $repos = @($repos) }
        Test-RepositoryConfig -Repos $repos -ConfigFile $ConfigFile
        return $repos
    } catch {
        throw "Failed to parse repo config '$ConfigFile': $_"
    }
}

function Test-RepositoryConfig {
    param($Repos, [string]$ConfigFile)

    $maxRegexLen = 2000
    foreach ($r in $Repos) {
        $url = ''
        if ($r.PSObject.Properties['baseUrl']) { $url = [string]$r.baseUrl }
        if (-not $url -or $url -notmatch '^https://') {
            throw "Repo '$($r.name)' has missing or non-https baseUrl ('$url'). Edit '$ConfigFile' to fix."
        }
        try { $null = [uri]$url } catch {
            throw "Repo '$($r.name)' baseUrl is not a valid URI: '$url'"
        }

        if ($r.PSObject.Properties['pagination'] -and $r.pagination) {
            $pag = $r.pagination
            $pagType = ''
            if ($pag.PSObject.Properties['type']) { $pagType = ([string]$pag.type).ToLower() }
            if ($pagType -eq 'page' -or $pagType -eq 'offset') {
                $pagParam = ''
                if ($pag.PSObject.Properties['param']) { $pagParam = [string]$pag.param }
                if (-not $pagParam) {
                    throw "Repo '$($r.name)' pagination type '$pagType' requires a non-empty 'param' query name."
                }
            }
        }

        if ($r.PSObject.Properties['items'] -and $r.items -and $r.items.PSObject.Properties['regex']) {
            if (([string]$r.items.regex).Length -gt $maxRegexLen) {
                throw "Repo '$($r.name)' items.regex exceeds $maxRegexLen chars."
            }
        }

        if ($r.PSObject.Properties['fields'] -and $r.fields) {
            foreach ($fp in $r.fields.PSObject.Properties) {
                $sel = $fp.Value
                $rx = ''
                if ($sel -is [string]) { $rx = $sel }
                elseif ($sel -and $sel.PSObject.Properties['regex']) { $rx = [string]$sel.regex }
                if ($rx.Length -gt $maxRegexLen) {
                    throw "Repo '$($r.name)' field '$($fp.Name)' regex exceeds $maxRegexLen chars."
                }
            }
        }

        if ($r.PSObject.Properties['sortFields'] -and $r.sortFields) {
            foreach ($sf in $r.sortFields) {
                $rx = ''
                if ($sf.PSObject.Properties['extract']) { $rx = [string]$sf.extract }
                if ($rx.Length -gt $maxRegexLen) {
                    throw "Repo '$($r.name)' sortField '$($sf.name)' extract regex exceeds $maxRegexLen chars."
                }
            }
        }

        if ($r.PSObject.Properties['tagFetch'] -and $r.tagFetch) {
            $tf = $r.tagFetch
            $tplList = @()
            if ($tf.PSObject.Properties['urlTemplate']) { $tplList += [string]$tf.urlTemplate }
            if ($tf.PSObject.Properties['sources'] -and $tf.sources) {
                foreach ($s in $tf.sources) {
                    if ($s.PSObject.Properties['urlTemplate']) { $tplList += [string]$s.urlTemplate }
                }
            }
            foreach ($tpl in $tplList) {
                if (-not $tpl) { continue }
                if ($tpl -notmatch '^https://') {
                    throw "Repo '$($r.name)' tagFetch urlTemplate must be https: '$tpl'"
                }
                $probe = $tpl -replace '\{base(Raw)?\}', 'x'
                try { $null = [uri]$probe } catch {
                    throw "Repo '$($r.name)' tagFetch urlTemplate is not a valid URI: '$tpl'"
                }
            }
        }
    }
}

function ConvertTo-RepositoryListLine {
    param($Repo)

    $fmt  = if ($Repo.PSObject.Properties['format'])       { $Repo.format }       else { 'html' }
    $desc = if ($Repo.PSObject.Properties['description'])  { $Repo.description }  else { '' }
    $pp   = if ($Repo.PSObject.Properties['pullPrefix'])   { $Repo.pullPrefix }   else { '' }
    $dl   = if ($Repo.PSObject.Properties['defaultLimit']) { $Repo.defaultLimit } else { 100 }
    $hostName = ''
    try { $hostName = ([uri]$Repo.baseUrl).Host } catch { $hostName = '' }
    $hasTags = '0'
    if ($Repo.PSObject.Properties['tagFetch'] -and $Repo.tagFetch) { $hasTags = '1' }
    elseif ($fmt -eq 'html' -and $hostName -eq 'ollama.com')       { $hasTags = '1' }
    if ([string]::IsNullOrEmpty([string]$pp)) { $pp = '(none)' }
    return "$($Repo.name)|$fmt|$desc|$pp|$dl|$hostName|$hasTags"
}

function Get-RepositorySortFieldLines {
    param($Repo)

    $lines = @()
    if ($Repo.PSObject.Properties['sortFields'] -and $Repo.sortFields) {
        foreach ($sf in $Repo.sortFields) {
            $num = '0'
            if ($sf.PSObject.Properties['numeric'] -and [bool]$sf.numeric) { $num = '1' }
            $lines += "$($sf.name)|$($sf.extract)|$num"
        }
    }
    return $lines
}

function Test-RepositoryPullTarget {
    param($Repo, [string]$RepoName, [string]$ModelName)

    if (-not $ModelName) { throw '-ModelName is required.' }
    $name = $ModelName.Trim()
    if ($name.Length -eq 0)   { throw 'Model name is empty.' }
    if ($name.Length -gt 256) { throw 'Model name exceeds 256 chars.' }
    if ($name -match '[\x00-\x1f]')         { throw 'Model name contains control characters.' }
    if ($name -match '[\s"''`;|&<>^$()\\]') { throw 'Model name contains shell metacharacters or whitespace.' }
    if ($name -match '\.\.')                { throw "Model name contains '..'" }
    if ($name -match '://')                 { throw 'Model name contains a URL scheme.' }

    $prefix = ''
    if ($Repo.PSObject.Properties['pullPrefix']) { $prefix = [string]$Repo.pullPrefix }
    if ($prefix) {
        if (-not $name.StartsWith($prefix)) {
            throw "Model name '$name' must start with required prefix '$prefix' for repo '$RepoName'."
        }
        $rest = $name.Substring($prefix.Length)
        if ($rest -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$') {
            throw "Model reference '$rest' does not match expected '<owner>/<model>[:<tag>]' shape."
        }
    } else {
        if ($name -notmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?(:[A-Za-z0-9._-]+)?$') {
            throw "Model name '$name' has invalid shape for repo '$RepoName'."
        }
        if ($name -match '^([^/:]+)/') {
            $first = $Matches[1]
            if ($first.Contains('.')) {
                throw "Model name '$name' appears to specify a remote registry host ('$first'); not allowed for repo '$RepoName'."
            }
        }
    }
    return $true
}

Export-ModuleMember -Function New-DefaultRepoConfig,
    Initialize-RepoConfig,
    Get-RepositoryConfig,
    Test-RepositoryConfig,
    ConvertTo-RepositoryListLine,
    Get-RepositorySortFieldLines,
    Test-RepositoryPullTarget
