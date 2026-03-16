# ==============================================================================
#  helpers/gui-panels.ps1  —  GUI Panel Functions & Event Handlers
# ==============================================================================
#
#  Extracted from CS2-Optimize-GUI.ps1 to keep the main file under 800 lines.
#  Dot-sourced into the same scope — all functions have access to $Window, El(),
#  $Script:UISync, $Script:Root, and all helper modules.
#
#  Panels: Dashboard, Analyze, Optimize, Backup, Benchmark, Video, Settings
#  Shared: Launch-Terminal, Save-SettingsToState

# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD
# ══════════════════════════════════════════════════════════════════════════════
function Load-Dashboard {
    # Progress from progress.json
    try {
        $prog = Load-Progress
        if ($prog) {
            $allDone = @($prog.completedSteps) + @($prog.skippedSteps)
            $p1Done = if ($prog.phase -ge 1) {
                @($allDone | Where-Object { $_ -match "^P1:" }).Count
            } else { 0 }
            $p3Done = if ($prog.phase -ge 3) {
                @($allDone | Where-Object { $_ -match "^P3:" }).Count
            } else { 0 }
            $Window.Dispatcher.Invoke({
                (El "ProgressP1").Value   = $p1Done
                (El "ProgressP1Txt").Text = "$p1Done / 38"
                (El "ProgressP3").Value   = $p3Done
                (El "ProgressP3Txt").Text = "$p3Done / 13"
            })
        }
    } catch {}

    # Benchmark history
    try {
        $hist = Get-BenchmarkHistory
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
            $Window.Dispatcher.Invoke({ (El "DashPerfBaseline").Text = "Baseline: avg $($hist[0].avgFps) fps  1%low $($hist[0].p1Fps) fps" })
        }
    } catch {}

    # Hardware (async)
    Invoke-Async -Work {
        param($ScriptRoot, $UISync)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"
        try {
            $cpu  = (Get-CimInstance Win32_Processor -Property Name -ErrorAction SilentlyContinue | Select-Object -First 1).Name
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
            $stPath = if ($ScriptRoot) { (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath } else { $null }
            $vtxt = if ($stPath) { Get-ChildItem "$stPath\userdata\*\730\local\cfg\video.txt" -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
            $optExists = if ($cs2) { Test-Path "$cs2\game\csgo\cfg\optimization.cfg" } else { $false }
            $UISync.Hw = @{
                CpuName  = $cpu
                GpuName  = $gpuN; GpuDriver = $gpuD
                RamGb    = if ($ram) { "$($ram.TotalGB) GB" } else { "?" }
                RamSpeed = if ($ram) { "$($ram.ActiveMhz) MHz$(if ($ram.XmpActive) {' XMP'} else {' (JEDEC)'})" } else { "" }
                RamXmp   = if ($ram) { if ($ram.XmpActive) { "✓ XMP active" } else { "⚠ XMP not active" } } else { "" }
                RamXmpOk = if ($ram) { $ram.XmpActive } else { $false }
                DualCh   = if ($dc) { $dc.Reason } else { "" }
                DualChOk = if ($dc) { $dc.DualChannel } else { $false }
                NicName  = if ($nic) { $nic.Name } else { "Not found" }
                NicSpeed = if ($nic) { "$([math]::Round($nic.LinkSpeed/1e6)) Mbps" } else { "" }
                NicType  = if ($nic) { "✓ Wired" } else { "⚠ No active wired NIC" }
                NicOk    = ($null -ne $nic)
                OsName   = if ($os) { $os.Caption -replace "Microsoft Windows ", "Windows " } else { "?" }
                OsBuild  = if ($os) { "Build $($os.BuildNumber)" } else { "" }
                HagsStr  = switch ($hags) { 2 {"HAGS: Enabled"} 1 {"HAGS: Disabled"} $null {"HAGS: Not set"} default {"HAGS: $hags"} }
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
        if (-not $hw) { return }
        (El "CardCpuName" ).Text = if ($hw.CpuName) { $hw.CpuName } else { "Unknown CPU" }
        (El "CardGpuName"  ).Text = if ($hw.GpuName) { $hw.GpuName } else { "Unknown GPU" }
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
    }.GetNewClosure()
}

# Quick action buttons
(El "BtnDashAnalyze"  ).Add_Click({ Switch-Panel "PanelAnalyze"; Start-Analysis })
(El "BtnDashVerify"   ).Add_Click({ Launch-Terminal "Verify-Settings.ps1" })
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
        $res = $Script:UISync.AnalysisResults
        if (-not $res) { $res = @() }
        (El "AnalysisGrid").ItemsSource = $res
        $ok   = @($res | Where-Object Status -eq "OK").Count
        $warn = @($res | Where-Object Status -eq "WARN").Count
        $err  = @($res | Where-Object Status -eq "ERR").Count
        (El "AnalyzeSummary" ).Text = "✓ $ok   ⚠ $warn   ✗ $err"
        (El "AnalyzeScanTime").Text = "Last scan: $(Get-Date -Format 'HH:mm  dd-MMM-yyyy')  ·  $($res.Count) checks"
        (El "BtnRunAnalysis" ).IsEnabled = $true
        (El "BtnRunAnalysis" ).Content   = "▶  Run Full Scan"
        if ($warn + $err -gt 0) {
            (El "DashIssueHint").Text = "⚠  $($warn+$err) item(s) need attention — see Analyze panel"
        }
    }.GetNewClosure()
}

(El "BtnRunAnalysis"   ).Add_Click({ Start-Analysis })
(El "BtnAnalyzeGotoOpt").Add_Click({ Switch-Panel "PanelOptimize"; Load-Optimize })
(El "BtnAnalyzeExport" ).Add_Click({
    $res = (El "AnalysisGrid").ItemsSource
    if (-not $res) { return }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dlg.FileName = "cs2-analyze-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    if ($dlg.ShowDialog()) {
        try {
            $res | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
            [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)", "Export Complete")
        } catch {
            [System.Windows.MessageBox]::Show("Export failed:`n$_`n`nCheck that the file is not open in another program.", "Export Error", "OK", "Error")
        }
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# OPTIMIZE
# ══════════════════════════════════════════════════════════════════════════════
function Load-Optimize {
    $prog = $null
    try { $prog = Load-Progress } catch {}
    $completed = if ($prog) { $prog.completedSteps } else { @() }
    $skipped   = if ($prog) { $prog.skippedSteps }   else { @() }

    $estimates = $CFG_ImprovementEstimates

    $rows = foreach ($s in $SCRIPT:StepCatalog) {
        $stepKey = "P$($s.Phase):$($s.Step)"
        $isDone  = $stepKey -in $completed -or $s.Step -in $completed
        $isSkip  = $stepKey -in $skipped -or $s.Step -in $skipped

        $statusKey   = if ($s.CheckOnly) { "Check" } elseif ($isDone) { "Done" } elseif ($isSkip) { "Skipped" } else { "Pending" }
        $statusLabel = if ($s.CheckOnly) { "—  Check" } elseif ($isDone) { "✓  Done" } elseif ($isSkip) { "—  Skipped" } else { "○  Pending" }
        $statusColor = if ($s.CheckOnly) { "#6b7280" } elseif ($isDone) { "#22c55e" } elseif ($isSkip) { "#374151" } else { "#fbbf24" }

        $tierColor = switch ($s.Tier) { 1 { "#22c55e" } 2 { "#fbbf24" } 3 { "#e8520a" } default { "#6b7280" } }
        $riskColor = switch ($s.Risk) {
            "SAFE"       { "#22c55e" } "MODERATE"   { "#fbbf24" }
            "AGGRESSIVE" { "#e8520a" } "CRITICAL"   { "#ef4444" }
            default      { "#6b7280" }
        }

        $est = ""
        if ($s.EstKey -and $estimates.ContainsKey($s.EstKey)) {
            $e = $estimates[$s.EstKey]
            if ($e.P1LowMin -ne 0 -or $e.P1LowMax -ne 0) {
                $est = "+$($e.P1LowMin)-$($e.P1LowMax)% P1"
            }
        }

        [PSCustomObject]@{
            PhLabel     = "P$($s.Phase)"
            StepLabel   = "$($s.Step)"
            Category    = $s.Category
            Title       = $s.Title
            Tier        = $s.Tier
            TierLabel   = "T$($s.Tier)"
            TierColor   = $tierColor
            Risk        = $s.Risk
            RiskColor   = $riskColor
            StatusKey   = $statusKey
            StatusLabel = $statusLabel
            StatusColor = $statusColor
            RebootLabel = if ($s.Reboot) { "Yes" } else { "" }
            EstLabel    = $est
            _Step       = $s
        }
    }

    $SCRIPT:OptimizeAllRows = $rows
    (El "OptimizeGrid").ItemsSource = $rows

    # Populate category filter
    $cats = @("All") + ($rows | Select-Object -ExpandProperty Category -Unique | Sort-Object)
    (El "OptFilterCat").ItemsSource   = $cats
    (El "OptFilterCat").SelectedIndex = 0

    $statuses = @("All", "Pending", "Done", "Skipped", "Check")
    (El "OptFilterStatus").ItemsSource   = $statuses
    (El "OptFilterStatus").SelectedIndex = 0
}

(El "OptFilterCat"   ).Add_SelectionChanged({ Filter-OptimizeGrid })
(El "OptFilterStatus").Add_SelectionChanged({ Filter-OptimizeGrid })

function Filter-OptimizeGrid {
    $cat    = (El "OptFilterCat").SelectedItem
    $status = (El "OptFilterStatus").SelectedItem
    $all    = $SCRIPT:OptimizeAllRows
    if (-not $all) { return }
    $filtered = $all | Where-Object {
        ($cat    -eq "All" -or $_.Category -eq $cat) -and
        ($status -eq "All" -or $_.StatusKey -eq $status)
    }
    (El "OptimizeGrid").ItemsSource = @($filtered)
}

(El "BtnOptPhase1"   ).Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnOptPhase3"   ).Add_Click({ Launch-Terminal "PostReboot-Setup.ps1" })
(El "BtnOptFullSetup").Add_Click({ Launch-Terminal "Run-Optimize.ps1" })
(El "BtnOptVerify"   ).Add_Click({ Launch-Terminal "Verify-Settings.ps1" })

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP
# ══════════════════════════════════════════════════════════════════════════════
function Load-Backup {
    try {
        $bd = Get-BackupData
        if (-not $bd -or -not $bd.entries) {
            (El "BackupSummary").Text = "No backups found in backup.json"
            (El "BackupGrid").ItemsSource = $null
            return
        }
        $entries = $bd.entries
        (El "BackupSummary").Text = "$($entries.Count) backup entries  ·  Created $($bd.created)"

        $rows = foreach ($e in $entries) {
            $key = switch ($e.type) {
                "registry"      { "$($e.path)  →  $($e.name)" }
                "service"       { $e.name }
                "bootconfig"    { $e.key }
                "powerplan"     { "Power Plan: $($e.originalName)" }
                "drs"           { "DRS Profile: $($e.profile)  ($($e.settings.Count) settings)" }
                "scheduledtask" { "Task: $($e.taskName)" }
                default         { "$($e.type)" }
            }
            $orig = switch ($e.type) {
                "registry"      { if ($e.existed) { "$($e.originalValue)" } else { "(new key)" } }
                "service"       { "$($e.originalStartType) / $($e.originalStatus)" }
                "bootconfig"    { if ($e.existed) { $e.originalValue } else { "(new)" } }
                "powerplan"     { $e.originalGuid }
                "drs"           { "$($e.settings.Count) settings" }
                "scheduledtask" { if ($e.existed) { "existed" } else { "(new)" } }
                default         { "" }
            }
            [PSCustomObject]@{
                Step      = $e.step
                Type      = $e.type
                Key       = $key
                Original  = $orig
                Timestamp = $e.timestamp
                _Entry    = $e
            }
        }
        (El "BackupGrid").ItemsSource = $rows
    } catch {
        (El "BackupSummary").Text = "Error loading backup.json: $($_.Exception.Message)"
    }
}

(El "BtnBackupRefresh").Add_Click({ Load-Backup })

(El "BtnBackupExport").Add_Click({
    $src = "$CFG_WorkDir\backup.json"
    if (-not (Test-Path $src)) { [System.Windows.MessageBox]::Show("backup.json not found.","Export"); return }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $dlg.FileName = "cs2-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
    if ($dlg.ShowDialog()) { Copy-Item $src $dlg.FileName -Force; [System.Windows.MessageBox]::Show("Exported to:`n$($dlg.FileName)","Export Complete") }
})

(El "BtnRestoreAll").Add_Click({
    $r = [System.Windows.MessageBox]::Show("Restore ALL backed-up settings?`nThis will undo every change the suite made.","Restore All","YesNo","Warning")
    if ($r -eq "Yes") {
        try {
            # Call step restores directly — Restore-AllChanges uses Read-Host which blocks GUI (no console)
            $bd = Get-BackupData
            if ($bd.entries -and $bd.entries.Count -gt 0) {
                $stepNames = @(($bd.entries | Group-Object -Property step).Name)
                $failures = 0
                foreach ($sn in $stepNames) { if (-not (Restore-StepChanges -StepTitle $sn)) { $failures++ } }
                if ($failures -gt 0) { throw "$failures step group(s) had restore failures." }
            }
            [System.Windows.MessageBox]::Show("All settings restored successfully.","Restore Complete")
            Load-Backup
        } catch {
            [System.Windows.MessageBox]::Show("Restore error: $($_.Exception.Message)","Restore Failed","OK","Error")
        }
    }
})

(El "BtnRestoreStep").Add_Click({
    $sel = (El "BackupGrid").SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Select a row first.","Restore Step"); return }
    $stepTitle = $sel.Step
    $r = [System.Windows.MessageBox]::Show("Restore all changes from:`n`"$stepTitle`"?","Restore Step","YesNo","Question")
    if ($r -eq "Yes") {
        try {
            Restore-StepChanges $stepTitle
            [System.Windows.MessageBox]::Show("Restore complete for:`n$stepTitle","Done")
            Load-Backup
        } catch { [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)","Restore Failed") }
    }
})

(El "BtnClearBackup").Add_Click({
    $r = [System.Windows.MessageBox]::Show("Delete all backup data?`nThis cannot be undone.","Clear Backups","YesNo","Warning")
    if ($r -eq "Yes") {
        if (Test-Path "$CFG_WorkDir\backup.json") { Remove-Item "$CFG_WorkDir\backup.json" -Force }
        Load-Backup
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# BENCHMARK
# ══════════════════════════════════════════════════════════════════════════════
function Load-Benchmark {
    try {
        $hist = Get-BenchmarkHistory
        if (-not $hist -or $hist.Count -eq 0) {
            (El "BenchGrid").ItemsSource = $null
            return
        }

        $rows = for ($i = 0; $i -lt $hist.Count; $i++) {
            $h = $hist[$i]
            $dAvg = if ($i -eq 0) { "—" } else {
                $prev = $hist[$i - 1]
                $d = if ($prev.avgFps -gt 0) { [math]::Round(($h.avgFps - $prev.avgFps) / $prev.avgFps * 100, 1) } else { 0 }
                if ($d -gt 0) { "+$d%" } else { "$d%" }
            }
            $dP1 = if ($i -eq 0) { "—" } else {
                $prev = $hist[$i - 1]
                $d = if ($prev.p1Fps -gt 0) { [math]::Round(($h.p1Fps - $prev.p1Fps) / $prev.p1Fps * 100, 1) } else { 0 }
                if ($d -gt 0) { "+$d%" } else { "$d%" }
            }
            $dc = if ($i -eq 0 -or $dAvg -eq "—") { "#6b7280" } elseif ($dAvg.StartsWith("+")) { "#22c55e" } elseif ($dAvg -eq "0%" -or $dAvg -eq "0.0%") { "#6b7280" } else { "#ef4444" }
            $dateStr = try { [datetime]::ParseExact($h.timestamp,"yyyy-MM-dd HH:mm:ss",$null).ToString("dd-MMM HH:mm") } catch { $h.timestamp }
            [PSCustomObject]@{
                Index      = $h.index
                Date       = $dateStr
                Label      = $h.label
                AvgFps     = [math]::Round($h.avgFps, 0)
                P1Fps      = [math]::Round($h.p1Fps,  0)
                DeltaAvg   = $dAvg
                DeltaP1    = $dP1
                DeltaColor = $dc
            }
        }
        (El "BenchGrid").ItemsSource = $rows
        Draw-BenchChart $hist
    } catch { }
}

function Draw-BenchChart {
    param($hist)
    $canvas = El "BenchChart"
    $canvas.Children.Clear()
    if (-not $hist -or $hist.Count -lt 2) { return }

    # Wait for layout
    $canvas.UpdateLayout()
    $w = if ($canvas.ActualWidth  -gt 0) { $canvas.ActualWidth  } else { 600 }
    $h = if ($canvas.ActualHeight -gt 0) { $canvas.ActualHeight } else { 130 }

    $allFps = ($hist | ForEach-Object { $_.avgFps, $_.p1Fps }) | Measure-Object -Maximum -Minimum
    $maxF = $allFps.Maximum * 1.08
    $minF = $allFps.Minimum * 0.92
    $range = $maxF - $minF
    if ($range -le 0) { $range = 1 }

    $xStep = $w / ($hist.Count - 1)
    $toY   = { param($v) $h - (($v - $minF) / $range * $h) }

    # Grid lines
    foreach ($pct in @(0.25, 0.5, 0.75)) {
        $y = $h * $pct
        $gl = [System.Windows.Shapes.Line]::new()
        $gl.X1 = 0; $gl.X2 = $w; $gl.Y1 = $y; $gl.Y2 = $y
        $gl.Stroke = New-Brush "#252525"; $gl.StrokeThickness = 1
        $canvas.Children.Add($gl) | Out-Null
    }

    # Build point collections
    $avgPts = [System.Windows.Media.PointCollection]::new()
    $p1Pts  = [System.Windows.Media.PointCollection]::new()
    for ($i = 0; $i -lt $hist.Count; $i++) {
        $x = $i * $xStep
        $avgPts.Add([System.Windows.Point]::new($x, (& $toY $hist[$i].avgFps))) | Out-Null
        $p1Pts.Add( [System.Windows.Point]::new($x, (& $toY $hist[$i].p1Fps ))) | Out-Null
    }

    # Avg line
    $avgLine = [System.Windows.Shapes.Polyline]::new()
    $avgLine.Points = $avgPts
    $avgLine.Stroke = New-Brush "#e8520a"; $avgLine.StrokeThickness = 2
    $canvas.Children.Add($avgLine) | Out-Null

    # P1 line
    $p1Line = [System.Windows.Shapes.Polyline]::new()
    $p1Line.Points = $p1Pts
    $p1Line.Stroke = New-Brush "#22c55e"; $p1Line.StrokeThickness = 2; $p1Line.StrokeDashArray = [System.Windows.Media.DoubleCollection]@(4, 3)
    $canvas.Children.Add($p1Line) | Out-Null

    # Dots + x-axis labels
    for ($i = 0; $i -lt $hist.Count; $i++) {
        $x = $i * $xStep
        foreach ($pts in @($avgPts, $p1Pts)) {
            $dot = [System.Windows.Shapes.Ellipse]::new()
            $dot.Width = 6; $dot.Height = 6
            $dot.Fill = if ($pts -eq $avgPts) { New-Brush "#e8520a" } else { New-Brush "#22c55e" }
            [System.Windows.Controls.Canvas]::SetLeft($dot, $pts[$i].X - 3)
            [System.Windows.Controls.Canvas]::SetTop( $dot, $pts[$i].Y - 3)
            $canvas.Children.Add($dot) | Out-Null
        }
        # x-label
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = try { [datetime]::ParseExact($hist[$i].timestamp,"yyyy-MM-dd HH:mm:ss",$null).ToString("d-MMM") } catch { "$($i+1)" }
        $lbl.FontSize = 9; $lbl.Foreground = New-Brush "#4b5563"
        [System.Windows.Controls.Canvas]::SetLeft($lbl, $x - 16)
        [System.Windows.Controls.Canvas]::SetTop( $lbl, $h + 4)
        $canvas.Children.Add($lbl) | Out-Null
    }

    # Y-axis label
    $yLbl = [System.Windows.Controls.TextBlock]::new()
    $yLbl.Text = "FPS"; $yLbl.FontSize = 9; $yLbl.Foreground = New-Brush "#4b5563"
    [System.Windows.Controls.Canvas]::SetLeft($yLbl, -28)
    [System.Windows.Controls.Canvas]::SetTop( $yLbl, $h / 2 - 8)
    $canvas.Children.Add($yLbl) | Out-Null

    # Legend
    $leg = [System.Windows.Controls.TextBlock]::new()
    $leg.Text = "— Avg FPS   - - 1% Low"; $leg.FontSize = 9; $leg.Foreground = New-Brush "#6b7280"
    [System.Windows.Controls.Canvas]::SetLeft($leg, $w - 120)
    [System.Windows.Controls.Canvas]::SetTop( $leg, -16)
    $canvas.Children.Add($leg) | Out-Null
}

# FPS Cap
(El "BtnBenchParse").Add_Click({
    $raw = (El "BenchVprof").Text.Trim()
    if ($raw -match "Avg\s*=\s*([\d.]+)") {
        $avg = [double]$Matches[1]
        $cap = [math]::Max($CFG_FpsCap_Min, [int]($avg - [math]::Round($avg * $CFG_FpsCap_Percent)))
        (El "BenchCapLabel").Text = "→  Cap:"
        (El "BenchCapValue").Text = "$cap"
        $Script:UISync.LastCap = $cap
    } else {
        (El "BenchCapLabel").Text = "⚠  No [VProf] FPS line detected"
        (El "BenchCapValue").Text = ""
    }
})

(El "BtnBenchCopy").Add_Click({
    $cap = $Script:UISync.LastCap
    if ($cap) { [System.Windows.Clipboard]::SetText("$cap") }
})

(El "BtnBenchAdd").Add_Click({
    $raw = (El "BenchVprof").Text.Trim()
    if ($raw -match "Avg\s*=\s*([\d.]+).*P1\s*=\s*([\d.]+)") {
        $avg = [double]$Matches[1]; $p1 = [double]$Matches[2]
        $lbl = [Microsoft.VisualBasic.Interaction]::InputBox("Label for this benchmark result:", "Add Result", "")
        Add-BenchmarkResult -AvgFps $avg -P1Fps $p1 -Label $lbl -Runs 1
        Load-Benchmark
    } else {
        [System.Windows.MessageBox]::Show("Paste a [VProf] FPS: Avg=… P1=… line first.","Add Result")
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# VIDEO
# ══════════════════════════════════════════════════════════════════════════════
$Script:VideoTxtPath = $null

function Load-Video {
    # Populate tier picker
    if ((El "VideoTierPicker").Items.Count -eq 0) {
        foreach ($t in @("Auto","HIGH","MID","LOW")) { (El "VideoTierPicker").Items.Add($t) | Out-Null }
        (El "VideoTierPicker").SelectedIndex = 0
    }

    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
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
    (El "VideoSummary").Text = "$diffs setting(s) differ from $tier-tier recommendation"
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
        if (Test-Path $Script:VideoTxtPath) { Copy-Item $Script:VideoTxtPath $bakPath -Force }

        $dir = Split-Path $Script:VideoTxtPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

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
        $lines | Set-Content $Script:VideoTxtPath -Encoding UTF8

        [System.Windows.MessageBox]::Show("video.txt written ($tier tier).`nOriginal saved as video.txt.bak`n`n$Script:VideoTxtPath","Done")
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
    try { if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile | ConvertFrom-Json } } catch {}

    $prof = if ($state) { $state.profile } else { "RECOMMENDED" }
    switch ($prof) {
        "SAFE"        { (El "RadioSafe"       ).IsChecked = $true }
        "COMPETITIVE" { (El "RadioCompetitive").IsChecked = $true }
        "CUSTOM"      { (El "RadioCustom"     ).IsChecked = $true }
        default       { (El "RadioRecommended").IsChecked = $true }
    }

    $dry = if ($state) { $state.mode -eq "DRY-RUN" } else { $false }
    (El "ChkDryRun").IsChecked = $dry
    (El "RegNA").IsChecked = $true
}

function Save-SettingsToState {
    $prof = if ((El "RadioSafe").IsChecked)        { "SAFE"
            } elseif ((El "RadioCompetitive").IsChecked) { "COMPETITIVE"
            } elseif ((El "RadioCustom").IsChecked)      { "CUSTOM"
            } else                                        { "RECOMMENDED" }
    $dry  = (El "ChkDryRun").IsChecked -eq $true
    $mode = if ($dry) { "DRY-RUN" } else {
        switch ($prof) { "SAFE" {"AUTO"} "RECOMMENDED" {"AUTO"} "COMPETITIVE" {"CONTROL"} "CUSTOM" {"INFORMED"} }
    }
    try {
        $state = $null
        if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile | ConvertFrom-Json }
        # Skip write if nothing changed
        if ($state -and $state.profile -eq $prof -and $state.mode -eq $mode) { return }
        if (-not $state) { $state = [PSCustomObject]@{ mode = $mode; profile = $prof } }
        $state | Add-Member -NotePropertyName "profile" -NotePropertyValue $prof -Force
        $state | Add-Member -NotePropertyName "mode"    -NotePropertyValue $mode -Force
        Save-JsonAtomic -Data $state -Path $CFG_StateFile
    } catch {}
}

foreach ($rb in @("RadioSafe","RadioRecommended","RadioCompetitive","RadioCustom")) {
    (El $rb).Add_Checked({
        $prof = if ((El "RadioSafe").IsChecked)        { "SAFE"
                } elseif ((El "RadioCompetitive").IsChecked) { "COMPETITIVE"
                } elseif ((El "RadioCustom").IsChecked)      { "CUSTOM"
                } else                                        { "RECOMMENDED" }
        (El "SbProfile").Text = "Profile: $prof"
        Save-SettingsToState
    }.GetNewClosure())
}

(El "ChkDryRun").Add_Checked({   (El "SbDryRun").Text = "DRY-RUN ON"; Save-SettingsToState })
(El "ChkDryRun").Add_Unchecked({ (El "SbDryRun").Text = "";           Save-SettingsToState })

(El "BtnSettingsPhase1").Add_Click({ Launch-Terminal "Run-Optimize.ps1" })

# ══════════════════════════════════════════════════════════════════════════════
# SHARED HELPERS
# ══════════════════════════════════════════════════════════════════════════════
function Launch-Terminal {
    param([string]$Script, [string]$ScriptArgs = "")
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Script:Root\$Script`" $ScriptArgs" -Verb RunAs
}
