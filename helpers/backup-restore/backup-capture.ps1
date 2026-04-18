function Backup-RegistryValue {
    <#  Records the current value of a registry key before modification.
        Entries are buffered in memory and flushed to disk at step boundaries
        (via Flush-BackupBuffer) to avoid O(n^2) I/O.  #>
    [CmdletBinding()]
    param([string]$Path, [string]$Name, [string]$StepTitle)
    if ($SCRIPT:DryRun) { return }
    $existing = $null
    $regType  = $null
    try {
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            $existing = $prop.$Name
            try {
                $regType = (Get-Item $Path).GetValueKind($Name).ToString()
            } catch {
                # Fallback: autostart \Run keys store command-line strings, not DWords.
                # Default to "String" for Run paths, "DWord" otherwise.
                $regType = if ($Path -match '\\Run$' -or $Path -match '\\Run\\') { "String" } else { "DWord" }
            }
        }
    } catch { Write-DebugLog "Backup-RegistryValue: could not read '$Name' from '$Path' — treating as non-existent." }

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
    if ($SCRIPT:DryRun) { return }
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        $escapedName = $ServiceName -replace "'", "''"
        $startType = (Get-CimInstance Win32_Service -Filter "Name='$escapedName'" -ErrorAction Stop).StartMode
        # Capture DelayedAutoStart flag — services with "Automatic (Delayed Start)" show StartMode=Auto
        # but have a separate registry flag. Without this, restore loses the "Delayed" qualifier.
        $delayedStart = $false
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
            $delayReg = Get-ItemProperty -Path $regPath -Name "DelayedAutostart" -ErrorAction SilentlyContinue
            $delayedStart = ($delayReg.DelayedAutostart -eq 1)
        } catch { Write-DebugLog "Backup-ServiceState: could not read DelayedAutostart for '$ServiceName' — defaulting to false." }
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
    } catch { Write-DebugLog "Backup-ServiceState: $ServiceName not found" }
}

function Backup-PowerPlan {
    <#  Records the currently active power plan GUID before switching.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param([string]$StepTitle)
    if ($SCRIPT:DryRun) { return }
    $originalGuid = $null
    $originalName = $null
    try {
        $activeOutput = powercfg /getactivescheme 2>&1
        if ($activeOutput -match "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})") {
            $originalGuid = $Matches[1]
            if ($activeOutput -match "\((.+)\)\s*$") {
                $originalName = $Matches[1]
            }
        }
    } catch { Write-DebugLog "Backup-PowerPlan: powercfg query failed — active plan GUID not captured." }

    if ($originalGuid) {
        # If the active plan is already "CS2 Optimized", skip backup — we don't want
        # to record the CS2 plan as the rollback target on re-runs. The original
        # user plan is already captured from the first run.
        if ($originalName -and $originalName -match "CS2 Optimized") {
            Write-DebugLog "Backup-PowerPlan: active plan is '$originalName' — skipping backup (re-run detected)"
            return
        }
        $entry = [ordered]@{
            type          = "powerplan"
            originalGuid  = $originalGuid
            originalName  = $originalName
            step          = $StepTitle
            timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $SCRIPT:_backupPending.Add($entry)
        Write-DebugLog "Backup-PowerPlan: saved $originalGuid ($originalName)"
    }
}

function Backup-BootConfig {
    <#  Records current bcdedit value before modification.
        Entries are buffered in memory and flushed at step boundaries.
        Uses bcdedit /v to get raw BCD element names (hex IDs), which are locale-independent.
        Without /v, key names like "safeboot" are localized (e.g., German: "Abgesicherter Start")
        and the English key name match would fail on non-English Windows.  #>
    [CmdletBinding()]
    param([string]$Key, [string]$StepTitle)
    if ($SCRIPT:DryRun) { return }

    # Map well-known bcdedit key names to their raw BCD element hex IDs.
    # bcdedit /enum /v outputs hex IDs instead of localized names.
    # Reference: Microsoft BCD WMI Provider documentation.
    $bcdElementMap = @{
        "safeboot"           = "0x26000081"
        "disabledynamictick" = "0x26000060"  # BcdOSLoaderBoolean_DisableDynamicTick
        "useplatformtick"    = "0x26000092"  # BcdOSLoaderBoolean_UsePlatformTick
        "useplatformclock"   = "0x26000091"  # BcdOSLoaderBoolean_UseLegacyApicTimer
    }
    $hexId = if ($bcdElementMap.ContainsKey($Key)) { $bcdElementMap[$Key] } else { $null }

    $existing = $null
    try {
        $bcdOutput = bcdedit /enum "{current}" /v 2>&1
        foreach ($line in $bcdOutput) {
            # Try hex ID match first (locale-independent), fall back to key name
            if ($hexId -and $line -match "^\s*$hexId\s+(.+)$") {
                $existing = $Matches[1].Trim()
                break
            } elseif (-not $hexId -and $line -match "^\s*$([regex]::Escape($Key))\s+(.+)$") {
                $existing = $Matches[1].Trim()
                break
            }
        }
    } catch { Write-DebugLog "Backup-BootConfig: bcdedit enum failed for key '$Key' — treating as non-existent." }

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
    if ($SCRIPT:DryRun) { return }
    $existed = $false
    $wasEnabled = $false
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $existed = ($null -ne $task)
        if ($existed) {
            $wasEnabled = ($task.State -ne "Disabled")
        }
    } catch { Write-DebugLog "Backup-ScheduledTask: could not query task '$TaskName' — assuming it does not exist." }

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
    Write-DebugLog "Backup-ScheduledTask: '$TaskName' existed=$existed wasEnabled=$wasEnabled"
}

