param(
    [int]$Skip=0,
    [int]$Limit=0,
    [switch]$Append,
    [string]$CacheFile,
    [switch]$Local,
    [string]$Repo='Ollama',
    [string]$ConfigFile,
    [switch]$ListRepos,
    [switch]$ListSortFields
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8

# ================================================================
# repos.json schema (single generic fetcher, no per-site code paths)
# ----------------------------------------------------------------
# Each repo entry declares HOW to fetch + parse, not bespoke logic:
#   name, description, pullPrefix, defaultLimit
#   format        : 'html' | 'json'
#   baseUrl       : root URL
#   queryParams   : { key:value, ... } static query string params
#   pagination    : { type, ... }
#       type='page'         param + start [+ pageSizeParam, pageSize]
#       type='offset'       param + start + pageSize [+ pageSizeParam]
#       type='cursor-link'  pageSizeParam + pageSize  (follows
#                           RFC-5988 Link: <url>; rel="next" header)
#       type='none'         single request
#       maxPages            safety cap (default 50)
#   items         : { regex, group? } for html, OR { path } for json
#   fields        : { fieldName : <selector> }
#       html selector : 'regex'  OR  { regex, group?, decode?, multi?, trim? }
#       json selector : 'dotted.path'
#   expandVariantField    : optional field name whose array of values
#                           is used to emit one result per variant
#                           (e.g. Ollama param sizes 1b/3b/7b/...)
#   variantNameSeparator  : separator inserted between name + variant
#                           value (default ':')
#   descriptionTemplate   : optional template "[{a}] foo {b}"
#   paramsFromName        : extract NN(b|m) from name when no variant
#   estimateSize          : compute GB estimate from params
# ================================================================

# ----------------------------------------------------------------
# Config bootstrap
# ----------------------------------------------------------------
if (-not $ConfigFile) {
    $ConfigFile = "$env:APPDATA\ollamaLauncher\repos.json"
}
$ConfigDir = Split-Path -Parent $ConfigFile
if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }

function New-DefaultRepoConfig {
    @(
        [PSCustomObject]@{
            name         = 'Ollama'
            description  = 'Official Ollama model library (https://ollama.com)'
            pullPrefix   = ''
            defaultLimit = 200
            format       = 'html'
            baseUrl      = 'https://ollama.com/search'
            pagination   = [PSCustomObject]@{ type='page'; param='page'; start=1; maxPages=50 }
            items        = [PSCustomObject]@{ regex='(?s)<li x-test-model(.*?)</li>'; group=1 }
            fields       = [PSCustomObject]@{
                name        = [PSCustomObject]@{ regex='x-test-search-response-title>([^<]+)<'; decode='html' }
                description = [PSCustomObject]@{ regex='(?s)<p[^>]*text-neutral-800[^>]*>(.*?)</p>' }
                variants    = [PSCustomObject]@{ regex='x-test-size[^>]*>([^<]+)<'; multi=$true }
            }
            expandVariantField   = 'variants'
            variantNameSeparator = ':'
            estimateSize         = $true
        },
        [PSCustomObject]@{
            name         = 'HuggingFace'
            description  = 'HuggingFace Hub via API (https://huggingface.co)'
            pullPrefix   = 'hf.co/'
            defaultLimit = 500
            format       = 'json'
            baseUrl      = 'https://huggingface.co/api/models'
            queryParams  = [PSCustomObject]@{ sort='trendingScore'; direction='-1'; full='false' }
            pagination   = [PSCustomObject]@{ type='cursor-link'; pageSizeParam='limit'; pageSize=100; maxPages=50 }
            items        = [PSCustomObject]@{ path='$' }
            fields       = [PSCustomObject]@{
                name      = 'id'
                pipeline  = 'pipeline_tag'
                downloads = 'downloads'
                likes     = 'likes'
            }
            descriptionTemplate = '[{pipeline}] Downloads: {downloads}, Likes: {likes}'
            paramsFromName      = $true
            estimateSize        = $true
            sortFields          = @(
                [PSCustomObject]@{ name='Downloads'; extract='Downloads:\s*(\d+)'; numeric=$true },
                [PSCustomObject]@{ name='Likes';     extract='Likes:\s*(\d+)';     numeric=$true }
            )
        }
    )
}

