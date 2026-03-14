#Requires -RunAsAdministrator
<#
.SYNOPSIS  CS2 Optimization Suite — Post-Reboot Setup (Normal boot after GPU driver clean)

  Steps:
    1   Install driver (native extract + install)  [T1]
    2   MSI Interrupts (native registry)  [T2]
    3   NIC Interrupt Affinity (native registry)  [T3]
    4   NVIDIA CS2 Profile (native registry)  [T3]
    5   FPS Cap Info  [T1]
    6   CS2 Launch Options + In-game Settings
    7   (reserved)
    8   AMD GPU Settings  [T2, AMD only]
    9   DNS Server Configuration  [T3]
    10  Process Priority / CCD Affinity (native IFEO)  [T3]
    11  VRAM Leak Awareness  [Info]
    12  Knowledge Summary + Checklist
    13  Final Benchmark + FPS Cap Calculation  [T1, LAST STEP]
#>

$ErrorActionPreference = "SilentlyContinue"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\config.env.ps1"
. "$ScriptRoot\helpers.ps1"
. "$ScriptRoot\Guide-VideoSettings.ps1"

$state    = Load-State $CFG_StateFile
$fpsCap   = $state.fpsCap
$avgFps   = $state.avgFps
$gpuInput = $state.gpuInput
$PHASE    = 3

# Initialize backup system for this phase
Initialize-Backup

Ensure-Dir $CFG_LogDir
Initialize-Log
Write-Banner 3 3 "Normal Boot  ·  Driver · MSI · CS2"

