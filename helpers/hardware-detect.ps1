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
            XmpActive  = ($configMhz -ge ($speedMhz * 0.9))  # active if >= 90% of rated
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
        # DriverVersion format "31.0.15.5762" -> last two segments = 576.20
        $parts = $gpu.DriverVersion.Split('.')
        $ver   = "$($parts[-2]).$($parts[-1])"
        $major = [int]$parts[-2]
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

# ── CS2 Install Path ─────────────────────────────────────────────────────────

function Get-CS2InstallPath {
    <#  Finds CS2 install directory via Steam registry + libraryfolders.vdf  #>
    $steamPath = (Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue)?.SteamPath
    if (-not $steamPath) { return $null }

    $defaultCS2 = "$steamPath\steamapps\common\Counter-Strike Global Offensive"
    if (Test-Path "$defaultCS2\game\bin\win64\cs2.exe") { return $defaultCS2 }

    $vdf = "$steamPath\steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $content = Get-Content $vdf -Raw
        $paths = [regex]::Matches($content, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
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
        Centralized NIC selection logic — used by NIC tweaks, RSS config, etc.  #>
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

# ── Chipset Vendor ───────────────────────────────────────────────────────────

function Get-ChipsetVendor {
    <#  Returns "AMD" or "Intel" based on CPU manufacturer  #>
    try {
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer
        if ($cpu -match "AMD")   { return "AMD" }
        if ($cpu -match "Intel") { return "Intel" }
    } catch {}
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
