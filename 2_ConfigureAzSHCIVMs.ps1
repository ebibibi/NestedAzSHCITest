param (
    [Parameter(Mandatory=$true)]
    [string]$nodeName,
    [string]$IPAddress
)

Write-Host "Start 2_ConfigureAzSHCIVMs.ps1 for $($node.name)"
Write-Verbose $nodeName
Write-Verbose $IPAddress


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


Function Confirm-AzSHCIVM {
    param (
        [string]$nodeName,
        [string]$newIP
    )
    
    while ((Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
        Write-Host "Waiting for server to set passowrd."
    }

    # Refer to earlier in the script for $nodeName and $newIP
    Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds -ScriptBlock {
        # Set Static IP
        New-NetIPAddress -IPAddress "$using:newIP" -DefaultGateway "$using:defaultGateway" -InterfaceAlias "Ethernet" -PrefixLength "16" | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ($using:DNSServer)
        $nodeIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet" | Select-Object IPAddress
        Write-Verbose "The currently assigned IPv4 address for $using:nodeName is $($nodeIP.IPAddress)" -Verbose 
    }

    Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds -ArgumentList $global:domainCreds -ScriptBlock {
        # Change the name and join domain
        Rename-Computer -NewName $Using:nodeName -LocalCredential $Using:azsHCILocalCreds -Force -Verbose
        Start-Sleep -Seconds 5
        Add-Computer -DomainName "$using:domainName" -Credential $Using:domainCreds -Force -Options JoinWithNewName,AccountCreate -Restart -Verbose
    }

    # Test for the node to be back online and responding
    while ((Invoke-Command -VMName $nodeName -Credential $global:domainCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
        Write-Host "Waiting for server to come back online"
    }
    Write-Verbose "$nodeName is now online. Proceed to the next step...." -Verbose

    # Provide the domain credentials to log into the VM
    Invoke-Command -VMName $nodeName -Credential $global:domainCreds -ScriptBlock {
        # Enable the Hyper-V role within the Azure Stack HCI 20H2 OS
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart -Verbose
    }

    Write-Verbose "Rebooting node for changes to take effect" -Verbose
    Stop-VM -Name $nodeName
    Start-Sleep -Seconds 5
    Start-VM -Name $nodeName

    # Test for the node to be back online and responding
    while ((Invoke-Command -VMName $nodeName -Credential $global:domainCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
    }
    Write-Verbose "$nodeName is now online. Proceeding to install Hyper-V PowerShell...." -Verbose

    Invoke-Command -VMName $nodeName -Credential $global:domainCreds -ScriptBlock {
        # Enable the Hyper-V PowerShell within the Azure Stack HCI 20H2 OS
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart -Verbose
    }

    Write-Verbose "Rebooting node for changes to take effect" -Verbose
    Stop-VM -Name $nodeName
    Start-Sleep -Seconds 5
    Start-VM -Name $nodeName

    # Test for the node to be back online and responding
    while ((Invoke-Command -VMName $nodeName -Credential $global:domainCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
    }
    Write-Verbose "$nodeName is now online. Proceed to the next step...." -Verbose

}


Confirm-AzSHCIVM -nodeName $nodeName -newIP $IPAddress
