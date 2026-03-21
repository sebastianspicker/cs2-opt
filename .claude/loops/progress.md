# Audit Progress Tracker — Round 3

Third pass after R1 (~51 fixes) + R2 (~47 fixes) = ~98 total. Consolidated from 17→8 loops. Focus: R2 fix validation, subtle integration bugs, UX polish, final hardening.

## Phase A: Infrastructure (consolidated)

### A-R3 — Full Infrastructure
- [x] R2 fixes: lock release (3 entry points), PID+ProcessName check, MultiString scalar coerce, Flush-BackupBuffer DRY-RUN path
- [x] Lock lifecycle end-to-end (acquire→run→release→crash recovery)
- [x] Backup buffer under error conditions (action throws mid-step with pending entries)
- [x] -ErrorAction Stop cascade audit (any function returning $null that callers depend on?)

## Phase B: Phase Scripts

### B-Scripts-R3 — Phase 1 Steps (consolidated B1-B4)
- [x] R2 fixes: power plan double-fallback, autoexec regex expansion, UserPreferencesMask Compare-Object, NtfsDisableLastAccessUpdate int32 sign
  - Power plan double-fallback: error message is actionable ("Manually set power plan: Control Panel -> Power Options"). PASS.
  - Autoexec regex: expanded from 11 to 16 commands — added setinfo, bindtoggle, unbindall, +/- prefix. Reordered longer keywords before shorter for correct \b matching.
  - UserPreferencesMask Compare-Object: correctly uses -SyncWindow 0, handles null/missing/match/mismatch cases. PASS.
  - NtfsDisableLastAccessUpdate: (-2147483647) correctly matches int32 read-back of DWORD 0x80000001. PASS.
- [x] Autoexec command list completeness (any Source 2 commands beyond unbind/toggle/incrementvar/echo?)
  - Added: setinfo (user info strings), bindtoggle (bind+toggle combo), unbindall (reset bindings), +/- prefix (hold/release actions like +jump)
  - con_logfile is a CVar (key=value format), correctly parsed by CVar pattern — no skip needed
  - Unrecognized commands without values fall through both checks harmlessly (not added to existingKeys)
- [x] Binary comparison pattern — should it be a reusable function?
  - Decision: keep inline. Only 1 binary check in Verify-Settings (UserPreferencesMask). SmoothMouse curves are not verified (B3 decision). Added comment noting to extract to helper if more binary checks are added.
- [x] Step 38 copy list completeness after all file additions
  - 5 core files copied: SafeMode-DriverClean.ps1, PostReboot-Setup.ps1, Guide-VideoSettings.ps1, helpers.ps1, config.env.ps1
  - helpers/ directory copied recursively (18 modules — includes GUI-only modules which are harmless extras)
  - Phase 2 dot-sources: config.env.ps1 + helpers.ps1. Phase 3 dot-sources: config.env.ps1 + helpers.ps1 + Guide-VideoSettings.ps1. All covered.
  - cs2_affinity.ps1 is generated at runtime by process-priority.ps1, not a file to copy. No test files in helpers/.
  - RunOnce chain: Step 38 sets Phase 2, Phase 2 Step 3 sets Phase 3. Both reference $CFG_WorkDir paths. PASS.

### B5-R3 — Safe Mode (kept separate — safety critical)
- [x] R2 bcdedit locale fix: bcdedit /enum parsing — robust on all Windows editions?
  - FIXED: `bcdedit /enum "{current}"` element names ARE localized (e.g., "safeboot" → "Abgesicherter Start" on German Windows). Switched to `bcdedit /enum "{current}" /v` which outputs raw BCD element ID `0x26000081` — never localized. Also added handling for bcdedit /enum itself failing (BCD corruption).
- [x] CIM→pnputil fallback: does pnputil parsing still work after CIM was added as primary?
  - FIXED: CIM `DeviceClass` was using localized class name ("DISPLAY" — only works on English Windows). Switched to `ClassGuid` matching against `$CFG_GUID_Display` ({4d36e968-...}) which is locale-independent. Fallback trigger and removal command verified correct for both paths.
- [x] Full crash scenario trace: power failure at each step → recovery path
  - Added comprehensive crash recovery documentation as header comment in SafeMode-DriverClean.ps1. Added catch block with user-visible recovery instructions for unhandled exceptions. Step ordering (bcdedit first) ensures Normal Mode boot even if later steps crash.

### B6-R3 — Post-Reboot (kept separate — complex state)
- [x] DNS virtual adapter filter accuracy (14→16 patterns)
  - FIXED: Removed bare "VPN" pattern — too broad, could false-match "Killer VPN-capable" NICs
  - Added: Mullvad, NordLynx, ProtonVPN, SoftEther, GlobalProtect, Pulse Secure (6 VPN products)
  - vEthernet filter is correct for DNS — WSL2 inherits host DNS; Hyper-V vSwitch DNS is managed separately
  - Added per-adapter selection (A/S/N menu) when multiple adapters detected instead of all-or-nothing
  - Added single-adapter confirmation prompt (previously applied without asking)
