# ==============================================================================
#  helpers/hardware-detect.ps1  —  RAM, GPU, NIC, Chipset Detection
# ==============================================================================

# ── XMP / RAM ────────────────────────────────────────────────────────────────

function Get-RamInfo {
    <#  Returns actual RAM speed and capacity.  #>
    try {
        $sticks = Get-CimInstance Win32_PhysicalMemory
        $totalGB = [math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB, 0)
        $speedMhz = ($sticks | Select-Object -First 1).Speed
        $configMhz = ($sticks | Select-Object -First 1).ConfiguredClockSpeed
        return @{
            TotalGB    = $totalGB
            SpeedMhz   = $speedMhz        # Rated module frequency
            ActiveMhz  = $configMhz       # Actually active frequency
            Sticks     = $sticks.Count
            XmpActive  = ($configMhz -gt 0 -and $speedMhz -gt 0 -and $configMhz -ge ($speedMhz * 0.9))  # active if >= 90% of rated; may false-positive on DDR5 JEDEC sticks
        }
    } catch {
        Write-Debug "RAM info error: $_"
        return $null
    }
}

function Test-XmpActive {
    $ram = Get-RamInfo
    if (-not $ram) { return $null }
    return $ram.XmpActive
}

# ── NVIDIA Driver ────────────────────────────────────────────────────────────

function Get-NvidiaDriverVersion {
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
        if (-not $gpu) { return $null }
        # DriverVersion "31.0.15.5762" → NVIDIA 557.62
        # Decode: concatenate last two segments, drop leading char, split major/minor
        $parts = $gpu.DriverVersion.Split('.')
        $combined = "$($parts[-2])$($parts[-1])"
        $nvStr = $combined.Substring(1)  # Remove Windows prefix digit
        if ($nvStr.Length -ge 3) {
            $major = [int]$nvStr.Substring(0, $nvStr.Length - 2)
            $minor = [int]$nvStr.Substring($nvStr.Length - 2)
            $ver = "$major.$minor"
        } else {
            $major = [int]$nvStr
            $ver = "$major"
        }
        return @{ Version = $ver; Major = $major; Name = $gpu.Name }
    } catch { return $null }
}

# Known problematic driver ranges (as of 2025/2026)
# R570+ (576.x and above) causes stutter on some CS2 systems
$NVIDIA_PROBLEMATIC_MAJOR = 576
$NVIDIA_STABLE_VERSION    = "566.36"

# ── Benchmark Parser ─────────────────────────────────────────────────────────

function Parse-BenchmarkOutput($text) {
    $pattern = '\[VProf\]\s*FPS:\s*Avg\s*=\s*([\d.]+)\s*,\s*P1\s*=\s*([\d.]+)'
    $m = [regex]::Matches($text, $pattern)
    if ($m.Count -eq 0) { return $null }
    $avgs = @($m | ForEach-Object { [float]$_.Groups[1].Value })
    $p1s  = @($m | ForEach-Object { [float]$_.Groups[2].Value })
    return @{
        Avg    = [math]::Round(($avgs | Measure-Object -Average).Average, 1)
        P1     = [math]::Round(($p1s  | Measure-Object -Average).Average, 1)
        Runs   = $m.Count
        RawAvg = $avgs; RawP1 = $p1s
    }
}

function Calculate-FpsCap($avgFps) {
    return [math]::Max($CFG_FpsCap_Min, [int]($avgFps - [math]::Round($avgFps * $CFG_FpsCap_Percent)))
}

# ── Steam + CS2 Install Path ─────────────────────────────────────────────────

function Get-SteamPath {
    <#  Returns the Steam installation root directory from the registry, or $null.
        Single source of truth for all callers that need the Steam base path.  #>
    $reg = Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
    if ($reg) { return $reg.SteamPath }
    return $null
}

