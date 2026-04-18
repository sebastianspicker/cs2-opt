# ==============================================================================
#  helpers/backup-restore.ps1  —  Setting Backup & Restore System
# ==============================================================================
#
#  Automatically captures registry, service, and boot config state BEFORE
#  modifications. Enables per-step or full rollback if something goes wrong.
#
#  Integration:
#    Set-RegistryValue / Set-BootConfig auto-backup via $SCRIPT:CurrentStepTitle
#    Backup-DrsSettings / Restore-DrsSettings for NVIDIA DRS profile settings
#    Manual: Backup-ServiceState, Restore-StepChanges, Restore-AllChanges

$CFG_BackupFile = "$CFG_WorkDir\backup.json"
$CFG_BackupLockFile = "$CFG_WorkDir\backup.lock"
# Sentinel used when DRS profile was found via app registration rather than by name.
# Must match between Backup-DrsSettings (write) and Restore-DrsSettings (read).
$SCRIPT:DRS_FOUND_VIA_APP = "(found via cs2.exe)"

# ── In-memory batch buffer ─────────────────────────────────────────────────
# Backup entries are accumulated in $SCRIPT:_backupPending during a step, then
# flushed to disk once via Flush-BackupBuffer.  This avoids O(n^2) I/O from
# reading+writing backup.json on every single Set-RegistryValue call (~60+
# calls per full Phase 1 run).  Flush is called automatically by
# Invoke-TieredStep after each step's action completes, and also by any
# function that reads backup data (Get-BackupData) to ensure consistency.
#
# DRY-RUN guard pattern:
#   Every Backup-* function owns its own `if ($SCRIPT:DryRun) { return }` guard
#   as the first statement. Callers should invoke backup capture unconditionally
#   when they have enough context; the backup function itself decides whether the
#   current mode allows persisting an entry.
$SCRIPT:_backupPending = [System.Collections.Generic.List[object]]::new()

. "$PSScriptRoot\backup-restore\core.ps1"
. "$PSScriptRoot\backup-restore\backup-capture.ps1"
. "$PSScriptRoot\backup-restore\restore.ps1"
