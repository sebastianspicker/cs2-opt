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
    7   VBS / Core Isolation disable  [T2]
    8   AMD GPU Settings  [T2, AMD only]
    9   DNS Server Configuration  [T3]
    10  Process Priority / CCD Affinity (native IFEO)  [T3]
    11  VRAM Leak Awareness  [Info]
    12  Knowledge Summary + Checklist
    13  Final Benchmark + FPS Cap Calculation  [T1, LAST STEP]
#>

param([switch]$SmokeTest)

if ($SmokeTest) {
    Write-Host "SMOKE TEST OK: PostReboot-Setup" -ForegroundColor Green
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\config.env.ps1"
. "$ScriptRoot\helpers.ps1"
. "$ScriptRoot\Guide-VideoSettings.ps1"

try {
    $state = Load-State $CFG_StateFile
} catch {
    Write-Host "  $([char]0x2718) Something went wrong: settings file (state.json) is missing or corrupted." -ForegroundColor Red
    Write-Host "    Error detail: $_" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $([char]0x2139) What to do:" -ForegroundColor Cyan
    Write-Host "    - Phase 1 may not have finished, or the runtime state was lost." -ForegroundColor White
    Write-Host "    - Re-run START.bat -> [1] Start / Resume Optimization to rebuild the handoff state." -ForegroundColor White
    Write-Host "    - If Phase 2 already finished, re-run START.bat -> [S] Boot to Safe Mode, then continue." -ForegroundColor White
    exit 1
}

if (-not (Test-Phase1SafeModeReady -State $state)) {
    Write-Host "" 
    Write-Host "  $([char]0x2718) Phase 3 launch rejected: the Phase 1 Safe Mode handoff is not marked ready." -ForegroundColor Red
    Write-Host "  $([char]0x2139) What to do:" -ForegroundColor Cyan
    Write-Host "    - Run START.bat -> [1] and complete Step 38, or use START.bat -> [S] Boot to Safe Mode." -ForegroundColor White
    Write-Host "    - Then let Phase 2 finish before re-running Phase 3 from START.bat -> [P]." -ForegroundColor White
    exit 1
}

$fpsCap   = if ($state.PSObject.Properties['fpsCap']) { $state.fpsCap } else { 0 }
$SCRIPT:fpsCap = $fpsCap
$avgFps   = if ($state.PSObject.Properties['avgFps']) { $state.avgFps } else { 0 }
$gpuInput = $state.gpuInput
$PHASE    = 3
$SCRIPT:PhaseTotal = 13
$SCRIPT:CurrentPhase = 3

# Guard: if Phase 1 was run in DRY-RUN, warn and confirm before Phase 3 applies real changes
if ($SCRIPT:DryRun) {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║  DRY-RUN MODE INHERITED FROM PHASE 1                       ║" -ForegroundColor Magenta
    Write-Host "  ║  Phase 3 will preview changes only — nothing will be       ║" -ForegroundColor Magenta
    Write-Host "  ║  applied unless you switch to a live profile.              ║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    $drChoice = if (Test-YoloProfile) { "Y" } else { Read-Host "  Continue in DRY-RUN mode? [Y/n]" }
    if ($drChoice -match "^[nN]$") {
        $SCRIPT:DryRun = $false
        # Derive mode from current profile (must match Setup-Profile.ps1 logic)
        $SCRIPT:Mode = switch ($SCRIPT:Profile) {
            "SAFE"        { "AUTO" }
            "RECOMMENDED" { "AUTO" }
            "COMPETITIVE" { "CONTROL" }
            "CUSTOM"      { "INFORMED" }
            "YOLO"        { "YOLO" }
            default       { "CONTROL" }
        }
        Write-Host "  Switched to $($SCRIPT:Mode) mode ($($SCRIPT:Profile) profile) — changes WILL be applied." -ForegroundColor Yellow
        # Persist the mode switch so re-launches don't revert to DRY-RUN
        try { $state | Add-Member -NotePropertyName "mode" -NotePropertyValue $SCRIPT:Mode -Force; Save-JsonAtomic -Data $state -Path $CFG_StateFile } catch {}
    }
}

# Guard: Phase 3 requires Normal Mode. If Safe Mode is active, the driver installer
# will fail and most optimizations cannot be applied.
if ($env:SAFEBOOT_OPTION) {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  SAFE MODE DETECTED — Phase 3 requires Normal Mode         ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host "  $([char]0x2139) Phase 3 installs GPU drivers and applies settings that need" -ForegroundColor Cyan
    Write-Host "    Normal Mode. The Safe Mode boot flag may not have been cleared." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Clearing Safe Mode flag now..." -ForegroundColor White
    try {
        $bcdResult = bcdedit /deletevalue safeboot 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  $([char]0x2714) Safe Mode disabled. Restarting into Normal Mode..." -ForegroundColor Green
            Write-Host "    Phase 3 will run automatically on next boot." -ForegroundColor White
            Set-RunOnce "CS2_Phase3" "$CFG_WorkDir\PostReboot-Setup.ps1"
            Start-Sleep -Seconds 2
            shutdown /r /t 0 /f
            exit 0
        }
    } catch {}
    Write-Host "  $([char]0x26A0) Could not clear Safe Mode flag automatically." -ForegroundColor Yellow
    Write-Host "  Run in elevated cmd.exe:" -ForegroundColor White
    Write-Host "    bcdedit /deletevalue safeboot" -ForegroundColor Cyan
    Write-Host "    shutdown /r /t 0" -ForegroundColor Cyan
    if (-not (Test-YoloProfile)) { Read-Host "  Press Enter to exit" }
    exit 1
}

