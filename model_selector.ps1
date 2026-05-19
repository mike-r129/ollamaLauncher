# model_selector.ps1
# Interactive arrow-key model selector for ollamaLauncher.bat.

param(
    [string]$SortedFile,
    [string]$LocalFile,
    [int]$Page = 1,
    [int]$PerPage = 50,
    [int]$TotalPages = 1,
    [int]$SelIndex = 1,
    [string]$Repo = "Ollama",
    [string]$SearchTerm = "",
    [string]$SortInfo = "Default",
    [string]$HwFilterLabel = "OFF",
    [string]$VramGb = "0",
    [string]$RamGb = "0",
    [string]$DiskGb = "0",
    [string]$ContextLength = "4096",
    [string]$HasTags = "0",
    [string]$ResultFile
)

$ErrorActionPreference = 'Stop'

function Write-Result([string]$action, $arg) {
    $selected = $script:SelIndex
    if ($null -eq $selected) { $selected = $SelIndex }
    $currentPage = $script:Page
    if ($null -eq $currentPage) { $currentPage = $Page }

    $line = $action
    if ($null -ne $arg -and "$arg" -ne "") { $line = "$action|$arg" }
    $content = $line + "`r`n" + "SEL_INDEX=" + $selected + "`r`n" + "PAGE=" + $currentPage + "`r`n"
    try {
        [System.IO.File]::WriteAllText($ResultFile, $content, [System.Text.Encoding]::ASCII)
    } catch {
        try { Set-Content -Path $ResultFile -Value @($line, ("SEL_INDEX=" + $selected), ("PAGE=" + $currentPage)) -Encoding ASCII -Force } catch {}
    }
}

$installed = @{}
if (Test-Path $LocalFile) {
    Get-Content $LocalFile -Encoding UTF8 | ForEach-Object { if ($_) { $installed[$_] = $true } }
}

$script:vram = 0.0; [double]::TryParse($env:HW_VRAM, [ref]$script:vram) | Out-Null
$script:ram  = 0.0; [double]::TryParse($env:HW_RAM,  [ref]$script:ram)  | Out-Null
$script:disk = 0.0; [double]::TryParse($env:HW_DISK, [ref]$script:disk) | Out-Null
$script:contextLength = 4096
# Prefer env var (set by batch) over -ContextLength param to avoid binding issues
$_ctxSrc = if ($env:OLLAMA_LAUNCHER_CTX) { $env:OLLAMA_LAUNCHER_CTX } else { $ContextLength }
try {
    $_clean = ("$_ctxSrc").Trim()
    if ($_clean) { $script:contextLength = [int]$_clean }
} catch { $script:contextLength = 4096 }

$script:all = @()
if (Test-Path $SortedFile) {
    $script:all = @(Import-Csv $SortedFile -Delimiter '|' -Header 'Name','Size','Params','TagCount','Description' -Encoding UTF8)
}

$script:totalItems = $script:all.Count
$script:TotalPages = [Math]::Max(1, [int][Math]::Ceiling($script:totalItems / [double]$PerPage))
if ($TotalPages -gt $script:TotalPages) { $script:TotalPages = $TotalPages }

$script:Page = $Page
$script:SelIndex = $SelIndex
$script:viewStart = 0
$script:rows = @()
$script:rowStartY = 0
$script:statusY = 0
$script:lastWidth = 0
$script:lastHeight = 0
$script:nameWidth = 25
$script:descWidth = 5
$script:visibleRows = 0

function Get-FitColor([string]$sizeStr) {
    $sizeGb = -1.0
    if ($sizeStr -match '([\d\.]+)\s*GB') { $sizeGb = [double]$matches[1] }
    elseif ($sizeStr -match '([\d\.]+)\s*MB') { $sizeGb = [double]$matches[1] / 1024.0 }
    elseif ($sizeStr -match '<\s*1') { $sizeGb = 0.5 }

    # Add context memory overhead (rough estimate: context_tokens / 50000 * model_size_gb)
    if ($sizeGb -gt 0) {
        $contextOverhead = ($script:contextLength / 50000.0) * $sizeGb
        $sizeGb = $sizeGb + $contextOverhead
    }

    if ($sizeGb -lt 0) { return 'Gray' }
    if ($script:disk -gt 0 -and $sizeGb -gt $script:disk) { return 'Red' }
    if ($script:vram -gt 0 -and $sizeGb -le $script:vram) { return 'Green' }
    if ($sizeGb -le ($script:vram + $script:ram)) { return 'Yellow' }
    return 'Red'
}

