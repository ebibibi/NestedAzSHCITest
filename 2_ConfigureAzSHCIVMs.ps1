$scriptPath = Split-Path -Parent ($MyInvocation.MyCommand.Path)
$configScript = Join-Path $scriptPath "0_Config.ps1"
. $configScript

# Define local credentials
$password = Get-Content $passwordFile | ConvertTo-SecureString
$global:azsHCILocalCreds = New-Object System.Management.Automation.PSCredential "Administrator",$password

# Define domain-join credentials
$domainName = "test.local"
$domainAdmin = "$domainName\administrator"
$password = Get-Content $passwordFile | ConvertTo-SecureString
$global:domainCreds = New-Object System.Management.Automation.PSCredential "$domainAdmin",$password

foreach($node in $AzSHCINodes) {
    Confirm-AzSHCIVM -nodeName $node.name -newIP $node.IPAddress
}
