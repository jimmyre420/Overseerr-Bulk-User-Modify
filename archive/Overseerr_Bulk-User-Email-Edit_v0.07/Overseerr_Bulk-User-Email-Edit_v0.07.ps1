<#
.SYNOPSIS
	Enables specific email notifications for all Overseerr users with corrected API endpoints.

.DESCRIPTION
	This script connects to the Overseerr API and configures email notification settings
	for all users. It fixes the '400 Bad Request' seen in previous versions by using
	the correct specific notification settings endpoint.
	
	The script allows the user to interactively select which notification types
	to enable or use defaults.

.NOTES
	File Name      : Overseerr_Bulk-User-Email-Edit_v0.07.ps1
	Author         : Modified by Antigravity AI Assistant
	Prerequisite   : PowerShell 5.1 or later, network access to Overseerr instance
	Version        : 0.07
	Date           : 2026-01-23 02:04
	
.CHANGELOG
	v0.07 (2026-01-23 02:04)
	- Fixed '400 Bad Request' by switching to specific notification settings endpoint.
	- Corrected notification bitmask values (Approved=2, Declined=16, Available=4).
	- Updated Legend to reflect the correct API bit values.
	- Updated default mask to 22 (2+16+4).
	
	v0.06 (2026-01-23 01:52)
	- Added human-friendly notification legend.
#>

Set-StrictMode -Version Latest

################################################################################
# SECTION: Configuration
################################################################################

[string]$OverseerrUrl = "http://192.168.1.20"
[string]$ApiKey = "MTczODE0OTc3NTYwNDk3YWE0NzRiLTJlNzgtNGY2OS1iMWNjLTBkYjE3YmI4YzViZg=="

# CORRECT Bitmask values based on Overseerr API schema:
[int]$BIT_APPROVED = 2     # MEDIA_APPROVED
[int]$BIT_AVAILABLE = 4     # MEDIA_AVAILABLE
[int]$BIT_DECLINED = 16    # MEDIA_DECLINED

################################################################################
# SECTION: Helper Functions
################################################################################

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
	
    if ($null -eq $response) {
        Write-Host $DefaultChoice -ForegroundColor Yellow -NoNewline
        Write-Host " (timeout)"
        $response = $DefaultChoice
    }
	
    return ($response -eq 'Y')
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
	
    [string]$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    [string]$logMessage = "[$timestamp] [$Level] $Message"
	
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "TESTMODE" { Write-Host $logMessage -ForegroundColor Magenta }
        default { Write-Host $logMessage -ForegroundColor White }
    }
}

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

function Invoke-OverseerrApi {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [hashtable]$Body = $null,
        [bool]$TestMode = $false
    )
	
    if ($TestMode -and ($Method -ne "GET")) {
        Write-Log "[TEST MODE] Would call: $Method $Endpoint" -Level "TESTMODE"
        if ($null -ne $Body) { Write-Log "[TEST MODE] Payload: $($Body | ConvertTo-Json -Depth 5 -Compress)" -Level "TESTMODE" }
        return [PSCustomObject]@{ success = $true }
    }
	
    [string]$url = "$OverseerrUrl$Endpoint"
    $headers = @{
        "X-Api-Key"    = $ApiKey
        "Content-Type" = "application/json"
        "Accept"       = "application/json"
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
		
        if ($null -ne $_.Exception.Response) {
            try {
                $streamReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errBody = $streamReader.ReadToEnd()
                Write-Log "Response Body: $errBody" -Level "ERROR"
            }
            catch {}
        }
		
        return $null
    }
}

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

function Update-UserNotifications {
    param(
        [int]$UserId,
        [int]$Mask,
        [bool]$TestMode = $false
    )
	
    # Payload structure for specific notification settings endpoint
    $updateBody = @{
        emailEnabled      = $true
        notificationTypes = @{
            email = $Mask
        }
    }
	
    # Correct endpoint for notification settings is POST /api/v1/user/{id}/settings/notifications
    $response = Invoke-OverseerrApi -Endpoint "/api/v1/user/$UserId/settings/notifications" -Method "POST" -Body $updateBody -TestMode $TestMode
    return ($null -ne $response)
}

################################################################################
# SECTION: Main Script Logic
################################################################################