function Limit-Text([string]$text, [int]$maxLen) {
    if ($null -eq $text) { $text = '' }
    if ($maxLen -le 0) { return '' }
    if ($text.Length -le $maxLen) { return $text }
    if ($maxLen -le 3) { return $text.Substring(0, $maxLen) }
    return ($text.Substring(0, $maxLen - 3) + '...')
}

function Update-Layout {
    try { $width = [Console]::WindowWidth } catch { $width = 80 }
    try { $height = [Console]::WindowHeight } catch { $height = 30 }
    if ($width -lt 40) { $width = 40 }
    if ($height -lt 10) { $height = 10 }

    $script:lastWidth = $width
    $script:lastHeight = $height
    $script:nameWidth = [Math]::Min(25, [Math]::Max(12, $width - 43))
    $script:descWidth = [Math]::Max(0, ($width - 1) - 41 - $script:nameWidth)

    $reservedLines = 14
    $rows = $height - $reservedLines
    if ($rows -lt 1) { $rows = 1 }
    if ($rows -gt $script:pageSize) { $rows = $script:pageSize }
    if ($script:pageSize -eq 0) { $rows = 0 }
    $script:visibleRows = $rows
}

function Build-PageRows {
    $script:rows = @()
    for ($offset = 0; $offset -lt $script:pageSize; $offset++) {
        $item = $script:pageItems[$offset]
        $absIdx = $script:start + $offset + 1

        $name = Limit-Text $item.Name $script:nameWidth
        $desc = $item.Description
        if ($null -eq $desc) { $desc = '' }
        if ($installed.ContainsKey($item.Name)) { $desc = '[Installed] ' + $desc }
        $desc = Limit-Text $desc $script:descWidth

        $script:rows += [pscustomobject]@{
            Idx      = $absIdx
            Name     = $name
            Size     = $item.Size
            Params   = $item.Params
            TagCount = $item.TagCount
            Desc     = $desc
            Color    = (Get-FitColor $item.Size)
        }
    }
}

function Set-PageState([int]$newPage, [int]$preferredSelection) {
    if ($newPage -lt 1) { $newPage = 1 }
    if ($newPage -gt $script:TotalPages) { $newPage = $script:TotalPages }
    $script:Page = $newPage

    $script:start = ($script:Page - 1) * $PerPage
    if ($script:start -lt 0) { $script:start = 0 }
    $script:endExclusive = [Math]::Min($script:start + $PerPage, $script:totalItems)
    $script:pageSize = $script:endExclusive - $script:start
    if ($script:pageSize -gt 0) {
        $script:pageItems = @($script:all[$script:start..($script:endExclusive - 1)])
        $script:minIdx = $script:start + 1
        $script:maxIdx = $script:start + $script:pageSize
        if ($preferredSelection -lt $script:minIdx) { $preferredSelection = $script:minIdx }
        if ($preferredSelection -gt $script:maxIdx) { $preferredSelection = $script:maxIdx }
        $script:SelIndex = $preferredSelection
    } else {
        $script:pageItems = @()
        $script:minIdx = 0
        $script:maxIdx = 0
        $script:SelIndex = 0
    }

    Update-Layout
    Build-PageRows

    if ($script:pageSize -gt 0 -and $script:visibleRows -gt 0) {
        $localSelection = $script:SelIndex - $script:minIdx
        $script:viewStart = $localSelection - $script:visibleRows + 1
        if ($script:viewStart -lt 0) { $script:viewStart = 0 }
        $maxViewStart = [Math]::Max(0, $script:pageSize - $script:visibleRows)
        if ($script:viewStart -gt $maxViewStart) { $script:viewStart = $maxViewStart }
    } else {
        $script:viewStart = 0
    }
}

