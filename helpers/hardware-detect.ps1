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
        # DDR5 note: Win32_PhysicalMemory.Speed reports the module's rated MT/s (e.g., 5600)
        # and ConfiguredClockSpeed reports the actual clock speed in MHz (e.g., 2800 for DDR5-5600).
        # DDR5 is double-data-rate, so ConfiguredClockSpeed = Speed / 2 when XMP is active.
        # Detect DDR type from SMBIOSMemoryType: 34 = DDR5, 26 = DDR4, 24 = DDR3.
        $memType = ($sticks | Select-Object -First 1).SMBIOSMemoryType
        $isDDR5 = ($memType -eq 34)
        # For DDR5: ConfiguredClockSpeed is the actual clock (half of transfer rate).
        # XMP is active if ConfiguredClockSpeed >= 90% of (Speed / 2).
        # For DDR4/DDR3: ConfiguredClockSpeed and Speed are both in MHz, use direct comparison.
        $xmpActive = if ($configMhz -gt 0 -and $speedMhz -gt 0) {
            if ($isDDR5) {
                $configMhz -ge ([math]::Floor($speedMhz / 2) * 0.9)
            } else {
                $configMhz -ge ($speedMhz * 0.9)
            }
        } else { $false }
        return @{
            TotalGB    = $totalGB
            SpeedMhz   = $speedMhz        # Rated module frequency (MT/s for DDR5)
            ActiveMhz  = $configMhz       # Actually active frequency (clock MHz)
            Sticks     = $sticks.Count
            IsDDR5     = $isDDR5
            XmpActive  = $xmpActive
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
        if (-not $gpu -or -not $gpu.DriverVersion) { return $null }
        # DriverVersion "31.0.15.5762" → NVIDIA 557.62
        # Decode: concatenate last two segments, drop leading char, split major/minor
        $parts = $gpu.DriverVersion.Split('.')
        if ($parts.Count -lt 2) {
            Write-Debug "NVIDIA DriverVersion has unexpected format: $($gpu.DriverVersion)"
            return $null
        }
        $combined = "$($parts[-2])$($parts[-1])"
        if ($combined.Length -lt 2) {
            Write-Debug "NVIDIA DriverVersion combined segment too short: $combined"
            return $null
        }
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
        # Read as UTF-8 explicitly — PS 5.1 defaults to ANSI codepage, which
        # mangles Unicode library paths (e.g., non-ASCII usernames or drive labels).
        $content = Get-Content $vdf -Raw -Encoding UTF8
        $paths = [regex]::Matches($content, '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' -replace '/', '\' }
        foreach ($lp in $paths) {
            # SECURITY: VDF is a Valve text file in userspace — a tampered libraryfolders.vdf
            # could contain paths with traversal sequences. Reject paths with .. components.
            # The path is only used in Test-Path and Get-Content on autoexec.cfg / optimization.cfg.
            # Symlink/junction attacks: if CS2 install path is a junction pointing to e.g. C:\Windows,
            # Set-Content would write to that location. The cs2.exe existence check below mitigates
            # this — a junction to C:\Windows would fail the cs2.exe check. Accepted residual risk:
            # if an attacker creates a junction containing a fake cs2.exe, we'd write autoexec there.
            if ($lp -match '\.\.') {
                Write-Debug "VDF path rejected (path traversal): $lp"
                continue
            }
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
    <#  Returns the GUID of the active (Up) wired network adapter for registry writes.
        SECURITY: The GUID is used in registry paths (e.g., Tcpip\Parameters\Interfaces\{GUID}).
        The value comes from Get-NetAdapter (system WMI), not user input. A malicious NIC driver
        could theoretically report a GUID containing path injection characters, but Windows
        enforces GUID format in the network stack. We validate the format as defense-in-depth.  #>
    $nic = Get-ActiveNicAdapter
    if ($nic) {
        $guid = $nic.InterfaceGuid
        # Defense-in-depth: validate GUID format {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
        if ($guid -and $guid -match '^\{[a-fA-F0-9\-]{36}\}$') {
            return $guid
        }
        Write-Warn "NIC GUID failed format validation: $guid"
        return $null
    }
    return $null
}

# ── Intel 12th-gen+ / Core Ultra CPU Detection ──────────────────────────────

function Get-IntelHybridCpuName {
    <#  Returns the CPU name string if this is an Intel 12th-gen-or-newer Core
        (12xxx–19xxx series with suffix) or Intel Core Ultra CPU, or $null
        otherwise. Used to gate Intel 12th-gen+ / Ultra-specific tweaks
        (e.g., PowerThrottlingOff, thread_pool_option). Note: this is a coarse
        heuristic and may include some non-hybrid (no E-core) SKUs.  #>
    try {
        $cpuObj = Get-CimInstance Win32_Processor -Property Name -ErrorAction Stop |
            Select-Object -First 1
        $cpuName = if ($cpuObj) { $cpuObj.Name } else { $null }
        if ($cpuName -and $cpuName -match "Intel" -and (
            $cpuName -match "\b1[2-9]\d{3}[A-Z]" -or  # 12th–19th gen Core-series (suffix required)
            $cpuName -match "\bUltra\b"                 # Core Ultra (Meteor Lake / Arrow Lake)
        )) {
            return $cpuName
        }
        return $null
    } catch {
        Write-Debug "Intel 12th-gen+ CPU detection failed: $_"
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
