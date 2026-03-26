# ==============================================================================
#  Setup-Profile.ps1  —  Step 1: Profile, Configuration, Resume
# ==============================================================================

# ── STEP 1 — PROFILE + CONFIGURATION ─────────────────────────────────────────
Write-LogoBanner "CS2 Optimization Suite  ·  Phase 1 / 3"

Write-Host @"

  DISCLAIMER: This suite provides optimization suggestions based on
  community research and benchmarks. We take NO RESPONSIBILITY for any
  damage whatsoever. Use entirely at your own risk.
  All changes are backed up automatically and can be rolled back.

"@ -ForegroundColor DarkRed

Write-Host "  HOW SHOULD THE SUITE OPERATE?" -ForegroundColor White
Write-Host @"

  ┌──────────────────────────────────────────────────────────────────
  │
  │  [1]  SAFE — Auto-apply safe tweaks only
  │       Applies all proven, universally harmless optimizations
  │       automatically. No prompts, no risky changes.
  │       Skips: driver changes, boot config, service tweaks.
  │
  │       Includes:
  │       $([char]0x2714) Shader cache clear, fullscreen optimization, power plan
  │       $([char]0x2714) Mouse acceleration off, Game DVR off, overlays off
  │       $([char]0x2714) Autoexec.cfg, GPU preference, timer resolution
  │       $([char]0x2714) Dual-channel RAM check, XMP/EXPO check, benchmarks
  │       $([char]0x2718) Driver rollback, debloat, NIC tweaks, boot config
  │
  │       Best for: First-time users, work PCs, laptops
  │
  │  [2]  RECOMMENDED — Ask before moderate changes
  │       Safe tweaks auto-applied. Moderate tweaks explained and
  │       prompted — you decide each one with full context.
  │       Skips: community tips (T3), aggressive changes.
  │
  │       Includes everything in SAFE, plus (prompted):
  │       $([char]0x25B2) HAGS, pagefile, debloat, NIC tweaks, MSI interrupts
  │       $([char]0x2718) Boot config, driver rollback, service disabling
  │
  │       Best for: Most desktop gamers  (recommended)
  │
  │  [3]  COMPETITIVE — Maximum performance
  │       Every optimization offered including community tips.
  │       Each step prompted with risk assessment.
  │       Only skips changes with security implications.
  │
  │       Includes everything in RECOMMENDED, plus (prompted):
  │       $([char]0x25C6) Timer tweaks (bcdedit), Game Mode, visual effects
  │       $([char]0x25C6) SysMain/Search disable, NIC affinity, NVIDIA profile
  │       $([char]0x25C6) Driver rollback (if applicable)
  │       $([char]0x2718) Windows Update disable (security risk)
  │
  │       Best for: Experienced users, tournament prep
  │
  │  [4]  CUSTOM — Full control (expert)
  │       Every single step shown with full detail card:
  │       risk level, expected improvement, side effects, undo.
  │       Nothing is automatic — you decide everything.
  │
  │       Best for: Users who want complete informed control
  │
  │  [D]  DRY-RUN — Preview only
  │       Shows what any profile would change without modifying
  │       anything. Perfect for reviewing before committing.
  │       Select a profile afterwards to define scope.
  │
  └──────────────────────────────────────────────────────────────────
"@ -ForegroundColor White

do { $pi = Read-Host "  Profile [1/2/3/4/D]" } while ($pi -notin @("1","2","3","4","d","D"))
$SCRIPT:DryRun = ($pi -in @("d","D"))

if ($SCRIPT:DryRun) {
    Write-Host "`n  DRY-RUN: Which profile scope to preview?" -ForegroundColor Magenta
    Write-Host "  [1] SAFE  [2] RECOMMENDED  [3] COMPETITIVE  [4] CUSTOM" -ForegroundColor DarkGray
    do { $pi = Read-Host "  [1/2/3/4]" } while ($pi -notin @("1","2","3","4"))
}

$SCRIPT:Profile = switch ($pi) { "1" {"SAFE"} "2" {"RECOMMENDED"} "3" {"COMPETITIVE"} "4" {"CUSTOM"} }
# Mode is derived from profile (kept for backward-compat with Load-State / banner)
$SCRIPT:Mode = switch ($SCRIPT:Profile) {
    "SAFE"        { "AUTO" }
    "RECOMMENDED" { "AUTO" }
    "COMPETITIVE" { "CONTROL" }
    "CUSTOM"      { "INFORMED" }
}
if ($SCRIPT:DryRun) { $SCRIPT:Mode = "DRY-RUN" }