# Materialize default config if missing
if (-not (Test-Path $ConfigFile)) {
    New-DefaultRepoConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile -Encoding UTF8
}

# Load
try {
    $repos = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($repos -isnot [System.Array]) { $repos = @($repos) }
} catch {
    Write-Error "Failed to parse repo config '$ConfigFile': $_"
    exit 1
}

# ----------------------------------------------------------------
# -ListRepos : write name|format|description|pullPrefix|defaultLimit
# ----------------------------------------------------------------
if ($ListRepos) {
    if (-not $CacheFile) { $CacheFile = "$env:APPDATA\ollamaLauncher\repos_list.txt" }
    $lines = @()
    foreach ($r in $repos) {
        $fmt  = if ($r.PSObject.Properties['format'])       { $r.format }       else { 'html' }
        $desc = if ($r.PSObject.Properties['description'])  { $r.description }  else { '' }
        $pp   = if ($r.PSObject.Properties['pullPrefix'])   { $r.pullPrefix }   else { '' }
        $dl   = if ($r.PSObject.Properties['defaultLimit']) { $r.defaultLimit } else { 100 }
        $lines += "$($r.name)|$fmt|$desc|$pp|$dl"
    }
    [System.IO.File]::WriteAllLines($CacheFile, $lines)
    foreach ($l in $lines) { Write-Host $l }
    exit 0
}

# ----------------------------------------------------------------
# -ListSortFields -Repo X : write name|extractRegex|numeric for the
# selected repo's configured sortable fields (one per line).
# ----------------------------------------------------------------
if ($ListSortFields) {
    $r = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $r) { Write-Error "Repository '$Repo' not found."; exit 1 }
    if (-not $CacheFile) { $CacheFile = "$env:APPDATA\ollamaLauncher\sort_fields.txt" }
    $lines = @()
    if ($r.PSObject.Properties['sortFields'] -and $r.sortFields) {
        foreach ($sf in $r.sortFields) {
            $num = '0'
            if ($sf.PSObject.Properties['numeric'] -and [bool]$sf.numeric) { $num = '1' }
            $lines += "$($sf.name)|$($sf.extract)|$num"
        }
    }
    [System.IO.File]::WriteAllLines($CacheFile, $lines)
    foreach ($l in $lines) { Write-Host $l }
    exit 0
}

# Default cache file
if (-not $CacheFile) { $CacheFile = "$env:APPDATA\ollamaLauncher\models_cache.txt" }
$CacheDir = Split-Path -Parent $CacheFile
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }

# ----------------------------------------------------------------
# -Local : list installed models via `ollama list`
# ----------------------------------------------------------------
if ($Local) {
    try {
        $output = ollama list | Select-Object -Skip 1
        $models = @()
        foreach ($line in $output) {
            if ($line -match '^(\S+)\s+\S+\s+(\S+\s+\S+)') {
                $name = $matches[1]; $size = $matches[2]
                $params = 'N/A'
                if ($name -match ':(\d+(\.\d+)?[bm])') { $params = $matches[1] }
                elseif ($name -match '(\d+(\.\d+)?[bm])') { $params = $matches[1] }
                $models += [PSCustomObject]@{Name=$name; Size=$size; Params=$params; Description='Installed'}
            }
        }
        if ($models.Count -eq 0) { exit 1 }
        [System.IO.File]::WriteAllLines($CacheFile, @($models.Name))
        try{$w=$Host.UI.RawUI.WindowSize.Width}catch{$w=80}; if($w -lt 60){$w=60}; $dw=$w-53; if($dw -lt 5){$dw=5}
        Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f 'Num','Model Name','Size','Params','Description')
        Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f ('-'*4),('-'*25),('-'*10),('-'*8),('-'*$dw))
        $k=0
        foreach ($m in $models) {
            $k++; $n=$m.Name; if($n.Length -gt 25){$n=$n.Substring(0,22)+'...'}
            Write-Host ('{0,3}. {1,-25} {2,-10} {3,-8}  {4}' -f $k,$n,$m.Size,$m.Params,$m.Description)
        }
        exit 0
    } catch { Write-Error $_; exit 1 }
}

