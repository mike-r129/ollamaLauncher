# ollama_wrapper.ps1
# Wraps ollama commands and displays tokens/sec in top-right corner

param(
    [string]$Command = "run",
    [string]$ModelName = "",
    [int]$ContextLength = 0,
    [switch]$Pull,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

if ($ContextLength -gt 0) {
    $env:OLLAMA_CONTEXT_LENGTH = $ContextLength.ToString()
}

# Store metrics
$script:tokensPerSec = 0
$script:totalTokens = 0
$script:totalTime = 0

function Format-TopRight([string]$text, [string]$color = "Cyan") {
    try {
        $width = [Console]::BufferWidth
        $height = [Console]::CursorTop
    } catch {
        $width = 80
        $height = 0
    }
    
    if ($text.Length -gt 20) { $text = $text.Substring(0, 17) + "..." }
    $padding = $width - $text.Length - 1
    if ($padding -lt 0) { $padding = 0 }
    
    Write-Host (" " * $padding) -NoNewline -ForegroundColor $color
    Write-Host $text -ForegroundColor $color
}

function Parse-OllamaMetrics([string]$line) {
    # Look for patterns like "tokens/sec: 45.2" or "45 tokens in 1.5s (30.0 tokens/sec)"
    if ($line -match 'tokens/sec[:\s]+([0-9.]+)') {
        $script:tokensPerSec = [double]$matches[1]
        return $true
    }
    if ($line -match '([0-9]+)\s+tokens?\s+in\s+([0-9.]+)s\s+\(([0-9.]+)\s+tokens/sec\)') {
        $script:tokensPerSec = [double]$matches[3]
        $script:totalTokens = [int]$matches[1]
        $script:totalTime = [double]$matches[2]
        return $true
    }
    return $false
}

try {
    if ($Pull -and $ModelName) {
        # Running: ollama pull modelname
        Write-Host "Pulling model: $ModelName`n"
        $process = Start-Process -FilePath "ollama" -ArgumentList "pull", $ModelName -NoNewWindow -PassThru -RedirectStandardOutput $env:TEMP\ollama_output.txt -RedirectStandardError $env:TEMP\ollama_error.txt
        
        $lastDisplayTime = [DateTime]::MinValue
        while (-not $process.HasExited) {
            $now = [DateTime]::Now
            if (($now - $lastDisplayTime).TotalMilliseconds -gt 500) {
                if (Test-Path $env:TEMP\ollama_output.txt) {
                    $lastLine = Get-Content $env:TEMP\ollama_output.txt | Select-Object -Last 1
                    if ($lastLine -and (Parse-OllamaMetrics $lastLine)) {
                        Format-TopRight "tok/s: $('{0:F1}' -f $script:tokensPerSec)" "Cyan"
                    }
                }
                $lastDisplayTime = $now
            }
            Start-Sleep -Milliseconds 100
        }
        
        # Show final output
        if (Test-Path $env:TEMP\ollama_output.txt) {
            Get-Content $env:TEMP\ollama_output.txt | ForEach-Object {
                Write-Host $_
                Parse-OllamaMetrics $_
            }
        }
        
        Write-Host ""
        if ($script:tokensPerSec -gt 0) {
            Format-TopRight "Done: $('{0:F1}' -f $script:tokensPerSec) tok/s" "Green"
            Write-Host "`nFinal metrics: $script:totalTokens tokens in $($script:totalTime)s"
        }
    }
    elseif ($Run -and $ModelName) {
        # Running: ollama run modelname (interactive mode - display metrics as they come)
        if ($ContextLength -gt 0) {
            Write-Host "Running model: $ModelName (context: $ContextLength tokens)`n"
        } else {
            Write-Host "Running model: $ModelName`n"
        }
        
        $process = Start-Process -FilePath "ollama" -ArgumentList "run", $ModelName -NoNewWindow -PassThru -RedirectStandardOutput $env:TEMP\ollama_run_output.txt -RedirectStandardError $env:TEMP\ollama_run_error.txt
        
        # Monitor output while running
        $lastPos = 0
        $lastDisplayTime = [DateTime]::MinValue
        
        while (-not $process.HasExited) {
            $now = [DateTime]::Now
            if (($now - $lastDisplayTime).TotalMilliseconds -gt 200) {
                if (Test-Path $env:TEMP\ollama_run_output.txt) {
                    $content = Get-Content $env:TEMP\ollama_run_output.txt
                    $lines = @($content)
                    
                    foreach ($line in $lines) {
                        if ($line.Length -gt 0) {
                            if (Parse-OllamaMetrics $line) {
                                Format-TopRight "tok/s: $('{0:F1}' -f $script:tokensPerSec)" "Cyan"
                            }
                        }
                    }
                }
                $lastDisplayTime = $now
            }
            Start-Sleep -Milliseconds 100
        }
        
        # Display final metrics
        if (Test-Path $env:TEMP\ollama_run_output.txt) {
            $finalContent = Get-Content $env:TEMP\ollama_run_output.txt -Raw
            Write-Host $finalContent
            
            # Extract final metrics
            $lines = $finalContent -split "`n"
            foreach ($line in $lines) {
                Parse-OllamaMetrics $line
            }
        }
        
        Write-Host ""
        if ($script:tokensPerSec -gt 0) {
            Format-TopRight "Final: $('{0:F1}' -f $script:tokensPerSec) tok/s" "Green"
        }
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup temp files
    Remove-Item -Path $env:TEMP\ollama_output.txt -ErrorAction SilentlyContinue
    Remove-Item -Path $env:TEMP\ollama_error.txt -ErrorAction SilentlyContinue
    Remove-Item -Path $env:TEMP\ollama_run_output.txt -ErrorAction SilentlyContinue
    Remove-Item -Path $env:TEMP\ollama_run_error.txt -ErrorAction SilentlyContinue
}
