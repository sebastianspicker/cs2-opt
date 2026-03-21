# Audit Progress Tracker

Central audit trail for the Ralph Loop system. Each loop records completed items and findings here.

## Phase A: Infrastructure

### A1 — Core Infrastructure
- [x] Set-RegistryValue / Set-BootConfig correctness — audited: param order correct, $null CurrentStepTitle guarded, nested key creation uses -Force, race condition is in safe direction (backup records old value before write attempt)
- [x] Save-JsonAtomic edge cases — FIXED: added parent directory creation; stale .tmp handled by overwrite; Move-Item failure handled by catch+cleanup; -Depth 10 sufficient (max nesting ~4 levels)
- [x] Invoke-TieredStep logic — FIXED: DRY-RUN Action now wrapped in try/catch (was leaking $CurrentStepTitle on exception); SAFE T2 auto-run logic correct; wouldSkip logic correct; EstimateKey tracking correct on throw
- [x] Load-State / Initialize-ScriptDefaults — FIXED: added -ErrorAction Stop to Get-Content; all 5 entry-points consistent (Run-Optimize inline, PostReboot/SafeMode use Load-State+try/catch, Cleanup/Verify/FpsCap use Initialize-ScriptDefaults); profile override on resume correct (Setup-Profile.ps1 fresh choice wins + persists to state.json)
- [x] Hardware detection robustness — FIXED: DDR5 XMP detection (ConfiguredClockSpeed = Speed/2 on DDR5, uses SMBIOSMemoryType to detect); FIXED: DriverVersion parse guards for short strings; FIXED: VDF UTF-8 encoding + escaped backslash handling; WiFi-only: correctly handled with advisory in Step 16
- [x] Config cross-check (EstimateKey parity) — FIXED: wired up HiberbootEnabled=0 (Step 23) and Win32PrioritySeparation (Step 27); documented 4 intentional orphan keys (FPS Cap, Clean Driver Install, Defender Exclusions merged into Visual Effects, DisablePagingExecutive/PowerThrottlingOff sub-actions of Step 27); $CFG_NIC_Tweaks uses DisplayName (vendor-dependent, handled by SilentlyContinue on Set-NetAdapterAdvancedProperty); $CFG_Autostart_Remove best-effort list
- [x] $ErrorActionPreference masking catalog — FIXED: 5 entry-points set SilentlyContinue; all critical JSON readers now use -ErrorAction Stop on Get-Content (Load-State, Initialize-ScriptDefaults, Load-Progress, Get-BackupData, Save/Load-AppliedSteps, Get-BenchmarkHistory); critical write functions (Set-RegistryValue, Save-JsonAtomic, Set-ItemProperty in restore) already used -ErrorAction Stop

### A2 — Backup/Restore & State
- [ ] Backup accumulation performance
- [ ] Restore type correctness
- [ ] DRS backup/restore integrity
- [ ] Step-state resume correctness
- [ ] Concurrent access safety
- [ ] Scheduled task backup

### A3 — DRY-RUN Correctness
- [ ] DRY-RUN leak audit (all write operations)
- [ ] State persistence in DRY-RUN
- [ ] Cross-phase inheritance
- [ ] Per-helper DRY-RUN audit
- [ ] Output completeness

---

## Phase B: Phase Scripts

### B1 — System Base (Steps 2-9)
- [ ] Step boundary correctness
- [ ] Step 3 shader cache
- [ ] Step 4 FSO
- [ ] Step 5 NVIDIA driver check
- [ ] Step 6 power plan
- [ ] Step 8 pagefile
- [ ] Step 9 ReBAR
- [ ] Error propagation

### B2 — Hardware (Steps 10-22)
- [ ] Step completeness audit
- [ ] Step 10 dynamic tick
- [ ] Step 13 debloat
- [ ] Step 15 WU blocker
- [ ] Step 16 NIC stack
- [ ] Step 17 benchmark
- [ ] Steps 18-22 prep steps

