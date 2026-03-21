#Requires -RunAsAdministrator
<#
.SYNOPSIS  CS2 Optimization Suite — Settings Verifier (Read-Only)

  Checks all registry keys, boot config and service states set by the suite.
  Useful after Windows Updates that reset settings.

  Color-coded:
    ✓  OK       (Green)  — Value matches
    ✗  CHANGED  (Yellow) — Value was modified
    ?  MISSING  (Red)    — Key doesn't exist
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptRoot\config.env.ps1"
. "$ScriptRoot\helpers.ps1"

Initialize-ScriptDefaults
Write-LogoBanner "Settings Verifier  ·  Read-Only Scan"
Write-Host "  Checks whether Windows Updates have reset your optimizations." -ForegroundColor DarkGray
Write-Host "  $("─" * 60)" -ForegroundColor DarkGray
Write-Blank

# ── Counters ──────────────────────────────────────────────────────────────────
Initialize-VerifyCounters

# ══════════════════════════════════════════════════════════════════════════════
# REGISTRY CHECKS
# ══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ═══ FULLSCREEN / GAME STORE ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1 "FSE Windows Compatible"
Test-RegistryCheck "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior" 2 "FSE Behavior"
Test-RegistryCheck "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2 "FSE Behavior Mode"
Test-RegistryCheck "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1 "Honor User FSE Mode"

Write-Host "`n  ═══ GAME BAR / DVR / GAME MODE ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 "App Capture"
Test-RegistryCheck "HKCU:\SOFTWARE\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0 "Game Bar Nexus"
Test-RegistryCheck "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0 "Game DVR Policy"
Test-RegistryCheck "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 "Game DVR master switch"
Test-RegistryCheck "HKCU:\SOFTWARE\Microsoft\GameBar" "AllowAutoGameMode" 1 "Auto Game Mode (enabled)"
Test-RegistryCheck "HKCU:\SOFTWARE\Microsoft\GameBar" "AutoGameModeEnabled" 1 "Game Mode (enabled)"

Write-Host "`n  ═══ GPU / DISPLAY ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" 5 "MPO disabled"
# HAGS is setup-dependent (0 or 2), just show current value
try {
    $hagsVal = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction Stop).HwSchMode
    $hagsLabel = switch ($hagsVal) { 0 {"OFF"} 2 {"ON"} default {"Unknown ($hagsVal)"} }
    Write-Host "  ✓  INFO      HAGS = $hagsLabel  (setup-dependent, no target value)" -ForegroundColor Cyan
    $global:_verifyOkCount++
} catch {
    Write-Host "  ?  MISSING   HAGS key not found" -ForegroundColor DarkGray
}

# NVIDIA GPU class registry keys — PerfLevelSrc + DisableDynamicPstate (P-state locks)
# Only checked if an NVIDIA GPU is detected in the device class registry
$_nvClassPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$CFG_GUID_Display"
$_nvKeyPath = $null
if (Test-Path $_nvClassPath) {
    $_nvSubkeys = Get-ChildItem $_nvClassPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match "^\d{4}$" }
    foreach ($_nvKey in $_nvSubkeys) {
        $_nvProps = Get-ItemProperty $_nvKey.PSPath -ErrorAction SilentlyContinue
        if ($_nvProps.ProviderName -match "NVIDIA" -or $_nvProps.DriverDesc -match "NVIDIA") {
            $_nvKeyPath = $_nvKey.PSPath
            break
        }
    }
}
if ($_nvKeyPath) {
    Test-RegistryCheck $_nvKeyPath "PerfLevelSrc" 0x2222 "NVIDIA PerfLevelSrc (P-state: Max Performance)"
    Test-RegistryCheck $_nvKeyPath "DisableDynamicPstate" 1 "NVIDIA DisableDynamicPstate (lock P0)"
} else {
    Write-Host "  ✓  INFO      NVIDIA GPU class key: N/A (no NVIDIA GPU detected)" -ForegroundColor Cyan
    $global:_verifyOkCount++
}

Write-Host "`n  ═══ SYSTEM PROFILE / GAMING ═══" -ForegroundColor Cyan

$mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Test-RegistryCheck $mmPath "SystemResponsiveness" 10 "SystemResponsiveness"
Test-RegistryCheck $mmPath "NoLazyMode" 1 "MMCSS NoLazyMode (realtime-only)"
# NetworkThrottlingIndex is NOT checked — deliberately left at Windows default (10)
# djdallmann xperf: 0xFFFFFFFF increases NDIS.sys DPC latency vs. default
Test-RegistryCheck "$mmPath\Tasks\Games" "Priority" 6 "Gaming Priority"
Test-RegistryCheck "$mmPath\Tasks\Games" "Scheduling Category" "High" "Gaming Scheduling Category"
Test-RegistryCheck "$mmPath\Tasks\Games" "GPU Priority" 8 "Gaming GPU Priority"
Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 0x2A "Win32PrioritySeparation (short fixed quantum, max foreground boost)"
Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1 "DisablePagingExecutive"

Write-Host "`n  ═══ TIMER / KERNEL ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" 1 "Timer Resolution"

# PowerThrottlingOff — Intel 12th gen+ only (E-core mismatch frametime spikes)
$_intelHybridName = Get-IntelHybridCpuName
if ($null -eq $_intelHybridName) {
    Write-Host "  ?  WARN      Power Throttling: could not detect CPU (skipping Intel-specific check)" -ForegroundColor Yellow
} elseif ($_intelHybridName) {
    Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1 "Intel Power Throttling disabled (E-core fix)"
} else {
    Write-Host "  ✓  INFO      Power Throttling: N/A (not Intel 12th gen+)" -ForegroundColor Cyan
    $global:_verifyOkCount++
}

Write-Host "`n  ═══ SYSTEM LATENCY TWEAKS ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKLM:\SOFTWARE\Microsoft\FTH" "Enabled" 0 "Fault Tolerant Heap disabled"
Test-RegistryCheck "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" "DisableCoInstallers" 1 "PnP co-installers disabled"
Test-RegistryCheck "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" "MaintenanceDisabled" 1 "Automatic Maintenance disabled"
# 0x80000001 stored as DWORD reads back as [int32]-2147483647 in PowerShell
# (0x80000001 literal is [int64]2147483649 — int32/int64 mismatch would fail -eq)
Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisableLastAccessUpdate" (-2147483647) "NTFS last-access update disabled"
Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisable8dot3NameCreation" 1 "NTFS 8.3 name creation disabled"

Write-Host "`n  ═══ MOUSE ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "Mouse Acceleration"
Test-RegistryCheck "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "Mouse Threshold 1"
Test-RegistryCheck "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "Mouse Threshold 2"
Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" "MouseDataQueueSize" 50 "mouclass kernel queue size (50)"

Write-Host "`n  ═══ NETWORK ═══" -ForegroundColor Cyan

$nicGuid = Get-ActiveNicGuid
if ($nicGuid) {
    $tcpBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$nicGuid"
    Test-RegistryCheck $tcpBase "TcpNoDelay" 1 "Nagle's Algorithm (TcpNoDelay)"
    Test-RegistryCheck $tcpBase "TcpAckFrequency" 1 "TCP Ack Frequency"
} else {
    Write-Host "  ?  MISSING   Active NIC not found — Nagle check skipped" -ForegroundColor Red
    $global:_verifyMissingCount += 2
}
Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS" "Do not use NLA" "1" "QoS NLA bypass (DSCP prerequisite)"
# IPv6 intentionally left ENABLED (2026 reversal: Steam prefers IPv6 when faster; disabling forces CGNAT)
Write-Host "  ✓  INFO      IPv6: enabled (intentional — Steam prefers IPv6 when faster)" -ForegroundColor Cyan
$global:_verifyOkCount++

Write-Host "`n  ═══ FAST STARTUP ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0 "Fast Startup disabled"

Write-Host "`n  ═══ AUDIO ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKCU:\Software\Microsoft\Multimedia\Audio" "UserDuckingPreference" 3 "Audio ducking disabled"

Write-Host "`n  ═══ OVERLAY ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKCU:\Software\Valve\Steam" "GameOverlayDisabled" 1 "Steam Overlay disabled"

Write-Host "`n  ═══ VISUAL EFFECTS / WIN11 ═══" -ForegroundColor Cyan

