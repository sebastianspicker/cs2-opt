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
$CFG_BackupLockFile = "$CFG_WorkDir\backup.lock"
# Sentinel used when DRS profile was found via app registration rather than by name.
# Must match between Backup-DrsSettings (write) and Restore-DrsSettings (read).
$SCRIPT:DRS_FOUND_VIA_APP = "(found via cs2.exe)"

# ── In-memory batch buffer ─────────────────────────────────────────────────
# Backup entries are accumulated in $SCRIPT:_backupPending during a step, then
# flushed to disk once via Flush-BackupBuffer.  This avoids O(n^2) I/O from
# reading+writing backup.json on every single Set-RegistryValue call (~60+
# calls per full Phase 1 run).  Flush is called automatically by
# Invoke-TieredStep after each step's action completes, and also by any
# function that reads backup data (Get-BackupData) to ensure consistency.
$SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

function Initialize-Backup {
    if (-not (Test-Path $CFG_BackupFile)) {
        Save-JsonAtomic -Data @{ entries = @(); created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") } -Path $CFG_BackupFile
    }
    # Acquire lock — warns if another instance is running but does not block
    # (the lock is advisory; concurrent writes are protected by Save-JsonAtomic)
    if (Test-BackupLock) {
        Write-Warn "Another CS2 Optimization process appears to be running (backup.lock exists)."
        Write-Warn "If the other process crashed, the lock will auto-clear."
    }
    Set-BackupLock
}

function Test-BackupLock {
    <#  Checks if another process is actively modifying backup.json.
        Returns $true if the lock is held (and the holding process is still alive).
        Stale locks (from crashed processes) are automatically cleaned up.
        Mitigates PID reuse: verifies the process is PowerShell, not an unrelated
        process that inherited the recycled PID.  #>
    if (-not (Test-Path $CFG_BackupLockFile)) { return $false }
    try {
        $lockData = Get-Content $CFG_BackupLockFile -Raw -ErrorAction Stop | ConvertFrom-Json
        # Check if the locking process is still alive
        $proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
        if ($proc) {
            # Mitigate PID reuse: Windows recycles PIDs, so a live process with the
            # same PID may be entirely unrelated. Verify it's a PowerShell instance.
            $isPowerShell = $proc.ProcessName -match '^(?:powershell|pwsh|powershell_ise)$'
            if ($isPowerShell) { return $true }
            # PID was reused by a non-PowerShell process — stale lock
            Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
            Write-Debug "Removed stale backup lock (PID $($lockData.pid) reused by '$($proc.ProcessName)')."
            return $false
        }
        # Process is dead — stale lock; remove it
        Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
        Write-Debug "Removed stale backup lock (PID $($lockData.pid) no longer running)."
    } catch {
        # Corrupted lock file — remove it
        Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
    }
    return $false
}

function Set-BackupLock {
    <#  Creates a lockfile indicating this process is modifying backup.json.
        Called at the start of optimization and restore operations.  #>
    $lockData = @{ pid = $PID; started = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    $lockData | ConvertTo-Json | Set-Content $CFG_BackupLockFile -Encoding UTF8 -Force
}

function Remove-BackupLock {
    <#  Removes the lockfile. Called at the end of operations.  #>
    Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
}

function Flush-BackupBuffer {
    <#  Writes any pending in-memory backup entries to backup.json in a single I/O pass.
        Safe to call multiple times — no-op when the buffer is empty.  #>
    if ($SCRIPT:_backupPending.Count -eq 0) { return }
    $backup = Get-BackupDataRaw
    $entries = [System.Collections.ArrayList]@($backup.entries)
    foreach ($e in $SCRIPT:_backupPending) {
        $entries.Add($e) | Out-Null
    }
    $backup.entries = @($entries)
    Save-BackupData $backup
    $SCRIPT:_backupPending.Clear()
}

function Get-BackupDataRaw {
    <#  Reads backup.json from disk without flushing the pending buffer.
        Internal use only — callers outside this module should use Get-BackupData.  #>
    if (-not (Test-Path $CFG_BackupFile)) { Initialize-Backup }
    try {
        $raw = Get-Content $CFG_BackupFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $raw.entries) { $raw | Add-Member -NotePropertyName "entries" -NotePropertyValue @() -Force }
        # Force entries to array — PS 5.1 ConvertFrom-Json unwraps single-element arrays to scalars
        $raw.entries = @($raw.entries)
        return $raw
    } catch {
        # Preserve corrupted file for recovery before overwriting
        $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $corruptPath = "$CFG_BackupFile.corrupt.$ts"
        try { Copy-Item $CFG_BackupFile $corruptPath -Force -ErrorAction Stop } catch { Write-Debug "Could not preserve corrupted backup file — original may already be gone." }
        Write-Warn "backup.json was corrupted — saved copy to $corruptPath before resetting."
        Initialize-Backup
        return [PSCustomObject]@{ entries = @(); created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    }
}

function Get-BackupData {
    <#  Returns all backup data including any pending (unflushed) entries.
        Flushes the buffer first to ensure disk and memory are consistent.  #>
    Flush-BackupBuffer
    return Get-BackupDataRaw
}

function Save-BackupData($data) {
    Save-JsonAtomic -Data $data -Path $CFG_BackupFile -Depth 10
}

function Backup-RegistryValue {
    <#  Records the current value of a registry key before modification.
        Entries are buffered in memory and flushed to disk at step boundaries
        (via Flush-BackupBuffer) to avoid O(n^2) I/O.  #>
    param([string]$Path, [string]$Name, [string]$StepTitle)
    $existing = $null
    $regType  = $null
    try {
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            $existing = $prop.$Name
            try { $regType = (Get-Item $Path).GetValueKind($Name).ToString() } catch { $regType = "DWord" }
        }
    } catch { Write-Debug "Backup-RegistryValue: could not read '$Name' from '$Path' — treating as non-existent." }

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
    $SCRIPT:_backupPending.Add($entry)
}

function Backup-ServiceState {
    <#  Records current service start type, delayed-start flag, and status before modification.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param([string]$ServiceName, [string]$StepTitle)
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
        } catch { Write-Debug "Backup-ServiceState: could not read DelayedAutostart for '$ServiceName' — defaulting to false." }
        $entry = [ordered]@{
            type              = "service"
            name              = $ServiceName
            originalStartType = $startType
            delayedAutoStart  = $delayedStart
            originalStatus    = $svc.Status.ToString()
            step              = $StepTitle
            timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $SCRIPT:_backupPending.Add($entry)
    } catch { Write-Debug "Backup-ServiceState: $ServiceName not found" }
}

