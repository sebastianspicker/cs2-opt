#Requires -RunAsAdministrator
<# CS2 Optimization Suite — Safe Mode · GPU Driver Clean Removal #>

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\config.env.ps1"
. "$ScriptRoot\helpers.ps1"

$state = Load-State $CFG_StateFile
Initialize-Log
Write-Banner 2 3 "Safe Mode  ·  GPU Driver Clean Removal"
Write-Info "Safe Mode active. GPU driver files are unlocked."

$PHASE = 2

# Validate we're actually in Safe Mode
if (-not $env:SAFEBOOT_OPTION) {
    Write-Warn "WARNING: This script is designed for Safe Mode but normal boot was detected."
    Write-Warn "GPU driver removal in normal mode may cause instability."
    $confirm = Read-Host "  Continue anyway? [y/N]"
    if ($confirm -notmatch "^[jJyY]$") {
        Write-Info "Aborted. Boot into Safe Mode first (START.bat -> [1])."
        exit 0
    }
}

Write-Section "Step 1 — Disable Safe Mode"
bcdedit /deletevalue safeboot 2>$null | Out-Null
Write-OK "Safe Mode disabled (next boot = normal)."
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
$r2 = Read-Host "  Restart now? [Y/n]"
if ($r2 -notmatch "^[nN]$") { Restart-Computer -Force }