if (-not (Test-StepDone 2 2)) {
    Write-Host ""
    Write-Host "  $([char]0x2718) Phase 3 launch rejected: Phase 2 driver removal is not recorded as completed." -ForegroundColor Red
    Write-Host "  $([char]0x2139) What to do:" -ForegroundColor Cyan
    Write-Host "    - Run START.bat -> [S] Boot to Safe Mode and complete the native driver-clean phase." -ForegroundColor White
    Write-Host "    - After the next normal boot, run START.bat -> [P] only if the auto-start did not fire." -ForegroundColor White
    exit 1
}

try {
# Initialize backup system for this phase (inside try so finally releases the lock on error)
Initialize-Backup
Initialize-PhaseCounters

# Load Phase 1 applied steps so improvement estimates are cumulative
Load-AppliedSteps

Ensure-Dir $CFG_LogDir
Initialize-Log
Write-Banner 3 3 "Normal Boot  ·  Driver · MSI · CS2"

$startStep = Show-ResumePrompt $PHASE 13
if ($startStep -gt 13) { Write-Info "Phase 3 already completed."; Remove-BackupLock; if (-not $SCRIPT:DryRun -and -not (Test-YoloProfile)) { Read-Host "  [Enter]" }; exit 0 }

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — INSTALL DRIVER  [T1]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 1) {
    Write-Section "Step 1 — Install Driver"
    Write-TierBadge 1 "Clean driver installation after GPU driver removal"

    # ── Remove leftover GPU AppX/MSIX packages ──────────────────────────────
    # Phase 2 runs in Safe Mode where AppXSVC cannot start, so AppX removal
    # is skipped there. Clean them up now in Normal Mode before the fresh install.
    $gpuAppxVendor = switch ($gpuInput) {
        { $_ -in @("1","2") } { "NVIDIA" }
        "3"                    { "AMD" }
        default                { $null }
    }
    if ($gpuAppxVendor -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        try {
            $gpuAppx = Get-AppxPackage -AllUsers -ErrorAction Stop |
                Where-Object { $_.Name -match $gpuAppxVendor }
            foreach ($pkg in $gpuAppx) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-OK "Removed leftover AppX: $($pkg.Name)"
                } catch {
                    Write-Debug "AppX removal: $($pkg.Name) — $_"
                }
            }
            # Also remove provisioned packages to prevent reinstall on feature updates
            $gpuProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match $gpuAppxVendor }
            foreach ($pkg in $gpuProv) {
                try {
                    $pkg | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
                    Write-OK "Removed provisioned: $($pkg.DisplayName)"
                } catch {
                    Write-Debug "Provisioned removal: $($pkg.DisplayName) — $_"
                }
            }
        } catch {
            Write-Debug "AppX cleanup: $_"
        }
    }

    if ($gpuInput -in @("1","2")) {
        # Find driver .exe — check state first, then prompt
        # SECURITY: state.json is in C:\CS2_OPTIMIZE\ — if tampered, nvidiaDriverPath could
        # point to malware. Validate: must be an .exe file, must exist, must not contain
        # path traversal sequences. The file is then passed to Start-Process in Install-NvidiaDriverClean.
        $driverExe = if ($state.PSObject.Properties['nvidiaDriverPath']) { $state.nvidiaDriverPath } else { $null }
        if ($driverExe) {
            # Reject path traversal, non-.exe, and suspicious paths
            if ($driverExe -match '\.\.' -or $driverExe -notmatch '\.exe$' -or $driverExe -match '[\x00]') {
                Write-Warn "state.json nvidiaDriverPath failed validation — ignoring: $driverExe"
                $driverExe = $null
            }
        }
        if (-not $driverExe -or -not (Test-Path $driverExe)) {
            Write-Info "NVIDIA driver .exe not found in expected location."
            Write-Info "If you downloaded the driver manually, provide the path now."
            Write-Info "Press [B] to browse for the file, or paste the path, or [Enter] to download."
            $driverExe = if ($SCRIPT:DryRun -or (Test-YoloProfile)) { "" } elseif ($true) {
                $driverInput = Read-Host "  Path / [B]rowse / [Enter] to download"
                if ($driverInput -match '^[bB]$') {
                    Add-Type -AssemblyName System.Windows.Forms
                    $dlg = New-Object System.Windows.Forms.OpenFileDialog
                    $dlg.Title = "Select NVIDIA Driver Installer"
                    $dlg.Filter = "Executable files (*.exe)|*.exe"
                    $dlg.InitialDirectory = [Environment]::GetFolderPath('UserProfile') + '\Downloads'
                    if ($dlg.ShowDialog() -eq 'OK') { $dlg.FileName } else { "" }
                } else {
                    # Strip surrounding quotes that paste sometimes adds
                    $driverInput -replace '^["'']|["'']$', ''
                }
            } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($driverExe)) {
                # Validate user-provided path: must exist and be an .exe
                if (-not (Test-Path $driverExe)) {
                    Write-Warn "File not found: $driverExe"
                    $driverExe = $null
                } elseif ($driverExe -notmatch '\.exe$') {
                    Write-Warn "Not an .exe file: $driverExe"
                    $driverExe = $null
                }
            }
            if ([string]::IsNullOrWhiteSpace($driverExe)) {
                if ($SCRIPT:DryRun) {
                    Write-Host "  [DRY-RUN] Would attempt automatic NVIDIA driver download" -ForegroundColor Magenta
                } else {
                    Write-Step "Attempting automatic driver download..."
                    $savedGpuName = if ($state.PSObject.Properties['nvidiaGpuName']) { $state.nvidiaGpuName } else { $null }
                    $driverInfo = Get-LatestNvidiaDriver -GpuName $savedGpuName
                    if ($driverInfo -and -not $driverInfo.ManualDownload) {
                        $driverExe = "$CFG_WorkDir\nvidia_driver.exe"
                        $dlResult = Invoke-Download $driverInfo.Url $driverExe "NVIDIA Driver $($driverInfo.Version)"
                        if (-not $dlResult) {
                            $driverExe = $null
                        # SECURITY (S1): Verify Authenticode signature immediately after download
                        } elseif (-not (Test-NvidiaDriverSignature $driverExe)) {
                            Write-Err "Downloaded driver failed signature verification. File removed."
                            $driverExe = $null
                        }
                    } else {
                        Write-Warn "Auto-download failed. Download manually:"
                        Write-Info "https://www.nvidia.com/en-us/drivers/"
                        Write-Info "Press [B] to browse for the file, or paste the path."
                        $rawInput = if (Test-YoloProfile) { "" } else { Read-Host "  Path / [B]rowse" }
                        if ($rawInput -match '^[bB]$') {
                            Add-Type -AssemblyName System.Windows.Forms
                            $dlg = New-Object System.Windows.Forms.OpenFileDialog
                            $dlg.Title = "Select NVIDIA Driver Installer"
                            $dlg.Filter = "Executable files (*.exe)|*.exe"
                            $dlg.InitialDirectory = [Environment]::GetFolderPath('UserProfile') + '\Downloads'
                            $driverExe = if ($dlg.ShowDialog() -eq 'OK') { $dlg.FileName } else { $null }
                        } else {
                            $driverExe = $rawInput -replace '^["'']|["'']$', ''
                        }
                        if ($driverExe -and ($driverExe -match '\.\.' -or $driverExe -notmatch '\.exe$' -or $driverExe -match '[\x00]')) {
                            Write-Warn "Invalid driver path: $driverExe"
                            $driverExe = $null
                        }
                    }
                }
            }
        }

        if ($state.PSObject.Properties['rollbackDriver'] -and $state.rollbackDriver) {
            Write-Blank
            Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
            $drvLabel = $state.rollbackDriver.Substring(0, [math]::Min(30, $state.rollbackDriver.Length))
            Write-Host "  ║  ROLLBACK REQUESTED: Driver $drvLabel$((' ' * [math]::Max(0, 30 - $drvLabel.Length)))║" -ForegroundColor Yellow
            Write-Host "  ║  Make sure the .exe matches this version!               ║" -ForegroundColor Yellow
            Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        }

        if ($driverExe -and (Test-Path $driverExe)) {
            Write-Info "Driver: $driverExe"
            Write-Info "Installing with bloat removed + post-install tweaks..."
            Write-Info "(MSI interrupts, telemetry off, HDCP off, write combining, MPO off)"
            Write-Blank
            $r = if ($SCRIPT:DryRun) { "n" } elseif (Test-YoloProfile) { "Y" } else { Read-Host "  Install now? [Y/n]" }
            if ($r -notmatch "^[nN]$") {
                $result = Install-NvidiaDriverClean -DriverExe $driverExe
                if ($result) {
                    Write-OK "NVIDIA driver installed successfully."
                    Complete-Step $PHASE 1 "Driver"
                } else {
                    Write-Warn "Installation may have had issues."
                    Write-Host "  $([char]0x2139) What to do: Open Device Manager (Win+X -> Device Manager)" -ForegroundColor Cyan
                    Write-Host "    and check if your GPU shows up under 'Display adapters' without" -ForegroundColor Cyan
                    Write-Host "    a yellow warning icon. If it looks fine, you're good!" -ForegroundColor Cyan
                    Write-Host "    This step will re-run on resume if needed." -ForegroundColor DarkGray
                }
            } else {
                Write-Info "Skipped driver install."
                Skip-Step $PHASE 1 "Driver"
            }
        } else {
            Write-Err "No valid driver file (.exe) found."
            Write-Host "  $([char]0x2139) What to do: Download your driver from the link below," -ForegroundColor Cyan
            Write-Host "    then re-run this phase from START.bat -> [P]." -ForegroundColor Cyan
            Write-Info "Download: https://www.nvidia.com/en-us/drivers/"
            $skipConfirm = if ($SCRIPT:DryRun -or (Test-YoloProfile)) { "y" } else { Read-Host "  Skip driver install and continue to Step 2? [y/N]" }
            if ($skipConfirm -match "^[jJyY]$") {
                Skip-Step $PHASE 1 "Driver"
            } else {
                Write-Info "Restart Phase 3 when ready."
            }
        }

        if ($gpuInput -eq "1") {
            Write-Warn "RTX 5000: NVIDIA CP -> Scaling -> MONITOR (not GPU)!"
        }
    } else {
        Write-Info "$(if($gpuInput -eq '3'){'AMD: https://www.amd.com/support'}else{'Intel Arc: https://www.intel.com/content/www/us/en/download-center/home.html'})"
        Write-Info "Custom Install -> driver only, no overlay / link."
        if (-not $SCRIPT:DryRun -and -not (Test-YoloProfile)) { Read-Host "  After driver installation [Enter]" }
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
            -Improvement "All 52 DWORD settings applied directly to DRS binary database + PerfLevelSrc registry key" `
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
        if (-not $SCRIPT:DryRun -and -not (Test-YoloProfile)) { Read-Host "  [Enter] to continue" }
    }

    # NVIDIA CP hints — always show for NVIDIA
    if ($gpuInput -in @("1","2")) {
        Write-Blank
        Write-Host "  NVIDIA CONTROL PANEL — remaining manual checks:" -ForegroundColor White
        if ($fpsCap -gt 0) {
            Write-Host "  [T1] Max Frame Rate        ->  $fpsCap  (avg $avgFps - 9%)" -ForegroundColor Green
            "$fpsCap" | Set-ClipboardSafe
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
# STEP 7 — VBS / CORE ISOLATION DISABLE  [T2]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 7) {
    Write-Section "Step 7 — VBS / Core Isolation (Memory Integrity)"
    Invoke-TieredStep -Tier 2 -Title "Disable VBS / Core Isolation (Memory Integrity)" `
        -Why "Virtualization-Based Security runs a Type-1 hypervisor below the kernel. On OEM Win11 systems this adds 5-15% CPU scheduling overhead in games. X3D tuning guide: Off." `
        -Evidence "Microsoft VBS docs; Phoronix benchmarks show 5-15% overhead. X3D guide (A18): Off. Multiple community benchmarks confirm FPS impact on CPU-bound titles." `
        -Caveat "SECURITY TRADE-OFF: Disables LSASS credential theft protection. FACEIT Anti-Cheat and Vanguard REQUIRE HVCI — skip this step if using these. Only disable on dedicated gaming PCs." `
        -Risk "MODERATE" -Depth "REGISTRY" -EstimateKey "VBS/Core Isolation Off" `
        -Improvement "Removes 5-15% CPU overhead from hypervisor layer — measurable on OEM Win11" `
        -SideEffects "Reduces credential theft protection (LSASS). May break FACEIT AC / Vanguard." `
        -Undo "Windows Security -> Device Security -> Core Isolation -> Memory Integrity: ON" `
        -Action {
            # Detect current VBS status + check if already pending disable via registry
            $vbsActive = $false
            $hvciPendingOff = $false
            try {
                $dg = Get-CimInstance -ClassName Win32_DeviceGuard `
                    -Namespace root/Microsoft/Windows/DeviceGuard -ErrorAction SilentlyContinue
                if ($dg -and $dg.VirtualizationBasedSecurityStatus -ge 2) {
                    $vbsActive = $true
                }
            } catch { Write-Debug "VBS detection: $_" }
            try {
                $hvciVal = Get-ItemProperty `
                    "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
                    -Name "Enabled" -ErrorAction SilentlyContinue
                if ($hvciVal -and $hvciVal.Enabled -eq 0) { $hvciPendingOff = $true }
            } catch {}

            if (-not $vbsActive) {
                Write-OK "VBS/Core Isolation: not active — no overhead to remove."
                Complete-Step $PHASE 7 "VBS"
                return
            }
            if ($hvciPendingOff) {
                Write-OK "Memory Integrity already set to disable — reboot to take effect."
                Complete-Step $PHASE 7 "VBS"
                return
            }

            Write-Warn "VBS/HVCI is ACTIVE — 5-15% CPU overhead detected."
            Write-Blank

            # FACEIT / Vanguard warning
            Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "  │  WARNING: FACEIT AC and Vanguard REQUIRE HVCI enabled.      │" -ForegroundColor Red
            Write-Host "  │  If you use FACEIT or Valorant, SKIP this step.             │" -ForegroundColor Red
            Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Red
            Write-Blank

            # Disable Memory Integrity (HVCI) via registry
            Set-RegistryValue `
                "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" `
                "Enabled" 0 "DWord" "Disable Memory Integrity (HVCI)"

            if (-not $SCRIPT:DryRun) {
                Write-OK "Memory Integrity (HVCI) disabled. Reboot required for full effect."
                Write-Info "Verify after reboot: msinfo32 -> Virtualization-based security -> 'Not Enabled'"
            }
            Complete-Step $PHASE 7 "VBS"
        } `
        -SkipAction { Skip-Step $PHASE 7 "VBS" }
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
                if (-not $SCRIPT:DryRun -and -not (Test-YoloProfile)) { Read-Host "  [Enter] when done" }
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
            if (Test-YoloProfile) { $dnsChoice = "1" }
            elseif (-not $SCRIPT:DryRun) {
                do { $dnsChoice = Read-Host "  [1/2/3]" } while ($dnsChoice -notin @("1","2","3"))
            } else { $dnsChoice = "3" }

            if ($dnsChoice -ne "3") {
                $dnsAddrs = if ($dnsChoice -eq "1") { $CFG_DNS_Cloudflare } else { $CFG_DNS_Google }
                $dnsName  = if ($dnsChoice -eq "1") { "Cloudflare" } else { "Google" }
                try {
                    # Set DNS on active physical adapters (wired + WiFi) — DNS is protocol-layer,
                    # unlike NIC hardware tweaks which are wired-only.
                    $nics = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
                        $_.Status -eq "Up" -and
                        $_.InterfaceDescription -notmatch $CFG_VirtualAdapterFilter
                    })
                    if ($nics.Count -gt 0) {
                        # Show numbered list so user can identify each adapter
                        Write-Blank
                        Write-Host "  Detected active adapters:" -ForegroundColor White
                        for ($i = 0; $i -lt $nics.Count; $i++) {
                            Write-Host "    [$($i+1)]  $($nics[$i].Name)  ($($nics[$i].InterfaceDescription))" -ForegroundColor Cyan
                        }
                        Write-Blank

                        if ($nics.Count -eq 1) {
                            $confirmDns = if (Test-YoloProfile) { "Y" } elseif (-not $SCRIPT:DryRun) { Read-Host "  Apply $dnsName DNS to this adapter? [Y/n]" } else { "n" }
                            if ($confirmDns -match "^[nN]$") {
                                Write-Info "DNS not changed. Configure manually in Network Settings."
                                Complete-Step $PHASE 9 "DNS"
                                return
                            }
                            $selectedNics = $nics
                        } else {
                            Write-Host "  [A]  Apply to ALL listed adapters" -ForegroundColor White
                            Write-Host "  [S]  Select individual adapters" -ForegroundColor White
                            Write-Host "  [N]  Skip — configure DNS manually" -ForegroundColor DarkGray
                            if (Test-YoloProfile) { $multiChoice = "a" }
                            elseif (-not $SCRIPT:DryRun) {
                                do { $multiChoice = Read-Host "  [A/S/N]" } while ($multiChoice -notmatch "^[aAsSnN]$")
                            } else { $multiChoice = "n" }
                            if ($multiChoice -match "^[nN]$") {
                                Write-Info "DNS not changed. Configure manually in Network Settings."
                                Complete-Step $PHASE 9 "DNS"
                                return
                            }
                            if ($multiChoice -match "^[sS]$") {
                                $selectedNics = @()
                                for ($i = 0; $i -lt $nics.Count; $i++) {
                                    $pick = if (Test-YoloProfile) { "y" } elseif (-not $SCRIPT:DryRun) { Read-Host "  Apply DNS to [$($i+1)] $($nics[$i].Name)? [y/N]" } else { "n" }
                                    if ($pick -match "^[jJyY]$") { $selectedNics += $nics[$i] }
                                }
                                if ($selectedNics.Count -eq 0) {
                                    Write-Info "No adapters selected. DNS not changed."
                                    Complete-Step $PHASE 9 "DNS"
                                    return
                                }
                            } else {
                                $selectedNics = $nics
                            }
                        }

                        foreach ($nic in $selectedNics) {
                            if ($SCRIPT:DryRun) {
                                Write-Host "  [DRY-RUN] Would set DNS to ${dnsName}: $($dnsAddrs -join ', ') (Adapter: $($nic.Name))" -ForegroundColor Magenta
                            } else {
                                # Backup current DNS servers before modification
                                $currentDns = @()
                                try {
                                    $dnsInfo = Get-DnsClientServerAddress -InterfaceIndex $nic.ifIndex `
                                        -AddressFamily IPv4 -ErrorAction SilentlyContinue
                                    if ($dnsInfo -and $dnsInfo.ServerAddresses) {
                                        $currentDns = @($dnsInfo.ServerAddresses)
                                    }
                                } catch { Write-Debug "Could not read current DNS for $($nic.Name)" }
                                Backup-DnsConfig -AdapterName $nic.Name `
                                    -InterfaceIndex $nic.ifIndex `
                                    -OriginalDnsServers $currentDns `
                                    -StepTitle $SCRIPT:CurrentStepTitle
                                Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $dnsAddrs
                                Write-OK "DNS set to ${dnsName}: $($dnsAddrs -join ', ') (Adapter: $($nic.Name))"
                            }
                        }
                    } else {
                        Write-Warn "No active network adapter found after filtering virtual/VPN adapters."
                        Write-Info "Check your network cable or WiFi. DNS can be set manually in Network Settings."
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

. "$ScriptRoot\phase3-steps\step-11-13-tail.ps1"
} catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  FATAL ERROR — Phase 3 crashed unexpectedly                ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host "  Error:      $_" -ForegroundColor Red
    Write-Host "  Location:   $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host "  Line:       $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    if ($_.ScriptStackTrace) {
        Write-Host "  Stack trace:" -ForegroundColor Yellow
        $_.ScriptStackTrace -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    Write-Host ""
    if (-not (Test-YoloProfile)) { Read-Host "  Press [Enter] to exit (error details above)" }
} finally {
    # Release backup lock — acquired by Initialize-Backup at the top of this script.
    # In try/finally to ensure release on crash, Ctrl+C, or normal exit.
    Remove-BackupLock
}
