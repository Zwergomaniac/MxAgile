$ErrorActionPreference = 'Stop'

# Define a temporary directory path for a mock Mendix project.
# Using a unique name to avoid conflicts in parallel runs.
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())

try {
    # Create the temporary directory.
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Create a dummy .mpr file inside it.
    $mprPath = Join-Path $tempDir "project.mpr"
    New-Item -ItemType File -Path $mprPath | Out-Null
    
    # Execute the refactored install-mxagile.ps1, passing the path of the temporary directory.
    # Assuming the script is in the root of the repo, and this test is in a 'tests' subfolder.
    $installerScriptPath = Join-Path $PSScriptRoot "..\install-mxagile.ps1"
    
    # We need to start a new process to capture the exit code correctly.
    $process = Start-Process pwsh -ArgumentList "-File `"$installerScriptPath`" -ProjectRoot `"$tempDir`"" -Wait -PassThru
    $exitCode = $process.ExitCode
    
    # Assert that the exit code is 0.
    if ($exitCode -ne 0) {
        throw "install-mxagile.ps1 exited with code $exitCode."
    }
    
    # Assert that the .mxagile directory was successfully created.
    $mxagilePath = Join-Path $tempDir ".mxagile"
    if (-not (Test-Path -Path $mxagilePath -PathType Container)) {
        throw ".mxagile directory was not created at '$mxagilePath'."
    }
    
    # If all assertions pass, print a "PASS" message and exit with code 0.
    Write-Host "PASS"
    exit 0
    
} catch {
    # If any assertion fails or an exception is caught, print a "FAIL" message and exit with code 1.
    Write-Host "FAIL: $($_.Exception.Message)"
    exit 1
    
} finally {
    # Use a `try/finally` block to ensure the temporary directory is always cleaned up.
    if (Test-Path -Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
}
