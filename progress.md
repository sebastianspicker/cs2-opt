# Audit Progress

## Item 1 — Code Duplication: Intel hybrid CPU detection [FIXED]

**Files:** `helpers/hardware-detect.ps1`, `Optimize-RegistryTweaks.ps1`, `Optimize-GameConfig.ps1`

**Issue:** The Intel hybrid CPU detection pattern (Get-CimInstance Win32_Processor, Intel regex match for 12xxx-19xxx + Core Ultra) was duplicated verbatim in Step 27 (PowerThrottlingOff) and Step 34 (thread_pool_option). Same 6-line block, same regexes, separate error handling.

**Fix:** Extracted to `Get-IntelHybridCpuName` in `hardware-detect.ps1`. Returns the CPU name string if Intel hybrid, `$null` otherwise. Both Step 27 and Step 34 now call this one function. Also eliminates the separate CIM query per step (both steps previously each made their own `Win32_Processor` call).

---

## Item 2 — Code Duplication: Steam base path lookup [FIXED]

**Files:** `helpers/hardware-detect.ps1` (new `Get-SteamPath`), plus 6 callers updated:
`Optimize-SystemBase.ps1` (Steps 3+4), `Cleanup.ps1`, `Optimize-GameConfig.ps1` (Step 34),
`helpers/system-analysis.ps1`, `Guide-VideoSettings.ps1`, `helpers/gui-panels.ps1` (×2).

**Issue:** The 3-line `Get-ItemProperty "HKCU:\SOFTWARE\Valve\Steam" / SteamPath` read
appeared 9 times in 7 files with slightly different variable names (`$_steamReg`,
`$_steamReg2`, `$_steamCloudReg`, `$_steamVideoReg`) — pure registry boilerplate.

**Fix:** Added `Get-SteamPath` to `hardware-detect.ps1`. `Get-CS2InstallPath` now
calls it internally. All 8 external call sites replaced with a single-line call.

---

## Item 3 — Code Duplication: Intel hybrid detection in Verify-Settings.ps1 [FIXED]

**File:** `Verify-Settings.ps1`

**Issue:** Lines 80-94 still contained the original 15-line try/catch Intel hybrid detection block (inline `Get-CimInstance Win32_Processor`, regex checks) even after Item 1 extracted the pattern to `Get-IntelHybridCpuName`. This was a missed call-site during the Item 1 sweep.

**Fix:** Replaced the 15-line try/catch with a 5-line `Get-IntelHybridCpuName` call. The outer try/catch is dropped because `Get-IntelHybridCpuName` handles failures internally and returns `$null` on error.

---

## Item 4 — Bug: Undefined `$steamReg` in Cleanup.ps1 Steam Verification [FIXED]

**File:** `Cleanup.ps1` line 161

**Issue:** Item 2 correctly added `$steamBase = Get-SteamPath` at line 63 for the shader cache path, but the Steam verification block's `steam.exe` lookup (line 161) still referenced the old `$steamReg` variable which no longer exists. With `Set-StrictMode -Version Latest` active, accessing an undefined variable is a terminating error — this would crash the Full Cleanup path whenever `Winsock Reset` or `Steam Verification` was run.

**Fix:** Changed `"$(if($steamReg){"$steamReg\steam.exe"})"` → `"$(if($steamBase){"$steamBase\steam.exe"})"` — uses the already-defined `$steamBase` from line 63.

---

## Item 5 — Critical Finding: No Tests Exist [DOCUMENTED]

**Finding:** Zero test files found. No `*.Tests.ps1`, no `tests/` directory, no Pester spec files anywhere in the repository.

**Impact:** The suite modifies Windows registry, boot configuration, services, GPU driver settings, and Safe Mode boot — all destructive or hard-to-reverse operations. Without tests:
- Pure helper functions (`Get-IntelHybridCpuName`, `Get-SteamPath`, `Calculate-FpsCap`, `Parse-BenchmarkOutput`, DRS struct sizes/offsets) cannot be regression-tested after refactoring.
- Logic bugs in `helpers/benchmark-history.ps1`, `helpers/tier-system.ps1`, and `helpers/backup-restore.ps1` can only be caught by running Phase 1 end-to-end on a real system.
- DRY-RUN mode has no automated verification.