# ----------------------------------------------------------------
# Generic helpers
# ----------------------------------------------------------------
function Get-PropValue($obj, $name, $default=$null) {
    if ($null -ne $obj -and $obj.PSObject.Properties[$name]) { return $obj.$name }
    return $default
}

function Get-FieldFromHtml($html, $sel) {
    if ($sel -is [string]) {
        $regex=$sel; $group=1; $decode=$false; $trim=$true; $multi=$false
    } else {
        $regex  = $sel.regex
        $group  = [int](Get-PropValue $sel 'group' 1)
        $decode = ((Get-PropValue $sel 'decode' '') -eq 'html')
        $trim   = [bool](Get-PropValue $sel 'trim' $true)
        $multi  = [bool](Get-PropValue $sel 'multi' $false)
    }
    if ($multi) {
        $vals = @()
        foreach ($m in [regex]::Matches($html, $regex)) {
            $v = $m.Groups[$group].Value
            if ($trim)   { $v = ($v.Trim() -replace '\s+',' ') }
            if ($decode) { $v = [System.Net.WebUtility]::HtmlDecode($v) }
            $vals += $v
        }
        return ,$vals
    }
    $m = [regex]::Match($html, $regex)
    if (-not $m.Success) { return $null }
    $v = $m.Groups[$group].Value
    if ($trim)   { $v = ($v.Trim() -replace '\s+',' ') }
    if ($decode) { $v = [System.Net.WebUtility]::HtmlDecode($v) }
    return $v
}

function Get-FieldFromJson($obj, $sel) {
    if ($sel -isnot [string]) { return $null }
    $cur = $obj
    foreach ($p in ($sel -split '\.')) {
        if ($null -eq $cur) { return $null }
        if ($p -eq '$' -or $p -eq '') { continue }
        $cur = $cur.$p
    }
    return $cur
}

function Expand-Template($template, $values) {
    $out = $template
    foreach ($k in $values.Keys) {
        $out = $out -replace ('\{' + [regex]::Escape($k) + '\}'), [string]$values[$k]
    }
    return $out
}

function Get-ParamsFromName($name) {
    if ($name -match ':(\d+(\.\d+)?[bm])')        { return $Matches[1].ToLower() }
    if ($name -match '(\d+(\.\d+)?)b(?![a-zA-Z])'){ return ($Matches[1] + 'b').ToLower() }
    if ($name -match '(\d+)m(?![a-zA-Z])')        { return ($Matches[1] + 'm').ToLower() }
    return 'N/A'
}

function Get-SizeEstimate($params) {
    if ($params -match '(\d+)x(\d+(\.\d+)?)b') {
        $experts = [double]$Matches[1]; $eSize = [double]$Matches[2]
        return ('{0:N1} GB' -f (($experts * $eSize) * 0.46))
    }
    if ($params -match '(\d+(\.\d+)?)b') {
        $val = [double]$Matches[1]
        if     ($val -le 3)  { $est = $val*0.6  + 0.5 }
        elseif ($val -le 10) { $est = $val*0.55 + 0.5 }
        else                 { $est = $val*0.56 }
        return ('{0:N1} GB' -f $est)
    }
    if ($params -match '(\d+)m') { return '< 1 GB' }
    return 'Unknown'
}