function Console-SizeChanged {
    try {
        return ([Console]::WindowWidth -ne $script:lastWidth -or [Console]::WindowHeight -ne $script:lastHeight)
    } catch {
        return $false
    }
}

function Write-PaddedLine([string]$text) {
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 1) { $width = 1 }
    if ($null -eq $text) { $text = '' }
    if ($text.Length -gt $width) { $text = $text.Substring(0, $width) }
    Write-Host ($text + (' ' * ($width - $text.Length)))
}

function Row-MainText($row) {
    $format = '{0,-' + $script:nameWidth + '} {1,-10} {2,-8}'
    return ($format -f $row.Name, $row.Size, $row.Params)
}

function Draw-Row($row, [bool]$isSelected) {
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 1) { $width = 1 }

    $marker = if ($isSelected) { '>' } else { ' ' }
    $prefix = '{0} {1,3}. ' -f $marker, $row.Idx
    $main = Row-MainText $row
    $tagCount = if ([string]::IsNullOrEmpty($row.TagCount)) { (' ' * 11) } else { ('{0,-11}' -f $row.TagCount) }
    $desc = '  ' + $row.Desc
    $rendered = $prefix + $main + ' ' + $tagCount + $desc
    $padCount = $width - $rendered.Length
    if ($padCount -lt 0) { $padCount = 0 }
    $pad = ' ' * $padCount

    if ($isSelected) {
        Write-Host $prefix -NoNewline -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host $main -NoNewline -ForegroundColor $row.Color -BackgroundColor DarkBlue
        Write-Host (' ' + $tagCount) -NoNewline -ForegroundColor Cyan -BackgroundColor DarkBlue
        Write-Host ($desc + $pad) -ForegroundColor Gray -BackgroundColor DarkBlue
    } else {
        Write-Host $prefix -NoNewline
        Write-Host $main -NoNewline -ForegroundColor $row.Color
        if ([string]::IsNullOrEmpty($row.TagCount)) {
            Write-Host (' ' + $tagCount) -NoNewline
        } else {
            Write-Host (' ' + $tagCount) -NoNewline -ForegroundColor Cyan
        }
        Write-Host ($desc + $pad)
    }
}

function Safe-SetCursor([int]$x, [int]$y) {
    try {
        if ($y -lt 0) { $y = 0 }
        $maxY = [Console]::BufferHeight - 1
        if ($y -gt $maxY) { $y = $maxY }
        [Console]::SetCursorPosition($x, $y)
        return $true
    } catch {
        return $false
    }
}

function Build-NavLine {
    $nav = ''
    if ($script:Page -gt 1) { $nav += '[Left/P] Prev   ' }
    if ($script:Page -lt $script:TotalPages) { $nav += '[Right/N] Next   ' }
    $nav += '[R] Refresh   [E] Repo'
    return $nav
}

function Build-HelpLine {
    $tagsOption = ''
    if ($HasTags -eq '1') { $tagsOption = '[Tab/V] View Tags  ' }
    return "[Up/Down] Move  [Enter] Select  $tagsOption[F] Find  [S] Sort Size  [B] Best Sort  [L] Context  [I] Sort Field  [D] Default  [A] Expand All  [C] Cancel  [X] Exit"
}

function Build-StatusLine {
    if ($script:pageSize -gt 0) {
        return ("Selected: #{0} of {1} (page {2}/{3}) - arrows move, Enter pulls, Tab views tags, or type a number/name..." -f $script:SelIndex, $script:totalItems, $script:Page, $script:TotalPages)
    }
    return 'No models to display. Press a command key (R/E/F/X)...'
}