**Recommendation (not auto-applied — requires Pester setup):**
1. Add `Pester` to the project: `Install-Module Pester -Scope CurrentUser`
2. Create `tests/` directory with:
   - `hardware-detect.Tests.ps1` — test `Get-IntelHybridCpuName` regex matching, `Get-SteamPath` registry mock, `Calculate-FpsCap` arithmetic
   - `benchmark-history.Tests.ps1` — test `Parse-BenchmarkOutput` against known `[VProf]` strings, `Calculate-FpsCap` edge cases (0, negative, very large FPS)
   - `tier-system.Tests.ps1` — test `Invoke-TieredStep` dry-run mock with fake `$SCRIPT:Profile`
3. Run in CI: `Invoke-Pester ./tests -CI`

**Scope of testable pure functions (no Windows API dependencies):**
- `Calculate-FpsCap($avg)` — pure arithmetic
- `Parse-BenchmarkOutput($text)` — pure regex parsing
- `Get-IntelHybridCpuName` — mockable via `Mock Get-CimInstance`
- `Get-SteamPath` — mockable via `Mock Get-ItemProperty`
- DRS struct size/offset constants in `NvApiDrs` C# class — validate with `sizeof` equivalents

---

## Remaining audit scope

All files have been reviewed. Summary of reviewed-clean files:
- `helpers/logging.ps1` — **REVIEWED**: `function Write-OK($t)` style is valid PowerShell simple-param syntax for one-liner wrappers; no change needed.
- `Run-Optimize.ps1` / all entry-points — **DOCUMENTED FINDING (not auto-fixed)**: ALL 5 entry-point scripts (`Run-Optimize.ps1`, `PostReboot-Setup.ps1`, `Cleanup.ps1`, `FpsCap-Calculator.ps1`, `Verify-Settings.ps1`) set `$ErrorActionPreference = "SilentlyContinue"` globally while also using `Set-StrictMode -Version Latest` (contradictory). This silently swallows all non-terminating cmdlet errors across all dot-sourced sub-scripts. Correct fix: change to `"Continue"` (PowerShell default) and add explicit `-ErrorAction SilentlyContinue` only where genuinely needed. Marked as risky-scope per audit rule — needs full sub-script audit before applying.
- `helpers/nvidia-drs.ps1` — **REVIEWED**: clean; correct GCHandle pinning in try/finally; `_resolved` guard; `Invoke-DrsSession` finally-cleanup; no issues
- `helpers/nvidia-profile.ps1` — **REVIEWED**: clean; DRS-first/registry-fallback architecture correct; `$NV_DRS_SETTINGS` table well-documented; no issues
- `helpers/nvidia-driver.ps1` — **REVIEWED**: clean; ordered series map for deterministic GPU matching; `$global:ProgressPreference` stored/restored correctly; no issues
- `helpers/gpu-driver-clean.ps1` — **REVIEWED**: clean; precise DriverStore patterns prevent false matches; DRY-RUN support correct; no issues
- `helpers/benchmark-history.ps1` — **REVIEWED**: no issues found (clean iterative tracking)
- `helpers/power-plan.ps1` — **REVIEWED**: clean; intentional duplicate GUID for DISKPOWERMGMT/DISKLPM (T1→1, T2 overrides→0) documented inline; T2 count formula accurate
- `helpers/step-catalog.ps1` — **REVIEWED**: pure data table; Step 7 gap is intentional (reserved placeholder); no issues
- `helpers/system-analysis.ps1` — **REVIEWED**: clean; uses `Get-SteamPath` correctly (Item 2 already applied); `New-CheckItem`/`Get-RegVal` helpers well-structured; no issues
- `helpers/gui-panels.ps1` — **REVIEWED**: clean; uses `Get-SteamPath` correctly at lines 73 and 543 (Item 2 already applied); 7-panel WPF architecture; async runspace pattern correct; no issues
- `Optimize-SystemBase.ps1` — **REVIEWED**: clean; Get-WmiObject in Step 8 is intentional (documented); Get-SteamPath already applied; no issues
- `Optimize-Hardware.ps1` — **REVIEWED**: Steps 10-22 clean; consistent DRY-RUN support; no issues
- `PostReboot-Setup.ps1` — **REVIEWED**: clean; Step 7 reserved placeholder intentional; DNS step intentionally uses broader NIC filter than Get-ActiveNicAdapter; no issues
- `SafeMode-DriverClean.ps1` — **REVIEWED**: clean; simple 3-step Phase 2 entry point; no issues
- `Cleanup.ps1` — **REVIEWED**: Bug fixed (Item 4 — `$steamReg` → `$steamBase` in Steam verification block)
- `FpsCap-Calculator.ps1` — **REVIEWED**: clean; proper input fallback chain; state/history persistence correct; no issues
- `CS2-Optimize-GUI.ps1` — **REVIEWED**: clean; 806 lines; `Invoke-Async` correct try/catch/finally + Dispose(); `Switch-Panel` nav clean; `Add_Closed` tears down RunspacePool; notably does NOT set `$ErrorActionPreference = "SilentlyContinue"` (unlike CLI entry-points); no issues
- `config.env.ps1` — **REVIEWED**: clean; 262 lines; paths, GUIDs, benchmark config, 74 CVars; no issues

