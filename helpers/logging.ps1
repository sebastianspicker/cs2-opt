# ==============================================================================
#  helpers/logging.ps1  —  Logging, Console Output, Banners
# ==============================================================================

function Initialize-Log {
    Ensure-Dir $CFG_LogDir
    if (Test-Path $CFG_LogFile) {
        $stamp   = (Get-Item $CFG_LogFile).LastWriteTime.ToString("yyyyMMdd_HHmmss")
        Move-Item $CFG_LogFile "$CFG_LogDir\optimize_$stamp.log" -Force
        Get-ChildItem $CFG_LogDir -Filter "optimize_*.log" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $CFG_LogMaxFiles |
            Remove-Item -Force
    }
    Set-Content $CFG_LogFile @"
================================================================================
  CS2 Optimization Suite · Log
  Started:    $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Profile:    $($SCRIPT:Profile)   Mode: $($SCRIPT:Mode)   Log: $($SCRIPT:LogLevel)
  Host:       $env:COMPUTERNAME     User:  $env:USERNAME
  Windows:    $([System.Environment]::OSVersion.VersionString)
================================================================================
"@ -Encoding UTF8
}

function Write-Log($Level, $Message) {
    $ts      = Get-Date -Format "HH:mm:ss"
    $logLine = "[$ts][$Level] $Message"
    if ($CFG_LogFile -and (Test-Path $CFG_LogDir -ErrorAction SilentlyContinue)) {
        Add-Content $CFG_LogFile $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    $show = switch ($SCRIPT:LogLevel) {
        "MINIMAL" { $Level -in @("ERROR","WARN","OK","INFO","SECTION","STEP","T1","T2","T3") }
        "NORMAL"  { $Level -notin @("DEBUG") }
        default   { $true }
    }
    if (-not $show) { return }
    $color = switch ($Level) {
        "OK"      { "Green" };    "WARN"    { "DarkYellow" }
        "ERROR"   { "Red" };      "STEP"    { "Yellow" }
        "SECTION" { "Cyan" };     "DEBUG"   { "DarkGray" }
        "T1"      { "Green" };    "T2"      { "Yellow" }
        "T3"      { "DarkGray" }; default   { "DarkGray" }
    }
    $prefix = switch ($Level) {
        "OK"      { "  ✔" }; "WARN"    { "  ⚠" }; "ERROR"   { "  ✘" }
        "STEP"    { "  ►" }; "SECTION" { "  ║" };  "DEBUG"   { "   " }
        "T1"      { "  ►" }; "T2"      { "  ►" };  "T3"      { "  ·" }
        default   { "   " }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Write-OK($t)       { Write-Log "OK"      $t }
function Write-Warn($t)     { Write-Log "WARN"    $t }
function Write-Err($t)      { Write-Log "ERROR"   $t }
function Write-Step($t)     { Write-Log "STEP"    $t }
function Write-Info($t)     { Write-Log "INFO"    $t }
function Write-Debug($t)    { Write-Log "DEBUG"   $t }
function Write-Blank()      { Write-Host "" }
function Write-Sub($t)      { Write-Host "  · $t" -ForegroundColor White }

function Write-TierBadge($tier, $label) {
    $color = switch ($tier) { 1 {"Green"} 2 {"Yellow"} 3 {"DarkGray"} default {"White"} }
    $badge = switch ($tier) {
        1 { "[T1 · Proven Effect]" }
        2 { "[T2 · Setup-Dependent]" }
        3 { "[T3 · Community Consensus]" }
        default { "[T? · Unknown Tier]" }
    }
    Write-Host "  $badge  $label" -ForegroundColor $color
    Write-Log "T$tier" "$label"
}

function Write-RiskBadge($risk) {
    $color = switch ($risk) { "SAFE" {"Green"} "MODERATE" {"Yellow"} "AGGRESSIVE" {"DarkYellow"} "CRITICAL" {"Red"} default {"White"} }
    $icon  = switch ($risk) { "SAFE" {"$([char]0x2714)"} "MODERATE" {"$([char]0x25B2)"} "AGGRESSIVE" {"$([char]0x25C6)"} "CRITICAL" {"$([char]0x2718)"} default {"?"} }
    Write-Host "  $icon $risk" -ForegroundColor $color -NoNewline
}

function Write-Section($title) {
    $pad = "═" * ($title.Length + 4)
    Write-Host "`n  ╔$pad╗" -ForegroundColor DarkCyan
    Write-Host "  ║  $title  ║" -ForegroundColor Cyan
    Write-Host "  ╚$pad╝" -ForegroundColor DarkCyan
    Write-Log "SECTION" "=== $title ==="
}

function Write-ToolInfo($name, $author, $purpose, $source, $trust) {
    Write-Blank
    Write-Host "  ┌─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  │  Tool:     $name" -ForegroundColor White
    Write-Host "  │  Author:   $author" -ForegroundColor DarkGray
    Write-Host "  │  Purpose:  $purpose" -ForegroundColor DarkGray
    Write-Host "  │  Source:   $source" -ForegroundColor DarkGray
    Write-Host "  │  Trust:    $trust" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Log "DEBUG" "Tool: $name | $source"
    Write-Blank
}

function Write-LogoBanner($subtitle) {
    <#  Lightweight banner: ASCII logo + subtitle. For entry-point scripts that
        don't need the full phase banner (Cleanup, FpsCap, Verify, etc.).  #>
    Clear-Host
    Write-Host @"

  ██████╗███████╗██████╗      ██████╗ ██████╗ ████████╗
 ██╔════╝██╔════╝╚════██╗    ██╔═══██╗██╔══██╗╚══██╔══╝
 ██║     ███████╗ █████╔╝    ██║   ██║██████╔╝   ██║
 ██║     ╚════██║██╔═══╝     ██║   ██║██╔═══╝    ██║
 ╚██████╗███████║███████╗    ╚██████╔╝██║        ██║
  ╚═════╝╚══════╝╚══════╝     ╚═════╝ ╚═╝        ╚═╝

         $subtitle
"@ -ForegroundColor Cyan
}

function Write-Banner($phase, $total, $subtitle) {
    Clear-Host
    $profileTag = if ($SCRIPT:Profile) { "[$($SCRIPT:Profile)]" } else { "[$($SCRIPT:Mode)]" }
    $levelTag   = "[LOG:$($SCRIPT:LogLevel)]"
    Write-Host @"

  ██████╗███████╗██████╗      ██████╗ ██████╗ ████████╗
 ██╔════╝██╔════╝╚════██╗    ██╔═══██╗██╔══██╗╚══██╔══╝
 ██║     ███████╗ █████╔╝    ██║   ██║██████╔╝   ██║
 ██║     ╚════██║██╔═══╝     ██║   ██║██╔═══╝    ██║
 ╚██████╗███████║███████╗    ╚██████╔╝██║        ██║
  ╚═════╝╚══════╝╚══════╝     ╚═════╝ ╚═╝        ╚═╝
"@ -ForegroundColor Cyan
    Write-Host "  Phase $phase / $total  ·  $subtitle" -ForegroundColor Cyan
    Write-Host "  $profileTag $levelTag  ·  Log: $CFG_LogFile" -ForegroundColor DarkGray
    if ($SCRIPT:DryRun) {
        Write-Host "  [DRY-RUN] Preview mode — NO changes will be applied" -ForegroundColor Magenta
    }
    $profileDesc = switch ($SCRIPT:Profile) {
        "SAFE"        { "T1 auto + T2(safe) auto. Moderate/aggressive skipped." }
        "RECOMMENDED" { "T1 auto. T2 prompted. T3 skipped." }
        "COMPETITIVE" { "T1 auto. T2+T3 prompted (up to AGGRESSIVE)." }
        "CUSTOM"      { "Everything prompted with full detail cards." }
        default       { "" }
    }
    if ($profileDesc) {
        Write-Host "  Profile: $profileDesc" -ForegroundColor DarkGray
    }
    Write-Host "" ; Write-Host "  Tier Legend:" -ForegroundColor DarkGray
    Write-Host "  [T1] Proven effect — auto-applied" -ForegroundColor Green
    Write-Host "  [T2] Setup-dependent — profile-dependent" -ForegroundColor Yellow
    Write-Host "  [T3] Community tip — COMPETITIVE/CUSTOM only" -ForegroundColor DarkGray
    Write-Host "  Risk: $([char]0x2714) SAFE  $([char]0x25B2) MODERATE  $([char]0x25C6) AGGRESSIVE  $([char]0x2718) CRITICAL" -ForegroundColor DarkGray
    Write-Host "  $("─" * 60)" -ForegroundColor DarkGray
    Write-Host "  DISCLAIMER: Use at your own risk. We take no responsibility" -ForegroundColor DarkRed
    Write-Host "  for any damage whatsoever. Always create a restore point." -ForegroundColor DarkRed
    Write-Host "  $("─" * 60)" -ForegroundColor DarkGray
    Write-Blank
}
