# PSScriptAnalyzer settings for CS2 Optimization Suite
# Run: Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # ── Intentional by design ─────────────────────────────────────────
        # This is a CLI tool — Write-Host with colors is the correct output
        'PSAvoidUsingWriteHost',

        # UTF-8 without BOM is preferred (modern tooling, git compatibility)
        'PSUseBOMForUnicodeEncodedFile',

        # Empty catches are intentional best-effort patterns throughout:
        # state loading, hardware detection, optional cleanup, async teardown
        'PSAvoidUsingEmptyCatchBlock',

        # config.env.ps1 exports variables consumed via dot-sourcing;
        # PSScriptAnalyzer can't track cross-file variable usage
        'PSUseDeclaredVarsMoreThanAssignments',

        # Suite has its own DRY-RUN / consent system (Invoke-TieredStep);
        # ShouldProcess would be redundant
        'PSUseShouldProcessForStateChangingFunctions',

        # Internal functions not exported as a module — verb/noun conventions
        # are relaxed for readability (Load-State, Apply-*, Ensure-Dir, etc.)
        'PSUseApprovedVerbs',

        # Plural nouns are clearer for functions that operate on collections
        # (Restore-DrsSettings, Backup-DrsSettings, etc.)
        'PSUseSingularNouns',

        # logging.ps1 intentionally overrides Write-Log and Write-Debug
        # with custom implementations for the suite's logging system
        'PSAvoidOverwritingBuiltInCmdlets',

        # Some params are used inside scriptblocks passed to Invoke-DrsSession
        # which PSScriptAnalyzer can't track; others are API-contract placeholders
        'PSReviewUnusedParameter',

        # Pagefile code in Optimize-SystemBase.ps1 requires WMI .Put() methods
        # that have no simple Get-CimInstance equivalent; annotated in code
        'PSAvoidUsingWMICmdlet'
    )
}
