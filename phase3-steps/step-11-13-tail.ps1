# ══════════════════════════════════════════════════════════════════════════════
# STEP 11 — VRAM LEAK AWARENESS  [Info]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 11) {
    Write-Section "Step 11 — VRAM Leak Awareness"
    Write-TierBadge 2 "CS2 VRAM Leak Bug — Known Issue"
    Write-Blank
    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  CS2 KNOWN VRAM LEAK BUG:                                   │" -ForegroundColor Yellow
    Write-Host "  │                                                              │" -ForegroundColor Yellow
    Write-Host "  │  CS2 has a known VRAM leak especially affecting GPUs with   │" -ForegroundColor White
    Write-Host "  │  8 GB VRAM. After long sessions (2+ hours) VRAM usage      │" -ForegroundColor White
    Write-Host "  │  steadily rises -> stutter and FPS drops.                  │" -ForegroundColor White
    Write-Host "  │                                                              │" -ForegroundColor Yellow
    Write-Host "  │  RECOMMENDATION:                                            │" -ForegroundColor White
    Write-Host "  │  -> Restart CS2 every 2-3 hours                            │" -ForegroundColor Green
    Write-Host "  │  -> Monitor VRAM usage with HWiNFO64 or Task Manager       │" -ForegroundColor White
    Write-Host "  │  -> Warning at > 85% VRAM usage                            │" -ForegroundColor White
    Write-Host "  │                                                              │" -ForegroundColor Yellow
    Write-Host "  │  MOST AFFECTED:                                             │" -ForegroundColor DarkYellow
    Write-Host "  │  -> RTX 4060 / 4060 Ti (8 GB) -> critical after ~3h       │" -ForegroundColor White
    Write-Host "  │  -> RX 7600 (8 GB) -> similar issues                       │" -ForegroundColor White
    Write-Host "  │  -> 12+ GB GPUs: less problematic, but exists              │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Blank
    Complete-Step $PHASE 11 "VRAMLeak"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 12 — FINAL CHECKLIST + HONEST KNOWLEDGE SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 12) {
    Write-Section "Step 12 — Final Checklist + Knowledge Summary"

    Write-Host @"

  DONE — with proven effect:
  ✔  Shader cache cleared           [T1: Directly measurable after driver change]
  ✔  Fullscreen optimizations       [T1: m0NESY-documented, no downside]
  ✔  CS2 Optimized power plan        [T1: 100+ sub-settings, full coverage]
  ✔  Native driver clean + install  [T1: Industry standard]
  ✔  GPU MSI via native registry    [T1: Interrupt overhead measurable]
  ✔  FPS cap via NVCP               [T1: Reproduced, more stable frametimes]
  ✔  Video settings configured      [Boost Contrast +5% lows, AO -30fps]
  ✔  Dual-channel RAM checked       [T1: Half bandwidth = dramatic]
"@ -ForegroundColor Green

    Write-Host @"
  DONE — setup-dependent (T2):
  ✔  XMP/EXPO checked               [Hardware logic: sensible. CS2 bench: unclear]
  ✔  Resizable BAR / SAM            [AMD: measurable. CS2-specific: no data]
  ✔  Nagle's Algorithm               [TCP latency reduced]
  ✔  GameConfigStore FSE keys       [Supplements fullscreen exclusive]
  ✔  SystemResponsiveness           [Gaming priority in scheduler]
  ✔  Timer resolution               [More precise system timer]
  ✔  Mouse acceleration             [1:1 input for aim consistency]
  ✔  Game DVR / Game Bar            [Background recording off]
  ✔  Overlays                       [Steam/Discord/GFE overlay off]
  ✔  Audio optimized                [24-bit/48kHz, no spatial sound]
  ✔  Autoexec.cfg                   [Network CVars optimized]
  ✔  Chipset driver checked         [Current driver recommended]
"@ -ForegroundColor Yellow

    Write-Host @"
  STILL MANUAL:
  ○  Run benchmark map 3 times (Dust2 + Inferno recommended)
  ○  Calculate FPS cap: START.bat -> [3] FPS Cap Calculator
  ○  Verify Reflex decision with CapFrameX:
     Test A (-noreflex + NVCP Ultra) vs. B (Reflex ON in-game)
     Choose what gives better lows AND better feel.
  ○  Check settings after Windows Update: START.bat -> [6] Verify
  ○  All 52 NVIDIA DRS settings applied natively — no external tools needed
"@ -ForegroundColor Cyan

    # ── X3D / Hardware Validation Checks ─────────────────────────────────
    # Box width: 66 chars total. Inner: "  │  " (6) + content (up to 58) + " " + "│" (1) = 66
    # Helper: pad content to 58 chars inside the box
    $amdCpu = Get-AmdCpuInfo
    if ($amdCpu -and $amdCpu.IsX3D) {
        Write-Blank
        Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
        $hdr = "$($amdCpu.CpuName) — POST-TUNING VALIDATION"
        Write-Host "  │  $($hdr.PadRight(58))│" -ForegroundColor Cyan
        Write-Host "  │                                                              │" -ForegroundColor DarkGray

        # CPU clock info (informational — MaxClockSpeed is base clock, not boost)
        if ($amdCpu.MaxClockSpeed -gt 0) {
            $msg = "$([char]0x2139)  CPU: $($amdCpu.CpuName) — base clock: $($amdCpu.MaxClockSpeed) MHz"
            Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor Cyan
            $msg2 = "   (boost clock requires HWiNFO to verify)"
            Write-Host "  │  $($msg2.PadRight(58))│" -ForegroundColor DarkGray
        }

        # WHEA error check
        $whea = Test-WheaErrors
        if ($whea) {
            if ($whea.HasErrors) {
                $msg = "$([char]0x2718)  WHEA errors: $($whea.RecentCount) in last 24h — CO too aggressive!"
                Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor Red
                Write-Host "  │     Reduce Curve Optimizer magnitude by 5 and retest.      │" -ForegroundColor Red
            } else {
                $totalLabel = if ($whea.Count -gt 0) { "$($whea.Count) total (none recent)" } else { "0 — clean" }
                $msg = "$([char]0x2714)  WHEA errors: $totalLabel"
                Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor Green
            }
        }

        # DDR5 FCLK/MCLK 1:1 check
        $ddr5 = Get-Ddr5TimingInfo
        if ($ddr5 -and $ddr5.IsDDR5) {
            $mclk = $ddr5.ActiveMhz
            $mts  = $ddr5.ActiveMTs
            if ($ddr5.IsOptimal1to1) {
                $msg = "$([char]0x2714)  DDR5-$mts (MCLK $mclk MHz) — 1:1 FCLK range"
                Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor Green
            } elseif ($mts -gt 6400) {
                $msg = "$([char]0x25B2)  DDR5-$mts — above 1:1 FCLK sweet spot (6000)"
                Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor Yellow
                if ($amdCpu -and $amdCpu.IsAMD) {
                    Write-Host "  │     Consider DDR5-6000 for lowest latency on AM5.          │" -ForegroundColor DarkGray
                }
            } else {
                $msg = "$([char]0x25CB)  DDR5-$mts (MCLK $mclk MHz)"
                Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor DarkGray
            }
            if ($ddr5.IsDownclocked) {
                $msg = "$([char]0x2139)  Kit rated $($ddr5.RatedMTs) MT/s, downclocked to $mts MT/s"
                Write-Host "  │  $($msg.PadRight(58))│" -ForegroundColor DarkGray
            }
        }

        Write-Host "  │                                                              │" -ForegroundColor DarkGray
        Write-Host "  │  Full validation: X3D_KOMPLETT_GUIDE.md Section E           │" -ForegroundColor DarkGray
        Write-Host "  │  ZenTimings screenshot recommended for RAM timing verify.   │" -ForegroundColor DarkGray
        Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    }

    Write-Blank
    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor DarkYellow
    Write-Host "  │  WHAT THIS SCRIPT CANNOT FIX                                │" -ForegroundColor DarkYellow
    Write-Host "  │                                                              │" -ForegroundColor DarkYellow
    Write-Host "  │  CS2 has structurally poor frame pacing.                    │" -ForegroundColor White
    Write-Host "  │  Apex Legends, The Finals and Warzone — all with higher     │" -ForegroundColor White
    Write-Host "  │  graphics load — deliver consistently better 1% lows.       │" -ForegroundColor White
    Write-Host "  │  This is a Valve/Source2 problem, not a hardware problem.   │" -ForegroundColor White
    Write-Host "  │  No tweak fundamentally fixes this.                         │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor DarkYellow

    Write-Blank
    Write-Host "  NEXT STEPS — IF PROBLEMS PERSIST:" -ForegroundColor White
    Write-Host @"
  1.  Run LatencyMon  (resplendence.com/latencymon)
      -> Shows which drivers cause DPC spikes
      -> Then decide if NIC tweaks or MSI Utility are useful

  2.  Log HWiNFO64 during a match
      -> Log CPU/GPU package temp + clock + power
      -> Thermal throttling is a commonly overlooked cause of lows

  3.  Rule out thermal problems
      -> CPU TJmax: AMD Ryzen 95C, Intel varies
      -> GPU: 83C = throttle start on NVIDIA

  4.  RAM sub-timings (only if XMP active and stable)
      -> B-Die or Hynix A-Die recommended
      -> CL30 -> CL28 -> CL26 stabilize with TM5/HCI MemTest
      -> Effect on 1% lows measurable but hardware-dependent

  5.  CPU upgrade as last resort
      -> 9800X3D is clear leader for CS2 as of March 2026
      -> Single-core performance is the limiting factor

  Rule: Always measure before/after with CapFrameX.
  Without measurement, any claim about improvement is placebo.
"@ -ForegroundColor DarkGray

    Write-Info "Log: $CFG_LogFile  |  Tools: $CFG_WorkDir"
    Complete-Step $PHASE 12 "Checklist"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 13 — FINAL BENCHMARK + FPS CAP  [T1, LAST STEP]
# ══════════════════════════════════════════════════════════════════════════════
if ($startStep -le 13) {
    Write-Section "Step 13 — Final Benchmark + FPS Cap Calculation  [LAST STEP]"
    Write-TierBadge 1 "Post-optimization benchmark — proof of improvement"
    Write-Blank

    Write-Host @"
  FPSHEAVEN BENCHMARK MAPS  (by @fREQUENCYcs)
  ─────────────────────────────────────────────
  Outputs at end in console window:
    [VProf] FPS: Avg=XXX.X, P1=XXX.X

  Map 1 — DUST2  (community standard):
  $CFG_Benchmark_Dust2

  Map 2 — INFERNO:
  $CFG_Benchmark_Inferno

  Map 3 — ANCIENT  (water interaction):
  $CFG_Benchmark_Ancient

  WORKFLOW:
  1.  Steam -> Workshop -> Subscribe to map
  2.  CS2: Play -> Workshop Maps -> start
  3.  Runs 2-3 minutes automatically — don't touch PC
  4.  Console opens automatically -> copy [VProf] line
  5.  Paste output below for automatic tracking + FPS cap

  BEST RESULT: Run 3 times, use the average.

  WHY AN FPS CAP?
  ────────────────
  Without a cap the GPU runs at max continuously -> frametimes fluctuate.
  With a cap the GPU runs at even load -> more consistent 1% lows.
  Method: avg FPS - 9%  (FPSHeaven / Blur Busters recommendation).
"@ -ForegroundColor DarkGray

    if ($fpsCap -gt 0) {
        Write-Host "  Already calculated cap: $fpsCap  (avg $avgFps - 9%)" -ForegroundColor Green
    }

    # Use the iterative benchmark tracking system
    $bmResult = Invoke-BenchmarkCapture -Label "After all optimizations"

    if ($bmResult) {
        Write-Blank
        Write-Info "Set FPS cap in: NVIDIA CP -> CS2 -> Max Frame Rate -> $($bmResult.Cap)"
        Write-Info "You can run this benchmark again anytime via START.bat -> [3] FPS Cap Calculator."
        Write-Info "All results are tracked in: $CFG_BenchmarkFile"

        # Show improvement estimate vs. actual results
        $baselineAvg = if ($state.PSObject.Properties['baselineAvg'] -and $null -ne $state.baselineAvg) { $state.baselineAvg } else { 0 }
        $baselineP1  = if ($state.PSObject.Properties['baselineP1']  -and $null -ne $state.baselineP1)  { $state.baselineP1 }  else { 0 }
        Show-ImprovementEstimate -BaselineAvg $baselineAvg -BaselineP1 $baselineP1 `
            -ActualAvg $bmResult.Avg -ActualP1 $bmResult.P1
    }

    # Show full history if multiple results exist
    $history = @(Get-BenchmarkHistory)
    if ($history.Count -ge 2) {
        Write-Blank
        Show-BenchmarkComparison
    }

    Complete-Step $PHASE 13 "FinalBenchmark"
}

Write-Blank
if ($SCRIPT:DryRun) {
    Write-PhaseSummary -PhaseLabel "PHASE 3" -DryRun
} else {
    Write-PhaseSummary -PhaseLabel "ALL 3 PHASES" -NextAction "Good luck, have fun! GG"

    $r = if (Test-YoloProfile) { "y" } else { Read-Host "  Final restart recommended (MSI changes). Now? [y/N]" }
    if ($r -match "^[jJyY]$") {
        Restart-Computer -Force
    }
}
