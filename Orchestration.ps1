$scriptPath = Split-Path -Parent ($MyInvocation.MyCommand.Path)
$configScript = Join-Path $scriptPath "0_Config.ps1"
. $configScript

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


#--------------------------------------------------------------------------
Write-Host "Execute 1_DeployNewAzSHCIVMs.ps1 from Orchestration.ps1"
#--------------------------------------------------------------------------
. (Join-Path $scriptPath "1_DeployNewAzSHCIVMs.ps1")

#--------------------------------------------------------------------------
Write-Host "Execute 2_ConfigureAzSHCIVMs.ps1 as job from Orchestration.ps1"
#--------------------------------------------------------------------------
$script = Join-Path $scriptPath "2_ConfigureAzSHCIVMs.ps1"
#for debug
. $script -nodeName $AzSHCINodes[0].name -IPAddress $AzSHCINodes[0].IPAddress -S2DIPAddress1 $AzSHCINodes[0].S2DIPAddress1 -S2DIPAddress2 $AzSHCINodes[0].S2DIPAddress2
. $script -nodeName $AzSHCINodes[1].name -IPAddress $AzSHCINodes[1].IPAddress -S2DIPAddress1 $AzSHCINodes[1].S2DIPAddress1 -S2DIPAddress2 $AzSHCINodes[1].S2DIPAddress2


get-job "ConfigureAzSHCIVM*" | remove-job -force
$jobs = @()
foreach($AzSHCINode in $AzSHCINodes) {
#    $jobs += Start-Job -Name "ConfigureAzSHCIVM $($AzSHCINode.name)" -scriptblock {. $using:configScript; . $using:script -nodeName $using:AzSHCINode.name -IPAddress $using:AzSHCINode.IPAddress -S2DIPAddress1 $using:AzSHCINode.S2DIPAddress1 -S2DIPAddress2 $using:AzSHCINode.S2DIPAddress2}
}


#WaitMultipleJobs($jobs)


