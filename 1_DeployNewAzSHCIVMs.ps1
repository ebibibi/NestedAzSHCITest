$scriptPath = Split-Path -Parent ($MyInvocation.MyCommand.Path)
$configScript = Join-Path $scriptPath "0_Config.ps1"
. $configScript


Function New-AzSHCIVM {
    param (
        [string]$nodeName,
        [string]$newIP
    )

    New-VM `
        -Name $nodeName  `
        -MemoryStartupBytes $VMMemory `
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

Write-Host "Remove VMs"
foreach($node in $AzSHCINodes) {
    Write-Verbose "Checking $($node.name)"
    $vm = Get-VM $node.name -ErrorAction SilentlyContinue
    If($null -ne $vm){
        Write-Verbose "$($node.name) is present. Removing it..."
        Remove-AzSHCIVM -nodeName $node.name
    }
}

Write-Host "Create and Start VMs"
foreach($node in $AzSHCINodes) {
    New-AzSHCIVM -nodeName $node.name -newIP $node.IPAddress
}

Write-Host "End of 1_DeployNewAzSHCIVMs.ps1"




