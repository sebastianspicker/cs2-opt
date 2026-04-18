function Get-StateDataSafe {
    try {
        if (Test-Path $CFG_StateFile) {
            return Get-Content $CFG_StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
    } catch {
        Write-DebugLog "State load failed: $($_.Exception.Message)"
    }
    return $null
}

function Save-StateDataSafe {
    param([Parameter(Mandatory)]$State)
    Save-JsonAtomic -Data $State -Path $CFG_StateFile
    Set-SecureAcl -Path $CFG_StateFile
}

function New-DefaultState {
    return [PSCustomObject]@{
        mode    = "AUTO"
        profile = "RECOMMENDED"
    }
}

function Should-SkipStartupDriftCheck {
    param(
        $State,
        [datetime]$Now = (Get-Date)
    )
    if (-not $State -or -not $State.PSObject.Properties['startup_last_verified']) { return $false }
    try {
        $lastVerified = [datetime]::Parse([string]$State.startup_last_verified)
        return (($Now - $lastVerified).TotalMinutes -lt 60)
    } catch {
        return $false
    }
}

function Test-StartupConfigDrift {
    $state = Get-StateDataSafe
    $now = Get-Date
    if (Should-SkipStartupDriftCheck -State $state -Now $now) {
        return [PSCustomObject]@{
            Skipped      = $true
            HasDrift     = $false
            DriftCount   = 0
            CheckedCount = 0
            DriftLabels  = @()
            CheckedAt    = [string]$state.startup_last_verified
        }
    }

    $checks = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayTestMode"; Expected = 5; Label = "MPO disabled" }
        @{ Path = "HKCU:\SOFTWARE\Microsoft\GameBar"; Name = "AutoGameModeEnabled"; Expected = 1; Label = "Game Mode enabled" }
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"; Name = "AppCaptureEnabled"; Expected = 0; Label = "Game DVR capture disabled" }
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"; Name = "GlobalTimerResolutionRequests"; Expected = 1; Label = "Timer Resolution enabled" }
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Label = "Fast Startup disabled" }
    )

    $driftLabels = [System.Collections.Generic.List[string]]::new()
    foreach ($check in $checks) {
        $result = Test-RegistryCheck $check.Path $check.Name $check.Expected $check.Label -Quiet
        if ($result.Status -ne "OK") {
            $driftLabels.Add($check.Label) | Out-Null
        }
    }

    if (-not $state) {
        $state = New-DefaultState
    }
    $state | Add-Member -NotePropertyName "startup_last_verified" -NotePropertyValue ($now.ToString("o")) -Force
    try {
        Save-StateDataSafe -State $state
    } catch {
        Write-DebugLog "Startup drift state save failed: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        Skipped      = $false
        HasDrift     = ($driftLabels.Count -gt 0)
        DriftCount   = $driftLabels.Count
        CheckedCount = $checks.Count
        DriftLabels  = @($driftLabels)
        CheckedAt    = $now.ToString("yyyy-MM-dd HH:mm")
    }
}

function Update-StartupDriftBanner {
    if ($Script:StartupDriftChecked) { return }
    $Script:StartupDriftChecked = $true

    $result = Test-StartupConfigDrift
    if ($result.Skipped -or -not $result.HasDrift) {
        (El "DashDriftBanner").Visibility = "Collapsed"
        return
    }

    (El "DashDriftBannerTitle").Text = "Configuration Drift Detected"
    (El "DashDriftBannerText").Text = "$($result.DriftCount) of $($result.CheckedCount) quick checks drifted. Run Verify-Settings to review and repair the full set."
    (El "DashDriftBanner").Visibility = "Visible"
}

function Get-BenchmarkCapFromText {
    param([string]$Text)
    if ($Text -notmatch "Avg\s*=\s*([\d.]+)") { return $null }

    $avg = [double]$Matches[1]
    $cap = [math]::Max($CFG_FpsCap_Min, [math]::Floor($avg - [math]::Floor($avg * $CFG_FpsCap_Percent)))
    return [PSCustomObject]@{
        AvgFps = $avg
        Cap    = $cap
    }
}

function Get-BenchmarkResultFromText {
    param([string]$Text)
    if ($Text -notmatch "Avg\s*=\s*([\d.]+).*P1\s*=\s*([\d.]+)") { return $null }

    return [PSCustomObject]@{
        AvgFps = [double]$Matches[1]
        P1Fps  = [double]$Matches[2]
    }
}

function Switch-Panel {
    param([string]$PanelName, [scriptblock]$OnSwitch = $null)
    foreach ($p in $Script:AllPanels) {
        (El $p).Visibility = if ($p -eq $PanelName) { "Visible" } else { "Collapsed" }
    }
    foreach ($kv in $Script:NavMap.GetEnumerator()) {
        (El $kv.Value).Style = if ($kv.Key -eq $PanelName) { $ActiveStyle } else { $InactiveStyle }
    }
    $Script:ActivePanel = $PanelName
    if ($OnSwitch) { & $OnSwitch }
}
