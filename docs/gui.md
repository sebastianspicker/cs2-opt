# GUI Dashboard Guide

> `START-GUI.bat` → Run as Administrator

The GUI dashboard is a non-destructive management layer for the optimization suite. It does not replace the terminal phases — Phase 1, 2, and 3 still run in a terminal window. The dashboard handles everything else: analyzing your current system state, reviewing what has been changed, tracking benchmark results over time, and configuring CS2 video settings.

---

## Launching

```
Right-click START-GUI.bat → Run as administrator
```

If you are not an administrator, the launcher automatically re-elevates via `Start-Process -Verb RunAs`. The dashboard requires admin rights because it reads hardware configuration registers, registry keys under `HKLM`, and system service states.

---

## Panel Overview

### Dashboard

The first screen after launch. Shows the current state of your system at a glance.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   DASHBOARD                                              │
│  ● Dashboard      │                                                          │
│                   │  Hardware                              Phase Progress    │
│  ○ Analyze        │  ┌────────────────┐ ┌──────────────┐                    │
│  ○ Optimize       │  │ CPU            │ │ GPU          │  Phase 1  ▓▓▓▓▓▓▓▓ │
│  ○ Backup         │  │ Ryzen 7950X3D  │ │ RTX 4090     │  Phase 2  ▓▓▓▓▓▓▓▓ │
│  ○ Benchmark      │  │ 16C / 32T      │ │ 24 GB VRAM   │  Phase 3  ▓▓▓▓░░░░ │
│  ○ Video          │  └────────────────┘ └──────────────┘                    │
│  ○ Settings       │  ┌────────────────┐ ┌──────────────┐  Benchmark         │
│                   │  │ RAM            │ │ OS           │  Avg FPS   387      │
│                   │  │ 64 GB DDR5     │ │ Win 11 24H2  │  P1 FPS    312      │
│                   │  │ 6000 MHz XMP   │ │ Build 26100  │  Ratio      0.81    │
│                   │  └────────────────┘ └──────────────┘                    │
│                   │                                                          │
│  Profile: SAFE    │  [ ▶ Phase 1 ]  [ ▶ Phase 3 ]  [ 🗑 Cleanup ]           │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Hardware cards** are populated asynchronously on first open (~1 second). They show CPU model, GPU model and VRAM, RAM size and detected speed, and Windows build.

**Phase Progress** reads `C:\CS2_OPTIMIZE\progress.json`. If you have not run any phases yet, all bars show 0%.

**Benchmark summary** shows the most recent result from `benchmark_history.json`. Ratio = P1/Avg; values above 0.40 indicate good frametime consistency.

**Quick action buttons** launch the terminal phases in a new elevated PowerShell window. The dashboard remains open while the terminal runs. Cleanup runs `Cleanup.ps1` in Quick Refresh mode.

---

### Analyze

Runs a non-destructive system health scan. No changes are made. Results take 5–15 seconds.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   ANALYZE  [Scan System]  [Export CSV]                  │
│  ○ Dashboard      │                                                          │
│  ○ Analyze ←      │  Category    Group      Setting              Status      │
│  ○ Optimize       │  ─────────────────────────────────────────────────────  │
│  ○ Backup         │  Hardware    Memory     Dual-Channel         ✓ OK        │
│  ○ Benchmark      │  Hardware    Memory     XMP/EXPO Active      ✓ OK        │
│  ○ Video          │  Hardware    Security   VBS/HVCI             ⚠ Enabled   │
│  ○ Settings       │  Windows     Gaming     HAGS                 ✓ OK        │
│                   │  Windows     Gaming     Game Mode            ✗ Off       │
│                   │  Windows     Gaming     Game DVR             ✓ OK        │
│                   │  Windows     Gaming     Fast Startup         ✗ On        │
│                   │  Windows     Gaming     MPO                  ✓ OK        │
│                   │  System      Scheduler  MMCSS Responsiveness ✗ Default   │
│                   │  System      Scheduler  Win32PrioritySep     ✗ Default   │
│                   │  Network     Stack      Nagle                ✓ OK        │
│                   │  Network     Stack      IPv6                 ⚠ Active    │
│                   │  CS2         Autoexec   m_rawinput           ✗ Missing   │
│                   │  CS2         Video      Fullscreen           ✓ OK        │
│                   │  ...                                                      │
│                   │  12 issues found                                         │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Status columns:**
- `✓ OK` (green) — matches the recommended value
- `⚠ Check` (yellow) — present but not optimal, or hardware-dependent
- `✗ Off / Missing / Default` (red) — not yet optimized

