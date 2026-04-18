BeforeAll {
    . "$PSScriptRoot/../_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
