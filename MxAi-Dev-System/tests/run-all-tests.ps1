<#
.SYNOPSIS
    The main test entry point for the MxAgile framework.
.DESCRIPTION
    This script discovers and executes all Pester-style test scripts (`test-*.ps1`)
    and the basic smoke test (`smoke-test.ps1`) located in the tests/ directory.
    It reports a summary of the results and exits with a non-zero status code if
    any test fails, making it suitable for CI/CD environments.
#>

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

# Discover all test scripts
$TestFiles = Get-ChildItem -Path $PSScriptRoot -Filter "test-*.ps1" 
$SmokeTestFile = Get-ChildItem -Path $PSScriptRoot -Filter "smoke-test.ps1"
$AllTests = $TestFiles + $SmokeTestFile

if ($AllTests.Count -eq 0) {
    Write-Error "No test files found in the tests/ directory."
    exit 1
}

Write-Host "Found $($AllTests.Count) test files to execute...
" -ForegroundColor Green

$Results = @()
$FailedCount = 0

foreach ($TestFile in $AllTests) {
    Write-Host "======================================================================"
    Write-Host "EXECUTING: $($TestFile.Name)"
    Write-Host "======================================================================"

    $StartTime = Get-Date
    
    # Execute the test script
    try {
        powershell -File $TestFile.FullName
        $ExitCode = $LASTEXITCODE
    } catch {
        # This will catch terminating errors within the script itself
        Write-Error "A terminating error occurred while running $($TestFile.Name):
$($_ | Out-String)"
        $ExitCode = -1 # Assign a custom exit code for script-level exceptions
    }

    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime

    $Status = if ($ExitCode -eq 0) { "Pass" } else { "Fail" }

    if ($Status -eq "Fail") {
        $FailedCount++
    }

    $Results += [PSCustomObject]@{
        TestFile = $TestFile.Name
        Status = $Status
        Duration = "{0:N2}s" -f $Duration.TotalSeconds
        ExitCode = $ExitCode
    }
    Write-Host ""
}

# --- Summary ---
Write-Host "======================================================================"
Write-Host "TEST SUMMARY"
Write-Host "======================================================================"

$Results | Format-Table -AutoSize

if ($FailedCount -gt 0) {
    Write-Error "$FailedCount test(s) failed."
    exit 1
} else {
    Write-Host "All tests passed successfully." -ForegroundColor Green
    exit 0
}
