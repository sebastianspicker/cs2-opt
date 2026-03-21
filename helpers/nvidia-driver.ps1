# ==============================================================================
#  helpers/nvidia-driver.ps1  —  NVIDIA Driver Download + Clean Install
# ==============================================================================

function Get-LatestNvidiaDriver {
    <#
    .SYNOPSIS  Queries NVIDIA's driver lookup API to find the latest driver
               for the detected GPU. Returns download URL and version info.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SpecificVersion',
        Justification = 'Reserved for future version-specific download support')]
    param(
        [string]$SpecificVersion  # If set, tries to find this version instead of latest
    )

    Write-Step "Detecting NVIDIA GPU for driver lookup..."

    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1

    if (-not $gpu) {
        Write-Warn "No NVIDIA GPU detected."
        return $null
    }

    Write-Info "GPU: $($gpu.Name)"

    # NVIDIA driver lookup API
    # psid = Product Series ID, pfid = Product Family ID
    # osid = 57 (Windows 10/11 64-bit), lid = 1 (English), whql = 1

    # Map common GPU series to NVIDIA product series/family IDs
    # [ordered] ensures deterministic match order (longest/newest series first)
    $gpuName = $gpu.Name
    $seriesMap = [ordered]@{
        "RTX 50"  = @{ psid = 129; pfid = 1010 }   # GeForce RTX 50 Series
        "RTX 40"  = @{ psid = 128; pfid = 993 }     # GeForce RTX 40 Series
        "RTX 30"  = @{ psid = 127; pfid = 945 }     # GeForce RTX 30 Series
        "RTX 20"  = @{ psid = 126; pfid = 903 }     # GeForce RTX 20 Series
        "GTX 16"  = @{ psid = 125; pfid = 904 }     # GeForce GTX 16 Series
        "GTX 10"  = @{ psid = 101; pfid = 816 }     # GeForce GTX 10 Series
    }

    $matchedSeries = $null
    foreach ($key in $seriesMap.Keys) {
        if ($gpuName -match $key) {
            $matchedSeries = $seriesMap[$key]
            break
        }
    }

    if (-not $matchedSeries) {
        # Default to latest GeForce driver page
        Write-Warn "GPU series not auto-detected. Using manual download."
        Write-Info "Download from: https://www.nvidia.com/en-us/drivers/"
        return @{
            ManualDownload = $true
            Url = "https://www.nvidia.com/en-us/drivers/"
            GpuName = $gpuName
        }
    }

    $lookupUrl = "https://www.nvidia.com/Download/processFind.aspx?" +
                 "psid=$($matchedSeries.psid)&pfid=$($matchedSeries.pfid)" +
                 "&osid=57&lid=1&whql=1&dtcid=1"

    $oldPP = $global:ProgressPreference
    try {
        Write-Step "Querying NVIDIA driver API..."
        $global:ProgressPreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $lookupUrl -UseBasicParsing -TimeoutSec 30

        # Parse the response for download link and version
        $content = $response.Content
        $downloadUrl = $null
        if ($content -match "downloadURL\s*=\s*'([^']+)'") {
            $downloadUrl = $Matches[1]
        } elseif ($content -match '(https://[^"''<>\s]+\.exe)') {
            $downloadUrl = $Matches[1]
        }

        $version = $null
        if ($content -match "Version:\s*([\d.]+)") {
            $version = $Matches[1]
        }

        if ($downloadUrl) {
            # Ensure full URL
            if ($downloadUrl -notmatch "^https?://") {
                $downloadUrl = "https://www.nvidia.com$downloadUrl"
            }
            if (-not $version) { Write-Warn "Could not parse driver version from API response." }
            Write-OK "Found driver: Version $(if ($version) { $version } else { '(unknown)' })"
            Write-Info "URL: $downloadUrl"
            return @{
                ManualDownload = $false
                Url = $downloadUrl
                Version = $version
                GpuName = $gpuName
            }
        }
    } catch {
        Write-Debug "NVIDIA API lookup failed: $_"
    } finally {
        $global:ProgressPreference = $oldPP
    }

    # Fallback to manual download
    Write-Warn "Auto-detection failed. Use manual download."
    Write-Info "Download from: https://www.nvidia.com/en-us/drivers/"
    return @{
        ManualDownload = $true
        Url = "https://www.nvidia.com/en-us/drivers/"
        GpuName = $gpuName
    }
}