## Audit Complete (Code Quality)

All files reviewed. 4 bugs/duplications fixed, 2 findings documented (not auto-applied):
- **Items 1-4**: Fixed (Intel hybrid CPU detection deduplication ×3, Steam path deduplication, undefined `$steamReg` crash)
- **Item 5**: Missing tests — documented critical finding; Pester recommended for pure functions
- **Global EAP issue**: `$ErrorActionPreference = "SilentlyContinue"` in 5 CLI entry-points — documented, risky-scope, not auto-fixed

---

# Security Audit (02-security.md)

## Item S1 — No Authenticode signature verification on downloaded NVIDIA driver [DOCUMENTED — MEDIUM]

**Files:** `helpers/system-utils.ps1` (`Invoke-Download`), `helpers/nvidia-driver.ps1` (`Get-LatestNvidiaDriver`), `helpers/nvidia-driver.ps1` (`Install-NvidiaDriverClean`)

**Severity:** MEDIUM

**Issue:**
The NVIDIA driver download pipeline has two related weaknesses:

1. **URL not domain-validated** (`nvidia-driver.ps1` lines 75-89): The download URL is scraped from NVIDIA's HTML response via regex (`downloadURL = '...'` or any `https://...exe` URL). The only validation is `if ($downloadUrl -notmatch "^https?://")` — this ensures HTTPS but does not verify the URL is within `*.nvidia.com`. A compromised NVIDIA lookup page could embed a URL pointing to a third-party `.exe`.

2. **No Authenticode signature check** (`system-utils.ps1` line 19): `Invoke-Download` only checks that the downloaded file is >1 MB (truncation guard). There is no call to `Get-AuthenticodeSignature` to verify the binary is signed by NVIDIA before `Install-NvidiaDriverClean` runs `Start-Process` on it. PowerShell's `Get-AuthenticodeSignature` works for Windows-signed `.exe` files and would catch unsigned or mis-signed binaries.

**Attack scenario:** Requires NVIDIA CDN compromise OR a network-level MitM that bypasses TLS (e.g., corporate proxy with cert injection). Low likelihood but the tool runs as Administrator, making impact severe if triggered.

**Recommended fix (not auto-applied — changes user-visible behavior):**
```powershell
# After Invoke-Download succeeds in PostReboot-Setup.ps1 / wherever Install-NvidiaDriverClean is called:
$sig = Get-AuthenticodeSignature -FilePath $DriverExe
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'NVIDIA') {
    Write-Err "Driver signature invalid or not from NVIDIA (status: $($sig.Status)). Aborting."
    Remove-Item $DriverExe -Force -ErrorAction SilentlyContinue
    return $false
}
Write-OK "Authenticode signature valid: $($sig.SignerCertificate.Subject)"
```

