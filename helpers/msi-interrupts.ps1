# ==============================================================================
#  helpers/msi-interrupts.ps1  —  MSI Interrupts + NIC Interrupt Affinity
# ==============================================================================

function Enable-DeviceMSI {
    <#
    .SYNOPSIS  Enables Message Signaled Interrupts (MSI) for GPU, NIC, and Audio
               devices via direct registry writes. Replaces MSI Utility v3.
    #>

    Write-Step "Enabling MSI interrupts for PCI devices..."

    $deviceClasses = @(
        @{ Class = "Display";       Label = "GPU";     MsiLimit = 16 },  # 16 MSI vectors for GPU
        @{ Class = "Net";           Label = "NIC";     MsiLimit = 0  },  # Default (no vector limit)
        @{ Class = "Media";        Label = "Audio";   MsiLimit = 0  }   # Default (no vector limit)
    )

    $modified = 0
    foreach ($dc in $deviceClasses) {
        $devices = Get-PnpDevice -Class $dc.Class -Status OK -ErrorAction SilentlyContinue
        if (-not $devices) {
            Write-Warn "No $($dc.Label) devices found in class $($dc.Class) — skipping."
            continue
        }

        foreach ($dev in $devices) {
            # Skip virtual and software devices
            if ($dev.InstanceId -notmatch "^PCI\\") { continue }

            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)"
            $msiPath = "$regBase\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"

            # Route through Set-RegistryValue for consistent DRY-RUN interception and auto-backup
            Set-RegistryValue $msiPath "MSISupported" 1 "DWord" `
                "MSI enabled for $($dc.Label): $($dev.FriendlyName)"

            # Set MSI vector count limit for GPU (16 vectors = full multi-queue support)
            if ($dc.MsiLimit -gt 0) {
                Set-RegistryValue $msiPath "MessageNumberLimit" $dc.MsiLimit "DWord" `
                    "MSI vector limit ($($dc.MsiLimit)) for $($dc.Label): $($dev.FriendlyName)"
            }

            $modified++
        }
    }

    if ($modified -eq 0) {
        Write-Warn "No PCI devices found to enable MSI."
    } else {
        Write-OK "$modified device(s) configured for MSI mode."
        if (-not $SCRIPT:DryRun) {
            Write-Info "Restart required for MSI changes to take effect."
        }
    }
}

