# ==============================================================================
#  tests/helpers/_TestInit.ps1  --  Common test setup for Pester 5.x tests
# ==============================================================================
#
#  Dot-source this file in BeforeAll {} blocks to get:
#    - All helper modules loaded (without side-effects)
#    - $SCRIPT:DryRun / $SCRIPT:Profile / $SCRIPT:Mode set to safe defaults
#    - $CFG_* variables from config.env.ps1 loaded
#    - Helper functions for creating temp JSON fixtures
#
#  Usage in a .Tests.ps1 file:
#    BeforeAll { . "$PSScriptRoot/_TestInit.ps1" }

# ── Resolve paths ─────────────────────────────────────────────────────────────
$_testInitRoot = $PSScriptRoot
$_projectRoot  = (Resolve-Path "$_testInitRoot/../..").Path

# ── Load config.env.ps1 (provides all $CFG_* variables) ──────────────────────
# Must load before helpers since some helpers reference $CFG_* at parse time.
. "$_projectRoot/config.env.ps1"

# ── Override $CFG_* paths to use temp directories (no admin / no real paths) ──
# Save originals so tests can inspect them if needed.
$SCRIPT:_OriginalCfgWorkDir      = $CFG_WorkDir
$SCRIPT:_OriginalCfgStateFile    = $CFG_StateFile
$SCRIPT:_OriginalCfgProgressFile = $CFG_ProgressFile

# Create a per-run temp directory for all test artifacts
$SCRIPT:TestTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "cs2opt-tests-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $SCRIPT:TestTempRoot -Force | Out-Null

# Redirect all working paths to temp
$CFG_WorkDir        = $SCRIPT:TestTempRoot
$CFG_LogDir         = Join-Path $SCRIPT:TestTempRoot "Logs"
$CFG_LogFile        = Join-Path $CFG_LogDir "test.log"
$CFG_StateFile      = Join-Path $SCRIPT:TestTempRoot "state.json"
$CFG_ProgressFile   = Join-Path $SCRIPT:TestTempRoot "progress.json"
$CFG_BackupFile     = Join-Path $SCRIPT:TestTempRoot "backup.json"
$CFG_BackupLockFile = Join-Path $SCRIPT:TestTempRoot "backup.lock"
$CFG_BenchmarkFile  = Join-Path $SCRIPT:TestTempRoot "benchmark_history.json"

# Ensure log directory exists (logging.ps1 functions reference it)
New-Item -ItemType Directory -Path $CFG_LogDir -Force | Out-Null

# ── Set safe script-scope defaults ────────────────────────────────────────────
$SCRIPT:DryRun   = $false
$SCRIPT:Profile  = "RECOMMENDED"
$SCRIPT:Mode     = "CONTROL"
$SCRIPT:LogLevel = "MINIMAL"
$SCRIPT:CurrentStepTitle = $null

# ── Cross-platform stubs for Windows-only cmdlets ───────────────────────────
# On macOS/Linux, cmdlets like Get-CimInstance, Get-Service, Get-ScheduledTask
# do not exist. Define no-op stubs so that Pester Mock can intercept them.
# These stubs are intentionally minimal — tests MUST mock them with real return values.
if ((Get-Variable IsWindows -Scope Global -ErrorAction SilentlyContinue) -and $IsWindows -eq $false) {
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance { param($ClassName, $Filter) $null }
    }
    if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
        function global:Get-Service { param($Name) $null }
    }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        function global:Get-ScheduledTask { param($TaskName) $null }
    }
    if (-not (Get-Command Enable-ScheduledTask -ErrorAction SilentlyContinue)) {
        function global:Enable-ScheduledTask { param($TaskName) $null }
    }
    if (-not (Get-Command Disable-ScheduledTask -ErrorAction SilentlyContinue)) {
        function global:Disable-ScheduledTask { param($TaskName) $null }
    }
    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        function global:Unregister-ScheduledTask { param($TaskName, [switch]$ConfirmAction) $null }
    }
    if (-not (Get-Command Set-Service -ErrorAction SilentlyContinue)) {
        function global:Set-Service { param($Name, $StartupType) $null }
    }
    if (-not (Get-Command Start-Service -ErrorAction SilentlyContinue)) {
        function global:Start-Service { param($Name) $null }
    }

    # On macOS/Linux, Set-ItemProperty does not have the -Type parameter
    # (it's a Windows registry provider feature). Wrap it so Pester can mock calls
    # that pass -Type without a parameter validation error.
    $originalSetItemProperty = Get-Command Set-ItemProperty -CommandType Cmdlet -ErrorAction SilentlyContinue
    if ($originalSetItemProperty -and -not $originalSetItemProperty.Parameters.ContainsKey('Type')) {
        function global:Set-ItemProperty {
            param($Path, $Name, $Value, $Type, $ErrorAction)
            # No-op on non-Windows — tests will mock this
        }
    }
    # Same for Remove-ItemProperty with -ErrorAction
    $originalRemoveItemProperty = Get-Command Remove-ItemProperty -CommandType Cmdlet -ErrorAction SilentlyContinue
    if (-not $originalRemoveItemProperty) {
        function global:Remove-ItemProperty {
            param($Path, $Name, $ErrorAction)
        }
    }
    # Same for New-Item if needed
    $originalNewItem = Get-Command New-Item -CommandType Cmdlet -ErrorAction SilentlyContinue
    if ($originalNewItem -and -not $originalNewItem.Parameters.ContainsKey('Force')) {
        # New-Item should exist everywhere, no wrapping needed
    }
}

