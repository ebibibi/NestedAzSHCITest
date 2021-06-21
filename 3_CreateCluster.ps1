Write-Host "Start 3_CreateCluster.ps1"

$scriptPath = Split-Path -Parent ($MyInvocation.MyCommand.Path)
$configScript = Join-Path $scriptPath "0_Config.ps1"
. $configScript

# Define domain-join credentials
$domainName = "test.local"
$domainAdmin = "$domainName\administrator"
$password = Get-Content $passwordFile | ConvertTo-SecureString
$global:domainCreds = New-Object System.Management.Automation.PSCredential "$domainAdmin",$password


$AzSHCINodesString = $AzSHCINodes.name | join-string -Separator ','


Write-Host -ForegroundColor White -BackgroundColor DarkBlue "Log in to the $($AzSHCINodes[0].name) and run the commands below."
Write-Host -ForegroundColor White -BackgroundColor DarkRed "Becareful! You have to log in with domain administrator's account!"

Write-Host ""
Write-Host "#---------------------------------------------------------------------------"
Write-Host "Test-Cluster -Node $AzSHCINodesString –Include `"Storage Spaces Direct`", `"Inventory`", `"Network`", `"System Configuration`""
Write-Host "Install-WindowsFeature RSAT-DNS-Server" 
Write-Host "Install-WindowsFeature RSAT-AD-PowerShell" 
Write-Host "try { `Remove-DnsServerResourceRecord -ComputerName $DCName -ZoneName $domainname -RRType A -Name $AzSHCIClusterName force } catch {}"
Write-Host "try { `Remove-ADComputer -Identity $AzSHCIClusterName -Confirm:$false} catch {}"
Write-Host "New-Cluster -Name $AzSHCIClusterName -StaticAddress $AzSHCIClusterIPAddress"
Write-Host "#---------------------------------------------------------------------------"
