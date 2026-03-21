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
    # Use -ErrorAction Stop so Get-Content failures are not silently swallowed
    # under the global $ErrorActionPreference = "SilentlyContinue" set by entry-point scripts.
    $s = Get-Content $path -ErrorAction Stop | ConvertFrom-Json
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
            # -ErrorAction Stop ensures Get-Content failures throw into the catch block
            # rather than being silently swallowed by the global SilentlyContinue preference.
            $st = Get-Content $CFG_StateFile -ErrorAction Stop | ConvertFrom-Json
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
    # SECURITY: Validate RunOnce name — alphanumeric + underscore only.
    # Prevents injection into the HKLM RunOnce key namespace.
    if ($name -notmatch '^[a-zA-Z0-9_]+$') {
        Write-Warn "Set-RunOnce: invalid name '$name' — rejected (security: registry injection prevention)"
        return
    }
    # SECURITY: Validate script path — must be under C:\CS2_OPTIMIZE\ and end in .ps1.
    # RunOnce executes at boot as the logged-on user with admin elevation (HKLM).
    # If an attacker could set $scriptPath to an arbitrary location, they get code execution.
    $resolvedPath = try { [System.IO.Path]::GetFullPath($scriptPath) } catch { $null }
    if (-not $resolvedPath -or
        $resolvedPath -notmatch '^C:\\CS2_OPTIMIZE\\' -or
        $resolvedPath -notmatch '\.ps1$') {
        Write-Warn "Set-RunOnce: script path must be under C:\CS2_OPTIMIZE\ and end in .ps1 — rejected: $scriptPath"
        return
    }

    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Would set RunOnce: $name -> $scriptPath" -ForegroundColor Magenta
        return
    }
    # Validate target script exists before registering — a RunOnce pointing to a missing
    # file would silently fail on next boot, leaving Phase 3 unexecuted with no error.
    if (-not (Test-Path $scriptPath)) {
        Write-Warn "RunOnce target does not exist: $scriptPath"
        Write-Warn "Phase 3 will NOT auto-start on next boot. Re-run Phase 1 Step 38 or launch manually."
        return
    }
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$scriptPath`""
    try {
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name $name -Value $cmd -ErrorAction Stop
        Write-OK "RunOnce: $name -> $scriptPath"
    } catch {
        Write-Err "Failed to set RunOnce '$name': $_"
        Write-Err "Phase 3 will NOT auto-start. Run manually: $scriptPath"
    }
}

function Set-BootConfig($key, $val, $why) {
    # SECURITY: Validate bcdedit key/value — these are passed as command-line arguments.
    # An attacker who controls state.json or backup.json could inject arbitrary bcdedit args.
    # bcdedit keys are alphanumeric identifiers; values are alphanumeric, hex, or simple tokens.
    if ($key -notmatch '^[a-zA-Z][a-zA-Z0-9_]*$') {
        Write-Warn "Set-BootConfig: invalid key format '$key' — rejected (security: command injection prevention)"
        return
    }
    if ($val -notmatch '^[a-zA-Z0-9_.{}\-]+$') {
        Write-Warn "Set-BootConfig: invalid value format '$val' — rejected (security: command injection prevention)"
        return
    }

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
    # SECURITY: Validate registry path — must start with a known hive prefix.
    # An attacker who controls backup.json or state.json could inject arbitrary paths
    # to write to sensitive registry locations outside the expected scope.
    if ($path -notmatch '^(HKLM:|HKCU:|HKCR:|HKU:|HKCC:|Microsoft\.PowerShell\.Core\\Registry::HK)') {
        Write-Warn "Set-RegistryValue: path does not start with a valid registry hive — rejected: $path"
        return
    }
    # SECURITY: Registry value name must not contain path separators or null bytes.
    if ($name -match '[\\/\x00]') {
        Write-Warn "Set-RegistryValue: name contains invalid characters — rejected: $name"
        return
    }

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

# ── System Compatibility Checks ──────────────────────────────────────────────
# Runs once at startup to detect and warn about edge-case environments.
# All issues are non-fatal — the suite degrades gracefully.

function Test-SystemCompatibility {
    <#
    .SYNOPSIS  Detects environment limitations and logs warnings.
    .DESCRIPTION
        Checks for: ARM64, Constrained Language Mode, Windows Server/LTSC,
        PowerShell 7 (missing Get-WmiObject), missing AppX cmdlets.
        Does not block execution — all limitations have graceful fallbacks.
    #>
    $warnings = 0

    # ARM64 Windows — nvapi64.dll and some x64 P/Invoke won't work
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        Write-Warn "ARM64 Windows detected. NVIDIA DRS writes will fall back to registry-only method."
        $warnings++
    }

    # Constrained Language Mode — Add-Type blocked (AppLocker, WDAC, DeviceGuard)
    if ($ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
        Write-Warn "Constrained Language Mode active. NVIDIA DRS and RAM trim will be skipped."
        Write-Warn "Registry-only paths will be used where available."
        $warnings++
    }

    # Windows Server / LTSC — missing AppX, Xbox services, some consumer features
    $productType = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType
    # ProductType: 1=Workstation, 2=DomainController, 3=Server
    if ($productType -and $productType -ne 1) {
        Write-Warn "Windows Server/DC edition detected (ProductType=$productType)."
        Write-Warn "AppX debloat, Xbox services, and some consumer features may not exist."
        $warnings++
    }

    # PowerShell 7+ — Get-WmiObject removed (pagefile step affected)
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Warn "PowerShell $($PSVersionTable.PSVersion) detected. Pagefile configuration"
        Write-Warn "requires Get-WmiObject (PS 5.1 only). Run with Windows PowerShell for full support."
        $warnings++
    }

    # Missing AppX cmdlets (Server Core, minimal installs)
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Debug "AppX cmdlets not available — debloat package removal will be skipped."
        $warnings++
    }

    if ($warnings -gt 0) {
        Write-Info "Detected $warnings compatibility note(s) — suite will adapt automatically."
    }
}

# ── Verification counter infrastructure ─────────────────────────────────────
# Uses $global: scope so counters work regardless of how this file is loaded
# (dot-source, Import-Module, or ScriptsToProcess). Callers initialize via
# Initialize-VerifyCounters and read via Get-VerifyCounters.

function Initialize-VerifyCounters {
    $global:_verifyOkCount      = 0
    $global:_verifyChangedCount = 0
    $global:_verifyMissingCount = 0
}

function Get-VerifyCounters {
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
            # Warn if the key lives under a Policies path — Group Policy may override user writes
            if ($Path -match '\\Policies\\') {
                Write-Host "               NOTE: This key is under a Policies path — may be managed by Group Policy" -ForegroundColor DarkYellow
            }
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
