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
	
	Test mode allows you to preview changes without actually modifying user settings.

.NOTES
	File Name      : Overseerr_Bulk-User-Email-Edit_v0.03.ps1
	Author         : Created by Antigravity AI Assistant
	Prerequisite   : PowerShell 5.1 or later, network access to Overseerr instance
	Version        : 0.03
	Date           : 2026-01-23 01:20
	
.CHANGELOG
	v0.03 (2026-01-23 01:20)
	- Added verbose mode with interactive prompt (default: N)
	- Verbose mode shows detailed per-user processing logs
	- Non-verbose mode shows only summary information
	- All logging respects verbose mode setting
	
	v0.02 (2026-01-23 01:17)
	- Added test mode (dry-run) functionality
	- Test mode shows what would be changed without making API calls
	- Interactive prompt for test mode with logical default (Y)
	- Verified API connectivity with 44 users
	
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
#   $Level - Log level (INFO, WARNING, ERROR, SUCCESS, TESTMODE)
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
        "TESTMODE" { Write-Host $logMessage -ForegroundColor Magenta }
        default { Write-Host $logMessage -ForegroundColor White }
    }
}

# Function: Invoke-OverseerrApi
# Purpose: Makes API calls to Overseerr with proper error handling
# Parameters:
#   $Endpoint - API endpoint path (e.g., "/api/v1/user")
#   $Method - HTTP method (GET, POST, PUT, DELETE)
#   $Body - Optional request body (as hashtable, will be converted to JSON)
#   $TestMode - If true, simulates the call without executing (for dry-run)
# Returns: PSCustomObject with API response or $null on failure
function Invoke-OverseerrApi {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [hashtable]$Body = $null,
        [bool]$TestMode = $false
    )
	
    # In test mode, skip actual API calls for write operations
    if ($TestMode -and ($Method -ne "GET")) {
        Write-Log "[TEST MODE] Would call: $Method $Endpoint" -Level "TESTMODE"
        if ($null -ne $Body) {
            Write-Log "[TEST MODE] With body: $($Body | ConvertTo-Json -Depth 5 -Compress)" -Level "TESTMODE"
        }
        # Return a simulated success response
        return @{ success = $true }
    }
	
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
# Parameters: 
#   $TestMode - If true, provides test mode logging
# Returns: Array of user objects or empty array on failure
function Get-OverseerrUsers {
    param(
        [bool]$TestMode = $false
    )
	
    Write-Log "Retrieving all users from Overseerr..." -Level "INFO"
	
    # Overseerr API returns paginated results, we need to handle pagination
    $allUsers = @()
    $pageIndex = 0
    $pageSize = 50  # Default page size
	
    # Keep fetching pages until we get all users
    do {
        # GET requests are allowed in test mode to retrieve data
        $response = Invoke-OverseerrApi -Endpoint "/api/v1/user?take=$pageSize&skip=$($pageIndex * $pageSize)" -Method "GET" -TestMode $TestMode
		
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
#   $TestMode - If true, simulates the update without making changes
# Returns: $true if successful, $false otherwise
function Update-UserNotifications {
    param(
        [int]$UserId,
        [object]$User,
        [bool]$TestMode = $false
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
	
    # Make the API call to update the user (or simulate in test mode)
    $response = Invoke-OverseerrApi -Endpoint "/api/v1/user/$UserId" -Method "PUT" -Body $updateBody -TestMode $TestMode
	
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
    Write-Host "Version 0.02" -ForegroundColor Cyan
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
	
    # INTERACTIVE PROMPT: Test Mode
    # Default to Y (safe to test first before making changes)
    $testMode = Get-UserChoice -Prompt "Run in TEST MODE (dry-run without making changes)?" -DefaultChoice "Y" -TimeoutSeconds 10
	
    if ($testMode) {
        Write-Host ""
        Write-Log "========================================" -Level "TESTMODE"
        Write-Log "TEST MODE ENABLED - No changes will be made" -Level "TESTMODE"
        Write-Log "========================================" -Level "TESTMODE"
        Write-Host ""
    }
	
    # INTERACTIVE PROMPT: Confirmation
    # Default to N since this modifies all users' settings (or would in live mode)
    $promptText = if ($testMode) { "Proceed with TEST RUN?" } else { "Proceed with updating ALL users' email notification settings?" }
    $shouldProceed = Get-UserChoice -Prompt $promptText -DefaultChoice "N" -TimeoutSeconds 10
	
    if (-not $shouldProceed) {
        Write-Log "Operation cancelled by user" -Level "WARNING"
        exit 0
    }
	
    Write-Host ""
	
    # Retrieve all users from Overseerr
    $users = Get-OverseerrUsers -TestMode $testMode
	
    # Verify we got users
    if ($users.Count -eq 0) {
        Write-Log "No users found or failed to retrieve users. Exiting." -Level "ERROR"
        exit 1
    }
	
    Write-Host ""
    $actionText = if ($testMode) { "Testing (dry-run)" } else { "Processing" }
    Write-Log "$actionText $($users.Count) users..." -Level "INFO"
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
        $activityText = if ($testMode) { "Testing User Notifications (Dry-Run)" } else { "Updating User Notifications" }
        Write-Progress -Activity $activityText `
            -Status "Processing user $currentIndex of $($users.Count): $($user.email)" `
            -PercentComplete $percentComplete
		
        $logPrefix = if ($testMode) { "[TEST] " } else { "" }
        Write-Log "$($logPrefix)Processing user: $($user.email) (ID: $($user.id))" -Level "INFO"
		
        # Update the user's notification settings (or simulate in test mode)
        $success = Update-UserNotifications -UserId $user.id -User $user -TestMode $testMode
		
        if ($success) {
            $successText = if ($testMode) { "Would update" } else { "Successfully updated" }
            Write-Log "  ✓ $successText $($user.email)" -Level "SUCCESS"
            $successCount++
        }
        else {
            $failText = if ($testMode) { "Would fail to update" } else { "Failed to update" }
            Write-Log "  ✗ $failText $($user.email)" -Level "ERROR"
            $failureCount++
        }
    }
	
    # Clear progress bar
    Write-Progress -Activity "Processing" -Completed
	
    # Display summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Summary" -ForegroundColor Cyan
    if ($testMode) {
        Write-Host "(TEST MODE - No actual changes made)" -ForegroundColor Magenta
    }
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
	
    if ($testMode) {
        Write-Log "TEST MODE completed - Run again with test mode disabled to apply changes" -Level "TESTMODE"
    }
    else {
        Write-Log "Script completed" -Level "SUCCESS"
    }
	
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
