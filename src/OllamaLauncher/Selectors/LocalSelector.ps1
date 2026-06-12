# local_selector.ps1
# Interactive main-screen model selector for ollamaLauncher.bat.
# Shows locally installed models with green/yellow/red hardware-fit colours
# and lets the user adjust context length inline so they can see the impact.

param(
    [string]$LocalFile,
    [string]$VramGb = "0",
    [string]$RamGb  = "0",
    [string]$DiskGb = "0",
    [int]$ContextLength = 4096,
    [string]$CurrentRepo = "Ollama",
    [string]$ResultFile
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------
# Result writer
# Line 1 : ACTION[|ARG]
# Line 2 : CTX=<tokens>   (so batch can persist a context change)
# ----------------------------------------------------------------
function Write-Result([string]$action, $arg) {
    $line = $action
    if ($null -ne $arg -and "$arg" -ne "") { $line = "$action|$arg" }
    $content = $line + "`r`n" + "CTX=" + $script:contextLength + "`r`n"
    try {
        [System.IO.File]::WriteAllText($ResultFile, $content, [System.Text.Encoding]::ASCII)
    } catch {
        try { Set-Content -Path $ResultFile -Value @($line, ("CTX=" + $script:contextLength)) -Encoding ASCII -Force } catch {}
    }
}

# ----------------------------------------------------------------
# Hardware values
# ----------------------------------------------------------------
$script:vram = 0.0; [double]::TryParse($VramGb, [ref]$script:vram) | Out-Null
$script:ram  = 0.0; [double]::TryParse($RamGb,  [ref]$script:ram)  | Out-Null
$script:disk = 0.0; [double]::TryParse($DiskGb, [ref]$script:disk) | Out-Null
$script:contextLength = $ContextLength

# ----------------------------------------------------------------
# Model loading  (same field extraction as fetch_models.ps1 -Local)
# ----------------------------------------------------------------
function Load-Models {
    $script:models = @()
    try {
        $output = ollama list | Select-Object -Skip 1
        foreach ($line in $output) {
            if ($line -match '^(\S+)\s+\S+\s+(\S+\s+\S+)') {
                $name    = $matches[1]
                $rawSize = $matches[2].Trim()
                $params  = 'N/A'
                if ($name -match ':(\d+(\.\d+)?[bm])') { $params = $matches[1] }
                elseif ($name -match '(\d+(\.\d+)?[bm])') { $params = $matches[1] }
                $script:models += [pscustomobject]@{ Name = $name; Size = $rawSize; Params = $params }
            }
        }
    } catch {
        $script:models = @()
    }

    # Write model names to LocalFile so the repo browser can mark installed models
    if ($LocalFile -and $script:models.Count -gt 0) {
        try {
            $names = $script:models | ForEach-Object { $_.Name }
            [System.IO.File]::WriteAllLines($LocalFile, $names, [System.Text.Encoding]::UTF8)
        } catch {}
    }
}

# ----------------------------------------------------------------
# Model metadata and KV cache calculation
# ----------------------------------------------------------------
function Get-SizeGb([string]$sizeStr) {
    # '< 1 GB' must be checked before the GB pattern, which would match the
    # literal '1' and overstate the size.
    if ($sizeStr -match '<\s*1')          { return 0.5 }
    if ($sizeStr -match '([\d\.]+)\s*GB') { return [double]$matches[1] }
    if ($sizeStr -match '([\d\.]+)\s*MB') { return [double]$matches[1] / 1024.0 }
    return -1.0
}

# 'ollama show' spawns a subprocess; cache results so navigation and context
# previews never re-query a model we already inspected this session.
$script:metadataCache = @{}

function Get-ModelMetadata([string]$modelName) {
    if ($script:metadataCache.ContainsKey($modelName)) { return $script:metadataCache[$modelName] }
    $meta = @{}
    try {
        $output = ollama show "$modelName" 2>$null | ForEach-Object { $_.Trim() }
        foreach ($line in $output) {
            if ($line -match '^\s*(\S+)\s+(.+)$') {
                $key = $matches[1]
                $val = $matches[2]
                $meta[$key] = $val
            }
        }
    } catch {
        $meta = @{}
    }
    $script:metadataCache[$modelName] = $meta
    return $meta
}

function Calculate-KvCacheGb([hashtable]$metadata, [int]$contextTokens) {
    try {
        $numLayers = if ($metadata.ContainsKey('num_layers')) { [int]$metadata['num_layers'] } else { 0 }
        $numKvHeads = if ($metadata.ContainsKey('num_kv_head')) { [int]$metadata['num_kv_head'] } else { 0 }
        $headDim = if ($metadata.ContainsKey('embedding_length')) { [int]$metadata['embedding_length'] / ([Math]::Max(1, $numKvHeads)) } else { 128 }

        if ($numLayers -eq 0 -or $numKvHeads -eq 0) { return 0.0 }

        $bytesPerElement = 2.0
        $kvCacheBytes = $contextTokens * $numLayers * 2 * $numKvHeads * $headDim * $bytesPerElement
        $kvCacheGb = $kvCacheBytes / 1073741824.0

        return $kvCacheGb
    } catch {
        return 0.0
    }
}

function Get-TotalMemoryEstimate([string]$modelName, [string]$sizeStr, [int]$contextTokens) {
    $weightsGb = Get-SizeGb $sizeStr
    if ($weightsGb -lt 0) { return -1.0 }

    $metadata = Get-ModelMetadata $modelName
    $kvCacheGb = Calculate-KvCacheGb $metadata $contextTokens
    $safetyMargin = 1.15

    return ($weightsGb + $kvCacheGb) * $safetyMargin
}

function Get-FitColor([string]$modelName, [string]$sizeStr, [int]$contextTokens) {
    $totalGb = Get-TotalMemoryEstimate $modelName $sizeStr $contextTokens

    if ($totalGb -lt 0)                                      { return 'Gray'   }
    if ($script:disk -gt 0 -and $totalGb -gt $script:disk)  { return 'Red'    }
    if ($script:vram -gt 0 -and $totalGb -le $script:vram)  { return 'Green'  }
    if ($totalGb -le ($script:vram + $script:ram))          { return 'Yellow' }
    return 'Red'
}

# ----------------------------------------------------------------
# Console helpers
# ----------------------------------------------------------------
function Write-PaddedLine([string]$text) {
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 1) { $width = 1 }
    if ($null -eq $text) { $text = '' }
    if ($text.Length -gt $width) { $text = $text.Substring(0, $width) }
    Write-Host ($text + (' ' * ($width - $text.Length)))
}

