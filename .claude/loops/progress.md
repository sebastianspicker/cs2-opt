# Audit Progress Tracker — Round 2

Second pass after Round 1 fixed ~51 bugs, added ~170 tests, and corrected 8 doc files. This round focuses on: regressions from Round 1 fixes, deeper edge cases, new code quality, test correctness, and integration between fixes.

## Phase A: Infrastructure

### A1 — Core Infrastructure (Round 2) — COMPLETE
- [x] Validate Round 1 fixes (Save-JsonAtomic dir creation, DDR5 XMP, VDF parsing) — all correct
- [x] Flush-BackupBuffer integration in Invoke-TieredStep — FIXED: added defensive flush to DRY-RUN path
- [x] New -ErrorAction Stop additions — do they change control flow? — all callers have appropriate try/catch
- [x] EstimateKey wiring (Steps 23/27) — values correct? — both keys exist, values reasonable
- [x] Config cross-check round 2 (any new orphans from B-loop changes?) — 5 orphaned config entries are intentional (GUI catalog / merged step sub-components)

### A2 — Backup/Restore & State (Round 2) — COMPLETE
- [x] Backup buffering correctness — Flush-BackupBuffer timing correct: entries buffer in memory during step, flush at step boundary via Invoke-TieredStep. If Save-BackupData throws, entries stay in memory for retry (Clear() is after Save). Get-BackupData flushes first; if flush fails, exception propagates and stale data is never returned. Zero-write step: Flush no-ops cleanly (count=0 early return). Thread-safety: single-threaded PS, not an issue. Crash between Backup-RegistryValue calls: entries lost (by-design tradeoff documented in header comment).
- [x] Lockfile system — FIXED 2 issues: (1) Remove-BackupLock was never called in any entry point (lock acquired but never released on normal exit). Added Remove-BackupLock to Run-Optimize.ps1, PostReboot-Setup.ps1, SafeMode-DriverClean.ps1. Stale lock auto-cleans on crash (process dead). (2) PID reuse: added PowerShell process name check to Test-BackupLock — recycled PIDs from non-PowerShell processes are treated as stale. Race condition: advisory lock only (documented), Save-JsonAtomic protects actual data. Lock path: Ensure-Dir $CFG_WorkDir called before Initialize-Backup in all entry points.
- [x] Binary restore [0,255] validation — Validation correctly skips (with warning + restoreFail++) rather than throwing. Negative ints from JSON: check `$_ -lt 0` catches them. FIXED: MultiString single-string case — PS 5.1 ConvertFrom-Json unwraps single-element arrays to scalars; added scalar-to-array coercion. ExpandString: Set-ItemProperty -Type ExpandString is valid PS, no special handling needed.
- [x] Legacy step-key removal — All Test-StepDone calls use composite keys (phase + stepNum params). GUI panels use "P{phase}:{step}" format. Dashboard uses regex ^P1:/^P3: matching. Pre-update progress.json with bare numbers: Test-StepDone returns $false (documented: "user re-runs from step 1"). No bare-number callers found.
- [x] wasEnabled scheduled task field — Restore reads it (line 541): $shouldBeEnabled defaults to $true if field is $null (handles pre-Round-1 backups). Boolean preserved through JSON round-trip (ConvertTo-Json serializes $true/$false correctly). $null -ne check works for both $true and $false values.
- [x] BONUS: Fixed Pester 5.7.1 root-level BeforeEach incompatibility in all 4 test files (backup-restore, step-state, system-utils, tier-system). Moved Reset-TestState into per-Describe BeforeEach blocks.

### A3 — DRY-RUN Correctness (Round 2) — COMPLETE
- [x] Verify Round 1 DRY-RUN guards (shader cache, bcdedit, Restart-Computer, Invoke-Download) — all 5 guards correct and producing messages
- [x] New code from other loops — no new DRY-RUN leaks: B1 Get-CS2InstallPath read-only, B4 UserPreferencesMask via Set-RegistryValue (intercepted), B5 CIM enumeration read-only + Remove-GpuDriverClean early-returns, B6 DNS gated by $SCRIPT:DryRun check, D1 Verify-Settings read-only, D2 system-analysis read-only
- [x] DRY-RUN output message consistency — FIXED: 2 messages in Optimize-Hardware.ps1 (URO, QoS DSCP) used Write-Info instead of Write-Host Magenta; corrected
- [x] State persistence correctness — state.json written (Setup-Profile runs before DRY-RUN applies); progress.json NOT updated in DRY-RUN (intentional: Complete-Step/Skip-Step return early); backup.json NOT written (Backup-RegistryValue/ServiceState/BootConfig gated by `-not $SCRIPT:DryRun` in Set-RegistryValue/Set-BootConfig); Flush-BackupBuffer defensive call in tier-system DRY-RUN path handles edge cases

---

## Phase B: Phase Scripts

