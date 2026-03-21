# ==============================================================================
#  tests/helpers/backup-restore.Tests.ps1  --  Backup & restore system tests
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/_TestInit.ps1"
}

BeforeEach {
    Reset-TestState
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Initialize-Backup ────────────────────────────────────────────────────────
Describe "Initialize-Backup" {

    BeforeEach {
        Mock Test-BackupLock { $false }
        Mock Set-BackupLock {}
    }

    It "creates backup.json with valid structure" {
        Initialize-Backup

        Test-Path $CFG_BackupFile | Should -Be $true
        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        $data.entries | Should -Not -BeNullOrEmpty
        # entries should be an array (may be empty)
        @($data.entries).Count | Should -BeGreaterOrEqual 0
        $data.created | Should -Not -BeNullOrEmpty
    }

    It "does not overwrite existing backup.json" {
        # Create a backup with an entry
        $existing = @{
            entries = @(
                [ordered]@{ type = "registry"; name = "TestValue"; step = "Existing Step" }
            )
            created = "2026-01-01 00:00:00"
        }
        $existing | ConvertTo-Json -Depth 10 | Set-Content $CFG_BackupFile -Encoding UTF8

        Initialize-Backup

        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        $data.created | Should -Be "2026-01-01 00:00:00"
    }

    It "warns when backup lock exists" {
        Mock Test-BackupLock { $true }
        Mock Write-Warn {} -Verifiable

        Initialize-Backup

        Should -Invoke Write-Warn -AtLeast 1
    }
}

# ── Backup-RegistryValue (in-memory buffering) ──────────────────────────────
Describe "Backup-RegistryValue" {

    BeforeEach {
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
    }

    It "adds entry to in-memory buffer (not disk)" {
        Mock Test-Path { $false } -ParameterFilter { $Path -match "HKLM:" }

        Backup-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "TestVal" -StepTitle "Step 1"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $SCRIPT:_backupPending[0].type | Should -Be "registry"
        $SCRIPT:_backupPending[0].name | Should -Be "TestVal"
        $SCRIPT:_backupPending[0].step | Should -Be "Step 1"
        $SCRIPT:_backupPending[0].existed | Should -Be $false
    }

    It "captures existing value when registry key exists" {
        Mock Test-Path { $true } -ParameterFilter { $Path -match "HKLM:" }
        Mock Get-ItemProperty {
            [PSCustomObject]@{ TestVal = 42 }
        } -ParameterFilter { $Path -match "HKLM:" }
        Mock Get-Item {
            $mockReg = [PSCustomObject]@{}
            $mockReg | Add-Member -MemberType ScriptMethod -Name "GetValueKind" -Value { "DWord" }
            $mockReg
        } -ParameterFilter { $Path -match "HKLM:" }

        Backup-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "TestVal" -StepTitle "Step 1"

        $SCRIPT:_backupPending[0].existed       | Should -Be $true
        $SCRIPT:_backupPending[0].originalValue  | Should -Be 42
        $SCRIPT:_backupPending[0].originalType   | Should -Be "DWord"
    }
}

# ── Flush-BackupBuffer ───────────────────────────────────────────────────────
Describe "Flush-BackupBuffer" {

    It "writes buffered entries to backup.json" {
        # Initialize backup file
        New-TestBackupFile

        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; path = "HKLM:\Test"; name = "Val1";
            originalValue = $null; existed = $false; step = "Step 1";
            timestamp = "2026-01-01 00:00:00"
        })

        Flush-BackupBuffer

        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($data.entries).Count | Should -Be 1
        $SCRIPT:_backupPending.Count | Should -Be 0
    }

    It "is a no-op when buffer is empty" {
        New-TestBackupFile

        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

        { Flush-BackupBuffer } | Should -Not -Throw

        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($data.entries).Count | Should -Be 0
    }
}

