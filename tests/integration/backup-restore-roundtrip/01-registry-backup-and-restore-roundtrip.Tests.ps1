BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
