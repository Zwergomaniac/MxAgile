# scripts/reset-testing-instance.ps1
# This script automates the creation of a clean testing environment.
param (
    [string]$MxcliPath = "../../mxcli.exe", # Default path, can be overridden
    [string]$TemplateName = "greenfield"
)

Write-Host "🚀 Resetting testing instance..."

# --- 1. Define Paths ---
$ProjectRoot = (Get-Item -Path ".").FullName
$TestingDir = Join-Path $ProjectRoot ".testing-MxAi"
$TemplateDir = Join-Path $ProjectRoot "project-templates\$TemplateName"

# --- 2. Clean and Recreate Testing Directory ---
Write-Host "- Removing old testing directory..."
if (Test-Path $TestingDir) {
    Remove-Item -Recurse -Force -Path $TestingDir
}
New-Item -ItemType Directory -Path $TestingDir | Out-Null

# --- 2.5. Initialize Git in Testing Directory ---
Push-Location $TestingDir
try {
    git init
    git config user.name "Test Bot"
    git config user.email "test@bot.com"
} finally {
    Pop-Location
}

Write-Host "- Created clean testing directory: $TestingDir"

# --- 3. Copy Mendix Project Template ---
Write-Host "- Copying Mendix project template..."
# We will check for content inside the template dir
if (-not (Get-ChildItem -Path $TemplateDir)) {
    Write-Warning "Warning: The template directory '$TemplateDir' is empty. Continuing without a Mendix project base."
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

# --- Initialize MxCLI for Agent Skills ---
Write-Host "
🚀 Initializing MxCLI to provide agent skills..."

# The mxcli executable is in the root of the parent project structure

if (Test-Path $MxcliPath) {
    # We need to execute from within the testing directory
    Push-Location $TestingDir
    
    try {
        & $MxcliPath init --non-interactive --no-banner
        Write-Host "✅ MxCLI initialized successfully."
    } catch {
        Write-Warning "MxCLI init failed. Agent skills will not be available in this test instance."
    }
    
    Pop-Location
} else {
    Write-Warning "Could not find mxcli.exe at '$MxcliPath'. Skipping initialization."
}