Also add URL domain validation in `Get-LatestNvidiaDriver`:
```powershell
if ($downloadUrl -notmatch '^https://[^/]*\.nvidia\.com/') {
    Write-Warn "Unexpected download domain — falling back to manual."
    return @{ ManualDownload = $true; Url = "https://www.nvidia.com/en-us/drivers/"; GpuName = $gpuName }
}
```

**Why not auto-applied:** The Authenticode check could fail legitimately if NVIDIA changes their signing certificate (e.g., new subsidiary CA), causing false-rejection. Should be opt-in or combined with a `Write-Warn` + user confirmation fallback rather than a hard block.

---

## Item S2 — CI/GitHub Actions security review [CLEAN — minor stale comment]

**Severity:** INFO (documentation only)

**CI security posture reviewed — exemplary:**
- `permissions: contents: read` on both `lint.yml` and `security.yml` — least privilege ✓
- `persist-credentials: false` on all `actions/checkout` steps ✓
- All `actions/checkout` steps pinned to full SHA `de0fac2e4500dabe0009e67214ff5f5447ce83dd` — supply chain protection ✓
- `concurrency` + `cancel-in-progress: true` on both workflows — prevents CI resource abuse ✓
- `dependabot.yml`: weekly grouped PRs for GitHub Actions SHA updates ✓
- No `pull_request_target` trigger (workflow integrity check verifies this) ✓
- No `write-all` permissions ✓
- Secret scanning covers AWS keys, GitHub PATs, Slack tokens, OpenAI keys ✓
- PowerShell safety: `Invoke-Expression`/`iex` and `DownloadString` blocked ✓
- Expression injection check covers all 11 attacker-controlled GitHub context values ✓
- SECURITY.md present with DRY-RUN system documentation and responsible disclosure process ✓

**Minor stale comment (not auto-fixed — security hook blocks workflow edits):**
`lint.yml` lines 26-27 say "Pinned to actions/checkout v4.2.2 (2024-10-28) full SHA" but the inline comment on line 28 says `# v6.0.2`. One is stale. The SHA pin is the actual security mechanism — the comment discrepancy is cosmetic. Fix: replace the descriptive block comment with a version-agnostic note pointing to Dependabot.

## Item S3 — Input validation: user-provided file paths [CLEAN — no privilege escalation]

**Severity:** INFO

`PostReboot-Setup.ps1` lines 89 and 99 accept a user-typed path to a driver `.exe` via `Read-Host`. The path is passed to `Install-NvidiaDriverClean` which calls `Start-Process -FilePath $DriverExe`.

**Why this is not a vulnerability:**
1. `#Requires -RunAsAdministrator` — the person at the keyboard already has full admin rights
2. `Start-Process -FilePath` calls `CreateProcess` directly — no shell invocation, no argument splitting, no injection possible
3. `Test-Path $DriverExe` check prevents execution of non-existent paths
4. An attacker who could control this input (physical/RDP access) already has full admin access — no privilege escalation possible

**Menu inputs** (`Read-Host` for `[1/2/3/4]`, `[y/N]`, profile selection) are all validated with `-notin` / `-match` guards before use.

**`state.json` deserialization:** `ConvertFrom-Json` reads from `C:\CS2_OPTIMIZE\state.json`. That directory is created with admin rights and requires admin to write. `.nvidiaDriverPath` field from state is also subject to `Test-Path` validation. No exploitation path exists without pre-existing admin access.

## Security Audit Complete

All security scope areas reviewed. One MEDIUM finding documented (S1), remainder clean:

