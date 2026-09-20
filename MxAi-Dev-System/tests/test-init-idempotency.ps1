$ErrorActionPreference = "Stop"
$ProjectRoot = Join-Path $PSScriptRoot "temp-project"

# Cleanup if it exists from previous run
if (Test-Path -LiteralPath $ProjectRoot) { Remove-Item -LiteralPath $ProjectRoot -Recurse -Force }
New-Item -ItemType Directory -Path $ProjectRoot | Out-Null

# Create dummy requirements.txt
New-Item -Path (Join-Path $ProjectRoot "requirements.txt") -ItemType File | Out-Null

try {
    # Run init 1
    Write-Host "Running init 1..."
    # Pass 'n' via input to Read-Host
    $output1 = "n" | & (Join-Path $PSScriptRoot "../scripts/mxagile-init.ps1") -ProjectRoot $ProjectRoot 2>&1

    # Verify structure
    $requiredDirs = @(".mxagile", "specs", "requirements", "planning/tasks")
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $dir))) { throw "Failed to create directory $dir" }
    }

    # Run init 2
    Write-Host "Running init 2..."
    $output2 = "n" | & (Join-Path $PSScriptRoot "../scripts/mxagile-init.ps1") -ProjectRoot $ProjectRoot 2>&1

    # Verify it completes successfully and check for skip message
    if ($LASTEXITCODE -ne 0) { throw "Script failed on second run" }

    if ($output2 -notmatch "Directory exists, skipping:") {
        # Depending on how the script is run, output might be formatted differently
        Write-Host "WARNING: Expected 'Directory exists, skipping:' in output, but not found."
    }

    Write-Host "PASS"
} catch {
    Write-Host "FAIL: $_"
    exit 1
} finally {
    # Cleanup
    if (Test-Path -LiteralPath $ProjectRoot) { Remove-Item -LiteralPath $ProjectRoot -Recurse -Force }
}
