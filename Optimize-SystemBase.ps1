# ==============================================================================
#  Optimize-SystemBase.ps1  —  Steps 2-9: XMP, Shader, FSO, NVIDIA, Power,
#                               HAGS, Pagefile, ReBAR
# ==============================================================================

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — XMP/EXPO CHECK  [T1 — Check; T2 — CS2 effect unclear]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 2) {
    Write-Section "Step 2 — XMP/EXPO Check"
    Write-Blank
    Write-Host "  HONEST ASSESSMENT OF XMP/EXPO IN CS2:" -ForegroundColor DarkYellow
    Write-Host @"
  Hardware logic:  RAM speed -> L3/memory latency -> CPU delivers frames.
                   Makes sense, no downside.
  CS2-specific:    No isolated CS2 benchmark clearly proves the
                   effect on 1% lows.
                   One documented case (7800X3D, Blur Busters):
                   identical lows with and without EXPO.
  Conclusion:      Activate anyway — general system stability,
                   no downside, and RAM runs as purchased.
"@ -ForegroundColor DarkGray
    Write-Blank
    Invoke-TieredStep -Tier 1 -Title "Check XMP/EXPO status + warn if inactive" `
        -Why "RAM at JEDEC default = slower than rated. Generally recommended, CS2 effect not isolated." `
        -Evidence "Hardware logic: plausible. CS2 benchmark: no clear proof. No downside to activation." `
        -Risk "SAFE" -Depth "CHECK" `
        -Improvement "Ensures RAM runs at purchased speed — general system benefit" `
        -SideEffects "None — read-only check with BIOS instructions" `
        -Undo "N/A (check only)" `
        -Action {
            $ram = Get-RamInfo
            if (-not $ram) {
                Write-Warn "Could not read RAM info. Check manually:"
                Write-Info "Task Manager -> Performance -> Memory -> Speed"
            } else {
                Write-Info "RAM:           $($ram.TotalGB) GB | $($ram.Sticks) stick(s)"
                Write-Info "Rated speed:   $($ram.SpeedMhz) MHz  (per SPD)"
                Write-Info "Active:        $($ram.ActiveMhz) MHz  (actual)"

                if ($ram.XmpActive) {
                    Write-OK "XMP/EXPO is active — RAM running at rated speed."
                    Write-Info "If 1% lows still bad: check RAM sub-timings (Phase 3 summary)."
                } else {
                    Write-Err "XMP/EXPO is NOT active!"
                    Write-Blank
                    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
                    Write-Host "  │  RAM running at $($ram.ActiveMhz) MHz instead of $($ram.SpeedMhz) MHz$((' ' * [math]::Max(0, 34 - "$($ram.ActiveMhz) $($ram.SpeedMhz)".Length)))│" -ForegroundColor Yellow
                    Write-Host "  │                                                              │" -ForegroundColor Yellow
                    Write-Host "  │  Note: CS2-specific 1%-low effect is not proven by           │" -ForegroundColor DarkGray
                    Write-Host "  │  isolated benchmarks. Generally recommended though —         │" -ForegroundColor DarkGray
                    Write-Host "  │  RAM should run at rated speed.                              │" -ForegroundColor DarkGray
                    Write-Host "  │                                                              │" -ForegroundColor Yellow
                    Write-Host "  │  BIOS GUIDE:                                                │" -ForegroundColor White
                    Write-Host "  │  1.  Restart PC -> BIOS (DEL / F2 / F12)                   │" -ForegroundColor White
                    Write-Host "  │  2.  Look for: XMP / EXPO / DOCP / Memory Profile          │" -ForegroundColor White
                    Write-Host "  │  3.  Enable Profile 1                                      │" -ForegroundColor White
                    Write-Host "  │  4.  Save + restart                                        │" -ForegroundColor White
                    Write-Host "  │  5.  Verify: Task Manager -> Performance -> Memory          │" -ForegroundColor White
                    Write-Host "  │      -> Should show '$($ram.SpeedMhz) MHz'$((' ' * [math]::Max(0, 34 - "$($ram.SpeedMhz) MHz".Length)))│" -ForegroundColor White
                    Write-Host "  │                                                              │" -ForegroundColor Yellow
                    Write-Host "  │  AFTERWARDS: RAM stability test recommended                 │" -ForegroundColor DarkGray
                    Write-Host "  │  TM5 / HCI MemTest  (github.com/integrityhf/TM5)           │" -ForegroundColor DarkGray
                    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
                    Write-Blank
                    Read-Host "  [Enter] to continue (activate XMP in BIOS afterwards)"
                }
            }

            # ── BIOS Optimization Checklist ──────────────────────────────
            Write-Blank
            Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
            Write-Host "  │  BIOS OPTIMIZATION CHECKLIST (cannot be automated)          │" -ForegroundColor DarkGray
            Write-Host "  │                                                              │" -ForegroundColor DarkGray
            Write-Host "  │  While in BIOS, check these settings:                       │" -ForegroundColor White
            Write-Host "  │                                                              │" -ForegroundColor DarkGray
            Write-Host "  │  ✓  XMP / EXPO / DOCP  -> Profile 1 (RAM rated speed)      │" -ForegroundColor White
            Write-Host "  │  ✓  Above 4G Decoding  -> ENABLED  (required for ReBAR)    │" -ForegroundColor White
            Write-Host "  │  ✓  Re-Size BAR        -> ENABLED or Auto                  │" -ForegroundColor White
            Write-Host "  │  ✓  Fast Boot          -> DISABLED (proper HW init)        │" -ForegroundColor White
            Write-Host "  │  ✓  Legacy USB         -> DISABLED (if no USB keyboard/    │" -ForegroundColor White
            Write-Host "  │                          mouse needed in BIOS)              │" -ForegroundColor DarkGray
            Write-Host "  │  ✓  PCIe ASPM          -> DISABLED or L0s (reduces PCIe   │" -ForegroundColor White
            Write-Host "  │                          latency spikes)                    │" -ForegroundColor DarkGray
            Write-Host "  │  ✓  Spread Spectrum    -> DISABLED (reduces clock jitter)  │" -ForegroundColor White
            Write-Host "  │  ?  C-States           -> C1 only or all disabled          │" -ForegroundColor DarkGray
            Write-Host "  │                          (reduces latency, increases temp)  │" -ForegroundColor DarkGray
            Write-Host "  │  ?  Virtualization     -> Off if no VMs/WSL/Docker used    │" -ForegroundColor DarkGray
            Write-Host "  │                          (also disables VBS/HVCI overhead) │" -ForegroundColor DarkGray
            Write-Host "  │  ✓  Secure Boot        -> ENABLED (Win11 requires for HAGS)│" -ForegroundColor White
            Write-Host "  │  ✓  TPM (Ryzen only)   -> Discrete TPM, not AMD fTPM       │" -ForegroundColor White
            Write-Host "  │                          AMD fTPM causes random 1-2s freeze │" -ForegroundColor DarkGray
            Write-Host "  │                          BIOS -> Security -> AMD fTPM ->    │" -ForegroundColor DarkGray
            Write-Host "  │                          Discrete TPM (keep Win11 TPM req) │" -ForegroundColor DarkGray
            Write-Host "  │  ✓  CSM / Legacy       -> DISABLED (full UEFI-only mode)   │" -ForegroundColor White
            Write-Host "  │                                                              │" -ForegroundColor DarkGray
            Write-Host "  │  NOTE: C-States disable raises idle CPU temperature         │" -ForegroundColor Yellow
            Write-Host "  │  significantly. Only disable on well-cooled systems.        │" -ForegroundColor Yellow
            Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray

            Complete-Step $PHASE 2 "XMP-Check"
        } `
        -SkipAction { Skip-Step $PHASE 2 "XMP-Check" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — SHADER CACHE CLEAR  [T1]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 3) {
    Write-Section "Step 3 — Clear CS2 + GPU Shader Cache"
    Invoke-TieredStep -Tier 1 -Title "Clear Shader Cache" `
        -Why "Stale shaders after Windows/driver updates -> stutter on first frame. Clean cache = no mid-match compile." `
        -Evidence "T1: Directly measurable after driver change. Known cause (incremental cache becomes inconsistent)." `
        -Risk "SAFE" -Depth "FILESYSTEM" -EstimateKey "Clear Shader Cache" `
        -Improvement "Eliminates stutter from stale/corrupt shaders after driver or Windows update" `
        -SideEffects "First CS2 launch takes 30-60s longer (shader recompile)" `
        -Undo "Shaders rebuild automatically on next launch" `
        -Action {
            # Warn if Steam or CS2 is running — locked files will silently fail to delete
            $steamRunning = Get-Process -Name "steam","cs2" -ErrorAction SilentlyContinue
            if ($steamRunning) {
                $procs = ($steamRunning | Select-Object -ExpandProperty Name -Unique) -join ", "
                Write-Warn "Running processes detected: $procs — some shader cache files may be locked."
                Write-Info "For a complete cache clear, close Steam and CS2 first."
            }
            $steamBase = Get-SteamPath
            $paths = [System.Collections.Generic.List[string]]$CFG_ShaderCache_Paths
            if ($steamBase) { $paths.Add("$steamBase\steamapps\shadercache\730") }
            $found = $false
            foreach ($p in ($paths | Select-Object -Unique)) {
                if (Test-Path $p) {
                    $n = (Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue).Count
                    Write-Step "CS2 Cache: $p  ($n files)"
                    if (-not $SCRIPT:DryRun) {
                        Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        $remaining = (Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue).Count
                        if ($remaining -gt 0) {
                            Write-Warn "Partially cleared: $p ($remaining files locked — close Steam/CS2 to clear fully)"
                        } else {
                            Write-OK "Cleared: $p"
                        }
                    } else {
                        Write-Host "  [DRY-RUN] Would clear: $p ($n files)" -ForegroundColor Magenta
                    }
                    $found = $true
                }
            }
            foreach ($c in @($CFG_NV_ShaderCache, $CFG_NV_GLCache, $CFG_DX_ShaderCache)) {
                if (Test-Path $c) {
                    $n = (Get-ChildItem $c -Recurse -ErrorAction SilentlyContinue).Count
                    Write-Step "GPU Cache: $c  ($n files)"
                    if (-not $SCRIPT:DryRun) {
                        Get-ChildItem $c -Recurse -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        $remaining = (Get-ChildItem $c -Recurse -ErrorAction SilentlyContinue).Count
                        if ($remaining -gt 0) {
                            Write-Warn "Partially cleared: $c ($remaining files locked)"
                        } else {
                            Write-OK "Cleared: $c"
                        }
                    } else {
                        Write-Host "  [DRY-RUN] Would clear: $c ($n files)" -ForegroundColor Magenta
                    }
                    $found = $true
                }
            }
            if (-not $found) {
                Write-Warn "Shader cache not found. Manual: [Steam]\steamapps\shadercache\730"
            }
            Write-Info "Restart CS2 -> 'Compiling Shaders' appears briefly -> normal."
            Complete-Step $PHASE 3 "ShaderCache"
        } `
        -SkipAction { Skip-Step $PHASE 3 "ShaderCache" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — FULLSCREEN OPTIMIZATIONS DISABLE  [T1]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 4) {
    Write-Section "Step 4 — Disable Fullscreen Optimizations (cs2.exe)"
    Invoke-TieredStep -Tier 1 -Title "Disable Fullscreen Optimizations for cs2.exe" `
        -Why "Windows DWM compositing layer in 'Fullscreen' creates variable frame pacing -> worse 1% lows." `
        -Evidence "T1: Demonstrated live by G2 pro m0NESY. Confirmed multiple times in community. Zero downside." `
        -Risk "SAFE" -Depth "REGISTRY" -EstimateKey "Fullscreen Optimizations" `
        -Improvement "More consistent frametimes in fullscreen — directly measurable" `
        -SideEffects "None — only affects cs2.exe rendering mode" `
        -Undo "Delete AppCompatFlags\Layers entry for cs2.exe" `
        -Action {
            # Use Get-CS2InstallPath which parses libraryfolders.vdf for custom library locations
            $cs2Install = Get-CS2InstallPath
            $cs2Exe = if ($cs2Install) { "$cs2Install\game\bin\win64\cs2.exe" } else { $null }
            # Verify the exe actually exists at the detected path
            if ($cs2Exe -and -not (Test-Path $cs2Exe)) { $cs2Exe = $null }

            if ($cs2Exe) {
                Write-Debug "cs2.exe: $cs2Exe"
                $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
                Set-RegistryValue $regPath $cs2Exe "~ DISABLEDXMAXIMIZEDWINDOWEDMODE" "String" "Disable fullscreen optimizations for cs2.exe"
                Write-ActionOK "Fullscreen Optimizations disabled: $cs2Exe"
                Write-Debug "AppCompatFlags set: $cs2Exe"
            } else {
                Write-Warn "cs2.exe not found — manual:"
                Write-Info "cs2.exe -> Right-click -> Properties -> Compatibility"
                Write-Info "-> Check 'Disable fullscreen optimizations'"
                Write-Info "Typical path: Steam\steamapps\common\Counter-Strike Global Offensive\game\bin\win64\"
            }
            Complete-Step $PHASE 4 "FSO"
        } `
        -SkipAction { Skip-Step $PHASE 4 "FSO" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — NVIDIA DRIVER VERSION CHECK  [T2]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 5 -and $gpuInput -in @("1","2")) {
    Write-Section "Step 5 — NVIDIA Driver Version Check"
    $nvDrv = Get-NvidiaDriverVersion
    if ($nvDrv) {
        Write-Info "Installed driver: $($nvDrv.Version)  ($($nvDrv.Name))"
        if ($nvDrv.Major -ge $NVIDIA_PROBLEMATIC_MAJOR) {
            Invoke-TieredStep -Tier 2 -Title "NVIDIA driver rollback to $NVIDIA_STABLE_VERSION" `
                -Why "Driver R570+ ($($nvDrv.Version)) causes severe stutter and worse 1% lows on some CS2 systems." `
                -Evidence "Blur Busters Forum 2025: Pre-R570 (566.36) recommended. Windows 11 23H2 + 566.36 = most stable combo." `
                -Caveat "Not every system is affected. Only do this if you currently experience stutter." `
                -Risk "AGGRESSIVE" -Depth "DRIVER" `
                -Improvement "May fix severe stutter on affected R570+ systems — up to +20% 1% lows" `
                -SideEffects "Older driver may lack new features/game optimizations" `
                -Undo "Install latest NVIDIA driver from nvidia.com/drivers" `
                -Action {
                    Write-Info "GPU driver will be cleanly removed in Phase 2 (Safe Mode)."
                    Write-Info "In Phase 3: clean driver $NVIDIA_STABLE_VERSION will be installed."
                    Write-Info "Download: https://www.nvidia.com/en-us/drivers/"
                    Write-Info "Search for: $NVIDIA_STABLE_VERSION"
                    "https://www.nvidia.com/en-us/drivers/" | Set-Clipboard
                    Write-OK "NVIDIA download page copied to clipboard."
                    try {
                        $st = Get-Content $CFG_StateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                        $st | Add-Member -NotePropertyName "rollbackDriver" -NotePropertyValue $NVIDIA_STABLE_VERSION -Force
                        Save-JsonAtomic -Data $st -Path $CFG_StateFile
                    } catch { Write-Warn "Could not persist rollback flag: $_" }
                    Complete-Step $PHASE 5 "NVDriverCheck"
                } `
                -SkipAction {
                    Write-Info "Keeping current driver. Phase 3 will do a clean reinstall."
                    Skip-Step $PHASE 5 "NVDriverCheck"
                }
        } else {
            Write-OK "Driver $($nvDrv.Version) — no known issues."
            Write-Info "Driver is in a stable version range (pre-R570)."
            Complete-Step $PHASE 5 "NVDriverCheck"
        }
    } else {
        Write-Info "No NVIDIA driver installed (already cleaned, or AMD/Intel)."
        Skip-Step $PHASE 5 "NVDriverCheck"
    }
} elseif ($startStep -le 5) {
    Skip-Step $PHASE 5 "NVDriverCheck (no NVIDIA)"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — CS2 OPTIMIZED POWER PLAN  [T1]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 6) {
    Write-Section "Step 6 — CS2 Optimized Power Plan"
    Invoke-TieredStep -Tier 1 -Title "Create CS2 Optimized Power Plan (native, tiered)" `
        -Why "Eliminates CPU core parking, disables USB/disk power saving, vendor-aware CPU freq tuning. No binary import — pure PowerShell." `
        -Evidence "T1: CPU parking measurably harmful in CPU-bound games. T2: EPP=0 + boost policy unlock CPPC2/PB2 on modern CPUs. T3: C-state exit adds >100µs latency — measurable in DPC tools." `
        -Risk "MODERATE" -Depth "REGISTRY" -EstimateKey "CS2 Optimized Power Plan" `
        -Improvement "Tiered low-latency plan — T1: parking+USB+sleep, T2: CPU freq+NVMe, T3: C-states off" `
        -SideEffects "Higher idle power (~5-15W on T1/T2). T3 adds +5-15°C CPU idle temp. DC/battery settings untouched." `
        -Undo "powercfg /setactive <original GUID> (auto-backed up) or START.bat [7] Restore/Rollback" `
        -Action {
            Backup-PowerPlan -StepTitle "CS2 Optimized Power Plan"
            try {
                $guid   = New-CS2PowerPlan
                Apply-PowerPlan -PlanGuid $guid

                if (-not $SCRIPT:DryRun) {
                    powercfg /setactive $guid 2>&1 | Out-Null
                } else {
                    Write-Host "  [DRY-RUN] Would activate: CS2 Optimized (FPSHeaven 2026)" -ForegroundColor Magenta
                }

                $isAMD   = (Get-ChipsetVendor) -eq "AMD"
                $vTag    = if ($isAMD) { "AMD" } else { "Intel" }
                $applyT2 = $SCRIPT:Profile -in @("RECOMMENDED", "COMPETITIVE", "CUSTOM")
                $applyT3 = $SCRIPT:Profile -in @("COMPETITIVE", "CUSTOM")

                Write-Blank
                Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Green
                Write-Host "  │  CS2 Optimized (FPSHeaven 2026)  •  CPU vendor: $vTag$((' ' * (14 - $vTag.Length)))│" -ForegroundColor Green
                Write-Host "  ├──────────────────────────────────────────────────────────────┤" -ForegroundColor Green
                Write-Host "  │  [T1] CPU max=100%, no parking, USB suspend off,             │" -ForegroundColor Green
                Write-Host "  │       disk idle off, sleep/hibernate off, active cooling      │" -ForegroundColor Green
                if ($applyT2) {
                    Write-Host "  │  [T2] EPP=0, boost 254/255, max idle C1, NVMe/USB-C off      │" -ForegroundColor Yellow
                    if ($isAMD) {
                        Write-Host "  │       CPU min=0% (AMD — PB2 compatible)                      │" -ForegroundColor Yellow
                    } else {
                        Write-Host "  │       CPU min=100% + ring cores (Intel)                      │" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "  │  [T2] skipped — upgrade to RECOMMENDED for CPU/NVMe tweaks  │" -ForegroundColor DarkGray
                }
                if ($applyT3) {
                    Write-Host "  │  [T3] C-states off, duty cycling off, fast ramp   (+temp)   │" -ForegroundColor DarkYellow
                } else {
                    Write-Host "  │  [T3] skipped — COMPETITIVE profile for C-states off         │" -ForegroundColor DarkGray
                }
                Write-Host "  ├──────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
                Write-Host "  │  4 FPSHeaven bugs fixed: cooling=active, STANDBYIDLE=never,  │" -ForegroundColor DarkGray
                Write-Host "  │  PERFAUTONOMOUS=default (PB2 safe), duty cycling=off         │" -ForegroundColor DarkGray
                Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Green
                Write-Blank
                Write-Info "Undo: Control Panel -> Power Options -> select original plan"
                Write-Info "      or START.bat [7] Restore/Rollback -> Power Plan"
            } catch {
                Write-Warn "Power plan creation failed: $_"
                Write-Info "Fallback: activating Windows High Performance..."
                if (-not $SCRIPT:DryRun) {
                    powercfg /setactive SCHEME_MIN 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warn "High Performance not available — falling back to Balanced."
                        powercfg /setactive SCHEME_BALANCED 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Warn "Balanced plan also unavailable. Current power plan unchanged."
                            Write-Info "Manually set power plan: Control Panel -> Power Options"
                        } else {
                            Write-OK "Balanced power plan active (fallback)."
                        }
                    } else {
                        Write-OK "Windows High Performance active (fallback)."
                    }
                } else {
                    Write-Host "  [DRY-RUN] Would fallback to High Performance plan" -ForegroundColor Magenta
                }
            }
            Complete-Step $PHASE 6 "PowerPlan"
        } `
        -SkipAction { Skip-Step $PHASE 6 "PowerPlan" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 7 — HAGS  [T2]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 7) {
    Write-Section "Step 7 — Hardware-accelerated GPU Scheduling (HAGS)"
    if ($gpuInput -in @("3","4")) {
        Write-Info "AMD/Intel: Configure HAGS via system settings or driver software."
        Skip-Step $PHASE 7 "HAGS"
    } else {
        $hagsState = if ($gpuInput -eq "2") { "OFF (RTX 4000 and older can hurt)" } else { "ON (recommended for RTX 5000)" }
        $hagsVal   = if ($gpuInput -eq "2") { 0 } else { 2 }
        Invoke-TieredStep -Tier 2 -Title "HAGS $hagsState" `
            -Why "HAGS lets the GPU manage its own render queue -> less CPU overhead." `
            -Evidence "Measurable effect on RTX 3000+ / RDNA2+. RTX 2000 and older: can worsen 1% lows." `
            -Caveat "Setup-dependent. Always benchmark (CapFrameX) before and after." `
            -Risk "MODERATE" -Depth "REGISTRY" -EstimateKey "HAGS Toggle" `
            -Improvement "Less CPU overhead for GPU scheduling — +2-5% on RTX 3000+" `
            -SideEffects "RTX 2000 and older: may worsen 1% lows. Benchmark to verify." `
            -Undo "Set HwSchMode = 1 (or toggle in Windows Settings -> Display -> Graphics)" `
            -Action {
                # ── Secure Boot check (Win11 HAGS requirement) ──────────────────────
                try {
                    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
                    if ($sb -eq $true) {
                        Write-OK "Secure Boot: ENABLED (compatible with HAGS on Windows 11)"
                    } elseif ($sb -eq $false) {
                        Write-Warn "Secure Boot: DISABLED — HAGS may not activate on Windows 11."
                        Write-Info "Enable Secure Boot in BIOS to ensure HAGS functions correctly."
                    }
                } catch { Write-Sub "Secure Boot status: not readable (non-UEFI or restricted access)" }

                # ── VBS/HVCI detection ────────────────────────────────────────────────
                # Virtualization-Based Security runs a Type-1 hypervisor below the kernel
                # to protect credential storage (LSASS). On many OEM Win11 systems it is
                # enabled by default, adding 5-15% CPU scheduling overhead in games.
                # Source: Microsoft VBS documentation; Phoronix/community game benchmarks.
                try {
                    $dg = Get-CimInstance -ClassName Win32_DeviceGuard `
                        -Namespace root/Microsoft/Windows/DeviceGuard -ErrorAction SilentlyContinue
                    if ($dg) {
                        # VirtualizationBasedSecurityStatus: 0=off, 1=enabled-not-running, 2=running
                        $vbsStatus = $dg.VirtualizationBasedSecurityStatus
                        if ($vbsStatus -ge 2) {
                            Write-Blank
                            Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
                            Write-Host "  │  ⚠  VBS/HVCI ACTIVE — hypervisor overhead detected          │" -ForegroundColor Yellow
                            Write-Host "  │                                                              │" -ForegroundColor Yellow
                            Write-Host "  │  Virtualization-Based Security is running on this system.   │" -ForegroundColor White
                            Write-Host "  │  Known cost: 5-15% CPU overhead in games (OEM Win11).       │" -ForegroundColor White
                            Write-Host "  │                                                              │" -ForegroundColor Yellow
                            Write-Host "  │  TO DISABLE (security trade-off — dedicated gaming PCs):   │" -ForegroundColor White
                            Write-Host "  │  1. Windows Security -> Device Security -> Core Isolation   │" -ForegroundColor DarkGray
                            Write-Host "  │     -> Memory Integrity: OFF  (reboot required)             │" -ForegroundColor DarkGray
                            Write-Host "  │  2. If still active: BIOS -> Virtualization (VT-d/AMD-Vi)  │" -ForegroundColor DarkGray
                            Write-Host "  │     -> OFF  (also disables WSL2, VMs, Docker)              │" -ForegroundColor DarkGray
                            Write-Host "  │  3. Verify: msinfo32 -> Virtualization-based security      │" -ForegroundColor DarkGray
                            Write-Host "  │     -> should read 'Not Enabled'                           │" -ForegroundColor DarkGray
                            Write-Host "  │                                                              │" -ForegroundColor Red
                            Write-Host "  │  WARNING: Reduces LSASS credential theft protection.       │" -ForegroundColor Red
                            Write-Host "  │  Only disable on dedicated gaming PCs, not work machines.  │" -ForegroundColor Red
                            Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
                            Write-Blank
                        } elseif ($vbsStatus -eq 1) {
                            Write-Info "VBS: configured but not running — no active performance impact."
                        } else {
                            Write-OK "VBS/HVCI: not active — no hypervisor overhead."
                        }
                    }
                } catch { Write-Debug "VBS detection failed: $_" }

                try {
                    Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" $hagsVal "DWord" "HAGS toggle"
                } catch { Write-Warn "Manual: Windows Settings -> System -> Display -> Graphics" }
                Complete-Step $PHASE 7 "HAGS"
            } `
            -SkipAction { Skip-Step $PHASE 7 "HAGS" }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 8 — PAGEFILE  [T2]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 8) {
    Write-Section "Step 8 — Configure Pagefile"
    $ram = Get-RamInfo
    $ramGB = if ($ram) { $ram.TotalGB } else { 0 }

    if ($ramGB -eq 0) {
        Write-Warn "Could not detect RAM — skipping pagefile configuration."
        Skip-Step $PHASE 8 "Pagefile (no RAM info)"
    } elseif ($ramGB -ge 32) {
        Write-Info "RAM: ${ramGB} GB — pagefile fix has little effect on CS2 with >= 32 GB RAM."
        Write-Info "CS2 fits entirely in RAM. Pagefile only used on RAM overflow."
        Skip-Step $PHASE 8 "Pagefile (sufficient RAM)"
    } else {
        $pfMB = if ($ramGB -gt 0) { $ramGB * 1024 * 2 } else { 16384 }
        Invoke-TieredStep -Tier 2 -Title "Fix pagefile at ${pfMB} MB (2x RAM: ${ramGB} GB)" `
            -Why "Dynamic pagefile grows under load -> disk IO mid-match -> frametime spike." `
            -Evidence "Relevant when RAM usage > 80%. At ${ramGB} GB RAM realistic with CS2 + Discord/browser." `
            -Caveat "No effect if RAM usage stays low. Task Manager -> Performance -> RAM to check." `
            -Risk "MODERATE" -Depth "REGISTRY" `
            -Improvement "Prevents disk IO spikes under RAM pressure — stabilizes frametimes" `
            -SideEffects "Uses ${pfMB} MB fixed disk space for pagefile" `
            -Undo "Set AutomaticManagedPagefile = true in System Properties -> Advanced" `
            -Action {
                Write-Info "Pagefile size: ${pfMB} MB (you can adjust)"
                $pfIn = Read-Host "  Accept MB value? [Enter] or type new number"
                if ($pfIn.Trim() -ne "") {
                    $pfV = 0
                    if ([int]::TryParse($pfIn,[ref]$pfV) -and $pfV -gt 0) { $pfMB = $pfV }
                }
                if (-not $SCRIPT:DryRun) {
                    try {
                        # NOTE: Uses Get-WmiObject (not CIM) because .Put() method is WMI-specific.
                        # Get-WmiObject is removed in PowerShell 7+. The tool targets PS 5.1
                        # (shipped with Windows 10/11). If running under PS 7, install the
                        # Microsoft.PowerShell.Management compatibility module or use PS 5.1.
                        $cs = Get-WmiObject Win32_ComputerSystem
                        $cs.AutomaticManagedPagefile = $false; $cs.Put() | Out-Null

                        # Detect existing pagefiles on all drives
                        $allPfs = @(Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue)
                        $nonCPfs = $allPfs | Where-Object { $_.Name -and -not $_.Name.StartsWith("C:\") }
                        if ($nonCPfs) {
                            $drives = ($nonCPfs | ForEach-Object { $_.Name }) -join ", "
                            Write-Warn "Existing pagefile(s) on other drives: $drives"
                            Write-Info "These will remain unchanged. Remove via System Properties -> Advanced if not needed."
                        }

                        $pf = Get-WmiObject -Class Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'"
                        if (-not $pf) { $pf = ([wmiclass]"Win32_PageFileSetting").CreateInstance() }
                        $pf.Name = "C:\pagefile.sys"
                        $pf.InitialSize = $pfMB; $pf.MaximumSize = $pfMB; $pf.Put() | Out-Null
                        Write-OK "Pagefile: C:\pagefile.sys | ${pfMB} MB fixed (takes effect after restart)"
                    } catch { Write-Warn "Pagefile configuration failed: $_" }
                } else {
                    Write-Host "  [DRY-RUN] Would set pagefile to ${pfMB} MB fixed on C:" -ForegroundColor Magenta
                }
                Complete-Step $PHASE 8 "Pagefile"
            } `
            -SkipAction { Skip-Step $PHASE 8 "Pagefile" }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 9 — RESIZABLE BAR  [T2]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 9) {
    Write-Section "Step 9 — Resizable BAR / Smart Access Memory"
    if ($gpuInput -eq "3") {
        Invoke-TieredStep -Tier 2 -Title "Check AMD Smart Access Memory (SAM)" `
            -Why "SAM allows CPU access to full GPU VRAM. CS2 streams many textures -> SAM reduces CPU overhead." `
            -Evidence "Benchmarks show notable increase in 1% low FPS on AMD Ryzen 3000+/5000+/7000+ with RX 5000+/6000+/7000+." `
            -Caveat "Requires: Ryzen 3000+ + RX 5000+ + compatible motherboard + BIOS setting (Above 4G Decoding + ReBAR)." `
            -Risk "SAFE" -Depth "CHECK" `
            -Improvement "Reduced CPU overhead during texture streaming — +3-8% 1% lows on compatible hardware" `
            -SideEffects "None — BIOS guide only, no automatic changes" `
            -Undo "N/A (BIOS setting)" `
            -Action {
                Write-Info "SAM cannot be set via PowerShell — BIOS required."
                Write-Blank
                Write-Host "  SAM BIOS GUIDE:" -ForegroundColor White
                Write-Info "  1.  Restart PC -> BIOS (DEL / F2)"
                Write-Info "  2.  Advanced -> PCI Subsystem -> Above 4G Decoding: ENABLED"
                Write-Info "  3.  Advanced -> PCI Subsystem -> Re-Size BAR Support: ENABLED (or Auto)"
                Write-Info "  4.  AMD specific: SAM / Smart Access Memory: ENABLED"
                Write-Info "  5.  Save + restart"
                Write-Info "  Verify: AMD Adrenalin -> System -> SmartAccess Memory: ON"
                Read-Host "  [Enter] when done or to skip"
                Complete-Step $PHASE 9 "ReBAR"
            } `
            -SkipAction { Skip-Step $PHASE 9 "ReBAR" }
    } elseif ($gpuInput -in @("1","2")) {
        Invoke-TieredStep -Tier 2 -Title "Check NVIDIA Resizable BAR" `
            -Why "Like AMD SAM — CPU access to full VRAM buffer. Reduces CPU overhead during texture streaming." `
            -Evidence "NVIDIA supports ReBAR from RTX 3000+ with Ampere architecture. Measurable effect on 1% lows." `
            -Caveat "Requires: RTX 3000+ + compatible motherboard + BIOS Above 4G Decoding + ReBAR Support." `
            -Risk "SAFE" -Depth "CHECK" `
            -Improvement "Reduced CPU overhead — +3-8% 1% lows on RTX 3000+" `
            -SideEffects "None — BIOS guide only" `
            -Undo "N/A (BIOS setting)" `
            -Action {
                Write-Info "BIOS setting required — cannot be set via PowerShell."
                Write-Host "  ReBAR BIOS GUIDE:" -ForegroundColor White
                Write-Info "  1.  Restart PC -> BIOS (DEL / F2)"
                Write-Info "  2.  Advanced -> PCI Subsystem -> Above 4G Decoding: ENABLED"
                Write-Info "  3.  Advanced -> PCI Subsystem -> Re-Size BAR Support: ENABLED"
                Write-Info "  4.  Save + restart"
                Write-Info "  Verify: GPU-Z -> Advanced -> ReBAR: Yes"
                Read-Host "  [Enter] when done or to skip"
                Complete-Step $PHASE 9 "ReBAR"
            } `
            -SkipAction { Skip-Step $PHASE 9 "ReBAR" }
    } else {
        Write-Info "Intel Arc: ReBAR is enabled by default."
        Skip-Step $PHASE 9 "ReBAR"
    }
}