**Categories covered:** Hardware (dual-channel, XMP, VBS/HVCI), Windows Gaming (HAGS, Game Mode, DVR, Fast Startup, MPO, FSE, Auto HDR), System Latency (MMCSS, Win32PrioritySeparation, DisablePagingExecutive, Timer, FTH, Maintenance, NTFS), Input (mouse acceleration, mouclass queue), Network (Nagle, IPv6, QoS NLA, URO), Services (SysMain, WSearch, Xbox, qWave), CS2 Config (autoexec CVars, video.txt settings, launch options).

**Export CSV** — saves the full results table to `C:\CS2_OPTIMIZE\analysis_<timestamp>.csv`. Useful for before/after comparison or sharing for support.

Each row includes a `StepRef` column showing which step addresses it (e.g., "Phase 1 Step 27") and an `Impact` estimate.

---

### Optimize

Shows the full step catalog — all 38 Phase 1 steps and all 13 Phase 3 steps — with their metadata. This is a read-only reference panel; steps run in the terminal.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   OPTIMIZE                                               │
│  ○ Dashboard      │   Filter Phase: [All ▼]  Category: [All ▼]              │
│  ○ Analyze        │   Risk: [All ▼]                                          │
│  ○ Optimize ←     │                                                          │
│  ○ Backup         │  Ph  Step  Category  Title                  Risk  Depth  │
│  ○ Benchmark      │  ─────────────────────────────────────────────────────  │
│  ○ Video          │  1   3     GPU       Clear Shader Cache      SAFE  FS    │
│  ○ Settings       │  1   4     Display   Fullscreen Opts Off     SAFE  REG   │
│                   │  1   6     System    CS2 Power Plan          MOD   REG   │
│                   │  1   7     GPU       HAGS                    MOD   REG   │
│                   │  1   16    Network   NIC Latency Stack       MOD   NET   │
│                   │  1   27    System    MMCSS + Gaming Priority SAFE  REG   │
│                   │  1   29    Input     Mouse Accel Off         SAFE  REG   │
│                   │  1   34    CS2       Autoexec (56 CVars)     SAFE  APP   │
│                   │  3   2     GPU       MSI Interrupts          MOD   DRV   │
│                   │  3   4     GPU       NVIDIA DRS Profile      SAFE  DRV   │
│                   │  3   10    CPU       Process Priority + X3D  SAFE  REG   │
│                   │  ...                                                      │
│                   │  [ ▶ Run Phase 1 Terminal ]  [ ▶ Run Phase 3 Terminal ]  │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Filters** let you narrow by phase, category (GPU, System, Network, etc.), and risk level. Useful when you want to see only MODERATE+ steps or only Network-category steps.

**Depth column** abbreviations: `FS` = filesystem, `REG` = registry, `NET` = network stack, `DRV` = driver, `SVC` = service, `APP` = application config, `BOOT` = bcdedit, `CHK` = check only.

The phase terminal buttons open a new elevated PowerShell window running `START.bat` pointed at the appropriate phase. The dashboard stays open.

---

### Backup