function New-RequestUrl($repo, $extraQuery) {
    $params = @{}
    $qp = Get-PropValue $repo 'queryParams' $null
    if ($qp) {
        foreach ($p in $qp.PSObject.Properties) { $params[$p.Name] = [string]$p.Value }
    }
    if ($extraQuery) {
        foreach ($k in $extraQuery.Keys) { $params[$k] = [string]$extraQuery[$k] }
    }
    if ($params.Count -eq 0) { return $repo.baseUrl }
    $qs = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([uri]::EscapeDataString($_.Value))"
    }) -join '&'
    if ($repo.baseUrl.Contains('?')) { return "$($repo.baseUrl)&$qs" }
    return "$($repo.baseUrl)?$qs"
}

function Get-NextLink($response) {
    $link = $null
    try {
        if ($response.Headers -and $response.Headers.ContainsKey('Link')) {
            $link = $response.Headers['Link']
        }
    } catch { $link = $null }
    if (-not $link) { return $null }
    $linkStr = if ($link -is [System.Array]) { $link -join ', ' } else { [string]$link }
    $m = [regex]::Match($linkStr, '<([^>]+)>;\s*rel="?next"?')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# ----------------------------------------------------------------
# The single, generic, config-driven fetcher
# ----------------------------------------------------------------
function Invoke-RepoFetch($repo, [int]$Skip, [int]$Limit) {
    $results  = @()
    $skipped  = 0
    $format   = (Get-PropValue $repo 'format' 'html').ToString().ToLower()
    $pag      = Get-PropValue $repo 'pagination' $null
    $pagType  = (Get-PropValue $pag 'type' 'none').ToString().ToLower()
    $maxPages = [int](Get-PropValue $pag 'maxPages' 50)
    $variantField     = [string](Get-PropValue $repo 'expandVariantField' '')
    $variantSeparator = [string](Get-PropValue $repo 'variantNameSeparator' ':')
    $descTemplate     = [string](Get-PropValue $repo 'descriptionTemplate' '')
    $paramsFromName   = [bool](Get-PropValue $repo 'paramsFromName' $false)
    $estimateSize     = [bool](Get-PropValue $repo 'estimateSize' $false)

    $nextUrl = $null
    $current = $null
    if ($pagType -eq 'page')   { $current = [int](Get-PropValue $pag 'start' 1) }
    if ($pagType -eq 'offset') { $current = [int](Get-PropValue $pag 'start' 0) }

    for ($pageIdx = 0; $pageIdx -lt $maxPages; $pageIdx++) {
        # ---- Build URL for this iteration ----
        if ($pagType -eq 'cursor-link' -and $nextUrl) {
            $url = $nextUrl
        } else {
            $extra = @{}
            if ($pagType -eq 'page' -or $pagType -eq 'offset') {
                $extra[$pag.param] = [string]$current
            }
            $psp = Get-PropValue $pag 'pageSizeParam' $null
            $ps  = Get-PropValue $pag 'pageSize' $null
            if ($psp -and $ps) { $extra[$psp] = [string]$ps }
            $url = New-RequestUrl $repo $extra
        }

        Write-Host "Fetching: $url" -ForegroundColor Gray
        try {
            $headers = @{}
            if ($format -eq 'json') { $headers['Accept'] = 'application/json' }
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $headers
        } catch {
            Write-Error "Fetch failed: $_"
            return $results
        }

        # ---- Extract raw items ----
        $rawItems = @()
        if ($format -eq 'html') {
            $itemsCfg = Get-PropValue $repo 'items' $null
            if (-not $itemsCfg) { Write-Error "html repo missing items.regex"; return $results }
            $grp = [int](Get-PropValue $itemsCfg 'group' 1)
            foreach ($m in [regex]::Matches($response.Content, $itemsCfg.regex)) {
                $rawItems += $m.Groups[$grp].Value
            }
        } else {
            $data = $response.Content | ConvertFrom-Json
            $itemsCfg = Get-PropValue $repo 'items' $null
            $path = [string](Get-PropValue $itemsCfg 'path' '$')
            if ($path -eq '$' -or [string]::IsNullOrEmpty($path)) {
                $rawItems = @($data)
            } else {
                $cur = $data
                foreach ($p in ($path -split '\.')) { if ($p -ne '$' -and $p -ne '') { $cur = $cur.$p } }
                $rawItems = @($cur)
            }
        }

        if (-not $rawItems -or $rawItems.Count -eq 0) {
            Write-Host "No more items. Pagination complete." -ForegroundColor Gray
            break
        }

        # ---- Process items ----
        $hitLimit = $false
        foreach ($raw in $rawItems) {
            if ($skipped -lt $Skip) { $skipped++; continue }
            if ($results.Count -ge $Limit) { $hitLimit = $true; break }

            $vals = @{}
            foreach ($fp in $repo.fields.PSObject.Properties) {
                if ($format -eq 'html') { $vals[$fp.Name] = Get-FieldFromHtml $raw $fp.Value }
                else                    { $vals[$fp.Name] = Get-FieldFromJson $raw $fp.Value }
            }

            # Determine variant list (or single null sentinel)
            $variants = @($null)
            if ($variantField -and $vals.ContainsKey($variantField)) {
                $vf = $vals[$variantField]
                if ($vf -is [System.Array] -and $vf.Count -gt 0) { $variants = $vf }
            }

            foreach ($v in $variants) {
                if ($results.Count -ge $Limit) { $hitLimit = $true; break }
                $name   = [string]$vals['name']
                $params = 'N/A'
                if ($v) {
                    $name   = "$name$variantSeparator$v"
                    $params = [string]$v
                }
                if ($params -eq 'N/A' -and $paramsFromName) { $params = Get-ParamsFromName $name }

                $desc = ''
                if ($descTemplate)        { $desc = Expand-Template $descTemplate $vals }
                elseif ($vals['description']) { $desc = [string]$vals['description'] }
                if (-not $desc) { $desc = 'No description available' }

                $size = if ($estimateSize) { Get-SizeEstimate $params } else { 'Unknown' }

                $results += [PSCustomObject]@{ Name=$name; SizeGB=$size; Params=$params; Description=$desc }
            }
            if ($hitLimit) { break }
        }
        if ($results.Count -ge $Limit) { break }

        # ---- Advance pagination ----
        switch ($pagType) {
            'page'        { $current++ }
            'offset'      { $current += [int](Get-PropValue $pag 'pageSize' $rawItems.Count) }
            'cursor-link' {
                $nextUrl = Get-NextLink $response
                if (-not $nextUrl) { Write-Host "No next link; pagination ends." -ForegroundColor Gray; break }
            }
            default { return $results }
        }
        if ($pagType -eq 'cursor-link' -and -not $nextUrl) { break }
    }
    return $results
}

# ----------------------------------------------------------------
# Dispatch
# ----------------------------------------------------------------
$activeRepo = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
if (-not $activeRepo) {
    Write-Error "Repository '$Repo' not found in '$ConfigFile'. Available: $($repos.name -join ', ')"
    exit 1
}

if ($Limit -le 0) {
    $Limit = [int](Get-PropValue $activeRepo 'defaultLimit' 100)
}

Write-Host "Using repository: $($activeRepo.name) [$($activeRepo.format)]  (limit=$Limit, skip=$Skip)" -ForegroundColor Cyan

$models = Invoke-RepoFetch $activeRepo $Skip $Limit

# ----------------------------------------------------------------
# Write cache
# ----------------------------------------------------------------
$lines = @()
foreach ($model in $models) {
    $lines += "$($model.Name)|$($model.SizeGB)|$($model.Params)|$($model.Description)"
}
if ($Append) { [System.IO.File]::AppendAllLines($CacheFile, $lines) }
else         { [System.IO.File]::WriteAllLines($CacheFile, $lines) }
Write-Host "Successfully fetched $($models.Count) models from $($activeRepo.name)."
