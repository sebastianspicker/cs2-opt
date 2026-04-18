function New-BackupDataObject {
    return [PSCustomObject]@{
        entries = @()
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Get-BackupVersionFiles {
    $backupDir = Split-Path $CFG_BackupFile -Parent
    $backupName = Split-Path $CFG_BackupFile -Leaf
    $backupStem = if ($backupName -match '^(.*)\.json$') { $Matches[1] } else { $backupName }
    if (-not $backupDir -or -not (Test-Path $backupDir)) { return @() }
    return @(
        Get-ChildItem $backupDir -Filter "$backupStem.*.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^$([regex]::Escape($backupStem))\.\d{8}-\d{6}\d{0,3}\.json$" } |
            Sort-Object Name
    )
}

function Prune-BackupVersions {
    $maxVersions = [Math]::Max(1, [int]$CFG_BackupMaxVersions)
    $versionFiles = @(Get-BackupVersionFiles)
    if ($versionFiles.Count -le $maxVersions) { return }

    $versionFiles |
        Select-Object -First ($versionFiles.Count - $maxVersions) |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function New-BackupFile {
    Save-JsonAtomic -Data (New-BackupDataObject) -Path $CFG_BackupFile
    Set-SecureAcl -Path $CFG_BackupFile
}

function Initialize-Backup {
    # Acquire lock before rotating or pruning so we never steal another live backup file.
    if (Test-BackupLock) {
        Write-Warn "Another CS2 Optimization window appears to be open already."
        Write-Host "  $([char]0x2139) What to do: Close the other window first, then try again." -ForegroundColor Cyan
        Write-Host "    If no other window is open, this will clear itself automatically." -ForegroundColor DarkGray
        throw "Backup lock is already held by another active CS2 Optimization process."
    }
    Set-BackupLock

    if (Test-Path $CFG_BackupFile) {
        $backupDir = Split-Path $CFG_BackupFile -Parent
        $backupName = Split-Path $CFG_BackupFile -Leaf
        $backupStem = if ($backupName -match '^(.*)\.json$') { $Matches[1] } else { $backupName }
        $stamp = (Get-Date).ToString("yyyyMMdd-HHmmssfff")
        $versionPath = Join-Path $backupDir "$backupStem.$stamp.json"
        Move-Item $CFG_BackupFile $versionPath -Force
        Prune-BackupVersions
    }
    if (-not (Test-Path $CFG_BackupFile)) { New-BackupFile } else { Set-SecureAcl -Path $CFG_BackupFile }
}

function Test-BackupLock {
    <#  Checks if another process is actively modifying backup.json.
        Returns $true if the lock is held (and the holding process is still alive).
        Stale locks are automatically cleaned up in three cases:
          1. The locking process is no longer running (crashed/exited).
          2. The PID was reused by a non-PowerShell process.
          3. The lock is older than 4 hours (handles hung/stalled processes).
        Mitigates PID reuse: verifies the process is PowerShell, not an unrelated
        process that inherited the recycled PID.  #>
    if (-not (Test-Path $CFG_BackupLockFile)) { return $false }
    try {
        $lockData = Get-Content $CFG_BackupLockFile -Raw -ErrorAction Stop | ConvertFrom-Json
        # Auto-expire: no optimization run should take more than 4 hours.
        # Handles the case where a process is alive but hung/stalled indefinitely.
        if ($lockData.started) {
            try {
                $parsedDate = [datetime]::Parse([string]$lockData.started)
            } catch {
                Write-DebugLog "Backup lock has unparseable timestamp '$($lockData.started)' — removing stale lock."
                Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
                return $false
            }
            $lockAge = (Get-Date) - $parsedDate
            if ($lockAge.TotalHours -gt 4) {
                Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
                Write-DebugLog "Removed expired backup lock (age: $([math]::Round($lockAge.TotalHours, 1))h, PID $($lockData.pid))."
                return $false
            }
        }
        $proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
        if ($proc) {
            # Mitigate PID reuse: Windows recycles PIDs, so a live process with the
            # same PID may be entirely unrelated. Verify it's a PowerShell instance.
            $isPowerShell = $proc.ProcessName -match '^(?:powershell|pwsh|powershell_ise)$'
            if ($isPowerShell) { return $true }
            # PID was reused by a non-PowerShell process — stale lock
            Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
            Write-DebugLog "Removed stale backup lock (PID $($lockData.pid) reused by '$($proc.ProcessName)')."
            return $false
        }
        # Process is dead — stale lock; remove it
        Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
        Write-DebugLog "Removed stale backup lock (PID $($lockData.pid) no longer running)."
    } catch {
        # Corrupted lock file — remove it
        Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
    }
    return $false
}

function Set-BackupLock {
    <#  Called at the start of optimization and restore operations.  #>
    $lockData = @{ pid = $PID; started = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    Save-JsonAtomic -Data $lockData -Path $CFG_BackupLockFile
}

function Remove-BackupLock {
    Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue
}

function Flush-BackupBuffer {
    <#  Writes any pending in-memory backup entries to backup.json in a single I/O pass.
        Safe to call multiple times — no-op when the buffer is empty.
        On failure: entries stay in memory (Clear runs AFTER Save) for the next flush attempt.
        If the process crashes before any flush, that step's backups are lost — acceptable
        tradeoff vs. O(n^2) I/O from flushing on every Set-RegistryValue call.  #>
    if ($SCRIPT:_backupPending.Count -eq 0) { return }
    $backup = Get-BackupDataRaw
    $entries = [System.Collections.ArrayList]@($backup.entries)
    foreach ($e in $SCRIPT:_backupPending) {
        # Deduplicate: skip if an entry for the same key already exists (prevents
        # duplicate backups on re-run — the first backup holds the true original value)
        $isDupe = $false
        foreach ($existing in $entries) {
            if ($existing.step -eq $e.step -and $existing.type -eq $e.type) {
                switch ($e.type) {
                    "registry"      { $isDupe = ($existing.PSObject.Properties['path'] -and $e.Contains('path') -and $existing.path -eq $e.path -and $existing.name -eq $e.name) }
                    "service"       { $isDupe = ($existing.name -eq $e.name) }
                    "scheduledtask" { $isDupe = ($existing.PSObject.Properties['taskName'] -and $e.Contains('taskName') -and $existing.taskName -eq $e.taskName) }
                    "bootconfig"    { $isDupe = ($existing.PSObject.Properties['key'] -and $e.Contains('key') -and $existing.key -eq $e.key) }
                    "powerplan"     { $isDupe = ($existing.PSObject.Properties['originalGuid'] -and $e.Contains('originalGuid') -and $existing.originalGuid -eq $e.originalGuid) }
                    "nic_adapter"   { $isDupe = ($existing.PSObject.Properties['adapterName'] -and $e.Contains('adapterName') -and $existing.adapterName -eq $e.adapterName -and $existing.propertyName -eq $e.propertyName) }
                    "dns"           { $isDupe = ($existing.PSObject.Properties['adapterName'] -and $e.Contains('adapterName') -and $existing.adapterName -eq $e.adapterName) }
                    default         { $isDupe = $false }
                }
                if ($isDupe) { break }
            }
        }
        if (-not $isDupe) { $entries.Add($e) | Out-Null }
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
        $backupDir = Split-Path $CFG_BackupFile -Parent
        $backupName = Split-Path $CFG_BackupFile -Leaf
        $backupStem = if ($backupName -match '^(.*)\.json$') { $Matches[1] } else { $backupName }
        $corruptPath = Join-Path $backupDir "$backupStem.corrupt.$ts.json"
        try { Copy-Item $CFG_BackupFile $corruptPath -Force -ErrorAction Stop } catch { Write-DebugLog "Could not preserve corrupted backup file — original may already be gone." }
        Write-Warn "backup.json was corrupted — saved copy to $corruptPath before resetting."
        Write-Warn "Backup history reset — previous entries preserved in $corruptPath"
        Remove-Item $CFG_BackupFile -Force -ErrorAction SilentlyContinue
        New-BackupFile
        return (New-BackupDataObject)
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
    Set-SecureAcl -Path $CFG_BackupFile
}

