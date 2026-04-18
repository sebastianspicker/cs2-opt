BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
