#Requires -RunAsAdministrator
# ==============================================================================
#  CS2-Optimize-GUI.ps1  —  WPF Dashboard
#  Launch via START-GUI.bat
# ==============================================================================
param([switch]$SmokeTest)

if ($SmokeTest) {
    Write-Host "SMOKE TEST OK: CS2-Optimize-GUI" -ForegroundColor Green
    exit 0
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms   # for Clipboard
Add-Type -AssemblyName Microsoft.VisualBasic  # for InputBox

$Script:Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }

. "$Script:Root\config.env.ps1"
. "$Script:Root\helpers.ps1"
. "$Script:Root\helpers\step-catalog.ps1"
. "$Script:Root\helpers\system-analysis.ps1"

if ($SmokeTest) {
    Write-Host "SMOKE TEST OK: CS2-Optimize-GUI" -ForegroundColor Green
    exit 0
}

# ── Async engine ──────────────────────────────────────────────────────────────
$Script:Pool   = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 3)
$Script:Pool.Open()
$Script:UISync    = [hashtable]::Synchronized(@{})
$Script:Closing   = $false
$Script:AsyncTimers = [System.Collections.Generic.List[System.Windows.Threading.DispatcherTimer]]::new()

function Invoke-Async {
    param([scriptblock]$Work, [object[]]$WorkArgs = @(), [scriptblock]$OnDone = {})
    $rs = [System.Management.Automation.PowerShell]::Create()
    $rs.RunspacePool = $Script:Pool
    [void]$rs.AddScript($Work)
    foreach ($a in $WorkArgs) { [void]$rs.AddArgument($a) }
    $handle = $rs.BeginInvoke()
    $timer  = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $capturedHandle = $handle
    $capturedRs     = $rs
    $capturedDone   = $OnDone
    $capturedWindow = $Window
    $capturedUISync = $Script:UISync
    $capturedTimers = $Script:AsyncTimers
    $timer.Add_Tick({
        if ($Script:Closing) {
            $timer.Stop()
            try { $capturedRs.Stop(); $capturedRs.Dispose() } catch {}
            return
        }
        if ($capturedHandle.IsCompleted) {
            $timer.Stop()
            $errorOccurred = $false
            try { $capturedRs.EndInvoke($capturedHandle) } catch { $capturedUISync.AsyncError = "$($_.Exception.GetType().Name): $($_.Exception.Message)"; $errorOccurred = $true }
            finally { $capturedRs.Dispose() }
            if ($errorOccurred) {
                if ($capturedWindow) {
                    $capturedWindow.Dispatcher.Invoke({
                        [System.Windows.MessageBox]::Show("Background task error: $($capturedUISync.AsyncError)", "Error", "OK", "Error")
                    })
                }
                $capturedUISync.AsyncError = $null
            } else {
                try { & $capturedDone } catch {
                    if ($capturedWindow) {
                        $capturedWindow.Dispatcher.Invoke({
                            [System.Windows.MessageBox]::Show("Callback error: $($_.Exception.Message)", "Error", "OK", "Error")
                        })
                    }
                }
            }
            $capturedTimers.Remove($timer)
        }
    }.GetNewClosure())
    $Script:AsyncTimers.Add($timer)
    $timer.Start()
}

function New-Brush { [System.Windows.Media.BrushConverter]::new().ConvertFromString($args[0]) }

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$XAML = Get-Content "$Script:Root\ui\CS2-Optimize-GUI.xaml" -Raw

# ── Load window ───────────────────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$reader.Dispose()

# ── Named element shortcuts ───────────────────────────────────────────────────
function El {
    $e = $Window.FindName($args[0])
    if ($null -eq $e) { Write-Warning "El: XAML element '$($args[0])' not found" }
    $e
}

# ── Version labels (from config.env.ps1) ─────────────────────────────────────
(El "TitleVersion").Text    = "  $CFG_Version"
(El "SettingsVersion").Text = "  $CFG_Version"

