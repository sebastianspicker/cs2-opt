# ==============================================================================
#  helpers/system-utils.ps1  —  Download, Registry, Boot Config, Filesystem
# ==============================================================================

function Invoke-Download($url, $dest, $name) {
    Write-Step "Download: $name"
    Write-Debug "URL: $url -> $dest"
    $maxAttempts = 2
    # Set $global: scope so PS 5.1's Invoke-WebRequest sees it (function-scope has no effect in 5.1)
    $oldProgressPref = $global:ProgressPreference
    try {
        $global:ProgressPreference = 'SilentlyContinue'
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 120
                $fileSize = (Get-Item $dest).Length
                $mb = [math]::Round($fileSize / 1MB, 2)
                # Sanity check: NVIDIA drivers are >100 MB; reject obviously truncated files
                if ($fileSize -lt 1MB) {
                    Write-Warn "Download appears truncated ($mb MB) — removing corrupt file."
                    Remove-Item $dest -Force -ErrorAction SilentlyContinue
                    if ($attempt -lt $maxAttempts) { Write-Info "Retrying..."; continue }
                    Write-Err "Download failed after $maxAttempts attempts (file too small)."
                    Write-Warn "Manual: $url"
                    return $false
                }
                Write-OK "$name ($mb MB)"
                return $true
            } catch {
                if ($attempt -lt $maxAttempts) {
                    Write-Warn "Download attempt $attempt failed: $_ — retrying..."
                    Remove-Item $dest -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Err "Download failed after $maxAttempts attempts: $_"
                    Write-Warn "Manual: $url"
                    Remove-Item $dest -Force -ErrorAction SilentlyContinue
                    return $false
                }
            }
        }
        return $false
    } finally {
        $global:ProgressPreference = $oldProgressPref
    }
}

function Save-JsonAtomic {
    <#  Writes JSON to a file atomically (write-to-temp-then-rename).
        Prevents corruption if interrupted by crash or power loss.  #>
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 10
    )
    # Ensure parent directory exists — callers usually call Ensure-Dir early,
    # but defensive creation here prevents silent failures from edge-case paths.
    $parentDir = Split-Path $Path -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force -ErrorAction Stop | Out-Null
    }
    $tmp = "$Path.tmp"
    try {
        $Data | ConvertTo-Json -Depth $Depth | Set-Content $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item $tmp $Path -Force -ErrorAction Stop
    } catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        throw "Save-JsonAtomic failed for '$Path': $_"
    }
}

function Save-State($obj, $path) {
    Save-JsonAtomic -Data $obj -Path $path
}

function Load-State($path) {
    if (-not (Test-Path $path)) { throw "state.json missing at '$path' — run Phase 1 first." }
    $s = Get-Content $path | ConvertFrom-Json
    $SCRIPT:Mode     = $s.mode
    $SCRIPT:LogLevel = if ($s.logLevel) { $s.logLevel } else { "NORMAL" }
    $SCRIPT:Profile  = if ($s.profile) { $s.profile } else { "RECOMMENDED" }
    $SCRIPT:DryRun   = ($SCRIPT:Mode -eq "DRY-RUN")
    return $s
}

function Initialize-ScriptDefaults {
    <#  Soft state loader for entry-point scripts (Cleanup, FpsCap, Verify).
        Loads state.json if present, otherwise sets safe defaults. Never exits.  #>
    if (Test-Path $CFG_StateFile) {
        try {
            $st = Get-Content $CFG_StateFile | ConvertFrom-Json
            $SCRIPT:Mode     = $st.mode
            $SCRIPT:LogLevel = if ($st.logLevel) { $st.logLevel } else { "NORMAL" }
            $SCRIPT:Profile  = if ($st.profile) { $st.profile } else { "RECOMMENDED" }
            $SCRIPT:DryRun   = ($SCRIPT:Mode -eq "DRY-RUN")
        } catch {
            $SCRIPT:Mode = "CONTROL"; $SCRIPT:LogLevel = "NORMAL"; $SCRIPT:Profile = "RECOMMENDED"; $SCRIPT:DryRun = $false
        }
    } else {
        $SCRIPT:Mode = "CONTROL"; $SCRIPT:LogLevel = "NORMAL"; $SCRIPT:Profile = "RECOMMENDED"; $SCRIPT:DryRun = $false
    }
}

