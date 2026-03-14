# ==============================================================================
#  helpers/step-state.ps1  —  Step Progress / Resume System
# ==============================================================================

function Load-Progress {
    if (Test-Path $CFG_ProgressFile) {
        try { return (Get-Content $CFG_ProgressFile | ConvertFrom-Json) } catch {}
    }
    return $null
}

function Save-Progress($prog) {
    Save-JsonAtomic -Data $prog -Path $CFG_ProgressFile
    Write-Debug "Progress saved: Phase $($prog.phase) Step $($prog.lastCompletedStep)"
}

function Complete-Step($phase, $stepNum, $stepName) {
    $prog = Load-Progress
    if (-not $prog) {
        $prog = [PSCustomObject]@{ phase=0; lastCompletedStep=0; completedSteps=@(); skippedSteps=@(); timestamps=@{} }
    }
    $prog.phase             = $phase
    $prog.lastCompletedStep = $stepNum
    if ($stepNum -notin $prog.completedSteps) { $prog.completedSteps = @($prog.completedSteps) + $stepNum }
    $prog.timestamps | Add-Member -NotePropertyName "$phase-$stepNum" `
        -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
    Save-Progress $prog
    Write-Debug "Step $stepNum completed: $stepName"
}

function Skip-Step($phase, $stepNum, $stepName) {
    $prog = Load-Progress
    if (-not $prog) {
        $prog = [PSCustomObject]@{ phase=0; lastCompletedStep=0; completedSteps=@(); skippedSteps=@(); timestamps=@{} }
    }
    if ($stepNum -notin $prog.skippedSteps) { $prog.skippedSteps = @($prog.skippedSteps) + $stepNum }
    # Do NOT add to completedSteps — skippedSteps is a separate semantic.
    # Test-StepDone checks both arrays for resume purposes.
    $prog.phase = $phase
    $prog.lastCompletedStep = [math]::Max($prog.lastCompletedStep, $stepNum)
    Save-Progress $prog
}

function Test-StepDone($phase, $stepNum) {
    $prog = Load-Progress
    if (-not $prog -or $prog.phase -ne $phase) { return $false }
    # A step is "done" for resume purposes if it was either completed or skipped
    return ($stepNum -in $prog.completedSteps -or $stepNum -in $prog.skippedSteps)
}

function Show-ResumePrompt($phase, $totalSteps) {
    $prog = Load-Progress
    if (-not $prog -or $prog.phase -ne $phase -or $prog.lastCompletedStep -eq 0) { return 1 }
    $nextStep = $prog.lastCompletedStep + 1
    if ($nextStep -gt $totalSteps) {
        Write-Info "All steps in this phase already completed."
        $r = Read-Host "  Start over anyway? [y/N]"
        if ($r -match "^[jJyY]$") { Clear-Progress $phase; return 1 }
        return ($totalSteps + 1)
    }
    if ($SCRIPT:Mode -eq "AUTO") {
        Write-Info "Auto-resume from step $nextStep."
        return $nextStep
    }
    Write-Blank
    Write-Host "  ┌─────────────────────────────────────────────────────────" -ForegroundColor DarkYellow
    Write-Host "  │  RESUME — Previous session found" -ForegroundColor Yellow
    Write-Host "  │  Last step: $($prog.lastCompletedStep)  |  Continue from: $nextStep" -ForegroundColor White
    $doneList = ($prog.completedSteps -join ', ')
    $skipList = if ($prog.skippedSteps -and $prog.skippedSteps.Count -gt 0) { " | Skipped: $($prog.skippedSteps -join ', ')" } else { "" }
    Write-Host "  │  Completed: $doneList$skipList" -ForegroundColor DarkGray
    Write-Host "  │" -ForegroundColor DarkYellow
    Write-Host "  │  [1]  Resume from step $nextStep" -ForegroundColor Green
    Write-Host "  │  [2]  Choose a specific step" -ForegroundColor White
    Write-Host "  │  [3]  Start over (reset progress)" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────────" -ForegroundColor DarkYellow
    do { $r = Read-Host "  [1/2/3]" } while ($r -notin @("1","2","3"))
    switch ($r) {
        "1" { return $nextStep }
        "2" {
            $s = Read-Host "  From step (1-$totalSteps)"
            $sv = 1
            if ([int]::TryParse($s,[ref]$sv) -and $sv -ge 1 -and $sv -le $totalSteps) { return $sv }
            return $nextStep
        }
        "3" { Clear-Progress $phase; return 1 }
    }
    return $nextStep
}

function Clear-Progress($phase = $null) {
    if (-not (Test-Path $CFG_ProgressFile)) { return }
    $prog = Load-Progress
    if (-not $prog) { return }

    if (-not $phase -or $prog.phase -eq $phase) {
        # Reset to empty progress rather than deleting the file — avoids race conditions
        # and makes intent clear (file exists but no steps are done)
        $empty = [PSCustomObject]@{ phase=0; lastCompletedStep=0; completedSteps=@(); skippedSteps=@(); timestamps=@{} }
        Save-Progress $empty
        Write-Debug "Progress reset$(if($phase){" (Phase $phase)"})"
    } else {
        Write-Debug "Progress not reset — file tracks Phase $($prog.phase), requested Phase $phase"
    }
}
