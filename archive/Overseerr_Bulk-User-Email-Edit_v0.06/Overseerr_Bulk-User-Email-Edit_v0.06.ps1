<#
.SYNOPSIS
	Enables specific email notifications for all Overseerr users with interactive selection and legend.

.DESCRIPTION
	This script connects to the Overseerr API and configures email notification settings
	for all users. It allows the user to interactively select which notification types
	to enable or use defaults.
	
	The script provides a detailed summary report at the end, including a human-friendly
	legend that explains the notification bitmask values.
	
	Test mode allows you to preview changes without actually modifying user settings.

.NOTES
	File Name      : Overseerr_Bulk-User-Email-Edit_v0.06.ps1
	Author         : Modified by Antigravity AI Assistant
	Prerequisite   : PowerShell 5.1 or later, network access to Overseerr instance
	Version        : 0.06
	Date           : 2026-01-23 01:52
	
.CHANGELOG
	v0.06 (2026-01-23 01:52)
	- Added human-friendly Notification Legend to the final summary output.
	- Explains bit values 32, 64, and 128 for easier interpretation.
	
	v0.05 (2026-01-23 01:48)
	- Added interactive notification selection logic.
	- Set Verbose mode default to 'Y'.
	- Added detailed summary table.
#>

# Script must run with StrictMode for safety
# Ensure all variables are pre-declared as per Section 1.3
Set-StrictMode -Version Latest

################################################################################
# SECTION: Configuration
################################################################################

# --- CONFIGURATION ---
[string]$OverseerrUrl = "http://192.168.1.20"
[string]$ApiKey = "MTczODE0OTc3NTYwNDk3YWE0NzRiLTJlNzgtNGY2OS1iMWNjLTBkYjE3YmI4YzViZg=="
# ---------------------

# Notification type flags (bitmask values)
[int]$BIT_DECLINED = 32    # Bit 5: Request Declined
[int]$BIT_APPROVED = 64    # Bit 6: Request Approved
[int]$BIT_AVAILABLE = 128   # Bit 7: Request Available

################################################################################
# SECTION: Helper Functions
################################################################################

# Function: Get-UserChoice
# Purpose: Prompts user for Y/N input with automatic timeout and default value
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
	
    [datetime]$startTime = Get-Date
    [string]$response = $null
	
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
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
	
    [string]$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    [string]$logMessage = "[$timestamp] [$Level] $Message"
	
    # Color code based on level
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "TESTMODE" { Write-Host $logMessage -ForegroundColor Magenta }
        default { Write-Host $logMessage -ForegroundColor White }
    }
}

# Function: Get-BitCount
# Purpose: Calculates the number of bits set in an integer (Population Count)
function Get-BitCount {
    param([int]$Value)
    [int]$count = 0
    [int]$v = $Value
    while ($v -gt 0) {
        $v = $v -band ($v - 1)
        $count++
    }
    return $count
}

