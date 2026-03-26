#Requires -RunAsAdministrator
<#
.SYNOPSIS  CS2 Optimization Suite — Full Optimization Run (38 steps)

  MINIMUM REQUIREMENTS:
    - Windows 10 (1903+) or Windows 11 (any build) — x64 desktop edition
    - PowerShell 5.1 (shipped with Windows 10/11; PS 7 has partial WMI gaps)
    - Administrator privileges (enforced by #Requires above)

  KNOWN LIMITATIONS:
    - ARM64 Windows: NVIDIA DRS writes are unavailable (nvapi64.dll is x64-only).
      Falls back to registry-only NVIDIA profile method automatically.
    - Windows Server / LTSC: AppX debloat is skipped (cmdlets unavailable).
      Xbox services may not exist. All handled gracefully.
    - Constrained Language Mode (AppLocker/WDAC): DRS writes and RAM trim
      are skipped (Add-Type is blocked). Registry-only paths are used instead.
    - PowerShell 7: Pagefile step uses Get-WmiObject (removed in PS 7).
      Use Windows PowerShell 5.1 for full functionality.
    - Non-English Windows: GPU driver clean uses CIM (locale-independent).
      pnputil text-parsing fallback only works on English installations.

  TIER SYSTEM:
    T1  Proven measurable effect -> always runs automatically
    T2  Setup-dependent -> always prompted (even AUTO mode)
    T3  Community tip without hard benchmark -> CONTROL mode only

  Steps:
    1   Mode + log level + configuration
    2   XMP/EXPO check  [T1]
    3   Shader cache clear  [T1]
    4   Fullscreen optimizations disable  [T1]
    5   NVIDIA driver version check  [T2]
    6   CS2 Optimized Power Plan (native powercfg)  [T1]
    7   HAGS configure  [T2]
    8   Pagefile fix  [T2]
    9   Resizable BAR check  [T2 AMD]
    10  Dynamic tick + platform timer  [T3]
    11  MPO disable  [T3]
    12  Windows Game Mode (enable)  [T3]
    13  Gaming Debloat (native PowerShell)  [Hygiene]
    14  Autostart cleanup  [Hygiene]
    15  Windows Update Blocker (native services)  [Optional]
    16  NIC tweaks  [T2]
    17  CapFrameX + Baseline Benchmark  [T1]
    18  GPU driver clean prep  [T1]
    19  NVIDIA driver download  [T1]
    20  NVIDIA profile prep  [T3]
    21  MSI interrupts prep  [T2]
    22  NIC interrupt affinity prep  [T3]
    23  Disable Fast Startup (HiberbootEnabled=0)  [T2]
    24  Dual-channel RAM detection  [T1]
    25  Nagle's Algorithm disable  [T2]
    26  GameConfigStore FSE registry  [T2]
    27  SystemResponsiveness + priority + NetworkThrottlingIndex + DisablePagingExecutive  [T2]
    28  Timer resolution  [T2]
    29  Mouse acceleration disable  [T2]
    30  CS2 GPU preference  [T2]
    31  Xbox Game Bar / Game DVR disable  [T2]
    32  Overlay disable  [T2]
    33  Audio optimization  [T2]
    34  Autoexec.cfg generator  [T2]
    35  Chipset driver check  [T2]
    36  Visual effects best performance  [T3]
    37  SysMain + Windows Search disable  [T3]
    38  Safe Mode -> restart
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\config.env.ps1"
. "$ScriptRoot\helpers.ps1"

Ensure-Dir $CFG_WorkDir
Ensure-Dir $CFG_LogDir

$TOTAL_STEPS = 38
$SCRIPT:PhaseTotal = $TOTAL_STEPS
$PHASE = 1

try {
    Initialize-PhaseCounters
    . "$ScriptRoot\Setup-Profile.ps1"
    . "$ScriptRoot\Optimize-SystemBase.ps1"
    . "$ScriptRoot\Optimize-Hardware.ps1"
    . "$ScriptRoot\Optimize-RegistryTweaks.ps1"
    . "$ScriptRoot\Optimize-GameConfig.ps1"

    # ── Phase 1 complete ─────────────────────────────────────────────────────────
    # Persist applied step keys so Phase 3 improvement estimates are cumulative
    Save-AppliedSteps
    if ($SCRIPT:DryRun) {
        Write-PhaseSummary -PhaseLabel "PHASE 1" -DryRun
    } else {
        $nextAction = "-> Restart -> Safe Mode -> GPU driver clean`n-> Normal boot -> Phase 3 starts automatically"
        Write-PhaseSummary -PhaseLabel "PHASE 1" -NextAction $nextAction

        if (Confirm-Risk "Restart now?" "Save all files!") {
            Start-Sleep 5; Restart-Computer -Force
        }
    }
} finally {
    # Release backup lock — acquired by Initialize-Backup in Setup-Profile.ps1.
    # In try/finally to ensure release on crash, Ctrl+C, or normal exit.
    # On Restart-Computer, the lock file becomes stale (process dead) and is
    # auto-cleaned by Test-BackupLock on next boot.
    Remove-BackupLock
}