- [x] State.json field completeness verified
  - 11 fields read from $state in PostReboot-Setup.ps1: fpsCap, avgFps, gpuInput, nvidiaDriverPath, rollbackDriver, baselineAvg, baselineP1, appliedSteps, mode, logLevel, profile
  - All either written by Setup-Profile.ps1 (initial), Optimize-Hardware.ps1 (baseline/driver), Optimize-SystemBase.ps1 (rollback), or tier-system.ps1 (appliedSteps)
  - Missing fields return $null via PSCustomObject property access — all usage guards with truthiness checks or -gt 0
  - FIXED: Fallback fpsCap/avgFps changed from $null to 0 to match Setup-Profile.ps1 type (always int)
  - appliedSteps: always array when present, $null when missing → Load-AppliedSteps guards with `if ($st.appliedSteps)` (empty array is falsy in PS)
- [x] PerfLevelSrc/DisableDynamicPstate Verify checks validated
  - GPU class key resolution in Verify-Settings.ps1 matches nvidia-profile.ps1 exactly: same $CFG_GUID_Display base, same ^\d{4}$ filter, same ProviderName/DriverDesc NVIDIA detection
  - AMD/Intel skip: $_nvKeyPath stays $null → else branch prints INFO + increments OK counter
  - 0x2222 comparison: PS evaluates hex at parse time → int32 8738; registry DWORD also int32 → -eq works correctly
  - DisableDynamicPstate=1: straightforward DWord comparison, path and value correct

## Phase C+D: Modules + Surface (consolidated)

### CD-R3 — Helpers, Entry Points, GUI
- [x] R2 fixes: GPU Affinity hex, MSI ErrorAction, benchmark cap, null guard, step-catalog P1:9, START-GUI elevation
  - GPU Affinity: 0x20D0F3E6 = 550564838 decimal — verified correct
  - MSI ErrorAction Stop: all 4 calls in msi-interrupts.ps1 preceded by Test-Path + New-Item -Force — verified
  - Benchmark cap: FIFO trim `[$excess..($count-1)]` keeps newest 200 — verified correct
  - PS 5.1 null guard: `$null -eq $data` in Get-BenchmarkHistory line 58 — verified correct
  - Step-catalog P1:9: Tier=2 Risk=SAFE Depth=CHECK matches both Invoke-TieredStep calls — verified
  - START-GUI: `-WindowStyle Hidden` on outer powershell call (line 7) — correct position
- [x] Verify-Settings definitive count (after B6-R2 added 2 checks)
  - 40 Test-RegistryCheck calls
  - 3 custom checks (HAGS info, UserPreferencesMask binary, IPv6 info)
  - 2 bcdedit checks (Dynamic Tick, Platform Tick)
  - 7 Test-ServiceCheck (SysMain, WSearch, qWave, 4x Xbox)
  - TOTAL: 52 guaranteed checks + conditional: NVIDIA (+2), Intel hybrid (+1), NIC found (+2→replace missing count)
  - Matches "52+ per F1-R2" target
- [x] GUI step-catalog — ALL entries match phase scripts (full re-scan)
  - 51 catalog entries verified against actual Invoke-TieredStep calls
  - P1:5 (NVIDIA Driver Version): catalog says SAFE/CHECK/CheckOnly=true, actual conditional Invoke-TieredStep says AGGRESSIVE/DRIVER — by design: step is fundamentally a version check; rollback action is conditional; catalog represents GUI user-facing behavior
  - P1:18/20/21/22 and P3:1/5/6/11/12/13: no Invoke-TieredStep (direct Complete-Step) — catalog N/A entries, no mismatch
  - All other entries: Tier/Risk/Depth/CheckOnly match exactly
  - No fixes needed
- [x] system-analysis read-only guarantee (re-confirm after D2-R2 additions)
  - Grepped for Set-, New-Item, Remove-, bcdedit /set, powercfg /, netsh set: ZERO matches
  - Only netsh call is `netsh int udp show global` (read-only query)
  - Confirmed: system-analysis.ps1 is purely read-only

## Phase E: Quality (consolidated)

### E-R3 — Tests + Docs + CI
- [x] R2 CI fixes validation (Item 1)
  - **Pester Exit=true**: `$cfg.Run.Exit = $true` at lint.yml:102, before `Invoke-Pester` at line 107. `$cfg` constructed via `New-PesterConfiguration` (line 100). PASS.
  - **Pester version bound**: `-MaximumVersion 5.99.99` is valid `Install-Module` syntax (line 94). Prevents Pester 6.x breaking changes. PASS.
  - **EstimateKey scope**: block-scoped parser (lint.yml:159-173) starts at `CFG_ImprovementEstimates`, stops at `^\s*\}`. Inner `@{...}` values are single-line, so no false stop. Commented keys (line 235 in config) start with `#` after whitespace — `^\s+"` regex correctly skips them. PASS.
  - **Security 50-line lookback**: 4 Restart-Computer -Force locations checked:
    - Cleanup.ps1:267 — DryRun guard at line 221 (46 lines). PASS.
    - PostReboot-Setup.ps1:681 — DryRun guard at line 678 (3 lines) + Read-Host at 676. PASS.
    - Run-Optimize.ps1:85 — DryRun guard at line 82 (3 lines) + Confirm-Risk at 81. PASS.
    - SafeMode-DriverClean.ps1:183 — DryRun guard at line 179 (4 lines) + Read-Host at 182. PASS.