# ── Window chrome ─────────────────────────────────────────────────────────────
(El "TitleBar").Add_MouseLeftButtonDown({ $Window.DragMove() })
(El "BtnMin").Add_Click({ $Window.WindowState = "Minimized" })
(El "BtnMax").Add_Click({ $Window.WindowState = if ($Window.WindowState -eq "Maximized") { "Normal" } else { "Maximized" } })
(El "BtnClose").Add_Click({ $Window.Close() })

# ── Navigation ────────────────────────────────────────────────────────────────
$Script:AllPanels = "PanelDashboard","PanelAnalyze","PanelOptimize","PanelBackup","PanelBenchmark","PanelNetwork","PanelVideo","PanelSettings"
$Script:NavMap    = @{
    "PanelDashboard"  = "NavDashboard"
    "PanelAnalyze"    = "NavAnalyze"
    "PanelOptimize"   = "NavOptimize"
    "PanelBackup"     = "NavBackup"
    "PanelBenchmark"  = "NavBenchmark"
    "PanelNetwork"    = "NavNetwork"
    "PanelVideo"      = "NavVideo"
    "PanelSettings"   = "NavSettings"
}
$Script:ActivePanel = "PanelDashboard"

$ActiveStyle   = $Window.Resources["NavBtnActive"]
$InactiveStyle = $Window.Resources["NavBtn"]

(El "NavDashboard").Add_Click({ Switch-Panel "PanelDashboard"; Load-Dashboard })
(El "NavAnalyze"  ).Add_Click({ Switch-Panel "PanelAnalyze" ; Start-Analysis })
(El "NavOptimize" ).Add_Click({ Switch-Panel "PanelOptimize" ; Load-Optimize  })
(El "NavBackup"   ).Add_Click({ Switch-Panel "PanelBackup"   ; Load-Backup    })
(El "NavBenchmark").Add_Click({ Switch-Panel "PanelBenchmark"; Load-Benchmark })
(El "NavNetwork"  ).Add_Click({ Switch-Panel "PanelNetwork"  ; Load-NetworkDiagnostics })
(El "NavVideo"    ).Add_Click({ Switch-Panel "PanelVideo"    ; Load-Video     })
(El "NavSettings" ).Add_Click({ Switch-Panel "PanelSettings" ; Load-Settings  })

# ── Sidebar status helpers ────────────────────────────────────────────────────
function Update-SidebarStatus {
    $state = $null
    try { if (Test-Path $CFG_StateFile) { $state = Get-Content $CFG_StateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } } catch {}
    $prof = if ($state) { $state.profile } else { "—" }
    $isDry = ($state -and $state.mode -eq "DRY-RUN")
    $phaseText = "—"
    if (Test-Path $CFG_ProgressFile) {
        try {
            $prog = Get-Content $CFG_ProgressFile -Raw | ConvertFrom-Json
            if ($prog.phase) { $phaseText = "$($prog.phase)" }
        } catch {}
    }
    $Window.Dispatcher.Invoke({
        (El "SbProfile").Text = "Profile: $prof"
        (El "SbDryRun" ).Text = if ($isDry) { "DRY-RUN" } else { "" }
        (El "SbDryRunBadge").Visibility = if ($isDry) { "Visible" } else { "Collapsed" }
        (El "SbPhase").Text = "Phase: $phaseText"
    })
}

# ── Load panel functions and event handlers ─────────────────────────────────
. "$Script:Root\helpers\gui-panels.ps1"

# ══════════════════════════════════════════════════════════════════════════════
# STARTUP
# ══════════════════════════════════════════════════════════════════════════════
$Window.Add_Loaded({
    Update-SidebarStatus
    Update-StartupDriftBanner
    Load-Dashboard
})

$Window.Add_Closed({
    $Script:Closing = $true
    # Snapshot the list before iterating — Tick handlers call Remove($timer) on this
    # same list, which would throw InvalidOperationException during enumeration.
    $timersSnapshot = @($Script:AsyncTimers)
    foreach ($t in $timersSnapshot) { try { $t.Stop() } catch {} }
    try { $Script:Pool.Close(); $Script:Pool.Dispose() } catch {}
})

$Window.ShowDialog() | Out-Null
