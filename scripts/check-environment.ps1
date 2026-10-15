<#
.SYNOPSIS
    TradeLab environment check for Windows. Read-only: it changes nothing on your system.

.DESCRIPTION
    Reports hardware (CPU, RAM, GPU/VRAM, disk), installed developer tooling,
    and the models LM Studio exposes on its local server. Writes the report to
    the console and to tradelab-environment.txt in the current directory.

.USAGE
    powershell -ExecutionPolicy Bypass -File .\scripts\check-environment.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\check-environment.ps1 -LmStudioUrl http://localhost:1234
#>
param(
    [string]$LmStudioUrl = "http://localhost:1234",
    [string]$OutFile = "tradelab-environment.txt"
)

$ErrorActionPreference = "Continue"
$report = New-Object System.Collections.Generic.List[string]
function Add-Line([string]$text = "") { $report.Add($text); Write-Host $text }
function Add-Section([string]$title) { Add-Line ""; Add-Line "=== $title ===" }

Add-Line "TradeLab environment report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"

# --- Operating system -------------------------------------------------------
Add-Section "Operating system"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Add-Line "$($os.Caption) $($os.Version) (build $($os.BuildNumber)), $($os.OSArchitecture)"
} catch { Add-Line "Could not read OS info: $_" }

# --- CPU --------------------------------------------------------------------
Add-Section "CPU"
try {
    Get-CimInstance Win32_Processor | ForEach-Object {
        Add-Line "$($_.Name.Trim()) - $($_.NumberOfCores) cores / $($_.NumberOfLogicalProcessors) threads"
    }
} catch { Add-Line "Could not read CPU info: $_" }

# --- Memory -----------------------------------------------------------------
Add-Section "Memory"
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $totalGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $freeGb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    Add-Line "Total RAM: $totalGb GB (free now: $freeGb GB)"
} catch { Add-Line "Could not read memory info: $_" }

# --- GPU --------------------------------------------------------------------
Add-Section "GPU"
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    # nvidia-smi reports true VRAM; Win32_VideoController caps AdapterRAM at 4 GB.
    $smi = & nvidia-smi --query-gpu=name,memory.total,memory.used,driver_version --format=csv,noheader 2>&1
    $smi | ForEach-Object { Add-Line "NVIDIA: $_" }
} else {
    Add-Line "nvidia-smi not found (no NVIDIA GPU, or driver tools not on PATH)."
}
try {
    Get-CimInstance Win32_VideoController | ForEach-Object {
        $ram = if ($_.AdapterRAM) { "$([math]::Round($_.AdapterRAM / 1GB, 1)) GB (WMI value, capped at 4 GB)" } else { "unknown" }
        Add-Line "Adapter: $($_.Name) - reported VRAM: $ram - driver $($_.DriverVersion)"
    }
} catch { Add-Line "Could not read video controllers: $_" }

# --- Disk -------------------------------------------------------------------
Add-Section "Disk"
try {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        Add-Line "$($_.DeviceID) free $([math]::Round($_.FreeSpace / 1GB, 1)) GB of $([math]::Round($_.Size / 1GB, 1)) GB"
    }
    Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Line "Physical disk: $($_.FriendlyName) - $($_.MediaType) - $([math]::Round($_.Size / 1GB)) GB"
    }
} catch { Add-Line "Could not read disk info: $_" }

# --- Developer tooling ------------------------------------------------------
Add-Section "Developer tooling"
$tools = [ordered]@{
    "python"  = @("--version")
    "py"      = @("--list")
    "uv"      = @("--version")
    "node"    = @("--version")
    "npm"     = @("--version")
    "pnpm"    = @("--version")
    "git"     = @("--version")
    "psql"    = @("--version")
    "docker"  = @("--version")
    "wsl"     = @("--status")
    "code"    = @("--version")
    "lms"     = @("version")
}
foreach ($name in $tools.Keys) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) { Add-Line ("{0,-7} not found" -f $name); continue }
    try {
        $out = & $name @($tools[$name]) 2>&1 | Select-Object -First 3
        $joined = ($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join " | "
        Add-Line ("{0,-7} {1}" -f $name, $joined)
    } catch { Add-Line ("{0,-7} present but failed to run: {1}" -f $name, $_) }
}

# PostgreSQL may be installed as a Windows service without psql on PATH.
$pgServices = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue
if ($pgServices) {
    $pgServices | ForEach-Object { Add-Line "PostgreSQL service: $($_.Name) ($($_.Status))" }
} else {
    Add-Line "No PostgreSQL Windows service found."
}

# --- LM Studio --------------------------------------------------------------
Add-Section "LM Studio ($LmStudioUrl)"
try {
    $models = Invoke-RestMethod -Uri "$LmStudioUrl/v1/models" -TimeoutSec 5
    Add-Line "OpenAI-compatible server reachable. Models exposed via /v1/models:"
    $models.data | ForEach-Object { Add-Line "  - $($_.id)" }
} catch {
    Add-Line "Could not reach $LmStudioUrl/v1/models. Start LM Studio's local server (Developer tab > Start Server)."
    Add-Line "  Error: $($_.Exception.Message)"
}
try {
    # LM Studio's native REST API gives load state, quantisation and max context length.
    $native = Invoke-RestMethod -Uri "$LmStudioUrl/api/v0/models" -TimeoutSec 5
    Add-Line "Details from /api/v0/models:"
    $native.data | ForEach-Object {
        Add-Line ("  - {0} | type={1} | state={2} | quant={3} | max_ctx={4} | arch={5}" -f `
            $_.id, $_.type, $_.state, $_.quantization, $_.max_context_length, $_.arch)
    }
} catch {
    Add-Line "Native /api/v0/models endpoint unavailable (older LM Studio, or server not running)."
}
if (Get-Command lms -ErrorAction SilentlyContinue) {
    Add-Line "Downloaded models (lms ls):"
    & lms ls 2>&1 | ForEach-Object { Add-Line "  $_" }
}

$report | Out-File -FilePath $OutFile -Encoding utf8
Write-Host ""
Write-Host "Report written to $(Resolve-Path $OutFile)"
