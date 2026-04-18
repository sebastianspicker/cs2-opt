# ══════════════════════════════════════════════════════════════════════════════
# BENCHMARK
# ══════════════════════════════════════════════════════════════════════════════
function Load-Benchmark {
    try {
        $hist = @(Get-BenchmarkHistory)
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
            $dp1c = if ($i -eq 0 -or $dP1 -eq "—") { "#6b7280" } elseif ($dP1.StartsWith("+")) { "#22c55e" } elseif ($dP1 -eq "0%" -or $dP1 -eq "0.0%") { "#6b7280" } else { "#ef4444" }
            $dateStr = try { [datetime]::ParseExact($h.timestamp,"yyyy-MM-dd HH:mm:ss",$null).ToString("dd-MMM HH:mm") } catch { $h.timestamp }
            [PSCustomObject]@{
                Index        = $i + 1
                Date         = $dateStr
                Label        = $h.label
                AvgFps       = [math]::Round($h.avgFps, 0)
                P1Fps        = [math]::Round($h.p1Fps,  0)
                DeltaAvg     = $dAvg
                DeltaP1      = $dP1
                DeltaColor   = $dc
                DeltaP1Color = $dp1c
            }
        }
        (El "BenchGrid").ItemsSource = $rows
        Draw-BenchChart $hist
    } catch { Write-DebugLog "Benchmark history load failed: $($_.Exception.Message)" }
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
    $parsed = Get-BenchmarkCapFromText $raw
    if ($parsed) {
        (El "BenchCapLabel").Text = "→  Cap:"
        (El "BenchCapValue").Text = "$($parsed.Cap)"
        $Script:UISync.LastCap = $parsed.Cap
    } else {
        (El "BenchCapLabel").Text = "⚠  No [VProf] FPS line detected"
        (El "BenchCapValue").Text = ""
    }
})

(El "BtnBenchCopy").Add_Click({
    $cap = $Script:UISync.LastCap
    if ($cap) {
        try { [System.Windows.Clipboard]::SetText("$cap") }
        catch { Write-DebugLog "Clipboard copy failed: $_" }
    }
})

