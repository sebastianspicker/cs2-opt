# ==============================================================================
#  tests/integration/backup-restore-roundtrip.Tests.ps1
#  End-to-end roundtrip for all 6 backup types.
# ==============================================================================
#
#  Backup types: registry, service, bootconfig, powerplan, drs, scheduledtask
#  Each test: write -> backup.json captures previous -> restore writes back

BeforeAll {
    . "$PSScriptRoot/_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Registry backup/restore roundtrip ────────────────────────────────────────
Describe "Registry backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "Registry Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        # Initialize backup file
        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "Backup-RegistryValue captures existing value and Restore writes it back" {
        # Mock reading the existing value
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "HKLM:\SOFTWARE\Test" }
        Mock Get-ItemProperty {
            return [PSCustomObject]@{ TestName = 42 }
        } -ParameterFilter { $Name -eq "TestName" }
        Mock Get-Item {
            $mock = New-Object PSObject
            $mock | Add-Member -MemberType ScriptMethod -Name GetValueKind -Value { "DWord" }
            return $mock
        } -ParameterFilter { $Path -eq "HKLM:\SOFTWARE\Test" }

        # Perform backup
        Backup-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "TestName" -StepTitle "Registry Test Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $entry = $SCRIPT:_backupPending[0]
        $entry.type | Should -Be "registry"
        $entry.path | Should -Be "HKLM:\SOFTWARE\Test"
        $entry.name | Should -Be "TestName"
        $entry.originalValue | Should -Be 42
        $entry.existed | Should -Be $true
        $entry.originalType | Should -Be "DWord"

        # Flush to disk
        Flush-BackupBuffer

        # Verify backup.json has the entry
        $backup = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        $backup.entries.Count | Should -Be 1

        # Now mock the restore path
        Mock Set-ItemProperty {} -Verifiable

        # Perform restore
        Restore-StepChanges -StepTitle "Registry Test Step"

        Should -InvokeVerifiable
    }

    It "Backup-RegistryValue captures non-existent key and Restore removes it" {
        # Mock: key does not exist
        Mock Test-Path { $false } -ParameterFilter { $Path -eq "HKLM:\SOFTWARE\NewKey" }

        Backup-RegistryValue -Path "HKLM:\SOFTWARE\NewKey" -Name "NewProp" -StepTitle "Registry Test Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $entry = $SCRIPT:_backupPending[0]
        $entry.existed | Should -Be $false
        $entry.originalValue | Should -BeNullOrEmpty

        # Flush to disk
        Flush-BackupBuffer

        # Restore should call Remove-ItemProperty for non-existent originals
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "HKLM:\SOFTWARE\NewKey" }
        Mock Get-ItemProperty { [PSCustomObject]@{ NewProp = "some_value" } } -ParameterFilter { $Path -eq "HKLM:\SOFTWARE\NewKey" }
        Mock Remove-ItemProperty {} -Verifiable

        Restore-StepChanges -StepTitle "Registry Test Step"

        Should -InvokeVerifiable
    }

    It "Multiple registry entries are backed up and restored as a group" {
        Mock Test-Path { $true } -ParameterFilter { $Path -like "HKLM:\SOFTWARE\Multi*" }
        Mock Get-ItemProperty {
            if ($Name -eq "ValA") { return [PSCustomObject]@{ ValA = 10 } }
            if ($Name -eq "ValB") { return [PSCustomObject]@{ ValB = 20 } }
        }
        Mock Get-Item {
            $mock = New-Object PSObject
            $mock | Add-Member -MemberType ScriptMethod -Name GetValueKind -Value { "DWord" }
            return $mock
        }

        Backup-RegistryValue -Path "HKLM:\SOFTWARE\MultiA" -Name "ValA" -StepTitle "Multi Step"
        Backup-RegistryValue -Path "HKLM:\SOFTWARE\MultiB" -Name "ValB" -StepTitle "Multi Step"

        $SCRIPT:_backupPending.Count | Should -Be 2

        Flush-BackupBuffer

        $backup = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($backup.entries).Count | Should -Be 2

        # Restore both
        Mock Set-ItemProperty {}
        Restore-StepChanges -StepTitle "Multi Step"

        Should -Invoke Set-ItemProperty -Times 2
    }
}