# ── Get-BackupData ────────────────────────────────────────────────────────────
Describe "Get-BackupData" {

    It "returns entries from disk" {
        $entries = @(
            [ordered]@{ type = "registry"; name = "A"; step = "Step 1"; timestamp = "2026-01-01" },
            [ordered]@{ type = "registry"; name = "B"; step = "Step 2"; timestamp = "2026-01-01" }
        )
        New-TestBackupFile -Entries $entries

        $data = Get-BackupData
        @($data.entries).Count | Should -Be 2
    }

    It "handles corrupted JSON by resetting" {
        "this is {{{ not valid json" | Set-Content $CFG_BackupFile -Encoding UTF8

        Mock Write-Warn {}
        Mock Write-Debug {}

        $data = Get-BackupData

        @($data.entries).Count | Should -Be 0
        # Should have created a .corrupt backup
        $corruptFiles = @(Get-ChildItem "$SCRIPT:TestTempRoot" -Filter "backup.json.corrupt.*")
        $corruptFiles.Count | Should -BeGreaterOrEqual 1
    }

    It "initializes backup.json if file is missing" {
        # Ensure no backup file
        Remove-Item $CFG_BackupFile -Force -ErrorAction SilentlyContinue
        Mock Test-BackupLock { $false }
        Mock Set-BackupLock {}

        $data = Get-BackupData

        Test-Path $CFG_BackupFile | Should -Be $true
        @($data.entries).Count | Should -Be 0
    }

    It "flushes pending buffer before returning" {
        New-TestBackupFile

        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; name = "Pending"; step = "Step X"; timestamp = "2026-01-01"
        })

        $data = Get-BackupData

        @($data.entries).Count | Should -Be 1
        @($data.entries)[0].name | Should -Be "Pending"
        $SCRIPT:_backupPending.Count | Should -Be 0
    }
}

# ── Backup accumulation ─────────────────────────────────────────────────────
Describe "Backup accumulation" {

    It "accumulates multiple entries for the same step" {
        New-TestBackupFile

        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; name = "Val1"; step = "Step 1"; timestamp = "2026-01-01"
        })
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; name = "Val2"; step = "Step 1"; timestamp = "2026-01-01"
        })
        Flush-BackupBuffer

        # Add more entries for the same step
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; name = "Val3"; step = "Step 1"; timestamp = "2026-01-01"
        })
        Flush-BackupBuffer

        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($data.entries).Count | Should -Be 3
        @($data.entries | Where-Object { $_.step -eq "Step 1" }).Count | Should -Be 3
    }

    It "accumulates entries across different steps" {
        New-TestBackupFile

        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; name = "A"; step = "Step 1"; timestamp = "2026-01-01"
        })
        $SCRIPT:_backupPending.Add([ordered]@{
            type = "registry"; name = "B"; step = "Step 2"; timestamp = "2026-01-01"
        })
        Flush-BackupBuffer

        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        $step1 = @($data.entries | Where-Object { $_.step -eq "Step 1" })
        $step2 = @($data.entries | Where-Object { $_.step -eq "Step 2" })
        $step1.Count | Should -Be 1
        $step2.Count | Should -Be 1
    }
}

# ── Restore-StepChanges ─────────────────────────────────────────────────────
Describe "Restore-StepChanges" {

    BeforeEach {
        Mock Write-Host {}
        Mock Write-Step {}
        Mock Write-OK {}
        Mock Write-Warn {}
        Mock Write-Debug {}
        Mock Write-Info {}
    }

    It "returns false when no backup exists for the step" {
        New-TestBackupFile

        $result = Restore-StepChanges -StepTitle "Nonexistent Step"

        $result | Should -Be $false
    }

    It "restores registry value and removes entry on success" {
        $entries = @(
            [ordered]@{
                type = "registry"; path = "HKLM:\SOFTWARE\Test"; name = "Restored";
                originalValue = 99; originalType = "DWord"; existed = $true;
                step = "Test Step"; timestamp = "2026-01-01"
            }
        )
        New-TestBackupFile -Entries $entries

        Mock Test-Path { $true } -ParameterFilter { $Path -match "HKLM:" }
        Mock Set-ItemProperty {}

        $result = Restore-StepChanges -StepTitle "Test Step"

        $result | Should -Be $true
        Should -Invoke Set-ItemProperty -Exactly 1

        # Entry should be removed from backup after successful restore
        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($data.entries).Count | Should -Be 0
    }

    It "removes registry value that did not exist before" {
        $entries = @(
            [ordered]@{
                type = "registry"; path = "HKLM:\SOFTWARE\Test"; name = "NewValue";
                originalValue = $null; originalType = $null; existed = $false;
                step = "Test Step"; timestamp = "2026-01-01"
            }
        )
        New-TestBackupFile -Entries $entries

        Mock Test-Path { $true } -ParameterFilter { $Path -match "HKLM:" }
        Mock Remove-ItemProperty {}

        $result = Restore-StepChanges -StepTitle "Test Step"

        $result | Should -Be $true
        Should -Invoke Remove-ItemProperty -Exactly 1
    }

    It "keeps entries on restore failure" {
        $entries = @(
            [ordered]@{
                type = "registry"; path = "HKLM:\SOFTWARE\Test"; name = "FailVal";
                originalValue = 1; originalType = "DWord"; existed = $true;
                step = "Fail Step"; timestamp = "2026-01-01"
            }
        )
        New-TestBackupFile -Entries $entries

        Mock Test-Path { $true } -ParameterFilter { $Path -match "HKLM:" }
        Mock Set-ItemProperty { throw "Access denied" }

        $result = Restore-StepChanges -StepTitle "Fail Step"

        $result | Should -Be $false

        # Entries should be retained for retry
        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($data.entries).Count | Should -Be 1
    }

    It "restores only the specified step's entries" {
        $entries = @(
            [ordered]@{
                type = "registry"; path = "HKLM:\Test"; name = "A";
                originalValue = 1; originalType = "DWord"; existed = $true;
                step = "Step A"; timestamp = "2026-01-01"
            },
            [ordered]@{
                type = "registry"; path = "HKLM:\Test"; name = "B";
                originalValue = 2; originalType = "DWord"; existed = $true;
                step = "Step B"; timestamp = "2026-01-01"
            }
        )
        New-TestBackupFile -Entries $entries

        Mock Test-Path { $true } -ParameterFilter { $Path -match "HKLM:" }
        Mock Set-ItemProperty {}

        Restore-StepChanges -StepTitle "Step A"

        $data = Get-Content $CFG_BackupFile -Raw | ConvertFrom-Json
        @($data.entries).Count | Should -Be 1
        $data.entries[0].step | Should -Be "Step B"
    }
}

