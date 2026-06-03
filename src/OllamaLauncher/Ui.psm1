function Limit-Text {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,
        [int]$MaxLength
    )

    if ($null -eq $Text) { $Text = '' }
    if ($MaxLength -le 0) { return '' }
    if ($Text.Length -le $MaxLength) { return $Text }
    if ($MaxLength -le 3) { return $Text.Substring(0, $MaxLength) }
    return ($Text.Substring(0, $MaxLength - 3) + '...')
}

function Write-PaddedLine {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    try { $width = [Console]::BufferWidth - 1 } catch { $width = 79 }
    if ($width -lt 1) { $width = 1 }
    $line = Limit-Text -Text $Text -MaxLength $width
    Write-Host ($line + (' ' * ($width - $line.Length)))
}

Export-ModuleMember -Function Limit-Text, Write-PaddedLine
