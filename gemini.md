# PowerShell Automation — GEMINI.md
# Version: 5.0
# Last Updated: 2026-01-23 01:00

## Role
Senior Automation Engineer. Refine functional scripts into production-grade tools.

================================================================================
SECTION 0: SCRIPT VERSIONING & ARCHIVING (MANDATORY)
================================================================================

### 0.1 Script Preamble (MANDATORY)
Every script MUST begin with a comprehensive preamble block containing:
```powershell
<#
.SYNOPSIS
    [Brief one-line description of script purpose]

.DESCRIPTION
    [Detailed description of what the script does, its purpose, and key features]

.NOTES
    File Name      : ScriptName_vX.YZ.ps1
    Author         : [Your Name]
    Prerequisite   : [PowerShell version, modules, permissions required]
    Version        : X.YZ
    Date           : YYYY-MM-DD HH:mm
    
.CHANGELOG
    vX.YZ (YYYY-MM-DD HH:mm)
    - [Brief summary of changes in this version]
    - [Additional changes]
    
    vX.Y(Z-1) (YYYY-MM-DD HH:mm)
    - [Previous version changes]
#>
```

### 0.2 Version Updates
Every modification to scripts MUST include:
1. Increment the Version field in the preamble (e.g., v2.76 → v2.77)
2. Always change the version number on ALL iterations of the script
3. Update the Date field with full datetime (YYYY-MM-DD HH:mm format)
4. Update the `.changelog` file in the root with detailed notes
5. Add a brief summary Changelog entry in the script's preamble .CHANGELOG section
6. Update the Author field if different from original author (use "Modified by: [Name]")

### 0.3 Filename & File Management
1. **Increase the version number in the filename** for every iteration (e.g., `Script_v2.76.ps1` → `Script_v2.77.ps1`)
2. **Create a new file** with the version incremented for each iteration. Never just overwrite the previous version's filename if the version number is in it
3. This applies to any versioned scripts where tracking history is important

### 0.4 Archiving Procedure
Within the `archive` folder:
1. Create a new folder with the name of the script including its version (e.g., `ScriptName_v2.76`)
2. Put the old version of the script into that folder
3. Include any associated files (logs, CSVs, config files, output files) that were created for that specific revision into the same folder
4. This keeps the root directory clean and maintains a perfect history

### 0.5 Version Format
- Major.Minor format (e.g., v2.71)
- Increment minor for all changes (bugfixes, refactors, features)
- Increment major only for breaking changes or significant rewrites

================================================================================
SECTION 1: HARD CONSTRAINTS (NON-NEGOTIABLE)
================================================================================

### 1.0 Machine Connectivity Restriction
> [!IMPORTANT]
> Do NOT attempt to connect to any remote systems (WinRS, Ping, CIM, SSH, API calls) from the Antigravity session or the local development machine unless explicitly confirmed as available. Remote systems may be unreachable from this machine. All verification involving remote connectivity must be guided by provided logs/artifacts or manual confirmation from the user.

### 1.1 Remote Execution Patterns (Windows)
When remote execution is required on Windows systems:
- Direct remote execution (e.g., via WinRS) may be BLOCKED by security policies
- Use the Scheduled Task pattern when needed:
  1. Write a runner script to a temp location on remote system
  2. Create a Scheduled Task with appropriate privileges (`/RU SYSTEM` or specified user)
  3. Execute via schtasks /Run
- NEVER use the `/IT` (Interactive) flag if the task needs to run without a logged-on user
- The /TR argument for schtasks /Create must stay UNDER 261 CHARACTERS (use runner script pattern to circumvent this limit)
- Consider alternative approaches: PowerShell Remoting, SSH, API endpoints, depending on the environment

### 1.2 User Interaction Pattern (Interactive Prompts)
> [!IMPORTANT]
> DO NOT use script parameters (`param()` block) for user configuration. Instead, use interactive Y/N prompts with automatic timeouts.