# ── Backup-ServiceState ─────────────────────────────────────────────────────
Describe "Backup-ServiceState" {

    BeforeEach {
        $SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()
    }

    It "captures service start type and status" {
        Mock Get-Service {
            [PSCustomObject]@{ Status = "Running" }
        } -ParameterFilter { $Name -eq "TestSvc" }

        Mock Get-CimInstance {
            [PSCustomObject]@{ StartMode = "Auto" }
        } -ParameterFilter { $ClassName -eq "Win32_Service" }

        Mock Get-ItemProperty {
            [PSCustomObject]@{ DelayedAutostart = 0 }
        }

        Backup-ServiceState -ServiceName "TestSvc" -StepTitle "Service Step"

        $SCRIPT:_backupPending.Count | Should -Be 1
        $SCRIPT:_backupPending[0].type | Should -Be "service"
        $SCRIPT:_backupPending[0].name | Should -Be "TestSvc"
        $SCRIPT:_backupPending[0].originalStartType | Should -Be "Auto"
        $SCRIPT:_backupPending[0].originalStatus | Should -Be "Running"
    }

    It "handles service not found gracefully" {
        Mock Get-Service { throw "Service not found" } -ParameterFilter { $Name -eq "FakeSvc" }
        Mock Write-Debug {}

        { Backup-ServiceState -ServiceName "FakeSvc" -StepTitle "Step" } | Should -Not -Throw
        $SCRIPT:_backupPending.Count | Should -Be 0
    }
}

# ── Backup lock system ───────────────────────────────────────────────────────
Describe "Backup lock system" {

    It "Set-BackupLock creates lock file with PID" {
        Set-BackupLock

        Test-Path $CFG_BackupLockFile | Should -Be $true
        $lockData = Get-Content $CFG_BackupLockFile -Raw | ConvertFrom-Json
        $lockData.pid | Should -Be $PID
    }

    It "Remove-BackupLock removes lock file" {
        Set-BackupLock
        Remove-BackupLock

        Test-Path $CFG_BackupLockFile | Should -Be $false
    }

    It "Test-BackupLock returns true for live process" {
        Set-BackupLock

        Test-BackupLock | Should -Be $true
    }

    It "Test-BackupLock returns false when no lock exists" {
        Remove-Item $CFG_BackupLockFile -Force -ErrorAction SilentlyContinue

        Test-BackupLock | Should -Be $false
    }

    It "Test-BackupLock cleans stale lock from dead process" {
        # Write a lock with a PID that definitely doesn't exist
        $fakeLock = @{ pid = 99999999; started = "2026-01-01 00:00:00" }
        $fakeLock | ConvertTo-Json | Set-Content $CFG_BackupLockFile -Encoding UTF8

        # Mock Get-Process to return null (process doesn't exist)
        Mock Get-Process { $null } -ParameterFilter { $Id -eq 99999999 }

        Test-BackupLock | Should -Be $false
        Test-Path $CFG_BackupLockFile | Should -Be $false
    }
}