function Render-Full {
    Clear-Host
    Write-PaddedLine ''
    Write-PaddedLine ("Hardware: VRAM={0}GB  RAM={1}GB  Disk={2}GB   Filter: {3}   |   Context: {4:N0} tokens" -f $VramGb, $RamGb, $DiskGb, $HwFilterLabel, $script:contextLength)
    Write-PaddedLine 'Legend: [green]=fits VRAM  [yellow]=spills to RAM  [red]=will not fit'
    Write-PaddedLine ''
    if ($SearchTerm) {
        Write-PaddedLine ("Showing Models (Page {0}/{1}) - Search Results: {2}  [Repo: {3}]" -f $script:Page, $script:TotalPages, $SearchTerm, $Repo)
    } else {
        Write-PaddedLine ("Showing Models (Page {0}/{1}) - Sorted by: {2}  [Repo: {3}]" -f $script:Page, $script:TotalPages, $SortInfo, $Repo)
    }
    Write-PaddedLine ''
    $headerFormat = '  {0,-4} {1,-' + $script:nameWidth + '} {2,-10} {3,-8} {4,-11}  {5}'
    Write-PaddedLine ($headerFormat -f 'Num', 'Model Name', 'Size (GB)', 'Params', '# of Models', 'Description')
    Write-PaddedLine ($headerFormat -f ('-' * 4), ('-' * $script:nameWidth), ('-' * 10), ('-' * 8), ('-' * 11), ('-' * $script:descWidth))

    $script:rowStartY = [Console]::CursorTop
    if ($script:pageSize -eq 0) {
        Write-PaddedLine '  (no models on this page)'
    } else {
        for ($rowOffset = 0; $rowOffset -lt $script:visibleRows; $rowOffset++) {
            $localIndex = $script:viewStart + $rowOffset
            Draw-Row $script:rows[$localIndex] (($script:minIdx + $localIndex) -eq $script:SelIndex)
        }
    }

    Write-PaddedLine ''
    Write-PaddedLine (Build-NavLine)
    Write-PaddedLine (Build-HelpLine)
    Write-PaddedLine ''
    $script:statusY = [Console]::CursorTop
    $status = Build-StatusLine
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 1) { $width = 1 }
    if ($status.Length -gt $width) { $status = $status.Substring(0, $width) }
    Write-Host $status -NoNewline
}

function Redraw-Row([int]$localIndex) {
    if ($localIndex -lt $script:viewStart -or $localIndex -ge ($script:viewStart + $script:visibleRows)) { return }
    $y = $script:rowStartY + ($localIndex - $script:viewStart)
    if (-not (Safe-SetCursor 0 $y)) { return }
    Draw-Row $script:rows[$localIndex] (($script:minIdx + $localIndex) -eq $script:SelIndex)
}

function Redraw-Status {
    if (-not (Safe-SetCursor 0 $script:statusY)) { return }
    $status = Build-StatusLine
    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 1) { $width = 1 }
    if ($status.Length -gt $width) { $status = $status.Substring(0, $width) }
    else { $status = $status + (' ' * ($width - $status.Length)) }
    Write-Host $status -NoNewline
}

function Move-Selection([int]$delta) {
    if ($script:pageSize -le 0) { return }
    $newSelection = $script:SelIndex + $delta
    if ($newSelection -lt $script:minIdx) { $newSelection = $script:minIdx }
    if ($newSelection -gt $script:maxIdx) { $newSelection = $script:maxIdx }
    if ($newSelection -eq $script:SelIndex) { return }

    $oldLocal = $script:SelIndex - $script:minIdx
    $newLocal = $newSelection - $script:minIdx
    $script:SelIndex = $newSelection

    if ($newLocal -lt $script:viewStart -or $newLocal -ge ($script:viewStart + $script:visibleRows)) {
        if ($newLocal -lt $script:viewStart) { $script:viewStart = $newLocal }
        else { $script:viewStart = $newLocal - $script:visibleRows + 1 }
        Render-Full
    } else {
        Redraw-Row $oldLocal
        Redraw-Row $newLocal
        Redraw-Status
    }
}

