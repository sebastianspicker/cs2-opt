BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
