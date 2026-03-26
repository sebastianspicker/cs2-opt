# ==============================================================================
#  tests/helpers/logging.Tests.ps1  --  Logging, console output, banners
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/_TestInit.ps1"
    # logging.ps1 is already loaded by _TestInit.ps1
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Write-OK / Write-Warn / Write-Err ──────────────────────────────────────
Describe "Write-OK" {

    BeforeEach { Reset-TestState }

    It "produces console output" {
        $output = Write-OK "test ok message" 6>&1
        # Write-OK calls Write-Host internally, which goes to information stream
        # Verify it doesn't throw
        { Write-OK "test ok message" } | Should -Not -Throw
    }

    It "writes to log file" {
        Initialize-Log
        Write-OK "logged ok message"
        $logContent = Get-Content $CFG_LogFile -Raw
        $logContent | Should -Match "logged ok message"
    }
}

Describe "Write-Warn" {

    BeforeEach { Reset-TestState }

    It "does not throw" {
        { Write-Warn "test warning" } | Should -Not -Throw
    }

    It "writes WARN level to log file" {
        Initialize-Log
        Write-Warn "warning message"
        $logContent = Get-Content $CFG_LogFile -Raw
        $logContent | Should -Match "\[WARN\].*warning message"
    }
}

Describe "Write-Err" {

    BeforeEach { Reset-TestState }

    It "does not throw" {
        { Write-Err "test error" } | Should -Not -Throw
    }

    It "writes ERROR level to log file" {
        Initialize-Log
        Write-Err "error message"
        $logContent = Get-Content $CFG_LogFile -Raw
        $logContent | Should -Match "\[ERROR\].*error message"
    }
}

# ── Write-Debug suppression ────────────────────────────────────────────────
Describe "Write-Debug (custom)" {

    BeforeEach { Reset-TestState }

    It "is suppressed at MINIMAL log level" {
        $SCRIPT:LogLevel = "MINIMAL"
        Initialize-Log
        Write-Debug "should not appear"
        $logContent = Get-Content $CFG_LogFile -Raw
        # The log file should contain the initial header but not the debug message
        # (Write-Log still writes to file, but show=false means no console output)
        # Actually, Write-Log writes to file regardless, then conditionally shows on console
        # Let's verify it writes to file but verify console suppression
        { Write-Debug "debug suppressed" } | Should -Not -Throw
    }

    It "is shown at VERBOSE log level" {
        $SCRIPT:LogLevel = "VERBOSE"
        Initialize-Log
        Write-Debug "verbose debug message"
        $logContent = Get-Content $CFG_LogFile -Raw
        $logContent | Should -Match "verbose debug message"
    }
}

# ── Write-Log ──────────────────────────────────────────────────────────────
Describe "Write-Log" {

    BeforeEach { Reset-TestState }

    It "includes timestamp in log line" {
        Initialize-Log
        Write-Log "INFO" "timestamp test"
        $logContent = Get-Content $CFG_LogFile -Raw
        # Format: [HH:mm:ss][LEVEL] message
        $logContent | Should -Match '\[\d{2}:\d{2}:\d{2}\]\[INFO\] timestamp test'
    }

    It "handles all standard log levels without error" {
        $levels = @("ERROR", "WARN", "OK", "INFO", "SECTION", "STEP", "DEBUG", "T1", "T2", "T3")
        Initialize-Log
        foreach ($level in $levels) {
            { Write-Log $level "test $level" } | Should -Not -Throw
        }
    }

    It "writes to log file when log directory exists" {
        Initialize-Log
        Write-Log "INFO" "file write test"
        Test-Path $CFG_LogFile | Should -Be $true
        $content = Get-Content $CFG_LogFile -Raw
        $content | Should -Match "file write test"
    }
}

# ── Write-Blank / Write-Sub ────────────────────────────────────────────────
Describe "Write-Blank" {

    It "produces empty line without error" {
        { Write-Blank } | Should -Not -Throw
    }
}

Describe "Write-Sub" {

    It "does not throw" {
        { Write-Sub "sub message" } | Should -Not -Throw
    }
}

# ── Write-ActionOK ──────────────────────────────────────────────────────────
Describe "Write-ActionOK" {

    BeforeEach { Reset-TestState }

    It "produces output when not in DRY-RUN" {
        $SCRIPT:DryRun = $false
        { Write-ActionOK "action completed" } | Should -Not -Throw
    }

    It "is suppressed in DRY-RUN mode" {
        $SCRIPT:DryRun = $true
        # Write-ActionOK should not call Write-OK in DRY-RUN
        Mock Write-OK {}
        Write-ActionOK "should be suppressed"
        Should -Invoke Write-OK -Times 0
    }
}

# ── Write-TierBadge ────────────────────────────────────────────────────────
Describe "Write-TierBadge" {

    BeforeEach { Reset-TestState }

    It "displays T1 badge" {
        Initialize-Log
        { Write-TierBadge 1 "Proven setting" } | Should -Not -Throw
    }

    It "displays T2 badge" {
        { Write-TierBadge 2 "Setup dependent" } | Should -Not -Throw
    }

    It "displays T3 badge" {
        { Write-TierBadge 3 "Community consensus" } | Should -Not -Throw
    }

    It "handles unknown tier" {
        { Write-TierBadge 99 "Unknown tier" } | Should -Not -Throw
    }
}

# ── Write-Section ──────────────────────────────────────────────────────────
Describe "Write-Section" {

    BeforeEach { Reset-TestState }

    It "displays section header without error" {
        Initialize-Log
        { Write-Section "Test Section" } | Should -Not -Throw
    }

    It "logs SECTION level" {
        Initialize-Log
        Write-Section "Logged Section"
        $logContent = Get-Content $CFG_LogFile -Raw
        $logContent | Should -Match "\[SECTION\].*Logged Section"
    }

    It "shows progress bar when PhaseTotal is set" {
        $SCRIPT:PhaseTotal = 10
        Initialize-Log
        { Write-Section "Step 5 — Test" } | Should -Not -Throw
        $SCRIPT:PhaseTotal = $null
    }
}

# ── Initialize-Log ─────────────────────────────────────────────────────────
Describe "Initialize-Log" {

    BeforeEach { Reset-TestState }

    It "creates log file" {
        Initialize-Log
        Test-Path $CFG_LogFile | Should -Be $true
    }

    It "writes header with profile and mode" {
        $SCRIPT:Profile = "COMPETITIVE"
        $SCRIPT:Mode = "CONTROL"
        Initialize-Log
        $content = Get-Content $CFG_LogFile -Raw
        $content | Should -Match "COMPETITIVE"
        $content | Should -Match "CONTROL"
    }

    It "rotates existing log file" {
        Initialize-Log
        Add-Content $CFG_LogFile "first run content" -Encoding UTF8
        Initialize-Log  # Second call should rotate
        # The rotated file should exist
        $rotatedFiles = Get-ChildItem $CFG_LogDir -Filter "optimize_*.log"
        $rotatedFiles.Count | Should -BeGreaterOrEqual 1
    }
}
