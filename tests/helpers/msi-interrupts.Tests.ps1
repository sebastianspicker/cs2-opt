# ==============================================================================
#  tests/helpers/msi-interrupts.Tests.ps1  --  MSI interrupts & NIC RSS/affinity
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/_TestInit.ps1"

    # Stub Windows-only cmdlets before loading the module
    if ($IsWindows -eq $false) {
        if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
            function global:Get-PnpDevice { param($Class, $Status, $ErrorAction) $null }
        }
        if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
            function global:Get-NetAdapter { param($Physical, $ErrorAction) $null }
        }
    }

    . "$PSScriptRoot/../../helpers/msi-interrupts.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Enable-DeviceMSI ───────────────────────────────────────────────────────
Describe "Enable-DeviceMSI" {

    BeforeEach { Reset-TestState }

    Context "No devices found" {

        It "handles gracefully when no PnP devices exist" {
            Mock Get-PnpDevice { $null }
            Mock Write-Step {}
            Mock Write-Warn {}
            Mock Write-DebugLog {}

            { Enable-DeviceMSI } | Should -Not -Throw
            Should -Invoke Write-Warn -Times 1
        }
    }

    Context "DRY-RUN mode" {

        It "does not write registry in DRY-RUN mode" {
            $SCRIPT:DryRun = $true
            Mock Get-PnpDevice {
                @([PSCustomObject]@{
                    InstanceId = "PCI\VEN_10DE&DEV_2684&SUBSYS_00001234&REV_A1\4&abc123"
                    FriendlyName = "NVIDIA GeForce RTX 4090"
                    Class = "Display"
                })
            }
            Mock Write-Step {}
            Mock Write-Host {}
            Mock Set-ItemProperty {}
            Mock Test-Path { $false }
            Mock New-Item {}

            Enable-DeviceMSI

            Should -Invoke Set-ItemProperty -Times 0
        }

        It "reports devices that would be modified in DRY-RUN" {
            $SCRIPT:DryRun = $true
            Mock Get-PnpDevice {
                @([PSCustomObject]@{
                    InstanceId = "PCI\VEN_10DE&DEV_2684\4&abc123"
                    FriendlyName = "NVIDIA GeForce RTX 4090"
                    Class = "Display"
                })
            }
            Mock Write-Step {}
            Mock Write-Host {} -ParameterFilter { $Object -match "DRY-RUN" }

            Enable-DeviceMSI

            Should -Invoke Write-Host -ParameterFilter { $Object -match "DRY-RUN" } -Scope It
        }
    }

    Context "Device filtering" {

        It "skips non-PCI devices" {
            $SCRIPT:DryRun = $true
            # Return devices only for Display class, nothing for Net/Media
            Mock Get-PnpDevice {
                if ($Class -eq "Display") {
                    @(
                        [PSCustomObject]@{
                            InstanceId = "USB\VID_1234&PID_5678\abc"
                            FriendlyName = "USB Audio Device"
                        },
                        [PSCustomObject]@{
                            InstanceId = "PCI\VEN_10DE&DEV_2684\4&abc"
                            FriendlyName = "NVIDIA RTX 4090"
                        }
                    )
                } else { $null }
            }
            Mock Write-Step {}
            Mock Write-DebugLog {}

            $script:hostOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host {
                if ($Object) { $script:hostOutput.Add([string]$Object) }
            }

            Enable-DeviceMSI

            # Only PCI device should be reported, not USB
            $msiReports = $script:hostOutput | Where-Object { $_ -match "DRY-RUN.*MSISupported" }
            @($msiReports).Count | Should -Be 1
        }
    }

    Context "MessageNumberLimit for GPU" {

        It "sets MessageNumberLimit=16 for Display class" {
            $SCRIPT:DryRun = $true
            Mock Get-PnpDevice {
                @([PSCustomObject]@{
                    InstanceId = "PCI\VEN_10DE&DEV_2684\4&abc"
                    FriendlyName = "NVIDIA GeForce RTX 4090"
                    Class = "Display"
                })
            }
            Mock Write-Step {}

            $script:hostOutput = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host {
                if ($Object) { $script:hostOutput.Add([string]$Object) }
            }

            Enable-DeviceMSI

            $msiLimitMsg = $script:hostOutput | Where-Object { $_ -match "MessageNumberLimit.*16" }
            $msiLimitMsg | Should -Not -BeNullOrEmpty
        }
    }

    Context "Device classes" {

        It "queries Display, Net, and Media device classes" {
            $SCRIPT:DryRun = $true
            $script:queriedClasses = [System.Collections.Generic.List[string]]::new()
            Mock Get-PnpDevice {
                if ($Class) { $script:queriedClasses.Add($Class) }
                $null
            }
            Mock Write-Step {}
            Mock Write-Warn {}
            Mock Write-DebugLog {}

            Enable-DeviceMSI

            $script:queriedClasses | Should -Contain "Display"
            $script:queriedClasses | Should -Contain "Net"
            $script:queriedClasses | Should -Contain "Media"
        }
    }
}

