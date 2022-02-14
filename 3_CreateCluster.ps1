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


Write-Host -ForegroundColor White -BackgroundColor DarkBlue "Log in to the $($AzSHCINodes[0].name) by RDP and run the commands below."
Write-Host -ForegroundColor White -BackgroundColor DarkBlue "I tried to automate this process by PowerShell Direct but I cloudn't. Maybe remote access rights problem."
Write-Host -ForegroundColor White -BackgroundColor DarkRed "Becareful! You have to log in with domain administrator's account!"

Write-Host ""
Write-Host "#---------------------------------------------------------------------------"
Write-Host "#(English version)"
Write-Host "Test-Cluster -Node $AzSHCINodesString –Include `"Storage Spaces Direct`", `"Inventory`", `"Network`", `"System Configuration`""
Write-Host "or"
Write-Host "#(Japanese version)"
Write-Host "Test-Cluster -Node $AzSHCINodesString –Include `"記憶域スペース ダイレクト`", `"インベントリ`", `"ネットワーク`", `"システムの構成`""
Write-Host "Install-WindowsFeature RSAT-DNS-Server" 
Write-Host "Install-WindowsFeature RSAT-AD-PowerShell" 
Write-Host "Remove-DnsServerResourceRecord -ComputerName $DCName -ZoneName $domainname -RRType A -Name $AzSHCIClusterName -force"
Write-Host "Remove-ADComputer -Identity $AzSHCIClusterName -Confirm:`$false"
Write-Host "New-Cluster -Name $AzSHCIClusterName -StaticAddress $AzSHCIClusterIPAddress -Node $AzSHCINodesString"
Write-Host "Enable-ClusterStorageSpacesDirect -PoolFriendlyName S2DPool"
Write-Host "#---------------------------------------------------------------------------"

Read-Host