function Get-CS2InstallPath {
    <#  Finds CS2 install directory via Steam registry + libraryfolders.vdf  #>
    $steamPath = Get-SteamPath
    if (-not $steamPath) { return $null }

    $defaultCS2 = "$steamPath\steamapps\common\Counter-Strike Global Offensive"
    if (Test-Path "$defaultCS2\game\bin\win64\cs2.exe") { return $defaultCS2 }

    $vdf = "$steamPath\steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $content = Get-Content $vdf -Raw
        $paths = [regex]::Matches($content, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '/', '\' }
        foreach ($lp in $paths) {
            $cs2Path = "$lp\steamapps\common\Counter-Strike Global Offensive"
            if (Test-Path "$cs2Path\game\bin\win64\cs2.exe") { return $cs2Path }
        }
    }

    foreach ($d in @("C","D","E","F")) {
        foreach ($base in @("$($d):\Steam","$($d):\Program Files (x86)\Steam","$($d):\Program Files\Steam","$($d):\SteamLibrary")) {
            $cs2Path = "$base\steamapps\common\Counter-Strike Global Offensive"
            if (Test-Path "$cs2Path\game\bin\win64\cs2.exe") { return $cs2Path }
        }
    }
    return $null
}

# ── Active NIC Adapter ───────────────────────────────────────────────────────

function Get-ActiveNicAdapter {
    <#  Returns the active (Up) wired network adapter object, or $null.
        Centralized NIC selection logic — used by NIC tweaks, RSS config, etc.
        Best-effort heuristic: may exclude USB Ethernet or include unintended adapters.  #>
    try {
        return Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Status -eq "Up" -and
            $_.InterfaceDescription -notmatch "Loopback|Virtual|Hyper-V|Bluetooth|Wi-Fi|Wireless"
        } | Sort-Object LinkSpeed -Descending | Select-Object -First 1
    } catch {
        Write-Debug "Get-ActiveNicAdapter error: $_"
        return $null
    }
}

function Get-ActiveNicGuid {
    <#  Returns the GUID of the active (Up) wired network adapter for registry writes  #>
    $nic = Get-ActiveNicAdapter
    if ($nic) { return $nic.InterfaceGuid }
    return $null
}

# ── Intel Hybrid CPU Detection ───────────────────────────────────────────────

function Get-IntelHybridCpuName {
    <#  Returns the CPU name string if this is an Intel hybrid CPU (12th gen+
        or Core Ultra), or $null otherwise. Used to gate Intel-specific tweaks
        (PowerThrottlingOff, thread_pool_option) that only apply to P/E-core CPUs.  #>
    try {
        $cpuObj = Get-CimInstance Win32_Processor -Property Name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $cpuName = if ($cpuObj) { $cpuObj.Name } else { $null }
        if ($cpuName -and $cpuName -match "Intel" -and (
            $cpuName -match "\b1[2-9]\d{3}[A-Z]" -or  # 12xxx-19xxx series
            $cpuName -match "\bUltra\b"                 # Core Ultra (Meteor Lake / Arrow Lake)
        )) {
            return $cpuName
        }
        return $null
    } catch {
        Write-Debug "Intel hybrid CPU detection failed: $_"
        return $null
    }
}

# ── Chipset Vendor ───────────────────────────────────────────────────────────

function Get-ChipsetVendor {
    <#  Returns "AMD" or "Intel" based on CPU manufacturer  #>
    try {
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer
        if ($cpu -match "AMD")   { return "AMD" }
        if ($cpu -match "Intel") { return "Intel" }
    } catch { Write-Debug "CPU vendor detection failed: $($_.Exception.Message)" }
    return "Unknown"
}

# ── Dual-Channel RAM ────────────────────────────────────────────────────────

function Test-DualChannel {
    <#  Checks if RAM is likely running in dual-channel (2+ sticks in different banks)  #>
    try {
        $sticks = @(Get-CimInstance Win32_PhysicalMemory)
        if ($sticks.Count -lt 2) {
            return @{ DualChannel = $false; Sticks = $sticks.Count; Reason = "Only $($sticks.Count) RAM stick detected — single-channel." }
        }
        $banks = $sticks | ForEach-Object { $_.BankLabel } | Select-Object -Unique
        if ($banks.Count -ge 2) {
            return @{ DualChannel = $true;  Sticks = $sticks.Count; Reason = "$($sticks.Count) sticks in $($banks.Count) banks — dual-channel likely." }
        }
        return @{ DualChannel = $false; Sticks = $sticks.Count; Reason = "$($sticks.Count) sticks but same bank — possibly wrong slots." }
    } catch {
        return @{ DualChannel = $null; Sticks = 0; Reason = "Could not read RAM info." }
    }
}
