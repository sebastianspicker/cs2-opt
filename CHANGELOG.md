# Changelog

All notable changes to the CS2 Optimization Suite are recorded here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- `helpers/process-priority.ps1` — replaces Process Lasso (final external tool eliminated). IFEO PerfOptions for persistent High CPU priority; scheduled task for dual-CCD X3D affinity pinning (7900X3D/7950X3D/9900X3D/9950X3D)
- `helpers/power-plan.ps1` — replaces FPSHeaven `.pow` binary import with native `powercfg` calls. Fixed 4 bugs in the original plan (passive cooling, AMD PROCTHROTTLEMIN, duty cycling, PERFAUTONOMOUS)
- `helpers/nvidia-drs.ps1` + `helpers/nvidia-profile.ps1` — direct `nvapi64.dll` DRS write via C# `Add-Type`, replacing NVIDIA Profile Inspector dependency. 52 DWORD settings decoded and written to DRS binary database
- `helpers/benchmark-history.ps1` — iterative FPS tracking across sessions (`benchmark_history.json`)
- `CS2-Optimize-GUI.ps1` + `START-GUI.bat` — WPF dashboard with 7 panels: Dashboard, Analyze, Optimize, Backup, Benchmark, Video, Settings
- `helpers/hardware-detect.ps1` — `Get-IntelHybridCpuName` and `Get-SteamPath` shared helpers (eliminates duplicated registry reads across 7 files)
- Risk/consent system on all steps: `-Risk`, `-Depth`, `-Improvement`, `-SideEffects`, `-Undo` metadata on every `Invoke-TieredStep` call
- `Backup-ScheduledTask` type in backup system for X3D affinity task rollback
- Step 31: `GameDVR_Enabled = 0` (master DVR switch, previously missing)
- Step 33: `UserDuckingPreference = 3` (disable VoIP audio ducking)
- Step 27: FTH disable, Automatic Maintenance disable, NTFS metadata optimizations, `DisableCoInstallers`
- Step 16: URO disable (UDP Receive Offload, Windows 11 build ≥22000), IPv6 left enabled (2026 reversal — Steam/Valve SDR prefers IPv6), `*GreenEthernet`/`*PowerSavingMode` (Realtek-specific), QoS DSCP prerequisite NLA key
- Power plan: PCIe ASPM T1 setting added (prevents Windows software ASPM between frames)
- NVIDIA DRS: `DisableDynamicPstate = 1` in GPU class key, ULL CPL State fixed to `1 (On)`, shader cache 4096→10240 MB
- `docs/video.txt` — annotated copy-ready CS2 video.txt for 2026 competitive meta (three GPU tiers)
- `docs/audio.md`, `docs/process-priority.md`, `docs/backup-restore.md`, `docs/debloat.md` and 10 additional deep-dive documentation files
- `.github/workflows/security.yml` — secret scanning, PowerShell safety patterns, workflow integrity checks
- `.github/CODEOWNERS`, `.github/REPO_SETTINGS.md`, `.github/dependabot.yml`
- `SECURITY.md` with DRY-RUN system documentation and responsible disclosure

### Changed
- All 8 external tool dependencies eliminated — pure PowerShell with zero external binaries (except NVIDIA driver .exe download)
- Step 12 (Game Mode): reversed from Disable to Enable — WU suppression + MMCSS `Games` scheduling; IFEO supersedes any priority interference
- Step 16 (NIC): interrupt moderation set to Medium for ALL profiles (djdallmann empirical result — Disabled causes interrupt storms under background traffic)
- `mouclass queue size`: 16 → 50 (2025 testing showed values below 30 cause event skipping)
- `Win32PrioritySeparation`: `0x26` (variable) → `0x2A` (fixed) — 2025 Blur Busters: short fixed quantum improves 1% lows
- Step 34 autoexec: 56 CVars (8 categories) → 74 CVars (10 categories). Added HUD/QoL (7), Privacy (5), updated Gameplay (17). `cl_predict_body/head_shot_fx` set to `0` per 95% pro consensus (ThourCS2 120-player study)
- Network stack: TCP-only settings removed from scope; `netsh int tcp` commands documented as no-op for CS2's UDP traffic

