# Audit Progress Tracker — Round 6

Security + compatibility pass. The tool runs as Administrator — one injection vector = system compromise. 3 loops.

## Loop 1: Security Hardening

### SECURITY-R6 — Admin-Level Attack Surface
- [x] Path injection — FIXED + DOCUMENTED
- [x] Registry injection — FIXED
- [x] Command injection — FIXED
- [x] Driver download — FIXED (HTTPS enforced, Authenticode verification, domain validation)
- [x] Scheduled task — DOCUMENTED (accepted risk: ACLs inherit from C:\, task is InteractiveToken not SYSTEM)
- [x] State file tampering — FIXED (nvidiaDriverPath validated, backup.json paths validated on restore)
- [x] RunOnce tampering — FIXED (path validation) + DOCUMENTED (accepted risk: HKLM requires admin)
- [x] Config dot-sourcing — DOCUMENTED (accepted risk: admin-level file access = system already compromised)

#### Findings Detail

**1. Path Injection** (Medium severity, Low exploitability)
- VDF `libraryfolders.vdf` parsed paths: Added `..` traversal rejection in `Get-CS2InstallPath`
- `nvidiaDriverPath` from state.json: Added traversal + .exe + null byte validation in PostReboot-Setup.ps1
- Symlink/junction on CS2 install path: Accepted risk — cs2.exe existence check mitigates (attacker would need to plant fake cs2.exe)
- `Set-RunOnce` path: Added validation — must be under `C:\CS2_OPTIMIZE\` and end in `.ps1`

**2. Registry Path Injection** (Medium severity, Low exploitability)
- `Set-RegistryValue`: Added hive prefix validation (HKLM:/HKCU:/etc.) and name character validation
- NIC GUID: Added GUID format validation in `Get-ActiveNicGuid` (defense-in-depth — value comes from WMI)
- GPU class key subkeys: Filtered by `^\d{4}$` pattern (already present) — safe
- Restore path in backup.json: Added registry path + name validation to `Restore-StepChanges`

**3. Command Injection** (High severity, Low exploitability)
- `bcdedit /set $key $val`: Added key format (`^[a-zA-Z][a-zA-Z0-9_]*$`) and value format validation
- `pnputil /delete-driver $inf`: Added strict `^oem\d+\.inf$` validation before passing to pnputil
- `powercfg` GUIDs: Added `^[a-fA-F0-9\-]{36}$` GUID format validation in `Set-PowerPlanValue`
- `powercfg` restore from backup.json: Added GUID validation for `originalGuid` in power plan restore
- `bcdedit` restore from backup.json: Added key/value format validation
- `netsh int udp set global uro=disabled`: Hardcoded — safe
- No `Invoke-Expression` usage anywhere — verified clean

**4. Driver Download** (Medium severity, Medium exploitability)
- HTTPS: API query URL is HTTPS (hardcoded). Download URL: added http->https upgrade + nvidia.com domain validation
- Authenticode: Added signature verification — warns if not signed or not NVIDIA-signed, prompts user
- TOCTOU: Accepted risk — window between download and Start-Process is seconds, requires local write access to C:\CS2_OPTIMIZE\ (admin-only)
- Hash: No server-side hash available from NVIDIA's API. Authenticode verification covers integrity.

**5. Scheduled Task** (Medium severity, Low exploitability)
- `cs2_affinity.ps1` in `C:\CS2_OPTIMIZE\`: Directory created by admin, inherits C:\ ACLs (Users: Read+Execute)
- Task runs `HighestAvailable` with `InteractiveToken` — NOT SYSTEM. Blast radius = current user
- Non-admin cannot modify the script (default NTFS ACLs)
- Documented in code comments

**6. State File Tampering** (High severity, Low exploitability)
- `nvidiaDriverPath` -> Start-Process: Added path traversal, .exe, null byte validation + Authenticode check
- `backup.json` registry paths in restore: Added hive prefix + name validation
- `backup.json` bcdedit key/value in restore: Added format validation
- `backup.json` powercfg GUID in restore: Added GUID format validation
- Files in `C:\CS2_OPTIMIZE\`: Admin-only write access via NTFS ACLs

**7. RunOnce Tampering** (Medium severity, Low exploitability)
- RunOnce is in HKLM (requires admin to modify) — prevents non-admin tampering
- Added path validation: script must be under `C:\CS2_OPTIMIZE\` and end in `.ps1`
- Window between phases: attacker would need admin access during reboot → system already compromised
- Added name validation: alphanumeric + underscore only

**8. Config Dot-Sourcing** (Critical severity if exploited, Very Low exploitability)
- Dot-sourcing `config.env.ps1` = arbitrary code execution if file is modified
- Source repo: standard Git checkout permissions
- `C:\CS2_OPTIMIZE\` copy: admin-only write (NTFS inherited ACLs)
- No integrity check performed — accepted risk: attacker with admin file write = system already compromised
- Documented with security header in config.env.ps1 and helpers.ps1

#### Verification
- 203 tests passing (0 failures)
- PSScriptAnalyzer: 0 violations

## Loop 2: Compatibility

### COMPAT-R6 — Windows + PowerShell Version Matrix
- [ ] Windows 10 (1903-22H2) vs Windows 11 (21H2-24H2): any API differences?
- [ ] PowerShell 5.1 vs 7.x: ConvertFrom-Json, Get-CimInstance, Test-Path behavior differences
- [ ] ARM64 Windows: any x64 assumptions? (nvapi64.dll, driver paths)
- [ ] Non-English Windows: any remaining localized string dependencies after R3 locale fixes?
- [ ] Windows Server editions: missing AppX packages, missing services, different defaults
- [ ] Restricted environments: AppLocker, WDAC, Constrained Language Mode — does the tool work?

## Loop 3: Final Gate

### GATE-R6 — Ship Decision
- [ ] PSScriptAnalyzer zero violations
- [ ] 203 tests passing
- [ ] Security findings addressed or documented
- [ ] Compatibility findings addressed or documented
- [ ] Final ship assessment