### B3 — Registry Tweaks (Steps 23-33)
- [ ] Registry path correctness
- [ ] Step 25 Nagle
- [ ] Step 27 MMCSS/scheduler
- [ ] Step 29 mouse
- [ ] Step 31 Game DVR
- [ ] Step 33 audio
- [ ] EstimateKey consistency
- [ ] Complete-Step/Skip-Step coverage

### B4 — Game Config (Steps 34-38)
- [ ] Step 34 autoexec merge
- [ ] Step 37 services
- [ ] Step 38 Safe Mode prep
- [ ] File operation error handling
- [ ] Step 35 chipset
- [ ] Step 36 visual effects

### B5 — Phase 2 Safe Mode
- [ ] Safe Mode boot validation
- [ ] bcdedit /deletevalue safeboot (CRITICAL)
- [ ] GPU driver clean removal
- [ ] RunOnce registration
- [ ] Skip path integrity
- [ ] Error recovery

### B6 — Phase 3 Post-Reboot
- [ ] State loading resilience
- [ ] DRY-RUN inheritance + switch
- [ ] Step 1 driver install
- [ ] Step 2 MSI interrupts
- [ ] Step 4 NVIDIA DRS
- [ ] Step 9 DNS
- [ ] Step 10 process priority
- [ ] Step 13 final benchmark
- [ ] Complete-Step/Skip-Step coverage

---

## Phase C: Specialized Modules

### C1 — NVIDIA Stack
- [ ] C# interop safety (GCHandle, structs)
- [ ] Driver version scraping
- [ ] Settings table correctness (52 IDs)
- [ ] Apply flow (profile lookup, backup order)
- [ ] DRY-RUN support
- [ ] Backup integration

### C2 — Network & Hardware
- [ ] MSI interrupts
- [ ] Power plan
- [ ] Process priority (X3D)
- [ ] Debloat
- [ ] Benchmark history

---

## Phase D: Surface Layer

### D1 — Entry Points & Utilities
- [ ] START.bat robustness
- [ ] Cleanup.ps1
- [ ] Verify-Settings parity (CRITICAL)
- [ ] FpsCap-Calculator
- [ ] Setup-Profile
- [ ] Run-Optimize

### D2 — GUI Layer
- [ ] WPF lifecycle
- [ ] Panel data accuracy
- [ ] Step-catalog metadata parity
- [ ] system-analysis read-only guarantee
- [ ] GUI-CLI parity
- [ ] START-GUI.bat

---

## Phase E: Quality

### E1 — Pester Tests
- [ ] _TestInit.ps1
- [ ] hardware-detect.Tests.ps1
- [ ] tier-system.Tests.ps1
- [ ] system-utils.Tests.ps1
- [ ] backup-restore.Tests.ps1
- [ ] step-state.Tests.ps1
- [ ] config.Tests.ps1

### E2 — Documentation Accuracy
- [ ] evidence.md
- [ ] nic-latency-stack.md
- [ ] windows-scheduler.md
- [ ] nvidia-optimization.md + nvidia-drs-settings.md
- [ ] power-plan.md
- [ ] services.md
- [ ] backup-restore.md
- [ ] README.md

### E3 — CI/CD Enhancement
- [ ] Pester test job
- [ ] EstimateKey cross-reference check
- [ ] PSScriptAnalyzer rules review
- [ ] Security workflow enhancements
- [ ] Stale SHA pin fix
- [ ] Concurrency and caching

---

## Phase F: Final Review

### F1 — Integration & Ship Check
- [ ] Cross-loop conflict resolution
- [ ] End-to-end flow trace
- [ ] $ErrorActionPreference resolution
- [ ] Regression check (PSScriptAnalyzer + Pester)
- [ ] Consistency final pass
- [ ] "Would I ship this?" test
- [ ] Verify-Settings bidirectional parity (final)
- [ ] Documentation coherence
