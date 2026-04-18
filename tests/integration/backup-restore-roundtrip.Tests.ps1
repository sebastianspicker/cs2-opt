# ==============================================================================
#  tests/integration/backup-restore-roundtrip.Tests.ps1
#  End-to-end roundtrip for backup/restore entry types.
# ==============================================================================
#
#  Core backup types: registry, service, bootconfig, powerplan, drs, scheduledtask
#  Extended backup types: nic_adapter, qos_uro, defender, pagefile, dns
#  Each test: write -> backup.json captures previous -> restore writes back

BeforeAll {
    . "$PSScriptRoot/_IntegrationInit.ps1"
}

AfterAll {
    if ($SCRIPT:TestTempRoot -and (Test-Path $SCRIPT:TestTempRoot)) {
        Remove-Item $SCRIPT:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}



. "$PSScriptRoot\backup-restore-roundtrip\01-registry-backup-and-restore-roundtrip.Tests.ps1"
. "$PSScriptRoot\backup-restore-roundtrip\02-service-backup-and-restore-roundtrip.Tests.ps1"
. "$PSScriptRoot\backup-restore-roundtrip\03-bootconfig-backup-and-restore-roundtrip.Tests.ps1"
. "$PSScriptRoot\backup-restore-roundtrip\04-powerplan-backup-and-restore-roundtrip.Tests.ps1"
. "$PSScriptRoot\backup-restore-roundtrip\05-scheduledtask-backup-and-restore-roundtrip.Tests.ps1"
. "$PSScriptRoot\backup-restore-roundtrip\06-flush-backupbuffer-integration.Tests.ps1"
. "$PSScriptRoot\backup-restore-roundtrip\07-corrupted-backup-json-recovery.Tests.ps1"