# ── Set-NicRssConfig ────────────────────────────────────────────────────────
Describe "Set-NicRssConfig" {

    BeforeEach { Reset-TestState }

    It "skips gracefully when no active NIC found" {
        Mock Get-ActiveNicAdapter { $null }
        Mock Write-Step {}
        Mock Write-Warn {}

        { Set-NicRssConfig } | Should -Not -Throw
        Should -Invoke Write-Warn -Times 1
    }

    It "skips when driver key not found" {
        Mock Get-ActiveNicAdapter {
            [PSCustomObject]@{ InterfaceDescription = "Realtek PCIe GbE" }
        }
        Mock Write-Step {}
        Mock Write-Info {}
        Mock Write-Warn {}
        Mock Get-ChildItem { @() }
        Mock Test-Path { $false }

        { Set-NicRssConfig } | Should -Not -Throw
    }

    Context "*RSS master switch" {

        # Shared helper: builds the NIC + driver key mock scaffolding.
        # Registers Get-ItemProperty mocks in specificity order (most-specific first).
        function Set-RssTestScaffolding {
            param([string]$NicDescription = "Realtek PCIe GbE", [long]$Speed = 1000000000)

            $fakePath   = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0001"
            $fakeSubKey = [PSCustomObject]@{ PSChildName = "0001"; PSPath = $fakePath }

            Mock Get-ActiveNicAdapter {
                param() [PSCustomObject]@{ InterfaceDescription = $using:NicDescription; Speed = $using:Speed }
            }
            Mock Get-ChildItem { @($fakeSubKey) }
            # DriverDesc match (first so it wins over the catch-all)
            Mock Get-ItemProperty {
                [PSCustomObject]@{ DriverDesc = $using:NicDescription }
            } -ParameterFilter { $Name -eq "DriverDesc" }
            # RSS sub-params — return null so Set-RegistryValue is called for each
            Mock Get-ItemProperty { $null } -ParameterFilter { $Name -ne "DriverDesc" -and $Name -ne "*RSS" }
            Mock Set-RegistryValue {}
            Mock Write-Step {}; Mock Write-Info {}; Mock Write-OK {}; Mock Write-Sub {}; Mock Write-Warn {}
        }

        It "creates and enables *RSS when the key is absent" {
            Set-RssTestScaffolding
            Mock Get-ItemProperty { $null } -ParameterFilter { $Name -eq "*RSS" }

            Set-NicRssConfig

            Should -Invoke Set-RegistryValue -Times 1 -ParameterFilter { $name -eq "*RSS" -and $value -eq 1 }
        }

        It "re-enables *RSS when it is 0" {
            Set-RssTestScaffolding
            $rssDisabled = New-Object PSObject
            $rssDisabled | Add-Member -MemberType NoteProperty -Name "*RSS" -Value 0
            Mock Get-ItemProperty { $rssDisabled } -ParameterFilter { $Name -eq "*RSS" }

            Set-NicRssConfig

            Should -Invoke Set-RegistryValue -Times 1 -ParameterFilter { $name -eq "*RSS" -and $value -eq 1 }
        }

        It "does not write *RSS when it is already 1" {
            Set-RssTestScaffolding
            $rssEnabled = New-Object PSObject
            $rssEnabled | Add-Member -MemberType NoteProperty -Name "*RSS" -Value 1
            Mock Get-ItemProperty { $rssEnabled } -ParameterFilter { $Name -eq "*RSS" }

            Set-NicRssConfig

            Should -Invoke Set-RegistryValue -Times 0 -ParameterFilter { $name -eq "*RSS" }
        }
    }

    Context "speed-aware RSS queue count" {

        function Set-SpeedTestScaffolding {
            param([long]$Speed)
            $fakePath   = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0001"
            $fakeSubKey = [PSCustomObject]@{ PSChildName = "0001"; PSPath = $fakePath }
            $rssEnabled = New-Object PSObject
            $rssEnabled | Add-Member -MemberType NoteProperty -Name "*RSS" -Value 1

            Mock Get-ActiveNicAdapter {
                param() [PSCustomObject]@{ InterfaceDescription = "Test NIC"; Speed = $using:Speed }
            }
            Mock Get-ChildItem { @($fakeSubKey) }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ DriverDesc = "Test NIC" }
            } -ParameterFilter { $Name -eq "DriverDesc" }
            Mock Get-ItemProperty { $rssEnabled } -ParameterFilter { $Name -eq "*RSS" }
            Mock Get-ItemProperty { $null } -ParameterFilter { $Name -ne "DriverDesc" -and $Name -ne "*RSS" }
            Mock Set-RegistryValue {}
            Mock Write-Step {}; Mock Write-Info {}; Mock Write-OK {}; Mock Write-Sub {}; Mock Write-Warn {}
        }

        It "emits 5+ GbE speed-detection message for NICs at 5 Gbps or above" {
            Set-SpeedTestScaffolding -Speed 5000000000

            Set-NicRssConfig

            Should -Invoke Write-Info -ParameterFilter { $t -match "5\+ GbE NIC detected" }
        }

        It "does not emit 5+ GbE detection message for 1 GbE NICs" {
            Set-SpeedTestScaffolding -Speed 1000000000

            Set-NicRssConfig

            Should -Invoke Write-Info -Times 0 -ParameterFilter { $t -match "5\+ GbE NIC detected" }
        }
    }
}

