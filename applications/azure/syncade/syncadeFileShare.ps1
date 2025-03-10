param
(
      [string]$subscriptionId,
      [string]$storageResourceGroup,
      [string]$storageAccountName
)
try {
    # Step 1: Get Authentication Token for Azure REST API
    $metadataUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2020-06-01&resource=https://management.azure.com"
    $tokenResponse = Invoke-RestMethod -Uri $metadataUri -Method GET -Headers @{Metadata="true"}
    $token = $tokenResponse.access_token
 
    if (-not $token) { 
        throw "Failed to retrieve authentication token." 
    }
 
    Write-Output "Successfully retrieved authentication token."
 
    $headers = @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    }
 
    $storageKeyUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$storageResourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccountName/listKeys?api-version=2021-04-01"
    $storageKeyResponse = Invoke-RestMethod -Uri $storageKeyUri -Method POST -Headers $headers
    $storageKey = $storageKeyResponse.keys[0].value
 
    if (-not $storageKey) { 
        throw "Failed to retrieve storage account key." 
    }
 
    Write-Output "Successfully retrieved storage account key."
 
    # Step 3: Delete old credentials if they exist
    Write-Output "Deleting old credentials (if any)..."
    cmdkey /delete:$storageAccountName.file.core.windows.net
 
    Start-Sleep -Seconds 2
 
    # Step 4: Store credentials in Windows Credential Manager
    Write-Output "Adding new credentials..."
    cmdkey /add:$storageAccountName.file.core.windows.net /user:Azure\$storageAccountName /pass:$storageKey
 
    Start-Sleep -Seconds 2
 
    # Step 5: Verify stored credentials
    Write-Output "Verifying stored credentials..."
    cmdkey /list | Select-String "$storageAccountName.file.core.windows.net"
 
    if (-not ($?)) { 
        throw "Failed to store credentials properly." 
    }
 
    # Step 6: Map the Z drive
    Write-Output "Mapping the Z drive..."
    net use Z: \\$storageAccountName.file.core.windows.net\sharedfiles /user:Azure\$storageAccountName $storageKey /persistent:yes
 
    Start-Sleep -Seconds 2
 
    # Step 7: Verify the drive mapping
    Write-Output "Verifying the drive mapping..."
    net use | Select-String "Z:"
 
    if (-not ($?)) { 
        throw "Failed to map Z drive." 
    }
 
    # Step 8: Create Scheduled Task for Persistence
    Write-Output "Creating scheduled task..."
    schtasks /create /tn "MapZDrive" /tr "cmd /c net use Z: \\$storageAccountName.file.core.windows.net\sharedfiles /user:Azure\$storageAccountName $storageKey /persistent:yes" /sc onlogon /rl highest /f
 
    Write-Output "Z drive mapping and scheduled task setup complete."
    exit 0
 
} catch {
    Write-Output "ERROR: $_"
    exit 1
}