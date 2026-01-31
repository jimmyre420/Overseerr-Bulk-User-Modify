<#
.SYNOPSIS
	Enables specific email notifications for all Overseerr users.

.DESCRIPTION
	This script connects to the Overseerr API and configures email notification settings
	for all users in the system. It enables ONLY the following notification types:
	- Request Approved
	- Request Declined
	- Request Available
	
	All other notification types are explicitly DISABLED to ensure clean configuration.
	The script uses interactive prompts with timeouts instead of parameters, and provides
	detailed progress reporting during execution.

.NOTES
	File Name      : Overseerr_Bulk-User-Email-Edit_v0.01.ps1
	Author         : Created by Antigravity AI Assistant
	Prerequisite   : PowerShell 5.1 or later, network access to Overseerr instance
	Version        : 0.01
	Date           : 2026-01-23 01:09
	
.CHANGELOG
	v0.01 (2026-01-23 01:09)
	- Initial release
	- Enables Request Approved, Request Declined, and Request Available email notifications
	- Disables all other email notification types for clean configuration
	- Interactive prompts with 10-second timeouts
	- Comprehensive error handling and progress reporting
#>

# Script must run with StrictMode for safety
Set-StrictMode -Version Latest

################################################################################
# SECTION: Configuration
################################################################################

# --- CONFIGURATION ---
$OverseerrUrl = "http://192.168.1.20"
$ApiKey = "MTczODE0OTc3NTYwNDk3YWE0NzRiLTJlNzgtNGY2OS1iMWNjLTBkYjE3YmI4YzViZg=="
# ---------------------

# Notification type flags (bitmask values)
# Based on Overseerr's notification system, these are the bit positions
# We want ONLY these three enabled, all others disabled
$NOTIFICATION_REQUEST_APPROVED = 64    # Bit 6: Request Approved
$NOTIFICATION_REQUEST_DECLINED = 32    # Bit 5: Request Declined
$NOTIFICATION_REQUEST_AVAILABLE = 128  # Bit 7: Request Available

# Calculate the combined bitmask for enabled notifications
# This is the ONLY value we want set - all other bits should be 0
$ENABLED_NOTIFICATIONS = $NOTIFICATION_REQUEST_APPROVED -bor $NOTIFICATION_REQUEST_DECLINED -bor $NOTIFICATION_REQUEST_AVAILABLE

################################################################################
# SECTION: Helper Functions
################################################################################

# Function: Get-UserChoice
# Purpose: Prompts user for Y/N input with automatic timeout and default value
# Parameters: 
#   $Prompt - The question to ask the user
#   $DefaultChoice - Default choice if timeout occurs (Y or N)
#   $TimeoutSeconds - Seconds to wait before using default
# Returns: $true if user chose Y, $false if user chose N
function Get-UserChoice {
    param(
        [string]$Prompt,
        [string]$DefaultChoice = "Y",
        [int]$TimeoutSeconds = 10
    )
	
    Write-Host "$Prompt " -NoNewline
    Write-Host "[Y/N]" -ForegroundColor Cyan -NoNewline
    Write-Host " (default: " -NoNewline
    Write-Host $DefaultChoice -ForegroundColor Yellow -NoNewline
    Write-Host " | timeout: $TimeoutSeconds`s): " -NoNewline
	
    $startTime = Get-Date
    $response = $null
	
    # Poll for keyboard input until timeout
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $response = $key.KeyChar.ToString().ToUpper()
            if ($response -eq 'Y' -or $response -eq 'N') {
                Write-Host $response -ForegroundColor Green
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }
	
    # If no response, use default
    if ($null -eq $response) {
        Write-Host $DefaultChoice -ForegroundColor Yellow -NoNewline
        Write-Host " (timeout)"
        $response = $DefaultChoice
    }
	
    return ($response -eq 'Y')
}

# Function: Write-Log
# Purpose: Writes timestamped log messages to console with color coding
# Parameters:
#   $Message - The message to log
#   $Level - Log level (INFO, WARNING, ERROR, SUCCESS)
# Returns: Nothing
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
	
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
	
    # Color code based on level
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor White }
    }
}

# Function: Invoke-OverseerrApi
# Purpose: Makes API calls to Overseerr with proper error handling
# Parameters:
#   $Endpoint - API endpoint path (e.g., "/api/v1/user")
#   $Method - HTTP method (GET, POST, PUT, DELETE)
#   $Body - Optional request body (as hashtable, will be converted to JSON)
# Returns: PSCustomObject with API response or $null on failure
function Invoke-OverseerrApi {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [hashtable]$Body = $null
    )
	
    # Build full URL
    $url = "$OverseerrUrl$Endpoint"
	
    # Prepare headers with API key
    $headers = @{
        "X-Api-Key"    = $ApiKey
        "Content-Type" = "application/json"
    }
	
    try {
        # Build request parameters
        $params = @{
            Uri         = $url
            Method      = $Method
            Headers     = $headers
            ErrorAction = "Stop"
        }
		
        # Add body if provided
        if ($null -ne $Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
		
        # Make API call
        $response = Invoke-RestMethod @params
        return $response
		
    }
    catch {
        # Log detailed error information
        Write-Log "API call failed: $Method $Endpoint" -Level "ERROR"
        Write-Log "Error: $($_.Exception.Message)" -Level "ERROR"
		
        # Check if there's a response with more details
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Log "HTTP Status Code: $statusCode" -Level "ERROR"
        }
		
        return $null
    }
}