Test-RegistryCheck "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2 "Visual Effects (Best Performance)"
# UserPreferencesMask: binary comparison (Test-RegistryCheck uses -eq which is reference equality for byte[])
try {
    $upmDesktop = "HKCU:\Control Panel\Desktop"
    $upmVal = (Get-ItemProperty -Path $upmDesktop -Name "UserPreferencesMask" -ErrorAction Stop).UserPreferencesMask
    $upmExpected = [byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)
    if ($null -eq $upmVal) {
        Write-Host "  ?  MISSING   UserPreferencesMask (Best Performance + ClearType)" -ForegroundColor Red
        Write-Host "               $upmDesktop\UserPreferencesMask" -ForegroundColor DarkGray
        $global:_verifyMissingCount++
    } elseif (@(Compare-Object $upmVal $upmExpected -SyncWindow 0).Count -eq 0) {
        Write-Host "  ✓  OK        UserPreferencesMask (Best Performance + ClearType)" -ForegroundColor Green
        $global:_verifyOkCount++
    } else {
        $hexVal = ($upmVal | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Host "  ✗  CHANGED   UserPreferencesMask (is: $hexVal, expected: 90 12 03 80 10 00 00 00)" -ForegroundColor Yellow
        Write-Host "               $upmDesktop\UserPreferencesMask" -ForegroundColor DarkGray
        $global:_verifyChangedCount++
    }
} catch {
    Write-Host "  ?  MISSING   UserPreferencesMask (Best Performance + ClearType)" -ForegroundColor Red
    Write-Host "               HKCU:\Control Panel\Desktop\UserPreferencesMask" -ForegroundColor DarkGray
    $global:_verifyMissingCount++
}
Test-RegistryCheck "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "ClearType font smoothing enabled"
Test-RegistryCheck "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\VideoSettings" "AutoHDREnabled" 0 "Win11 Auto HDR disabled"

# ══════════════════════════════════════════════════════════════════════════════
# BCDEDIT CHECKS
# ══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ═══ BOOT CONFIG (bcdedit) ═══" -ForegroundColor Cyan

try {
    $bcdOutput = bcdedit /enum "{current}" 2>&1 | Out-String
    if ($bcdOutput -match "disabledynamictick\s+Yes") {
        Write-Host "  ✓  OK        Dynamic Tick disabled" -ForegroundColor Green
        $global:_verifyOkCount++
    } else {
        Write-Host "  ✗  CHANGED   Dynamic Tick is ACTIVE (expected: disabled)" -ForegroundColor Yellow
        $global:_verifyChangedCount++
    }
    if ($bcdOutput -match "useplatformtick\s+Yes") {
        Write-Host "  ✓  OK        Platform Tick active" -ForegroundColor Green
        $global:_verifyOkCount++
    } else {
        Write-Host "  ✗  CHANGED   Platform Tick is INACTIVE (expected: active)" -ForegroundColor Yellow
        $global:_verifyChangedCount++
    }
} catch {
    Write-Host "  ?  MISSING   bcdedit not readable" -ForegroundColor Red
    $global:_verifyMissingCount += 2
}

# ══════════════════════════════════════════════════════════════════════════════
# SERVICE CHECKS
# ══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  ═══ SERVICES ═══" -ForegroundColor Cyan

Test-ServiceCheck "SysMain" "Disabled" "SysMain (Superfetch)"
Test-ServiceCheck "WSearch" "Disabled" "Windows Search"
Test-ServiceCheck "qWave"   "Disabled" "qWave (QoS network probes)"
foreach ($xSvc in $CFG_XboxServices) {
    $xLabel = if ($xSvc -eq "XboxGipSvc") {
        "$xSvc (Xbox wireless accessories — re-enable if using Xbox controller/headset)"
    } else {
        "$xSvc (Xbox background service)"
    }
    Test-ServiceCheck $xSvc "Disabled" $xLabel
}

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

$counts = Get-VerifyCounters
$total = $counts.okCount + $counts.changedCount + $counts.missingCount
Write-Blank
Write-Host "  $("═" * 60)" -ForegroundColor DarkGray
Write-Host "  RESULT:  $total checks" -ForegroundColor White
Write-Host "  ✓  OK:       $($counts.okCount)" -ForegroundColor Green
Write-Host "  ✗  CHANGED:  $($counts.changedCount)" -ForegroundColor Yellow
Write-Host "  ?  MISSING:  $($counts.missingCount)" -ForegroundColor Red
Write-Host "  $("═" * 60)" -ForegroundColor DarkGray

if ($counts.changedCount -gt 0 -or $counts.missingCount -gt 0) {
    Write-Blank
    Write-Host "  Windows Update has likely reset some settings." -ForegroundColor Yellow
    Write-Host "  Recommendation: Run Phase 1 again (START.bat -> [1])." -ForegroundColor White
    Write-Host "  The suite detects completed steps and offers resume." -ForegroundColor DarkGray
} else {
    Write-Blank
    Write-Host "  All settings intact — no changes needed." -ForegroundColor Green
}

Write-Blank