function Set-RunOnce($name, $scriptPath) {
    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would set RunOnce: $name -> $scriptPath" -ForegroundColor Magenta
        return
    }
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$scriptPath`""
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name $name -Value $cmd
    Write-OK "RunOnce: $name"
}

function Set-BootConfig($key, $val, $why) {
    # Auto-backup before modification
    if ($SCRIPT:CurrentStepTitle -and -not $SCRIPT:DryRun) {
        Backup-BootConfig -Key $key -StepTitle $SCRIPT:CurrentStepTitle
    }
    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would set: bcdedit /set $key $val  ($why)" -ForegroundColor Magenta
        return
    }
    Write-Step "bcdedit /set $key $val  ($why)"
    $output = bcdedit /set $key $val 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warn "bcdedit failed (exit $LASTEXITCODE): $output" }
    else { Write-OK "Set: $key = $val" }
}

function Set-RegistryValue($path, $name, $value, $type, $why) {
    # Auto-backup before modification
    if ($SCRIPT:CurrentStepTitle -and -not $SCRIPT:DryRun) {
        Backup-RegistryValue -Path $path -Name $name -StepTitle $SCRIPT:CurrentStepTitle
    }
    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would set: $name = $value [$type]  ($why)" -ForegroundColor Magenta
        Write-Host "  [DRY-RUN]   Path: $path" -ForegroundColor DarkMagenta
        return
    }
    Write-Debug "Registry: $path | $name = $value [$type] — $why"
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -ErrorAction Stop
        Write-OK "Registry: $name = $value"
    } catch { Write-Warn "Registry write failed ($name): $_" }
}

function Ensure-Dir($path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

function Clear-Dir($path, $label) {
    if (-not (Test-Path $path)) { Write-Debug "${label}: not found ($path)"; return 0 }
    $items = Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    $n = $files.Count
    $mb = [math]::Round(($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)
    Write-Step "$label  ($n files · $mb MB)"
    $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $remaining = @(Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }).Count
    $del = [math]::Max(0, $n - $remaining)
    Write-OK "${label}: $del deleted$(if($remaining){" ($remaining locked — normal)"})"
    Write-Debug "${label}: del=$del locked=$remaining path=$path"
    return $del
}

# ── Verification counter infrastructure ─────────────────────────────────────
# Uses $global: scope so counters work regardless of how this file is loaded
# (dot-source, Import-Module, or ScriptsToProcess). Callers initialize via
# Initialize-VerifyCounters and read via Get-VerifyCounters.

function Initialize-VerifyCounters {
    <#  Resets verification counters. Call before a batch of Test-RegistryCheck/Test-ServiceCheck calls.  #>
    $global:_verifyOkCount      = 0
    $global:_verifyChangedCount = 0
    $global:_verifyMissingCount = 0
}

function Get-VerifyCounters {
    <#  Returns a hashtable with current ok/changed/missing counts.  #>
    return @{
        okCount      = [int]$global:_verifyOkCount
        changedCount = [int]$global:_verifyChangedCount
        missingCount = [int]$global:_verifyMissingCount
    }
}

function Test-RegistryCheck {
    param(
        [string] $Path,
        [string] $Name,
        $Expected,
        [string] $Label,
        [switch] $Quiet   # Returns structured @{Status; Value} without console output or counter updates
    )
    $result = $null
    try {
        if (Test-Path $Path) {
            $val = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            $result = $val.$Name
        }
    } catch { Write-Debug "Test-RegistryCheck: could not read '$Name' from '$Path'" }

    $status = if ($null -eq $result) { "MISSING" } elseif ($result -eq $Expected) { "OK" } else { "CHANGED" }

    if ($Quiet) {
        return @{ Status = $status; Value = $result }
    }

    switch ($status) {
        "MISSING" {
            Write-Host "  ?  MISSING   $Label" -ForegroundColor Red
            Write-Host "               $Path\$Name" -ForegroundColor DarkGray
            $global:_verifyMissingCount++
        }
        "OK" {
            Write-Host "  ✓  OK        $Label  ($result)" -ForegroundColor Green
            $global:_verifyOkCount++
        }
        "CHANGED" {
            Write-Host "  ✗  CHANGED   $Label  (is: $result, expected: $Expected)" -ForegroundColor Yellow
            Write-Host "               $Path\$Name" -ForegroundColor DarkGray
            $global:_verifyChangedCount++
        }
    }
    # No return value when not -Quiet — prevents stdout clutter in Verify-Settings.ps1
}

function Test-ServiceCheck {
    param(
        [string] $ServiceName,
        [string] $ExpectedStartType,
        [string] $Label
    )
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        $rawStartType = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").StartMode
        # WMI returns "Auto" but Set-Service uses "Automatic" — normalize for comparison
        $startType = switch ($rawStartType) {
            "Auto"         { "Automatic" }
            "Auto Delayed" { "AutomaticDelayedStart" }
            default        { $rawStartType }
        }
        if ($startType -eq $ExpectedStartType) {
            Write-Host "  ✓  OK        $Label  (StartType: $startType, Status: $($svc.Status))" -ForegroundColor Green
            $global:_verifyOkCount++
        } else {
            Write-Host "  ✗  CHANGED   $Label  (StartType: $startType, expected: $ExpectedStartType)" -ForegroundColor Yellow
            $global:_verifyChangedCount++
        }
    } catch {
        Write-Host "  ?  MISSING   $Label  (Service not found)" -ForegroundColor Red
        $global:_verifyMissingCount++
    }
}
