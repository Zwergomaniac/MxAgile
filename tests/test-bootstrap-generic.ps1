$ErrorActionPreference = 'Stop'

# Define a temporary directory path for a mock Mendix project.
# Using a unique name to avoid conflicts in parallel runs.
$tempPrefix = 'mxagile-bootstrap-generic-'
$tempDir = Join-Path $env:TEMP ($tempPrefix + [System.Guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'helpers/Remove-TestTempDirectory.ps1')

try {
    # Create the temporary directory.
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Create a dummy .mpr file inside it.
    $mprPath = Join-Path $tempDir "project.mpr"
    New-Item -ItemType File -Path $mprPath | Out-Null
    
    # Exercise the canonical bootstrap in unattended test mode. Wrapper delegation
    # is covered separately by test-setup-detection.ps1.
    $installerScriptPath = Join-Path $PSScriptRoot "..\mxagile-setup.ps1"
    
    # We need to start a new process to capture the exit code correctly.
    $process = Start-Process pwsh -ArgumentList "-NoProfile -NonInteractive -File `"$installerScriptPath`" -ProjectRoot `"$tempDir`" -NonInteractive" -Wait -PassThru
    $exitCode = $process.ExitCode
    
    # Assert that the exit code is 0.
    if ($exitCode -ne 0) {
        throw "mxagile-setup.ps1 exited with code $exitCode."
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
    Remove-TestTempDirectory -Path $tempDir -ExpectedPrefix $tempPrefix
}
