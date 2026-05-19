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
#   tagFetch              : optional per-repo block describing how to
#                           fetch the "all tags / variants / quants"
#                           list for a single base model. Used by the
#                           [V] View Models UI in the launcher.
#       type='ollama-library'        scrape /library/<base>/tags
#           urlTemplate              https URL with {base} placeholder
#           countInMainList=true     also probe each base while
#                                    populating the main listing to
#                                    fill the "# of Models" column
#       type='huggingface-base-model'  HF API filter by base_model tag
#           sources : [ { label, urlTemplate } ]
#               urlTemplate may contain {base} (url-encoded) or
#               {baseRaw} (raw); each source returns a JSON array of
#               model objects with id/downloads/likes/...
#           countInMainList=false    (default) HF has many bases, so
#                                    skip the per-base pre-count
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
            defaultLimit = 500
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
            tagFetch             = [PSCustomObject]@{
                type             = 'ollama-library'
                urlTemplate      = 'https://ollama.com/library/{base}/tags'
                countInMainList  = $true
            }
        },
        [PSCustomObject]@{
            name         = 'HuggingFace'
            description  = 'HuggingFace Hub via API (https://huggingface.co)'
            pullPrefix   = 'hf.co/'
            defaultLimit = 500
            format       = 'json'
            baseUrl      = 'https://huggingface.co/api/models'
            queryParams  = [PSCustomObject]@{ filter='gguf'; sort='trendingScore'; direction='-1'; full='false' }
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
            tagFetch            = [PSCustomObject]@{
                type            = 'huggingface-base-model'
                countInMainList = $false
                sources         = @(
                    [PSCustomObject]@{ label='gguf-variants';  urlTemplate='https://huggingface.co/api/models?search={base}&filter=gguf&limit=100&full=false' }
                )
            }
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
# Security: validate the loaded config (https-only baseUrl + regex
# length caps to mitigate ReDoS via tampered repos.json).
# ----------------------------------------------------------------
function Test-RepoConfig($repos) {
    $maxRegexLen = 2000
    foreach ($r in $repos) {
        $url = ''
        if ($r.PSObject.Properties['baseUrl']) { $url = [string]$r.baseUrl }
        if (-not $url -or $url -notmatch '^https://') {
            Write-Error "Repo '$($r.name)' has missing or non-https baseUrl ('$url'). Edit '$ConfigFile' to fix."
            exit 1
        }
        try { $null = [uri]$url } catch {
            Write-Error "Repo '$($r.name)' baseUrl is not a valid URI: '$url'"; exit 1
        }
        if ($r.PSObject.Properties['items'] -and $r.items -and $r.items.PSObject.Properties['regex']) {
            if (([string]$r.items.regex).Length -gt $maxRegexLen) {
                Write-Error "Repo '$($r.name)' items.regex exceeds $maxRegexLen chars."; exit 1
            }
        }
        if ($r.PSObject.Properties['fields'] -and $r.fields) {
            foreach ($fp in $r.fields.PSObject.Properties) {
                $sel = $fp.Value
                $rx = ''
                if ($sel -is [string]) { $rx = $sel }
                elseif ($sel -and $sel.PSObject.Properties['regex']) { $rx = [string]$sel.regex }
                if ($rx.Length -gt $maxRegexLen) {
                    Write-Error "Repo '$($r.name)' field '$($fp.Name)' regex exceeds $maxRegexLen chars."; exit 1
                }
            }
        }
        if ($r.PSObject.Properties['sortFields'] -and $r.sortFields) {
            foreach ($sf in $r.sortFields) {
                $rx = ''
                if ($sf.PSObject.Properties['extract']) { $rx = [string]$sf.extract }
                if ($rx.Length -gt $maxRegexLen) {
                    Write-Error "Repo '$($r.name)' sortField '$($sf.name)' extract regex exceeds $maxRegexLen chars."; exit 1
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
                    Write-Error "Repo '$($r.name)' tagFetch urlTemplate must be https: '$tpl'"; exit 1
                }
                # Strip placeholders before URI parse so {base} doesn't trip it
                $probe = $tpl -replace '\{base(Raw)?\}','x'
                try { $null = [uri]$probe } catch {
                    Write-Error "Repo '$($r.name)' tagFetch urlTemplate is not a valid URI: '$tpl'"; exit 1
                }
            }
        }
    }
}
Test-RepoConfig $repos

# ----------------------------------------------------------------
# Generic helpers
# ----------------------------------------------------------------
function Get-PropValue($obj, $name, $default=$null) {
    if ($null -ne $obj -and $obj.PSObject.Properties[$name]) { return $obj.$name }
    return $default
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

# ----------------------------------------------------------------
# Get-OllamaModelTags : scrape /library/<base>/tags and return one
# [PSCustomObject] per published tag (Name/SizeGB/Params/Description).
# Used both by -FetchTags (on-demand) and by the main fetch loop
# when the active repo is an Ollama-format html repo
# (so every tag/quant variant appears in the initial pull).
# Returns @() on any failure (caller decides how to handle).
# ----------------------------------------------------------------
function Get-OllamaModelTags([string]$base) {
    $base = ($base -split ':')[0].Trim()
    if ($base.Length -eq 0)   { return @() }
    if ($base.Length -gt 128) { return @() }
    if ($base -notmatch '^[A-Za-z0-9._-]+$') { return @() }
    $url = "https://ollama.com/library/$base/tags"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
    } catch {
        Write-Host "  Tag fetch failed for ${base}: $_" -ForegroundColor Yellow
        return @()
    }
    $content = $response.Content
    if ($content -is [string] -and $content.Length -gt 10000000) {
        $content = $content.Substring(0, 10000000)
    }
    $timeout = [TimeSpan]::FromSeconds(2)
    $escBase = [regex]::Escape($base)
    try {
        $rxTag  = [regex]::new('href="/library/' + $escBase + ':(?<tag>[^"#?]+)"', [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
        $rxSize = [regex]::new('(\d+(?:\.\d+)?)\s*(GB|MB|TB)',                                [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
        $rxCtx  = [regex]::new('(\d+K)\s*context\s*window',                                   [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $timeout)
        $rxHash = [regex]::new('font-mono"\s*>\s*([a-f0-9]{12})',                             [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
        $rxAge  = [regex]::new('(\d+\s+\w+\s+ago)',                                           [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
    } catch {
        return @()
    }
    $seen = @{}
    $out  = @()
    try { $tagMatches = $rxTag.Matches($content) }
    catch [System.Text.RegularExpressions.RegexMatchTimeoutException] { return @() }
    foreach ($m in $tagMatches) {
        $tag = $m.Groups['tag'].Value
        if ($seen.ContainsKey($tag)) { continue }
        $seen[$tag] = $true
        $start  = $m.Index + $m.Length
        $winLen = [Math]::Min(1500, $content.Length - $start)
        if ($winLen -le 0) { continue }
        $win = $content.Substring($start, $winLen)
        $sz  = '?'
        try { $sm = $rxSize.Match($win); if ($sm.Success) { $sz = "$($sm.Groups[1].Value) $($sm.Groups[2].Value)" } } catch {}
        $ctx = ''
        try { $cm = $rxCtx.Match($win);  if ($cm.Success) { $ctx = $cm.Groups[1].Value } } catch {}
        $hash = ''
        try { $hm = $rxHash.Match($win); if ($hm.Success) { $hash = $hm.Groups[1].Value } } catch {}
        $age = ''
        try { $am = $rxAge.Match($win);  if ($am.Success) { $age = $am.Groups[1].Value } } catch {}
        $fullName = "$base`:$tag"
        $params = 'N/A'
        if     ($fullName -match ':(\d+(\.\d+)?[bm])')           { $params = $Matches[1].ToLower() }
        elseif ($fullName -match '(\d+(\.\d+)?)b(?![a-zA-Z])')   { $params = ($Matches[1] + 'b').ToLower() }
        elseif ($fullName -match '(\d+)m(?![a-zA-Z])')           { $params = ($Matches[1] + 'm').ToLower() }
        $descParts = @()
        if ($ctx)  { $descParts += "Context: $ctx" }
        if ($hash) { $descParts += "Hash: $hash" }
        if ($age)  { $descParts += "Updated $age" }
        $desc = if ($descParts.Count -gt 0) { $descParts -join '  ' } else { 'Tag variant' }
        $out += [PSCustomObject]@{ Name=$fullName; SizeGB=$sz; Params=$params; Description=$desc }
    }
    return $out
}

# ----------------------------------------------------------------
# Get-HuggingFaceModelTags : query the HF Hub API for all models
# that declare the given owner/model as their base_model (split into
# 'finetune' and 'quantized' sources, both configured in repos.json).
# Returns the same {Name;SizeGB;Params;Description} shape as the
# Ollama scraper so the launcher's tag UI works unchanged.
# ----------------------------------------------------------------
function Get-HuggingFaceModelTags([string]$base, $sources) {
    if (-not $sources) { return @() }
    $base = $base.Trim()
    if ($base.Length -eq 0 -or $base.Length -gt 256) { return @() }
    # HF model ids are owner/name with A-Z 0-9 . _ - allowed in each segment.
    if ($base -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { return @() }

    $encBase = [uri]::EscapeDataString($base)
    $seen = @{}
    $out  = @()
    foreach ($src in $sources) {
        $label = [string](Get-PropValue $src 'label' '')
        $tpl   = [string](Get-PropValue $src 'urlTemplate' '')
        if (-not $tpl) { continue }
        if ($tpl -notmatch '^https://') {
            Write-Host "  Refusing non-https HF tag source: $tpl" -ForegroundColor Yellow
            continue
        }
        $url = $tpl.Replace('{base}', $encBase).Replace('{baseRaw}', $base)
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -Headers @{ Accept='application/json' }
        } catch {
            Write-Host "  HF tag fetch failed ($label) for ${base}: $_" -ForegroundColor Yellow
            continue
        }
        $body = $resp.Content
        if ($body -is [string] -and $body.Length -gt 10000000) { $body = $body.Substring(0, 10000000) }
        try { $items = $body | ConvertFrom-Json } catch { continue }
        if ($null -eq $items) { continue }
        foreach ($it in @($items)) {
            $id = [string](Get-PropValue $it 'id' '')
            if (-not $id) { continue }
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $dl   = Get-PropValue $it 'downloads' 0
            $lk   = Get-PropValue $it 'likes' 0
            $pipe = [string](Get-PropValue $it 'pipeline_tag' '')
            $params = Get-ParamsFromName $id
            $size   = Get-SizeEstimate $params
            $descParts = @()
            if ($label) { $descParts += "[$label]" }
            if ($pipe)  { $descParts += $pipe }
            $descParts += "Downloads: $dl"
            $descParts += "Likes: $lk"
            $desc = $descParts -join ' '
            $out += [PSCustomObject]@{ Name=$id; SizeGB=$size; Params=$params; Description=$desc }
        }
    }
    return $out
}

# ----------------------------------------------------------------
# Get-RepoTags : dispatcher that routes to the engine declared by
# the active repo's tagFetch.type. Returns @() when the repo has no
# tagFetch configured (so callers can no-op gracefully).
# ----------------------------------------------------------------
function Get-RepoTags($repo, [string]$base) {
    $cfg = Get-PropValue $repo 'tagFetch' $null
    if (-not $cfg) {
        # Legacy fallback: any ollama.com html repo without explicit
        # tagFetch still supports the original scraper.
        $rh = ''
        try { $rh = ([uri]$repo.baseUrl).Host } catch { $rh = '' }
        if ($rh -eq 'ollama.com') { return Get-OllamaModelTags $base }
        return @()
    }
    $type = ([string](Get-PropValue $cfg 'type' '')).ToLower()
    switch ($type) {
        'ollama-library' {
            # urlTemplate is honored implicitly by Get-OllamaModelTags
            # (which hardcodes ollama.com/library/<base>/tags); we keep
            # it in config for transparency / future override.
            return Get-OllamaModelTags $base
        }
        'huggingface-base-model' {
            $sources = Get-PropValue $cfg 'sources' $null
            return Get-HuggingFaceModelTags $base $sources
        }
        default {
            Write-Host "Unknown tagFetch.type '$type' for repo '$($repo.name)'." -ForegroundColor Yellow
            return @()
        }
    }
}
# ----------------------------------------------------------------
if ($ListRepos) {
    if (-not $CacheFile) { $CacheFile = "$env:APPDATA\ollamaLauncher\repos_list.txt" }
    $lines = @()
    foreach ($r in $repos) {
        $fmt  = if ($r.PSObject.Properties['format'])       { $r.format }       else { 'html' }
        $desc = if ($r.PSObject.Properties['description'])  { $r.description }  else { '' }
        $pp   = if ($r.PSObject.Properties['pullPrefix'])   { $r.pullPrefix }   else { '' }
        $dl   = if ($r.PSObject.Properties['defaultLimit']) { $r.defaultLimit } else { 100 }
        $hostName = ''
        try { $hostName = ([uri]$r.baseUrl).Host } catch { $hostName = '' }
        # hasTags: 1 if the repo declares a tagFetch block, OR if it
        # is an ollama.com html repo (legacy behavior preserved by the
        # Get-RepoTags fallback). The launcher uses this to toggle
        # the [V] View Models option per-repo.
        $hasTags = '0'
        if ($r.PSObject.Properties['tagFetch'] -and $r.tagFetch) { $hasTags = '1' }
        elseif ($fmt -eq 'html' -and $hostName -eq 'ollama.com')  { $hasTags = '1' }
        # Emit "(none)" sentinel for empty pullPrefix so batch for/f does not collapse
        # consecutive | delimiters and shift later fields (e.g. defaultLimit) into the prefix slot.
        if ([string]::IsNullOrEmpty([string]$pp)) { $pp = '(none)' }
        $lines += "$($r.name)|$fmt|$desc|$pp|$dl|$hostName|$hasTags"
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

# ----------------------------------------------------------------
# -ValidatePull -Repo X -ModelName Y
# Validates that a pull target is shape-safe for the active repo.
# Prevents a tampered repos.json (or a malicious cache entry) from
# tricking `ollama pull` into hitting an attacker-controlled OCI
# registry. Exit 0 = safe, exit 1 = rejected (with reason on stderr).
# ----------------------------------------------------------------
if ($ValidatePull) {
    $r = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $r) { Write-Error "Repository '$Repo' not found."; exit 1 }
    if (-not $ModelName) { Write-Error "-ModelName is required."; exit 1 }
    $name = $ModelName.Trim()
    if ($name.Length -eq 0)   { Write-Error "Model name is empty."; exit 1 }
    if ($name.Length -gt 256) { Write-Error "Model name exceeds 256 chars."; exit 1 }
    if ($name -match '[\x00-\x1f]')              { Write-Error "Model name contains control characters."; exit 1 }
    if ($name -match '[\s"''`;|&<>^$()\\]')      { Write-Error "Model name contains shell metacharacters or whitespace."; exit 1 }
    if ($name -match '\.\.')                      { Write-Error "Model name contains '..'"; exit 1 }
    if ($name -match '://')                       { Write-Error "Model name contains a URL scheme."; exit 1 }
    $prefix = ''
    if ($r.PSObject.Properties['pullPrefix']) { $prefix = [string]$r.pullPrefix }
    if ($prefix) {
        if (-not $name.StartsWith($prefix)) {
            Write-Error "Model name '$name' must start with required prefix '$prefix' for repo '$Repo'."; exit 1
        }
        $rest = $name.Substring($prefix.Length)
        if ($rest -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$') {
            Write-Error "Model reference '$rest' does not match expected '<owner>/<model>[:<tag>]' shape."; exit 1
        }
    } else {
        # Empty prefix (e.g. Ollama). Accept: model[:tag] OR namespace/model[:tag].
        if ($name -notmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?(:[A-Za-z0-9._-]+)?$') {
            Write-Error "Model name '$name' has invalid shape for repo '$Repo'."; exit 1
        }
        # First path segment must not look like a hostname (contain a dot).
        if ($name -match '^([^/:]+)/') {
            $first = $Matches[1]
            if ($first.Contains('.')) {
                Write-Error "Model name '$name' appears to specify a remote registry host ('$first'); not allowed for repo '$Repo'."; exit 1
            }
        }
    }
    Write-Host "OK"
    exit 0
}

# ----------------------------------------------------------------
# -DetectHardware : write a single line describing available
# VRAM / RAM / Disk-free so the launcher can color models by fit.
# Output format: VRAM=<gb>|RAM=<gb>|DISK=<gb>|PATH=<models-dir>
# ----------------------------------------------------------------
if ($DetectHardware) {
    if (-not $CacheFile) { $CacheFile = "$env:APPDATA\ollamaLauncher\hardware.txt" }

    # --- VRAM: prefer nvidia-smi; fall back to WMI; cross-check the
    #     PnP-class registry (Win32_VideoController caps at 4GB on
    #     32-bit AdapterRAM for >=4GB cards). Take the maximum value.
    $vramBytes = 0.0
    try {
        $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        if ($LASTEXITCODE -eq 0 -and $nv) {
            foreach ($line in @($nv)) {
                $val = 0.0
                if ([double]::TryParse(([string]$line).Trim(), [ref]$val)) {
                    $b = $val * 1MB
                    if ($b -gt $vramBytes) { $vramBytes = $b }
                }
            }
        }
    } catch {}
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
        foreach ($g in $gpus) {
            if ($g.AdapterRAM) {
                $b = [double]$g.AdapterRAM
                if ($b -gt $vramBytes) { $vramBytes = $b }
            }
        }
    } catch {}
    try {
        $keys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction Stop
        foreach ($k in $keys) {
            $v = (Get-ItemProperty -Path $k.PSPath -Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize'
            if ($v) {
                $b = [double]$v
                if ($b -gt $vramBytes) { $vramBytes = $b }
            }
        }
    } catch {}
    $vramGB = [Math]::Round($vramBytes / 1GB, 1)

    # --- System RAM
    $ramGB = 0.0
    try {
        $ramBytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
        $ramGB = [Math]::Round([double]$ramBytes / 1GB, 1)
    } catch {}

    # --- Disk free on the drive that holds Ollama's models directory
    $ollamaModels = $env:OLLAMA_MODELS
    if (-not $ollamaModels) { $ollamaModels = Join-Path $env:USERPROFILE '.ollama\models' }
    $diskGB = 0.0
    try {
        $qual = Split-Path -Qualifier $ollamaModels
        if ($qual) {
            $letter = $qual.TrimEnd(':')
            $drv = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction Stop
            $diskGB = [Math]::Round([double]$drv.Free / 1GB, 1)
        }
    } catch {}

    $line = "VRAM=$vramGB|RAM=$ramGB|DISK=$diskGB|PATH=$ollamaModels"
    [System.IO.File]::WriteAllText($CacheFile, $line)
    Write-Host $line
    exit 0
}


if (-not $CacheFile) { $CacheFile = "$env:APPDATA\ollamaLauncher\models_cache.txt" }
$CacheDir = Split-Path -Parent $CacheFile
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }

# ----------------------------------------------------------------
# -FetchTags -ModelName X : list every published tag for an Ollama
# library model by scraping https://ollama.com/library/<name>/tags.
# Emits one Name|Size|Params|Description line per tag (same shape
# as the main model cache) so the launcher can re-use its display +
# pull pipeline. Restricted to the Ollama repository because the
# /library/<name>/tags URL pattern is Ollama-specific.
# ----------------------------------------------------------------
if ($FetchTags) {
    if (-not $ModelName) { Write-Error "-ModelName is required for -FetchTags."; exit 1 }
    $r = $repos | Where-Object { $_.name -eq $Repo } | Select-Object -First 1
    if (-not $r) { Write-Error "Repository '$Repo' not found."; exit 1 }
    $tfCfg = Get-PropValue $r 'tagFetch' $null
    $repoHost = ''
    try { $repoHost = ([uri]$r.baseUrl).Host } catch { $repoHost = '' }
    if (-not $tfCfg -and $repoHost -ne 'ollama.com') {
        Write-Error "Tag listing is not configured for repository '$Repo' (add a 'tagFetch' block to repos.json)."; exit 1
    }
    # ModelName may be either a bare ollama name (e.g. 'qwen3') or an
    # HF-style owner/repo id (e.g. 'meta-llama/Llama-3-8B'). Strip a
    # trailing ':<variant>' if present, then validate the remainder.
    $base = ($ModelName -split ':')[0].Trim()
    if ($base.Length -eq 0)   { Write-Error "Model base name is empty."; exit 1 }
    if ($base.Length -gt 256) { Write-Error "Model base name too long."; exit 1 }
    if ($base -notmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$') {
        Write-Error "Invalid model base name '$base' (only A-Z, 0-9, dot, underscore, hyphen, and a single '/' allowed)."; exit 1
    }
    Write-Host "Fetching tags for '$base' from $($r.name)..." -ForegroundColor Gray
    $tags = Get-RepoTags $r $base
    if (-not $tags -or $tags.Count -eq 0) {
        Write-Error "No tags found for '$base'."; exit 1
    }
    $lines = foreach ($t in $tags) { "$($t.Name)|$($t.SizeGB)|$($t.Params)|$($t.Description)" }
    [System.IO.File]::WriteAllLines($CacheFile, $lines)
    Write-Host "Wrote $($tags.Count) tags to $CacheFile" -ForegroundColor Cyan
    exit 0
}

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
# Safe regex wrappers: enforce a 2-second timeout to mitigate ReDoS
# from patterns sourced from a (possibly tampered) repos.json.
$script:RegexTimeout = [TimeSpan]::FromSeconds(2)
function Invoke-SafeRegexMatches([string]$inputText, [string]$pattern) {
    if ([string]::IsNullOrEmpty($pattern)) { return @() }
    try {
        $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::None, $script:RegexTimeout)
        return $rx.Matches($inputText)
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        Write-Host "Regex timed out (skipped): $pattern" -ForegroundColor Yellow; return @()
    } catch {
        Write-Host "Regex error '$pattern': $_" -ForegroundColor Yellow; return @()
    }
}
function Invoke-SafeRegexMatch([string]$inputText, [string]$pattern) {
    if ([string]::IsNullOrEmpty($pattern)) { return $null }
    try {
        $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::None, $script:RegexTimeout)
        return $rx.Match($inputText)
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        Write-Host "Regex timed out (skipped): $pattern" -ForegroundColor Yellow; return $null
    } catch {
        Write-Host "Regex error '$pattern': $_" -ForegroundColor Yellow; return $null
    }
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
        foreach ($m in (Invoke-SafeRegexMatches $html $regex)) {
            $v = $m.Groups[$group].Value
            if ($trim)   { $v = ($v.Trim() -replace '\s+',' ') }
            if ($decode) { $v = [System.Net.WebUtility]::HtmlDecode($v) }
            $vals += $v
        }
        return ,$vals
    }
    $m = Invoke-SafeRegexMatch $html $regex
    if (-not $m -or -not $m.Success) { return $null }
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

function Get-NextLink($response, [string]$expectedHost) {
    $link = $null
    try {
        if ($response.Headers -and $response.Headers.ContainsKey('Link')) {
            $link = $response.Headers['Link']
        }
    } catch { $link = $null }
    if (-not $link) { return $null }
    $linkStr = if ($link -is [System.Array]) { $link -join ', ' } else { [string]$link }
    $m = [regex]::Match($linkStr, '<([^>]+)>;\s*rel="?next"?')
    if (-not $m.Success) { return $null }
    $candidate = $m.Groups[1].Value
    try {
        $u = [uri]$candidate
        if ($u.Scheme -ne 'https') {
            Write-Host "Refusing non-https next link: $candidate" -ForegroundColor Yellow; return $null
        }
        if ($expectedHost -and ($u.Host -ne $expectedHost)) {
            Write-Host "Refusing cross-host next link ($($u.Host) != $expectedHost): $candidate" -ForegroundColor Yellow; return $null
        }
    } catch { return $null }
    return $candidate
}

# ----------------------------------------------------------------
# The single, generic, config-driven fetcher
# ----------------------------------------------------------------
function Invoke-RepoFetch($repo, [int]$Skip, [int]$Limit, [bool]$ExpandTags) {
    $results  = @()
    $skipped  = 0
    $basesProcessed = 0
    $format   = (Get-PropValue $repo 'format' 'html').ToString().ToLower()
    $pag      = Get-PropValue $repo 'pagination' $null
    $pagType  = (Get-PropValue $pag 'type' 'none').ToString().ToLower()
    $maxPages = [int](Get-PropValue $pag 'maxPages' 50)
    $variantField     = [string](Get-PropValue $repo 'expandVariantField' '')
    $variantSeparator = [string](Get-PropValue $repo 'variantNameSeparator' ':')
    $descTemplate     = [string](Get-PropValue $repo 'descriptionTemplate' '')
    $paramsFromName   = [bool](Get-PropValue $repo 'paramsFromName' $false)
    $estimateSize     = [bool](Get-PropValue $repo 'estimateSize' $false)

    # Per-repo tag-fetch configuration drives both:
    #   * Without -ExpandTags : optionally call Get-RepoTags on each
    #     base model to fill the "# of Models" column (gated by
    #     tagFetch.countInMainList so e.g. HF -- which would issue
    #     500+ extra API calls -- stays off by default).
    #   * With    -ExpandTags : emit one row per discovered tag /
    #     variant / quant, optionally hardware-filtered via
    #     $env:HW_VRAM/RAM/DISK.
    $tagFetchCfg    = Get-PropValue $repo 'tagFetch' $null
    $repoHost = ''
    try { $repoHost = ([uri]$repo.baseUrl).Host } catch { $repoHost = '' }
    # Legacy: an ollama.com repo without an explicit tagFetch block
    # still supports the original behavior via Get-RepoTags fallback.
    $canFetchTags   = ($null -ne $tagFetchCfg) -or ($format -eq 'html' -and $repoHost -eq 'ollama.com')
    $countInList    = $true
    if ($tagFetchCfg) { $countInList = [bool](Get-PropValue $tagFetchCfg 'countInMainList' $true) }
    $fetchTagCounts = ($canFetchTags -and $countInList -and -not $ExpandTags)
    $tagCountCache  = @{}

    # Parse hardware budget once (only used with -ExpandTags).
    $hwVram = 0.0; [double]::TryParse($env:HW_VRAM, [ref]$hwVram) | Out-Null
    $hwRam  = 0.0; [double]::TryParse($env:HW_RAM,  [ref]$hwRam)  | Out-Null
    $hwDisk = 0.0; [double]::TryParse($env:HW_DISK, [ref]$hwDisk) | Out-Null
    $hwBudget = $hwVram + $hwRam
    $hwFilterActive = ($ExpandTags -and ($hwBudget -gt 0 -or $hwDisk -gt 0))

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
        # Cap response content to 10MB before any regex/JSON parsing.
        $content = $response.Content
        if ($content -is [string] -and $content.Length -gt 10000000) {
            Write-Host "Truncating response from $($content.Length) to 10MB" -ForegroundColor Yellow
            $content = $content.Substring(0, 10000000)
        }
        if ($format -eq 'html') {
            $itemsCfg = Get-PropValue $repo 'items' $null
            if (-not $itemsCfg) { Write-Error "html repo missing items.regex"; return $results }
            $grp = [int](Get-PropValue $itemsCfg 'group' 1)
            foreach ($m in (Invoke-SafeRegexMatches $content $itemsCfg.regex)) {
                $rawItems += $m.Groups[$grp].Value
            }
        } else {
            $data = $content | ConvertFrom-Json
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
            # In expand mode, $Limit caps the number of base models we visit
            # (each one fans out into many tag rows); otherwise it caps output rows.
            if ($ExpandTags) {
                if ($basesProcessed -ge $Limit) { $hitLimit = $true; break }
            } else {
                if ($results.Count -ge $Limit) { $hitLimit = $true; break }
            }

            $vals = @{}
            foreach ($fp in $repo.fields.PSObject.Properties) {
                if ($format -eq 'html') { $vals[$fp.Name] = Get-FieldFromHtml $raw $fp.Value }
                else                    { $vals[$fp.Name] = Get-FieldFromJson $raw $fp.Value }
            }

            # --- Expand path: emit one row per real published tag (filtered
            #     against hardware budget when env vars are set). Bypasses
            #     the variant-expansion + tag-counting paths below.
            if ($ExpandTags -and $canFetchTags) {
                $baseName = [string]$vals['name']
                if ($baseName) {
                    $basesProcessed++
                    Write-Host "  + Expanding tags for $baseName ($basesProcessed/$Limit)..." -ForegroundColor DarkGray
                    $tags = Get-RepoTags $repo $baseName
                    if ($tags) {
                        foreach ($t in $tags) {
                            $sz = -1.0
                            if     ($t.SizeGB -match '([\d\.]+)\s*GB') { $sz = [double]$Matches[1] }
                            elseif ($t.SizeGB -match '([\d\.]+)\s*MB') { $sz = [double]$Matches[1] / 1024.0 }
                            elseif ($t.SizeGB -match '([\d\.]+)\s*TB') { $sz = [double]$Matches[1] * 1024.0 }
                            elseif ($t.SizeGB -match '<\s*1')          { $sz = 0.5 }
                            if ($hwFilterActive -and $sz -ge 0) {
                                if ($hwDisk   -gt 0 -and $sz -gt $hwDisk)   { continue }
                                if ($hwBudget -gt 0 -and $sz -gt $hwBudget) { continue }
                            }
                            $results += [PSCustomObject]@{ Name=$t.Name; SizeGB=$t.SizeGB; Params=$t.Params; TagCount=''; Description=$t.Description }
                        }
                    }
                }
                continue
            }

            # Look up tag count for this base name (one HTTP per base, cached).
            $tagCount = ''
            if ($fetchTagCounts) {
                $baseName = [string]$vals['name']
                if ($baseName) {
                    if ($tagCountCache.ContainsKey($baseName)) {
                        $tagCount = $tagCountCache[$baseName]
                    } else {
                        Write-Host "  + Counting tags for $baseName..." -ForegroundColor DarkGray
                        $tags = Get-RepoTags $repo $baseName
                        $tagCount = if ($tags) { [string]$tags.Count } else { '' }
                        $tagCountCache[$baseName] = $tagCount
                    }
                }
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

                $results += [PSCustomObject]@{ Name=$name; SizeGB=$size; Params=$params; TagCount=$tagCount; Description=$desc }
            }
            if ($hitLimit) { break }
        }
        if ($ExpandTags) {
            if ($basesProcessed -ge $Limit) { break }
        } else {
            if ($results.Count -ge $Limit) { break }
        }

        # ---- Advance pagination ----
        switch ($pagType) {
            'page'        { $current++ }
            'offset'      { $current += [int](Get-PropValue $pag 'pageSize' $rawItems.Count) }
            'cursor-link' {
                $expectedHost = ''
                try { $expectedHost = ([uri]$repo.baseUrl).Host } catch { $expectedHost = '' }
                $nextUrl = Get-NextLink $response $expectedHost
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

Write-Host "Using repository: $($activeRepo.name) [$($activeRepo.format)]  (limit=$Limit, skip=$Skip, expand=$ExpandTags)" -ForegroundColor Cyan

$models = Invoke-RepoFetch $activeRepo $Skip $Limit ([bool]$ExpandTags)

# ----------------------------------------------------------------
# Write cache
# ----------------------------------------------------------------
$lines = @()
foreach ($model in $models) {
    $tc = ''
    if ($model.PSObject.Properties['TagCount']) { $tc = [string]$model.TagCount }
    $lines += "$($model.Name)|$($model.SizeGB)|$($model.Params)|$tc|$($model.Description)"
}
if ($Append) { [System.IO.File]::AppendAllLines($CacheFile, $lines) }
else         { [System.IO.File]::WriteAllLines($CacheFile, $lines) }
Write-Host "Successfully fetched $($models.Count) models from $($activeRepo.name)."
