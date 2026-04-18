BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
