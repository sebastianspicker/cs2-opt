BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
