# Pester-less test for local updater script
# Runs a self-contained test to verify that the project-local updater
# script can both install and conditionally skip updates for mxcli.

$ErrorActionPreference = 'Stop'

# Top-level error handling to ensure a clear PASS/FAIL exit code
try {
    # Assertion helper function
    function Assert-True {
        param(
            [bool]$Condition,
            [string]$Message
        )
        if (-not $Condition) {
            # Throw an exception that will be caught by the top-level handler
            throw "Assertion Failed: $Message"
        }
    }

    # 1. Define a temporary directory for the mock project.
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "mxcli-test-local-updater-$(Get-Random)"

    # 2. In a try/finally block, ensure this temporary directory is always cleaned up.
    try {
        # 3a. Create the temporary directory.
        Write-Host "Creating temporary directory: $tempDir"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        # 3b. Copy the canonical install script into the temp directory.
        # Note: $PSScriptRoot is the directory where this script is located (tests/)
        $sourceScriptPath = Join-Path $PSScriptRoot "..\scripts\install-mxcli.ps1"
        $destinationScriptPath = Join-Path $tempDir "update-mxcli.ps1"
        Copy-Item -Path $sourceScriptPath -Destination $destinationScriptPath
        Assert-True -Condition (Test-Path $destinationScriptPath) -Message "Failed to copy updater script to temp directory."

        # Change location to the temp directory to simulate running from a project root
        Push-Location $tempDir

        # 3c. First Run (Installation):
        Write-Host "--- First Run (Installation) ---"
        # Execute the script and capture its output.
        $output1 = & .\update-mxcli.ps1
        Write-Host $output1

        # Assert that mxcli.exe now exists.
        Assert-True -Condition (Test-Path "mxcli.exe") -Message "mxcli.exe was not found after the first run."
        Write-Host "  [OK] mxcli.exe exists."

        # Execute mxcli.exe --version and assert success.
        & .\mxcli.exe --version
        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "'mxcli.exe --version' failed with exit code $LASTEXITCODE."
        Write-Host "  [OK] 'mxcli.exe --version' ran successfully."


        # 3d. Second Run (Conditional Update Check):
        Write-Host "--- Second Run (Conditional Update Check) ---"
        # Execute the script a second time.
        $output2 = & .\update-mxcli.ps1
        Write-Host $output2

        # Assert that the output indicates an up-to-date status.
        Assert-True -Condition ([bool]($output2 -like "*is already up-to-date*")) -Message "Second run output did not contain the 'up-to-date' message."
        Write-Host "  [OK] Second run confirmed mxcli is up-to-date."

    }
    finally {
        # Return to the original directory
        Pop-Location

        # Cleanup the temporary directory
        if (Test-Path $tempDir) {
            Write-Host "Cleaning up temporary directory: $tempDir"
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }

    # 4. If all assertions pass, print a "PASS" message and exit with code 0.
    Write-Host ""
    Write-Host "****************"
    Write-Host "*     PASS     *"
    Write-Host "****************"
    exit 0
}
catch {
    # 5. If any assertion fails, print a "FAIL" message and exit with code 1.
    Write-Host ""
    Write-Host "****************"
    Write-Host "*     FAIL     *"
    Write-Host "****************"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    # Ensure cleanup happens even on failure
    if ($tempDir -and (Test-Path $tempDir)) {
        Write-Host "Attempting cleanup of temporary directory: $tempDir"
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
