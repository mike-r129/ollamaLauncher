function Get-OllamaLauncherHardwareInfo {
    [CmdletBinding()]
    param()

    $vramBytes = 0.0
    try {
        $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        if ($LASTEXITCODE -eq 0 -and $nv) {
            foreach ($line in @($nv)) {
                $val = 0.0
                if ([double]::TryParse(([string]$line).Trim(), [ref]$val)) {
                    $b = $val * 1MB
                    if ($b -gt $vramBytes) { $vramBytes = $b }
                }
            }
        }
    } catch {}
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
        foreach ($g in $gpus) {
            if ($g.AdapterRAM) {
                $b = [double]$g.AdapterRAM
                if ($b -gt $vramBytes) { $vramBytes = $b }
            }
        }
    } catch {}
    try {
        $keys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction Stop
        foreach ($k in $keys) {
            $v = (Get-ItemProperty -Path $k.PSPath -Name 'HardwareInformation.qwMemorySize' -ErrorAction SilentlyContinue).'HardwareInformation.qwMemorySize'
            if ($v) {
                $b = [double]$v
                if ($b -gt $vramBytes) { $vramBytes = $b }
            }
        }
    } catch {}

    $ramGB = 0.0
    try {
        $ramBytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
        $ramGB = [Math]::Round([double]$ramBytes / 1GB, 1)
    } catch {}
    if ($ramGB -le 0) {
        try {
            $ramBytes = (Get-WmiObject Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
            $ramGB = [Math]::Round([double]$ramBytes / 1GB, 1)
        } catch {}
    }

    $ollamaModels = $env:OLLAMA_MODELS
    if (-not $ollamaModels) {
        $profileRoot = $env:USERPROFILE
        if (-not $profileRoot) { $profileRoot = $HOME }
        if (-not $profileRoot) { $profileRoot = [System.IO.Path]::GetTempPath() }
        $ollamaModels = Join-Path $profileRoot '.ollama\models'
    }
    $diskGB = 0.0
    try {
        $qual = Split-Path -Qualifier $ollamaModels
        if ($qual) {
            $letter = $qual.TrimEnd(':')
            $drv = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction Stop
            $diskGB = [Math]::Round([double]$drv.Free / 1GB, 1)
        }
    } catch {}
    if ($diskGB -le 0) {
        try {
            $root = [System.IO.Path]::GetPathRoot($ollamaModels)
            if ($root) {
                $drive = [System.IO.DriveInfo]::new($root)
                if ($drive.IsReady) {
                    $diskGB = [Math]::Round([double]$drive.AvailableFreeSpace / 1GB, 1)
                }
            }
        } catch {}
    }

    [PSCustomObject]@{
        VRAM = [Math]::Round($vramBytes / 1GB, 1)
        RAM  = $ramGB
        Disk = $diskGB
        Path = $ollamaModels
    }
}

function Convert-HardwareInfoToLine {
    param($HardwareInfo)

    return "VRAM=$($HardwareInfo.VRAM)|RAM=$($HardwareInfo.RAM)|DISK=$($HardwareInfo.Disk)|PATH=$($HardwareInfo.Path)"
}

function Get-ModelFitTier {
    param(
        [double]$SizeGb,
        [double]$VramGb,
        [double]$RamGb,
        [double]$DiskGb,
        [int]$ContextLength = 4096
    )

    if ($SizeGb -lt 0) { return 3 }
    $effective = $SizeGb * (1 + ($ContextLength / 50000.0))
    if ($DiskGb -gt 0 -and $effective -gt $DiskGb) { return 2 }
    if ($VramGb -gt 0 -and $effective -le $VramGb) { return 0 }
    if ($effective -le ($VramGb + $RamGb)) { return 1 }
    return 2
}

Export-ModuleMember -Function Get-OllamaLauncherHardwareInfo,
    Convert-HardwareInfoToLine,
    Get-ModelFitTier
