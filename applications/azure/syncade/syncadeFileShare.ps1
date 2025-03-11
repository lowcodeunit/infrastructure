param (
    [string]$subscriptionId,
    [string]$storageResourceGroup,
    [string]$storageAccountName
)

$logFile = "C:\SyncadeSetup.log"

# Ensure the log file exists and clear its contents before starting
if (Test-Path $logFile) {
    Clear-Content -Path $logFile -Force
} else {
    New-Item -ItemType File -Path $logFile -Force | Out-Null
}

# Function for logging
function Log-Message {
    param ([string]$message)
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timeStamp - $message" | Out-File -Append -FilePath $logFile
}

# Start logging
Log-Message "Starting script execution"

try {
    # Step 1: Retrieve authentication token
    Log-Message "Retrieving authentication token..."
    $metadataUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2020-06-01&resource=https://management.azure.com"
    $tokenResponse = Invoke-RestMethod -Uri $metadataUri -Method GET -Headers @{Metadata="true"}
    $token = $tokenResponse.access_token

    if (-not $token) { 
        Log-Message "ERROR: Failed to retrieve authentication token."
        throw "Failed to retrieve authentication token." 
    }

    Log-Message "Successfully retrieved authentication token."

    $headers = @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    }

    # Step 2: Retrieve Storage Account Key
    Log-Message "Retrieving storage account key..."
    $storageKeyUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$storageResourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccountName/listKeys?api-version=2021-04-01"
    $storageKeyResponse = Invoke-RestMethod -Uri $storageKeyUri -Method POST -Headers $headers
    $storageKey = $storageKeyResponse.keys[0].value

    if (-not $storageKey) { 
        Log-Message "ERROR: Failed to retrieve storage account key."
        throw "Failed to retrieve storage account key." 
    }

    Log-Message "Successfully retrieved storage account key."

    # Step 3: Remove Old Drive Mappings
    Log-Message "Removing existing Z: drive mappings..."
    net use Z: /delete /y
    mountvol Z: /D  # Force-remove orphaned mounts

    # Step 4: Store Credentials Globally
    Log-Message "Storing credentials in Windows Credential Manager..."
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c cmdkey /add:$storageAccountName.file.core.windows.net /user:localhost\$storageAccountName /pass:$storageKey" -NoNewWindow -Wait
    Start-Sleep -Seconds 2

    # Verify credentials were stored
    $credentialCheck = cmdkey /list | Select-String "$storageAccountName.file.core.windows.net"
    if (-not $credentialCheck) {
        Log-Message "ERROR: Failed to store credentials properly in Windows Credential Manager."
        throw "Failed to store credentials properly in Windows Credential Manager."
    }
    Log-Message "Credentials stored successfully."

    # Step 5: Create a Scheduled Task to Ensure Drive Mapping on Startup
    Log-Message "Creating scheduled task for persistence..."
    $taskName = "MapZDrive"

    # Remove existing task if it exists
    schtasks /delete /tn $taskName /f

    # Define the task action
    $taskAction = "cmd /c net use Z: \\$storageAccountName.file.core.windows.net\sharedfiles /user:localhost\$storageAccountName $storageKey /persistent:yes"

    # Create the task under SYSTEM
    $taskCreateCmd = "schtasks /create /tn `"$taskName`" /tr `"$taskAction`" /sc onlogon /ru `"INTERACTIVE`" /rl highest /f"

    Log-Message "Creating task with command: $taskCreateCmd"
    Invoke-Expression $taskCreateCmd

    # Verify task creation
    $taskCheck = schtasks /query /tn $taskName
    if (-not $taskCheck) {
        Log-Message "ERROR: Failed to create scheduled task."
        throw "Failed to create scheduled task."
    }
    Log-Message "Scheduled task created successfully."

    Log-Message "Script completed successfully."
    exit 0

} catch {
    # Log the error before throwing
    Log-Message "ERROR: $_"
    exit 1
}
