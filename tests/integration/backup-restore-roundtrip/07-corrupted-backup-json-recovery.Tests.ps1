BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Corrupted backup.json recovery" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false

        Mock Write-DebugLog {}
        Mock Write-Warn {}
        Mock Write-Host {}
    }

    It "Get-BackupDataRaw recovers from corrupted JSON" {
        # Write invalid JSON to backup file
        Set-Content $CFG_BackupFile -Value "{ this is not valid json !!!" -Encoding UTF8

        $result = Get-BackupDataRaw

        # Should return a fresh empty backup structure
        $result | Should -Not -BeNullOrEmpty
        @($result.entries).Count | Should -Be 0
    }

    It "Get-BackupDataRaw preserves corrupted file before resetting" {
        Set-Content $CFG_BackupFile -Value "corrupt data here" -Encoding UTF8

        Get-BackupDataRaw

        # A .corrupt.*.json file should have been created
        $corruptFiles = @(Get-ChildItem (Split-Path $CFG_BackupFile -Parent) -Filter "backup.corrupt.*.json")
        $corruptFiles.Count | Should -BeGreaterOrEqual 1
    }

    It "Get-BackupData flushes buffer before reading" {
        New-TestBackupFile -Entries @()
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; path = "HKLM:\Test"; name = "Buffered";
            originalValue = 99; originalType = "DWord"; existed = $true;
            step = "Buffer Test"; timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })

        $result = Get-BackupData

        @($result.entries).Count | Should -Be 1
        $result.entries[0].name | Should -Be "Buffered"
        $SCRIPT:_backupPending.Count | Should -Be 0
    }
}

