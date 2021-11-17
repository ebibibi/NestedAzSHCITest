#config
class AzSHCINode {
    [string]$name
    [string]$IPAddress
    [string]$S2DIPAddress1
    [string]$S2DIPAddress2
    AzSHCINode($name, $IPAddress, $S2DIPAddress1, $S2DIPAddress2) { $this.name = $name; $this.IPAddress = $IPAddress; $this.S2DIPAddress1 = $S2DIPAddress1; $this.S2DIPAddress2 = $S2DIPAddress2;}
}

$AzSHCINodes = @()
$AzSHCINodes += New-Object AzSHCINode("AZSHCINODE01","192.168.1.4","10.10.1.1","10.10.2.1")
$AzSHCINodes += New-Object AzSHCINode("AZSHCINODE02","192.168.1.5","10.10.1.2","10.10.2.2")


$VMMemory = 64GB
$VMPath = "D:\Hyper-V\"
$AzSHCI_ISOPATH = "D:\ISOs\AzSHCI.iso"
$VMSwitchName = "NatSwitch"
$defaultGateway = "192.168.1.254"
$DNSServer = "192.168.1.254"
$domainname = "test.local"
$AzSHCIClusterName = "AzSHCI"
$AzSHCIClusterIPAddress = "192.168.1.100"
$DCName = "ADCONNECTTEST"

# Trusted Hosts
Write-Host "you have to allow connecting AZSHCINODEs by TrustedHosts"
Write-Host "example:"
Write-Host "winrm set winrm/config/client '@{TrustedHosts=`"*`"}'"
Write-Host "winrm set winrm/config/client '@{TrustedHosts=`"xxx.xxx.xxx, yyy,yyy,yyy`"}'"

# Get Password
$passwordFile = Join-Path $env:TEMP "password.txt"
if((Test-Path $passwordFile) -eq $false){
    Write-Host "generate password file to $passwordFile ."
    $credential = Get-Credential -UserName "Administrator" -Message "Plase type password of local Administrator and cloud Administrator. This script using same password for both credentials."
    $credential.Password | ConvertFrom-SecureString | Set-Content $passwordFile
} else {
    Write-Host "using password from $passwordFile ."
}

function WaitMultipleJobs($jobs){
    Write-Host "Wait for these jobs"
    get-job -Name "ConfigureAzSHCIVM*"
    $runningJobsCount = 1

    While($runningJobsCount -gt 0){
        $runningJobsCount = 0
        foreach($job in $jobs) {
            if ($job.State -eq "Running") {
                $runningJobsCount += 1
                Write-Host ""
                Write-Host "Job Name $($job.Name) : "
                Receive-Job $job
    
            } elseif ($job.State -eq "Completed") {
                Write-Host ""
                Write-Host "Job Name $($job.Name) : Completed."
            }
            Start-Sleep 5
        }
    }
}