function Backup-NicAdapterProperty {
    <#  Records the current value of a NIC adapter property before modification.
        Entries are buffered in memory and flushed at step boundaries.
        PropertyType is "DisplayName" for Set-NetAdapterAdvancedProperty -DisplayName
        or "RegistryKeyword" for -RegistryKeyword calls.  #>
    param(
        [string]$AdapterName,
        [string]$PropertyName,
        [string]$OriginalValue,
        [string]$PropertyType,
        [string]$StepTitle
    )
    if ($SCRIPT:DryRun) { return }
    # Capture InterfaceDescription for cross-adapter detection on restore
    $ifDesc = ""
    try {
        $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($adapter) { $ifDesc = $adapter.InterfaceDescription }
    } catch { Write-DebugLog "Backup-NicAdapterProperty: could not resolve InterfaceDescription for '$AdapterName'" }
    $entry = [ordered]@{
        type                 = "nic_adapter"
        adapterName          = $AdapterName
        interfaceDescription = $ifDesc
        propertyName         = $PropertyName
        originalValue        = $OriginalValue
        propertyType         = $PropertyType
        step                 = $StepTitle
        timestamp            = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
    Write-DebugLog "Backup-NicAdapterProperty: '$PropertyName' = '$OriginalValue' on '$AdapterName' ($ifDesc)"
}

function Backup-QosAndUro {
    <#  Records existing QoS policy names and URO state before modification.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param(
        [string[]]$PolicyNames,
        [string]$UroState,
        [string]$StepTitle
    )
    if ($SCRIPT:DryRun) { return }
    $entry = [ordered]@{
        type        = "qos_uro"
        policies    = $PolicyNames
        uroState    = $UroState
        step        = $StepTitle
        timestamp   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
    Write-DebugLog "Backup-QosAndUro: policies=[$($PolicyNames -join ', ')] uro=$UroState"
}

function Backup-DefenderExclusions {
    <#  Records Defender exclusion paths and processes added by this tool.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param(
        [string[]]$ExclusionPaths,
        [string[]]$ExclusionProcesses,
        [string]$StepTitle
    )
    if ($SCRIPT:DryRun) { return }
    $entry = [ordered]@{
        type               = "defender"
        exclusionPaths     = $ExclusionPaths
        exclusionProcesses = $ExclusionProcesses
        step               = $StepTitle
        timestamp          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
    Write-DebugLog "Backup-DefenderExclusions: $($ExclusionPaths.Count) paths, $($ExclusionProcesses.Count) processes"
}

function Backup-PagefileConfig {
    <#  Records current pagefile configuration before modification.
        Entries are buffered in memory and flushed at step boundaries.
        Manual restoration: System Properties -> Advanced -> Performance -> Virtual Memory  #>
    param(
        [bool]$AutomaticManaged,
        [string]$PagefilePath,
        [int]$InitialSize,
        [int]$MaximumSize,
        [string]$StepTitle
    )
    if ($SCRIPT:DryRun) { return }
    $entry = [ordered]@{
        type              = "pagefile"
        automaticManaged  = $AutomaticManaged
        pagefilePath      = $PagefilePath
        initialSize       = $InitialSize
        maximumSize       = $MaximumSize
        step              = $StepTitle
        timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
    Write-DebugLog "Backup-PagefileConfig: auto=$AutomaticManaged path=$PagefilePath init=$InitialSize max=$MaximumSize"
}

function Backup-DnsConfig {
    <#  Records current DNS server addresses before modification.
        Entries are buffered in memory and flushed at step boundaries.  #>
    param(
        [string]$AdapterName,
        [int]$InterfaceIndex,
        [string[]]$OriginalDnsServers,
        [string]$StepTitle
    )
    if ($SCRIPT:DryRun) { return }
    $entry = [ordered]@{
        type               = "dns"
        adapterName        = $AdapterName
        interfaceIndex     = $InterfaceIndex
        originalDnsServers = $OriginalDnsServers
        step               = $StepTitle
        timestamp          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $SCRIPT:_backupPending.Add($entry)
    Write-DebugLog "Backup-DnsConfig: adapter=$AdapterName dns=[$($OriginalDnsServers -join ', ')]"
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
    if ($SCRIPT:DryRun) { return }

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
    Write-DebugLog "Backup-DrsSettings: saved $($SettingIds.Count) DRS settings for '$StepTitle'"
}

