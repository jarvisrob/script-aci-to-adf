
[CmdletBinding()]
Param(
    [switch] $AsRunbook,

    [Parameter(Mandatory=$True)]
    [string] $ContainerImage,

    [Parameter(Mandatory=$True)]
    [string] $ContainerResourceGroup,

    [Parameter(Mandatory=$True)]
    [string] $ContainerName,

    [Parameter(Mandatory=$True)]
    [string] $ContainerVolumeMountPath,
    
    [Parameter(Mandatory=$True)]
    [string] $StorageAccountResourceGroup,

    [string] $StorageAccountName,

    [SecureString] $StorageAccountKey,

    [string] $StorageCredentialName,

    [Parameter(Mandatory=$True)]
    [string] $FileShareName,

    [Parameter(Mandatory=$True)]
    [string] $BlobContainerName,

    [Parameter(Mandatory=$True)]
    [string] $DataFactoryResourceGroup,

    [Parameter(Mandatory=$True)]
    [string] $DataFactoryName,

    [Parameter(Mandatory=$True)]
    [string] $PipelineName
)


# Naming the file produced
$y = Get-Date -UFormat %Y
$m = Get-Date -UFormat %m
$d = Get-Date -UFormat %d
$OutFileName = "reiv_$y-$m-$d.csv"


If ($AsRunbook) {

    $connectionName = "AzureRunAsConnection"
    try
    {
        # Get the connection "AzureRunAsConnection"
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

        "Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

    $StorageAccountCredential = Get-AutomationPSCredential -Name $StorageCredentialName

} Else {
    $StorageAccountCredential = New-Object System.Management.Automation.PSCredential ($StorageAccountName, $StorageAccountKey)
}


# Spin-up the container
Write-Output "Spinning up container"
New-AzureRmContainerGroup -ResourceGroupName $ContainerResourceGroup -Name $ContainerName -Image $ContainerImage -RestartPolicy Never -AzureFileVolumeShareName $FileShareName -AzureFileVolumeAccountCredential $StorageAccountCredential -AzureFileVolumeMountPath $ContainerVolumeMountPath -Command "python /app/scrape_reiv.py $OutFileName"

# Poll the container, waiting for it to finish running, and kill once finished
$ContainerInfo = Get-AzureRmContainerGroup -ResourceGroupName $ContainerResourceGroup -Name $ContainerName
While (-not (($ContainerInfo.State -eq "Succeeded") -or ($ContainerInfo.State -eq "Failed"))) {
    Write-Output "Waiting ... Container state: $($ContainerInfo.State)"
    Start-Sleep -Seconds 10
    $ContainerInfo = Get-AzureRmContainerGroup -ResourceGroupName $ContainerResourceGroup -Name $ContainerName
}
If ($ContainerInfo.State -eq "Succeeded") {
    Write-Output "Container finished. Final instance log:"
    Get-AzureRmContainerInstanceLog -ResourceGroupName $ContainerResourceGroup -ContainerGroupName $ContainerName -Tail 20
    Write-Output "Killing container"
    Remove-AzureRmContainerGroup -ResourceGroupName $ContainerResourceGroup -Name $ContainerName
} Else {
    Write-Output "ERROR: Container failed. Exiting script."
    $ContainerInfo
    Exit
}

# Copy file(s) from file storage to blob
Write-Output "Copying file(s) to staging blob"
Set-AzureRmCurrentStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name  $StorageAccountCredential.UserName
Start-AzureStorageBlobCopy -SrcShareName $FileShareName -SrcFilePath "/$OutFileName" -DestContainer $BlobContainerName
$BlobCopyState = Get-AzureStorageBlobCopyState -Blob $OutFileName -Container $BlobContainerName
While (-not (($BlobCopyState.Status -eq "Success") -or ($BlobCopyState.Status -eq "Failed"))) {
    Write-Output "Waiting ... Blob copy status: $($BlobCopyState.Status)"
    Start-Sleep -Seconds 2
    $BlobCopyState = Get-AzureStorageBlobCopyState -Blob $OutFileName -Container $BlobContainerName
}
If ($BlobCopyState.Status -eq "Success") {
    Write-Output "Copy complete"
} Else {
    Write-Output "ERROR: Copy failed. Exiting script."
    $BlobCopyState
    Exit
}

# Invoke the Data Factory pipeline
Write-Output "Invoking the Data Factory pipeline"
$PipelineRunId = Invoke-AzureRmDataFactoryV2Pipeline -ResourceGroupName $DataFactoryResourceGroup -DataFactoryName $DataFactoryName -PipelineName $PipelineName

# Poll and monitor the pipeline run until succeeded
$PipelineRunInfo = Get-AzureRmDataFactoryV2PipelineRun -ResourceGroupName $DataFactoryResourceGroup -DataFactoryName $DataFactoryName -PipelineRunId $PipelineRunId
While (-not (($PipelineRunInfo.Status -eq "Succeeded") -or ($PipelineRunInfo.Status -eq "Failed"))) {
    Write-Output "Waiting ... Pipeline status: $($PipelineRunInfo.Status)"
    Start-Sleep -Seconds 10
    $PipelineRunInfo = Get-AzureRmDataFactoryV2PipelineRun -ResourceGroupName $DataFactoryResourceGroup -DataFactoryName $DataFactoryName -PipelineRunId $PipelineRunId
}
If ($PipelineRunInfo.Status -eq "Succeeded") {
    Write-Output "Pipline run complete"
} Else {
    Write-Output "ERROR: Pipeline run failed. Exiting script."
    $PipelineRunInfo
    Exit
}

Write-Output "Script completed"