# Function: Invoke-OverseerrApi
# Purpose: Makes API calls to Overseerr with proper error handling
function Invoke-OverseerrApi {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [hashtable]$Body = $null,
        [bool]$TestMode = $false
    )
	
    if ($TestMode -and ($Method -ne "GET")) {
        Write-Log "[TEST MODE] Would call: $Method $Endpoint" -Level "TESTMODE"
        return [PSCustomObject]@{ success = $true }
    }
	
    [string]$url = "$OverseerrUrl$Endpoint"
    $headers = @{
        "X-Api-Key"    = $ApiKey
        "Content-Type" = "application/json"
    }
	
    try {
        $params = @{
            Uri         = $url
            Method      = $Method
            Headers     = $headers
            ErrorAction = "Stop"
        }
		
        if ($null -ne $Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
		
        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        Write-Log "API call failed: $Method $Endpoint" -Level "ERROR"
        Write-Log "Error: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Function: Get-OverseerrUsers
# Purpose: Retrieves all users from Overseerr with pagination support
function Get-OverseerrUsers {
    param([bool]$TestMode = $false)
	
    Write-Log "Retrieving all users from Overseerr..." -Level "INFO"
    $allUsers = @()
    [int]$pageIndex = 0
    [int]$pageSize = 50
	
    do {
        $response = Invoke-OverseerrApi -Endpoint "/api/v1/user?take=$pageSize&skip=$([int]($pageIndex * $pageSize))" -Method "GET" -TestMode $TestMode
		
        if ($null -eq $response) { return @() }
		
        if ($null -ne $response.results -and @($response.results).Count -gt 0) {
            $allUsers += $response.results
            $pageIndex++
        }
        else { break }
		
        if ($null -ne $response.pageInfo -and $response.pageInfo.pages -le $pageIndex) { break }
    } while ($true)
	
    Write-Log "Retrieved $(@($allUsers).Count) users" -Level "SUCCESS"
    return $allUsers
}

# Function: Update-UserNotifications
# Purpose: Updates notification settings for a specific user
function Update-UserNotifications {
    param(
        [int]$UserId,
        [string]$UserEmail,
        [int]$Mask,
        [bool]$TestMode = $false
    )
	
    $updateBody = @{
        email    = $UserEmail
        settings = @{
            notificationTypes = @{
                email = $Mask
            }
        }
    }
	
    $response = Invoke-OverseerrApi -Endpoint "/api/v1/user/$UserId" -Method "PUT" -Body $updateBody -TestMode $TestMode
    return ($null -ne $response)
}

################################################################################
# SECTION: Main Script Logic
################################################################################

try {
    # Display script header
    Write-Host ""
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host "# Overseerr Bulk User Modifier" -ForegroundColor Cyan
    Write-Host "# Version 0.06" -ForegroundColor Cyan
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host ""
	
    Write-Log "Script started" -Level "INFO"
    Write-Log "Overseerr URL: $OverseerrUrl" -Level "INFO"
    Write-Host ""
	
    # INTERACTIVE PROMPT: Notification Selection
    [int]$finalMask = 0
    [bool]$useDefaults = Get-UserChoice -Prompt "Use default notification settings (32:Declined, 64:Approved, 128:Available)?" -DefaultChoice "Y" -TimeoutSeconds 10
	
    if ($useDefaults) {
        $finalMask = $BIT_DECLINED -bor $BIT_APPROVED -bor $BIT_AVAILABLE
        Write-Log "Selected Mask: $finalMask (Defaults)" -Level "INFO"
    }
    else {
        Write-Host ""
        Write-Log "Custom Selection Mode:" -Level "INFO"
        if (Get-UserChoice -Prompt "  - Enable Bit 32 (Request Declined)?" -DefaultChoice "Y") { $finalMask = $finalMask -bor $BIT_DECLINED }
        if (Get-UserChoice -Prompt "  - Enable Bit 64 (Request Approved)?" -DefaultChoice "Y") { $finalMask = $finalMask -bor $BIT_APPROVED }
        if (Get-UserChoice -Prompt "  - Enable Bit 128 (Request Available)?" -DefaultChoice "Y") { $finalMask = $finalMask -bor $BIT_AVAILABLE }
        Write-Log "Selected Mask: $finalMask" -Level "INFO"
    }
	
    [int]$permissionCount = Get-BitCount -Value $finalMask
    Write-Log "Each successful update will assign $permissionCount permissions." -Level "INFO"
    Write-Host ""
	
    # INTERACTIVE PROMPT: Test Mode
    [bool]$testMode = Get-UserChoice -Prompt "Run in TEST MODE (dry-run without making changes)?" -DefaultChoice "Y" -TimeoutSeconds 10
	
    if ($testMode) {
        Write-Host ""
        Write-Log "########################################" -Level "TESTMODE"
        Write-Log "TEST MODE ENABLED - No changes will be made" -Level "TESTMODE"
        Write-Log "########################################" -Level "TESTMODE"
        Write-Host ""
    }
	
    # INTERACTIVE PROMPT: Verbose Mode (Default: Y)
    [bool]$verboseMode = Get-UserChoice -Prompt "Enable VERBOSE logging (detailed per-user info)?" -DefaultChoice "Y" -TimeoutSeconds 10
    Write-Host ""
	
    # INTERACTIVE PROMPT: Confirmation
    [string]$promptText = if ($testMode) { "Proceed with TEST RUN?" } else { "Proceed with updating ALL users?" }
    [bool]$shouldProceed = Get-UserChoice -Prompt $promptText -DefaultChoice "N" -TimeoutSeconds 10
	
    if (-not $shouldProceed) {
        Write-Log "Operation cancelled by user" -Level "WARNING"
        exit 0
    }
	
    Write-Host ""
	
    # Retrieve all users from Overseerr
    $users = Get-OverseerrUsers -TestMode $testMode
	
    if (@($users).Count -eq 0) {
        Write-Log "No users found. Exiting." -Level "ERROR"
        exit 1
    }
	
    # Results collection for final summary
    $scriptResults = @()
    [int]$successCount = 0
    [int]$failureCount = 0
    [int]$currentIndex = 0
	
    Write-Log "Processing $(@($users).Count) users..." -Level "INFO"
	
    foreach ($user in $users) {
        $currentIndex++
		
        # Progress indicator
        [int]$percentComplete = [int](($currentIndex / @($users).Count) * 100)
        Write-Progress -Activity "Updating Users" -Status "User $currentIndex of $(@($users).Count)" -PercentComplete $percentComplete
		
        if ($verboseMode) {
            Write-Log "Processing: $($user.email) (ID: $($user.id))" -Level "INFO"
        }
		
        # Perform update
        $success = Update-UserNotifications -UserId $user.id -UserEmail $user.email -Mask $finalMask -TestMode $testMode
		
        [string]$updateStatus = "FAIL"
        if ($success) {
            $updateStatus = "OK"
            $successCount++
            if ($verboseMode) { Write-Log "  [OK] Updated $($user.email)" -Level "SUCCESS" }
        }
        else {
            $failureCount++
            Write-Log "  [FAIL] Failed: $($user.email)" -Level "ERROR"
        }
		
        # Add to results collection
        $scriptResults += [PSCustomObject]@{
            Email     = $user.email
            ID        = $user.id
            Mask      = $finalMask
            PermCount = $permissionCount
            Status    = $updateStatus
        }
    }
	
    Write-Progress -Activity "Updating Users" -Completed
	
    # Detailed Summary Table
    Write-Host ""
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host "# DETAILED EXECUTION SUMMARY" -ForegroundColor Cyan
    Write-Host "########################################" -ForegroundColor Cyan
	
    # Output human-friendly Legend
    Write-Host ""
    Write-Host "Notification Mask Legend:" -ForegroundColor Yellow
    Write-Host "  Bit 32  : Request Declined"
    Write-Host "  Bit 64  : Request Approved"
    Write-Host "  Bit 128 : Request Available"
    Write-Host "  ------------------------------------"
    Write-Host "  Total Mask = Sum of enabled bits (e.g., 224 = 32+64+128)"
    Write-Host ""
	
    $scriptResults | Format-Table -Property Email, ID, Mask, PermCount, Status -AutoSize
	
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host "# STATS SUMMARY" -ForegroundColor Cyan
    if ($testMode) { Write-Host "# (TEST MODE - No actual changes made)" -ForegroundColor Magenta }
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Log "Total users: $(@($users).Count)" -Level "INFO"
    Write-Log "Success:     $successCount" -Level "SUCCESS"
    Write-Log "Failure:     $failureCount" -Level "ERROR"
    Write-Host ""
	
    # Exit with status
    if ($failureCount -gt 0) { exit 1 } else { exit 0 }
	
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