function Limit-Text([string]$text, [int]$maxLen) {
    if ($null -eq $text) { $text = '' }
    if ($maxLen -le 0)             { return '' }
    if ($text.Length -le $maxLen)  { return $text }
    if ($maxLen -le 3)             { return $text.Substring(0, $maxLen) }
    return ($text.Substring(0, $maxLen - 3) + '...')
}

function Get-SafeCursorTop {
    try { return [Console]::CursorTop } catch { return -1 }
}

function Safe-SetCursor([int]$x, [int]$y) {
    try {
        if ($y -lt 0) { return $false }
        $maxY = [Console]::BufferHeight - 1
        if ($y -gt $maxY) { return $false }
        [Console]::SetCursorPosition($x, $y)
        return $true
    } catch {
        return $false
    }
}

# ----------------------------------------------------------------
# Layout state
# ----------------------------------------------------------------
$script:selIdx     = 0
$script:nameWidth  = 25
$script:statusY    = -1
$script:rowStartY  = -1
$script:lastWidth  = 0
$script:lastHeight = 0
$script:rows       = @()

function Update-NameWidth {
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 40) { $width = 40 }
    $script:nameWidth = [Math]::Min(30, [Math]::Max(15, $width - 38))
}

function Console-SizeChanged {
    try {
        return ([Console]::WindowWidth -ne $script:lastWidth -or [Console]::WindowHeight -ne $script:lastHeight)
    } catch {
        return $false
    }
}

# ----------------------------------------------------------------
# Rendering
# ----------------------------------------------------------------
# Precompute per-row colour and fit label once per (models, context) change so
# navigating never re-runs the memory estimate, let alone 'ollama show'.
function Build-Rows {
    $script:rows = @()
    foreach ($m in $script:models) {
        $color = Get-FitColor $m.Name $m.Size $script:contextLength
        $fitLabel = switch ($color) {
            'Green'  { 'Fits VRAM' }
            'Yellow' { 'RAM needed' }
            'Red'    { 'Too large' }
            default  { 'Unknown' }
        }
        $script:rows += [pscustomobject]@{
            Name   = $m.Name
            Size   = $m.Size
            Params = $m.Params
            Color  = $color
            Fit    = $fitLabel
        }
    }
}