# Function: Get-OverseerrUsers
# Purpose: Retrieves all users from Overseerr
# Parameters: None
# Returns: Array of user objects or empty array on failure
function Get-OverseerrUsers {
    Write-Log "Retrieving all users from Overseerr..." -Level "INFO"
	
    # Overseerr API returns paginated results, we need to handle pagination
    $allUsers = @()
    $pageIndex = 0
    $pageSize = 50  # Default page size
	
    # Keep fetching pages until we get all users
    do {
        $response = Invoke-OverseerrApi -Endpoint "/api/v1/user?take=$pageSize&skip=$($pageIndex * $pageSize)" -Method "GET"
		
        if ($null -eq $response) {
            Write-Log "Failed to retrieve users (page $pageIndex)" -Level "ERROR"
            return @()
        }
		
        # Add users from this page
        if ($null -ne $response.results -and $response.results.Count -gt 0) {
            $allUsers += $response.results
            $pageIndex++
        }
        else {
            # No more results
            break
        }
		
        # Safety check: if we've got all users according to pageInfo, stop
        if ($null -ne $response.pageInfo -and $response.pageInfo.pages -le $pageIndex) {
            break
        }
		
    } while ($true)
	
    Write-Log "Retrieved $($allUsers.Count) users" -Level "SUCCESS"
    return $allUsers
}

# Function: Update-UserNotifications
# Purpose: Updates notification settings for a specific user
# Parameters:
#   $UserId - The user ID to update
#   $User - The full user object (needed to preserve other settings)
# Returns: $true if successful, $false otherwise
function Update-UserNotifications {
    param(
        [int]$UserId,
        [object]$User
    )
	
    # IMPORTANT: We're setting the notification flags to an exact value
    # This DISABLES all notification types except the three we want:
    # - Request Approved (bit 6 = 64)
    # - Request Declined (bit 5 = 32)
    # - Request Available (bit 7 = 128)
    # Combined: 64 + 32 + 128 = 224
	
    # Build the update payload
    # We need to send the complete user object with modifications
    $updateBody = @{
        email    = $User.email
        # Set email notifications to ONLY the enabled flags (disables all others)
        settings = @{
            notificationTypes = @{
                email = $ENABLED_NOTIFICATIONS
            }
        }
    }
	
    # Make the API call to update the user
    $response = Invoke-OverseerrApi -Endpoint "/api/v1/user/$UserId" -Method "PUT" -Body $updateBody
	
    if ($null -ne $response) {
        return $true
    }
    else {
        return $false
    }
}

################################################################################
# SECTION: Main Script Logic
################################################################################

try {
    # Display script header
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Overseerr Bulk User Modifier" -ForegroundColor Cyan
    Write-Host "Version 0.01" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
	
    Write-Log "Script started" -Level "INFO"
    Write-Log "Overseerr URL: $OverseerrUrl" -Level "INFO"
    Write-Host ""
	
    Write-Log "This script will enable ONLY these email notifications:" -Level "INFO"
    Write-Log "  - Request Approved" -Level "INFO"
    Write-Log "  - Request Declined" -Level "INFO"
    Write-Log "  - Request Available" -Level "INFO"
    Write-Log "All other email notifications will be DISABLED." -Level "WARNING"
    Write-Host ""
	
    # Prompt user for confirmation before proceeding
    # Default to N since this modifies all users' settings
    $shouldProceed = Get-UserChoice -Prompt "Proceed with updating ALL users' email notification settings?" -DefaultChoice "N" -TimeoutSeconds 10
	
    if (-not $shouldProceed) {
        Write-Log "Operation cancelled by user" -Level "WARNING"
        exit 0
    }
	
    Write-Host ""
	
    # Retrieve all users from Overseerr
    $users = Get-OverseerrUsers
	
    # Verify we got users
    if ($users.Count -eq 0) {
        Write-Log "No users found or failed to retrieve users. Exiting." -Level "ERROR"
        exit 1
    }
	
    Write-Host ""
    Write-Log "Processing $($users.Count) users..." -Level "INFO"
    Write-Host ""
	
    # Counters for summary
    $successCount = 0
    $failureCount = 0
    $currentIndex = 0
	
    # Process each user
    foreach ($user in $users) {
        $currentIndex++
		
        # Show progress
        $percentComplete = [int](($currentIndex / $users.Count) * 100)
        Write-Progress -Activity "Updating User Notifications" `
            -Status "Processing user $currentIndex of $($users.Count): $($user.email)" `
            -PercentComplete $percentComplete
		
        Write-Log "Processing user: $($user.email) (ID: $($user.id))" -Level "INFO"
		
        # Update the user's notification settings
        $success = Update-UserNotifications -UserId $user.id -User $user
		
        if ($success) {
            Write-Log "  ✓ Successfully updated $($user.email)" -Level "SUCCESS"
            $successCount++
        }
        else {
            Write-Log "  ✗ Failed to update $($user.email)" -Level "ERROR"
            $failureCount++
        }
    }
	
    # Clear progress bar
    Write-Progress -Activity "Updating User Notifications" -Completed
	
    # Display summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "Total users processed: $($users.Count)" -Level "INFO"
    Write-Log "Successful updates: $successCount" -Level "SUCCESS"
	
    if ($failureCount -gt 0) {
        Write-Log "Failed updates: $failureCount" -Level "ERROR"
    }
    else {
        Write-Log "Failed updates: 0" -Level "INFO"
    }
	
    Write-Host ""
    Write-Log "Script completed" -Level "SUCCESS"
	
    # Exit with appropriate code
    if ($failureCount -gt 0) {
        exit 1
    }
    else {
        exit 0
    }
	
}
catch {
    # Catch any unexpected errors
    Write-Log "Unexpected error occurred: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