Shows everything the suite has backed up in `C:\CS2_OPTIMIZE\backup.json`, organized by step.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   BACKUP  [Export backup.json]                          │
│  ○ Dashboard      │                                                          │
│  ○ Analyze        │  Step                    Type       Date/Time            │
│  ○ Optimize       │  ─────────────────────────────────────────────────────  │
│  ○ Backup ←       │  Fullscreen Optimizations registry   2026-03-12 14:22   │
│  ○ Benchmark      │  CS2 Power Plan          powerplan   2026-03-12 14:23   │
│  ○ Video          │  HAGS                    registry    2026-03-12 14:25   │
│  ○ Settings       │  NIC Latency Stack       registry    2026-03-12 14:31   │
│                   │  MMCSS + Gaming Priority registry    2026-03-12 14:33   │
│                   │  Mouse Acceleration Off  registry    2026-03-12 14:35   │
│                   │  Disable Overlays        registry    2026-03-12 14:38   │
│                   │  SysMain Disable         service     2026-03-12 14:41   │
│                   │  MSI Interrupts          registry    2026-03-12 15:02   │
│                   │  NVIDIA DRS Profile      drs         2026-03-12 15:08   │
│                   │  Process Priority + X3D  registry    2026-03-12 15:11   │
│                   │  ...                                                      │
│                   │                                                          │
│                   │  [ Restore Selected ]  [ Restore All ]                  │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Restore Selected** — rolls back only the highlighted step(s). Registry keys are returned to their pre-suite values; services are returned to their original start type; power plans are re-activated; DRS settings are restored per-setting.

**Restore All** — full rollback to pre-suite state. Equivalent to `START.bat → [7] → Full restore`.

**Export** saves a copy of `backup.json` with a timestamped filename. Useful before any major change.

---

### Benchmark

Tracks FPS measurements over time and calculates your optimal NVCP frame cap.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   BENCHMARK  [ + Add Result ]                           │
│  ○ Dashboard      │                                                          │
│  ○ Analyze        │  FPS  ▲                                                  │
│  ○ Optimize       │  400 ┤                              ●                    │
│  ○ Backup         │  350 ┤               ●                                   │
│  ○ Benchmark ←    │  300 ┤    ●                                              │
│  ○ Video          │  250 ┤                         ─ ─ ─(P1)                 │
│  ○ Settings       │  200 ┤─────────────────────────────────────────► runs    │
│                   │      Baseline    Post-P1    Post-P3                      │
│                   │                                                          │
│                   │  #   Label        Avg FPS   P1 FPS   Ratio   Date        │
│                   │  ─────────────────────────────────────────────────────  │
│                   │  1   Baseline     290       115       0.40    03-12 09:10│
│                   │  2   Post-Phase1  341       201       0.59    03-12 14:45│
│                   │  3   Post-Phase3  387       312       0.81    03-12 15:30│
│                   │                                                          │
│                   │  FPS Cap Calculator                                      │
│                   │  Paste [VProf] line: [_________________________] [Calc]  │
│                   │  Recommended cap: 352 FPS  (387 − 9%)   [Copy cap]      │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Chart** — shows Avg FPS (solid line/dots) and P1 FPS (dashed line/dots) across all runs. The canvas is drawn programmatically — no external charting library.

**+ Add Result** — opens a dialog to label the result. If you paste a `[VProf] FPS: Avg=387.2, P1=312.0` line into the text field first, the Avg and P1 values are auto-parsed; you only need to confirm the label.

**FPS Cap Calculator** — paste any `[VProf]` line from the CS2 console into the text field, hit Calc, and the recommended cap is computed (`Avg × 0.91`). Click "Copy cap" to put the value on clipboard for pasting into NVCP.

---

### Video

Compares your current `video.txt` against the recommended values for your hardware tier. Write the optimized file in one click.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   VIDEO SETTINGS              [HIGH ▼]  [Write video.txt]│
│  ○ Dashboard      │   C:\...\userdata\12345678\730\local\cfg\video.txt       │
│  ○ Analyze        │                                                          │
│  ○ Optimize       │  Setting                  Your Value  Recommended  Status│
│  ○ Backup         │  ─────────────────────────────────────────────────────  │
│  ○ Benchmark      │  csm_enabled              1           1            ✓ OK  │
│  ○ Video ←        │  fullscreen               0           1            ⚠ ←  │
│  ○ Settings       │  mat_vsync                0           0            ✓ OK  │
│                   │  msaa_samples             0           4            ⚠ ←  │
│                   │  r_aoproxy_enable         1           0            ⚠ ←  │
│                   │  r_csgo_cmaa_enable       0           0            ✓ OK  │
│                   │  r_csgo_fsr_upsample      0           0            ✓ OK  │
│                   │  r_low_latency            1           1            ✓ OK  │
│                   │  r_particle_max_detail    2           0            ⚠ ←  │
│                   │  r_texturefilteringquality 0          5            ⚠ ←  │
│                   │  sc_hdr_enabled_override  0           3            ⚠ ←  │
│                   │  shaderquality            1           1            ✓ OK  │
│                   │                                                          │
│                   │  6 setting(s) differ from HIGH-tier recommendation       │
│                   │  [Write video.txt  (renames original → .bak)]            │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Tier picker** — AUTO (detects NVIDIA GPU presence → HIGH), HIGH, MID, or LOW. The recommended values change based on tier. See [`docs/video-settings.md`](video-settings.md) for the full rationale.

