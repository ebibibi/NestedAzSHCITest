param (
    [Parameter(Mandatory=$true)]
    [string]$nodeName,
    [string]$IPAddress,
    [string]$S2DIPAddress1,
    [string]$S2DIPAddress2
)

Write-Host "Start 2_ConfigureAzSHCIVMs.ps1 for $($node.name)"
Write-Verbose $nodeName -Verbose
Write-Verbose $IPAddress -Verbose
Write-Verbose $S2DIPAddress1 -Verbose
Write-Verbose $S2DIPAddress2 -Verbose



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
        [string]$newIPAddress,
        [string]$S2DIPAddress1,
        [string]$S2DIPAddress2
    )
    
    while ((Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
        Write-Host "Waiting for server to set passowrd."
    }

    # Refer to earlier in the script for $nodeName and $newIPAddress
    Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds -ScriptBlock {
        # Set Static IP
        New-NetIPAddress -IPAddress "$using:newIPAddress" -DefaultGateway "$using:defaultGateway" -InterfaceAlias "Ethernet" -PrefixLength "16" | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ($using:DNSServer)
        $nodeIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet" | Select-Object IPAddress
        Rename-NetAdapter -Name "Ethernet" -NewName "Management"
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
        
        # Enable Windows Features
        Install-WindowsFeature -Name File-Services
        Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools
        Install-WindowsFeature -Name Data-Center-Bridging
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


    Write-Verbose "Change NICs setting for S2D" -Verbose
    Invoke-Command -VMName $nodeName -Credential $global:domainCreds -ScriptBlock {
        # Changeing NIC name and Setting Static IP
        Rename-NetAdapter -Name "Ethernet 2" -NewName "S2D NIC 1"
        Rename-NetAdapter -Name "Ethernet 3" -NewName "S2D NIC 2"
        
        New-NetIPAddress -IPAddress "$using:S2DIPAddress1" -InterfaceAlias "S2D NIC 1" -PrefixLength "24" | Out-Null
        New-NetIPAddress -IPAddress "$using:S2DIPAddress2" -InterfaceAlias "S2D NIC 2" -PrefixLength "16" | Out-Null
        
        $nodeIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "S2D NIC 1" | Select-Object IPAddress
        Write-Verbose "The currently assigned IPv4 address for $using:nodeName [S2D NIC 1] is $($nodeIP.IPAddress)" -Verbose 

        $nodeIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "S2D NIC 2" | Select-Object IPAddress
        Write-Verbose "The currently assigned IPv4 address for $using:nodeName [S2D NIC 2] is $($nodeIP.IPAddress)" -Verbose 

    }


    Write-Verbose "Creating vSwitch..." -Verbose
    Invoke-Command -VMName $nodeName -Credential $global:domainCreds -ScriptBlock {
        #create vSwitch for vms
        Rename-NetAdapter -Name "Ethernet 4" -NewName "vSwitch for VMs"
        New-VMSwitch -Name "vSwitch for VMs" -NetAdapterName "vSwitch for VMs" -AllowManagementOS $false
    }

    # Test for the node to be back online and responding
    while ((Invoke-Command -VMName $nodeName -Credential $global:domainCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
    }
    Write-Verbose "$nodeName is now online. Proceed to the next step...." -Verbose


}

Confirm-AzSHCIVM -nodeName $nodeName -newIP $IPAddress -S2DIPAddress1 $S2DIPAddress1 -S2DIPAddress2 $S2DIPAddress2



