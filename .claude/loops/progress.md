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

### B2 — Hardware (Round 2) — COMPLETE
- [x] Debloat autostart removal — was the dedup correct? — YES. Old debloat code and Step 14 both iterated `$CFG_Autostart_Remove` over same registry paths. No entries lost. FIXED: docs/debloat.md header still said "Step 13" only; updated to reference both Step 13 and Step 14.
- [x] Driver path Write-Debug→Write-Warn — log level appropriate? — YES. Write-Warn is correct: failure means Phase 3 will unnecessarily prompt for already-downloaded driver. Error details included via `$_`. Catch correctly swallows (download succeeded, only state tracking failed).
- [x] -ErrorAction Stop additions — any behavioral changes? — NO regressions. Both calls (lines 401, 461) are inside try/catch with appropriate Write-Warn handlers that swallow and continue. Before: silent null passed to ConvertFrom-Json causing corrupt state write. Now: catch fires cleanly. No other `Get-Content $CFG_StateFile` calls in this file are missing -ErrorAction Stop.
- [x] State.json field names still match Phase 3 after B6 changes? — YES. All 5 Phase-1-written fields read by Phase 3 match: `baselineAvg`/`baselineP1` (Step 17→line 608-609), `nvidiaDriverPath` (Step 19→line 92), `rollbackDriver` (Step 9→lines 129/132), `appliedSteps` (Save-AppliedSteps→Load-AppliedSteps). Fallback state on line 36 includes all required fields. `nvidiaDriverVersion` written but not read by Phase 3 (metadata only, not an issue).

### B3 — Registry Tweaks (Round 2) — COMPLETE
- [x] SmoothMouse 40-byte curves — values produce correct 1:1 mapping? — YES: 5 INT64 values (40 bytes) using standard Windows default XCurve thresholds (0, 0xA000, 0x14000, 0x28000, 0x50000). Y=X at all 5 points guarantees 1:1 regardless of spacing (linear interpolation between points: Y(s)=s). Registry type is Binary (correct). Verify-Settings does not check binary curves (acceptable: MouseSpeed/Threshold checks cover acceleration disable).
- [x] All 30+ Set-RegistryValue calls still match Verify-Settings after D1 changes? — FIXED: NtfsDisableLastAccessUpdate expected value was 0x80000001 (int64 2147483649), but DWORD reads back as int32 -2147483647 in PowerShell. Changed Verify-Settings.ps1 expected to (-2147483647) so -eq comparison succeeds. All other 32 registry checks verified: exact value/type match. GPU Preference and FSO compat flag are path-dependent (correctly skipped). SmoothMouse binary curves skipped (acceptable).
- [x] New EstimateKey wiring from A1 — estimate values reasonable? — YES: HiberbootEnabled=0 has P1Low 0/0, Avg 0/0, Confidence HIGH (correct: no FPS impact, enables MSI persistence). Win32PrioritySeparation has P1Low 1/4, Avg 0/1, Confidence HIGH (reasonable: cites 2025 Blur Busters + Overclock.net benchmarks showing fixed quantum improves 1% lows vs variable).

