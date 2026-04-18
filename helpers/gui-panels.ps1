# ==============================================================================
#  helpers/gui-panels.ps1  —  GUI Panel Functions & Event Handlers
# ==============================================================================

$Script:DashboardLastLoad = [datetime]::MinValue
$Script:StartupDriftChecked = $false

. "$PSScriptRoot\gui-panels\state-drift.ps1"
. "$PSScriptRoot\gui-panels\dashboard-analyze.ps1"
. "$PSScriptRoot\gui-panels\optimize-backup.ps1"
. "$PSScriptRoot\gui-panels\benchmark-network.ps1"
. "$PSScriptRoot\gui-panels\video-settings.ps1"

(El "BtnOptPhase2").Add_Click({ Launch-Terminal "Boot-SafeMode.ps1" })