# ── Service backup/restore roundtrip ─────────────────────────────────────────
Describe "Service backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "Service Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "Backup-ServiceState captures startup type and Restore re-enables" {
        # Mock service query
        Mock Get-Service {
            return [PSCustomObject]@{
                Name = "TestSvc"
                Status = "Running"
                StartType = "Automatic"
            }
        } -ParameterFilter { $Name -eq "TestSvc" }

        Mock Get-CimInstance {
            return [PSCustomObject]@{ StartMode = "Auto" }
        } -ParameterFilter { $ClassName -eq "Win32_Service" }

        Mock Get-ItemProperty {
            return [PSCustomObject]@{ DelayedAutostart = 0 }
        } -ParameterFilter { $Name -eq "DelayedAutostart" }

        Backup-ServiceState -ServiceName "TestSvc" -StepTitle "Service Test Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $entry = $SCRIPT:_backupPending[0]
        $entry.type | Should -Be "service"
        $entry.name | Should -Be "TestSvc"
        $entry.originalStartType | Should -Be "Auto"
        $entry.originalStatus | Should -Be "Running"

        Flush-BackupBuffer

        # Restore
        Mock Set-Service {}
        Mock Start-Service {}

        Restore-StepChanges -StepTitle "Service Test Step"

        Should -Invoke Set-Service -Times 1
        Should -Invoke Start-Service -Times 1  # Because original status was Running
    }

    It "Backup-ServiceState captures delayed auto start flag" {
        Mock Get-Service {
            return [PSCustomObject]@{ Name = "DelayedSvc"; Status = "Running"; StartType = "Automatic" }
        }
        Mock Get-CimInstance {
            return [PSCustomObject]@{ StartMode = "Auto" }
        }
        Mock Get-ItemProperty {
            return [PSCustomObject]@{ DelayedAutostart = 1 }
        }

        Backup-ServiceState -ServiceName "DelayedSvc" -StepTitle "Service Test Step"

        $entry = $SCRIPT:_backupPending[0]
        $entry.delayedAutoStart | Should -Be $true
    }
}

# ── BootConfig backup/restore roundtrip ──────────────────────────────────────
Describe "BootConfig backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "Boot Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "Backup-BootConfig captures existing bcdedit value" {
        # Backup-BootConfig uses bcdedit /enum /v which outputs hex element IDs.
        # "disabledynamictick" maps to 0x26000060 in the bcdElementMap.
        Mock bcdedit {
            return @(
                "Windows Boot Loader",
                "identifier              {current}",
                "0x26000060              Yes"
            )
        }

        Backup-BootConfig -Key "disabledynamictick" -StepTitle "Boot Test Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $entry = $SCRIPT:_backupPending[0]
        $entry.type | Should -Be "bootconfig"
        $entry.key | Should -Be "disabledynamictick"
        $entry.originalValue | Should -Be "Yes"
        $entry.existed | Should -Be $true
    }

    It "Backup-BootConfig captures non-existent bcdedit value" {
        Mock bcdedit {
            return @(
                "Windows Boot Loader",
                "identifier              {current}"
            )
        }

        Backup-BootConfig -Key "nonexistentkey" -StepTitle "Boot Test Step"

        $entry = $SCRIPT:_backupPending[0]
        $entry.existed | Should -Be $false
        $entry.originalValue | Should -BeNullOrEmpty
    }

    It "BootConfig restore calls bcdedit /set for existing values" {
        # bcdedit /enum /v outputs hex element IDs, not localized names
        Mock bcdedit {
            return @("identifier  {current}", "0x26000060  No")
        }

        Backup-BootConfig -Key "disabledynamictick" -StepTitle "Boot Test Step"
        Flush-BackupBuffer

        # Mock bcdedit for restore
        Mock bcdedit {
            $capturedArgs = if ($null -ne $CmdArgs) { @($CmdArgs) } else { @($args) }
            $SCRIPT:MockTracker.Bcdedit.Add(@{ Args = $capturedArgs })
            $global:LASTEXITCODE = 0
            return "The operation completed successfully."
        }

        Restore-StepChanges -StepTitle "Boot Test Step"

        $SCRIPT:MockTracker.Bcdedit.Count | Should -BeGreaterThan 0
        # Verify it used /set (restoring an existing value)
        $setCall = $SCRIPT:MockTracker.Bcdedit | Where-Object { ($_.Args -join " ") -match "/set" }
        $setCall | Should -Not -BeNullOrEmpty
    }

    It "BootConfig restore calls bcdedit /deletevalue for non-existent values" {
        Mock bcdedit {
            return @("identifier  {current}")
        }

        Backup-BootConfig -Key "testkey" -StepTitle "Boot Test Step"
        Flush-BackupBuffer

        Mock bcdedit {
            $capturedArgs = if ($null -ne $CmdArgs) { @($CmdArgs) } else { @($args) }
            $SCRIPT:MockTracker.Bcdedit.Add(@{ Args = $capturedArgs })
            $global:LASTEXITCODE = 0
            return "The operation completed successfully."
        }

        Restore-StepChanges -StepTitle "Boot Test Step"

        $SCRIPT:MockTracker.Bcdedit.Count | Should -BeGreaterThan 0
        # Verify it used /deletevalue (removing a value that didn't originally exist)
        $delCall = $SCRIPT:MockTracker.Bcdedit | Where-Object { ($_.Args -join " ") -match "/deletevalue" }
        $delCall | Should -Not -BeNullOrEmpty
    }
}

