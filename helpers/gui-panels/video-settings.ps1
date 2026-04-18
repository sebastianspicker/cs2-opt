# VIDEO
# ══════════════════════════════════════════════════════════════════════════════
$Script:VideoTxtPath = $null

function Load-Video {
    # Populate tier picker
    if ((El "VideoTierPicker").Items.Count -eq 0) {
        foreach ($t in @("Auto","HIGH","MID","LOW")) { (El "VideoTierPicker").Items.Add($t) | Out-Null }
        (El "VideoTierPicker").SelectedIndex = 0
    }

    $steamPath = Get-SteamPath
    $vtxt = if ($steamPath) {
        Get-ChildItem "$steamPath\userdata\*\730\local\cfg\video.txt" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if ($vtxt) {
        $Script:VideoTxtPath = $vtxt.FullName
        (El "VideoTxtPath").Text = $vtxt.FullName
        (El "BtnVideoWrite").IsEnabled = $true
        (El "BtnVideoWriteFooter").IsEnabled = $true
    } else {
        (El "VideoTxtPath").Text = "video.txt not found — launch CS2 once to generate it"
        (El "BtnVideoWrite").IsEnabled = $false
        (El "BtnVideoWriteFooter").IsEnabled = $false
        return
    }

    Refresh-VideoGrid
}

# Single source of truth for video tier presets (V=value, N=note for display)
$Script:VideoPresets = @{
    "HIGH" = @{
        "setting.msaa_samples"              = @{ V="4";  N="4x MSAA — better 1% lows than None (ThourCS2)" }
        "setting.mat_vsync"                 = @{ V="0";  N="Always OFF — adds render queue latency" }
        "setting.fullscreen"                = @{ V="1";  N="Exclusive fullscreen — bypasses DWM compositor" }
        "setting.r_low_latency"             = @{ V="1";  N="NVIDIA Reflex On — saves 3-4ms input latency" }
        "setting.r_csgo_fsr_upsample"       = @{ V="0";  N="FSR OFF — artifacts harm enemy recognition" }
        "setting.shaderquality"             = @{ V="1";  N="High — GPU has headroom at this tier" }
        "setting.r_texturefilteringquality" = @{ V="5";  N="AF16x — near-zero cost on modern GPUs" }
        "setting.r_csgo_cmaa_enable"        = @{ V="0";  N="Off — MSAA handles AA" }
        "setting.r_aoproxy_enable"          = @{ V="0";  N="AO off — purely cosmetic, up to 6% FPS cost" }
        "setting.sc_hdr_enabled_override"   = @{ V="3";  N="Performance — Quality washes out sun/window areas" }
        "setting.r_particle_max_detail_level"=@{ V="0";  N="Low particles — no competitive disadvantage" }
        "setting.csm_enabled"               = @{ V="1";  N="Shadows ON — foot shadows reveal enemy positions" }
    }
    "MID" = @{
        "setting.msaa_samples"              = @{ V="4";  N="4x — or 2x if below 200 avg FPS" }
        "setting.mat_vsync"                 = @{ V="0";  N="Always OFF" }
        "setting.fullscreen"                = @{ V="1";  N="Exclusive fullscreen" }
        "setting.r_low_latency"             = @{ V="1";  N="NVIDIA Reflex On" }
        "setting.r_csgo_fsr_upsample"       = @{ V="0";  N="FSR OFF" }
        "setting.shaderquality"             = @{ V="0";  N="Low — saves GPU headroom on mid-tier" }
        "setting.r_texturefilteringquality" = @{ V="5";  N="AF16x" }
        "setting.r_csgo_cmaa_enable"        = @{ V="0";  N="Off — MSAA handles AA" }
        "setting.r_aoproxy_enable"          = @{ V="0";  N="AO off" }
        "setting.sc_hdr_enabled_override"   = @{ V="3";  N="Performance" }
        "setting.r_particle_max_detail_level"=@{ V="0";  N="Low" }
        "setting.csm_enabled"               = @{ V="1";  N="Shadows ON" }
    }
    "LOW" = @{
        "setting.msaa_samples"              = @{ V="0";  N="None + CMAA2 — free AA alternative" }
        "setting.mat_vsync"                 = @{ V="0";  N="Always OFF" }
        "setting.fullscreen"                = @{ V="1";  N="Exclusive fullscreen — critical for FPS" }
        "setting.r_low_latency"             = @{ V="1";  N="NVIDIA Reflex On" }
        "setting.r_csgo_fsr_upsample"       = @{ V="0";  N="FSR OFF" }
        "setting.shaderquality"             = @{ V="0";  N="Low" }
        "setting.r_texturefilteringquality" = @{ V="0";  N="Bilinear — legacy for max FPS" }
        "setting.r_csgo_cmaa_enable"        = @{ V="1";  N="CMAA2 ON — near-zero cost AA when MSAA=0" }
        "setting.r_aoproxy_enable"          = @{ V="0";  N="AO off" }
        "setting.sc_hdr_enabled_override"   = @{ V="3";  N="Performance" }
        "setting.r_particle_max_detail_level"=@{ V="0";  N="Low" }
        "setting.csm_enabled"               = @{ V="1";  N="Shadows ON — keep even on low-end" }
    }
}

function Get-ResolvedVideoTier {
    # Auto tier: HIGH for NVIDIA (detected via driver version), MID for AMD/Intel
    # The suite is NVIDIA-focused; AMD/Intel users should select tier manually
    param([string]$TierSel)
    if ($TierSel -eq "Auto") {
        $nv = Get-NvidiaDriverVersion
        if ($nv) { return "HIGH" }
        return "MID"
    }
    return $TierSel
}

function Refresh-VideoGrid {
    $tier = Get-ResolvedVideoTier (El "VideoTierPicker").SelectedItem
    $recommended = $Script:VideoPresets[$tier]

    $current = @{}
    if ($Script:VideoTxtPath -and (Test-Path $Script:VideoTxtPath)) {
        Get-Content $Script:VideoTxtPath | ForEach-Object {
            if ($_ -match '^\s*"([^"]+)"\s+"([^"]*)"') { $current[$Matches[1]] = $Matches[2] }
        }
    }

    $rows = foreach ($kv in $recommended.GetEnumerator() | Sort-Object Key) {
        $cur  = $current[$kv.Key]
        $rec  = $kv.Value.V
        $note = $kv.Value.N
        $st   = if ($null -eq $cur) { "—  Missing" } elseif ($cur -eq $rec) { "✓  OK" } else { "⚠  Differs" }
        $sc   = if ($st -match "OK") { "#22c55e" } elseif ($st -match "Missing") { "#6b7280" } else { "#fbbf24" }
        [PSCustomObject]@{
            Setting     = $kv.Key -replace "^setting\.",""
            YourValue   = if ($null -eq $cur) { "(not set)" } else { $cur }
            Recommended = $rec
            StatusLabel = $st
            StatusColor = $sc
            Notes       = $note
        }
    }

    (El "VideoGrid").ItemsSource = $rows
    $diffs = @($rows | Where-Object { $_.StatusLabel -notmatch "OK" }).Count
    (El "VideoSummary").Text = "$diffs setting(s) need attention for $tier-tier recommendation"
}

(El "VideoTierPicker").Add_SelectionChanged({ if ((El "VideoTierPicker").SelectedItem) { Refresh-VideoGrid } })

$writeVideo = {
    if (-not $Script:VideoTxtPath) { [System.Windows.MessageBox]::Show("video.txt not found.","Write"); return }

    $tier = Get-ResolvedVideoTier (El "VideoTierPicker").SelectedItem

    # Derive values-only hashtable from shared presets
    $managed = @{}
    foreach ($kv in $Script:VideoPresets[$tier].GetEnumerator()) { $managed[$kv.Key] = $kv.Value.V }

    # Read existing file — preserve unmanaged keys (resolution, Hz, etc.)
    $existing = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path $Script:VideoTxtPath) {
        Get-Content $Script:VideoTxtPath | ForEach-Object {
            if ($_ -match '^\s*"([^"]+)"\s+"([^"]*)"') { $existing[$Matches[1]] = $Matches[2] }
        }
    }

    # Merge: apply managed overrides onto existing keys
    foreach ($kv in $managed.GetEnumerator()) { $existing[$kv.Key] = $kv.Value }

    $summary = ($managed.Keys | ForEach-Object { "$($_ -replace '^setting\.',''): $($managed[$_])" }) -join "`n"
    $r = [System.Windows.MessageBox]::Show(
        "Write optimized video.txt ($tier tier)?`n`nOriginal → video.txt.bak`n`nSettings:`n$summary",
        "Confirm Write","YesNo","Question")
    if ($r -ne "Yes") { return }

    try {
        $bakPath = "$Script:VideoTxtPath.bak"
        # Only create backup if one doesn't already exist — preserve the original
        $bakMade = $false
        if ((Test-Path $Script:VideoTxtPath) -and -not (Test-Path $bakPath)) {
            Copy-Item $Script:VideoTxtPath $bakPath -Force
            $bakMade = $true
        }

        $dir = Split-Path $Script:VideoTxtPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null }

        $lines = @(
            '"VideoConfig"'
            '{'
            "    // CS2-Optimize Suite — $(Get-Date -Format 'yyyy-MM-dd HH:mm')  Tier: $tier"
            "    // Original backed up as video.txt.bak"
            ""
        )
        foreach ($kv in $existing.GetEnumerator() | Sort-Object Key) {
            $lines += "    `"$($kv.Key)`"`t`"$($kv.Value)`""
        }
        $lines += "}"
        # Steam Cloud can set video.txt read-only — clear the flag before writing
        if ((Test-Path $Script:VideoTxtPath) -and (Get-Item $Script:VideoTxtPath).IsReadOnly) {
            try { (Get-Item $Script:VideoTxtPath).IsReadOnly = $false }
            catch {
                [System.Windows.MessageBox]::Show(
                    "video.txt is read-only (Steam Cloud may be syncing).`n`nTry disabling Steam Cloud sync for CS2:`nSteam → CS2 → Properties → General → Steam Cloud",
                    "Read-Only File", "OK", "Warning")
                return
            }
        }
        [System.IO.File]::WriteAllLines($Script:VideoTxtPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))

        $backupMsg = if ($bakMade) { "Original saved as video.txt.bak" } else { "Backup preserved as video.txt.bak (from first run)" }
        [System.Windows.MessageBox]::Show("video.txt written ($tier tier).`n$backupMsg`n`n$Script:VideoTxtPath","Done")
        Load-Video
    } catch { [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)","Write Failed") }
}
(El "BtnVideoWrite"      ).Add_Click($writeVideo)
(El "BtnVideoWriteFooter").Add_Click($writeVideo)