# ── Load all helper modules ──────────────────────────────────────────────────
# Load in the same order as helpers.ps1 to match production behavior.
$_helpersDir = "$_projectRoot/helpers"
. "$_helpersDir/logging.ps1"
. "$_helpersDir/tier-system.ps1"
. "$_helpersDir/step-state.ps1"
. "$_helpersDir/system-utils.ps1"
. "$_helpersDir/hardware-detect.ps1"
. "$_helpersDir/backup-restore.ps1"
# Note: debloat, msi-interrupts, gpu-driver-clean, nvidia-driver, nvidia-drs,
# nvidia-profile, benchmark-history, power-plan, process-priority are NOT loaded
# here because they have heavy external dependencies (nvapi64.dll, bcdedit, etc.)
# Tests that need them should load them explicitly with appropriate mocks.

# ── Helper: Create temp state.json ───────────────────────────────────────────
function New-TestStateFile {
    <#  Creates a minimal state.json in the test temp directory.
        Returns the file path.  #>
    param(
        [string]$TestProfile  = "RECOMMENDED",
        [string]$Mode         = "CONTROL",
        [string]$LogLevel = "NORMAL",
        [string[]]$AppliedSteps = @()
    )
    $state = [PSCustomObject]@{
        profile      = $TestProfile
        mode         = $Mode
        logLevel     = $LogLevel
        appliedSteps = $AppliedSteps
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content $CFG_StateFile -Encoding UTF8
    return $CFG_StateFile
}

# ── Helper: Create temp progress.json ────────────────────────────────────────
function New-TestProgressFile {
    <#  Creates a minimal progress.json in the test temp directory.
        Returns the file path.  #>
    param(
        [int]$Phase = 1,
        [int]$LastStep = 0,
        [string[]]$CompletedSteps = @(),
        [string[]]$SkippedSteps = @()
    )
    $prog = [PSCustomObject]@{
        phase             = $Phase
        lastCompletedStep = $LastStep
        completedSteps    = $CompletedSteps
        skippedSteps      = $SkippedSteps
        timestamps        = @{}
    }
    $prog | ConvertTo-Json -Depth 5 | Set-Content $CFG_ProgressFile -Encoding UTF8
    return $CFG_ProgressFile
}

# ── Helper: Create temp backup.json ──────────────────────────────────────────
function New-TestBackupFile {
    <#  Creates a minimal backup.json in the test temp directory.
        Returns the file path.  #>
    param(
        [array]$Entries = @()
    )
    $backup = [PSCustomObject]@{
        entries = $Entries
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $backup | ConvertTo-Json -Depth 10 | Set-Content $CFG_BackupFile -Encoding UTF8
    return $CFG_BackupFile
}

# ── Helper: Reset script state between tests ─────────────────────────────────
function Reset-TestState {
    <#  Resets script-scope variables and cleans test temp files.
        Call in BeforeEach blocks for isolation between tests.  #>
    $SCRIPT:DryRun   = $false
    $SCRIPT:Profile  = "RECOMMENDED"
    $SCRIPT:Mode     = "CONTROL"
    $SCRIPT:LogLevel = "MINIMAL"
    $SCRIPT:CurrentStepTitle = $null
    $SCRIPT:AppliedSteps = [System.Collections.Generic.List[string]]::new()
    $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

    # Remove test JSON files so each test starts clean
    Remove-Item $CFG_StateFile    -Force -ErrorAction SilentlyContinue
    Remove-Item $CFG_ProgressFile -Force -ErrorAction SilentlyContinue
    Remove-Item $CFG_BackupFile   -Force -ErrorAction SilentlyContinue
    Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
}

# ── Cleanup hook ──────────────────────────────────────────────────────────────
# Register cleanup to run when the test session ends.
# Note: Pester 5.x AfterAll in the consuming test file handles per-file cleanup.
# This global cleanup catches anything left behind.
if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -MessageData $SCRIPT:TestTempRoot -Action {
        if (Test-Path $Event.MessageData) {
            Remove-Item $Event.MessageData -Recurse -Force -ErrorAction SilentlyContinue
        }
    } -SupportEvent | Out-Null
}