**Interactive Prompt Pattern:**
```powershell
# Function to get user input with timeout and default
function Get-UserChoice {
    param(
        [string]$Prompt,
        [string]$DefaultChoice = "Y",  # Y or N
        [int]$TimeoutSeconds = 10
    )
    
    Write-Host "$Prompt " -NoNewline
    Write-Host "[Y/N]" -ForegroundColor Cyan -NoNewline
    Write-Host " (default: " -NoNewline
    Write-Host $DefaultChoice -ForegroundColor Yellow -NoNewline
    Write-Host " | timeout: $TimeoutSeconds`s): " -NoNewline
    
    $startTime = Get-Date
    $response = $null
    
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
```

**Usage Example:**
```powershell
# Prompt with logical default (Y for safe operations, N for destructive ones)
$shouldContinue = Get-UserChoice -Prompt "Do you want to process all items?" -DefaultChoice "Y" -TimeoutSeconds 10
if (-not $shouldContinue) {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    exit 0
}

# Destructive operation - default to N
$confirmDelete = Get-UserChoice -Prompt "WARNING: Delete all temporary files?" -DefaultChoice "N" -TimeoutSeconds 10
```

**Rules:**
- Always use interactive prompts instead of parameters for runtime decisions
- Set logical defaults: `Y` for safe operations, `N` for destructive/risky operations
- Standard timeout: 10 seconds (adjustable for critical decisions)
- Always show the default value and timeout duration
- Display user choice or timeout notification

### 1.3 StrictMode Compliance
- Assume `Set-StrictMode -Version Latest` is ALWAYS active in PowerShell scripts
- NEVER use `.Count` directly on variables — use `@($var).Count` or a Get-Count helper function
- ALWAYS pre-declare variables used with `[ref]`:
  - WRONG:  `[int]::TryParse($str, [ref]$n)`
  - RIGHT:  `[int]$n = 0; [int]::TryParse($str, [ref]$n)`
- Uninitialised variable access = fatal error under StrictMode
- Always initialize variables before use

### 1.4 Timezone & DateTime Safety
- When working across systems, calculate timestamps using UTC or the target system's timezone
- Never assume local and remote clocks match
- For remote systems: Fetch time via appropriate remote command (e.g., `[DateTime]::UtcNow`)
- Store timestamps in consistent format (ISO 8601 recommended: `YYYY-MM-DDTHH:mm:ss`)
- Document timezone assumptions in code comments

================================================================================
SECTION 2: CODE DOCUMENTATION STANDARDS
================================================================================

### 2.0 Inline Code Comments (MANDATORY)
All code MUST include comprehensive comments:

**Required Comment Locations:**
1. **Function Headers:** Every function must have a comment block explaining:
   ```powershell
   # Function: Get-RemoteData
   # Purpose: Retrieves data from remote system via API
   # Parameters: $hostname - target system, $endpoint - API endpoint
   # Returns: PSCustomObject with retrieved data or $null on failure
   function Get-RemoteData {
       param([string]$hostname, [string]$endpoint)
       # Implementation...
   }
   ```

2. **Complex Logic Blocks:** Use comments to explain WHY, not just WHAT:
   ```powershell
   # We use Base64 encoding here because WinRS has issues with special characters
   # in command arguments. This ensures the script content is transmitted intact.
   $encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptContent))
   ```

3. **Non-Obvious Workarounds:** Always document quirks and workarounds:
   ```powershell
   # WORKAROUND: StrictMode requires pre-declaration of [ref] variables
   # See Section 1.3 of gemini.md for details
   [int]$exitCode = 0
   [int]::TryParse($output, [ref]$exitCode)
   ```

4. **Section Separators:** Use visual separators for major sections:
   ```powershell
   ################################################################################
   # SECTION: Remote Execution Logic
   ################################################################################
   ```

5. **Variable Declarations:** Comment purpose of non-obvious variables:
   ```powershell
   $runId = [Guid]::NewGuid().ToString().Substring(0,8)  # Unique identifier for this execution
   $maxRetries = 3                                        # Number of retry attempts for remote operations
   ```

**Comment Style Guidelines:**
- Use `#` for single-line comments
- Use `<# ... #>` for multi-line comment blocks
- Keep comments concise but informative
- Update comments when code changes
- Avoid redundant comments that just repeat the code

**Code Formatting:**
- **Indentation:** ALWAYS use TAB characters for indentation, NEVER spaces
- Configure your editor to use tabs (not spaces converted to tabs)
- This ensures consistency across all scripts and editors

