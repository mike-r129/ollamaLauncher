param([int]$Skip=0,[int]$Limit=100,[switch]$Append,[string]$CacheFile,[switch]$Local)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
# Set default cache file if not provided
if (-not $CacheFile) {
    $CacheFile = "$env:APPDATA\ollamaLauncher\models_cache.txt"
}
# Ensure cache directory exists
$CacheDir = Split-Path -Parent $CacheFile
if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}
if ($Local) {
    # Local mode: List installed models
    try {
        $output = ollama list | Select-Object -Skip 1
        $models = @()
        foreach ($line in $output) {
            if ($line -match '^(\S+)\s+\S+\s+(\S+\s+\S+)') {
                $name = $matches[1]
                $size = $matches[2]
                $params = 'N/A'
                if ($name -match ':(\d+(\.\d+)?[bm])') { $params = $matches[1] }
                elseif ($name -match '(\d+(\.\d+)?[bm])') { $params = $matches[1] }
                $models += [PSCustomObject]@{Name=$name; Size=$size; Params=$params; Description='Installed'}
            }
        }
        if ($models.Count -eq 0) { exit 1 }
        # Output to cache file for batch script to read
        if ($CacheFile) {
            [System.IO.File]::WriteAllLines($CacheFile, @($models.Name))
        }
        # Display table
        try{$w=$Host.UI.RawUI.WindowSize.Width}catch{$w=80}; if($w -lt 60){$w=60}; $dw=$w-53; if($dw -lt 5){$dw=5}
        Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f 'Num','Model Name','Size','Params','Description')
        Write-Host ('{0,-4} {1,-25} {2,-10} {3,-8}  {4}' -f ('-'*4),('-'*25),('-'*10),('-'*8),('-'*$dw))
        $k=0
        foreach ($m in $models) {
            $k++
            $n=$m.Name; if($n.Length -gt 25){$n=$n.Substring(0,22)+'...'};
            Write-Host ('{0,3}. {1,-25} {2,-10} {3,-8}  {4}' -f $k,$n,$m.Size,$m.Params,$m.Description)
        }
        exit 0
    } catch {
        Write-Error $_
        exit 1
    }
}
# Fetch HTML from Ollama model library
$url='https://ollama.com/search'
try {
    $response=Invoke-WebRequest -Uri $url -UseBasicParsing
    $content=$response.Content
} catch {
    Write-Error $_
    exit 1
}
# Extract model list items from HTML
$modelRegex=[regex]'(?s)<li x-test-model(.*?)</li>'
$modelMatches=$modelRegex.Matches($content)
$models=@()
$count=0
$skipped=0
# Process each model: extract name, description, and size estimates
foreach($match in $modelMatches) {
    if($skipped -lt $Skip) { $skipped++; continue }
    if($count -ge $Limit) { break }
    $modelHtml=$match.Groups[1].Value
    # Extract model name from title
    $nameRegex=[regex]'x-test-search-response-title>([^<]+)<'
    $nameMatch=$nameRegex.Match($modelHtml)
    $name=if($nameMatch.Success){[System.Net.WebUtility]::HtmlDecode($nameMatch.Groups[1].Value.Trim())}else{'Unknown'}
    # Extract description
    $descRegex=[regex]'(?s)<p[^>]*text-neutral-800[^>]*>(.*?)</p>'
    $descMatch=$descRegex.Match($modelHtml)
    $description=if($descMatch.Success){($descMatch.Groups[1].Value.Trim()-replace '\s+', ' ')}else{'No description available'}
    # Extract and estimate download size based on parameters
  $sizeRegex=[regex]'x-test-size[^>]*>([^<]+)<'
  $sizeMatches=$sizeRegex.Matches($modelHtml)
  if($sizeMatches.Count -gt 0) {
        foreach($sm in $sizeMatches) {
            $paramSize=$sm.Groups[1].Value.Trim()
            $gbSize='Unknown'
            # Standard models: size = (params * compression) + overhead
            if($paramSize -match '(\d+(\.\d+)?)b'){
                $pMatch=$Matches
                $val=[double]$pMatch[1]
                if($val -le 3){$est=$val*0.6+0.5}elseif($val -le 10){$est=$val*0.55+0.5}else{$est=$val*0.56}
                $gbSize='{0:N1} GB'-f $est
            }
            # Tiny models
            elseif($paramSize -match '(\d+)m') {
                $gbSize='< 1 GB'
            }
            # MoE models (e.g. Mixtral 8x7B): size = (experts * expert_size) * compression
            elseif($paramSize -match '(\d+)x(\d+(\.\d+)?)b'){
                $mMatch=$Matches
                $experts=[double]$mMatch[1]
                $eSize=[double]$mMatch[2]
                $total=$experts*$eSize
                $est=$total*0.46
                $gbSize='{0:N1} GB'-f $est
            }
            $fullName="$name`:$paramSize"
            $models+=[PSCustomObject]@{Name=$fullName;SizeGB=$gbSize;Params=$paramSize;Description=$description}
        }
    } else {
        $models+=[PSCustomObject]@{Name=$name;SizeGB='Unknown';Params='N/A';Description=$description}
    }
    $count++
}
# Output results in pipe-delimited format (Name|Size|Params|Description)
$lines=@()
foreach($model in $models) {
    $lines+="$($model.Name)|$($model.SizeGB)|$($model.Params)|$($model.Description)"
}
if($Append) {
    [System.IO.File]::AppendAllLines($CacheFile, $lines)
} else {
    [System.IO.File]::WriteAllLines($CacheFile, $lines)
}
Write-Host "Successfully fetched $($models.Count) models."
