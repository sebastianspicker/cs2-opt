# ==============================================================================
#  tests/SafeMode-DriverClean.Tests.ps1  --  direct shipped-entrypoint contract tests
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/helpers/_TestInit.ps1"
    $script:ProjectRoot = (Resolve-Path "$PSScriptRoot/..").Path
    $script:TargetScript = Join-Path $script:ProjectRoot "SafeMode-DriverClean.ps1"
    $script:TargetSource = Get-Content $script:TargetScript -Raw
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "SafeMode-DriverClean.ps1 shipped smoke contract" {

    It "supports -SmokeTest as a clean short-circuit" -Skip:(-not $IsWindows) {
        $records = & powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:TargetScript -SmokeTest 2>&1
        $exitCode = $LASTEXITCODE
        $output = ($records | ForEach-Object { $_.ToString() }) -join "`n"
        $errorRecords = @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $exitCode | Should -Be 0
        $errorRecords | Should -BeNullOrEmpty
        $output | Should -Match 'SMOKE TEST OK'
    }
}

Describe "SafeMode-DriverClean.ps1 prerequisite guardrails" {

    It "fails closed when state.json is missing or corrupt" {
        $script:TargetSource | Should -Match 'state\.json.*missing or corrupted'
        $script:TargetSource | Should -Not -Match 'Continue with defaults\? \[y/N\]'
        $script:TargetSource | Should -Not -Match 'continue with safe defaults'
    }

    It "requires the Phase 1 handoff and an actual Safe Mode boot" {
        $script:TargetSource | Should -Match 'Test-Phase1SafeModeReady\s+-State\s+\$state'
        $script:TargetSource | Should -Match 'This script needs Safe Mode to work properly'
        $script:TargetSource | Should -Match 'Aborted\. Boot into Safe Mode first'
    }
}