function Draw-Row([int]$index, [bool]$isSelected) {
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 40) { $width = 40 }

    $row      = $script:rows[$index]
    $marker   = if ($isSelected) { '>' } else { ' ' }
    $name     = Limit-Text $row.Name $script:nameWidth
    $prefix   = "  $marker {0,3}. " -f ($index + 1)
    $mainText = ('{0,-' + $script:nameWidth + '} {1,-12} {2,-8}') -f $name, $row.Size, $row.Params
    $fitPart  = "  $($row.Fit)"

    $fullLen = $prefix.Length + $mainText.Length + $fitPart.Length
    $padding = ' ' * [Math]::Max(0, $width - $fullLen)

    if ($isSelected) {
        Write-Host $prefix    -NoNewline -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host $mainText  -NoNewline -ForegroundColor $row.Color -BackgroundColor DarkBlue
        Write-Host ($fitPart + $padding) -ForegroundColor Gray -BackgroundColor DarkBlue
    } else {
        Write-Host $prefix    -NoNewline
        Write-Host $mainText  -NoNewline -ForegroundColor $row.Color
        Write-Host ($fitPart + $padding)
    }
}

function Build-StatusLine {
    if ($script:models.Count -gt 0) {
        return ("Selected: #{0} of {1} - {2}" -f ($script:selIdx + 1), $script:models.Count, $script:models[$script:selIdx].Name)
    }
    return 'No local models installed. Use [U] or [0] to pull a model from the repository.'
}

function Render-Full {
    Update-NameWidth
    try { $script:lastWidth = [Console]::WindowWidth; $script:lastHeight = [Console]::WindowHeight } catch {}

    Clear-Host
    Write-PaddedLine ''
    Write-PaddedLine ("Hardware: VRAM={0}GB  RAM={1}GB  Disk={2}GB   |   Context: {3:N0} tokens  (press C to adjust)" -f $VramGb, $RamGb, $DiskGb, $script:contextLength)
    Write-PaddedLine 'Legend: [green]=fits VRAM  [yellow]=spills to RAM  [red]=will not fit  [gray]=size unknown'
    Write-PaddedLine ''

    $hFmt = '  {0,-4} {1,-' + $script:nameWidth + '} {2,-12} {3,-8}  {4}'
    Write-PaddedLine ($hFmt -f 'Num', 'Model Name', 'Size', 'Params', 'Fit')
    Write-PaddedLine ($hFmt -f ('-'*4), ('-'*$script:nameWidth), ('-'*12), ('-'*8), ('-'*14))

    $script:rowStartY = Get-SafeCursorTop

    if ($script:rows.Count -eq 0) {
        Write-PaddedLine '  (no installed models - press U or 0 to pull a model)'
    } else {
        for ($i = 0; $i -lt $script:rows.Count; $i++) {
            Draw-Row $i ($i -eq $script:selIdx)
        }
    }

    Write-PaddedLine ''
    Write-PaddedLine ("[0/U] Pull/Update   [E] Repository ($CurrentRepo)   [R] Remove   [C] Context ({0:N0})   [L] Launch Ollama   [X] Exit" -f $script:contextLength)
    Write-PaddedLine '[Up/Down] Move   [Enter] Run selected model   or type a number and press Enter'
    Write-PaddedLine ''

    $script:statusY = Get-SafeCursorTop
    $statusMsg = Build-StatusLine
    try { $w = [Console]::BufferWidth - 1 } catch { $w = 79 }
    if ($w -lt 1) { $w = 1 }
    if ($statusMsg.Length -gt $w) { $statusMsg = $statusMsg.Substring(0, $w) }
    else { $statusMsg = $statusMsg + (' ' * ($w - $statusMsg.Length)) }
    Write-Host $statusMsg -NoNewline
}

function Redraw-Row([int]$index) {
    if ($script:rowStartY -lt 0) { return $false }
    if (-not (Safe-SetCursor 0 ($script:rowStartY + $index))) { return $false }
    Draw-Row $index ($index -eq $script:selIdx)
    return $true
}

function Redraw-Status {
    if (-not (Safe-SetCursor 0 $script:statusY)) { return }
    $statusMsg = Build-StatusLine
    try { $w = [Console]::BufferWidth - 1 } catch { $w = 79 }
    if ($w -lt 1) { $w = 1 }
    if ($statusMsg.Length -gt $w) { $statusMsg = $statusMsg.Substring(0, $w) }
    else { $statusMsg = $statusMsg + (' ' * ($w - $statusMsg.Length)) }
    Write-Host $statusMsg -NoNewline
}

