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
- [x] Backup accumulation performance — FIXED: all 6 Backup-* functions now buffer entries in $SCRIPT:_backupPending (List<object>), flushed once per step via Flush-BackupBuffer in Invoke-TieredStep. Reduces ~60+ read/parse/write cycles to ~38 (one per step). Get-BackupData flushes before reading for consistency.
- [x] Restore type correctness — FIXED: binary byte[] validation (reject values outside [0,255] instead of silent truncation); MultiString explicit [string[]] cast; registry path existence guards (create missing parent on restore, skip remove if path gone); DRS restore casts through [double]->[uint32] for JSON round-trip safety; improved nvapi64.dll-missing error message
- [x] DRS backup/restore integrity — FIXED: uint32 setting IDs/values stored as [double] in Backup-DrsSettings (ConvertTo-Json loses uint32 type; double has 53-bit mantissa, lossless for 32-bit values). Sentinel profile "(found via cs2.exe)" path traced: correctly skips FindProfileByName and falls through to FindApplicationProfile. profileCreated+sentinel can never co-occur (verified in Apply-NvidiaCS2ProfileDrs).
- [x] Step-state resume correctness — FIXED: removed legacy bare step-number fallback from Test-StepDone; bare "5" matched across phases (P1:5 vs P3:5 collision). Now only composite keys checked. lastCompletedStep=0 with entries: returns step 1 (safe, idempotent re-run). Clear-Progress stale data: not a bug — Complete-Step always calls Load-Progress (reads cleared file).
- [x] Concurrent access safety — FIXED: added advisory lockfile (backup.lock) with PID-based stale detection. Initialize-Backup acquires lock; Restore-Interactive checks lock before proceeding. Save-JsonAtomic still protects against corruption. Batch buffer introduces small crash window (entries in memory between write and flush) — acceptable tradeoff vs 60+ I/O cycles; all changes also covered by System Restore Point.
- [x] Scheduled task backup — FIXED: Backup-ScheduledTask now records wasEnabled state (was the task enabled before we disabled it). Restore-Interactive uses wasEnabled to restore exact state instead of blindly re-enabling. Handles missing tasks (removed by Windows Update) with warning. Trigger settings not preserved (design limitation: debloat only disables, process-priority creates new task with existed=false so restore unregisters it).

### A3 — DRY-RUN Correctness
- [x] DRY-RUN leak audit (all write operations) — FIXED: shader cache Remove-Item in Optimize-SystemBase.ps1 Step 3, bcdedit /deletevalue safeboot in SafeMode-DriverClean.ps1, Clear-Dir/ipconfig/wevtutil/prefetch/RAM-trim/Steam-validate in Cleanup.ps1, Invoke-Download ~600MB NVIDIA driver in Optimize-Hardware.ps1 Step 19 and PostReboot-Setup.ps1 Step 1. All now gated with descriptive [DRY-RUN] messages. Confirmed: debloat, MSI, power-plan, NIC tweaks, QoS policies, services, NVIDIA install/profile all properly gated.
- [x] State persistence in DRY-RUN — INTENTIONAL: state.json written in DRY-RUN for mode propagation across phases (Setup-Profile.ps1). progress.json properly guarded (Complete-Step/Skip-Step return early). backup.json entries properly guarded (Set-RegistryValue/Set-BootConfig only backup when not DRY-RUN). Directory creation intentional for infrastructure.
- [x] Cross-phase inheritance — CORRECT: Phase 1 saves mode="DRY-RUN" to state.json. Phase 2 loads via Load-State, now properly guards bcdedit /deletevalue safeboot + Restart-Computer. Phase 3 loads state, shows DRY-RUN banner, offers switch; persists mode change. Phase 1 Step 38 Set-BootConfig "safeboot" intercepted so DRY-RUN never actually reaches Safe Mode.
- [x] Per-helper DRY-RUN audit — ALL PASS: msi-interrupts.ps1 (Set-ItemProperty/New-Item inside DryRun guards), gpu-driver-clean.ps1 (early return line 24-32), process-priority.ps1 (IFEO via Set-RegistryValue, task via early return line 165-168), power-plan.ps1 (Set-PowerPlanValue wrapper + New-CS2PowerPlan early return), debloat.ps1 (all 5 operation types gated), nvidia-driver.ps1 (early return line 127-133 + post-install services gated), nvidia-profile.ps1 (DRS writes gated line 304-306)
- [x] Output completeness — ALL DRY-RUN interceptions include descriptive [DRY-RUN] prefix messages in Magenta/DarkMagenta. Invoke-TieredStep shows title+depth+improvement. Set-RegistryValue shows name+value+type+path. Set-BootConfig shows key+val. No silent skips found. Complete-Step/Skip-Step use Write-Debug (intentional for internal tracking).

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