function Install-NvidiaDriverClean {
    <#
    .SYNOPSIS  Extracts NVIDIA driver package and installs with only essential
               components (no GFE, no telemetry). Replaces NVCleanstall.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DriverExe
    )

    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would extract and install NVIDIA driver: $DriverExe" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   1. Extract driver package" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   2. Remove bloat components (GFE, telemetry)" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   3. Silent install with essential components only" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   4. Apply post-install registry tweaks" -ForegroundColor Magenta
        return $true
    }

    if (-not (Test-Path $DriverExe)) {
        Write-Err "Driver file not found: $DriverExe"
        return $false
    }

    $tempDir = "$env:TEMP\NVDriver_Extract"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

    # ── 1. Extract driver package ────────────────────────────────────────────
    Write-Step "Extracting NVIDIA driver package..."
    Write-Info "This may take 1-2 minutes..."

    $extractProc = Start-Process -FilePath $DriverExe -ArgumentList "-extract:`"$tempDir`" -noeula" -Wait -PassThru -NoNewWindow
    if ($extractProc.ExitCode -ne 0 -or -not (Test-Path "$tempDir\setup.exe")) {
        # Clean partial extraction before retry
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        # Try alternate extraction flags
        $extractProc2 = Start-Process -FilePath $DriverExe -ArgumentList "-y -gm2 -InstallPath=`"$tempDir`"" -Wait -PassThru -NoNewWindow
        if ($extractProc2.ExitCode -ne 0) {
            Write-Err "Could not extract driver (exit codes: $($extractProc.ExitCode), $($extractProc2.ExitCode))"
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    if (-not (Test-Path "$tempDir\setup.exe")) {
        Write-Err "Extraction failed — setup.exe not found in $tempDir"
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    Write-OK "Driver extracted to: $tempDir"

    # ── 2. Remove unwanted components ────────────────────────────────────────
    Write-Step "Removing bloat components..."
    $removeComponents = @(
        "GFExperience",
        "GFExperience.NvStreamSrv",
        "NvApp",
        "NvTelemetry",
        "Display.NvContainer",
        "NvAbHub",
        "NvBackend",
        "NvCamera",
        "NvVAD",
        "ShadowPlay",
        "ShieldWirelessController",
        "Update.Core",
        "EULA.txt",
        "ListDevices.txt",
        "license.txt"
    )

    $removedCount = 0
    foreach ($comp in $removeComponents) {
        $compPath = Join-Path $tempDir $comp
        if (Test-Path $compPath) {
            Remove-Item $compPath -Recurse -Force -ErrorAction SilentlyContinue
            $removedCount++
        }
    }
    Write-OK "Removed $removedCount bloat components."

    # ── 3. Install driver (silent) ───────────────────────────────────────────
    Write-Step "Installing NVIDIA driver (silent install)..."
    Write-Info "This takes 2-5 minutes. Screen may flicker."

    $setup = Join-Path $tempDir "setup.exe"
    $installProcess = Start-Process -FilePath $setup -ArgumentList "-s -noreboot" -Wait -PassThru -NoNewWindow

    if ($installProcess.ExitCode -eq 0) {
        Write-OK "NVIDIA driver installed successfully."
    } elseif ($installProcess.ExitCode -eq 1) {
        Write-OK "NVIDIA driver installed (exit code 1 — reboot required)."
        Write-Info "Exit code 1 may indicate partial install or reboot needed. Verify in Device Manager."
    } else {
        Write-Warn "Installer exited with code $($installProcess.ExitCode)."
        Write-Info "This may still be OK — check Device Manager after restart."
    }

    # ── 4. Post-install tweaks ───────────────────────────────────────────────
    Apply-NvidiaPostInstallTweaks

    # ── 5. Cleanup ───────────────────────────────────────────────────────────
    Write-Step "Cleaning up extraction folder..."
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Cleanup complete."

    return $true
}

function Apply-NvidiaPostInstallTweaks {
    <#
    .SYNOPSIS  Applies post-install registry tweaks that NVCleanstall's
               "Expert Tweaks" would normally handle.
    #>

    Write-Step "Applying post-install NVIDIA tweaks..."

    # ── Disable NVIDIA Telemetry ─────────────────────────────────────────────
    $telemetryPaths = @(
        @{ Path = "HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client"; Name = "OptInOrOutPreference"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS"; Name = "EnableRID44231"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS"; Name = "EnableRID64640"; Value = 0 },
        @{ Path = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS"; Name = "EnableRID66610"; Value = 0 }
    )
    if (-not $SCRIPT:CurrentStepTitle) { $SCRIPT:CurrentStepTitle = "NVIDIA Post-Install Tweaks" }
    foreach ($t in $telemetryPaths) {
        Set-RegistryValue $t.Path $t.Name $t.Value "DWord" "NVIDIA telemetry disable"
    }
    if (-not $SCRIPT:DryRun) { Write-OK "NVIDIA telemetry disabled." }

    # ── Disable HDCP ─────────────────────────────────────────────────────────
    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$CFG_GUID_Display"
    if (Test-Path $classPath) {
        $subkeys = Get-ChildItem $classPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match "^\d{4}$" }
        foreach ($key in $subkeys) {
            $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($props.ProviderName -match "NVIDIA" -or $props.DriverDesc -match "NVIDIA") {
                Set-RegistryValue $key.PSPath "RMHdcpKeyglobZero" 1 "DWord" "HDCP disable for $($props.DriverDesc)"
            }
        }
    }

    # ── Enable Write Combining ───────────────────────────────────────────────
    $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    if (-not $SCRIPT:DryRun -and -not (Test-Path $gfxPath)) { New-Item -Path $gfxPath -Force | Out-Null }
    Set-RegistryValue $gfxPath "EnableWriteCombining" 1 "DWord" "GPU write combining"
    if (-not $SCRIPT:DryRun) { Write-OK "Write Combining enabled." }

    # ── Disable MPO (Multiplane Overlay) ─────────────────────────────────────
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" 5 "DWord" "MPO disable"
    if (-not $SCRIPT:DryRun) { Write-OK "MPO disabled." }

    # ── Disable NVIDIA telemetry services ────────────────────────────────────
    $nvTelServices = @("NvTelemetryContainer", "NvContainerNetworkService")
    foreach ($svc in $nvTelServices) {
        try {
            if (-not $SCRIPT:DryRun) {
                Backup-ServiceState -ServiceName $svc -StepTitle $SCRIPT:CurrentStepTitle
                Stop-Service $svc -Force -ErrorAction SilentlyContinue
                Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            } else {
                Write-Host "  [DRY-RUN] Would stop + disable: ${svc}" -ForegroundColor Magenta
            }
        } catch { Write-Debug "Telemetry service ${svc}: $_" }
    }
    if (-not $SCRIPT:DryRun) { Write-OK "NVIDIA telemetry services disabled." }

    if (-not $SCRIPT:DryRun) { Write-Info "Post-install tweaks applied. Restart recommended." }
}
