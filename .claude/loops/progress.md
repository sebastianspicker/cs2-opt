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
- [ ] R2 fixes: power plan double-fallback, autoexec regex expansion, UserPreferencesMask Compare-Object, NtfsDisableLastAccessUpdate int32 sign
- [ ] Autoexec command list completeness (any Source 2 commands beyond unbind/toggle/incrementvar/echo?)
- [ ] Binary comparison pattern — should it be a reusable function?
- [ ] Step 38 copy list completeness after all file additions

### B5-R3 — Safe Mode (kept separate — safety critical)
- [x] R2 bcdedit locale fix: bcdedit /enum parsing — robust on all Windows editions?
  - FIXED: `bcdedit /enum "{current}"` element names ARE localized (e.g., "safeboot" → "Abgesicherter Start" on German Windows). Switched to `bcdedit /enum "{current}" /v` which outputs raw BCD element ID `0x26000081` — never localized. Also added handling for bcdedit /enum itself failing (BCD corruption).
- [x] CIM→pnputil fallback: does pnputil parsing still work after CIM was added as primary?
  - FIXED: CIM `DeviceClass` was using localized class name ("DISPLAY" — only works on English Windows). Switched to `ClassGuid` matching against `$CFG_GUID_Display` ({4d36e968-...}) which is locale-independent. Fallback trigger and removal command verified correct for both paths.
- [x] Full crash scenario trace: power failure at each step → recovery path
  - Added comprehensive crash recovery documentation as header comment in SafeMode-DriverClean.ps1. Added catch block with user-visible recovery instructions for unhandled exceptions. Step ordering (bcdedit first) ensures Normal Mode boot even if later steps crash.

### B6-R3 — Post-Reboot (kept separate — complex state)
- [ ] R2 fixes: DNS virtual adapter filter (14 patterns), multi-adapter confirmation, PerfLevelSrc/DisableDynamicPstate Verify checks
- [ ] DNS adapter filter — any legitimate adapters falsely excluded?
- [ ] State.json field completeness after 99 commits of changes

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
- [ ] R2 fixes: Pester Exit=true, version bound, EstimateKey scope, security lookback, test bugs, CHANGELOG count
- [ ] Run full Pester suite mentally — any remaining failures?
- [ ] CI workflow dry-run (trace each job step-by-step)
- [ ] Doc accuracy final spot-check (5 random claims → verify in code)

## Phase F: Final

### F-R3 — Ship-Ready
- [ ] PSScriptAnalyzer zero violations
- [ ] 200+ tests validated
- [ ] Verify-Settings parity confirmed
- [ ] DRY-RUN zero leaks
- [ ] No TODO/FIXME/debug code
- [ ] Overall assessment: ship or iterate?