# ── Security validation on restore ──────────────────────────────────────────
Describe "Restore security validation" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "Rejects registry restore with invalid path" {
        $malicious = @([ordered]@{
            type = "registry"; path = "C:\Windows\System32\evil";
            name = "payload"; originalValue = "pwned"; originalType = "DWord";
            existed = $true; step = "Tampered Step";
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
        New-TestBackupFile -Entries $malicious

        Mock Set-ItemProperty {}

        Restore-StepChanges -StepTitle "Tampered Step"

        # Set-ItemProperty should NOT be called for invalid paths
        Should -Not -Invoke Set-ItemProperty
    }

    It "Rejects registry restore with path traversal in name" {
        $malicious = @([ordered]@{
            type = "registry"; path = "HKLM:\SOFTWARE\Test";
            name = "..\..\Run\evil"; originalValue = "payload"; originalType = "String";
            existed = $true; step = "Traversal Step";
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
        New-TestBackupFile -Entries $malicious

        Mock Set-ItemProperty {}

        Restore-StepChanges -StepTitle "Traversal Step"

        Should -Not -Invoke Set-ItemProperty
    }

    It "Rejects bcdedit restore with invalid key format" {
        $malicious = @([ordered]@{
            type = "bootconfig"; key = "evil;shutdown /s";
            originalValue = "yes"; existed = $true; step = "BCD Tamper";
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
        New-TestBackupFile -Entries $malicious

        Mock bcdedit {}

        Restore-StepChanges -StepTitle "BCD Tamper"

        Should -Not -Invoke bcdedit
    }

    It "Rejects powerplan restore with invalid GUID" {
        $malicious = @([ordered]@{
            type = "powerplan"; originalGuid = "not-a-real-guid!; powercfg /delete all";
            originalName = "Evil Plan"; step = "Power Tamper";
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
        New-TestBackupFile -Entries $malicious

        Mock powercfg {}

        Restore-StepChanges -StepTitle "Power Tamper"

        Should -Not -Invoke powercfg
    }
}

# ── NIC adapter backup/restore roundtrip ─────────────────────────────────────
Describe "NIC adapter backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "NIC Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "restores nic_adapter entries via Set-NetAdapterAdvancedProperty" {
        Mock Get-NetAdapter {
            [PSCustomObject]@{ Name = "Ethernet"; InterfaceDescription = "Intel NIC" }
        }

        Backup-NicAdapterProperty -AdapterName "Ethernet" -PropertyName "EEE" `
            -OriginalValue "Disabled" -PropertyType "DisplayName" -StepTitle "NIC Test Step"
        Flush-BackupBuffer

        Mock Set-NetAdapterAdvancedProperty {} -Verifiable

        $result = Restore-StepChanges -StepTitle "NIC Test Step"

        $result | Should -Be $true
        Should -Invoke Set-NetAdapterAdvancedProperty -Exactly 1 -ParameterFilter {
            $Name -eq "Ethernet" -and $DisplayName -eq "EEE" -and $DisplayValue -eq "Disabled"
        }
    }

    It "retains nic_adapter entries when the adapter identity changed" {
        Mock Get-NetAdapter {
            [PSCustomObject]@{ Name = "Ethernet"; InterfaceDescription = "Intel NIC" }
        }

        Backup-NicAdapterProperty -AdapterName "Ethernet" -PropertyName "EEE" `
            -OriginalValue "Disabled" -PropertyType "DisplayName" -StepTitle "NIC Test Step"
        Flush-BackupBuffer

        Mock Get-NetAdapter {
            [PSCustomObject]@{ Name = "Ethernet"; InterfaceDescription = "Replacement NIC" }
        }
        Mock Set-NetAdapterAdvancedProperty {}

        $result = Restore-StepChanges -StepTitle "NIC Test Step"

        $result | Should -Be $false
        Should -Not -Invoke Set-NetAdapterAdvancedProperty
        @((Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json).entries).Count | Should -Be 1
    }
}

# ── QoS/URO backup/restore roundtrip ────────────────────────────────────────
Describe "QoS/URO backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "QoS Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "removes QoS policies and restores URO state" {
        Backup-QosAndUro -PolicyNames @("CS2 UDP") -UroState "disabled" -StepTitle "QoS Test Step"
        Flush-BackupBuffer

        Mock Get-NetQosPolicy { [PSCustomObject]@{ Name = "CS2 UDP" } }
        Mock Remove-NetQosPolicy {}
        Mock netsh {
            $global:LASTEXITCODE = 0
            "Ok."
        }

        $result = Restore-StepChanges -StepTitle "QoS Test Step"

        $result | Should -Be $true
        Should -Invoke Remove-NetQosPolicy -Exactly 1 -ParameterFilter { $Name -eq "CS2 UDP" }
    }

    It "retains qos_uro entries when policy removal fails" {
        Backup-QosAndUro -PolicyNames @("CS2 UDP") -UroState "disabled" -StepTitle "QoS Test Step"
        Flush-BackupBuffer

        Mock Get-NetQosPolicy { [PSCustomObject]@{ Name = "CS2 UDP" } }
        Mock Remove-NetQosPolicy { throw "Permission denied" }
        Mock netsh {
            $global:LASTEXITCODE = 0
            "Ok."
        }

        $result = Restore-StepChanges -StepTitle "QoS Test Step"

        $result | Should -Be $false
        @((Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json).entries).Count | Should -Be 1
    }
}

# ── Defender backup/restore roundtrip ───────────────────────────────────────
Describe "Defender backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "Defender Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "removes stored Defender exclusions during restore" {
        Backup-DefenderExclusions -ExclusionPaths @("C:\Games\CS2") -ExclusionProcesses @("cs2.exe") -StepTitle "Defender Test Step"
        Flush-BackupBuffer

        Mock Remove-MpPreference {}

        $result = Restore-StepChanges -StepTitle "Defender Test Step"

        $result | Should -Be $true
        Should -Invoke Remove-MpPreference -Exactly 2
    }

    It "retains defender entries when exclusion removal fails" {
        Backup-DefenderExclusions -ExclusionPaths @("C:\Games\CS2") -ExclusionProcesses @("cs2.exe") -StepTitle "Defender Test Step"
        Flush-BackupBuffer

        Mock Remove-MpPreference { throw "Tamper protection" }

        $result = Restore-StepChanges -StepTitle "Defender Test Step"

        $result | Should -Be $false
        @((Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json).entries).Count | Should -Be 1
    }
}

# ── Pagefile backup/restore roundtrip ───────────────────────────────────────
Describe "Pagefile backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "Pagefile Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "automates pagefile restore and logs that a reboot is required" {
        Backup-PagefileConfig -AutomaticManaged $false -PagefilePath "C:\pagefile.sys" `
            -InitialSize 4096 -MaximumSize 8192 -StepTitle "Pagefile Test Step"
        Flush-BackupBuffer

        $computerSystem = [PSCustomObject]@{ Name = "HOST" }
        $pagefileSetting = [PSCustomObject]@{ Name = "C:\\pagefile.sys" }
        Mock Get-CimInstance {
            if ($ClassName -eq "Win32_ComputerSystem") { return $computerSystem }
            if ($ClassName -eq "Win32_PageFileSetting") { return $pagefileSetting }
        }
        Mock Invoke-PagefileCimUpdate {}

        $result = Restore-StepChanges -StepTitle "Pagefile Test Step"

        $result | Should -Be $true
        Should -Invoke Invoke-PagefileCimUpdate -Exactly 1 -ParameterFilter {
            $InputObject -eq $pagefileSetting -and $Property.InitialSize -eq 4096 -and $Property.MaximumSize -eq 8192
        }
        Should -Invoke Write-OK -ParameterFilter { $t -match "automated restore completed" }
        Should -Invoke Write-Info -ParameterFilter { $t -match "reboot is required" }
    }

    It "falls back to manual instructions and retains the pagefile entry when automation fails" {
        Backup-PagefileConfig -AutomaticManaged $true -PagefilePath "C:\pagefile.sys" `
            -InitialSize 0 -MaximumSize 0 -StepTitle "Pagefile Test Step"
        Flush-BackupBuffer

        Mock Get-CimInstance { throw "CIM unavailable" }
        Mock Write-Info {}

        $result = Restore-StepChanges -StepTitle "Pagefile Test Step"

        $result | Should -Be $false
        Should -Invoke Write-Info -ParameterFilter { $t -match "Manual restore: System Properties" }
        Should -Invoke Write-Warn -ParameterFilter { $t -match "partial success" }
        Should -Invoke Write-Info -ParameterFilter { $t -match "reboot is required" }
        @((Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json).entries).Count | Should -Be 1
    }
}

# ── DNS backup/restore roundtrip ────────────────────────────────────────────
Describe "DNS backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "DNS Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "restores DNS using the current adapter interface index" {
        Backup-DnsConfig -AdapterName "Ethernet" -InterfaceIndex 12 -OriginalDnsServers @("1.1.1.1", "1.0.0.1") -StepTitle "DNS Test Step"
        Flush-BackupBuffer

        Mock Get-NetAdapter {
            [PSCustomObject]@{ Name = "Ethernet"; InterfaceIndex = 99 }
        }
        Mock Set-DnsClientServerAddress {}

        $result = Restore-StepChanges -StepTitle "DNS Test Step"

        $result | Should -Be $true
        Should -Invoke Set-DnsClientServerAddress -Exactly 1 -ParameterFilter {
            $InterfaceIndex -eq 99 -and @($ServerAddresses).Count -eq 2
        }
    }

    It "retains dns entries when restore fails" {
        Backup-DnsConfig -AdapterName "Ethernet" -InterfaceIndex 12 -OriginalDnsServers @("1.1.1.1") -StepTitle "DNS Test Step"
        Flush-BackupBuffer

        Mock Get-NetAdapter {
            [PSCustomObject]@{ Name = "Ethernet"; InterfaceIndex = 12 }
        }
        Mock Set-DnsClientServerAddress { throw "Access denied" }

        $result = Restore-StepChanges -StepTitle "DNS Test Step"

        $result | Should -Be $false
        @((Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json).entries).Count | Should -Be 1
    }
}

# ── DRS backup/restore roundtrip ────────────────────────────────────────────
Describe "DRS backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "delegates drs restore entries to Restore-DrsSettings" {
        New-TestBackupFile -Entries @(
            [ordered]@{
                type = "drs"
                step = "DRS Test Step"
                profile = "CS2"
                profileCreated = $false
                settings = @([ordered]@{ id = 1; previousValue = 1; existed = $true })
                timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        )

        Mock Restore-DrsSettings { $true }

        $result = Restore-StepChanges -StepTitle "DRS Test Step"

        $result | Should -Be $true
        Should -Invoke Restore-DrsSettings -Exactly 1
    }

    It "retains drs entries when Restore-DrsSettings reports failure" {
        New-TestBackupFile -Entries @(
            [ordered]@{
                type = "drs"
                step = "DRS Test Step"
                profile = "CS2"
                profileCreated = $false
                settings = @([ordered]@{ id = 1; previousValue = 1; existed = $true })
                timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        )

        Mock Restore-DrsSettings { $false }

        $result = Restore-StepChanges -StepTitle "DRS Test Step"

        $result | Should -Be $false
        @((Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json).entries).Count | Should -Be 1
    }
}
