# Azure runbook for a contatiner through to Azure Data Factory

PowerShell runbook for Azure Automation. Does the following:

1. Spins-up one-shot container, which stores output file(s) to Azure File storage
2. Kills the container
3. Copies output file(s) to Azure Blob storage, used as a staging area
4. Invokes Azure Data Factory pipeline to manipulate (often ingest) data in output file(s)

Runbook job remains active unitl invoking the ADF pipeline. It continuously polls state/status flags for steps 1-3.