================================================================================
SECTION 3: CRITICAL BUG PATTERNS TO AVOID
================================================================================

### 3.1 PowerShell Here-String Interpolation (THE #1 FAILURE MODE)

When building scripts via here-string (`@"..."@`), variables expand at DEFINITION time. 
If you wrap the expanded value in quotes inside the here-string, you get DOUBLE QUOTING 
that mangles arguments.

**BROKEN PATTERN:**
```powershell
$outputPath = "C:\Temp\output.xml"
$args = "command -output `"$outputPath`""

$scriptContent = @"
Start-Process -FilePath 'program.exe' -ArgumentList '$args' ...
"@
```

After expansion, script contains:
```powershell
Start-Process -FilePath 'program.exe' -ArgumentList 'command -output "C:\Temp\output.xml"' ...
```

**PROBLEM:** Entire argument string wrapped in single quotes. Start-Process receives it as ONE argument. 
The command misparses and silently ignores flags.

**CORRECT PATTERN — use direct invocation with `&`:**
```powershell
$scriptContent = @"
`$exitCode = 0
try {
    & program.exe $args 2>&1 | Out-File -FilePath `$logFile -Append -Encoding UTF8
    `$exitCode = `$LASTEXITCODE
} catch {
    `$exitCode = 9999
}
"@
```

**WHY THIS WORKS:** Here-string expands `$args` to: `command -output "C:\Temp\output.xml"`
PowerShell's `&` operator then parses these as separate arguments natively.

**RULE:** NEVER use `Start-Process -ArgumentList` with complex quoted arguments in 
dynamically generated scripts. Use `&` operator instead.

### 3.2 Null Safety
- Always check for `$null` before calling string methods (`.Trim()`, `.Split()`, etc.)
- Use defensive patterns: 
  ```powershell
  if ([string]::IsNullOrWhiteSpace($val)) { return "" }
  ```
- For arrays, check `$null` before accessing elements:
  ```powershell
  if ($null -ne $array -and $array.Count -gt 0) { ... }
  ```

### 3.3 Remote Command Output Handling
- Remote command output (WinRS, SSH, Invoke-Command) can be:
  - `$null`
  - Empty array
  - Contains unexpected lines (warnings, errors, verbose output)
- Always use defensive access patterns:
  ```powershell
  $result = ($output | Where-Object { $_ -match 'expected pattern' } | Select-Object -First 1)
  if ($null -ne $result) { ... }
  ```
- Never assume output array has elements
- Filter noise before parsing

### 3.4 Error Handling
- Use `try-catch-finally` blocks for all risky operations
- Capture `$LASTEXITCODE` immediately after external command execution
- Set `$ErrorActionPreference` explicitly when needed
- Always cleanup resources in `finally` blocks (files, connections, temp directories)
- Log errors with full context (what failed, when, with what inputs)

### 3.5 Encoding Issues
- Always specify `-Encoding` parameter when using:
  - `Out-File`
  - `Set-Content`
  - `Export-Csv`
- Default encoding varies by PowerShell version
- Use UTF8 (without BOM) for cross-platform compatibility: `-Encoding UTF8`
- Use ASCII only when specifically required

================================================================================
SECTION 4: ARCHITECTURE PATTERNS
================================================================================

### 4.1 Script Structure (Best Practices)
1. **Preamble:** Version, date, author, purpose, changelog summary
2. **Parameters:** Use `[CmdletBinding()]` and `param()` block with validation
3. **Configuration:** Define constants and configuration at top
4. **Helper Functions:** Define all functions before main logic
5. **Main Logic:** Organized, commented, with progress indicators
6. **Cleanup:** Proper resource cleanup and exit codes
7. **Error Handling:** Comprehensive try-catch blocks with logging

### 4.2 Logging Pattern
- Create timestamped log files in designated output directory
- Log format: `[YYYY-MM-DD HH:mm:ss] [LEVEL] Message`
- Levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
- Write-Log helper function for consistency
- Always log: start time, end time, parameters used, errors, final status

### 4.3 File Organization (Standard Layout)
```
Project Root/
├── ScriptName_vX.YZ.ps1    (current version)
├── .changelog              (detailed change history)
├── README.md               (usage documentation)
├── gemini.md               (AI assistant constraints & guidelines)
├── config/                 (configuration files)
├── output/                 (logs, results, generated files)
│   └── YYYY-MM-DD_HHmmss/  (timestamped output folders)
└── archive/                (previous versions)
    └── ScriptName_vX.YY/   (version-specific archive)
        ├── ScriptName_vX.YY.ps1
        └── associated_files/
```

### 4.4 Temporary File Management
- Use system temp directory: `$env:TEMP` or `[System.IO.Path]::GetTempPath()`
- Create unique filenames with timestamps or GUIDs: `script_$([Guid]::NewGuid()).tmp`
- Always clean up temporary files in `finally` blocks
- For remote temp files: Document the cleanup strategy

### 4.5 Progress Reporting
- Use `Write-Progress` for long-running operations
- Update user with meaningful status messages
- Show percentage complete when possible
- Use `Write-Host` with colors for key milestones (start, success, error)
- Consider transcript logging: `Start-Transcript` / `Stop-Transcript`

================================================================================
SECTION 5: TESTING & VERIFICATION
================================================================================

### 5.1 Pre-Deployment Testing Checklist
Before declaring any script change complete:
1. **Syntax Check:** Script runs without syntax errors
2. **StrictMode:** Test with `Set-StrictMode -Version Latest` enabled
3. **Error Handling:** Verify all error paths work correctly
4. **Exit Codes:** Confirm appropriate exit codes (0 = success, non-zero = failure)
5. **Log Files:** Verify logs are created and contain expected information
6. **Output Files:** Confirm output files exist and contain valid data
7. **Cleanup:** Verify temporary files are removed
8. **Edge Cases:** Test with empty inputs, null values, missing files

### 5.2 Remote Execution Verification (if applicable)
1. Confirm runner script is created on remote system
2. Verify scheduled task is created with correct parameters
3. Check task execution status
4. Confirm output files are created on remote system
5. Verify file retrieval mechanism works
6. Confirm remote cleanup completes successfully

### 5.3 Output Validation
- Verify output format matches specification (CSV, JSON, XML, etc.)
- Check for required fields/properties
- Validate data types and ranges
- Confirm no sensitive information is exposed in logs/output
- Test with typical, edge-case, and invalid inputs

### 5.4 Documentation Requirements
After significant changes:
1. Update README with current usage instructions
2. Update inline code comments for complex logic
3. Update .changelog with detailed change notes
4. Add examples for new features or parameters
5. Document known limitations or gotchas

================================================================================
SECTION 6: STATE HANDOFF FORMAT
================================================================================

After every significant work session, provide a handoff summary:

---
### State Handoff — [Date] [Time] — Gemini Code Assist

**Modified Files:**
- `[path/to/file]` — [brief description of changes]

**What Was Implemented:**
- [Specific change 1 with rationale]
- [Specific change 2 with rationale]

**Testing/Verification Results:**
- [ ] Script executes without errors
- [ ] Output files created successfully
- [ ] Logs contain expected information
- [ ] [Additional verification items as appropriate]

**Next Steps:**
- [ ] [Immediate action 1]
- [ ] [Follow-up action 2]

**Known Issues/Blockers:**
- [Issues requiring user input or decisions]
- [Technical limitations or dependencies]

**Notes:**
- [Additional context or observations]
---

================================================================================
SECTION 7: PROJECT-SPECIFIC EXTENSIONS
================================================================================

> [!NOTE]
> This section is for project-specific constraints, architecture notes, 
> API behaviors, third-party tool quirks, or domain-specific requirements.
> 
> Add subsections as needed for your specific project:
> - API endpoint behaviors
> - Third-party tool limitations
> - Domain-specific validation rules
> - Environment-specific configurations
> - Known issues with external dependencies

### 7.1 [Project-Specific Topic]
[Document project-specific requirements here]

### 7.2 [Another Topic]
[Document additional project-specific details here]

================================================================================
NOTES
================================================================================

- This document version: 5.0 (Generalized from WinSAT-Remote specific version)
- All constraints above apply to PowerShell automation projects
- Adapt Section 6 for project-specific requirements
- Keep this document updated as new patterns emerge or constraints are discovered