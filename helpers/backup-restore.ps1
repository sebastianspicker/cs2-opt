# ==============================================================================
#  helpers/backup-restore.ps1  —  Setting Backup & Restore System
# ==============================================================================
#
#  Automatically captures registry, service, and boot config state BEFORE
#  modifications. Enables per-step or full rollback if something goes wrong.
#
#  Integration:
#    Set-RegistryValue / Set-BootConfig auto-backup via $SCRIPT:CurrentStepTitle
#    Backup-DrsSettings / Restore-DrsSettings for NVIDIA DRS profile settings
#    Manual: Backup-ServiceState, Restore-StepChanges, Restore-AllChanges

$CFG_BackupFile = "$CFG_WorkDir\backup.json"
# Sentinel used when DRS profile was found via app registration rather than by name.
# Must match between Backup-DrsSettings (write) and Restore-DrsSettings (read).
$SCRIPT:DRS_FOUND_VIA_APP = "(found via cs2.exe)"

function Initialize-Backup {
    if (-not (Test-Path $CFG_BackupFile)) {
        Save-JsonAtomic -Data @{ entries = @(); created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") } -Path $CFG_BackupFile
    }
}

function Get-BackupData {
    if (-not (Test-Path $CFG_BackupFile)) { Initialize-Backup }
    try {
        $raw = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        if ($null -eq $raw.entries) { $raw | Add-Member -NotePropertyName "entries" -NotePropertyValue @() -Force }
        return $raw
    } catch {
        # Preserve corrupted file for recovery before overwriting
        $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $corruptPath = "$CFG_BackupFile.corrupt.$ts"
        try { Copy-Item $CFG_BackupFile $corruptPath -Force -ErrorAction Stop } catch {}
        Write-Warn "backup.json was corrupted — saved copy to $corruptPath before resetting."
        Initialize-Backup
        return [PSCustomObject]@{ entries = @(); created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    }
}

function Save-BackupData($data) {
    Save-JsonAtomic -Data $data -Path $CFG_BackupFile -Depth 10
}

function Backup-RegistryValue {
    <#  Records the current value of a registry key before modification.  #>
    param([string]$Path, [string]$Name, [string]$StepTitle)
    $backup = Get-BackupData
    $existing = $null
    $regType  = $null
    try {
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            $existing = $prop.$Name
            try { $regType = (Get-Item $Path).GetValueKind($Name).ToString() } catch { $regType = "DWord" }
        }
    } catch {}

    $entry = [ordered]@{
        type          = "registry"
        path          = $Path
        name          = $Name
        originalValue = $existing
        originalType  = $regType
        existed       = ($null -ne $existing)
        step          = $StepTitle
        timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $entries = [System.Collections.ArrayList]@($backup.entries)
    $entries.Add($entry) | Out-Null
    $backup.entries = @($entries)
    Save-BackupData $backup
}

function Backup-ServiceState {
    <#  Records current service start type, delayed-start flag, and status before modification.  #>
    param([string]$ServiceName, [string]$StepTitle)
    $backup = Get-BackupData
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        $startType = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop).StartMode
        # Capture DelayedAutoStart flag — services with "Automatic (Delayed Start)" show StartMode=Auto
        # but have a separate registry flag. Without this, restore loses the "Delayed" qualifier.
        $delayedStart = $false
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
            $delayReg = Get-ItemProperty -Path $regPath -Name "DelayedAutostart" -ErrorAction SilentlyContinue
            $delayedStart = ($delayReg.DelayedAutostart -eq 1)
        } catch {}
        $entry = [ordered]@{
            type              = "service"
            name              = $ServiceName
            originalStartType = $startType
            delayedAutoStart  = $delayedStart
            originalStatus    = $svc.Status.ToString()
            step              = $StepTitle
            timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $entries = [System.Collections.ArrayList]@($backup.entries)
        $entries.Add($entry) | Out-Null
        $backup.entries = @($entries)
        Save-BackupData $backup
    } catch { Write-Debug "Backup-ServiceState: $ServiceName not found" }
}