# Redraw only the rows that changed instead of clearing the screen, so
# arrow-key navigation does not flicker.
function Move-Selection([int]$delta) {
    if ($script:models.Count -eq 0) { return }
    $newIdx = $script:selIdx + $delta
    if ($newIdx -lt 0) { $newIdx = $script:models.Count - 1 }
    elseif ($newIdx -ge $script:models.Count) { $newIdx = 0 }
    if ($newIdx -eq $script:selIdx) { return }

    $oldIdx = $script:selIdx
    $script:selIdx = $newIdx

    if (-not (Redraw-Row $oldIdx) -or -not (Redraw-Row $newIdx)) {
        Render-Full
        return
    }
    Redraw-Status
}

# ----------------------------------------------------------------
# Inline context selector (matches context_selector.ps1 options)
# Returns $true if context was changed.
# ----------------------------------------------------------------
function Show-ContextSelector {
    $contexts = @(
        [pscustomobject]@{ label = '4K';   tokens = 4096   },
        [pscustomobject]@{ label = '8K';   tokens = 8192   },
        [pscustomobject]@{ label = '16K';  tokens = 16384  },
        [pscustomobject]@{ label = '32K';  tokens = 32768  },
        [pscustomobject]@{ label = '64K';  tokens = 65536  },
        [pscustomobject]@{ label = '128K'; tokens = 131072 },
        [pscustomobject]@{ label = '256K'; tokens = 262144 }
    )

    $ci = 0
    for ($i = 0; $i -lt $contexts.Count; $i++) {
        if ($contexts[$i].tokens -eq $script:contextLength) { $ci = $i; break }
    }

    # Compute the KV cache delta per option once, up front (one cached
    # 'ollama show' at most) instead of per option per keypress.
    $notes = @()
    $meta = $null
    if ($script:models.Count -gt 0) { $meta = Get-ModelMetadata $script:models[0].Name }
    $currentKv = if ($meta) { Calculate-KvCacheGb $meta $script:contextLength } else { 0.0 }
    foreach ($ctx in $contexts) {
        $note = ''
        if ($meta) {
            $kvDelta = (Calculate-KvCacheGb $meta $ctx.tokens) - $currentKv
            if ($kvDelta -gt 0)     { $note = ' (+{0:N1} GB KV cache)' -f $kvDelta }
            elseif ($kvDelta -lt 0) { $note = ' (-{0:N1} GB KV cache)' -f [Math]::Abs($kvDelta) }
        }
        $notes += $note
    }

    function Draw-ContextOption([int]$i, [bool]$isSelected) {
        $ctx = $contexts[$i]
        $line = "  {0}. {1,-5}  ({2,8:N0} tokens){3}" -f ($i + 1), $ctx.label, $ctx.tokens, $notes[$i]
        if ($isSelected) {
            Write-Host $line -BackgroundColor Cyan -ForegroundColor Black
        } else {
            Write-Host $line -ForegroundColor White
        }
    }

    # Render the menu once; arrow keys repaint only the two affected rows.
    Clear-Host
    Write-Host ''
    Write-Host '=============== Context Length Selection ===============' -ForegroundColor Cyan
    Write-Host ("Current: {0:N0} tokens - higher context = more memory overhead" -f $script:contextLength) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Choose context window size:' -ForegroundColor White
    Write-Host ''
    $optionStartY = Get-SafeCursorTop
    for ($i = 0; $i -lt $contexts.Count; $i++) {
        Draw-ContextOption $i ($i -eq $ci)
    }
    Write-Host ''
    Write-Host '[Up/Down] Move   [Enter] Select   [1-7] Quick select   [Esc/C] Cancel' -ForegroundColor Gray
    Write-Host ''

    $changed = $false

    while ($true) {
        $k = [Console]::ReadKey($true)

        if ($k.Key -eq [ConsoleKey]::UpArrow -or $k.Key -eq [ConsoleKey]::DownArrow) {
            $oldCi = $ci
            if ($k.Key -eq [ConsoleKey]::UpArrow) {
                $ci = if ($ci -gt 0) { $ci - 1 } else { $contexts.Count - 1 }
            } else {
                $ci = if ($ci -lt $contexts.Count - 1) { $ci + 1 } else { 0 }
            }
            if ($optionStartY -ge 0 -and (Safe-SetCursor 0 ($optionStartY + $oldCi))) {
                Draw-ContextOption $oldCi $false
                if (Safe-SetCursor 0 ($optionStartY + $ci)) { Draw-ContextOption $ci $true }
            }
        } elseif ($k.Key -eq [ConsoleKey]::Enter) {
            $script:contextLength = $contexts[$ci].tokens
            $changed = $true
            break
        } elseif ($k.Key -eq [ConsoleKey]::Escape -or $k.KeyChar -eq 'c' -or $k.KeyChar -eq 'C') {
            break
        } elseif ([char]::IsDigit($k.KeyChar)) {
            $d = [int]::Parse([string]$k.KeyChar)
            if ($d -ge 1 -and $d -le $contexts.Count) {
                $script:contextLength = $contexts[$d - 1].tokens
                $changed = $true
                break
            }
        }
    }
    return $changed
}