- [x] Pester suite final check (Item 2)
  - **3 R2 bug fixes verified**:
    - Initialize-Backup assertion: tests `entries` property exists + count >= 0. Matches code output `@{ entries = @(); created = ... }`. PASS.
    - Get-SteamPath mock: `-ParameterFilter { $Path -like "*Valve\Steam*" }` matches actual `HKCU:\SOFTWARE\Valve\Steam`. PASS.
    - Config path regex: `[^:]/"` correctly flags forward slashes in Windows paths while ignoring drive-letter colons. PASS.
  - **7 new tests verified**:
    - Binary restore (3 tests): [0,255,300] triggers >255 guard; [10,-1,128] triggers <0 guard; [0,128,255] passes and casts to [byte[]]. All match code lines 450-459. PASS.
    - Flush retry (1 test): Mocks Save-JsonAtomic to throw; buffer retains entries because Clear() is after Save-BackupData call. PASS.
    - wasEnabled (4 tests): wasEnabled=true -> Enable; wasEnabled=false -> Disable; wasEnabled=null -> defaults to true; existed=false -> Unregister. All match code lines 544-578. PASS.
  - **Exact test count: 203** (config:28, system-utils:29, hardware-detect:39, step-state:24, backup-restore:35, tier-system:48)
  - No test relies on real registry, services, or external tools. All mocked. Would pass on clean Windows + Pester 5.x.
- [x] CI workflow dry-run (Item 3)
  - **psscriptanalyzer**: checkout → cache check (key: `psscriptanalyzer-1-Windows`) → install if missing → run with settings file → throw on violations. Cache staleness: module stays at first-installed version; bump key `-1-` to `-2-` to force update. Acceptable since PSScriptAnalyzer is backward-compatible.
  - **syntax-check**: checkout → parse all .ps1 via `[Parser]::ParseFile` → count errors → throw on >0. No dependencies beyond PowerShell. PASS.
  - **pester**: checkout → cache check (key: `pester5-1-Windows`) → install Pester 5.x if missing (bounded 5.0–5.99.99) → configure with Exit=true → run → upload NUnit XML. Cache staleness: same approach as psscriptanalyzer. `$cfg.Run.Exit = $true` ensures non-zero exit on failures. PASS.
  - **estimate-keys**: checkout (ubuntu-latest) → grep `-EstimateKey` from 5 phase scripts → grep keys from `CFG_ImprovementEstimates` block → cross-reference → fail on missing. Runs on Linux (no PS needed — pure bash). PASS.
  - **security.yml**: 3 jobs (secret-scan, script-safety, workflow-integrity). All bash on ubuntu-latest. Shell scripts syntactically valid (YAML validates). LINENO_HIT variable doesn't conflict with LINENO builtin. PASS.
- [x] Doc accuracy spot-check (Item 4)
  - **evidence.md Step 16 InterruptModeration**: table says "NIC Tweaks | 0–3 | 0". Config has `P1LowMin=0; P1LowMax=3; AvgMin=0; AvgMax=0`. MATCH.
  - **power-plan.md PROCTHROTTLEMIN AMD=0**: doc says "0% (AMD only)". Code line 215: `$minState = if ($isAMD) { 0 } else { 100 }`. MATCH.
  - **nvidia-drs-settings.md ShaderCache 10240**: doc says "10240 MB (10 GB)". Code: `@{ Id=11306135; Value=10240; Name="Shader disk cache max: 10240 MB (10 GB)" }`. MATCH.
  - **README "18 helper modules"**: README file tree lists 18 files in helpers/. Glob confirms 18 .ps1 files. helpers.ps1 loads 15, GUI loads 3 separately. MATCH.
  - **backup-restore.md 6 backup types**: Doc lists registry, service, bootconfig, powerplan, drs, scheduledtask. Code has all 6 `type = "..."` assignments. MATCH.
  - FIXED: helpers.ps1 GUI-only comment was missing gui-panels.ps1 (listed 2 of 3 GUI modules). Added.

## Phase F: Final

### F-R3 — Ship-Ready
- [ ] PSScriptAnalyzer zero violations
- [ ] 200+ tests validated
- [ ] Verify-Settings parity confirmed
- [ ] DRY-RUN zero leaks
- [ ] No TODO/FIXME/debug code
- [ ] Overall assessment: ship or iterate?
