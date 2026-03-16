# ==============================================================================
#  helpers/gpu-driver-clean.ps1  —  Safe Mode GPU Driver Removal (DDU replacement)
# ==============================================================================

function Remove-GpuDriverClean {
    <#
    .SYNOPSIS  Removes GPU drivers cleanly in Safe Mode. Pure PowerShell replacement
               for Display Driver Uninstaller (DDU).
    .DESCRIPTION
        1. Stops and disables GPU-related services
        2. Removes GPU driver packages via pnputil
        3. Cleans GPU registry entries
        4. Removes DriverStore orphans
        5. Cleans shader caches and temp folders
    #>
    param(
        [ValidateSet("NVIDIA","AMD","Intel")]
        [string]$GpuVendor = "NVIDIA"
    )

    Write-Step "GPU Driver Clean Removal — $GpuVendor"
    Write-Info "This replaces DDU with native PowerShell commands."

    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would perform complete GPU driver removal for $GpuVendor" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   1. Stop + disable GPU services" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   2. Remove driver packages via pnputil" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   3. Clean GPU class registry keys" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   4. Remove DriverStore orphan folders" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   5. Clean shader caches" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN] No files or registry entries will be modified." -ForegroundColor Magenta
        return
    }

    # ── 1. Stop and Disable GPU Services ─────────────────────────────────────
    Write-Step "Stopping $GpuVendor services..."

    $servicePatterns = switch ($GpuVendor) {
        "NVIDIA" { @(
            "NVDisplay.ContainerLocalSystem",
            "NvTelemetryContainer",
            "NvContainerNetworkService",
            "NvContainerLocalSystem",
            "NVDisplay*",
            "nvsvc"
        )}
        "AMD" { @(
            "AMD External Events Utility",
            "AMDRyzenMasterDriverV*",
            "amdlog",
            "amdfendr*"
        )}
        "Intel" { @(
            "igfxCUIService*",
            "IntelGraphicsControlPanel*"
        )}
    }

    foreach ($pattern in $servicePatterns) {
        $services = Get-Service -Name $pattern -ErrorAction SilentlyContinue
        foreach ($svc in $services) {
            try {
                Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-OK "Stopped + disabled: $($svc.Name)"
            } catch {
                Write-Debug "Service $($svc.Name): $_"
            }
        }
    }

    # ── 2. Remove GPU Driver Packages via pnputil ────────────────────────────
    Write-Step "Enumerating GPU driver packages..."

    $vendorMatch = switch ($GpuVendor) {
        "NVIDIA" { "nvidia|nv_dispi|nvd" }
        "AMD"    { "amd|ati|radeon" }
        "Intel"  { "igfx|iigd|intel.*graphics" }
    }

    # Parse pnputil output to find display driver packages
    $pnpOutput = pnputil /enum-drivers 2>$null
    $driverPackages = @()
    $currentInf = $null
    $currentClass = $null
    $currentProvider = $null

    foreach ($line in $pnpOutput) {
        if ($line -match "Published Name\s*:\s*(oem\d+\.inf)") {
            $currentInf = $Matches[1]
        }
        if ($line -match "Class Name\s*:\s*(.+)") {
            $currentClass = $Matches[1].Trim()
        }
        if ($line -match "Driver Package Provider\s*:\s*(.+)") {
            $currentProvider = $Matches[1].Trim()
        }
        # When we hit an empty line or end, check if it's a display driver from our vendor
        if (($line.Trim() -eq "" -or $line -match "^$") -and $currentInf) {
            if ($currentClass -match "Display|display" -and $currentProvider -match $vendorMatch) {
                $driverPackages += $currentInf
            }
            $currentInf = $null
            $currentClass = $null
            $currentProvider = $null
        }
    }
    # Check last entry
    if ($currentInf -and $currentClass -match "Display|display" -and $currentProvider -match $vendorMatch) {
        $driverPackages += $currentInf
    }

    $removedDrivers = 0
    foreach ($inf in $driverPackages) {
        Write-Step "Removing driver package: $inf"
        try {
            $result = pnputil /delete-driver $inf /uninstall /force 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Removed: $inf"
                $removedDrivers++
            } else {
                Write-Warn "Could not remove $inf (may be in use): $result"
            }
        } catch {
            Write-Warn "Error removing $inf`: $_"
        }
    }
    Write-Info "$removedDrivers driver package(s) removed."

    # ── 3. Clean GPU Class Registry ──────────────────────────────────────────
    Write-Step "Cleaning GPU registry entries..."

    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$CFG_GUID_Display"

    if (Test-Path $classPath) {
        $subkeys = Get-ChildItem $classPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match "^\d{4}$" }

        foreach ($key in $subkeys) {
            try {
                $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
                $match = switch ($GpuVendor) {
                    "NVIDIA" { $props.ProviderName -match "NVIDIA" -or $props.DriverDesc -match "NVIDIA" }
                    "AMD"    { $props.ProviderName -match "AMD|ATI" -or $props.DriverDesc -match "AMD|Radeon" }
                    "Intel"  { $props.ProviderName -match "Intel" -or $props.DriverDesc -match "Intel.*Graphics" }
                }
                if ($match) {
                    Remove-Item $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-OK "Registry cleaned: $($key.PSChildName) ($($props.DriverDesc))"
                }
            } catch {
                Write-Debug "Registry key $($key.PSChildName): $_"
            }
        }
    }

    # Clean NVIDIA-specific registry paths
    if ($GpuVendor -eq "NVIDIA") {
        $nvRegPaths = @(
            "HKLM:\SOFTWARE\NVIDIA Corporation",
            "HKCU:\SOFTWARE\NVIDIA Corporation",
            "HKLM:\SOFTWARE\WOW6432Node\NVIDIA Corporation"
        )
        foreach ($p in $nvRegPaths) {
            if (Test-Path $p) {
                Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                Write-OK "Registry cleaned: $p"
            }
        }
    } elseif ($GpuVendor -eq "AMD") {
        $amdRegPaths = @(
            "HKLM:\SOFTWARE\AMD",
            "HKLM:\SOFTWARE\ATI Technologies",
            "HKCU:\SOFTWARE\AMD"
        )
        foreach ($p in $amdRegPaths) {
            if (Test-Path $p) {
                Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                Write-OK "Registry cleaned: $p"
            }
        }
    }

    # ── 4. Clean DriverStore Orphans ─────────────────────────────────────────
    Write-Step "Cleaning DriverStore orphan folders..."

    $driverStore = "$env:SystemRoot\System32\DriverStore\FileRepository"
    # Use precise patterns to avoid matching non-GPU drivers (e.g., nvdimm, amdppm)
    $patterns = switch ($GpuVendor) {
        "NVIDIA" { @("nv_dispi*","nvdsp*","nvlddmkm*","nview*","nvhdc*","nvmdi*") }
        "AMD"    { @("atiilhag*","atiumdag*","amdkmdap*","amdxe*","atihdw*","radeon*") }
        "Intel"  { @("iigd_dch*","igfx*","igd10*","igd11*","igd12*") }
    }

    $cleanedFolders = 0
    if (Test-Path $driverStore) {
        foreach ($p in $patterns) {
            $folders = Get-ChildItem $driverStore -Directory -Filter $p -ErrorAction SilentlyContinue
            foreach ($f in $folders) {
                try {
                    Remove-Item $f.FullName -Recurse -Force -ErrorAction Stop
                    Write-OK "DriverStore cleaned: $($f.Name)"
                    $cleanedFolders++
                } catch {
                    Write-Debug "Could not remove $($f.Name) (locked): $_"
                }
            }
        }
    }
    Write-Info "$cleanedFolders DriverStore folders cleaned."

    # ── 5. Clean Shader Caches ───────────────────────────────────────────────
    Write-Step "Cleaning shader caches..."

    $cachePaths = switch ($GpuVendor) {
        "NVIDIA" { @(
            "$env:LOCALAPPDATA\NVIDIA\DXCache",
            "$env:LOCALAPPDATA\NVIDIA\GLCache",
            "$env:TEMP\NVIDIA Corporation",
            "$env:ProgramData\NVIDIA Corporation"
        )}
        "AMD" { @(
            "$env:LOCALAPPDATA\AMD\DxCache",
            "$env:LOCALAPPDATA\AMD\GLCache",
            "$env:TEMP\AMDRSServ"
        )}
        "Intel" { @(
            "$env:LOCALAPPDATA\Intel"
        )}
    }

    # Common shader caches
    $cachePaths += "$env:LOCALAPPDATA\D3DSCache"

    foreach ($cp in $cachePaths) {
        if (Test-Path $cp) {
            $items = Get-ChildItem $cp -Recurse -ErrorAction SilentlyContinue
            $count = $items.Count
            Remove-Item $cp -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Cache cleaned: $cp ($count items)"
        }
    }

    # ── Summary ──────────────────────────────────────────────────────────────
    Write-Blank
    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Green
    Write-Host "  │  GPU DRIVER CLEAN REMOVAL COMPLETE                          │" -ForegroundColor Green
    Write-Host "  │                                                              │" -ForegroundColor Green
    Write-Host "  │  Vendor:          $GpuVendor$((' ' * (39 - $GpuVendor.Length)))│" -ForegroundColor White
    Write-Host "  │  Drivers removed: $removedDrivers$((' ' * (39 - "$removedDrivers".Length)))│" -ForegroundColor White
    Write-Host "  │  Folders cleaned: $cleanedFolders$((' ' * (39 - "$cleanedFolders".Length)))│" -ForegroundColor White
    Write-Host "  │                                                              │" -ForegroundColor Green
    Write-Host "  │  Ready for clean driver installation.                       │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Green
}