# ══════════════════════════════════════════════════════════════════════════════
# SETTINGS
# ══════════════════════════════════════════════════════════════════════════════
function Load-Settings {
    $state = $null
    try { if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } } catch { Write-DebugLog "Settings state load failed: $($_.Exception.Message)" }

    $prof = if ($state) { $state.profile } else { "RECOMMENDED" }
    switch ($prof) {
        "SAFE"        { (El "RadioSafe"       ).IsChecked = $true }
        "COMPETITIVE" { (El "RadioCompetitive").IsChecked = $true }
        "CUSTOM"      { (El "RadioCustom"     ).IsChecked = $true }
        "YOLO"        { (El "RadioYolo"       ).IsChecked = $true }
        default       { (El "RadioRecommended").IsChecked = $true }
    }

    $dry = if ($state) { $state.mode -eq "DRY-RUN" } else { $false }
    (El "ChkDryRun").IsChecked = $dry
}

function Save-SettingsToState {
    $prof = if ((El "RadioSafe").IsChecked)        { "SAFE"
            } elseif ((El "RadioYolo").IsChecked)        { "YOLO"
            } elseif ((El "RadioCompetitive").IsChecked) { "COMPETITIVE"
            } elseif ((El "RadioCustom").IsChecked)      { "CUSTOM"
            } else                                        { "RECOMMENDED" }
    $dry  = (El "ChkDryRun").IsChecked -eq $true
    $mode = if ($dry) { "DRY-RUN" } else {
        switch ($prof) { "SAFE" {"AUTO"} "RECOMMENDED" {"AUTO"} "COMPETITIVE" {"CONTROL"} "CUSTOM" {"INFORMED"} "YOLO" {"YOLO"} }
    }
    try {
        $state = $null
        if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        # Skip write if nothing changed
        if ($state -and $state.PSObject.Properties['profile'] -and $state.PSObject.Properties['mode'] -and $state.profile -eq $prof -and $state.mode -eq $mode) { return }
        if (-not $state) { $state = [PSCustomObject]@{ mode = $mode; profile = $prof } }
        $state | Add-Member -NotePropertyName "profile" -NotePropertyValue $prof -Force
        $state | Add-Member -NotePropertyName "mode"    -NotePropertyValue $mode -Force
        Save-JsonAtomic -Data $state -Path $CFG_StateFile
        Set-SecureAcl -Path $CFG_StateFile
    } catch {
        Write-DebugLog "Settings state save failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Failed to save settings:`n$($_.Exception.Message)`n`nYour profile/mode change was NOT persisted. Terminal operations may use the previous settings.",
            "Settings Save Error", "OK", "Warning")
    }
}

