# scripts/reset-testing-instance.ps1
# This script automates the creation of a clean testing environment.

Write-Host "🚀 Resetting testing instance..."

# --- 1. Define Paths ---
$ProjectRoot = (Get-Item -Path ".").FullName
$TestingDir = Join-Path $ProjectRoot ".testing-MxAi"
$TemplateDir = Join-Path $ProjectRoot "project-template"

# --- 2. Clean and Recreate Testing Directory ---
Write-Host "- Removing old testing directory..."
if (Test-Path $TestingDir) {
    Remove-Item -Recurse -Force -Path $TestingDir
}
New-Item -ItemType Directory -Path $TestingDir | Out-Null
Write-Host "- Created clean testing directory: $TestingDir"

# --- 3. Copy Mendix Project Template ---
Write-Host "- Copying Mendix project template..."
# We will check for content inside the template dir
if (-not (Get-ChildItem -Path $TemplateDir)) {
    Write-Warning "Warning: The 'project-template' directory is empty. Continuing without a Mendix project base."
} else {
    Copy-Item -Path (Join-Path $TemplateDir "*") -Destination $TestingDir -Recurse -Force
}

# --- 4. Copy MxAgile Framework Files ---
Write-Host "- Copying MxAgile framework files..."

$frameworkDirs = @(".mxagile", "scripts", "specs", "requirements", "planning", "waves")

foreach ($dir in $frameworkDirs) {
    $sourceDir = Join-Path $ProjectRoot $dir
    $destDir = Join-Path $TestingDir $dir
    if (Test-Path $sourceDir) {
        Copy-Item -Path $sourceDir -Destination $destDir -Recurse -Force
        Write-Host "  - Copied $dir"
    }
}

Write-Host "✅ Testing instance reset successfully."
Write-Host "Navigate to '$TestingDir' to work within the simulated project."
