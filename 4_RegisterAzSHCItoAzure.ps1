Write-Host "Start 4_RegisterAzSHCItoAzure.ps1"

$scriptPath = Split-Path -Parent ($MyInvocation.MyCommand.Path)
$configScript = Join-Path $scriptPath "0_Config.ps1"
. $configScript

# Define domain-join credentials
$domainName = "test.local"
$domainAdmin = "$domainName\administrator"
$password = Get-Content $passwordFile | ConvertTo-SecureString
$global:domainCreds = New-Object System.Management.Automation.PSCredential "$domainAdmin",$password



Write-Host -ForegroundColor White -BackgroundColor DarkBlue "Log in to the $($AzSHCINodes[0].name) by RDP and run the commands below."
Write-Host ""
Write-Host "#---------------------------------------------------------------------------"
Write-Host "Install-Module -Name Az.StackHCI"
Write-Host "Register-AzStackHCI  -SubscriptionId $subscriptionID -ComputerName $($AzSHCINodes[0].name)"
Write-Host "#---------------------------------------------------------------------------"