# ----------------------------------------------------------------
# Typed number input (seeded with first char already pressed)
# ----------------------------------------------------------------
function Read-NumberInput([char]$seedChar) {
    try { [Console]::CursorVisible = $true } catch {}
    try { $w = [Console]::BufferWidth - 1 } catch { $w = 79 }
    if ($w -lt 1) { $w = 1 }
    $prompt = 'Run model number: '
    try { [Console]::SetCursorPosition(0, $script:statusY) } catch {}
    $display = $prompt + $seedChar + (' ' * [Math]::Max(0, $w - $prompt.Length - 1))
    if ($display.Length -gt $w) { $display = $display.Substring(0, $w) }
    Write-Host $display -NoNewline
    try { [Console]::SetCursorPosition($prompt.Length + 1, $script:statusY) } catch {}
    try { $rest = [Console]::ReadLine() } catch { $rest = '' }
    try { [Console]::CursorVisible = $false } catch {}
    return ("$seedChar" + "$rest")
}

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
Load-Models
Build-Rows

# Clamp selection to valid range after (re-)loading
if ($script:models.Count -eq 0) {
    $script:selIdx = 0
} elseif ($script:selIdx -ge $script:models.Count) {
    $script:selIdx = $script:models.Count - 1
}

try { [Console]::CursorVisible = $false } catch {}

try {
    Render-Full

    while ($true) {
        if (Console-SizeChanged) {
            Render-Full
        }

        if (-not [Console]::KeyAvailable) {
            [System.Threading.Thread]::Sleep(50)
            continue
        }

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'UpArrow' {
                Move-Selection -1
                break
            }
            'DownArrow' {
                Move-Selection 1
                break
            }
            'Enter' {
                if ($script:models.Count -gt 0) {
                    Write-Result 'SELECT' $script:models[$script:selIdx].Name
                    return
                }
                break
            }
            'Escape' {
                Write-Result 'CMD' 'X'
                return
            }
            default {
                $char = $key.KeyChar
                if ([char]::IsLetter($char)) {
                    $upper = ([string]$char).ToUpper()
                    switch ($upper) {
                        'U' { Write-Result 'CMD' 'U'; return }
                        'E' { Write-Result 'CMD' 'E'; return }
                        'R' { Write-Result 'CMD' 'R'; return }
                        'L' { Write-Result 'CMD' 'L'; return }
                        'X' { Write-Result 'CMD' 'X'; return }
                        'C' {
                            if (Show-ContextSelector) {
                                # Context changed: fit colours depend on it
                                Build-Rows
                            }
                            Render-Full
                            break
                        }
                        default { break }
                    }
                } elseif ([char]::IsDigit($char)) {
                    if ($char -eq '0') {
                        Write-Result 'CMD' 'U'
                        return
                    }
                    $numStr = (Read-NumberInput $char).Trim()
                    $num = 0
                    if ([int]::TryParse($numStr, [ref]$num)) {
                        if ($num -eq 0) {
                            Write-Result 'CMD' 'U'
                            return
                        }
                        if ($num -ge 1 -and $num -le $script:models.Count) {
                            Write-Result 'SELECT' $script:models[$num - 1].Name
                            return
                        }
                    }
                    # Invalid number - just redraw
                    Render-Full
                }
                break
            }
        }
    }
} catch {
    Write-Result 'CMD' 'X'
} finally {
    try { [Console]::CursorVisible = $true } catch {}
}
