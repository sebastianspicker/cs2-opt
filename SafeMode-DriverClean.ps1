#Requires -RunAsAdministrator
<# CS2 Optimization Suite — Safe Mode · GPU Driver Clean Removal

    CRASH RECOVERY SCENARIOS — this script is safety-critical.

    Steps execute in order: (1) bcdedit /deletevalue safeboot, (2) driver removal, (3) RunOnce.
    Step 1 is done FIRST so that a crash at any later point still boots into Normal Mode.

    Crash during Step 1 (bcdedit /deletevalue):
        bcdedit is atomic — either the BCD write completes or it doesn't.
        - If completed:  next boot = Normal Mode. Safe to re-run this script.
        - If not completed (power loss mid-write): next boot = Safe Mode. The script
          re-runs via RunOnce and retries Step 1. If BCD is corrupt, user sees manual
          fix instructions: "bcdedit /deletevalue safeboot" from elevated cmd.exe.

    Crash during Step 2 (driver removal):
        Step 1 already completed, so next boot = Normal Mode.
        - Partial driver removal: Windows auto-detects missing display driver and loads
          Microsoft Basic Display Adapter (MSBDA). Resolution limited to 1024x768 but
          the system is usable. User can install GPU driver normally.
        - The RunOnce for Phase 3 was NOT yet registered (Step 3), so Phase 3 won't
          auto-start. User runs PostReboot-Setup.ps1 manually from START.bat.

    Crash during Step 3 (RunOnce registration):
        Steps 1+2 completed. Next boot = Normal Mode, GPU driver removed.
        - Phase 3 won't auto-start. User runs PostReboot-Setup.ps1 from START.bat -> [3].
        - This is the lowest-risk crash point — system boots fine, just needs manual Phase 3.

    Power failure during Restart-Computer:
        All steps completed. System reboots normally. RunOnce fires Phase 3.
        - This is equivalent to a normal power cycle — no data loss risk.
#>

$ErrorActionPreference = "SilentlyContinue"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\config.env.ps1"
. "$ScriptRoot\helpers.ps1"

try {
    $state = Load-State $CFG_StateFile
} catch {
    Write-Host "  ERROR: state.json missing or corrupted: $_" -ForegroundColor Red
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  MANUAL SAFE MODE EXIT (run in elevated cmd.exe if needed):" -ForegroundColor Yellow
    Write-Host "    bcdedit /deletevalue safeboot" -ForegroundColor White
    Write-Host "    shutdown /r /t 0" -ForegroundColor White
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  To continue anyway with defaults, press [Y]." -ForegroundColor Yellow
    $r = Read-Host "  Continue with defaults? [y/N]"
    if ($r -notmatch "^[jJyY]$") { exit 1 }
    $state = [PSCustomObject]@{ gpuInput="2"; mode="CONTROL"; profile="RECOMMENDED"; rollbackDriver=$null; nvidiaDriverPath=$null }
    $SCRIPT:Mode = "CONTROL"; $SCRIPT:LogLevel = "NORMAL"; $SCRIPT:Profile = "RECOMMENDED"; $SCRIPT:DryRun = $false
}
Initialize-Log
Initialize-Backup
Write-Banner 2 3 "Safe Mode  ·  GPU Driver Clean Removal"
Write-Info "Safe Mode active. GPU driver files are unlocked."

$PHASE = 2