**Write video.txt** — backs up your current file as `video.txt.bak`, then writes the optimized values. Unmanaged keys (your resolution, refresh rate, and any custom settings not in the suite's managed set) are preserved. CS2 must be fully closed for the change to take effect on next launch.

---

### Settings

Configure how the terminal optimization phases behave. These settings persist in `C:\CS2_OPTIMIZE\state.json`.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CS2 Optimize Suite  2026                                    —   □   ✕      │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │   SETTINGS                                               │
│  ○ Dashboard      │                                                          │
│  ○ Analyze        │  Optimization Profile                                    │
│  ○ Optimize       │  ○ SAFE         Auto-apply proven tweaks only            │
│  ○ Backup         │  ● RECOMMENDED  Prompt on moderate tweaks  ← default     │
│  ○ Benchmark      │  ○ COMPETITIVE  Prompt on all tweaks                     │
│  ○ Video          │  ○ CUSTOM       Full detail card for every step          │
│  ○ Settings ←     │                                                          │
│                   │  DRY-RUN mode   ○ Off  ● On                              │
│                   │  Preview changes without applying anything               │
│                   │                                                          │
│                   │  DNS Region                                              │
│                   │  [EU (Cloudflare) ▼]                                     │
│                   │  Applied in Phase 3 Step 9                               │
│                   │                                                          │
│                   │  Average FPS (for FPS cap)                               │
│                   │  [387 ________________]                                   │
│                   │  Used in Phase 3 Step 13 for cap calculation             │
│                   │                                                          │
│                   │  [ Save Settings ]                                       │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

**Profile** — determines which steps run automatically vs. prompted vs. skipped in the terminal phases. See the [Profile System](../README.md#profile-system) section for the full behavior matrix.

**DRY-RUN** — when on, all registry, boot config, and service writes are replaced by preview messages. The full terminal flow runs but nothing is changed. Safe to use on any profile to preview what would happen.

**DNS Region** — applies in Phase 3 Step 9. Cloudflare `1.1.1.1/1.0.0.1` is the default; `8.8.8.8/8.8.4.4` (Google) is the alternative. Use your nearest regional option.

**Average FPS** — if you already know your average FPS from a previous benchmark, set it here. Phase 3 uses it for FPS cap calculation.

---

## What the GUI Cannot Do

The GUI is a management dashboard, not a replacement for the terminal phases. The following require the terminal:

| Task | Why terminal only |
|------|------------------|
| Phase 1 (38-step optimization) | Requires reboot into Safe Mode at the end; interactive confirmation at each step |
| Phase 2 (GPU driver removal in Safe Mode) | Runs automatically from RunOnce in Safe Mode — no GUI is available in Safe Mode |
| Phase 3 (driver install + final steps) | Runs automatically after Phase 2 |
| Cleanup (Quick / Full / Driver Refresh) | Driver Refresh involves Safe Mode reboot |

The GUI **does** supplement the terminal with:
- Pre-flight system analysis before you run any phases
- Backup review and per-step rollback after running phases
- Benchmark tracking across multiple sessions
- video.txt management independently of the optimization phases

---

## Technical Notes

**Admin requirement:** The dashboard requires elevation to read hardware configuration, HKLM registry keys, and system service states. The `START-GUI.bat` launcher handles this automatically.

**Async model:** Hardware detection, system analysis, and backup loading all run in background RunSpaces (PowerShell thread pool). The UI remains responsive during these operations. A 250ms DispatcherTimer polls for completion and updates the UI thread.

**Scope:** The GUI dot-sources `config.env.ps1` and `helpers.ps1` at startup. The `step-catalog.ps1` and `system-analysis.ps1` helpers are GUI-only and are not loaded in the terminal flow.