function Set-NicRssConfig {
    <#
    .SYNOPSIS  Adds missing RSS (Receive Side Scaling) registry entries to NIC driver key.
    .DESCRIPTION
        Many NIC drivers — notably Intel I225-V and I226-V (shipped as the onboard NIC on
        most Ryzen 5000/7000 and Intel 12th+ gen boards) — omit RSS indirection table
        registry entries. Without them, all receive-side interrupt processing defaults to
        Core 0. When Core 0 is also handling game threads, NIC DPCs contend with them,
        producing irregular packet delivery timing (jitter).

        This function adds *RSSProfile, *RssBaseProcNumber, *MaxRssProcessors, *NumRssQueues
        ONLY if they are absent from the driver key. Existing values are never overwritten
        (respects manual or driver-written configuration).

        Source: djdallmann/GamingPCSetup — "many vendor drivers omit these entries;
        Intel I219-V missing these by default; notable NDIS DPC latency improvements
        vs. default Core 0 allocation."
    #>

    Write-Step "Configuring NIC RSS (Receive Side Scaling) distribution..."

    $nic = Get-ActiveNicAdapter

    if (-not $nic) {
        Write-Warn "RSS: no active wired NIC found — skipping."
        return
    }

    # Locate the NIC's driver subkey under the Network class GUID.
    # Each installed NIC driver is registered as a numbered subkey (0000, 0001, ...)
    # under HKLM:\...\Control\Class\{4d36e972-...}. DriverDesc matches the adapter
    # description reported by Get-NetAdapter.
    $classPath    = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$CFG_GUID_Network"
    $driverKey    = $null

    try {
        $subkeys = Get-ChildItem $classPath -ErrorAction Stop |
            Where-Object { $_.PSChildName -match "^\d{4}$" }

        # Prefer exact match, fallback to substring only if no exact match found
        $substringMatch = $null
        foreach ($key in $subkeys) {
            $desc = (Get-ItemProperty $key.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
            if ($desc -and $desc -eq $nic.InterfaceDescription) {
                $driverKey = $key.PSPath
                break
            }
            if (-not $substringMatch -and $desc -and (
                $nic.InterfaceDescription -like "*$desc*" -or
                $desc -like "*$($nic.InterfaceDescription)*")) {
                $substringMatch = $key.PSPath
            }
        }
        if (-not $driverKey -and $substringMatch) {
            $driverKey = $substringMatch
            Write-Debug "RSS: using substring match for NIC driver key (no exact match found)"
        }
    } catch {
        Write-Warn "RSS: could not enumerate network class keys: $_"
        return
    }

    if (-not $driverKey) {
        Write-Warn "RSS: driver registry key not found for '$($nic.InterfaceDescription)' — skipping."
        return
    }

    Write-Info "RSS NIC: $($nic.InterfaceDescription)"

    # RSS entries and their rationale:
    #
    #   *RSSProfile = 1 (ClosestProcessor)
    #     Each RSS queue is processed on the CPU whose cache is closest to where the NIC
    #     DMA-landed the packet data. On single-NUMA desktop systems this minimises
    #     cross-core cache misses. Value 2 (ClosestProcessorStatic) gives fixed assignment
    #     which may be more predictable; 1 is appropriate for most gaming systems.
    #
    #   *RssBaseProcNumber = 2
    #     First logical processor to assign RSS queues to. Core 0 handles the majority of
    #     OS interrupt bookkeeping; Core 1 is its HT/SMT sibling on most CPUs. Starting
    #     at Core 2 keeps NIC DPCs off the most-contended cores.
    #
    #   *MaxRssProcessors = 4
    #     Upper bound on how many processors RSS will spread queues across. 4 covers all
    #     gaming scenarios; beyond 4 provides no benefit for CS2's ~128 pkt/s rate.
    #
    #   *NumRssQueues = 4
    #     Explicit queue count matching MaxRssProcessors. Without this, drivers may default
    #     to 1 queue regardless of the processor count setting.
    #
    $rssDefaults = [ordered]@{
        "*RSSProfile"        = @{ Value = 1; Type = "DWord";
            Note = "ClosestProcessor: NIC DPCs on cache-local core" }
        "*RssBaseProcNumber" = @{ Value = 2; Type = "DWord";
            Note = "Start RSS from Core 2 — avoids Core 0/1 OS overhead" }
        "*MaxRssProcessors"  = @{ Value = 4; Type = "DWord";
            Note = "Cap RSS spread at 4 processors" }
        "*NumRssQueues"      = @{ Value = 4; Type = "DWord";
            Note = "4 RSS queues matching processor cap" }
    }

    $added   = 0
    $skipped = 0

    foreach ($entry in $rssDefaults.GetEnumerator()) {
        $existing = Get-ItemProperty $driverKey -Name $entry.Key -ErrorAction SilentlyContinue
        if ($null -ne $existing.($entry.Key)) {
            Write-Sub "$($entry.Key) = $($existing.($entry.Key)) (already set — preserved)"
            $skipped++
        } else {
            Set-RegistryValue $driverKey $entry.Key $entry.Value.Value $entry.Value.Type $entry.Value.Note
            $added++
        }
    }

    if ($added -gt 0) {
        Write-OK "RSS: added $added missing entries ($skipped existing preserved). Restart required."
        Write-Info "Effect: NIC receive DPCs distributed away from Core 0."
        # Flag Intel I225-V/I226-V specifically — these are the most commonly affected NICs
        if ($nic.InterfaceDescription -match "I225|I226|I219") {
            Write-Info "Intel $($Matches[0]) detected — this NIC is known to omit RSS entries by default."
        }
    } else {
        Write-OK "RSS: all $skipped entries already present — no changes needed."
    }
}

function Set-NicInterruptAffinity {
    <#
    .SYNOPSIS  Sets NIC interrupt affinity to last physical core (avoids Core 0).
               Replaces GoInterruptPolicy for NIC interrupt binding.
    #>

    Write-Step "Setting NIC interrupt affinity..."

    # Use the active wired adapter (consistent with Set-NicRssConfig)
    $activeNic = Get-ActiveNicAdapter
    if (-not $activeNic) {
        Write-Warn "No active wired NIC found — skipping affinity."
        return
    }

    # Match PnP device for registry path.
    # NIC FriendlyName may include an instance suffix (e.g., "Intel I226-V #2") that
    # differs from InterfaceDescription. Try exact match first, then substring match
    # in both directions, then match by PCI hardware path segment as last resort.
    $friendlyName = $activeNic.InterfaceDescription
    $allPciNics = @(Get-PnpDevice -Class Net -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "^PCI\\" })

    # Strategy 1: Exact match
    $nic = $allPciNics | Where-Object { $_.FriendlyName -eq $friendlyName } | Select-Object -First 1

    if (-not $nic) {
        # Strategy 2: Substring match (either direction) — handles instance suffixes like "#2"
        $nic = $allPciNics |
            Where-Object { $friendlyName -like "*$($_.FriendlyName)*" -or $_.FriendlyName -like "*$friendlyName*" } |
            Select-Object -First 1
    }

    if (-not $nic) {
        # Strategy 3: Match by PCI hardware path segment — extracts VEN/DEV from InstanceId
        # and compares against the active NIC's PnP device ID (most reliable for multi-instance NICs)
        try {
            $activeHwId = (Get-NetAdapter -Name $activeNic.Name -ErrorAction SilentlyContinue).PnpDeviceID
            if ($activeHwId) {
                $nic = $allPciNics |
                    Where-Object { $activeHwId -eq $_.InstanceId } |
                    Select-Object -First 1
            }
        } catch { Write-Debug "PCI path matching failed for NIC affinity: $_" }
    }

    if (-not $nic) {
        Write-Warn "Active NIC '$($activeNic.InterfaceDescription)' not found as PCI device — skipping affinity."
        return
    }

    # Ensure single device (not array)
    if ($nic -is [array]) { $nic = $nic | Select-Object -First 1 }

    # Get physical core count (need physical, not logical, for correct core targeting)
    try {
        $coreCount = (Get-CimInstance Win32_Processor | Select-Object -First 1).NumberOfCores
    } catch {
        # Fallback: use logical count directly (safer than assuming SMT factor)
        $logicalCount = [Environment]::ProcessorCount
        $coreCount = [math]::Max(2, $logicalCount)
        Write-Debug "CIM failed — using $coreCount logical processors as core count"
    }

    if ($coreCount -lt 2) {
        Write-Warn "Only 1 core detected — cannot set affinity away from Core 0."
        return
    }

    # Calculate affinity mask for target core.
    # On hybrid CPUs (Intel 12th+), NIC interrupts should target an E-core
    # (efficiency core) to avoid contending with game threads on P-cores.
    # E-cores are typically the last physical cores in the topology.
    # On non-hybrid CPUs, use the last physical core to avoid Core 0 (OS-heavy).
    # Clamp to 63 — processor group 0 supports max 64 logical processors;
    # systems with >64 LPs require GROUP_AFFINITY which needs a different API.
    $hybridCpu = Get-IntelHybridCpuName
    if ($hybridCpu) {
        # Intel hybrid: target last core (E-core region)
        $targetCore = [math]::Min($coreCount - 1, 63)
        Write-Debug "Hybrid CPU detected ($hybridCpu) — targeting E-core region (Core $targetCore)"
    } else {
        # Non-hybrid: use last physical core to avoid Core 0
        $targetCore = [math]::Min($coreCount - 1, 63)
    }
    $mask = [uint64]1 -shl $targetCore

    # Convert mask to 8-byte array for registry (binary value)
    $maskBytes = [BitConverter]::GetBytes([uint64]$mask)

    $regBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($nic.InstanceId)"
    $affinityPath = "$regBase\Device Parameters\Interrupt Management\Affinity Policy"

    # Route DevicePolicy through Set-RegistryValue for consistent DRY-RUN/backup handling
    Set-RegistryValue $affinityPath "DevicePolicy" 4 "DWord" `
        "NIC interrupt affinity policy (Specified Processors): $($nic.FriendlyName)"

    # AssignmentSetOverride is Binary — Set-RegistryValue supports this via -Type passthrough
    Set-RegistryValue $affinityPath "AssignmentSetOverride" ([byte[]]$maskBytes) "Binary" `
        "NIC affinity mask 0x$($mask.ToString('X')) -> Core ${targetCore}: $($nic.FriendlyName)"

    if (-not $SCRIPT:DryRun) {
        Write-OK "NIC affinity set: $($nic.FriendlyName) -> Core $targetCore"
        Write-Info "Affinity mask: 0x$($mask.ToString('X')) (Core $targetCore of $coreCount)"
    }
    Write-Info "Restart required for affinity changes to take effect."
}