foreach ($rb in @("RadioSafe","RadioRecommended","RadioCompetitive","RadioCustom","RadioYolo")) {
    (El $rb).Add_Checked({
        $prof = if ((El "RadioSafe").IsChecked)        { "SAFE"
                } elseif ((El "RadioYolo").IsChecked)        { "YOLO"
                } elseif ((El "RadioCompetitive").IsChecked) { "COMPETITIVE"
                } elseif ((El "RadioCustom").IsChecked)      { "CUSTOM"
                } else                                        { "RECOMMENDED" }
        (El "SbProfile").Text = "Profile: $prof"
        Save-SettingsToState
    })
}

(El "ChkDryRun").Add_Checked({   (El "SbDryRun").Text = "DRY-RUN"; (El "SbDryRunBadge").Visibility = "Visible"; Save-SettingsToState })
(El "ChkDryRun").Add_Unchecked({ (El "SbDryRun").Text = "";          (El "SbDryRunBadge").Visibility = "Collapsed"; Save-SettingsToState })

(El "BtnSettingsPhase1").Add_Click({ Launch-Terminal "Run-Optimize.ps1" })

# ══════════════════════════════════════════════════════════════════════════════
# SHARED HELPERS
# ══════════════════════════════════════════════════════════════════════════════
function Launch-Terminal {
    param([string]$Script, [string]$ScriptArgs = "")
    $fileArg = "`"$Script:Root\$Script`""
    $allArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File $fileArg"
    if ($ScriptArgs) { $allArgs += " `"$ScriptArgs`"" }
    Start-Process powershell -ArgumentList $allArgs
}