function Jump-Selection([int]$absoluteIndex) {
    if ($script:pageSize -le 0) { return }
    if ($absoluteIndex -lt $script:minIdx) { $absoluteIndex = $script:minIdx }
    if ($absoluteIndex -gt $script:maxIdx) { $absoluteIndex = $script:maxIdx }
    Move-Selection ($absoluteIndex - $script:SelIndex)
}

function Change-Page([int]$newPage) {
    if ($newPage -lt 1 -or $newPage -gt $script:TotalPages -or $newPage -eq $script:Page) { return }
    $preferredSelection = (($newPage - 1) * $PerPage) + 1
    Set-PageState $newPage $preferredSelection
    Render-Full
}

function Read-SeededInput([char]$char) {
    if (-not (Safe-SetCursor 0 ($script:statusY + 1))) { Write-Host '' }
    Write-Host 'Enter model number or name: ' -NoNewline
    Write-Host $char -NoNewline
    [Console]::CursorVisible = $true
    try { $rest = [Console]::ReadLine() } catch { $rest = '' }
    [Console]::CursorVisible = $false
    return ("$char" + "$rest")
}

Set-PageState $Page $SelIndex

$commandLetters = @('R','F','E','S','B','L','I','D','A','C','X','V','T','H','U')

try { [Console]::CursorVisible = $false } catch {}

try {
    Render-Full
    while ($true) {
        # Check for console size changes frequently (before waiting for input)
        if (Console-SizeChanged) {
            Set-PageState $script:Page $script:SelIndex
            Render-Full
        }
        
        # Check if a key is available (non-blocking)
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
        } else {
            # Sleep briefly to avoid consuming CPU while still responding to resizes
            [System.Threading.Thread]::Sleep(100)
            continue
        }

        switch ($key.Key) {
            'UpArrow'    { Move-Selection -1; break }
            'DownArrow'  { Move-Selection 1; break }
            'LeftArrow'  { Change-Page ($script:Page - 1); break }
            'RightArrow' { Change-Page ($script:Page + 1); break }
            'PageUp'     { if ($script:visibleRows -gt 0) { Move-Selection (-$script:visibleRows) }; break }
            'PageDown'   { if ($script:visibleRows -gt 0) { Move-Selection $script:visibleRows }; break }
            'Home'       { Jump-Selection $script:minIdx; break }
            'End'        { Jump-Selection $script:maxIdx; break }
            'Enter'      { if ($script:pageSize -gt 0) { Write-Result 'SELECT' $script:SelIndex; return }; break }
            'Tab'        { if ($script:pageSize -gt 0) { Write-Result 'EXPAND' $script:SelIndex; return }; break }
            'Escape'     { Write-Result 'CMD' 'C'; return }
            default {
                $char = $key.KeyChar
                if ([char]::IsLetter($char)) {
                    $upper = ([string]$char).ToUpper()
                    if ($upper -eq 'N') { Change-Page ($script:Page + 1); break }
                    if ($upper -eq 'P') { Change-Page ($script:Page - 1); break }
                    if ($upper -eq 'R') {
                        try { [Console]::CursorVisible = $true } catch {}
                        Write-Host "`n`n=============== Re-pull Models ===============" -ForegroundColor Cyan
                        Write-Host "This will clear the cached model list and re-fetch from the server." -ForegroundColor Yellow
                        Write-Host "This may take a moment depending on your connection speed." -ForegroundColor Yellow
                        Write-Host ""
                        $confirm = Read-Host "Are you sure you want to refresh? (Y/N)"
                        try { [Console]::CursorVisible = $false } catch {}
                        if ($confirm -ieq 'Y') {
                            Write-Result 'CMD' 'R'
                            return
                        }
                        Render-Full
                        break
                    }
                    if ($commandLetters -contains $upper) {
                        Write-Result 'CMD' $upper
                        return
                    }
                    Write-Result 'INPUT' (Read-SeededInput $char)
                    return
                }
                if ([char]::IsDigit($char)) {
                    Write-Result 'INPUT' (Read-SeededInput $char)
                    return
                }
                break
            }
        }
    }
} catch {
    Write-Result 'CMD' 'C'
} finally {
    try { [Console]::CursorVisible = $true } catch {}
}