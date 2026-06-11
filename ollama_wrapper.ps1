# ollama_wrapper.ps1
# Runs ollama pull/run for the launcher with shared context-length handling.
# Output streams directly to the console; type '/set verbose' inside an
# interactive run session to see tokens/sec stats from ollama itself.

param(
    [string]$ModelName = "",
    [int]$ContextLength = 0,
    [switch]$Pull,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = (Get-Location).Path }

# Delegate to OllamaCli when running beside the module tree; fall back to
# direct ollama invocation so legacy AppData copies of this script keep working.
$OllamaCliModule = Join-Path $ScriptRoot 'src\OllamaLauncher\OllamaCli.psm1'
if (Test-Path -LiteralPath $OllamaCliModule) {
    Import-Module $OllamaCliModule -Force -DisableNameChecking
}

if ($ContextLength -gt 0) {
    $env:OLLAMA_CONTEXT_LENGTH = $ContextLength.ToString()
}

if (-not $ModelName -or (-not $Pull -and -not $Run)) {
    Write-Host 'Usage: ollama_wrapper.ps1 -Pull|-Run -ModelName <name> [-ContextLength <tokens>]' -ForegroundColor Yellow
    exit 1
}

try {
    if ($Pull) {
        Write-Host "Pulling model: $ModelName`n"
        if (Get-Command Invoke-OllamaPull -ErrorAction SilentlyContinue) {
            Invoke-OllamaPull -ModelName $ModelName
        } else {
            & ollama pull $ModelName
        }
    }
    else {
        if ($ContextLength -gt 0) {
            Write-Host "Running model: $ModelName (context: $ContextLength tokens)"
        } else {
            Write-Host "Running model: $ModelName"
        }
        Write-Host "Tip: type '/set verbose' in the session to see tokens/sec stats.`n" -ForegroundColor DarkGray
        if (Get-Command Invoke-OllamaRun -ErrorAction SilentlyContinue) {
            Invoke-OllamaRun -ModelName $ModelName -ContextLength $ContextLength
        } else {
            & ollama run $ModelName
        }
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
exit 0