# Log level — simplified for profiles
if ($SCRIPT:Profile -eq "CUSTOM") {
    Write-Host @"

  LOG LEVEL:
  [1]  MINIMAL   Errors, warnings and successes only
  [2]  NORMAL    Standard  (recommended)
  [3]  VERBOSE   Everything incl. registry values and download details
"@ -ForegroundColor White
    do { $li = Read-Host "  [1/2/3]" } while ($li -notin @("1","2","3"))
    $SCRIPT:LogLevel = switch ($li) { "1" {"MINIMAL"} "2" {"NORMAL"} "3" {"VERBOSE"} }
} else {
    $SCRIPT:LogLevel = "NORMAL"
}

Initialize-Log
Write-Banner 1 3 "Optimization · Downloads · Safe Mode"

$startStep = Show-ResumePrompt $PHASE $TOTAL_STEPS
if ($startStep -gt $TOTAL_STEPS) { Write-Info "Phase 1 already completed."; exit 0 }

# Initialize backup system
Initialize-Backup

# Detect and warn about compatibility limitations (ARM64, CLM, Server, PS7)
Test-SystemCompatibility

# Restore Point
if ($startStep -eq 1) {
    Write-Blank
    if ($SCRIPT:Profile -eq "SAFE") {
        Write-Info "SAFE profile: only harmless, reversible changes will be applied."
        Write-Info "All changes are backed up automatically and can be rolled back."
    } else {
        Write-Warn "Create a System Restore Point NOW!"
        Write-Info "Windows Search -> 'restore point' -> C: -> Create"
        Write-Info "Additionally, this suite backs up every changed setting automatically."
        Write-Info "You can rollback individual steps via START.bat -> Restore."
        if (-not (Confirm-Risk "Restore point created. Continue?" "No rollback possible without a restore point!")) {
            exit 0
        }
    }
}

# Load or create state
$state = $null
if (Test-Path $CFG_StateFile) {
    try {
        $state = Get-Content $CFG_StateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warn "Previous state file could not be read (corrupt or empty). Starting fresh."
        $state = $null
    }
}

if (-not $state -or $startStep -eq 1) {
    Write-Section "Step 1 — Configuration"

    Write-Host "`n  GPU:" -ForegroundColor White
    Write-Host "  [1] NVIDIA RTX 5000  [2] NVIDIA RTX 4000/older  [3] AMD  [4] Intel Arc"
    do { $gpuInput = Read-Host "  [1/2/3/4]" } while ($gpuInput -notin @("1","2","3","4"))

    Write-Blank
    Write-Host "  AVG FPS IN CS2  (0 = calculate later with FpsCap-Calculator):" -ForegroundColor White
    do {
        $f = Read-Host "  Avg FPS"; $avgFps = 0
        $ok2 = [int]::TryParse($f,[ref]$avgFps) -and $avgFps -ge 0
        if (-not $ok2) { Write-Warn "Enter >= 0." }
    } while (-not $ok2)
    $fpsCap = if ($avgFps -gt 0) { Calculate-FpsCap $avgFps } else { 0 }

    $state = @{
        mode = $SCRIPT:Mode; logLevel = $SCRIPT:LogLevel
        profile = $SCRIPT:Profile
        fpsCap = $fpsCap; avgFps = $avgFps
        gpuInput = $gpuInput; pagefileMB = 0
        workDir = $CFG_WorkDir; scriptRoot = $ScriptRoot
    }
    Save-State $state $CFG_StateFile
    Complete-Step $PHASE 1 "Configuration"
} else {
    # Restore saved config but honor the fresh profile/DRY-RUN choice made above
    $SCRIPT:LogLevel = if ($state.logLevel) { $state.logLevel } else { "NORMAL" }
    if ($SCRIPT:Profile -ne "CUSTOM") { $SCRIPT:LogLevel = "NORMAL" }
    # Profile and Mode were already set from user input at lines 86-103 — keep them
    # Only fall back to state values if user chose the same profile
    $fpsCap  = $state.fpsCap
    $avgFps    = $state.avgFps;   $gpuInput = $state.gpuInput
    # Update state file with the fresh profile choice
    $state.mode     = $SCRIPT:Mode
    $state.profile  = $SCRIPT:Profile
    Save-State $state $CFG_StateFile
    Write-Info "Configuration loaded from previous session (Profile: $($SCRIPT:Profile)$(if($SCRIPT:DryRun){' [DRY-RUN]'}))."
}