### B1 — System Base (Round 2) — COMPLETE
- [x] New Skip-Step additions (Steps 2,3,4,6) — correct params? — All 8 steps (2-9) have SkipAction with correct $PHASE, step number, and title matching their Complete-Step calls. CUSTOM profile T1 decline path traces correctly through tier-system.ps1 line 348-350.
- [x] Shader cache lock detection — false positives? — Get-Process -Name "steam" is exact match (does NOT match steamwebhelper). Pre-deletion warning is precautionary ("may be locked"), not assertive. If Steam runs but no files are locked, deletion succeeds and shows "Cleared". Remaining count includes directories (cosmetic, not functional). Step always completes.
- [x] FSO Get-CS2InstallPath integration — handles all Steam library formats? — Returns game directory, FSO code correctly appends \game\bin\win64\cs2.exe. Null return falls through to manual instructions. VDF regex handles escaped backslashes and forward slashes. Fallback loop covers C/D/E/F common locations. Test-Path works on UNC/network paths.
- [x] Power plan HP→Balanced fallback — correct GUID? — SCHEME_BALANCED is correct alias for 381b4222-f694-41f0-9685-ff5bb260df2e. DRY-RUN guard correct. FIXED: Added LASTEXITCODE check after SCHEME_BALANCED activation — if both HP and Balanced are unavailable, shows actionable manual instruction instead of false success message.
- [x] Pagefile non-C: warning — actionable message? — WMI query correct, filter for non-C: StartsWith check correct. Warning names drives and directs user to System Properties -> Advanced. AutomaticManagedPagefile .Put() works. C: pagefile still configured regardless of other-drive pagefiles.

### B2 — Hardware (Round 2)
- [ ] Debloat autostart removal — was the dedup correct?
- [ ] Driver path Write-Debug→Write-Warn — log level appropriate?
- [ ] -ErrorAction Stop additions — any behavioral changes?
- [ ] State.json field names still match Phase 3 after B6 changes?

### B3 — Registry Tweaks (Round 2)
- [ ] SmoothMouse 40-byte curves — values produce correct 1:1 mapping?
- [ ] All 30 Set-RegistryValue calls still match Verify-Settings after D1 changes?
- [ ] New EstimateKey wiring from A1 — estimate values reasonable?

### B4 — Game Config (Round 2)
- [ ] Autoexec parser comment/command skip — regex correct?
- [ ] Service existence check pattern — consistent with Step 37?
- [ ] Copy-Item -ErrorAction Stop — error message actionable?
- [ ] UserPreferencesMask + ClearType — byte values correct?
- [ ] Verify-Settings check for visual effects added in B4 — matches D1 parity?

### B5 — Safe Mode (Round 2)
- [ ] CIM driver enumeration — fallback to pnputil correct?
- [ ] bcdedit "already removed" detection — regex robust?
- [ ] RunOnce existence validation — error message actionable?
- [ ] $ErrorActionPreference addition — any side effects?

### B6 — Post-Reboot (Round 2)
- [ ] Fallback state new fields (baselineAvg, baselineP1, appliedSteps) — types correct?
- [ ] DRY-RUN→live mode derivation — matches Setup-Profile exactly?
- [ ] Install-NvidiaDriverClean exit code check — all codes handled?
- [ ] DisableDynamicPstate registry fallback fix — path correct?
- [ ] DNS all-adapter change — virtual adapter filtering?

---

## Phase C: Specialized Modules

### C1 — NVIDIA Stack (Round 2)
- [ ] FXAA value 0 — confirm against NVAPI enum
- [ ] SHIM_RENDERING_OPTIONS hex fix — verify bit layout
- [ ] $downloadUrl init — any other uninitialized vars in StrictMode?
- [ ] Doc fix propagation — nvidia-drs-settings.md consistent with code?

### C2 — Network & Hardware (Round 2)
- [ ] MSI -ErrorAction Stop — any operations that should remain SilentlyContinue?
- [ ] Benchmark history cap (200) — FIFO trim logic correct?
- [ ] PS 5.1 null guard — does it handle all ConvertFrom-Json edge cases?
- [ ] Debloat pre-fetch — still correct after B2 dedup changes?

---

## Phase D: Surface Layer

### D1 — Entry Points & Utilities (Round 2)
- [ ] 5 new Verify-Settings service checks — correct service names and states?
- [ ] Cleanup.ps1 -ErrorAction Stop — error messages actionable?
- [ ] Run-Optimize DRY-RUN restart guard — consistent with B5 pattern?
- [ ] FpsCap/Setup-Profile -ErrorAction Stop — any behavioral changes?

### D2 — GUI Layer (Round 2)
- [ ] 7 step-catalog fixes — verify against actual Invoke-TieredStep params
- [ ] gui-panels bare step-number removal — uses composite keys correctly?
- [ ] WPF closing flag + timer cleanup — no race conditions?
- [ ] 9 new system-analysis checks — paths match current code?
- [ ] START-GUI.bat -WindowStyle Hidden — works on all Windows versions?

---

## Phase E: Quality

### E1 — Pester Tests (Round 2)
- [ ] Run all tests — identify failures
- [ ] Test correctness audit (do tests test the RIGHT thing?)
- [ ] Mock completeness (any tests hitting real filesystem/registry?)
- [ ] Edge case coverage gaps
- [ ] Test isolation (no cross-test state leakage)

### E2 — Documentation (Round 2)
- [ ] Verify Round 1 doc fixes are accurate
- [ ] Any new code changes not yet reflected in docs?
- [ ] CHANGELOG audit entry — complete and accurate?

### E3 — CI/CD (Round 2)
- [ ] Pester job YAML validity
- [ ] EstimateKey cross-ref script correctness
- [ ] New PSScriptAnalyzer rules — any false positives?
- [ ] Security checks — false positive rate?
- [ ] Cache keys correct for module paths?

---

## Phase F: Final Review

### F1 — Integration & Ship Check (Round 2)
- [ ] Full PSScriptAnalyzer pass
- [ ] Full Pester test pass
- [ ] Verify-Settings bidirectional parity (definitive)
- [ ] DRY-RUN zero-leak confirmation
- [ ] git diff review — no accidental regressions
- [ ] Overall code quality assessment
