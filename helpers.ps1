# ==============================================================================
#  helpers.ps1  —  Backward-compatible loader (dot-sources all helper modules)
# ==============================================================================

$helpersRoot = "$PSScriptRoot\helpers"

# ── Core modules (CLI + GUI) ──────────────────────────────────────────────
. "$helpersRoot\logging.ps1"
. "$helpersRoot\tier-system.ps1"
. "$helpersRoot\step-state.ps1"
. "$helpersRoot\system-utils.ps1"
. "$helpersRoot\hardware-detect.ps1"
. "$helpersRoot\debloat.ps1"
. "$helpersRoot\msi-interrupts.ps1"
. "$helpersRoot\gpu-driver-clean.ps1"
. "$helpersRoot\nvidia-driver.ps1"
. "$helpersRoot\nvidia-drs.ps1"
. "$helpersRoot\nvidia-profile.ps1"
. "$helpersRoot\backup-restore.ps1"
. "$helpersRoot\benchmark-history.ps1"
. "$helpersRoot\power-plan.ps1"
. "$helpersRoot\process-priority.ps1"
# ── GUI-only modules (loaded separately by CS2-Optimize-GUI.ps1) ──────────
# step-catalog.ps1    — Step metadata table for Optimize panel display
# system-analysis.ps1 — Non-destructive health checks for Analyze panel
