#config
class AzSHCINode {
    [string]$name
    [string]$IPAddress
    AzSHCINode($name, $IPAddress) { $this.name = $name; $this.IPAddress = $IPAddress}
}

$AzSHCINodes = @()
$AzSHCINodes += New-Object AzSHCINode("AZSHCINODE01","192.168.1.4")
$AzSHCINodes += New-Object AzSHCINode("AZSHCINODE02","192.168.1.5")


$VMPath = "D:\Hyper-V\"
$AzSHCI_ISOPATH = "D:\ISOs\AzSHCI.iso"
$VMSwitchName = "NatSwitch"
$defaultGateway = "192.168.1.254"
$DNSServer = "192.168.1.254"
$domainname = "test.local"


# Get Password
$passwordFile = Join-Path $env:TEMP "password.txt"
if((Test-Path $passwordFile) -eq $false){
    Write-Host "generate password file to $passwordFile ."
    $credential = Get-Credential -UserName "Administrator" -Message "Plase type password of local Administrator and cloud Administrator. This script using same password for both credentials."
    $credential.Password | ConvertFrom-SecureString | Set-Content $passwordFile
} else {
    Write-Host "using password from $passwordFile ."
}



Function New-AzSHCIVM {
    param (
        [string]$nodeName,
        [string]$newIP
    )

    New-VM `
        -Name $nodeName  `
        -MemoryStartupBytes 64GB `
        -SwitchName $VMSwitchName `
        -Path $VMPath `
        -NewVHDPath "$VMPath$nodeName\Virtual Hard Disks\$nodeName.vhdx" `
        -NewVHDSizeBytes 30GB `
        -Generation 2

    # Disable Dynamic Memory
    Set-VMMemory -VMName $nodeName -DynamicMemoryEnabled $false
    # Add the DVD drive, attach the ISO to DC01 and set the DVD as the first boot device
    $DVD = Add-VMDvdDrive -VMName $nodeName -Path $AzSHCI_ISOPATH -Passthru
    Set-VMFirmware -VMName $nodeName -FirstBootDevice $DVD

    # Set the VM processor count for the VM
    Set-VM -VMname $nodeName -ProcessorCount 16
    # Add the virtual network adapters to the VM and configure appropriately
    1..3 | ForEach-Object { 
        Add-VMNetworkAdapter -VMName $nodeName -SwitchName $VMSwitchName
        Set-VMNetworkAdapter -VMName $nodeName -MacAddressSpoofing On -AllowTeaming On 
    }
    # Create the DATA virtual hard disks and attach them
    $dataDrives = 1..4 | ForEach-Object { New-VHD -Path "$VMPath$nodeName\Virtual Hard Disks\DATA0$_.vhdx" -Dynamic -Size 100GB }
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

function Remove-AzSHCIVM {
    param (
        [string]$nodeName
    )
    try {
        Stop-VM $nodeName -Force
        Remove-VM $nodeName -Force
        Remove-Item -Path "$VMPath$nodeName" -Recurse -Force
    }
    catch {
        
    }

}

foreach($node in $AzSHCINodes) {
    Write-Host "hoge"
    Write-Verbose "Checking $($node.name)"
    $vm = Get-VM $node.name -ErrorAction SilentlyContinue
    If($null -ne $vm){
        Write-Verbose "$($node.name) is present. Removing it..."
        Remove-AzSHCIVM -nodeName $node.name
    }
}


foreach($node in $AzSHCINodes) {
    New-AzSHCIVM -nodeName $node.name -newIP $node.IPAddress
}

Read-Host "Install OS. Change administrator's password. After that, Hit Enter!"

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