try {
    # Validate we're actually in Safe Mode
    # $env:SAFEBOOT_OPTION is set by winload.exe on Safe Mode boot ("MINIMAL" or "NETWORK").
    # Reliable on all Windows 10/11 editions. If absent, we're in normal boot.
    if (-not $env:SAFEBOOT_OPTION) {
        Write-Warn "WARNING: This script is designed for Safe Mode but normal boot was detected."
        Write-Warn "GPU driver removal in normal mode may fail — driver files may be locked by"
        Write-Warn "running services (NVDisplay, AMD External Events, etc.)."
        Write-Warn "Partially removed drivers can cause black screen or BSOD on next boot."
        $confirm = Read-Host "  Continue anyway? [y/N]"
        if ($confirm -notmatch "^[jJyY]$") {
            Write-Info "Aborted. Boot into Safe Mode first (START.bat -> [1])."
            exit 0
        }
    }

    Write-Section "Step 1 — Disable Safe Mode"
    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would run: bcdedit /deletevalue safeboot" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN] CRITICAL: In a real run this removes Safe Mode boot flag" -ForegroundColor Magenta
    } else {
        $smOutput = bcdedit /deletevalue safeboot 2>&1
        if ($LASTEXITCODE -ne 0) {
            # bcdedit returns non-zero if the value doesn't exist — this is expected on re-run
            # (safeboot was already cleared by a previous execution) or if not in Safe Mode.
            # NOTE: bcdedit error text is LOCALIZED ("element not found" in English, but different
            # on German/French/etc Windows). Instead of parsing the error message, we verify the
            # actual BCD state using bcdedit /enum /v, which outputs RAW BCD element IDs
            # (e.g., "0x26000081") instead of human-readable names. Element names like "safeboot"
            # ARE localized (e.g., German: "Abgesicherter Start"), but the /v flag outputs the
            # numeric ID which is always "0x26000081" regardless of locale.
            $bcdEnum = bcdedit /enum "{current}" /v 2>&1
            $bcdEnumExitCode = $LASTEXITCODE
            $bcdEnumText = ($bcdEnum | Out-String)
            if ($bcdEnumExitCode -ne 0) {
                # bcdedit /enum itself failed — possible BCD corruption or permissions issue.
                # Cannot determine Safe Mode state; treat as critical and ask user.
                Write-Err "CRITICAL: bcdedit /enum failed (exit $bcdEnumExitCode). Cannot verify Safe Mode state."
                Write-Err "BCD may be corrupted or permissions insufficient."
                Write-Err ""
                Write-Err "MANUAL FIX (run in elevated cmd.exe):"
                Write-Err "  bcdedit /deletevalue safeboot"
                Write-Err "  shutdown /r /t 0"
                $smConfirm = Read-Host "  Continue anyway? [y/N]"
                if ($smConfirm -notmatch "^[jJyY]$") { exit 1 }
            } else {
                # BCD element 0x26000081 = BcdOSLoaderInteger_SafeBoot (safeboot type).
                # With /v, this appears as the raw hex ID, never localized.
                $safebootStillSet = $bcdEnumText -match "(?m)^\s*0x26000081\s"
                if (-not $safebootStillSet) {
                    Write-OK "Safe Mode already disabled (safeboot element not present). OK to continue."
                } else {
                    Write-Err "CRITICAL: Failed to disable Safe Mode (exit $LASTEXITCODE): $smOutput"
                    Write-Err "System will boot into Safe Mode again on next restart!"
                    Write-Err ""
                    Write-Err "MANUAL FIX (run in elevated cmd.exe):"
                    Write-Err "  bcdedit /deletevalue safeboot"
                    Write-Err "  shutdown /r /t 0"
                    $smConfirm = Read-Host "  Continue anyway? [y/N]"
                    if ($smConfirm -notmatch "^[jJyY]$") { exit 1 }
                }
            }
        } else {
            Write-OK "Safe Mode disabled (next boot = normal)."
        }
    }
    Complete-Step $PHASE 1 "SafeMode off"

    Write-Section "Step 2 — GPU Driver Clean Removal"
    $gpuName = switch ($state.gpuInput) {
        "1" {"NVIDIA"} "2" {"NVIDIA"} "3" {"AMD"} "4" {"Intel"} default {"NVIDIA"}
    }

    Write-Info "Detected GPU vendor: $gpuName"
    Write-Info "This performs a complete driver removal using native PowerShell."
    Write-Info "Equivalent to DDU — stops services, removes drivers, cleans registry."

    # Check if rollback was requested
    if ($state.rollbackDriver) {
        Write-Blank
        $drvLabel = $state.rollbackDriver
        $pad = [math]::Max(0, 30 - $drvLabel.Length)
        Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "  ║  ROLLBACK REQUESTED: Driver $drvLabel$((' ' * $pad))║" -ForegroundColor Yellow
        Write-Host "  ║  Make sure you have downloaded this driver version       ║" -ForegroundColor Yellow
        Write-Host "  ║  BEFORE proceeding. It will be installed in Phase 3.    ║" -ForegroundColor Yellow
        Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    }

    Write-Blank
    $r = Read-Host "  Proceed with GPU driver removal? [Y/n]"
    if ($r -match "^[nN]$") {
        Write-Warn "Skipped GPU driver removal."
        Skip-Step $PHASE 2 "DriverClean"

        # Ask whether to still proceed with Phase 3
        Write-Blank
        $rPhase3 = Read-Host "  Still register Phase 3 for next boot? [y/N]"
        if ($rPhase3 -match "^[jJyY]$") {
            Write-Section "Step 3 — Register Phase 3 for next boot"
            Set-RunOnce "CS2_Phase3" "$CFG_WorkDir\PostReboot-Setup.ps1"
            Complete-Step $PHASE 3 "RunOnce Phase3"
        } else {
            Write-Info "Phase 3 not registered. Re-run from START.bat when ready."
            Skip-Step $PHASE 3 "RunOnce Phase3"
        }
    } else {
        Remove-GpuDriverClean -GpuVendor $gpuName
        Complete-Step $PHASE 2 "DriverClean"

        # Register Phase 3 RunOnce AFTER driver removal
        Write-Section "Step 3 — Register Phase 3 for next boot"
        Set-RunOnce "CS2_Phase3" "$CFG_WorkDir\PostReboot-Setup.ps1"
        Complete-Step $PHASE 3 "RunOnce Phase3"
    }

    Write-Blank
    Write-Info "Restart to continue."
    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would prompt for restart" -ForegroundColor Magenta
    } else {
        $r2 = Read-Host "  Restart now? [Y/n]"
        if ($r2 -notmatch "^[nN]$") { Restart-Computer -Force }
    }
} catch {
    # Unhandled exception — display recovery instructions so user isn't stuck.
    Write-Host "" -ForegroundColor Red
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  UNEXPECTED ERROR DURING SAFE MODE SCRIPT               ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  RECOVERY:" -ForegroundColor Yellow
    Write-Host "  Step 1 (bcdedit) runs first. If it completed, next boot = Normal Mode." -ForegroundColor White
    Write-Host "  If you're stuck in Safe Mode, run in elevated cmd.exe:" -ForegroundColor White
    Write-Host "    bcdedit /deletevalue safeboot" -ForegroundColor Cyan
    Write-Host "    shutdown /r /t 0" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor White
    Write-Host "  If GPU driver was partially removed, Windows will load Basic Display" -ForegroundColor White
    Write-Host "  Adapter on next boot. Install your GPU driver manually or re-run" -ForegroundColor White
    Write-Host "  the suite from START.bat." -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Read-Host "  Press Enter to exit"
} finally {
    # Release backup lock — acquired by Initialize-Backup at the top of this script.
    # In try/finally to ensure release on crash, Ctrl+C, or normal exit.
    Remove-BackupLock
}