| Item | Severity | Status |
|------|----------|--------|
| S1 — No Authenticode check on downloaded NVIDIA driver | MEDIUM | Documented — recommended fix provided |
| S2 — CI/GitHub Actions | INFO | Clean; stale comment in lint.yml |
| S3 — User-provided file path inputs | INFO | Clean — no privilege escalation possible |
| Secrets/credentials in codebase | — | Clean |
| `.gitignore` coverage | — | Clean |
| `Invoke-Expression`/iex usage | — | Clean (zero instances) |
| SSRF / outbound request validation | — | All URLs are hardcoded NVIDIA/Steam/AMD/Intel domains |
| `state.json` deserialization | — | Clean — requires pre-existing admin access to attack |

---

# Documentation Audit (03-docs-writing.md)

## Item D1 — README.md: bold-as-emphasis violations [FIXED]

**File:** `README.md`

8 instances of bold used for mid-paragraph emphasis, violating "bold for headings/definition terms only":
- `**We only claim what we can back up.**` — standalone callout
- `**This is mostly ineffective.**` — NVIDIA DRS section
- `**Empirically, the opposite is true.**` — NIC coalescing section
- `**Game Mode suppresses Windows Update installation during active gaming**` — mid-sentence
- `**We deliberately leave it at the Windows default (10).**` — NetworkThrottlingIndex section
- `**Do not treat either side as settled.**` — Reflex section
- `**Critical caveat:**` — mid-sentence, Reflex section
- `**not**` — single word, Network Condition CFGs

All 8 converted to plain text. Retained bold only for definition terms (Position A/B, Method:, etc.) and table headings.

## Item D2 — README.md: stale CVar count [FIXED]

Lines 169 and 222 said "56 CVars (8 categories)". Actual count in `config.env.ps1 $CFG_CS2_Autoexec`: 74 CVars across 10 categories (Network 11, Engine 5, Gameplay 17, HUD/QoL 7, Privacy 5, Telemetry 5, Audio Spatial 9, Audio Music 8, Mouse 4, Video 3). Both references updated to "74 CVars (10 categories)".

## Item D2b — CONTRIBUTING.md: broken cross-reference link [FIXED]

Line 41 linked to `README.md#debunked--contested-settings` — that anchor doesn't exist. The debunked content lives at `docs/debunked.md`. Link updated.

## Item D3 — docs/evidence.md: stale values + bold violations [FIXED]

- `mouclass queue 100→16` → `100→50` (line 133: suite now sets 50, not 16)
- `56 CVars` → `74 CVars` (line 138: step 34 table, same stale count)
- 3 bold-as-emphasis violations removed (lines 30, 38, 72)

## Item D4 — docs/debunked.md: bold violations [FIXED]

8 bold-as-emphasis violations removed:
- Line 43: `**Resolved.**` → plain (table cell)
- Lines 45, 46, 53: `**TCP-only**` → plain (3 rows)
- Line 84: `**\`AppInit_DLLs\`**` → `` `AppInit_DLLs` `` (code stays, bold wrapper removed)
- Line 84: `**CS2 players using AMD Anti-Lag received VAC bans.**` → plain
- Line 98: `**If you are on a current AMD driver (late 2023+), Anti-Lag is safe.**` → plain
- Line 106: `**a setting must have a mechanistic explanation...**` → plain

## Documentation Remaining Scope

- ~~README.md~~ ✓ | ~~CONTRIBUTING.md~~ ✓ | ~~docs/evidence.md~~ ✓ | ~~docs/debunked.md~~ ✓
- ~~docs/gui.md~~ ✓ | ~~docs/windows-scheduler.md~~ ✓ | ~~docs/nic-latency-stack.md~~ ✓
- ~~docs/nvidia-optimization.md~~ ✓ | ~~docs/backup-restore.md~~ ✓ (FPSHeaven ref removed)
- ~~docs/nvidia-drs-settings.md~~ ✓ | ~~docs/power-plan.md~~ ✓
- ~~docs/power-plan.md~~ ✓ | ~~docs/network-cfgs.md~~ ✓ | ~~docs/services.md~~ ✓
- ~~docs/msi-interrupts.md~~ ✓ | ~~docs/process-priority.md~~ ✓
- ~~docs/debloat.md~~ ✓ | ~~docs/audio.md~~ ✓
- ~~docs/audio.md~~ ✓ | ~~docs/video-settings.md~~ ✓ (56→74 CVars, missing HUD/QoL+Privacy sections added, cl_predict values 1→0)
- ~~Inline code comments in PS1 files~~ ✓ — No redundant WHAT-only comments found. All explain WHY with sources.