function Backup-PowerPlan {
    <#  Records the currently active power plan GUID before switching.  #>
    param([string]$StepTitle)
    $backup = Get-BackupData
    $originalGuid = $null
    $originalName = $null
    try {
        $activeOutput = powercfg /getactivescheme 2>&1
        if ($activeOutput -match "([a-f0-9-]{36})") {
            $originalGuid = $Matches[1]
            if ($activeOutput -match "\((.+)\)\s*$") {
                $originalName = $Matches[1]
            }
        }
    } catch {}

    if ($originalGuid) {
        $entry = [ordered]@{
            type          = "powerplan"
            originalGuid  = $originalGuid
            originalName  = $originalName
            step          = $StepTitle
            timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $entries = [System.Collections.ArrayList]@($backup.entries)
        $entries.Add($entry) | Out-Null
        $backup.entries = @($entries)
        Save-BackupData $backup
        Write-Debug "Backup-PowerPlan: saved $originalGuid ($originalName)"
    }
}

function Backup-BootConfig {
    <#  Records current bcdedit value before modification.  #>
    param([string]$Key, [string]$StepTitle)
    $backup = Get-BackupData
    $existing = $null
    try {
        $bcdOutput = bcdedit /enum "{current}" 2>&1
        foreach ($line in $bcdOutput) {
            if ($line -match "^\s*$Key\s+(.+)$") {
                $existing = $Matches[1].Trim()
                break
            }
        }
    } catch {}

    $entry = [ordered]@{
        type          = "bootconfig"
        key           = $Key
        originalValue = $existing
        existed       = ($null -ne $existing)
        step          = $StepTitle
        timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $entries = [System.Collections.ArrayList]@($backup.entries)
    $entries.Add($entry) | Out-Null
    $backup.entries = @($entries)
    Save-BackupData $backup
}

function Backup-ScheduledTask {
    <#  Records whether a scheduled task existed before we create/replace it.  #>
    param([string]$TaskName, [string]$StepTitle)
    $backup = Get-BackupData
    $existed = $false
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $existed = ($null -ne $task)
    } catch {}

    $entry = [ordered]@{
        type       = "scheduledtask"
        taskName   = $TaskName
        existed    = $existed
        scriptPath = "$CFG_WorkDir\cs2_affinity.ps1"
        step       = $StepTitle
        timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $entries = [System.Collections.ArrayList]@($backup.entries)
    $entries.Add($entry) | Out-Null
    $backup.entries = @($entries)
    Save-BackupData $backup
    Write-Debug "Backup-ScheduledTask: '$TaskName' existed=$existed"
}

function Backup-DrsSettings {
    <#
    .SYNOPSIS  Records current NVIDIA DRS setting values before overwrite.
    .DESCRIPTION
        Reads each setting ID from the DRS profile and stores the current value
        (or null if the setting doesn't exist yet) in backup.json.
        Called from Apply-NvidiaCS2ProfileDrs before writing new values.
    #>
    param(
        [IntPtr]$Session,
        [IntPtr]$DrsProfile,
        [uint32[]]$SettingIds,
        [string]$StepTitle,
        [string]$ProfileName,
        [bool]$ProfileCreated
    )
    $backup = Get-BackupData

    $settings = @()
    foreach ($id in $SettingIds) {
        [uint32]$currentValue = 0
        $status = [NvApiDrs]::GetDwordSetting($Session, $DrsProfile, $id, [ref]$currentValue)
        $settings += [ordered]@{
            id            = $id
            previousValue = $(if ($status -eq 0) { $currentValue } else { $null })
            existed       = ($status -eq 0)
        }
    }

    $entry = [ordered]@{
        type           = "drs"
        step           = $StepTitle
        profile        = $ProfileName
        profileCreated = $ProfileCreated
        settings       = $settings
        timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $entries = [System.Collections.ArrayList]@($backup.entries)
    $entries.Add($entry) | Out-Null
    $backup.entries = @($entries)
    Save-BackupData $backup
    Write-Debug "Backup-DrsSettings: saved $($SettingIds.Count) DRS settings for '$StepTitle'"
}

function Restore-DrsSettings {
    <#
    .SYNOPSIS  Restores NVIDIA DRS settings from a backup entry.
    .DESCRIPTION
        For each backed up setting:
        - If it existed before: writes the previous value back via DRS
        - If it didn't exist: writes 0 (default) as fallback
        If the profile was created by us, deletes it entirely.
    #>
    param($Entry)

    if (-not (Initialize-NvApiDrs)) {
        Write-Warn "Cannot restore DRS settings — nvapi64.dll unavailable."
        return
    }

    try {
        Invoke-DrsSession -Action {
            param($session)

            # Find the profile
            $drsProfile = [IntPtr]::Zero
            if ($Entry.profile -and $Entry.profile -ne $SCRIPT:DRS_FOUND_VIA_APP) {
                $drsProfile = [NvApiDrs]::FindProfileByName($session, $Entry.profile)
            }
            if ($drsProfile -eq [IntPtr]::Zero) {
                $drsProfile = [NvApiDrs]::FindApplicationProfile($session, "cs2.exe")
            }
            if ($drsProfile -eq [IntPtr]::Zero) {
                Write-Warn "DRS restore: CS2 profile not found — may have been deleted already."
                return
            }

            if ($Entry.profileCreated) {
                # We created this profile — delete it entirely
                try {
                    [NvApiDrs]::DeleteProfile($session, $drsProfile)
                    Write-OK "Deleted DRS profile: $($Entry.profile)"
                } catch {
                    Write-Warn "DRS restore: could not delete profile — $_"
                }
            } else {
                # Profile existed before — restore individual settings
                $restored = 0
                $skipped  = 0
                $errors   = 0
                foreach ($s in $Entry.settings) {
                    try {
                        if ($s.existed) {
                            [NvApiDrs]::SetDwordSetting($session, $drsProfile, [uint32]$s.id, [uint32]$s.previousValue)
                            $restored++
                        } else {
                            # Setting didn't exist before — skip (writing 0 is NOT equivalent to "not set"
                            # for many DRS settings, e.g., VSync tear control 0 = enabled, not "remove")
                            $skipped++
                        }
                    } catch {
                        $errors++
                        Write-Debug "DRS restore: failed for 0x$($s.id.ToString('X')): $_"
                    }
                }
                if ($errors -eq 0) {
                    Write-OK "Restored $restored DRS settings in profile '$($Entry.profile)'"
                } else {
                    Write-Warn "DRS restore: $restored restored, $errors failed in profile '$($Entry.profile)'"
                }
                if ($skipped -gt 0) {
                    Write-Info "DRS restore: $skipped setting(s) were new (no previous value) — left as-is."
                }
            }
        }
    } catch {
        Write-Warn "DRS restore failed: $_"
    }
}

function Show-BackupSummary {
    <#  Displays all backed-up settings grouped by step.  #>
    $backup = Get-BackupData
    if (-not $backup.entries -or $backup.entries.Count -eq 0) {
        Write-Info "No backups recorded yet."
        return
    }

    Write-Blank
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  BACKUP SUMMARY — Recorded Settings Before Changes              ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

    $grouped = $backup.entries | Group-Object -Property step
    foreach ($group in $grouped) {
        Write-Host "  ║  $($group.Name)  ($($group.Count) change(s))" -ForegroundColor White
        foreach ($e in $group.Group) {
            $detail = switch ($e.type) {
                "registry"   { "REG  $($e.name) = $(if($e.existed){"$($e.originalValue)"}else{'(not set)'})" }
                "service"    { "SVC  $($e.name) was $($e.originalStartType) / $($e.originalStatus)" }
                "bootconfig" { "BCD  $($e.key) = $(if($e.existed){"$($e.originalValue)"}else{'(not set)'})" }
                "powerplan"  { "PWR  was $($e.originalName) ($($e.originalGuid))" }
                "drs"           { "DRS  profile '$($e.profile)' — $($e.settings.Count) setting(s)" }
                "scheduledtask" { "TASK $($e.taskName) $(if($e.existed){'(existed before)'}else{'(created by us)'})" }
            }
            Write-Host "  ║    $detail" -ForegroundColor DarkGray
        }
    }

    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  Total: $($backup.entries.Count) setting(s) backed up" -ForegroundColor DarkGray
    Write-Host "  File:  $CFG_BackupFile" -ForegroundColor DarkGray
}

function Restore-StepChanges {
    <#  Restores all backed-up settings from a specific step.  #>
    param([string]$StepTitle)
    $backup = Get-BackupData
    $entries = @($backup.entries | Where-Object { $_.step -eq $StepTitle })
    if ($entries.Count -eq 0) {
        Write-Warn "No backup found for: $StepTitle"
        return $false
    }

    Write-Step "Restoring $($entries.Count) setting(s) from: $StepTitle"
    $restoreOk = 0
    $restoreFail = 0
    foreach ($e in $entries) {
        try {
            switch ($e.type) {
                "registry" {
                    if ($e.existed) {
                        $restoreType = if ($e.originalType) { $e.originalType } else { "DWord" }
                        $restoreValue = $e.originalValue
                        # Binary values are serialized as int arrays in JSON; cast back to byte[]
                        if ($restoreType -eq "Binary" -and $restoreValue -is [array]) {
                            $restoreValue = [byte[]]@($restoreValue | ForEach-Object { [byte]$_ })
                        }
                        Set-ItemProperty -Path $e.path -Name $e.name -Value $restoreValue -Type $restoreType -ErrorAction Stop
                        Write-OK "Restored: $($e.name) = $($e.originalValue)"
                    } else {
                        Remove-ItemProperty -Path $e.path -Name $e.name -ErrorAction Stop
                        Write-OK "Removed: $($e.name) (was not set before)"
                    }
                    $restoreOk++
                }
                "service" {
                    $startMap = @{ "Auto"="Automatic"; "Manual"="Manual"; "Disabled"="Disabled"; "Auto Delayed"="AutomaticDelayedStart" }
                    $mapped = if ($startMap[$e.originalStartType]) { $startMap[$e.originalStartType] } else { $e.originalStartType }
                    # Boot/System/Unknown are kernel driver start types — Set-Service cannot change them
                    if ($e.originalStartType -in @("Boot","System","Unknown")) {
                        Write-Warn "Service $($e.name) has start type '$mapped' — cannot restore via Set-Service (kernel driver)."
                        $restoreOk++
                        continue
                    }
                    Set-Service -Name $e.name -StartupType $mapped -ErrorAction SilentlyContinue
                    # Restore DelayedAutoStart flag if it was set (Auto + Delayed = "Automatic (Delayed Start)")
                    if ($e.delayedAutoStart) {
                        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($e.name)"
                        Set-ItemProperty -Path $regPath -Name "DelayedAutostart" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                    }
                    if ($e.originalStatus -eq "Running") {
                        Start-Service -Name $e.name -ErrorAction SilentlyContinue
                    }
                    $delayTag = if ($e.delayedAutoStart) { " (Delayed)" } else { "" }
                    Write-OK "Restored: $($e.name) -> $($e.originalStartType)$delayTag"
                    $restoreOk++
                }
                "bootconfig" {
                    if ($e.existed) {
                        bcdedit /set $e.key $e.originalValue 2>&1 | Out-Null
                        Write-OK "Restored: bcdedit $($e.key) = $($e.originalValue)"
                    } else {
                        bcdedit /deletevalue $e.key 2>&1 | Out-Null
                        Write-OK "Removed: bcdedit $($e.key)"
                    }
                    $restoreOk++
                }
                "powerplan" {
                    # Restore original power plan and delete the imported one
                    powercfg /setactive $e.originalGuid 2>&1 | Out-Null
                    Write-OK "Restored power plan: $($e.originalName) ($($e.originalGuid))"
                    # Delete any FPSHeaven/CS2 Optimized plans we created
                    $allPlans = powercfg /list 2>&1
                    foreach ($line in $allPlans) {
                        if ($line -match "([a-f0-9-]{36})") {
                            $planGuid = $Matches[1]
                            if (($line -match "FPSHeaven" -or $line -match "CS2 Optimized") -and $planGuid -ne $e.originalGuid) {
                                powercfg /delete $planGuid 2>&1 | Out-Null
                                Write-OK "Deleted imported plan: $planGuid"
                            }
                        }
                    }
                    $restoreOk++
                }
                "drs" {
                    Restore-DrsSettings -Entry $e
                    $restoreOk++
                }
                "scheduledtask" {
                    if (-not $e.existed) {
                        try {
                            $task = Get-ScheduledTask -TaskName $e.taskName -ErrorAction SilentlyContinue
                            if ($task) {
                                Unregister-ScheduledTask -TaskName $e.taskName -Confirm:$false
                                Write-OK "Removed scheduled task: $($e.taskName)"
                            }
                        } catch { Write-Warn "Could not remove scheduled task $($e.taskName): $_" }
                        if ($e.scriptPath -and (Test-Path $e.scriptPath)) {
                            Remove-Item $e.scriptPath -Force -ErrorAction SilentlyContinue
                            Write-OK "Removed: $($e.scriptPath)"
                        }
                    } else {
                        # Task existed before — re-enable it (we disabled it, not removed it)
                        try {
                            $task = Get-ScheduledTask -TaskName $e.taskName -ErrorAction SilentlyContinue
                            if ($task -and $task.State -eq "Disabled") {
                                Enable-ScheduledTask -TaskName $e.taskName -ErrorAction Stop | Out-Null
                                Write-OK "Re-enabled scheduled task: $($e.taskName)"
                            } else {
                                Write-Info "Scheduled task '$($e.taskName)' already enabled — kept."
                            }
                        } catch { Write-Warn "Could not re-enable task $($e.taskName): $_" }
                    }
                    $restoreOk++
                }
            }
        } catch {
            $restoreFail++
            Write-Warn "Restore failed for $($e.type) $(if($e.name){$e.name}else{$e.profile}): $_"
        }
    }

    # Summary
    if ($restoreFail -gt 0) {
        Write-Warn "Restore '$StepTitle': $restoreOk succeeded, $restoreFail failed — check warnings above."
    }

    # Remove restored entries
    $backup.entries = @($backup.entries | Where-Object { $_.step -ne $StepTitle })
    Save-BackupData $backup
    return $true
}

function Restore-AllChanges {
    <#  Interactive restore of ALL backed-up settings.  #>
    $backup = Get-BackupData
    if (-not $backup.entries -or $backup.entries.Count -eq 0) {
        Write-Info "No backups to restore."
        return
    }

    Show-BackupSummary
    Write-Blank
    Write-Warn "This will restore ALL $($backup.entries.Count) backed up setting(s)."
    $r = Read-Host "  Proceed with full restore? [y/N]"
    if ($r -notmatch "^[jJyY]$") { Write-Info "Cancelled."; return }

    $stepNames = @(($backup.entries | Group-Object -Property step).Name)
    $failures = 0
    foreach ($stepName in $stepNames) {
        $result = Restore-StepChanges -StepTitle $stepName
        if (-not $result) { $failures++ }
    }
    if ($failures -eq 0) {
        Write-OK "All settings restored to pre-optimization state."
    } else {
        Write-Warn "$failures step group(s) had restore failures — check output above."
    }
}

function Restore-Interactive {
    <#  Let the user pick which steps to restore.  #>
    $backup = Get-BackupData
    if (-not $backup.entries -or $backup.entries.Count -eq 0) {
        Write-Info "No backups to restore."
        return
    }

    Show-BackupSummary
    Write-Blank
    $grouped = $backup.entries | Group-Object -Property step
    Write-Host "  Select step to restore:" -ForegroundColor White
    for ($i = 0; $i -lt $grouped.Count; $i++) {
        Write-Host "  [$($i+1)]  $($grouped[$i].Name)  ($($grouped[$i].Count) change(s))" -ForegroundColor White
    }
    Write-Host "  [A]  Restore ALL" -ForegroundColor Yellow
    Write-Host "  [0]  Cancel" -ForegroundColor DarkGray

    $choice = Read-Host "  Choice"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -match "^[aA]$") { Restore-AllChanges; return }

    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $grouped.Count) {
        Restore-StepChanges -StepTitle $grouped[$idx-1].Name
    } else { Write-Warn "Invalid selection." }
}
