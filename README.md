# Azure Container Instance to Azure Data Factory

PowerShell script that does the following. Assumes you are already logged into Azure using `Login-AzureRmAccount`.

1. Spins-up one-shot container instance, which stores output file(s) to Azure File storage through volume mounting
2. Kills the container
3. Copies output file(s) to Azure Blob storage, used as a staging area
4. Invokes Azure Data Factory pipeline to manipulate (often ingest) data in output file(s)

Script runs until the Data Factory pipeline is complete. It continuously polls state/status flags during operation, providing feedback on the process as it unfolds.

## Requirements
- Azure PowerShell installed
- One-shot container image that produces output file(s)
- Storage account with file share and blob storage container ready to go
- Credentials (name and key) for the storage account
- Data Factory pipeline connecting the blob (source) to the destination data sink

To use in Azure Automation as a runbook, you will need to load the `AzureRM.ContainerInstance` PowerShell module.

## Script call

`./Invoke-ContainerToDataFactory.ps1 -ContainerImage <String> -ContainerResourceGroup <String> -ContainerName <String> -ContainerVolumeMountPath <String> -StorageAccountResourceGroup <String> -StorageAccountName <String> -StorageAccountKey <SecureString> -FileShareName <String> -BlobContainerName <String> -DataFactoryResourceGroup <String> -DataFactoryName <String> -PipelineName <String>`

### Example
**Container image**: `dockerhubaccount/myimage` hosted at DockerHub

**Container**: To be deployed to existing resource group, `rgcontainer`. Container will be named `mycontainer` when deployed. When it completes running, output files are created in `/out` within the container.

**Storage account**: Already exists within the resource group `rgstorage`, where it is named `mystorage`. The key for the storage account has been assigned as a secure string to `$MyStorageKey`. Within the storage account, the file share to be used is named `myfileshare` and the blob container is `myblobcontainer`.

**Data Factory**: Already created within resource group `rgdatafactory`, where it is named `mydatafactory`. Data Factory contains the pipeline, `mypipeline` which will be invoked to manipulate the data within the output file(s).

**Resulting script call**:

`./Invoke-ContainerToDataFactory.ps1 -ContainerImage dockerhubaccount/myimage -ContainerResourceGroup rgcontainer -ContainerName mycontainer -ContainerVolumeMountPath /out -StorageAccountResourceGroup rgstorage -StorageAccountName mystorage -StorageAccountKey $MyStorageKey -FileShareName myfileshare -BlobContainerName myblobcontainer -DataFactoryResourceGroup rgdatafactory -DataFactoryName mydatafactory -PipelineName mypipeline`