# ── Set-NicInterruptAffinity ───────────────────────────────────────────────
Describe "Set-NicInterruptAffinity" {

    BeforeEach { Reset-TestState }

    It "skips gracefully when no active NIC found" {
        Mock Get-ActiveNicAdapter { $null }
        Mock Write-Step {}
        Mock Write-Warn {}

        { Set-NicInterruptAffinity } | Should -Not -Throw
        Should -Invoke Write-Warn -Times 1
    }

    It "handles single-core systems gracefully" {
        Mock Get-ActiveNicAdapter {
            [PSCustomObject]@{ InterfaceDescription = "Intel I225-V" }
        }
        Mock Get-PnpDevice {
            [PSCustomObject]@{
                InstanceId = "PCI\VEN_8086&DEV_15F3\abc"
                FriendlyName = "Intel I225-V"
            }
        }
        Mock Get-CimInstance {
            [PSCustomObject]@{ NumberOfCores = 1 }
        }
        Mock Write-Step {}
        Mock Write-Warn {}

        { Set-NicInterruptAffinity } | Should -Not -Throw
        Should -Invoke Write-Warn -Times 1
    }

    It "skips registry writes in DRY-RUN mode" {
        $SCRIPT:DryRun = $true
        Mock Get-ActiveNicAdapter {
            [PSCustomObject]@{ InterfaceDescription = "Intel I225-V" }
        }
        Mock Get-PnpDevice {
            [PSCustomObject]@{
                InstanceId = "PCI\VEN_8086&DEV_15F3\abc"
                FriendlyName = "Intel I225-V"
            }
        }
        Mock Get-CimInstance {
            [PSCustomObject]@{ NumberOfCores = 8 }
        }
        Mock Write-Step {}
        Mock Write-Host {}
        Mock Write-Info {}
        Mock Set-ItemProperty {}
        Mock Test-Path { $true }
        Mock New-Item {}

        Set-NicInterruptAffinity

        Should -Invoke Set-ItemProperty -Times 0
    }
}