# ── PowerPlan backup/restore roundtrip ───────────────────────────────────────
Describe "PowerPlan backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "PowerPlan Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "Backup-PowerPlan captures active plan GUID" {
        Mock powercfg {
            return "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)"
        }

        Backup-PowerPlan -StepTitle "PowerPlan Test Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $entry = $SCRIPT:_backupPending[0]
        $entry.type | Should -Be "powerplan"
        $entry.originalGuid | Should -Be "381b4222-f694-41f0-9685-ff5bb260df2e"
        $entry.originalName | Should -Be "Balanced"
    }

    It "Backup-PowerPlan skips in DRY-RUN" {
        $SCRIPT:DryRun = $true

        Backup-PowerPlan -StepTitle "PowerPlan DRY Test"

        $SCRIPT:_backupPending.Count | Should -Be 0
    }
}

# ── ScheduledTask backup/restore roundtrip ───────────────────────────────────
Describe "ScheduledTask backup and restore roundtrip" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:CurrentStepTitle = "Task Test Step"
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-Host {}
        Mock Write-DebugLog {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Step {}
        Mock Write-Info {}
    }

    It "Backup-ScheduledTask captures existing enabled task" {
        Mock Get-ScheduledTask {
            return [PSCustomObject]@{ TaskName = "TestTask"; State = "Ready" }
        }

        Backup-ScheduledTask -TaskName "TestTask" -StepTitle "Task Test Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $entry = $SCRIPT:_backupPending[0]
        $entry.type | Should -Be "scheduledtask"
        $entry.taskName | Should -Be "TestTask"
        $entry.existed | Should -Be $true
        $entry.wasEnabled | Should -Be $true
    }

    It "Backup-ScheduledTask captures non-existent task" {
        Mock Get-ScheduledTask { $null }

        Backup-ScheduledTask -TaskName "NewTask" -StepTitle "Task Test Step" -ScriptPath "C:\test.ps1"

        $entry = $SCRIPT:_backupPending[0]
        $entry.existed | Should -Be $false
        $entry.wasEnabled | Should -Be $false
        $entry.scriptPath | Should -Be "C:\test.ps1"
    }

    It "Restore removes task that did not exist before" {
        Mock Get-ScheduledTask { $null }
        Backup-ScheduledTask -TaskName "CreatedTask" -StepTitle "Task Test Step" -ScriptPath "C:\fake.ps1"
        Flush-BackupBuffer

        # Mock for restore: task now exists and should be removed
        Mock Get-ScheduledTask {
            return [PSCustomObject]@{ TaskName = "CreatedTask"; State = "Ready" }
        }
        Mock Unregister-ScheduledTask {}
        Mock Test-Path { $false } -ParameterFilter { $Path -eq "C:\fake.ps1" }

        Restore-StepChanges -StepTitle "Task Test Step"

        Should -Invoke Unregister-ScheduledTask -Times 1
    }

    It "Restore re-enables task that was enabled before" {
        Mock Get-ScheduledTask {
            return [PSCustomObject]@{ TaskName = "EnabledTask"; State = "Ready" }
        }
        Backup-ScheduledTask -TaskName "EnabledTask" -StepTitle "Task Test Step"
        Flush-BackupBuffer

        # Mock for restore: task is now disabled
        Mock Get-ScheduledTask {
            return [PSCustomObject]@{ TaskName = "EnabledTask"; State = "Disabled" }
        }
        Mock Enable-ScheduledTask {}

        Restore-StepChanges -StepTitle "Task Test Step"

        Should -Invoke Enable-ScheduledTask -Times 1
    }
}

# ── Flush-BackupBuffer integration ──────────────────────────────────────────
Describe "Flush-BackupBuffer integration" {

    BeforeEach {
        Reset-IntegrationState
        $SCRIPT:DryRun = $false
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        New-TestBackupFile -Entries @()

        Mock Write-DebugLog {}
    }

    It "Flush writes pending entries to backup.json and clears buffer" {
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; path = "HKLM:\Test"; name = "X";
            originalValue = 1; originalType = "DWord"; existed = $true;
            step = "Flush Test"; timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; path = "HKLM:\Test"; name = "Y";
            originalValue = 2; originalType = "DWord"; existed = $true;
            step = "Flush Test"; timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })

        $SCRIPT:_backupPending.Count | Should -Be 2

        Flush-BackupBuffer

        $SCRIPT:_backupPending.Count | Should -Be 0
        $backup = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($backup.entries).Count | Should -Be 2
    }

    It "Flush is idempotent (no-op when buffer is empty)" {
        Flush-BackupBuffer
        Flush-BackupBuffer

        $backup = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($backup.entries).Count | Should -Be 0
    }
}

# ── Corrupted backup.json handling ──────────────────────────────────────────
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

        # A .corrupt.* file should have been created
        $corruptFiles = Get-ChildItem (Split-Path $CFG_BackupFile -Parent) -Filter "backup.json.corrupt.*"
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