### B4 — Game Config (Round 2) — COMPLETE
- [x] Autoexec parser comment/command skip — FIXED: expanded command skip regex from (exec|bind|alias) to include unbind, toggle, incrementvar, echo, host_writeconfig, clear, say, say_team. Comment regex (// and blank lines) correct for CS2 Source 2 format (#-style comments not used in CS2 cfg). Inline comment stripping safe (no CS2 CVar values contain //). Three-way merge logic unaffected (operates on $existingKeys dict populated by parser).
- [x] Service existence check pattern — consistent with Step 37: all 7 services (SysMain, WSearch, qWave, 4 Xbox via $CFG_XboxServices) pre-checked with Get-Service -ErrorAction SilentlyContinue before Set-Service -ErrorAction Stop. Catch messages include service name + $_ error detail. Debloat.ps1 uses different pattern (no pre-check, relies on try/catch) but Backup-ServiceState handles non-existent services gracefully. Double-disable is harmless (Set-Service to already-Disabled is a no-op).
- [x] Copy-Item -ErrorAction Stop — correct behavior: core scripts abort with actionable "Missing: $f" message + throw. Helpers dir abort also correct (Phase 2/3 would fail without them). Guide-VideoSettings.ps1 included in copy list. Wildcard copy gets all 18 helper modules.
- [x] UserPreferencesMask + ClearType — byte values correct: 0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00 is standard "Best Performance" with byte 2 = 0x03 (bit 0 = font smoothing, bit 1 = ClearType). FontSmoothing="2" is ClearType at GDI level. No FontSmoothingType needed on Win10+.
- [x] Verify-Settings visual effects — FIXED: added UserPreferencesMask 8-byte binary comparison using Compare-Object (Test-RegistryCheck -eq is reference equality for byte[]). Also fixed NtfsDisableLastAccessUpdate: 0x80000001 literal is [int64] but registry DWORD reads as [int32]-2147483647, causing false CHANGED. FontSmoothing and VisualFXSetting checks were already present and correct.

### B5 — Safe Mode (Round 2) — COMPLETE
- [x] CIM driver enumeration — VERIFIED: `DeviceClass -eq "DISPLAY"` is correct (`-eq` is case-insensitive in PS, so "Display"/"DISPLAY"/"display" all match). `InfName` returns `oem*.inf` published name matching pnputil expectation. CIM available in Safe Mode (winmgmt is in SafeBoot\Minimal service list; CIMWin32 provider always present). `-ErrorAction Stop` + try/catch ensures clean pnputil fallback. `$vendorMatch` regex patterns ("nvidia", "amd|ati|radeon", "intel") correct with case-insensitive `-match`. FIXED: docstring said "pnputil with CIM fallback" but code does CIM-first — corrected to "CIM primary, pnputil fallback".
- [x] bcdedit "already removed" detection — FIXED: replaced English-only string match (`"not found|not valid|element not found"`) with locale-independent BCD state verification. Now runs `bcdedit /enum "{current}"` and checks if `safeboot` element still appears (element name is internal BCD identifier, never localized). Output joined via `Out-String` with multiline regex `(?m)^\s*safeboot\s` for reliable matching. Handles: non-English Windows, re-run after previous clear, normal-mode execution.
- [x] RunOnce existence validation — VERIFIED: `Set-RunOnce` checks `Test-Path $scriptPath` where `$scriptPath = "$CFG_WorkDir\PostReboot-Setup.ps1"`. Phase 1 Step 38 copies this file in `Optimize-GameConfig.ps1` (line 574-578) BEFORE Phase 2 runs (system reboots between phases). Error message is actionable: "Re-run Phase 1 Step 38 or launch manually." `-ErrorAction Stop` on `Set-ItemProperty` propagates registry write failures; catch block provides fallback: "Run manually: $scriptPath".
- [x] $ErrorActionPreference addition — VERIFIED: `SilentlyContinue` set on line 4, BEFORE bcdedit on line 51. No side effects: (1) bcdedit is a native command — unaffected by PS ErrorActionPreference; errors detected via `$LASTEXITCODE`. (2) `Get-CimInstance -ErrorAction Stop` explicitly overrides. (3) `Set-ItemProperty -ErrorAction Stop` explicitly overrides. (4) `pnputil` is native, unaffected. All 7 entry points now have it (Run-Optimize, PostReboot-Setup, SafeMode-DriverClean, Cleanup, FpsCap-Calculator, Verify-Settings + the GUI bat). No operations that should fail loudly are suppressed — all critical paths use explicit `-ErrorAction Stop`.

### B6 — Post-Reboot (Round 2) — COMPLETE
- [x] Fallback state new fields (baselineAvg, baselineP1, appliedSteps) — types correct? — YES. `$null` round-trips through JSON correctly. `@()` serializes as `[]`, deserializes as empty `Object[]`; `if ($st.appliedSteps)` is falsy for empty array (correct: skips loop body, no steps to load). `@()` wrap in Load-AppliedSteps handles PS 5.1 single-element scalar unwrap. `if ($state.baselineAvg)` with `$null` or `0` both evaluate to `$false`, fallback to `0` correct — `Show-ImprovementEstimate` guards with `$BaselineP1 -gt 0` before division. No missing `$state.` fields: all 5 Phase-1-written fields (`baselineAvg`, `baselineP1`, `nvidiaDriverPath`, `rollbackDriver`, `appliedSteps`) present in fallback. `$SCRIPT:fpsCap` set from `$state.fpsCap` at line 40.
- [x] DRY-RUN→live mode derivation — matches Setup-Profile exactly? — YES. PostReboot lines 57-61 mapping (SAFE→AUTO, RECOMMENDED→AUTO, COMPETITIVE→CONTROL, CUSTOM→INFORMED) identical to Setup-Profile lines 86-91. PostReboot adds `default { "CONTROL" }` for null/empty `$SCRIPT:Profile` — defensive addition, never reached in normal flow. If `$SCRIPT:Profile` is null at the switch, the `default` branch provides safe fallback instead of leaving `$SCRIPT:Mode` as `$null`.
- [x] Install-NvidiaDriverClean exit code check — all codes handled? — YES. Exit code 0 = success, 1 = reboot required (treated as success with advisory message), all other codes = `$installSuccess = $false`. Post-install tweaks correctly gated by `if ($installSuccess)`. `.exe` validation uses `-notmatch '\.exe$'` which is case-insensitive by default in PowerShell (matches .EXE, .Exe, etc.). NVIDIA setup.exe exit codes: 0=success, 1=reboot needed, 2=error — all covered. Extraction also validates setup.exe existence before install attempt.
- [x] DisableDynamicPstate registry fallback fix — path correct? — YES. Path is `$nvKeyPath` dynamically resolved from `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-...}\XXXX` by matching ProviderName/DriverDesc containing "NVIDIA". Written as DWord=1 in BOTH DRS success path (line 192) and registry fallback (line 356). FIXED: Verify-Settings.ps1 was missing checks for both `PerfLevelSrc` (0x2222) and `DisableDynamicPstate` (1) — added with same NVIDIA GPU detection logic, graceful skip on non-NVIDIA.
- [x] DNS all-adapter change — virtual adapter filtering? — FIXED 2 issues: (1) Filter was too narrow (`Loopback|Virtual|Hyper-V|Bluetooth`), missing VPN (TAP-Windows, WireGuard, Tailscale, OpenVPN, Cisco AnyConnect, Juniper, Fortinet), Docker (vEthernet), and generic VPN adapters. Expanded regex. (2) User was not warned about multi-adapter changes. Added: adapter names displayed before change; multi-adapter confirmation prompt with escape hatch. DNS not added to Verify-Settings (volatile: DHCP renewals reset DNS, would cause persistent false CHANGED reports).

---

## Phase C: Specialized Modules

### C1 — NVIDIA Stack (Round 2) — COMPLETE
- [x] FXAA value 0 — CONFIRMED: `FXAA_ENABLE_OFF = 0` per NVAPI enum. Code has `Id=276089202; Value=0`. Doc matches at line 46. Second gate `Id=271895433; Value=0` also correct.
- [x] SHIM_RENDERING_OPTIONS hex fix — VERIFIED: `469762050` = `0x1C000002`. Bits 1, 26, 27, 28 set. Bit 1 = SHIM_RENDERING_DISABLE_THREADING. Bit 14 (DISABLE_CUDA) NOT set. Doc and code consistent.
- [x] $downloadUrl init — VERIFIED: No other uninitialized vars found in nvidia-driver.ps1, nvidia-profile.ps1, or nvidia-drs.ps1. All `$SCRIPT:` vars either guarded by null checks (`-eq $true`/`-eq $false`) or set before use. C# code enforces definite assignment at compile time. `$SCRIPT:NvApiAvailable` starts `$null` but `-eq $true` / `-eq $false` both return `$false` for `$null` — correct tri-state caching.
- [x] Doc fix propagation — FIXED 3 issues: (1) OpenGL GPU Affinity hex annotation wrong in both code comment and doc: `550564838` = `0x20D0F3E6`, was incorrectly `0x20D3A2E6`. (2) Header comment and docstring said "~24" registry fallback settings, actual count is 25. (3) All 52 DRS setting IDs and values verified matching between `nvidia-profile.ps1` and `nvidia-drs-settings.md`. Registry fallback breakdown (22 d3d + 1 NVTweak + 2 GPU class = 25) matches `nvidia-optimization.md`. Bloat count (15) matches. Decoded flags count (16 = 6+8+2) matches.

### C2 — Network & Hardware (Round 2) — COMPLETE
- [x] MSI -ErrorAction Stop — VERIFIED: registry paths always created via New-Item -Force before Set-ItemProperty; try/catch provides device-specific error messages; no operations should remain SilentlyContinue
- [x] Benchmark history cap (200) — VERIFIED: FIFO trim removes oldest (index 0 excluded via array slice from tail), applied after adding new entry, boundary case (200→201→200) correct, saved atomically via Save-JsonAtomic, cap defined in benchmark-history.ps1 line 6
- [x] PS 5.1 null guard — FIXED: changed `-not $data` to `$null -eq $data` to avoid false positives on valid falsy values (0, ""); single-element array and PSCustomObject cases already handled by `-is [array]` + `@()` wrapper
- [x] Debloat pre-fetch — VERIFIED: no autostart code in debloat.ps1 (comment on line 122 confirms Step 14 handles it), pre-fetch optimization intact (line 37), telemetry service backups in place (line 75), 18 AppX packages match docs exactly; FIXED stale autostart references in docs/debloat.md

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
