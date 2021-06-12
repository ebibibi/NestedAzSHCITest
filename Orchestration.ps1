$scriptPath = Split-Path -Parent ($MyInvocation.MyCommand.Path)
$configScript = Join-Path $scriptPath "0_Config.ps1"
. $configScript

. (Join-Path $scriptPath "1_DeployNewAzSHCIVMs.ps1")
. (Join-Path $scriptPath "2_ConfigureAzSHCIVMs.ps1")