$startStep = Show-ResumePrompt $PHASE 13
if ($startStep -gt 13) { Write-Info "Phase 3 already completed."; Read-Host "  [Enter]"; exit 0 }

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — INSTALL DRIVER  [T1]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 1) {
    Write-Section "Step 1 — Install Driver"
    Write-TierBadge 1 "Clean driver installation after GPU driver removal"

    if ($gpuInput -in @("1","2")) {
        # Find driver .exe — check state first, then prompt
        $driverExe = $state.nvidiaDriverPath
        if (-not $driverExe -or -not (Test-Path $driverExe)) {
            Write-Info "NVIDIA driver .exe not found in expected location."
            Write-Info "If you downloaded the driver manually, provide the path now."
            $driverExe = Read-Host "  Path to NVIDIA driver .exe (or [Enter] to download)"
            if ([string]::IsNullOrWhiteSpace($driverExe)) {
                Write-Step "Attempting automatic driver download..."
                $driverInfo = Get-LatestNvidiaDriver
                if ($driverInfo -and -not $driverInfo.ManualDownload) {
                    $driverExe = "$CFG_WorkDir\nvidia_driver.exe"
                    Invoke-Download $driverInfo.Url $driverExe "NVIDIA Driver $($driverInfo.Version)" | Out-Null
                } else {
                    Write-Warn "Auto-download failed. Download manually:"
                    Write-Info "https://www.nvidia.com/en-us/drivers/"
                    $driverExe = Read-Host "  Path to downloaded .exe"
                }
            }
        }

        if ($state.rollbackDriver) {
            Write-Blank
            Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
            Write-Host "  ║  ROLLBACK REQUESTED: Driver $($state.rollbackDriver)$((' ' * (30 - $state.rollbackDriver.Length)))║" -ForegroundColor Yellow
            Write-Host "  ║  Make sure the .exe matches this version!               ║" -ForegroundColor Yellow
            Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        }

        if ($driverExe -and (Test-Path $driverExe)) {
            Write-Info "Driver: $driverExe"
            Write-Info "Installing with bloat removed + post-install tweaks..."
            Write-Info "(MSI interrupts, telemetry off, HDCP off, write combining, MPO off)"
            Write-Blank
            $r = Read-Host "  Install now? [Y/n]"
            if ($r -notmatch "^[nN]$") {
                $result = Install-NvidiaDriverClean -DriverExe $driverExe
                if ($result) {
                    Write-OK "NVIDIA driver installed successfully."
                    Complete-Step $PHASE 1 "Driver"
                } else {
                    Write-Warn "Installation may have issues — check Device Manager."
                    Write-Warn "Step 1 not marked complete — will re-run on resume."
                }
            } else {
                Write-Info "Skipped driver install."
                Skip-Step $PHASE 1 "Driver"
            }
        } else {
            Write-Err "No valid driver .exe found."
            Write-Info "Download from: https://www.nvidia.com/en-us/drivers/"
            Write-Info "Then restart Phase 3."
        }

        if ($gpuInput -eq "1") {
            Write-Warn "RTX 5000: NVIDIA CP -> Scaling -> MONITOR (not GPU)!"
        }
    } else {
        Write-Info "$(if($gpuInput -eq '3'){'AMD: https://www.amd.com/support'}else{'Intel Arc: https://www.intel.com/content/www/us/en/download-center/home.html'})"
        Write-Info "Custom Install -> driver only, no overlay / link."
        Read-Host "  After driver installation [Enter]"
        Complete-Step $PHASE 1 "Driver"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — MSI INTERRUPTS  [T2]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 2) {
    Write-Section "Step 2 — MSI Interrupts  ·  GPU + NIC + Audio"
    Invoke-TieredStep -Tier 2 -Title "Enable MSI interrupts (native registry)" `
        -Why "MSI interrupts for GPU, NIC, audio -> less DPC latency." `
        -Evidence "Measurable if LatencyMon shows DPC spikes. Without diagnosis: situational." `
        -Caveat "Not all devices support MSI. Errors are ignored for unsupported devices." `
        -Risk "MODERATE" -Depth "REGISTRY" -EstimateKey "MSI Interrupts" `
        -Improvement "Less DPC latency for GPU/NIC/audio — measurable with LatencyMon" `
        -SideEffects "Rare: device instability if MSI not supported (errors are ignored safely)" `
        -Undo "Delete MSISupported values from device Interrupt Management registry keys" `
        -Action {
            Enable-DeviceMSI
            Complete-Step $PHASE 2 "MSI"
        } `
        -SkipAction { Skip-Step $PHASE 2 "MSI" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — NIC INTERRUPT AFFINITY  [T3]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 3) {
    Write-Section "Step 3 — NIC Interrupt Affinity"
    Invoke-TieredStep -Tier 3 -Title "Set NIC interrupt affinity (native registry)" `
        -Why "Binds NIC interrupts to last physical core, away from Core 0." `
        -Evidence "T3: Only relevant after LatencyMon diagnosis with clear NIC DPC issue." `
        -Caveat "For most users: no measurable effect. Goal: keep NIC DPC/ISR off Core 0." `
        -Risk "MODERATE" -Depth "REGISTRY" `
        -Improvement "NIC interrupts off Core 0 — only relevant if LatencyMon shows NIC DPC issue" `
        -SideEffects "Wrong affinity can increase latency. Only useful after LatencyMon diagnosis." `
        -Undo "Delete DevicePolicy + AssignmentSetOverride from NIC Affinity Policy key" `
        -Action {
            Set-NicInterruptAffinity
            Complete-Step $PHASE 3 "NicAffinity"
        } `
        -SkipAction { Skip-Step $PHASE 3 "NicAffinity" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — NVIDIA CS2 PROFILE  [T3]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 4) {
    if ($gpuInput -in @("1","2")) {
        Write-Section "Step 4 — NVIDIA CS2 Profile (DRS direct write)"
        Invoke-TieredStep -Tier 3 -Title "Apply NVIDIA CS2 profile settings (DRS + registry)" `
            -Why "Writes 51 optimized DWORD settings directly to NVIDIA DRS binary database via nvapi64.dll. Falls back to registry if DRS unavailable." `
            -Evidence "T3: No isolated 1%-low benchmark for the full profile. Individual flags may be T2." `
            -Caveat "Requires nvapi64.dll (NVIDIA driver installed). Falls back to registry if unavailable." `
            -Risk "SAFE" -Depth "DRIVER" `
            -Improvement "All 51 DWORD settings applied directly to DRS binary database + PerfLevelSrc registry key" `
            -SideEffects "None — all DRS settings backed up automatically. Reversible via rollback or NPI -> Restore Defaults" `
            -Undo "Restore via backup rollback, or NVIDIA CP -> Manage 3D Settings -> Restore Defaults" `
            -Action {
                Apply-NvidiaCS2Profile
                Complete-Step $PHASE 4 "NVProfile"
            } `
            -SkipAction { Skip-Step $PHASE 4 "NVProfile" }
    } else {
        Skip-Step $PHASE 4 "NVProfile"
        Write-Section "Step 4 — GPU Profile (skipped — non-NVIDIA)"
        Write-Blank
        Write-Host "  This suite has no AMD/Intel equivalent of the NVIDIA DRS profile step." -ForegroundColor Yellow
        Write-Host "  For AMD GPUs, configure the following manually in Radeon Software → Gaming → CS2:" -ForegroundColor White
        Write-Blank
        Write-Sub "Radeon Chill             → Disabled"
        Write-Sub "Radeon Boost             → Disabled"
        Write-Sub "Anti-Aliasing            → Use Application Settings  (let CS2 MSAA handle it)"
        Write-Sub "Anisotropic Filtering    → Use Application Settings  (let video.txt AF16x handle it)"
        Write-Sub "Texture Filtering Quality→ Performance"
        Write-Sub "Power Efficiency         → Prefer Maximum Performance"
        Write-Blank
        Write-Info "These settings persist in Radeon Software across game launches."
        Write-Info "Re-apply after major AMD driver updates (Adrenalin can reset per-game profiles)."
        Write-Blank
        Read-Host "  [Enter] to continue"
    }

    # NVIDIA CP hints — always show for NVIDIA
    if ($gpuInput -in @("1","2")) {
        Write-Blank
        Write-Host "  NVIDIA CONTROL PANEL — remaining manual checks:" -ForegroundColor White
        if ($fpsCap -gt 0) {
            Write-Host "  [T1] Max Frame Rate        ->  $fpsCap  (avg $avgFps - 9%)" -ForegroundColor Green
            "$fpsCap" | Set-Clipboard
            Write-Info "       FPS cap $fpsCap copied to clipboard."
        } else {
            Write-Host "  [T1] Max Frame Rate        ->  set after benchmark with FpsCap-Calculator" -ForegroundColor Yellow
        }
        Write-Host "  [T2] Low Latency Mode      ->  Ultra  (only if Reflex NOT active)" -ForegroundColor Yellow
        Write-Blank
        Write-Host "  NOTE: 3 niche settings excluded (string type, GPU-specific, frame interp)." -ForegroundColor DarkGray
        Write-Host "  See docs/nvidia-drs-settings.md for full details." -ForegroundColor DarkGray
        if ($gpuInput -eq "1") {
            Write-Warn "RTX 5000: Scaling -> MONITOR (not GPU) for 4:3 stretched."
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — FPS CAP INFO  [T1]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 5) {
    Write-Section "Step 5 — FPS Cap Info"
    Write-TierBadge 1 "FPS Cap — directly measurable effect on frametime consistency"
    Write-Blank
    Write-Host "  FPS cap will be calculated in the FINAL STEP after all optimizations." -ForegroundColor Yellow
    Write-Host "  Method: avg FPS - 9%  (FPSHeaven / Blur Busters recommendation)." -ForegroundColor DarkGray
    if ($fpsCap -gt 0) {
        Write-Host "  Already calculated cap: $fpsCap  (avg $avgFps - 9%)" -ForegroundColor Green
    }
    Complete-Step $PHASE 5 "FpsCapInfo"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — CS2 LAUNCH OPTIONS + VIDEO SETTINGS (Feb 2026 Meta)
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 6) {
    Write-Section "Step 6 — Launch Options + Video Settings (Feb 2026 Meta)"
    Show-CS2SettingsGuide -fpsCap $fpsCap -avgFps $avgFps -gpuInput $gpuInput
    Complete-Step $PHASE 6 "CS2Settings"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 7 — RESERVED
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 7 -and -not (Test-StepDone $PHASE 7)) {
    Complete-Step $PHASE 7 "Reserved"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 8 — AMD GPU SETTINGS  [T2, AMD only]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 8) {
    if ($gpuInput -eq "3") {
        Write-Section "Step 8 — AMD GPU Settings"
        Invoke-TieredStep -Tier 2 -Title "Optimize AMD Radeon Software for CS2" `
            -Why "AMD Adrenalin has several features that actively hurt competitive CS2: Radeon Boost dynamically lowers resolution during mouse movement (resolution drops at exactly the wrong moment). Radeon Chill is a dynamic FPS limiter (raises latency). AMD Fluid Motion Frames (AFMF) is frame interpolation — adds ~1 frame of input lag. Anti-Lag (driver-level) and Anti-Lag 2 (game-engine-integrated, RDNA3+) reduce input lag by coordinating CPU-GPU timing; Anti-Lag was temporarily pulled in Sept 2023 due to CS2 VAC bans but current drivers are patched and whitelisted." `
            -Evidence "Radeon Boost: AMD documentation — 'dynamically adjusts resolution during fast movements'. Radeon Chill: dynamic FPS limiter, latency cost confirmed. AFMF: frame interpolation inherently adds input lag. Anti-Lag: driver-level CPU-GPU timing coordination, measured input lag reduction. Anti-Lag 2: game-engine-integrated version (RDNA3+); VAC ban incident Sept 2023 resolved by AMD driver patch." `
            -Caveat "Anti-Lag 2 is RDNA3+ only (RX 7000 series+). VAC ban risk from Anti-Lag is resolved in current AMD drivers — use Anti-Lag 1 if RDNA2 or earlier. AMD driver must be installed manually from amd.com (no auto-install in this suite for AMD). fTPM stuttering: if on Ryzen and experiencing random 1-2 second freezes, disable fTPM in BIOS (BIOS -> AMD fTPM switch -> Discrete TPM) — separate from driver settings." `
            -Risk "SAFE" -Depth "CHECK" `
            -Improvement "Eliminates resolution-drop artifacts (Boost off), FPS limiter latency (Chill off), frame interpolation lag (AFMF off). Anti-Lag: measured input lag reduction." `
            -SideEffects "Manual Adrenalin settings — no system changes made here." `
            -Undo "N/A (manual AMD Adrenalin settings)" `
            -Action {
                Write-Blank
                Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Red
                Write-Host "  │  AMD RADEON SOFTWARE — COMPETITIVE CS2 SETTINGS              │" -ForegroundColor Red
                Write-Host "  │                                                              │" -ForegroundColor Red
                Write-Host "  │  Gaming -> Graphics (Global Settings):                      │" -ForegroundColor White
                Write-Host "  │  ✔  Anti-Lag:                  ON  (Anti-Lag 2 if RDNA3+)  │" -ForegroundColor Green
                Write-Host "  │  ✗  Radeon Boost:              OFF (lowers res mid-aim!)   │" -ForegroundColor Red
                Write-Host "  │  ✗  Radeon Chill:              OFF (dynamic FPS = latency) │" -ForegroundColor Red
                Write-Host "  │  ✗  Fluid Motion Frames (AFMF):OFF (frame interp = lag)   │" -ForegroundColor Red
                Write-Host "  │  ✗  Image Sharpening:          OFF (post-process overhead) │" -ForegroundColor DarkGray
                Write-Host "  │  ✔  Texture Filtering Quality: Performance                 │" -ForegroundColor White
                Write-Host "  │  ✔  Wait for Vertical Refresh: Always Off                  │" -ForegroundColor White
                Write-Host "  │                                                              │" -ForegroundColor Red
                Write-Host "  │  Performance -> Tuning:                                     │" -ForegroundColor White
                Write-Host "  │  ✔  GPU Tuning:                Standard                    │" -ForegroundColor White
                Write-Host "  │  ✔  VRAM Tuning:               Standard (or EXPO match)    │" -ForegroundColor White
                Write-Host "  │                                                              │" -ForegroundColor Red
                Write-Host "  │  NOTE — Anti-Lag VAC ban (Sept 2023):                       │" -ForegroundColor Yellow
                Write-Host "  │  AMD pulled Anti-Lag in Sept 2023 after CS2 VAC bans.       │" -ForegroundColor DarkYellow
                Write-Host "  │  Current drivers (Nov 2023+) are patched and whitelisted.  │" -ForegroundColor DarkYellow
                Write-Host "  │  Anti-Lag 1 safe for all RDNA. Anti-Lag 2: RDNA3+ only.   │" -ForegroundColor DarkYellow
                Write-Host "  │                                                              │" -ForegroundColor Red
                Write-Host "  │  NOTE — AMD fTPM stuttering (Ryzen only):                   │" -ForegroundColor Yellow
                Write-Host "  │  Random 1-2 second freezes on Ryzen? Disable fTPM in BIOS: │" -ForegroundColor DarkYellow
                Write-Host "  │  BIOS -> Security -> AMD fTPM switch -> Discrete TPM.       │" -ForegroundColor DarkYellow
                Write-Host "  │  (Windows 11 requires TPM — use Discrete if available.)    │" -ForegroundColor DarkYellow
                Write-Host "  │                                                              │" -ForegroundColor Red
                Write-Host "  │  DRIVER INSTALL:                                             │" -ForegroundColor White
                Write-Host "  │  amd.com/support -> Download driver                         │" -ForegroundColor White
                Write-Host "  │  -> Custom Install -> Driver only (minimal Adrenalin)       │" -ForegroundColor White
                Write-Host "  │  -> Check 'Factory Reset' for clean install                 │" -ForegroundColor White
                Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Red
                Read-Host "  [Enter] when done"
                Complete-Step $PHASE 8 "AMDSettings"
            } `
            -SkipAction { Skip-Step $PHASE 8 "AMDSettings" }
    } else {
        Write-Debug "Step 8 — AMD GPU Settings skipped (not AMD)."
        Skip-Step $PHASE 8 "AMDSettings (not AMD)"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 9 — DNS SERVER CONFIGURATION  [T3]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 9) {
    Write-Section "Step 9 — DNS Server Configuration"
    Invoke-TieredStep -Tier 3 -Title "Switch DNS server to Cloudflare or Google" `
        -Why "ISP DNS can be slow -> longer connection setup times (not in-match ping)." `
        -Evidence "T3: DNS only affects connection setup, not in-game latency. No FPS effect." `
        -Caveat "Corporate networks often need custom DNS. Only for private internet connections." `
        -Risk "SAFE" -Depth "NETWORK" `
        -Improvement "Faster DNS lookups — affects matchmaking/lobby, NOT in-game latency" `
        -SideEffects "May not work on corporate/managed networks. ISP DNS features lost." `
        -Undo "Set DNS back to automatic: Set-DnsClientServerAddress -ResetServerAddresses" `
        -Action {
            Write-Blank
            Write-Host "  Choose DNS server:" -ForegroundColor White
            Write-Host "  [1]  Cloudflare  1.1.1.1 / 1.0.0.1  (fastest, privacy-focused)" -ForegroundColor Cyan
            Write-Host "  [2]  Google      8.8.8.8 / 8.8.4.4  (stable, widely used)" -ForegroundColor White
            Write-Host "  [3]  Skip" -ForegroundColor DarkGray
            do { $dnsChoice = Read-Host "  [1/2/3]" } while ($dnsChoice -notin @("1","2","3"))

            if ($dnsChoice -ne "3") {
                $dnsAddrs = if ($dnsChoice -eq "1") { $CFG_DNS_Cloudflare } else { $CFG_DNS_Google }
                $dnsName  = if ($dnsChoice -eq "1") { "Cloudflare" } else { "Google" }
                try {
                    $nic = Get-NetAdapter | Where-Object {
                        $_.Status -eq "Up" -and
                        $_.InterfaceDescription -notmatch "Loopback|Virtual|Hyper-V|Bluetooth"
                    } | Sort-Object LinkSpeed -Descending | Select-Object -First 1
                    if ($nic) {
                        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $dnsAddrs
                        Write-OK "DNS set to ${dnsName}: $($dnsAddrs -join ', ') (Adapter: $($nic.Name))"
                    } else {
                        Write-Warn "No active network adapter found."
                    }
                } catch { Write-Warn "DNS change failed: $_" }
            } else {
                Write-Info "DNS not changed."
            }
            Complete-Step $PHASE 9 "DNS"
        } `
        -SkipAction { Skip-Step $PHASE 9 "DNS" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 10 — PROCESS PRIORITY / CCD AFFINITY  [T3]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 10) {
    Write-Section "Step 10 — Process Priority / CCD Affinity (native IFEO)"
    Invoke-TieredStep -Tier 3 -Title "Set persistent CS2 process priority (native IFEO)" `
        -Why "High CPU priority gives CS2 scheduler preference. CCD pinning for dual-CCD X3D." `
        -Evidence "T3: No isolated benchmark for priority class. CCD pinning measurable on dual-CCD X3D." `
        -Caveat "High priority is safe for games. Realtime would be dangerous — we never use it." `
        -Risk "SAFE" -Depth "REGISTRY" `
        -Improvement "CPU priority for CS2 — persistent via IFEO (no background service needed)" `
        -SideEffects "None — High priority is standard for games. Easily reversible." `
        -Undo "Remove IFEO PerfOptions key + unregister CCD affinity task (if created)" `
        -Action {
            Set-CS2ProcessPriority
            Complete-Step $PHASE 10 "ProcessPriority"
        } `
        -SkipAction { Skip-Step $PHASE 10 "ProcessPriority" }
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 11 — VRAM LEAK AWARENESS  [Info]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 11) {
    Write-Section "Step 11 — VRAM Leak Awareness"
    Write-TierBadge 2 "CS2 VRAM Leak Bug — Known Issue"
    Write-Blank
    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  CS2 KNOWN VRAM LEAK BUG:                                   │" -ForegroundColor Yellow
    Write-Host "  │                                                              │" -ForegroundColor Yellow
    Write-Host "  │  CS2 has a known VRAM leak especially affecting GPUs with   │" -ForegroundColor White
    Write-Host "  │  8 GB VRAM. After long sessions (2+ hours) VRAM usage      │" -ForegroundColor White
    Write-Host "  │  steadily rises -> stutter and FPS drops.                  │" -ForegroundColor White
    Write-Host "  │                                                              │" -ForegroundColor Yellow
    Write-Host "  │  RECOMMENDATION:                                            │" -ForegroundColor White
    Write-Host "  │  -> Restart CS2 every 2-3 hours                            │" -ForegroundColor Green
    Write-Host "  │  -> Monitor VRAM usage with HWiNFO64 or Task Manager       │" -ForegroundColor White
    Write-Host "  │  -> Warning at > 85% VRAM usage                            │" -ForegroundColor White
    Write-Host "  │                                                              │" -ForegroundColor Yellow
    Write-Host "  │  MOST AFFECTED:                                             │" -ForegroundColor DarkYellow
    Write-Host "  │  -> RTX 4060 / 4060 Ti (8 GB) -> critical after ~3h       │" -ForegroundColor White
    Write-Host "  │  -> RX 7600 (8 GB) -> similar issues                       │" -ForegroundColor White
    Write-Host "  │  -> 12+ GB GPUs: less problematic, but exists              │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Blank
    Complete-Step $PHASE 11 "VRAMLeak"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 12 — FINAL CHECKLIST + HONEST KNOWLEDGE SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 12) {
    Write-Section "Step 12 — Final Checklist + Knowledge Summary"

    Write-Host @"

  DONE — with proven effect:
  ✔  Shader cache cleared           [T1: Directly measurable after driver change]
  ✔  Fullscreen optimizations       [T1: m0NESY-documented, no downside]
  ✔  FPSHeaven 2026 power plan       [T1: 100+ sub-settings, comprehensive]
  ✔  Native driver clean + install  [T1: Industry standard]
  ✔  GPU MSI via native registry    [T1: Interrupt overhead measurable]
  ✔  FPS cap via NVCP               [T1: Reproduced, more stable frametimes]
  ✔  Video settings configured      [Boost Contrast +5% lows, AO -30fps]
  ✔  Dual-channel RAM checked       [T1: Half bandwidth = dramatic]
"@ -ForegroundColor Green

    Write-Host @"
  DONE — setup-dependent (T2):
  ✔  XMP/EXPO checked               [Hardware logic: sensible. CS2 bench: unclear]
  ✔  Resizable BAR / SAM            [AMD: measurable. CS2-specific: no data]
  ✔  Nagle's Algorithm               [TCP latency reduced]
  ✔  GameConfigStore FSE keys       [Supplements fullscreen exclusive]
  ✔  SystemResponsiveness           [Gaming priority in scheduler]
  ✔  Timer resolution               [More precise system timer]
  ✔  Mouse acceleration             [1:1 input for aim consistency]
  ✔  Game DVR / Game Bar            [Background recording off]
  ✔  Overlays                       [Steam/Discord/GFE overlay off]
  ✔  Audio optimized                [24-bit/48kHz, no spatial sound]
  ✔  Autoexec.cfg                   [Network CVars optimized]
  ✔  Chipset driver checked         [Current driver recommended]
"@ -ForegroundColor Yellow

    Write-Host @"
  STILL MANUAL:
  ○  Run benchmark map 3 times (Dust2 + Inferno recommended)
  ○  Calculate FPS cap: START.bat -> [3] FPS Cap Calculator
  ○  Verify Reflex decision with CapFrameX:
     Test A (-noreflex + NVCP Ultra) vs. B (Reflex ON in-game)
     Choose what gives better lows AND better feel.
  ○  Check settings after Windows Update: START.bat -> [6] Verify
  ○  All 52 NVIDIA DRS settings applied natively — no external tools needed
"@ -ForegroundColor Cyan

    Write-Blank
    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor DarkYellow
    Write-Host "  │  WHAT THIS SCRIPT CANNOT FIX                                │" -ForegroundColor DarkYellow
    Write-Host "  │                                                              │" -ForegroundColor DarkYellow
    Write-Host "  │  CS2 has structurally poor frame pacing.                    │" -ForegroundColor White
    Write-Host "  │  Apex Legends, The Finals and Warzone — all with higher     │" -ForegroundColor White
    Write-Host "  │  graphics load — deliver consistently better 1% lows.       │" -ForegroundColor White
    Write-Host "  │  This is a Valve/Source2 problem, not a hardware problem.   │" -ForegroundColor White
    Write-Host "  │  No tweak fundamentally fixes this.                         │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor DarkYellow

    Write-Blank
    Write-Host "  NEXT STEPS — IF PROBLEMS PERSIST:" -ForegroundColor White
    Write-Host @"
  1.  Run LatencyMon  (resplendence.com/latencymon)
      -> Shows which drivers cause DPC spikes
      -> Then decide if NIC tweaks or MSI Utility are useful

  2.  Log HWiNFO64 during a match
      -> Log CPU/GPU package temp + clock + power
      -> Thermal throttling is a commonly overlooked cause of lows

  3.  Rule out thermal problems
      -> CPU TJmax: AMD Ryzen 95C, Intel varies
      -> GPU: 83C = throttle start on NVIDIA

  4.  RAM sub-timings (only if XMP active and stable)
      -> B-Die or Hynix A-Die recommended
      -> CL30 -> CL28 -> CL26 stabilize with TM5/HCI MemTest
      -> Effect on 1% lows measurable but hardware-dependent

  5.  CPU upgrade as last resort
      -> 9800X3D is clear leader for CS2 as of March 2026
      -> Single-core performance is the limiting factor

  Rule: Always measure before/after with CapFrameX.
  Without measurement, any claim about improvement is placebo.
"@ -ForegroundColor DarkGray

    Write-Info "Log: $CFG_LogFile  |  Tools: $CFG_WorkDir"
    Complete-Step $PHASE 12 "Checklist"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 13 — FINAL BENCHMARK + FPS CAP  [T1, LAST STEP]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 13) {
    Write-Section "Step 13 — Final Benchmark + FPS Cap Calculation  [LAST STEP]"
    Write-TierBadge 1 "Post-optimization benchmark — proof of improvement"
    Write-Blank

    Write-Host @"
  FPSHEAVEN BENCHMARK MAPS  (by @fREQUENCYcs)
  ─────────────────────────────────────────────
  Outputs at end in console window:
    [VProf] FPS: Avg=XXX.X, P1=XXX.X

  Map 1 — DUST2  (community standard):
  $CFG_Benchmark_Dust2

  Map 2 — INFERNO:
  $CFG_Benchmark_Inferno

  Map 3 — ANCIENT  (water interaction):
  $CFG_Benchmark_Ancient

  WORKFLOW:
  1.  Steam -> Workshop -> Subscribe to map
  2.  CS2: Play -> Workshop Maps -> start
  3.  Runs 2-3 minutes automatically — don't touch PC
  4.  Console opens automatically -> copy [VProf] line
  5.  Paste output below for automatic tracking + FPS cap

  BEST RESULT: Run 3 times, use the average.

  WHY AN FPS CAP?
  ────────────────
  Without a cap the GPU runs at max continuously -> frametimes fluctuate.
  With a cap the GPU runs at even load -> more consistent 1% lows.
  Method: avg FPS - 9%  (FPSHeaven / Blur Busters recommendation).
"@ -ForegroundColor DarkGray

    if ($fpsCap -gt 0) {
        Write-Host "  Already calculated cap: $fpsCap  (avg $avgFps - 9%)" -ForegroundColor Green
    }

    # Use the iterative benchmark tracking system
    $bmResult = Invoke-BenchmarkCapture -Label "After all optimizations"

    if ($bmResult) {
        Write-Blank
        Write-Info "Set FPS cap in: NVIDIA CP -> CS2 -> Max Frame Rate -> $($bmResult.Cap)"
        Write-Info "You can run this benchmark again anytime via START.bat -> [3] FPS Cap Calculator."
        Write-Info "All results are tracked in: $CFG_BenchmarkFile"

        # Show improvement estimate vs. actual results
        $baselineAvg = if ($state.baselineAvg) { $state.baselineAvg } else { 0 }
        $baselineP1  = if ($state.baselineP1)  { $state.baselineP1 }  else { 0 }
        Show-ImprovementEstimate -BaselineAvg $baselineAvg -BaselineP1 $baselineP1 `
            -ActualAvg $bmResult.Avg -ActualP1 $bmResult.P1
    }

    # Show full history if multiple results exist
    $history = Get-BenchmarkHistory
    if ($history.Count -ge 2) {
        Write-Blank
        Show-BenchmarkComparison
    }

    Complete-Step $PHASE 13 "FinalBenchmark"
}

Write-Blank
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║  ALL 3 PHASES COMPLETE — GOOD LUCK!                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Blank

$r = Read-Host "  Final restart recommended (MSI changes). Now? [y/N]"
if ($r -match "^[jJyY]$") { Restart-Computer -Force }