### Fixed
- `Cleanup.ps1` line 161: undefined `$steamReg` crash on Steam Verification path (changed to `$steamBase`)
- 3× Intel hybrid CPU detection duplicated inline → `Get-IntelHybridCpuName` shared function
- 9× Steam path lookup duplicated inline → `Get-SteamPath` shared function
- Power plan: passive cooling bug (FPSHeaven shipped `SYSCOOLPOL=0`; corrected to Active)
- Power plan: AMD PROCTHROTTLEMIN bug (100% bypasses Precision Boost 2; corrected to 0% on AMD)
- NVIDIA DRS: `PerfLevelSrc=0x2222` registry key correctly placed in GPU class key `{4d36e968}` (not `d3d\` path which is a no-op on modern drivers)

### Removed
- All external tool downloads: NVCleanstall, NVIDIA Profile Inspector, FPSHeaven, Process Lasso, GoInterruptPolicy, and 3 others
- `FPSHEAVEN2026.pow` dependency (binary `.pow` import replaced by native `powercfg` calls)
- Debunked settings removed from autoexec: `-tickrate 128`, `-threads N`, `cl_cmdrate`, `net_graph 1`, `r_dynamic 0`, `mat_queue_mode 2`

### Audit (March 2026)
16-loop code audit (A1-A3, B1-B6, C1-C2, D1-D2, E1-E3, F1) covering infrastructure, phase scripts, specialized modules, GUI, tests, documentation, and CI/CD.

**Bug fixes:**
- Step 29: mouse acceleration curves were 20 bytes instead of required 40 bytes (INT64 per entry)
- Step 9 DNS: only fastest adapter was configured; now sets DNS on all active adapters
- Phase 3 DRY-RUN switch: mode derivation was hardcoded CONTROL instead of matching profile
- Phase 3 fallback state missing `baselineAvg`, `baselineP1`, `appliedSteps` fields
- GPU driver clean: CIM/WMI primary enumeration for non-English Windows (pnputil labels are locale-dependent)
- NVIDIA registry fallback missing `DisableDynamicPstate=1` in GPU class key
- Install-NvidiaDriverClean: unconditional `$true` return on non-zero exit codes
- Step 37 services: SysMain/WSearch did not check service existence before disable
- Step 38: silent failure on missing helpers/ directory during Safe Mode file copy
- Step 13 debloat: duplicate autostart cleanup overlapped with Step 14
- Phase 2 bcdedit: re-run caused false CRITICAL error when safeboot value already cleared
- Legacy bare step-number keys in progress.json caused P1:5/P3:5 collision on resume
- Pester test parse errors: `$key:` inside double-quoted strings parsed as scope qualifier

**Reliability improvements:**
- `-ErrorAction Stop` on all critical JSON readers (state.json, progress.json, backup.json)
- Missing `-SkipAction` on T1 steps 2, 3, 4, 6 (CUSTOM profile decline left progress unrecorded)
- Backup I/O batching: ~60 read/write cycles reduced to 38 (one flush per step)
- Advisory lockfile for concurrent backup.json access
- GUI: async timers stopped on window close to prevent post-dispose crashes
- Restart-Computer gated by DRY-RUN at Phase 1 completion

**New:**
- Pester 5.x test suite: 7 test files, 150+ test cases covering core helpers
- CI: Pester test job, EstimateKey cross-reference check, enhanced PSScriptAnalyzer rules
- CI: security workflow with Restart-Computer/Remove-Item gate checks
- Verify-Settings: added missing qWave + 4 Xbox service checks (was only SysMain + WSearch)
- GUI system-analysis: 9 additional checks for GUI-CLI parity

