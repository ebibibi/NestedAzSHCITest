Function New-AzSHCIVM {
    param (
        [string]$nodeName,
        [string]$newIP
    )

    New-VM `
        -Name $nodeName  `
        -MemoryStartupBytes 64GB `
        -SwitchName "NATSwitch" `
        -Path "D:\Hyper-V\" `
        -NewVHDPath "D:\Hyper-V\$nodeName\Virtual Hard Disks\$nodeName.vhdx" `
        -NewVHDSizeBytes 30GB `
        -Generation 2

    # Disable Dynamic Memory
    Set-VMMemory -VMName $nodeName -DynamicMemoryEnabled $false
    # Add the DVD drive, attach the ISO to DC01 and set the DVD as the first boot device
    $DVD = Add-VMDvdDrive -VMName $nodeName -Path D:\ISOs\AzSHCI.iso -Passthru
    Set-VMFirmware -VMName $nodeName -FirstBootDevice $DVD

    # Set the VM processor count for the VM
    Set-VM -VMname $nodeName -ProcessorCount 16
    # Add the virtual network adapters to the VM and configure appropriately
    1..3 | ForEach-Object { 
        Add-VMNetworkAdapter -VMName $nodeName -SwitchName NatSwitch
        Set-VMNetworkAdapter -VMName $nodeName -MacAddressSpoofing On -AllowTeaming On 
    }
    # Create the DATA virtual hard disks and attach them
    $dataDrives = 1..4 | ForEach-Object { New-VHD -Path "D:\Hyper-V\$nodeName\Virtual Hard Disks\DATA0$_.vhdx" -Dynamic -Size 100GB }
    $dataDrives | ForEach-Object {
        Add-VMHardDiskDrive -Path $_.path -VMName $nodeName
    }
    # Disable checkpoints
    Set-VM -VMName $nodeName -CheckpointType Disabled
    # Enable nested virtualization
    Set-VMProcessor -VMName $nodeName -ExposeVirtualizationExtensions $true -Verbose

    # Open a VM Connect window, and start the VM
    vmconnect.exe localhost $nodeName
    Start-Sleep -Seconds 5
    Start-VM -Name $nodeName
}

Function Confirm-AzSHCIVM {
    param (
        [string]$nodeName,
        [string]$newIP
    )
    
    # Refer to earlier in the script for $nodeName and $newIP
    Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds -ScriptBlock {
        # Set Static IP
        New-NetIPAddress -IPAddress "$using:newIP" -DefaultGateway "192.168.1.254" -InterfaceAlias "Ethernet" -PrefixLength "16" | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("192.168.1.254")
        $nodeIP = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet" | Select-Object IPAddress
        Write-Verbose "The currently assigned IPv4 address for $using:nodeName is $($nodeIP.IPAddress)" -Verbose 
    }

    Invoke-Command -VMName $nodeName -Credential $global:azsHCILocalCreds -ArgumentList $global:domainCreds -ScriptBlock {
        # Change the name and join domain
        Rename-Computer -NewName $Using:nodeName -LocalCredential $Using:azsHCILocalCreds -Force -Verbose
        Start-Sleep -Seconds 5
        Add-Computer -DomainName "test.local" -Credential $Using:domainCreds -Force -Options JoinWithNewName,AccountCreate -Restart -Verbose
    }

    # Test for the node to be back online and responding
    while ((Invoke-Command -VMName $nodeName -Credential $global:domainCreds {"Test"} -ErrorAction SilentlyContinue) -ne "Test") {
        Start-Sleep -Seconds 1
        Write-Host "Waiting for server to come back online"
    }
    Write-Verbose "$nodeName is now online. Proceed to the next step...." -Verbose

    # Provide the domain credentials to log into the VM
    #$domainName = "test.local"
    #$domainAdmin = "$domainName\administrator"
    #$global:domainCreds = Get-Credential -UserName "$domainAdmin" -Message "Enter the password for the domain administrator account"
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

function Remove-AzSHCIVM {
    param (
        [string]$nodeName
    )
    try {
        Stop-VM $nodeName -Force
        Remove-VM $nodeName -Force
        Remove-Item -Path "D:\Hyper-V\$nodeName" -Recurse -Force
    }
    catch {
        
    }

}



Remove-AzSHCIVM -nodeName "AZSHCINODE01"
Remove-AzSHCIVM -nodeName "AZSHCINODE02"


New-AzSHCIVM -nodeName "AZSHCINODE01" -newIP "192.168.1.4"
New-AzSHCIVM -nodeName "AZSHCINODE02" -newIP "192.168.1.5"

Read-Host "全台のVMにOSをインストールして初回ログイン～パスワード設定まで実行してから次に進む"

# Define local credentials
$global:azsHCILocalCreds = Get-Credential -UserName "Administrator" -Message "Enter the password used when you deployed the Azure Stack HCI 20H2 OS"

# Define domain-join credentials
$domainName = "test.local"
$domainAdmin = "$domainName\administrator"
$global:domainCreds = Get-Credential -UserName "$domainAdmin" -Message "Enter the password for the Domain Administrator account"


Confirm-AzSHCIVM -nodeName "AZSHCINODE01" -newIP "192.168.1.4"
Confirm-AzSHCIVM -nodeName "AZSHCINODE02" -newIP "192.168.1.5"