function Backup-PowerPlan {
    <#  Records the currently active power plan GUID before switching.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param([string]$StepTitle)
    if ($SCRIPT:DryRun) { Write-Host "  [DRY-RUN] Would backup current power plan" -ForegroundColor Magenta; return }
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
    } catch { Write-Debug "Backup-PowerPlan: powercfg query failed — active plan GUID not captured." }

    if ($originalGuid) {
        $entry = [ordered]@{
            type          = "powerplan"
            originalGuid  = $originalGuid
            originalName  = $originalName
            step          = $StepTitle
            timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $SCRIPT:_backupPending.Add($entry)
        Write-Debug "Backup-PowerPlan: saved $originalGuid ($originalName)"
    }
}

function Backup-BootConfig {
    <#  Records current bcdedit value before modification.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param([string]$Key, [string]$StepTitle)
    $existing = $null
    try {
        $bcdOutput = bcdedit /enum "{current}" 2>&1
        foreach ($line in $bcdOutput) {
            if ($line -match "^\s*$Key\s+(.+)$") {
                $existing = $Matches[1].Trim()
                break
            }
        }
    } catch { Write-Debug "Backup-BootConfig: bcdedit enum failed for key '$Key' — treating as non-existent." }

    $entry = [ordered]@{
        type          = "bootconfig"
        key           = $Key
        originalValue = $existing
        existed       = ($null -ne $existing)
        step          = $StepTitle
        timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
}

function Backup-ScheduledTask {
    <#  Records whether a scheduled task existed and its enabled state before we modify it.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param([string]$TaskName, [string]$StepTitle, [string]$ScriptPath = "")
    $existed = $false
    $wasEnabled = $false
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $existed = ($null -ne $task)
        if ($existed) {
            $wasEnabled = ($task.State -ne "Disabled")
        }
    } catch { Write-Debug "Backup-ScheduledTask: could not query task '$TaskName' — assuming it does not exist." }

    $entry = [ordered]@{
        type       = "scheduledtask"
        taskName   = $TaskName
        existed    = $existed
        wasEnabled = $wasEnabled
        scriptPath = $ScriptPath
        step       = $StepTitle
        timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
    Write-Debug "Backup-ScheduledTask: '$TaskName' existed=$existed wasEnabled=$wasEnabled"
}

function Backup-DrsSettings {
    <#
    .SYNOPSIS  Records current NVIDIA DRS setting values before overwrite.
    .DESCRIPTION
        Reads each setting ID from the DRS profile and stores the current value
        (or null if the setting doesn't exist yet) in backup.json.
        Called from Apply-NvidiaCS2ProfileDrs before writing new values.
        Uses the in-memory buffer (flushed at step boundaries).
    #>
    param(
        [IntPtr]$Session,
        [IntPtr]$DrsProfile,
        [uint32[]]$SettingIds,
        [string]$StepTitle,
        [string]$ProfileName,
        [bool]$ProfileCreated
    )

    $settings = @()
    foreach ($id in $SettingIds) {
        [uint32]$currentValue = 0
        $status = [NvApiDrs]::GetDwordSetting($Session, $DrsProfile, $id, [ref]$currentValue)
        # Store previousValue as [double] to preserve uint32 values through JSON round-trip.
        # ConvertTo-Json/ConvertFrom-Json loses uint32 type info; values >2^31 would become
        # negative Int32 or Int64. Casting to [double] ensures lossless round-trip for all
        # uint32 values (double has 53-bit mantissa, uint32 needs only 32 bits).
        $settings += [ordered]@{
            id            = [double]$id
            previousValue = $(if ($status -eq 0) { [double]$currentValue } else { $null })
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
    $SCRIPT:_backupPending.Add($entry)
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Entry',
        Justification = 'Entry is captured by the Invoke-DrsSession scriptblock closure')]
    param($Entry)

    if (-not (Initialize-NvApiDrs)) {
        Write-Warn "Cannot restore DRS settings — nvapi64.dll unavailable (driver uninstalled or 32-bit PowerShell)."
        Write-Warn "To restore DRS settings: reinstall the NVIDIA driver, then re-run Restore."
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
                            # Cast through [double] -> [uint32] to handle JSON round-trip
                            # (ConvertFrom-Json may produce Int64 or Double for numeric values)
                            [NvApiDrs]::SetDwordSetting($session, $drsProfile, [uint32][double]$s.id, [uint32][double]$s.previousValue)
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
                            # Validate each element is in [0,255] before casting — JSON may
                            # contain Int64 values from manual editing or corruption.
                            $badValues = @($restoreValue | Where-Object { $_ -lt 0 -or $_ -gt 255 })
                            if ($badValues.Count -gt 0) {
                                Write-Warn "Binary restore for $($e.name): $($badValues.Count) byte(s) outside [0,255] — skipping (backup may be corrupted)."
                                $restoreFail++
                                continue
                            }
                            $restoreValue = [byte[]]@($restoreValue | ForEach-Object { [byte]$_ })
                        }
                        # MultiString values are deserialized as Object[] from JSON; ensure string[].
                        # PS 5.1 ConvertFrom-Json unwraps single-element arrays to scalars, so
                        # a MultiString backup with one entry arrives as a plain string — wrap it.
                        if ($restoreType -eq "MultiString") {
                            if ($null -eq $restoreValue) {
                                $restoreValue = [string[]]@()
                            } elseif ($restoreValue -is [array]) {
                                $restoreValue = [string[]]@($restoreValue)
                            } elseif ($restoreValue -is [string]) {
                                $restoreValue = [string[]]@($restoreValue)
                            }
                        }
                        # ExpandString: Set-ItemProperty -Type ExpandString is valid in PowerShell;
                        # no special handling needed — the value passes through as-is.
                        if (-not (Test-Path $e.path)) {
                            New-Item -Path $e.path -Force -ErrorAction Stop | Out-Null
                        }
                        Set-ItemProperty -Path $e.path -Name $e.name -Value $restoreValue -Type $restoreType -ErrorAction Stop
                        Write-OK "Restored: $($e.name) = $($e.originalValue)"
                    } else {
                        if (Test-Path $e.path) {
                            Remove-ItemProperty -Path $e.path -Name $e.name -ErrorAction Stop
                            Write-OK "Removed: $($e.name) (was not set before)"
                        } else {
                            Write-Debug "Restore: path '$($e.path)' no longer exists — skip remove for '$($e.name)'"
                        }
                    }
                    $restoreOk++
                }
                "service" {
                    $startMap = @{ "Auto"="Automatic"; "Manual"="Manual"; "Disabled"="Disabled"; "Auto Delayed"="AutomaticDelayedStart" }
                    $mapped = if ($startMap[$e.originalStartType]) { $startMap[$e.originalStartType] } else { $e.originalStartType }
                    # Boot/System/Unknown are kernel driver start types — Set-Service cannot change them
                    if ($e.originalStartType -in @("Boot","System","Unknown")) {
                        Write-Warn "Service $($e.name) has start type '$mapped' — cannot restore via Set-Service (kernel driver)."
                        # Don't count kernel-driver skips as successful restores
                    } else {
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
                }
                "bootconfig" {
                    if ($e.existed) {
                        $bcdOut = bcdedit /set $e.key $e.originalValue 2>&1
                        if ($LASTEXITCODE -ne 0) { Write-Warn "bcdedit restore failed for $($e.key): $bcdOut" }
                        else { Write-OK "Restored: bcdedit $($e.key) = $($e.originalValue)"; $restoreOk++ }
                    } else {
                        $bcdOut = bcdedit /deletevalue $e.key 2>&1
                        if ($LASTEXITCODE -ne 0) { Write-Warn "bcdedit deletevalue failed for $($e.key): $bcdOut" }
                        else { Write-OK "Removed: bcdedit $($e.key)"; $restoreOk++ }
                    }
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
                        # Task didn't exist before we created it — remove it entirely
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
                        # Task existed before — restore its enabled/disabled state
                        # Use wasEnabled field (added in batch buffer update) to avoid
                        # blindly re-enabling tasks that were already disabled before optimization.
                        $shouldBeEnabled = if ($null -ne $e.wasEnabled) { $e.wasEnabled } else { $true }
                        try {
                            $task = Get-ScheduledTask -TaskName $e.taskName -ErrorAction SilentlyContinue
                            if (-not $task) {
                                Write-Warn "Scheduled task '$($e.taskName)' no longer exists — cannot restore."
                            } elseif ($shouldBeEnabled -and $task.State -eq "Disabled") {
                                Enable-ScheduledTask -TaskName $e.taskName -ErrorAction Stop | Out-Null
                                Write-OK "Re-enabled scheduled task: $($e.taskName)"
                            } elseif (-not $shouldBeEnabled -and $task.State -ne "Disabled") {
                                Disable-ScheduledTask -TaskName $e.taskName -ErrorAction Stop | Out-Null
                                Write-OK "Re-disabled scheduled task: $($e.taskName) (was disabled before optimization)"
                            } else {
                                Write-Info "Scheduled task '$($e.taskName)' already in correct state — kept."
                            }
                        } catch { Write-Warn "Could not restore task $($e.taskName): $_" }
                    }
                    $restoreOk++
                }
            }
        } catch {
            $restoreFail++
            Write-Warn "Restore failed for $($e.type) $(if($e.name){$e.name}elseif($e.profile){$e.profile}elseif($e.originalName){$e.originalName}elseif($e.taskName){$e.taskName}else{$e.type}): $_"
        }
    }

    # Summary
    if ($restoreFail -gt 0) {
        Write-Warn "Restore '$StepTitle': $restoreOk succeeded, $restoreFail failed — check warnings above."
    }

    # Only remove entries when all restores succeeded — keep entries on failure so user can retry
    if ($restoreFail -eq 0) {
        $backup.entries = @($backup.entries | Where-Object { $_.step -ne $StepTitle })
        Save-BackupData $backup
    } else {
        Write-Warn "Backup entries retained for '$StepTitle' — retry restore to complete."
    }
    return ($restoreFail -eq 0)
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
    if (Test-BackupLock) {
        Write-Warn "Another CS2 Optimization process is currently running (backup.json is locked)."
        Write-Warn "Wait for it to finish, or close it manually before restoring."
        return
    }
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
