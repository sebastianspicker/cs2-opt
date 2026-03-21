# Audit Progress Tracker — Round 2

Second pass after Round 1 fixed ~51 bugs, added ~170 tests, and corrected 8 doc files. This round focuses on: regressions from Round 1 fixes, deeper edge cases, new code quality, test correctness, and integration between fixes.

## Phase A: Infrastructure

### A1 — Core Infrastructure (Round 2) — COMPLETE
- [x] Validate Round 1 fixes (Save-JsonAtomic dir creation, DDR5 XMP, VDF parsing) — all correct
- [x] Flush-BackupBuffer integration in Invoke-TieredStep — FIXED: added defensive flush to DRY-RUN path
- [x] New -ErrorAction Stop additions — do they change control flow? — all callers have appropriate try/catch
- [x] EstimateKey wiring (Steps 23/27) — values correct? — both keys exist, values reasonable
- [x] Config cross-check round 2 (any new orphans from B-loop changes?) — 5 orphaned config entries are intentional (GUI catalog / merged step sub-components)

### A2 — Backup/Restore & State (Round 2)
- [ ] Backup buffering correctness (Flush-BackupBuffer timing, edge cases)
- [ ] Lockfile system (stale PID detection, cross-process race)
- [ ] Binary restore [0,255] validation + MultiString cast
- [ ] Legacy step-key removal — any callers still using bare numbers?
- [ ] wasEnabled scheduled task field — all consumers updated?

### A3 — DRY-RUN Correctness (Round 2)
- [ ] Verify Round 1 DRY-RUN guards (shader cache, bcdedit, Restart-Computer, Invoke-Download)
- [ ] New code from other loops — any new DRY-RUN leaks introduced?
- [ ] DRY-RUN output message consistency after all changes
- [ ] State persistence correctness after all fixes

---

## Phase B: Phase Scripts

### B1 — System Base (Round 2)
- [ ] New Skip-Step additions (Steps 2,3,4,6) — correct params?
- [ ] Shader cache lock detection — false positives?
- [ ] FSO Get-CS2InstallPath integration — handles all Steam library formats?
- [ ] Power plan HP→Balanced fallback — correct GUID?
- [ ] Pagefile non-C: warning — actionable message?

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