try {
    Write-Host ""
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host "# Overseerr Bulk User Modifier" -ForegroundColor Cyan
    Write-Host "# Version 0.07" -ForegroundColor Cyan
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host ""
	
    Write-Log "Script started" -Level "INFO"
    Write-Log "Overseerr URL: $OverseerrUrl" -Level "INFO"
    Write-Host ""
	
    # INTERACTIVE PROMPT: Notification Selection
    [int]$finalMask = 0
    [bool]$useDefaults = Get-UserChoice -Prompt "Use default notification settings (2:Approved, 16:Declined, 4:Available)?" -DefaultChoice "Y" -TimeoutSeconds 10
	
    if ($useDefaults) {
        $finalMask = $BIT_APPROVED -bor $BIT_DECLINED -bor $BIT_AVAILABLE
        Write-Log "Selected Mask: $finalMask (Defaults)" -Level "INFO"
    }
    else {
        Write-Host ""
        Write-Log "Custom Selection Mode:" -Level "INFO"
        if (Get-UserChoice -Prompt "  - Enable Bit 2  (Request Approved)?" -DefaultChoice "Y") { $finalMask = $finalMask -bor $BIT_APPROVED }
        if (Get-UserChoice -Prompt "  - Enable Bit 16 (Request Declined)?" -DefaultChoice "Y") { $finalMask = $finalMask -bor $BIT_DECLINED }
        if (Get-UserChoice -Prompt "  - Enable Bit 4  (Request Available)?" -DefaultChoice "Y") { $finalMask = $finalMask -bor $BIT_AVAILABLE }
        Write-Log "Selected Mask: $finalMask" -Level "INFO"
    }
	
    [int]$permissionCount = Get-BitCount -Value $finalMask
    Write-Log "Each successful update will assign $permissionCount permissions." -Level "INFO"
    Write-Host ""
	
    [bool]$testMode = Get-UserChoice -Prompt "Run in TEST MODE (dry-run)?" -DefaultChoice "Y" -TimeoutSeconds 10
    if ($testMode) {
        Write-Host ""
        Write-Log "TEST MODE ENABLED - No changes will be made" -Level "TESTMODE"
        Write-Host ""
    }
	
    [bool]$verboseMode = Get-UserChoice -Prompt "Enable VERBOSE logging?" -DefaultChoice "Y" -TimeoutSeconds 10
    Write-Host ""
	
    [bool]$shouldProceed = Get-UserChoice -Prompt "Proceed with processing users?" -DefaultChoice "N" -TimeoutSeconds 10
    if (-not $shouldProceed) {
        Write-Log "Operation cancelled" -Level "WARNING"
        exit 0
    }
	
    $users = Get-OverseerrUsers -TestMode $testMode
    if (@($users).Count -eq 0) {
        Write-Log "No users found. Exiting." -Level "ERROR"
        exit 1
    }
	
    $scriptResults = @()
    [int]$successCount = 0
    [int]$failureCount = 0
    [int]$currentIndex = 0
	
    Write-Log "Processing $(@($users).Count) users..." -Level "INFO"
	
    foreach ($user in $users) {
        $currentIndex++
        Write-Progress -Activity "Updating Users" -Status "User $currentIndex of $(@($users).Count)" -PercentComplete ([int](($currentIndex / @($users).Count) * 100))
		
        if ($verboseMode) { Write-Log "Processing: $($user.email) (ID: $($user.id))" -Level "INFO" }
		
        $success = Update-UserNotifications -UserId $user.id -Mask $finalMask -TestMode $testMode
		
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
		
        $scriptResults += [PSCustomObject]@{
            Email     = $user.email
            ID        = $user.id
            Mask      = $finalMask
            PermCount = $permissionCount
            Status    = $updateStatus
        }
    }
	
    Write-Progress -Activity "Updating Users" -Completed
	
    Write-Host ""
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host "# DETAILED EXECUTION SUMMARY" -ForegroundColor Cyan
    Write-Host "########################################" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Notification Mask Legend (Corrected):" -ForegroundColor Yellow
    Write-Host "  Bit 2   : Request Approved"
    Write-Host "  Bit 4   : Request Available"
    Write-Host "  Bit 16  : Request Declined"
    Write-Host "  ------------------------------------"
    Write-Host "  Total Mask = Sum of enabled bits (e.g., 22 = 2+4+16)"
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
	
    if ($failureCount -gt 0) { exit 1 } else { exit 0 }
	
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
