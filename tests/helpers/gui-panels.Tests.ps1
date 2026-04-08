# ==============================================================================
#  tests/helpers/gui-panels.Tests.ps1  --  Non-WPF GUI logic
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/_TestInit.ps1"

    function New-FakeGuiElement {
        $element = [PSCustomObject]@{
            Visibility   = "Collapsed"
            Style        = $null
            Text         = ""
            SelectedItem = $null
            SelectedIndex = -1
            IsChecked    = $false
            IsEnabled    = $true
            Content      = ""
            ToolTip      = ""
            Foreground   = $null
            ItemsSource  = $null
            Items        = [System.Collections.ArrayList]::new()
            Children     = [System.Collections.ArrayList]::new()
            ActualWidth  = 600
            ActualHeight = 130
        }
        $element | Add-Member -MemberType ScriptMethod -Name Add_Click -Value { param($Handler) }
        $element | Add-Member -MemberType ScriptMethod -Name Add_SelectionChanged -Value { param($Handler) }
        $element | Add-Member -MemberType ScriptMethod -Name Add_Checked -Value { param($Handler) }
        $element | Add-Member -MemberType ScriptMethod -Name Add_Unchecked -Value { param($Handler) }
        $element | Add-Member -MemberType ScriptMethod -Name UpdateLayout -Value { }
        return $element
    }

    $script:GuiElements = @{}
    function El {
        param([string]$Name)
        if (-not $script:GuiElements.ContainsKey($Name)) {
            $script:GuiElements[$Name] = New-FakeGuiElement
        }
        return $script:GuiElements[$Name]
    }

    function New-Brush { param([string]$Color) $Color }
    function Invoke-Async {}
    function Launch-Terminal {}
    function Load-Dashboard {}
    function Start-Analysis {}
    function Load-Optimize {}
    function Start-InlineVerify {}
    function Load-Backup {}
    function Load-Benchmark {}
    function Load-Video {}
    function Load-Settings {}
    function Add-BenchmarkResult {}
    function Write-DebugLog {}

    $Script:UISync = @{}
    $Script:AllPanels = @("PanelDashboard", "PanelAnalyze", "PanelOptimize")
    $Script:NavMap = @{
        "PanelDashboard" = "NavDashboard"
        "PanelAnalyze"   = "NavAnalyze"
        "PanelOptimize"  = "NavOptimize"
    }
    $ActiveStyle = "ACTIVE"
    $InactiveStyle = "INACTIVE"

    . "$PSScriptRoot/../../helpers/gui-panels.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Switch-Panel" {

    BeforeEach {
        $script:GuiElements = @{}
        $Script:AllPanels = @("PanelDashboard", "PanelAnalyze", "PanelOptimize")
        $Script:NavMap = @{
            "PanelDashboard" = "NavDashboard"
            "PanelAnalyze"   = "NavAnalyze"
            "PanelOptimize"  = "NavOptimize"
        }
        $Script:ActivePanel = "PanelDashboard"
    }

    It "updates panel visibility and active nav style" {
        Switch-Panel -PanelName "PanelAnalyze"

        (El "PanelDashboard").Visibility | Should -Be "Collapsed"
        (El "PanelAnalyze").Visibility   | Should -Be "Visible"
        (El "NavDashboard").Style        | Should -Be "INACTIVE"
        (El "NavAnalyze").Style          | Should -Be "ACTIVE"
        $Script:ActivePanel              | Should -Be "PanelAnalyze"
    }

    It "runs the OnSwitch callback after updating state" {
        $called = $false

        Switch-Panel -PanelName "PanelOptimize" -OnSwitch { $script:called = $true }

        $script:called | Should -Be $true
        $Script:ActivePanel | Should -Be "PanelOptimize"
    }
}

Describe "Benchmark parsing helpers" {

    It "extracts an FPS cap from VProf text" {
        $result = Get-BenchmarkCapFromText "Noise [VProf] Avg=300.5 P1=220.4"

        $result.AvgFps | Should -Be 300.5
        $result.Cap    | Should -BeGreaterThan 0
    }

    It "returns null when no Avg FPS token exists" {
        Get-BenchmarkCapFromText "No FPS data here" | Should -BeNullOrEmpty
    }

    It "extracts Avg and P1 values for benchmark result imports" {
        $result = Get-BenchmarkResultFromText "[VProf] Avg=280.0 P1=190.0"

        $result.AvgFps | Should -Be 280.0
        $result.P1Fps  | Should -Be 190.0
    }

    It "returns null when the benchmark result text is incomplete" {
        Get-BenchmarkResultFromText "[VProf] Avg=280.0 only" | Should -BeNullOrEmpty
    }
}

Describe "Startup drift helpers" {

    BeforeEach {
        $script:GuiElements = @{}
        $Script:StartupDriftChecked = $false
        Reset-TestState
    }

    It "skips the startup drift probe when startup_last_verified is recent" {
        $state = [PSCustomObject]@{
            startup_last_verified = (Get-Date).AddMinutes(-10).ToString("o")
        }

        Should-SkipStartupDriftCheck -State $state | Should -Be $true
    }

    It "records startup_last_verified and reports drift counts from the quick startup check" {
        Mock Test-RegistryCheck {
            if ($Name -eq "OverlayTestMode") {
                return @{ Status = "CHANGED"; Value = 0 }
            }
            return @{ Status = "OK"; Value = $Expected }
        }
        Mock Save-JsonAtomic { $script:SavedState = $Data }
        Mock Set-SecureAcl {}

        $result = Test-StartupConfigDrift

        $result.Skipped | Should -Be $false
        $result.HasDrift | Should -Be $true
        $result.DriftCount | Should -Be 1
        Should -Invoke Save-JsonAtomic -Exactly 1
        $script:SavedState.PSObject.Properties.Name | Should -Contain "startup_last_verified"
        $script:SavedState.PSObject.Properties.Name | Should -Not -Contain "last_verified"
    }

    It "uses AUTO as the fallback mode for the recommended profile" {
        Mock Test-RegistryCheck { @{ Status = "OK"; Value = $Expected } }
        Mock Save-JsonAtomic { $script:SavedState = $Data }
        Mock Set-SecureAcl {}

        Test-StartupConfigDrift | Out-Null

        $script:SavedState.profile | Should -Be "RECOMMENDED"
        $script:SavedState.mode | Should -Be "AUTO"
    }

    It "shows the drift banner when startup drift is detected" {
        Mock Test-StartupConfigDrift {
            [PSCustomObject]@{
                Skipped = $false
                HasDrift = $true
                DriftCount = 2
                CheckedCount = 5
                DriftLabels = @("MPO disabled", "Game Mode enabled")
                CheckedAt = "2026-04-08 14:00"
            }
        }

        Update-StartupDriftBanner

        (El "DashDriftBanner").Visibility | Should -Be "Visible"
        (El "DashDriftBannerText").Text | Should -Match "2 of 5 quick checks drifted"
    }

    It "hides the drift banner when the startup check is skipped or clean" {
        Mock Test-StartupConfigDrift {
            [PSCustomObject]@{
                Skipped = $true
                HasDrift = $false
                DriftCount = 0
                CheckedCount = 0
                DriftLabels = @()
                CheckedAt = ""
            }
        }

        Update-StartupDriftBanner

        (El "DashDriftBanner").Visibility | Should -Be "Collapsed"
    }
}
