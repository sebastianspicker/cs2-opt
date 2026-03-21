# ==============================================================================
#  helpers/debloat.ps1  —  Targeted Bloatware + Telemetry Removal
# ==============================================================================

function Invoke-GamingDebloat {
    <#
    .SYNOPSIS  Removes known bloatware AppX packages, disables telemetry services
               and scheduled tasks. Pure PowerShell — no external tools.
    #>

    Write-Step "Removing bloatware AppX packages..."

    $bloatPackages = @(
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.People",
        "Microsoft.Todos",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.YourPhone",
        "Microsoft.WindowsMaps",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Clipchamp.Clipchamp",
        "Microsoft.549981C3F5F10",          # Cortana
        "Microsoft.MixedReality.Portal",
        "Microsoft.SkypeApp",
        "Microsoft.WindowsCommunicationsApps"  # Mail & Calendar
    )

    # Pre-fetch provisioned packages once (avoid querying per-package in the loop)
    $provisionedPkgs = $null
    if (-not $SCRIPT:DryRun) {
        $provisionedPkgs = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }

    $removedCount = 0
    foreach ($pkg in $bloatPackages) {
        $apps = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
        if ($apps) {
            if (-not $SCRIPT:DryRun) {
                $apps | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                # Also remove provisioned package to prevent reinstall on Windows feature updates
                if ($provisionedPkgs) {
                    $provisionedPkgs |
                        Where-Object { $_.DisplayName -eq $pkg } |
                        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                }
                Write-OK "Removed: $pkg"
            } else {
                Write-Host "  [DRY-RUN] Would remove AppX: $pkg" -ForegroundColor Magenta
            }
            $removedCount++
        }
    }
    if ($removedCount -eq 0) {
        Write-Info "No bloatware packages found (already clean)."
    } else {
        $verb = if ($SCRIPT:DryRun) { "would be removed" } else { "removed" }
        Write-OK "$removedCount bloatware packages $verb."
    }

    # ── Disable Telemetry Services ───────────────────────────────────────────
    Write-Step "Disabling telemetry services..."
    $telemetryServices = @(
        @{ Name = "DiagTrack";        Label = "Connected User Experiences and Telemetry" },
        @{ Name = "dmwappushservice"; Label = "Device Management WAP Push" }
    )
    foreach ($svc in $telemetryServices) {
        try {
            if (-not $SCRIPT:DryRun) {
                Backup-ServiceState -ServiceName $svc.Name -StepTitle $SCRIPT:CurrentStepTitle
                Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service $svc.Name -StartupType Disabled -ErrorAction Stop
                Write-OK "Disabled: $($svc.Label) ($($svc.Name))"
            } else {
                Write-Host "  [DRY-RUN] Would stop + disable service: $($svc.Label) ($($svc.Name))" -ForegroundColor Magenta
            }
        } catch {
            Write-Debug "Service $($svc.Name) not found or already disabled."
        }
    }

    # ── Disable Telemetry Scheduled Tasks ────────────────────────────────────
    Write-Step "Disabling telemetry scheduled tasks..."
    $taskPaths = @(
        "\Microsoft\Windows\Application Experience\",
        "\Microsoft\Windows\Customer Experience Improvement Program\"
    )
    foreach ($tp in $taskPaths) {
        try {
            $tasks = Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue
            foreach ($t in $tasks) {
                if (-not $SCRIPT:DryRun) {
                    Backup-ScheduledTask -TaskName $t.TaskName -StepTitle $SCRIPT:CurrentStepTitle
                    Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
                    Write-OK "Disabled task: $($t.TaskName)"
                } else {
                    Write-Host "  [DRY-RUN] Would disable task: $($t.TaskName)" -ForegroundColor Magenta
                }
            }
        } catch {
            Write-Debug "Task path $tp not found."
        }
    }

    # ── Disable Consumer Features ────────────────────────────────────────────
    Write-Step "Disabling consumer features..."
    $consumerPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    Set-RegistryValue $consumerPath "DisableWindowsConsumerFeatures" 1 "DWord" "Disable consumer features (app suggestions)"
    Set-RegistryValue $consumerPath "DisableSoftLanding" 1 "DWord" "Disable soft landing (app suggestions)"
    if (-not $SCRIPT:DryRun) { Write-OK "Consumer features disabled (no app suggestions)." }

    # ── Disable Advertising ID ───────────────────────────────────────────────
    $adPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    Set-RegistryValue $adPath "Enabled" 0 "DWord" "Disable advertising ID"
    if (-not $SCRIPT:DryRun) { Write-OK "Advertising ID disabled." }

    # NOTE: Autostart cleanup is handled separately by Step 14 (Optimize-Hardware.ps1).
    # Keeping it out of debloat ensures the user's choice to skip Step 14 is honored.
}
