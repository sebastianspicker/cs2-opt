# ══════════════════════════════════════════════════════════════════════════════
# OPTIMIZE
# ══════════════════════════════════════════════════════════════════════════════
function Load-Optimize {
    $prog = $null
    try { $prog = Load-Progress } catch { Write-DebugLog "Optimize progress load failed: $($_.Exception.Message)" }
    $completed = if ($prog) { $prog.completedSteps } else { @() }
    $skipped   = if ($prog) { $prog.skippedSteps }   else { @() }

    $estimates = $CFG_ImprovementEstimates

    $rows = foreach ($s in $SCRIPT:StepCatalog) {
        $stepKey = "P$($s.Phase):$($s.Step)"
        $isDone  = $stepKey -in $completed
        $isSkip  = $stepKey -in $skipped

        $statusKey   = if ($s.CheckOnly) { "Check" } elseif ($isDone) { "Done" } elseif ($isSkip) { "Skipped" } else { "Pending" }
        $statusLabel = if ($s.CheckOnly) { "—  Check" } elseif ($isDone) { "✓  Done" } elseif ($isSkip) { "—  Skipped" } else { "○  Pending" }
        $statusColor = if ($s.CheckOnly) { "#6b7280" } elseif ($isDone) { "#22c55e" } elseif ($isSkip) { "#374151" } else { "#fbbf24" }

        $tierColor = switch ($s.Tier) { 1 { "#22c55e" } 2 { "#fbbf24" } 3 { "#e8520a" } default { "#6b7280" } }
        $riskColor = switch ($s.Risk) {
            "SAFE"       { "#22c55e" } "MODERATE"   { "#fbbf24" }
            "AGGRESSIVE" { "#e8520a" } "CRITICAL"   { "#ef4444" }
            default      { "#6b7280" }
        }

        $est = ""
        if ($s.EstKey -and $estimates.ContainsKey($s.EstKey)) {
            $e = $estimates[$s.EstKey]
            if ($e.P1LowMin -ne 0 -or $e.P1LowMax -ne 0) {
                $est = "+$($e.P1LowMin)-$($e.P1LowMax)% P1"
            }
        }

        [PSCustomObject]@{
            PhLabel     = "P$($s.Phase)"
            StepLabel   = "$($s.Step)"
            Category    = $s.Category
            Title       = $s.Title
            Tier        = $s.Tier
            TierLabel   = "T$($s.Tier)"
            TierColor   = $tierColor
            Risk        = $s.Risk
            RiskColor   = $riskColor
            StatusKey   = $statusKey
            StatusLabel = $statusLabel
            StatusColor = $statusColor
            RebootLabel = if ($s.Reboot) { "Yes" } else { "" }
            EstLabel    = $est
            _Step       = $s
        }
    }

    $SCRIPT:OptimizeAllRows = $rows
    (El "OptimizeGrid").ItemsSource = $rows

    # Populate category filter
    $cats = @("All") + ($rows | Select-Object -ExpandProperty Category -Unique | Sort-Object)
    (El "OptFilterCat").ItemsSource   = $cats
    (El "OptFilterCat").SelectedIndex = 0

    $statuses = @("All", "Pending", "Done", "Skipped", "Check")
    (El "OptFilterStatus").ItemsSource   = $statuses
    (El "OptFilterStatus").SelectedIndex = 0
}

(El "OptFilterCat"   ).Add_SelectionChanged({ Filter-OptimizeGrid })
(El "OptFilterStatus").Add_SelectionChanged({ Filter-OptimizeGrid })

function Filter-OptimizeGrid {
    $cat    = (El "OptFilterCat").SelectedItem
    $status = (El "OptFilterStatus").SelectedItem
    $all    = $SCRIPT:OptimizeAllRows
    if (-not $all) { return }
    $filtered = $all | Where-Object {
        ($cat    -eq "All" -or $_.Category -eq $cat) -and
        ($status -eq "All" -or $_.StatusKey -eq $status)
    }
    (El "OptimizeGrid").ItemsSource = @($filtered)
}