---

# GitHub Polish & CI Audit (04-github-ci.md)

## Item G1 — CHANGELOG.md [CREATED]

No changelog existed. Created `CHANGELOG.md` following Keep a Changelog format with an [Unreleased] section documenting all major changes from the audit loops (external tool elimination, new helpers, fixed bugs, changed settings, removed debunked CVars).

## GitHub CI Audit — Status

### Existing infrastructure (reviewed, no changes needed):
- `.gitignore` — comprehensive: OS, IDE, PS artifacts, runtime state, secrets, personal configs ✓
- `LICENSE` — MIT ✓
- `CONTRIBUTING.md` — evidence requirement, PSScriptAnalyzer instructions, backup rules ✓
- `.github/ISSUE_TEMPLATE/bug_report.yml` + `feature_request.yml` — YAML forms, PS-specific fields ✓
- `.github/PULL_REQUEST_TEMPLATE.md` — checklist including DRY-RUN, backup, no iex ✓
- `.github/dependabot.yml` — GitHub Actions weekly grouped updates ✓
- `.github/SECURITY.md` — responsible disclosure, DRY-RUN security docs, CI enforcement notes ✓
- `.github/CODEOWNERS` — owner required for all files, extra guard on workflows/ ✓
- `.github/REPO_SETTINGS.md` — branch protection docs (cannot be automated, documented) ✓
- `.github/workflows/lint.yml` — PSScriptAnalyzer + parse check, SHA-pinned, least-privilege ✓
- `.github/workflows/security.yml` — secret scan, PS safety patterns, workflow integrity ✓
- `FPSHEAVEN2026.pow` — gitignored, not tracked ✓
- Default branch: `main` ✓
- SHA-pinned actions, `persist-credentials: false`, `permissions: contents: read` ✓
- No `.env` files in project (PS suite, not applicable) ✓
- README quickstart: 3-step Options A (GUI) and B (Terminal) — clear ✓

### Notes:
- Audit spec mentions Python CI (ruff, mypy, pytest, pip-audit) — not applicable. This is a PowerShell project. The equivalent (PSScriptAnalyzer + syntax check) already exists in lint.yml.
- No Makefile needed — `START.bat` and `START-GUI.bat` serve as entry points. PSScriptAnalyzer command documented in CONTRIBUTING.md.
- Pre-commit: not standard for PS projects. CONTRIBUTING.md documents the manual check command.
- `lint.yml` stale version comment (v4.2.2 vs v6.0.2) — cosmetic, not a security issue. Edit blocked by security hook in Loop 2; SHA pin is the actual security mechanism.

---

# Final Opus Review (05-final-opus.md)

## Item F1 — Win32PrioritySeparation quantum description: factual error from mechanical substitution [FIXED]

**File:** `docs/windows-scheduler.md` line 136

**Issue:** Loop 3 (Sonnet) changed `0x26` → `0x2A` throughout the doc but carried over the quantum table description verbatim: "`PspForegroundQuantum[0x2A] = {6,12,18}` — the foreground thread gets 3× the quantum of a background thread." This claim was correct for `0x26` (variable quantum, where the scheduler gives foreground threads a 3× longer time slice) but incorrect for `0x2A` (fixed quantum, where all threads get the same time slice and the foreground advantage is priority-based preemption, not quantum length).

**Fix:** Rewrote the paragraph to correctly describe fixed quantum semantics. The 3× ratio and quantum table now correctly apply to the previous `0x26` value, with an explanation of why `0x2A` (fixed) produces lower 1% low variance.

**Root cause:** This is the exact "Sonnet blind spot" the audit spec predicts — mechanical text substitution where matching a pattern (`0x26` → `0x2A`) without understanding the semantics produces a factual error.

