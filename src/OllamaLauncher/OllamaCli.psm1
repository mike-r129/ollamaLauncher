function Test-OllamaCommand {
    [CmdletBinding()]
    param()

    return [bool](Get-Command ollama -ErrorAction SilentlyContinue)
}

function Start-OllamaServer {
    [CmdletBinding()]
    param([switch]$Minimized)

    if ($Minimized) {
        Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Minimized | Out-Null
    } else {
        Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    }
}

function Stop-OllamaProcess {
    [CmdletBinding()]
    param()

    Stop-Process -Name ollama -Force -ErrorAction SilentlyContinue
}

function Invoke-OllamaPull {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ModelName)

    & ollama pull $ModelName
}

function Start-OllamaCommandProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory=$true)]
        [string]$StandardOutputPath,
        [Parameter(Mandatory=$true)]
        [string]$StandardErrorPath
    )

    Start-Process -FilePath 'ollama' `
        -ArgumentList $ArgumentList `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $StandardOutputPath `
        -RedirectStandardError $StandardErrorPath
}

function Invoke-OllamaRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ModelName,
        [int]$ContextLength = 0
    )

    if ($ContextLength -gt 0) {
        $env:OLLAMA_CONTEXT_LENGTH = $ContextLength.ToString()
    }
    & ollama run $ModelName
}

function Remove-OllamaModel {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ModelName)

    & ollama rm $ModelName
}

Export-ModuleMember -Function Test-OllamaCommand,
    Start-OllamaServer,
    Stop-OllamaProcess,
    Invoke-OllamaPull,
    Start-OllamaCommandProcess,
    Invoke-OllamaRun,
    Remove-OllamaModel
