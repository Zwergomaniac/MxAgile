<#
.SYNOPSIS
    Installs the MxAgile framework into the current directory.

.DESCRIPTION
    This script downloads the MxAgile template repository, copies the necessary framework
    files (.mxagile, scripts) into the current project, and cleans up afterwards.

.PARAMETER RepositoryUrl
    The URL of the MxAgile git repository template.

.EXAMPLE
    ./install-mxagile.ps1 -RepositoryUrl "https://github.com/your-org/mxagile-template.git"
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$RepositoryUrl = "https://github.com/example/mxagile-template.git" # Placeholder URL
)

Write-Host "🚀 Installing MxAgile Framework..."

$TempDir = "_mxagile_temp_install"
$FrameworkDirs = @(".mxagile", "scripts")

# --- 1. Preliminary Checks ---
if (Test-Path $TempDir) {
    Write-Error "Error: Temporary directory '$TempDir' already exists. Please remove it and try again."
    return
}

# Check if git is installed
$gitExists = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitExists) {
    Write-Error "Error: Git is not installed or not in your PATH. Please install Git to proceed."
    return
}

# --- 2. Clone Template Repository ---
Write-Host "- Cloning template from $RepositoryUrl..."
try {
    git clone --depth 1 $RepositoryUrl $TempDir
} catch {
    Write-Error "Error: Failed to clone repository. Please check the URL and your connection."
    # Clean up on failure
    if (Test-Path $TempDir) { Remove-Item -Recurse -Force -Path $TempDir }
    return
}

# --- 3. Copy Framework Files ---
Write-Host "- Copying framework files into the current project..."

foreach ($dir in $FrameworkDirs) {
    $sourceDir = Join-Path $TempDir $dir
    $destDir = Join-Path (Get-Location).Path $dir

    if (Test-Path $sourceDir) {
        if (Test-Path $destDir) {
            Write-Warning "Warning: Directory '$dir' already exists and will be overwritten."
        }
        Copy-Item -Path $sourceDir -Destination $destDir -Recurse -Force
        Write-Host "  - Copied $dir"
    } else {
        Write-Warning "Warning: Source directory '$dir' not found in the template repository."
    }
}

# --- 4. Clean up ---
Write-Host "- Cleaning up temporary files..."
Remove-Item -Recurse -Force -Path $TempDir

Write-Host "✅ MxAgile framework installed successfully!"
Write-Host "You can now start by creating artifacts in the 'requirements' and 'specs' directories."