## Item F2 — video-settings.md Network section: deprecated CVars described as functional + wrong CVar name + 4 missing CVars [FIXED]

**File:** `docs/video-settings.md` lines 159-169

**Issues (3 overlapping):**
1. `cl_interp_ratio` and `cl_updaterate` described as "Standard settings since CS:GO" with functional explanations. The code's own `config.env.ps1` comment (lines 112-114) says they're "deprecated in CS2 Source 2... kept as belt-and-suspenders (harmless no-ops)." Doc now matches code.
2. Wrong CVar name: doc said `cl_tickpacket_queuelength`, actual CVar is `cl_tickpacket_desired_queuelength`.
3. Section header says "11 CVars" but only 7 were described. Missing: `cl_interp`, `cl_net_buffer_ticks_use_interp`, `mm_session_search_qos_timeout`, `cl_timeout`. All 11 now covered.

**Root cause:** This section predated the Loop 3 docs audit and was never updated to match `config.env.ps1`. Sonnet's Loop 3 pass added the HUD/QoL and Privacy sections but didn't verify the existing Network section against the actual config.

## Item F3 — CHANGELOG.md: bold violation, fabricated claim, dead link, boilerplate [FIXED]

**File:** `CHANGELOG.md`

**Issues:**
1. Line 34: `**All 8 external tool dependencies eliminated**` — bold mid-sentence, violating the project's own style rule enforced across 18 docs in Loop 3. Removed bold.
2. Line 52: Claimed `FPSHEAVEN2026.pow` was removed "from tracked files" — `git log --all -- FPSHEAVEN2026.pow` returns nothing. The file was never tracked (always gitignored). Reworded to describe what actually changed: the binary dependency was replaced by native `powercfg` calls.
3. Lines 57-66: "Format Reference" section duplicated Keep a Changelog's own documentation (already linked on line 5). The comparison link `HEAD...HEAD` was nonsensical. Removed both.

## Item F4 — Final consistency and "would I ship this" pass [VERIFIED]

**Scope:** All 24 modified files reviewed.

**PS1 code changes (6 files):** All refactoring is mechanical and correct. `Get-IntelHybridCpuName` and `Get-SteamPath` behave identically to the inline code they replaced. The `$steamReg` → `$steamBase` bug fix in Cleanup.ps1 is verified correct. Minor diagnostic info loss in else-branch messages (CPU name no longer shown for non-Intel-hybrid) — acceptable trade-off for deduplication.

**Doc bold style:** 385+ remaining bold instances across 17 docs are all definition-term, table-header, or label style — consistent with Loop 3's rule. No violations found.

**Cross-file consistency:**
- `Win32PrioritySeparation=0x2A` consistent across: Optimize-RegistryTweaks.ps1, Verify-Settings.ps1, config.env.ps1, README.md, evidence.md, debunked.md, windows-scheduler.md, gui.md, step-catalog.ps1, system-analysis.ps1, CHANGELOG.md
- CVar count "74 CVars (10 categories)" consistent across: README.md (×2), evidence.md, gui.md, video-settings.md
- `mouclass queue 50` consistent across: windows-scheduler.md, evidence.md
- Logging infrastructure: unified `Write-Log` pipeline with `Write-OK/Warn/Err/Info/Step/Debug` wrappers used consistently across all 13 helper modules (205 total calls)

**"Would I ship this?" verdict:** Yes. The code is clean, the docs are accurate and internally consistent, the CI is appropriate for the project type, and the three semantic bugs introduced by mechanical substitution (F1, F2) or fabrication (F3) have been fixed.

## Final Review Complete

All files reviewed. Three issues found and fixed across four iterations:
- F1: Win32PrioritySeparation quantum description (semantic error from mechanical 0x26→0x2A replacement)
- F2: video-settings.md Network section (deprecated CVars described as functional, wrong CVar name, 4 missing CVars)
- F3: CHANGELOG.md (bold violation, fabricated git claim, dead link, unnecessary boilerplate)
- F4: Full consistency pass — verified clean
