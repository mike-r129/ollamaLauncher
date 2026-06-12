# context_selector.ps1
# Interactive arrow-key context length selector for ollamaLauncher.bat.

param(
    [int]$CurrentContext = 4096,
    [string]$ResultFile
)

$ErrorActionPreference = 'Stop'

function Write-Result([string]$action) {
    try {
        [System.IO.File]::WriteAllText($ResultFile, $action, [System.Text.Encoding]::ASCII)
    } catch {
        try { Set-Content -Path $ResultFile -Value $action -Encoding ASCII -Force } catch {}
    }
}

$contexts = @(
    @{ number = 1; label = '4K'; tokens = 4096 },
    @{ number = 2; label = '8K'; tokens = 8192 },
    @{ number = 3; label = '16K'; tokens = 16384 },
    @{ number = 4; label = '32K'; tokens = 32768 },
    @{ number = 5; label = '64K'; tokens = 65536 },
    @{ number = 6; label = '128K'; tokens = 131072 },
    @{ number = 7; label = '256K'; tokens = 262144 }
)

$selectedIdx = 0
for ($i = 0; $i -lt $contexts.Count; $i++) {
    if ($contexts[$i].tokens -eq $CurrentContext) {
        $selectedIdx = $i
        break
    }
}

$script:optionStartY = -1

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

function Draw-Option([int]$i, [bool]$isSelected) {
    $ctx = $contexts[$i]
    $line = "  {0}. {1,-5} ({2:N0} tokens)" -f $ctx.number, $ctx.label, $ctx.tokens
    if ($isSelected) {
        Write-Host $line -BackgroundColor Cyan -ForegroundColor Black
    } else {
        Write-Host $line -ForegroundColor White
    }
}

# Full render happens once; arrow keys repaint only the two affected rows so
# navigation does not flicker.
function Render {
    Clear-Host
    Write-Host ''
    Write-Host '=============== Context Length Selection ===============' -ForegroundColor Cyan
    Write-Host "Current context length: $CurrentContext tokens" -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Select context length (affects model usability estimates):' -ForegroundColor White
    Write-Host ''

    $script:optionStartY = Get-SafeCursorTop
    for ($i = 0; $i -lt $contexts.Count; $i++) {
        Draw-Option $i ($i -eq $selectedIdx)
    }

    Write-Host ''
    Write-Host '[Up/Down] Move  [Enter] Select  [C] Cancel  [X] Exit' -ForegroundColor Gray
    Write-Host ''
}

function Move-Selection([int]$newIdx) {
    $oldIdx = $script:selectedIdx
    if ($newIdx -eq $oldIdx) { return }
    $script:selectedIdx = $newIdx

    if ($script:optionStartY -ge 0 -and (Safe-SetCursor 0 ($script:optionStartY + $oldIdx))) {
        Draw-Option $oldIdx $false
        if (Safe-SetCursor 0 ($script:optionStartY + $newIdx)) {
            Draw-Option $newIdx $true
            return
        }
    }
    Render
}

try {
    try { [Console]::CursorVisible = $false } catch {}
    Render

    while ($true) {
        $key = [System.Console]::ReadKey($true)

        if ($key.Key -eq [System.ConsoleKey]::UpArrow) {
            Move-Selection $(if ($selectedIdx -gt 0) { $selectedIdx - 1 } else { $contexts.Count - 1 })
        }
        elseif ($key.Key -eq [System.ConsoleKey]::DownArrow) {
            Move-Selection $(if ($selectedIdx -lt $contexts.Count - 1) { $selectedIdx + 1 } else { 0 })
        }
        elseif ($key.Key -eq [System.ConsoleKey]::Enter) {
            $selected = $contexts[$selectedIdx]
            Write-Result $selected.tokens.ToString()
            break
        }
        elseif ($key.KeyChar -eq 'C' -or $key.KeyChar -eq 'c') {
            Write-Result 'CANCEL'
            break
        }
        elseif ($key.KeyChar -eq 'X' -or $key.KeyChar -eq 'x') {
            Write-Result 'EXIT'
            break
        }
        elseif ([char]::IsDigit($key.KeyChar)) {
            $digit = [int]::Parse([string]$key.KeyChar)
            if ($digit -ge 1 -and $digit -le 7) {
                $selected = $contexts[$digit - 1]
                Write-Result $selected.tokens.ToString()
                break
            }
        }
    }
} catch {
    Write-Result 'CANCEL'
} finally {
    try { [Console]::CursorVisible = $true } catch {}
}
