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

function Render {
    Clear-Host
    Write-Host ''
    Write-Host '=============== Context Length Selection ===============' -ForegroundColor Cyan
    Write-Host "Current context length: $CurrentContext tokens" -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Select context length (affects model usability estimates):' -ForegroundColor White
    Write-Host ''

    for ($i = 0; $i -lt $contexts.Count; $i++) {
        $ctx = $contexts[$i]
        if ($i -eq $selectedIdx) {
            Write-Host ("  {0}. {1,-5} ({2:N0} tokens)" -f $ctx.number, $ctx.label, $ctx.tokens) -BackgroundColor Cyan -ForegroundColor Black
        } else {
            Write-Host ("  {0}. {1,-5} ({2:N0} tokens)" -f $ctx.number, $ctx.label, $ctx.tokens) -ForegroundColor White
        }
    }

    Write-Host ''
    Write-Host '[Up/Down] Move  [Enter] Select  [C] Cancel  [X] Exit' -ForegroundColor Gray
    Write-Host ''
}

try {
    [Console]::CursorVisible = $false
    Render

    while ($true) {
        $key = [System.Console]::ReadKey($true)

        if ($key.Key -eq [System.ConsoleKey]::UpArrow) {
            $selectedIdx = if ($selectedIdx -gt 0) { $selectedIdx - 1 } else { $contexts.Count - 1 }
            Render
        }
        elseif ($key.Key -eq [System.ConsoleKey]::DownArrow) {
            $selectedIdx = if ($selectedIdx -lt $contexts.Count - 1) { $selectedIdx + 1 } else { 0 }
            Render
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
