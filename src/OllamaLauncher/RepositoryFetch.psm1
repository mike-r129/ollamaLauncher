Import-Module (Join-Path $PSScriptRoot 'RepositoryParse.psm1') -Force

function Get-OllamaModelTags {
    param([string]$Base)

    $base = ($Base -split ':')[0].Trim()
    if ($base.Length -eq 0)   { return @() }
    if ($base.Length -gt 128) { return @() }
    if ($base -notmatch '^[A-Za-z0-9._-]+$') { return @() }

    try {
        $response = Invoke-WebRequest -Uri "https://ollama.com/library/$base/tags" -UseBasicParsing -TimeoutSec 15
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
        $rxSize = [regex]::new('(\d+(?:\.\d+)?)\s*(GB|MB|TB)', [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
        $rxCtx  = [regex]::new('(\d+K)\s*context\s*window', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $timeout)
        $rxHash = [regex]::new('font-mono"\s*>\s*([a-f0-9]{12})', [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
        $rxAge  = [regex]::new('(\d+\s+\w+\s+ago)', [System.Text.RegularExpressions.RegexOptions]::None, $timeout)
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
        $start = $m.Index + $m.Length
        $winLen = [Math]::Min(1500, $content.Length - $start)
        if ($winLen -le 0) { continue }
        $win = $content.Substring($start, $winLen)
        $sz = '?'
        try { $sm = $rxSize.Match($win); if ($sm.Success) { $sz = "$($sm.Groups[1].Value) $($sm.Groups[2].Value)" } } catch {}
        $ctx = ''
        try { $cm = $rxCtx.Match($win); if ($cm.Success) { $ctx = $cm.Groups[1].Value } } catch {}
        $hash = ''
        try { $hm = $rxHash.Match($win); if ($hm.Success) { $hash = $hm.Groups[1].Value } } catch {}
        $age = ''
        try { $am = $rxAge.Match($win); if ($am.Success) { $age = $am.Groups[1].Value } } catch {}
        $fullName = "$base`:$tag"
        $params = Get-ModelParamsFromName $fullName
        $descParts = @()
        if ($ctx)  { $descParts += "Context: $ctx" }
        if ($hash) { $descParts += "Hash: $hash" }
        if ($age)  { $descParts += "Updated $age" }
        $desc = if ($descParts.Count -gt 0) { $descParts -join '  ' } else { 'Tag variant' }
        $out += [PSCustomObject]@{ Name=$fullName; SizeGB=$sz; Params=$params; Description=$desc }
    }
    return $out
}

function Get-HuggingFaceModelTags {
    param([string]$Base, $Sources)

    if (-not $Sources) { return @() }
    $base = $Base.Trim()
    if ($base.Length -eq 0 -or $base.Length -gt 256) { return @() }
    if ($base -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { return @() }

    $encBase = [uri]::EscapeDataString($base)
    $seen = @{}
    $out  = @()
    foreach ($src in $Sources) {
        $label = [string](Get-RepoProperty $src 'label' '')
        $tpl = [string](Get-RepoProperty $src 'urlTemplate' '')
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
            $id = [string](Get-RepoProperty $it 'id' '')
            if (-not $id) { continue }
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $dl = Get-RepoProperty $it 'downloads' 0
            $lk = Get-RepoProperty $it 'likes' 0
            $pipe = [string](Get-RepoProperty $it 'pipeline_tag' '')
            $params = Get-ModelParamsFromName $id
            $size = Get-ModelSizeEstimate $params
            $descParts = @()
            if ($label) { $descParts += "[$label]" }
            if ($pipe)  { $descParts += $pipe }
            $descParts += "Downloads: $dl"
            $descParts += "Likes: $lk"
            $out += [PSCustomObject]@{ Name=$id; SizeGB=$size; Params=$params; Description=($descParts -join ' ') }
        }
    }
    return $out
}

function Get-RepoTags {
    param($Repo, [string]$Base)

    $cfg = Get-RepoProperty $Repo 'tagFetch' $null
    if (-not $cfg) {
        $rh = ''
        try { $rh = ([uri]$Repo.baseUrl).Host } catch { $rh = '' }
        if ($rh -eq 'ollama.com') { return Get-OllamaModelTags $Base }
        return @()
    }

    switch (([string](Get-RepoProperty $cfg 'type' '')).ToLower()) {
        'ollama-library' { return Get-OllamaModelTags $Base }
        'huggingface-base-model' {
            return Get-HuggingFaceModelTags $Base (Get-RepoProperty $cfg 'sources' $null)
        }
        default {
            Write-Host "Unknown tagFetch.type '$($cfg.type)' for repo '$($Repo.name)'." -ForegroundColor Yellow
            return @()
        }
    }
}

function Invoke-RepoFetch {
    param($Repo, [int]$Skip, [int]$Limit, [bool]$ExpandTags)

    $results = @()
    $skipped = 0
    $basesProcessed = 0
    $format = (Get-RepoProperty $Repo 'format' 'html').ToString().ToLower()
    $pag = Get-RepoProperty $Repo 'pagination' $null
    $pagType = (Get-RepoProperty $pag 'type' 'none').ToString().ToLower()
    $maxPages = [int](Get-RepoProperty $pag 'maxPages' 50)
    $variantField = [string](Get-RepoProperty $Repo 'expandVariantField' '')
    $variantSeparator = [string](Get-RepoProperty $Repo 'variantNameSeparator' ':')
    $descTemplate = [string](Get-RepoProperty $Repo 'descriptionTemplate' '')
    $paramsFromName = [bool](Get-RepoProperty $Repo 'paramsFromName' $false)
    $estimateSize = [bool](Get-RepoProperty $Repo 'estimateSize' $false)

    $tagFetchCfg = Get-RepoProperty $Repo 'tagFetch' $null
    $repoHost = ''
    try { $repoHost = ([uri]$Repo.baseUrl).Host } catch { $repoHost = '' }
    $canFetchTags = ($null -ne $tagFetchCfg) -or ($format -eq 'html' -and $repoHost -eq 'ollama.com')
    $countInList = $true
    if ($tagFetchCfg) { $countInList = [bool](Get-RepoProperty $tagFetchCfg 'countInMainList' $true) }
    $fetchTagCounts = ($canFetchTags -and $countInList -and -not $ExpandTags)
    $tagCountCache = @{}

    $hwVram = 0.0; [double]::TryParse($env:HW_VRAM, [ref]$hwVram) | Out-Null
    $hwRam  = 0.0; [double]::TryParse($env:HW_RAM,  [ref]$hwRam)  | Out-Null
    $hwDisk = 0.0; [double]::TryParse($env:HW_DISK, [ref]$hwDisk) | Out-Null
    $hwBudget = $hwVram + $hwRam
    $hwFilterActive = ($ExpandTags -and ($hwBudget -gt 0 -or $hwDisk -gt 0))

    $nextUrl = $null
    $current = $null
    if ($pagType -eq 'page')   { $current = [int](Get-RepoProperty $pag 'start' 1) }
    if ($pagType -eq 'offset') { $current = [int](Get-RepoProperty $pag 'start' 0) }

    for ($pageIdx = 0; $pageIdx -lt $maxPages; $pageIdx++) {
        if ($pagType -eq 'cursor-link' -and $nextUrl) {
            $url = $nextUrl
        } else {
            $extra = @{}
            if ($pagType -eq 'page' -or $pagType -eq 'offset') {
                $extra[$pag.param] = [string]$current
            }
            $psp = Get-RepoProperty $pag 'pageSizeParam' $null
            $ps = Get-RepoProperty $pag 'pageSize' $null
            if ($psp -and $ps) { $extra[$psp] = [string]$ps }
            $url = New-RepositoryRequestUrl $Repo $extra
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

        $rawItems = @()
        $content = $response.Content
        if ($content -is [string] -and $content.Length -gt 10000000) {
            Write-Host "Truncating response from $($content.Length) to 10MB" -ForegroundColor Yellow
            $content = $content.Substring(0, 10000000)
        }
        if ($format -eq 'html') {
            $itemsCfg = Get-RepoProperty $Repo 'items' $null
            if (-not $itemsCfg) { Write-Error "html repo missing items.regex"; return $results }
            $grp = [int](Get-RepoProperty $itemsCfg 'group' 1)
            foreach ($m in (Invoke-SafeRegexMatches $content $itemsCfg.regex)) {
                $rawItems += $m.Groups[$grp].Value
            }
        } else {
            $data = $content | ConvertFrom-Json
            $itemsCfg = Get-RepoProperty $Repo 'items' $null
            $path = [string](Get-RepoProperty $itemsCfg 'path' '$')
            if ($path -eq '$' -or [string]::IsNullOrEmpty($path)) {
                $rawItems = @($data)
            } else {
                $cur = $data
                foreach ($p in ($path -split '\.')) {
                    if ($p -ne '$' -and $p -ne '') { $cur = $cur.$p }
                }
                $rawItems = @($cur)
            }
        }

        if (-not $rawItems -or $rawItems.Count -eq 0) {
            Write-Host "No more items. Pagination complete." -ForegroundColor Gray
            break
        }

        $hitLimit = $false
        foreach ($raw in $rawItems) {
            if ($skipped -lt $Skip) { $skipped++; continue }
            if ($ExpandTags) {
                if ($basesProcessed -ge $Limit) { $hitLimit = $true; break }
            } else {
                if ($results.Count -ge $Limit) { $hitLimit = $true; break }
            }

            $vals = @{}
            foreach ($fp in $Repo.fields.PSObject.Properties) {
                if ($format -eq 'html') { $vals[$fp.Name] = Get-FieldFromHtml $raw $fp.Value }
                else                    { $vals[$fp.Name] = Get-FieldFromJson $raw $fp.Value }
            }

            if ($ExpandTags -and $canFetchTags) {
                $baseName = [string]$vals['name']
                if ($baseName) {
                    $basesProcessed++
                    Write-Host "  + Expanding tags for $baseName ($basesProcessed/$Limit)..." -ForegroundColor DarkGray
                    $tags = Get-RepoTags $Repo $baseName
                    foreach ($t in @($tags)) {
                        $sz = ConvertTo-ModelSizeGb $t.SizeGB
                        if ($hwFilterActive -and $sz -ge 0) {
                            if ($hwDisk -gt 0 -and $sz -gt $hwDisk) { continue }
                            if ($hwBudget -gt 0 -and $sz -gt $hwBudget) { continue }
                        }
                        $results += [PSCustomObject]@{ Name=$t.Name; SizeGB=$t.SizeGB; Params=$t.Params; TagCount=''; Description=$t.Description }
                    }
                }
                continue
            }

            $tagCount = ''
            if ($fetchTagCounts) {
                $baseName = [string]$vals['name']
                if ($baseName) {
                    if ($tagCountCache.ContainsKey($baseName)) {
                        $tagCount = $tagCountCache[$baseName]
                    } else {
                        Write-Host "  + Counting tags for $baseName..." -ForegroundColor DarkGray
                        $tags = Get-RepoTags $Repo $baseName
                        $tagCount = if ($tags) { [string]$tags.Count } else { '' }
                        $tagCountCache[$baseName] = $tagCount
                    }
                }
            }

            $variants = @($null)
            if ($variantField -and $vals.ContainsKey($variantField)) {
                $vf = $vals[$variantField]
                if ($vf -is [System.Array] -and $vf.Count -gt 0) { $variants = $vf }
            }

            foreach ($v in $variants) {
                if ($results.Count -ge $Limit) { $hitLimit = $true; break }
                $name = [string]$vals['name']
                $params = 'N/A'
                if ($v) {
                    $name = "$name$variantSeparator$v"
                    $params = [string]$v
                }
                if ($params -eq 'N/A' -and $paramsFromName) { $params = Get-ModelParamsFromName $name }

                $desc = ''
                if ($descTemplate)          { $desc = Expand-RepoTemplate $descTemplate $vals }
                elseif ($vals['description']) { $desc = [string]$vals['description'] }
                if (-not $desc) { $desc = 'No description available' }
                $size = if ($estimateSize) { Get-ModelSizeEstimate $params } else { 'Unknown' }
                $results += [PSCustomObject]@{ Name=$name; SizeGB=$size; Params=$params; TagCount=$tagCount; Description=$desc }
            }
            if ($hitLimit) { break }
        }

        if ($ExpandTags) {
            if ($basesProcessed -ge $Limit) { break }
        } else {
            if ($results.Count -ge $Limit) { break }
        }

        switch ($pagType) {
            'page'   { $current++ }
            'offset' { $current += [int](Get-RepoProperty $pag 'pageSize' $rawItems.Count) }
            'cursor-link' {
                $expectedHost = ''
                try { $expectedHost = ([uri]$Repo.baseUrl).Host } catch { $expectedHost = '' }
                $nextUrl = Get-RepositoryNextLink $response $expectedHost
                if (-not $nextUrl) {
                    Write-Host "No next link; pagination ends." -ForegroundColor Gray
                    break
                }
            }
            default { return $results }
        }
        if ($pagType -eq 'cursor-link' -and -not $nextUrl) { break }
    }
    return $results
}

Export-ModuleMember -Function Get-OllamaModelTags,
    Get-HuggingFaceModelTags,
    Get-RepoTags,
    Invoke-RepoFetch
