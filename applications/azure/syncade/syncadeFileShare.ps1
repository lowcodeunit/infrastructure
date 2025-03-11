param
(
      [string]$subscriptionId,
      [string]$storageResourceGroup,
      [string]$storageAccountName
)
try {
    $logFile = "C:\SyncadeSetup.log"
    Write-Output "Starting Script." | Out-File -Append -FilePath $logFile

    # Step 1: Get Authentication Token for Azure REST API
    $metadataUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2020-06-01&resource=https://management.azure.com"
    $tokenResponse = Invoke-RestMethod -Uri $metadataUri -Method GET -Headers @{Metadata="true"}
    $token = $tokenResponse.access_token
 
    if (-not $token) { 
	Write-Output "Failed to retrieve authentication token." | Out-File -Append -FilePath $logFile
        throw "Failed to retrieve authentication token." 
    }
 
    Write-Output "Successfully retrieved authentication token." | Out-File -Append -FilePath $logFile
 
    $headers = @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    }
 
    $storageKeyUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$storageResourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccountName/listKeys?api-version=2021-04-01"
    $storageKeyResponse = Invoke-RestMethod -Uri $storageKeyUri -Method POST -Headers $headers
    $storageKey = $storageKeyResponse.keys[0].value
 
    if (-not $storageKey) { 
	Write-Output "Failed to retrieve storage account key." | Out-File -Append -FilePath $logFile
        throw "Failed to retrieve storage account key." 
    }
 
    Write-Output "Successfully retrieved storage account key." | Out-File -Append -FilePath $logFile
 
    # Step 3: Delete old credentials if they exist
    Write-Output "Deleting old credentials (if any)..." | Out-File -Append -FilePath $logFile
    cmdkey /delete:$storageAccountName.file.core.windows.net
 
    Start-Sleep -Seconds 2
 
    # Step 4: Store credentials in Windows Credential Manager
    Write-Output "Adding new credentials..." | Out-File -Append -FilePath $logFile
    cmdkey /add:$storageAccountName.file.core.windows.net /user:Azure\$storageAccountName /pass:$storageKey
 
    Start-Sleep -Seconds 2
 
    # Step 5: Verify stored credentials
    Write-Output "Verifying stored credentials..." | Out-File -Append -FilePath $logFile
    cmdkey /list | Select-String "$storageAccountName.file.core.windows.net"
 
    if (-not ($?)) { 
        Write-Output "Failed to store credentials properly." | Out-File -Append -FilePath $logFile
        throw "Failed to store credentials properly." 
    }
 
    # Step 6: Map the Z drive
    Write-Output "Mapping the Z drive..." | Out-File -Append -FilePath $logFile
    net use Z: \\$storageAccountName.file.core.windows.net\sharedfiles /user:Azure\$storageAccountName $storageKey /savecred /persistent:yes
 
    Start-Sleep -Seconds 2
 
    # Step 7: Verify the drive mapping
    Write-Output "Verifying the drive mapping..." | Out-File -Append -FilePath $logFile
    net use | Select-String "Z:"
 
    if (-not ($?)) { 
        Write-Output "Failed to map Z drive." | Out-File -Append -FilePath $logFile
    }
 
    # Step 8: Create Scheduled Task for Persistence
    Write-Output "Creating scheduled task..." | Out-File -Append -FilePath $logFile
    schtasks /create /tn "MapZDrive" /tr "cmd /c net use Z: \\$storageAccountName.file.core.windows.net\sharedfiles /user:Azure\$storageAccountName $storageKey  /persistent:yes" /sc onlogon /ru "SYSTEM" /rl highest /f
 
    Write-Output "Z drive mapping and scheduled task setup complete." | Out-File -Append -FilePath $logFile
    exit 0
 
} catch {
    Write-Output "ERROR: $_" | Out-File -Append -FilePath $logFile
    exit 1
}