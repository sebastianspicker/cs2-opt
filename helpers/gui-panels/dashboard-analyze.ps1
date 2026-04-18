# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD
# ══════════════════════════════════════════════════════════════════════════════
function Load-Dashboard {
    if (([datetime]::Now - $Script:DashboardLastLoad).TotalSeconds -lt 30) { return }
    $Script:DashboardLastLoad = [datetime]::Now

    # Progress from progress.json
    try {
        $prog = Load-Progress
        if ($prog) {
            $allDone = @($prog.completedSteps) + @($prog.skippedSteps)
            $p1Done = if ($prog.phase -ge 1) {
                @($allDone | Where-Object { $_ -match "^P1:" }).Count
            } else { 0 }
            $p2Done = @($allDone | Where-Object { $_ -match "^P2:" }).Count
            $p3Done = if ($prog.phase -ge 3) {
                @($allDone | Where-Object { $_ -match "^P3:" }).Count
            } else { 0 }
            $Window.Dispatcher.Invoke({
                (El "ProgressP1").Value   = $p1Done
                (El "ProgressP1Txt").Text = "$p1Done / 38"
                (El "ProgressP2").Value   = $p2Done
                (El "ProgressP2Txt").Text = "$p2Done / 3"
                (El "ProgressP3").Value   = $p3Done
                (El "ProgressP3Txt").Text = "$p3Done / 13"
            })
        }
    } catch { Write-DebugLog "Dashboard progress load failed: $($_.Exception.Message)" }

    # Benchmark history
    try {
        $hist = @(Get-BenchmarkHistory)
        if ($hist -and $hist.Count -ge 2) {
            $first = $hist[0]; $last = $hist[-1]
            $dAvg  = if ($first.avgFps -gt 0) { [math]::Round(($last.avgFps - $first.avgFps) / $first.avgFps * 100, 1) } else { 0 }
            $dP1   = if ($first.p1Fps -gt 0)  { [math]::Round(($last.p1Fps  - $first.p1Fps)  / $first.p1Fps  * 100, 1) } else { 0 }
            $Window.Dispatcher.Invoke({
                (El "DashPerfBaseline").Text = "Baseline:  avg $($first.avgFps) fps   1%low $($first.p1Fps) fps"
                (El "DashPerfLatest"  ).Text = "Latest:    avg $($last.avgFps) fps   1%low $($last.p1Fps) fps"
                $sign   = if ($dAvg -gt 0) { "+" } else { "" }
                $signP1 = if ($dP1  -gt 0) { "+" } else { "" }
                (El "DashPerfDelta"   ).Text = "Δ avg: ${sign}${dAvg}%   Δ 1%low: ${signP1}${dP1}%"
                (El "DashPerfDelta"   ).Foreground = if ($dAvg -gt 0) { New-Brush "#22c55e" } elseif ($dAvg -lt 0) { New-Brush "#ef4444" } else { New-Brush "#6b7280" }
            })
        } elseif ($hist -and $hist.Count -eq 1) {
            $Window.Dispatcher.Invoke({
                (El "DashPerfBaseline").Text = "Baseline: avg $($hist[0].avgFps) fps  1%low $($hist[0].p1Fps) fps"
                (El "DashPerfLatest").Text = ""
                (El "DashPerfDelta").Text = ""
            })
        }
    } catch { Write-DebugLog "Dashboard benchmark history load failed: $($_.Exception.Message)" }

    # Hardware (async)
    Invoke-Async -Work {
        param($ScriptRoot, $UISync)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"
        try {
            $cpu  = (Get-CachedCpuInfo).Name
            $gpu  = Get-NvidiaDriverVersion
            $gpuN = if ($gpu) { $gpu.Name } else {
                (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1).Caption }
            $gpuD = if ($gpu) { "Driver $($gpu.Version)" } else { "" }
            $ram  = Get-RamInfo
            $dc   = Test-DualChannel
            $nic  = Get-ActiveNicAdapter
            $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $hags = try { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" -ErrorAction Stop).HwSchMode } catch { $null }
            $cs2  = Get-CS2InstallPath
            $stPath = Get-SteamPath
            $vtxt = if ($stPath) { Get-ChildItem "$stPath\userdata\*\730\local\cfg\video.txt" -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
            $optExists = if ($cs2) { Test-Path "$cs2\game\csgo\cfg\optimization.cfg" } else { $false }
            $UISync.Hw = @{
                CpuName  = $cpu
                GpuName  = $gpuN; GpuDriver = $gpuD; GpuVendor = (Get-ChipsetVendor)
                RamGb    = if ($ram) { "$($ram.TotalGB) GB" } else { "?" }
                RamSpeed = if ($ram) { "$($ram.ActiveMhz) MT/s$(if (-not $ram.AtRatedSpeed) {' (below rated)'})" } else { "" }
                RamXmp   = if ($ram) { if ($ram.AtRatedSpeed) { "✓ Running at rated speed" } else { "⚠ Below rated speed — enable XMP/EXPO" } } else { "" }
                RamXmpOk = if ($ram) { $ram.AtRatedSpeed } else { $false }
                DualCh   = if ($dc) { $dc.Reason } else { "" }
                DualChOk = if ($dc) { $dc.DualChannel } else { $false }
                NicName  = if ($nic) { $nic.Name } else { "Not found" }
                NicSpeed = if ($nic) { "$([math]::Round($nic.Speed/1e6)) Mbps" } else { "" }
                NicType  = if ($nic) { "✓ Wired" } else { "⚠ No active wired NIC" }
                NicOk    = ($null -ne $nic)
                OsName   = if ($os) { $os.Caption -replace "Microsoft Windows ", "Windows " } else { "?" }
                OsBuild  = if ($os) { "Build $($os.BuildNumber)" } else { "" }
                HagsStr  = switch ($hags) { 2 {"HAGS: Enabled"} 1 {"HAGS: Disabled"} 0 {"HAGS: Disabled"} $null {"HAGS: Not set"} default {"HAGS: $hags"} }
                Cs2Found = ($null -ne $cs2)
                Cs2Path  = if ($cs2) { "CS2 installed" } else { "CS2 not found" }
                OptCfg   = if ($optExists) { "optimization.cfg: present" } else { "optimization.cfg: missing" }
                VideoTxt = if ($vtxt) { "video.txt: present" } else { "video.txt: missing" }
                OptOk    = $optExists
                VtxtOk   = ($null -ne $vtxt)
            }
        } catch { $UISync.HwErr = $_.Exception.Message }
        $UISync.HwDone = $true
    } -WorkArgs @($Script:Root, $Script:UISync) -OnDone {
        $hw = $Script:UISync.Hw
        if (-not $hw) {
            $hwErr = $Script:UISync.HwErr
            (El "CardCpuName").Text = if ($hwErr) { "Error: $hwErr" } else { "Detection failed" }
            return
        }
        (El "CardCpuName" ).Text = if ($hw.CpuName) { $hw.CpuName } else { "Unknown CPU" }
        (El "CardGpuName"  ).Text = if ($hw.GpuName) { $hw.GpuName } else { "Unknown GPU" }
        (El "CardGpuVendor").Text = if ($hw.GpuVendor) { $hw.GpuVendor } else { "" }
        (El "CardGpuDriver").Text = $hw.GpuDriver
        (El "CardRamSize" ).Text = $hw.RamGb
        (El "CardRamSpeed").Text = $hw.RamSpeed
        (El "CardRamXmp"  ).Text = $hw.RamXmp
        (El "CardRamXmp"  ).Foreground = if ($hw.RamXmpOk) { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
        (El "CardNicName" ).Text = $hw.NicName
        (El "CardNicSpeed").Text = $hw.NicSpeed
        (El "CardNicType" ).Text = $hw.NicType
        (El "CardNicType" ).Foreground = if ($hw.NicOk) { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
        (El "CardOsName"  ).Text = $hw.OsName
        (El "CardOsBuild" ).Text = $hw.OsBuild
        (El "CardOsHags"  ).Text = $hw.HagsStr
        (El "CardCs2Status").Text = $hw.Cs2Path
        (El "CardCs2Status").Foreground = if ($hw.Cs2Found) { New-Brush "#22c55e" } else { New-Brush "#ef4444" }
        (El "CardCs2Cfg"  ).Text = $hw.OptCfg
        (El "CardCs2Cfg"  ).Foreground = if ($hw.OptOk)  { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
        (El "CardCs2Video").Text = $hw.VideoTxt
        (El "CardCs2Video").Foreground = if ($hw.VtxtOk) { New-Brush "#22c55e" } else { New-Brush "#fbbf24" }
    }
}

# Quick action buttons
(El "BtnDashAnalyze"  ).Add_Click({ Switch-Panel "PanelAnalyze"; Start-Analysis })
(El "BtnDashVerify"   ).Add_Click({ Switch-Panel "PanelOptimize"; Load-Optimize; Start-InlineVerify })
(El "BtnDashBackup"   ).Add_Click({ Switch-Panel "PanelBackup"; Load-Backup })
(El "BtnDashPhase1"   ).Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnDashLaunchCs2").Add_Click({ Start-Process "steam://rungameid/730" })

# ══════════════════════════════════════════════════════════════════════════════
# ANALYZE
# ══════════════════════════════════════════════════════════════════════════════
function Start-Analysis {
    (El "BtnRunAnalysis").IsEnabled = $false
    (El "BtnRunAnalysis").Content   = "Scanning…"
    (El "AnalyzeScanTime").Text     = "Scanning…"
    (El "AnalysisGrid").ItemsSource = $null

    Invoke-Async -Work {
        param($ScriptRoot, $UISync)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"
        . "$ScriptRoot\helpers\system-analysis.ps1"
        try { $UISync.AnalysisResults = Invoke-SystemAnalysis }
        catch { $UISync.AnalysisError = $_.Exception.Message }
    } -WorkArgs @($Script:Root, $Script:UISync) -OnDone {
        $analysisErr = $Script:UISync.AnalysisError
        $res = $Script:UISync.AnalysisResults
        if (-not $res) { $res = @() }
        (El "AnalysisGrid").ItemsSource = $res
        $ok   = @($res | Where-Object Status -eq "OK").Count
        $warn = @($res | Where-Object Status -eq "WARN").Count
        $err  = @($res | Where-Object Status -eq "ERR").Count
        (El "AnalyzeSummary" ).Text = "✓ $ok   ⚠ $warn   ✗ $err"
        if ($analysisErr) {
            (El "AnalyzeScanTime").Text = "Scan error: $analysisErr"
        } else {
            (El "AnalyzeScanTime").Text = "Last scan: $(Get-Date -Format 'HH:mm  dd-MMM-yyyy')  ·  $($res.Count) checks"
        }
        (El "BtnRunAnalysis" ).IsEnabled = $true
        (El "BtnRunAnalysis" ).Content   = "▶  Run Full Scan"
        if ($warn + $err -gt 0) {
            (El "DashIssueHint").Text = "⚠  $($warn+$err) item(s) need attention — see Analyze panel"
        }
        Refresh-StorageHealthCard
        # Clear for next run
        $Script:UISync.AnalysisError   = $null
        $Script:UISync.AnalysisResults = $null
    }
}

(El "BtnRunAnalysis"   ).Add_Click({ Start-Analysis })
(El "BtnAnalyzeGotoOpt").Add_Click({ Switch-Panel "PanelOptimize"; Load-Optimize })
(El "BtnAnalyzeExport" ).Add_Click({
    $res = (El "AnalysisGrid").ItemsSource
    if (-not $res) { return }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dlg.FileName = "cs2-analyze-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    if ($dlg.ShowDialog() -eq $true) {
        try {
            $res | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
            [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)", "Export Complete")
        } catch {
            [System.Windows.MessageBox]::Show("Export failed:`n$_`n`nCheck that the file is not open in another program.", "Export Error", "OK", "Error")
        }
    }
})

function Refresh-StorageHealthCard {
    try {
        $trim = Get-TrimHealthStatus
        (El "AnalyzeStorageHealth").Text = "Storage maintenance: $($trim.Summary)"
        (El "BtnAnalyzeTrimEnable").IsEnabled = $trim.AnyTrimDisabled
        (El "BtnAnalyzeRetrim").IsEnabled = $trim.RetrimAvailable
        if ($trim.RetrimAvailable) {
            (El "BtnAnalyzeRetrim").ToolTip = "ReTrim available on: $(@($trim.RetrimmableVolumes) -join ', ')"
        }
    } catch {
        (El "AnalyzeStorageHealth").Text = "Storage maintenance: state not readable"
        (El "BtnAnalyzeTrimEnable").IsEnabled = $false
        (El "BtnAnalyzeRetrim").IsEnabled = $false
    }
}

(El "BtnAnalyzeStorageRefresh").Add_Click({ Refresh-StorageHealthCard })
(El "BtnAnalyzeTrimEnable").Add_Click({
    try {
        $result = Enable-TrimSupport
        if ($result.Success) {
            [System.Windows.MessageBox]::Show("TRIM support enabled. This is storage maintenance/correctness, not a gaming-meta claim.", "Storage Health")
        } else {
            [System.Windows.MessageBox]::Show("Enable TRIM failed.`n$(@($result.Output) -join [Environment]::NewLine)", "Storage Health", "OK", "Warning")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Enable TRIM failed:`n$($_.Exception.Message)", "Storage Health", "OK", "Error")
    }
    Refresh-StorageHealthCard
})
(El "BtnAnalyzeRetrim").Add_Click({
    try {
        $trim = Get-TrimHealthStatus
        $volumes = @($trim.RetrimmableVolumes)
        if ($volumes.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No eligible fixed volumes were detected for ReTrim.", "Storage Health", "OK", "Warning")
            return
        }
        $confirm = [System.Windows.MessageBox]::Show(
            "Run ReTrim on: $($volumes -join ', ')?`n`nThis is a storage-maintenance action, not an FPS optimization.",
            "Storage Health", "YesNo", "Question")
        if ($confirm -ne "Yes") { return }
        foreach ($drive in $volumes) {
            Invoke-StorageRetrim -DriveLetter $drive
        }
        [System.Windows.MessageBox]::Show("ReTrim completed for: $($volumes -join ', ')", "Storage Health")
    } catch {
        [System.Windows.MessageBox]::Show("ReTrim failed:`n$($_.Exception.Message)", "Storage Health", "OK", "Error")
    }
    Refresh-StorageHealthCard
})