# ── Inline Verification ──────────────────────────────────────────────────────
# Checks actual system state (registry/services) and updates progress.json
# so the Optimize grid reflects which optimizations are actually applied,
# even if progress.json was lost or corrupted.
function Start-InlineVerify {
    (El "BtnOptVerify").IsEnabled = $false
    (El "BtnOptVerify").Content   = "Verifying…"

    Invoke-Async -Work {
        param($ScriptRoot, $UISync)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"

        $verified = [System.Collections.Generic.List[string]]::new()

        # ── Registry checks mapped to optimization steps ───────────────
        # Each entry: stepKey -> array of @{P=Path; N=Name; E=Expected}
        # Step is "verified" only if ALL checks pass.
        $checks = [ordered]@{
            # Phase 1
            "P1:4"  = @( @{P="HKCU:\System\GameConfigStore"; N="GameDVR_DXGIHonorFSEWindowsCompatible"; E=1} )
            "P1:11" = @( @{P="HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; N="OverlayTestMode"; E=5} )
            "P1:12" = @( @{P="HKCU:\SOFTWARE\Microsoft\GameBar"; N="AllowAutoGameMode"; E=1},
                         @{P="HKCU:\SOFTWARE\Microsoft\GameBar"; N="AutoGameModeEnabled"; E=1} )
            "P1:23" = @( @{P="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; N="HiberbootEnabled"; E=0} )
            "P1:26" = @( @{P="HKCU:\System\GameConfigStore"; N="GameDVR_FSEBehavior"; E=2},
                         @{P="HKCU:\System\GameConfigStore"; N="GameDVR_FSEBehaviorMode"; E=2},
                         @{P="HKCU:\System\GameConfigStore"; N="GameDVR_HonorUserFSEBehaviorMode"; E=1} )
            "P1:27" = @( @{P="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; N="SystemResponsiveness"; E=10},
                         @{P="HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; N="Win32PrioritySeparation"; E=0x2A} )
            "P1:28" = @( @{P="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"; N="GlobalTimerResolutionRequests"; E=1} )
            "P1:29" = @( @{P="HKCU:\Control Panel\Mouse"; N="MouseSpeed"; E="0"},
                         @{P="HKCU:\Control Panel\Mouse"; N="MouseThreshold1"; E="0"},
                         @{P="HKCU:\Control Panel\Mouse"; N="MouseThreshold2"; E="0"} )
            "P1:31" = @( @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"; N="AppCaptureEnabled"; E=0},
                         @{P="HKCU:\SOFTWARE\Microsoft\GameBar"; N="UseNexusForGameBarEnabled"; E=0},
                         @{P="HKCU:\System\GameConfigStore"; N="GameDVR_Enabled"; E=0} )
            "P1:32" = @( @{P="HKCU:\Software\Valve\Steam"; N="GameOverlayDisabled"; E=1} )
            "P1:33" = @( @{P="HKCU:\Software\Microsoft\Multimedia\Audio"; N="UserDuckingPreference"; E=3} )
            "P1:36" = @( @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"; N="VisualFXSetting"; E=2} )
            # Phase 3
            "P3:7"  = @( @{P="HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; N="Enabled"; E=0} )
            "P3:10" = @( @{P="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions"; N="CpuPriorityClass"; E=3} )
        }

        foreach ($stepKey in $checks.Keys) {
            $allOk = $true
            foreach ($c in $checks[$stepKey]) {
                $r = Test-RegistryCheck $c.P $c.N $c.E "" -Quiet
                if ($r.Status -ne "OK") { $allOk = $false; break }
            }
            if ($allOk) { $verified.Add($stepKey) }
        }

        # ── Service checks ─────────────────────────────────────────────
        # P1:37 - Disable Bloat Services (SysMain + WSearch)
        try {
            $sm = Get-Service -Name "SysMain" -ErrorAction Stop
            $ws = Get-Service -Name "WSearch" -ErrorAction Stop
            if ($sm.StartType -eq 'Disabled' -and $ws.StartType -eq 'Disabled') { $verified.Add("P1:37") }
        } catch {}

        # ── NIC check (P1:25 - Disable Nagle) ─────────────────────────
        try {
            $nicGuid = Get-ActiveNicGuid
            if ($nicGuid) {
                $tcpBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$nicGuid"
                $r = Test-RegistryCheck $tcpBase "TcpNoDelay" 1 "" -Quiet
                if ($r.Status -eq "OK") { $verified.Add("P1:25") }
            }
        } catch {}

        # ── NVIDIA GPU check (P3:4 - DRS Profile / PerfLevelSrc) ──────
        try {
            $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$CFG_GUID_Display"
            if (Test-Path $classPath) {
                $subkeys = Get-ChildItem $classPath -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -match "^\d{4}$" }
                foreach ($key in $subkeys) {
                    $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
                    if ($props.ProviderName -match "NVIDIA" -or $props.DriverDesc -match "NVIDIA") {
                        $r = Test-RegistryCheck $key.PSPath "PerfLevelSrc" 0x2222 "" -Quiet
                        if ($r.Status -eq "OK") { $verified.Add("P3:4") }
                        break
                    }
                }
            }
        } catch {}

        $UISync.VerifyResults = @($verified)
    } -WorkArgs @($Script:Root, $Script:UISync) -OnDone {
        $verified = $Script:UISync.VerifyResults
        if (-not $verified) { $verified = @() }

        # Update progress.json with verified steps
        $prog = Load-Progress
        if (-not $prog) {
            $prog = [PSCustomObject]@{ phase=0; lastCompletedStep=0; completedSteps=@(); skippedSteps=@(); timestamps=[PSCustomObject]@{} }
        }

        $added = 0
        foreach ($stepKey in $verified) {
            if ($stepKey -notin @($prog.completedSteps)) {
                $prog.completedSteps = @($prog.completedSteps) + $stepKey
                $added++
            }
        }
        if ($added -gt 0) {
            if (Test-BackupLock) {
                Write-DebugLog "Inline verify: skipping progress save — backup lock held by another process"
            } else {
                $maxPhase = ($verified | ForEach-Object {
                    if ($_ -match "^P(\d+):") { [int]$Matches[1] } else { 0 }
                } | Measure-Object -Maximum).Maximum
                if ($maxPhase -gt $prog.phase) { $prog.phase = $maxPhase }
                Save-Progress $prog
                $state = Get-StateDataSafe
                if (-not $state) {
                    $state = New-DefaultState
                }
                $state | Add-Member -NotePropertyName "startup_last_verified" -NotePropertyValue ((Get-Date).ToString("o")) -Force
                Save-StateDataSafe -State $state
            }
        }

        # Reload grid with updated progress
        Load-Optimize

        (El "BtnOptVerify").IsEnabled = $true
        (El "BtnOptVerify").Content   = "✓  Verify All"

        $total = @($verified).Count
        $msg = if ($added -gt 0) {
            "Verified: $total steps applied.`n$added step(s) recovered to progress."
        } else {
            "Verified: $total steps applied.`nProgress already up to date."
        }
        [System.Windows.MessageBox]::Show($msg, "Verification Complete")
        $Script:UISync.VerifyResults = $null
    }
}

(El "BtnOptPhase1"   ).Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnOptPhase3"   ).Add_Click({ Launch-Terminal "PostReboot-Setup.ps1" })
(El "BtnOptFullSetup").Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnOptVerify"   ).Add_Click({ Start-InlineVerify })

# Phase 2 and 3 launch buttons: expose only the safe entrypoint for the current boot mode.
if ($env:SAFEBOOT_OPTION) {
    (El "BtnOptPhase3").IsEnabled = $false
    (El "BtnOptPhase3").ToolTip   = "Phase 3 requires a Normal Mode boot after Phase 2 completes"
} else {
    (El "BtnOptPhase3").ToolTip = "Manual recovery entrypoint after a completed Phase 2 run"
}

# Boot to Safe Mode / Normal Mode button — context-aware failsafe
if ($env:SAFEBOOT_OPTION) {
    # In Safe Mode: offer to exit back to Normal Mode
    (El "BtnBootSafeMode").Content = "Boot to Normal Mode"
    (El "BtnBootSafeMode").ToolTip = "Remove Safe Mode boot flag and restart into Normal Mode"
    (El "BtnBootSafeMode").Add_Click({
        $confirm = [System.Windows.MessageBox]::Show(
            "This will remove the Safe Mode boot flag and restart into Normal Mode.`n`nRestart now?",
            "Boot to Normal Mode", "YesNo", "Question")
        if ($confirm -eq "Yes") {
            $bcdOut = bcdedit /deletevalue safeboot 2>&1
            if ($LASTEXITCODE -ne 0) {
                [System.Windows.MessageBox]::Show(
                    "Failed to remove Safe Mode flag (bcdedit exit $LASTEXITCODE).`n`n$($bcdOut | Out-String)`nReboot aborted — you are still in Safe Mode.",
                    "bcdedit Error", "OK", "Error")
                return
            }
            shutdown /r /t 5 /f
        }
    })
} else {
    # In Normal Mode: offer to boot into Safe Mode
    (El "BtnBootSafeMode").Add_Click({
        try {
            Launch-Terminal "Boot-SafeMode.ps1"
        } catch {
            [System.Windows.MessageBox]::Show("Boot-SafeMode failed: $_", "Error", "OK", "Error")
        }
    })
}

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP
# ══════════════════════════════════════════════════════════════════════════════
function Load-Backup {
    try {
        $bd = Get-BackupData
        if (-not $bd -or -not $bd.entries) {
            (El "BackupSummary").Text = "No backups found in backup.json"
            (El "BackupGrid").ItemsSource = $null
            return
        }
        $entries = $bd.entries
        (El "BackupSummary").Text = "$($entries.Count) backup entries  ·  Created $($bd.created)"

        $rows = foreach ($e in $entries) {
            $key = switch ($e.type) {
                "registry"      { "$($e.path)  →  $($e.name)" }
                "service"       { $e.name }
                "bootconfig"    { $e.key }
                "powerplan"     { "Power Plan: $($e.originalName)" }
                "drs"           { "DRS Profile: $($e.profile)  ($($e.settings.Count) settings)" }
                "scheduledtask" { "Task: $($e.taskName)" }
                default         { "$($e.type)" }
            }
            $orig = switch ($e.type) {
                "registry"      { if ($e.existed) { "$($e.originalValue)" } else { "(new key)" } }
                "service"       { "$($e.originalStartType) / $($e.originalStatus)" }
                "bootconfig"    { if ($e.existed) { $e.originalValue } else { "(new)" } }
                "powerplan"     { $e.originalGuid }
                "drs"           { "$($e.settings.Count) settings" }
                "scheduledtask" { if ($e.existed) { "existed" } else { "(new)" } }
                default         { "" }
            }
            [PSCustomObject]@{
                Step      = $e.step
                Type      = $e.type
                Key       = $key
                Original  = $orig
                Timestamp = $e.timestamp
                _Entry    = $e
            }
        }
        (El "BackupGrid").ItemsSource = $rows
    } catch {
        (El "BackupSummary").Text = "Error loading backup.json: $($_.Exception.Message)"
    }
}

(El "BtnBackupRefresh").Add_Click({ Load-Backup })

(El "BtnBackupExport").Add_Click({
    $src = "$CFG_WorkDir\backup.json"
    if (-not (Test-Path $src)) { [System.Windows.MessageBox]::Show("backup.json not found.","Export"); return }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $dlg.FileName = "cs2-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
    if ($dlg.ShowDialog() -eq $true) { Copy-Item $src $dlg.FileName -Force; [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)","Export Complete") }
})

(El "BtnRestoreAll").Add_Click({
    if (Test-BackupLock) {
        [System.Windows.MessageBox]::Show(
            "Another CS2 Optimization process is running. Wait for it to finish first.",
            "Locked", "OK", "Warning")
        return
    }
    $r = [System.Windows.MessageBox]::Show("Restore ALL backed-up settings?`nThis will undo every change the suite made.","Restore All","YesNo","Warning")
    if ($r -eq "Yes") {
        Set-BackupLock
        try {
            # Call step restores directly — Restore-AllChanges uses Read-Host which blocks GUI (no console)
            $bd = Get-BackupData
            if ($bd.entries -and $bd.entries.Count -gt 0) {
                $stepNames = @(($bd.entries | Group-Object -Property step).Name)
                $failures = 0
                foreach ($sn in $stepNames) { if (-not (Restore-StepChanges -StepTitle $sn)) { $failures++ } }
                if ($failures -gt 0) { throw "$failures step group(s) had restore failures." }
            }
            [System.Windows.MessageBox]::Show("All settings restored successfully.","Restore Complete")
            Load-Backup
        } catch {
            [System.Windows.MessageBox]::Show("Restore error: $($_.Exception.Message)","Restore Failed","OK","Error")
        } finally {
            Remove-BackupLock
        }
    }
})

(El "BtnRestoreStep").Add_Click({
    if (Test-BackupLock) {
        [System.Windows.MessageBox]::Show(
            "Another CS2 Optimization process is running. Wait for it to finish first.",
            "Locked", "OK", "Warning")
        return
    }
    $sel = (El "BackupGrid").SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a row first.","Restore Step"); return }
    $stepTitle = $sel.Step
    $r = [System.Windows.MessageBox]::Show("Restore all changes from:`n`"$stepTitle`"?","Restore Step","YesNo","Question")
    if ($r -eq "Yes") {
        Set-BackupLock
        try {
            $ok = Restore-StepChanges $stepTitle
            if ($ok) {
                [System.Windows.MessageBox]::Show("Restore complete for:`n$stepTitle","Done")
            } else {
                [System.Windows.MessageBox]::Show("Restore partially failed for:`n$stepTitle`n`nSome entries could not be restored. Check the log for details.","Restore Incomplete","OK","Warning")
            }
            Load-Backup
        } catch { [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)","Restore Failed") }
        finally { Remove-BackupLock }
    }
})

(El "BtnClearBackup").Add_Click({
    $r = [System.Windows.MessageBox]::Show("Delete all backup data?`nThis cannot be undone.","Clear Backups","YesNo","Warning")
    if ($r -eq "Yes") {
        if (Test-Path "$CFG_WorkDir\backup.json") { Remove-Item "$CFG_WorkDir\backup.json" -Force }
        Load-Backup
    }
})

