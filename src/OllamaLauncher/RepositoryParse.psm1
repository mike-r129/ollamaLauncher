function Get-RepoProperty {
    param($Object, [string]$Name, $Default = $null)

    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        return $Object.$Name
    }
    return $Default
}

function Get-ModelParamsFromName {
    param([string]$Name)

    if ($Name -match ':(\d+(\.\d+)?[bm])')         { return $Matches[1].ToLower() }
    if ($Name -match '(\d+(\.\d+)?)b(?![a-zA-Z])') { return ($Matches[1] + 'b').ToLower() }
    if ($Name -match '(\d+)m(?![a-zA-Z])')         { return ($Matches[1] + 'm').ToLower() }
    return 'N/A'
}

function Get-ModelSizeEstimate {
    param([string]$Params)

    if ($Params -match '(\d+)x(\d+(\.\d+)?)b') {
        $experts = [double]$Matches[1]
        $eSize = [double]$Matches[2]
        return ('{0:N1} GB' -f (($experts * $eSize) * 0.46))
    }
    if ($Params -match '(\d+(\.\d+)?)b') {
        $val = [double]$Matches[1]
        if     ($val -le 3)  { $est = $val * 0.6 + 0.5 }
        elseif ($val -le 10) { $est = $val * 0.55 + 0.5 }
        else                 { $est = $val * 0.56 }
        return ('{0:N1} GB' -f $est)
    }
    if ($Params -match '(\d+)m') { return '< 1 GB' }
    return 'Unknown'
}

function ConvertTo-ModelSizeGb {
    param([string]$Size)

    if ($Size -match '([\d\.]+)\s*GB') { return [double]$Matches[1] }
    if ($Size -match '([\d\.]+)\s*MB') { return [double]$Matches[1] / 1024.0 }
    if ($Size -match '([\d\.]+)\s*TB') { return [double]$Matches[1] * 1024.0 }
    if ($Size -match '<\s*1')          { return 0.5 }
    return -1.0
}

$script:RegexTimeout = [TimeSpan]::FromSeconds(2)

function Invoke-SafeRegexMatches {
    param([string]$InputText, [string]$Pattern)

    if ([string]::IsNullOrEmpty($Pattern)) { return @() }
    try {
        $rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::None, $script:RegexTimeout)
        return $rx.Matches($InputText)
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        Write-Host "Regex timed out (skipped): $Pattern" -ForegroundColor Yellow
        return @()
    } catch {
        Write-Host "Regex error '$Pattern': $_" -ForegroundColor Yellow
        return @()
    }
}

function Invoke-SafeRegexMatch {
    param([string]$InputText, [string]$Pattern)

    if ([string]::IsNullOrEmpty($Pattern)) { return $null }
    try {
        $rx = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::None, $script:RegexTimeout)
        return $rx.Match($InputText)
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        Write-Host "Regex timed out (skipped): $Pattern" -ForegroundColor Yellow
        return $null
    } catch {
        Write-Host "Regex error '$Pattern': $_" -ForegroundColor Yellow
        return $null
    }
}

function Get-FieldFromHtml {
    param($Html, $Selector)

    if ($Selector -is [string]) {
        $regex = $Selector
        $group = 1
        $decode = $false
        $trim = $true
        $multi = $false
    } else {
        $regex  = $Selector.regex
        $group  = [int](Get-RepoProperty $Selector 'group' 1)
        $decode = ((Get-RepoProperty $Selector 'decode' '') -eq 'html')
        $trim   = [bool](Get-RepoProperty $Selector 'trim' $true)
        $multi  = [bool](Get-RepoProperty $Selector 'multi' $false)
    }

    if ($multi) {
        $vals = @()
        foreach ($m in (Invoke-SafeRegexMatches $Html $regex)) {
            $v = $m.Groups[$group].Value
            if ($trim)   { $v = ($v.Trim() -replace '\s+', ' ') }
            if ($decode) { $v = [System.Net.WebUtility]::HtmlDecode($v) }
            $vals += $v
        }
        return ,$vals
    }

    $m = Invoke-SafeRegexMatch $Html $regex
    if (-not $m -or -not $m.Success) { return $null }
    $v = $m.Groups[$group].Value
    if ($trim)   { $v = ($v.Trim() -replace '\s+', ' ') }
    if ($decode) { $v = [System.Net.WebUtility]::HtmlDecode($v) }
    return $v
}

function Get-FieldFromJson {
    param($Object, $Selector)

    if ($Selector -isnot [string]) { return $null }
    $cur = $Object
    foreach ($p in ($Selector -split '\.')) {
        if ($null -eq $cur) { return $null }
        if ($p -eq '$' -or $p -eq '') { continue }
        $cur = $cur.$p
    }
    return $cur
}

function Expand-RepoTemplate {
    param([string]$Template, $Values)

    $out = $Template
    foreach ($k in $Values.Keys) {
        $out = $out -replace ('\{' + [regex]::Escape($k) + '\}'), [string]$Values[$k]
    }
    return $out
}

function New-RepositoryRequestUrl {
    param($Repo, $ExtraQuery)

    $params = @{}
    $qp = Get-RepoProperty $Repo 'queryParams' $null
    if ($qp) {
        foreach ($p in $qp.PSObject.Properties) {
            $params[$p.Name] = [string]$p.Value
        }
    }
    if ($ExtraQuery) {
        foreach ($k in $ExtraQuery.Keys) {
            $params[$k] = [string]$ExtraQuery[$k]
        }
    }
    if ($params.Count -eq 0) { return $Repo.baseUrl }
    $qs = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
    }) -join '&'
    if ($Repo.baseUrl.Contains('?')) { return "$($Repo.baseUrl)&$qs" }
    return "$($Repo.baseUrl)?$qs"
}

function Get-RepositoryNextLink {
    param($Response, [string]$ExpectedHost)

    $link = $null
    try {
        if ($Response.Headers -and $Response.Headers.ContainsKey('Link')) {
            $link = $Response.Headers['Link']
        }
    } catch {
        $link = $null
    }
    if (-not $link) { return $null }

    $linkStr = if ($link -is [System.Array]) { $link -join ', ' } else { [string]$link }
    $m = [regex]::Match($linkStr, '<([^>]+)>;\s*rel="?next"?')
    if (-not $m.Success) { return $null }

    $candidate = $m.Groups[1].Value
    try {
        $u = [uri]$candidate
        if ($u.Scheme -ne 'https') {
            Write-Host "Refusing non-https next link: $candidate" -ForegroundColor Yellow
            return $null
        }
        if ($ExpectedHost -and ($u.Host -ne $ExpectedHost)) {
            Write-Host "Refusing cross-host next link ($($u.Host) != $ExpectedHost): $candidate" -ForegroundColor Yellow
            return $null
        }
    } catch {
        return $null
    }
    return $candidate
}

Export-ModuleMember -Function Get-RepoProperty,
    Get-ModelParamsFromName,
    Get-ModelSizeEstimate,
    ConvertTo-ModelSizeGb,
    Invoke-SafeRegexMatches,
    Invoke-SafeRegexMatch,
    Get-FieldFromHtml,
    Get-FieldFromJson,
    Expand-RepoTemplate,
    New-RepositoryRequestUrl,
    Get-RepositoryNextLink
