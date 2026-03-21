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
            Write-Debug "No $($dc.Label) devices found in class $($dc.Class)."
            continue
        }

        foreach ($dev in $devices) {
            # Skip virtual and software devices
            if ($dev.InstanceId -notmatch "^PCI\\") { continue }

            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)"
            $msiPath = "$regBase\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"

            try {
                if (-not $SCRIPT:DryRun) {
                    if (-not (Test-Path $msiPath)) {
                        New-Item -Path $msiPath -Force | Out-Null
                    }
                    # Backup before modifying
                    if ($SCRIPT:CurrentStepTitle) {
                        Backup-RegistryValue -Path $msiPath -Name "MSISupported" -StepTitle $SCRIPT:CurrentStepTitle
                        if ($dc.MsiLimit -gt 0) {
                            Backup-RegistryValue -Path $msiPath -Name "MessageNumberLimit" -StepTitle $SCRIPT:CurrentStepTitle
                        }
                    }
                    Set-ItemProperty -Path $msiPath -Name "MSISupported" -Value 1 -Type DWord -ErrorAction Stop

                    # Set MSI vector count limit for GPU (16 vectors = full multi-queue support)
                    if ($dc.MsiLimit -gt 0) {
                        Set-ItemProperty -Path $msiPath -Name "MessageNumberLimit" -Value $dc.MsiLimit -Type DWord -ErrorAction Stop
                    }

                    Write-OK "$($dc.Label) MSI enabled: $($dev.FriendlyName)"
                    $modified++
                } else {
                    Write-Host "  [DRY-RUN] Would enable MSI for $($dc.Label): $($dev.FriendlyName)" -ForegroundColor Magenta
                    if ($dc.MsiLimit -gt 0) {
                        Write-Host "  [DRY-RUN]   MessageNumberLimit = $($dc.MsiLimit)" -ForegroundColor DarkMagenta
                    }
                    $modified++
                }
            } catch {
                Write-Warn "Could not set MSI for $($dev.FriendlyName): $_"
            }
        }
    }

    if ($modified -eq 0) {
        Write-Warn "No PCI devices found to enable MSI."
    } elseif ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would set $modified device(s) to MSI mode." -ForegroundColor Magenta
    } else {
        Write-OK "$modified devices set to MSI mode."
        Write-Info "Restart required for MSI changes to take effect."
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

        foreach ($key in $subkeys) {
            $desc = (Get-ItemProperty $key.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
            if ($desc -and ($desc -eq $nic.InterfaceDescription -or
                            $nic.InterfaceDescription -like "*$desc*" -or
                            $desc -like "*$($nic.InterfaceDescription)*")) {
                $driverKey = $key.PSPath
                break
            }
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

    # Match PnP device for registry path
    $nic = Get-PnpDevice -Class Net -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "^PCI\\" -and $_.FriendlyName -eq $activeNic.InterfaceDescription }

    if (-not $nic) {
        # Fallback: try matching by description substring
        $nic = Get-PnpDevice -Class Net -Status OK -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match "^PCI\\" -and $activeNic.InterfaceDescription -like "*$($_.FriendlyName)*" } |
            Select-Object -First 1
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

    # Calculate affinity mask for last physical core
    # Core 0 = bit 0, Core 1 = bit 1, etc.
    # We want the last physical core to avoid Core 0 (OS-heavy)
    # Clamp to 63 — processor group 0 supports max 64 logical processors;
    # systems with >64 LPs require GROUP_AFFINITY which needs a different API.
    $targetCore = [math]::Min($coreCount - 1, 63)
    $mask = [uint64]1 -shl $targetCore

    # Convert mask to 8-byte array for registry (binary value)
    $maskBytes = [BitConverter]::GetBytes([uint64]$mask)

    $regBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($nic.InstanceId)"
    $affinityPath = "$regBase\Device Parameters\Interrupt Management\Affinity Policy"

    try {
        if (-not $SCRIPT:DryRun) {
            if (-not (Test-Path $affinityPath)) {
                New-Item -Path $affinityPath -Force | Out-Null
            }

            # Backup before modifying
            if ($SCRIPT:CurrentStepTitle) {
                Backup-RegistryValue -Path $affinityPath -Name "DevicePolicy" -StepTitle $SCRIPT:CurrentStepTitle
                Backup-RegistryValue -Path $affinityPath -Name "AssignmentSetOverride" -StepTitle $SCRIPT:CurrentStepTitle
            }

            # DevicePolicy = 4 means "Specified Processors"
            Set-ItemProperty -Path $affinityPath -Name "DevicePolicy" -Value 4 -Type DWord -ErrorAction Stop
            Set-ItemProperty -Path $affinityPath -Name "AssignmentSetOverride" -Value ([byte[]]$maskBytes) -Type Binary -ErrorAction Stop

            Write-OK "NIC affinity set: $($nic.FriendlyName) -> Core $targetCore"
            Write-Info "Affinity mask: 0x$($mask.ToString('X')) (Core $targetCore of $coreCount)"
        } else {
            Write-Host "  [DRY-RUN] Would set NIC affinity: $($nic.FriendlyName) -> Core $targetCore (mask 0x$($mask.ToString('X')))" -ForegroundColor Magenta
        }
    } catch {
        Write-Warn "Could not set affinity for $($nic.FriendlyName): $_"
    }

    Write-Info "Restart required for affinity changes to take effect."
}