(El "BtnBenchAdd").Add_Click({
    $raw = (El "BenchVprof").Text.Trim()
    $parsed = Get-BenchmarkResultFromText $raw
    if ($parsed) {
        $lbl = [Microsoft.VisualBasic.Interaction]::InputBox("Label for this benchmark result:", "Add Result", "")
        Add-BenchmarkResult -AvgFps $parsed.AvgFps -P1Fps $parsed.P1Fps -Label $lbl -Runs 1
        Load-Benchmark
    } else {
        [System.Windows.MessageBox]::Show("Paste a [VProf] FPS: Avg=… P1=… line first.","Add Result")
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# NETWORK
# ══════════════════════════════════════════════════════════════════════════════
function Load-NetworkDiagnostics {
    $summary = Get-NetworkDiagnosticSummary
    if (-not $summary.AdapterFound) {
        (El "NetDiagAdapterSummary").Text = "Adapter: no active adapter found"
        (El "NetDiagDnsSummary").Text = "DNS: unavailable"
    } else {
        $dnsText = if (@($summary.DnsServers).Count -gt 0) { @($summary.DnsServers) -join ', ' } else { "automatic / DHCP" }
        (El "NetDiagAdapterSummary").Text = "Adapter: $($summary.AdapterName)  ·  $($summary.AdapterType)"
        (El "NetDiagDnsSummary").Text = "DNS: $($summary.DnsProvider)  ·  $dnsText"
    }

    $historyRows = @(Get-LatencyHistoryRows)
    (El "NetDiagHistoryGrid").ItemsSource = $historyRows
    (El "NetDiagComparisonGrid").ItemsSource = @(Get-ValveLatencyComparisonRows)
    (El "NetDiagHistorySummary").Text = if ($historyRows.Count -gt 0) {
        "Latest run: $($historyRows[-1].Timestamp)  ·  $($historyRows[-1].Kind)"
    } else {
        "No latency diagnostics recorded yet."
    }
}

function Start-LatencyDiagnostic {
    param(
        [ValidateSet("baseline", "post")][string]$Kind
    )

    $buttonName = if ($Kind -eq "baseline") { "BtnNetBaseline" } else { "BtnNetPost" }
    (El "BtnNetBaseline").IsEnabled = $false
    (El "BtnNetPost").IsEnabled = $false
    (El $buttonName).Content = if ($Kind -eq "baseline") { "Running…" } else { "Retesting…" }

    Invoke-Async -Work {
        param($ScriptRoot, $UISync, $RunKind)
        . "$ScriptRoot\config.env.ps1"
        . "$ScriptRoot\helpers.ps1"
        try {
            $UISync.LatencyRun = Invoke-ValveRegionLatencyDiagnostic -Kind $RunKind
        } catch {
            $UISync.LatencyError = $_.Exception.Message
        }
    } -WorkArgs @($Script:Root, $Script:UISync, $Kind) -OnDone {
        $err = $Script:UISync.LatencyError
        Load-NetworkDiagnostics
        (El "BtnNetBaseline").IsEnabled = $true
        (El "BtnNetPost").IsEnabled = $true
        (El "BtnNetBaseline").Content = "Baseline Test"
        (El "BtnNetPost").Content = "Post-Change Retest"
        if ($err) {
            [System.Windows.MessageBox]::Show("Latency diagnostic failed:`n$err", "Network Diagnostic", "OK", "Error")
        } else {
            $run = $Script:UISync.LatencyRun
            $okRegions = @($run.Results | Where-Object { $null -ne $_.AvgRttMs }).Count
            [System.Windows.MessageBox]::Show("Saved $($run.Kind) run at $($run.Timestamp).`nResponsive regions: $okRegions / $(@($run.Results).Count)", "Network Diagnostic")
        }
        $Script:UISync.LatencyRun = $null
        $Script:UISync.LatencyError = $null
    }
}

function Invoke-GuiDnsProfileChange {
    param(
        [ValidateSet("Cloudflare", "Google", "DHCP")][string]$Provider
    )

    try {
        $result = Set-NetworkDiagnosticDnsProfile -Provider $Provider
        Load-NetworkDiagnostics
        if ($result.Changed) {
            [System.Windows.MessageBox]::Show("DNS updated on $($result.AdapterName): $Provider", "DNS Updated")
        } else {
            [System.Windows.MessageBox]::Show("DNS is already set to $Provider on $($result.AdapterName).", "DNS Unchanged")
        }
    } catch {
        [System.Windows.MessageBox]::Show("DNS update failed:`n$($_.Exception.Message)", "DNS Error", "OK", "Error")
    }
}

(El "BtnNetRefresh").Add_Click({ Load-NetworkDiagnostics })
(El "BtnNetBaseline").Add_Click({ Start-LatencyDiagnostic -Kind baseline })
(El "BtnNetPost").Add_Click({ Start-LatencyDiagnostic -Kind post })
(El "BtnNetDnsCloudflare").Add_Click({ Invoke-GuiDnsProfileChange -Provider Cloudflare })
(El "BtnNetDnsGoogle").Add_Click({ Invoke-GuiDnsProfileChange -Provider Google })
(El "BtnNetDnsDhcp").Add_Click({ Invoke-GuiDnsProfileChange -Provider DHCP })
(El "BtnNetDnsRestore").Add_Click({
    try {
        $ok = Restore-LatestDnsBackup
        Load-NetworkDiagnostics
        if ($ok) {
            [System.Windows.MessageBox]::Show("Restored the latest GUI DNS backup.", "DNS Restore")
        } else {
            [System.Windows.MessageBox]::Show("No GUI DNS backup was found.", "DNS Restore", "OK", "Warning")
        }
    } catch {
        [System.Windows.MessageBox]::Show("DNS restore failed:`n$($_.Exception.Message)", "DNS Restore", "OK", "Error")
    }
})

# ══════════════════════════════════════════════════════════════════════════════
