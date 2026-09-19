<#
.SYNOPSIS
    Adds a company-specific layer to the MxAgile project.

.DESCRIPTION
    This script downloads a company layer from a Git repository and integrates it
    into the current project's .mxagile/layers directory.

.PARAMETER RepositoryUrl
    The Git URL of the company layer repository.
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$RepositoryUrl
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Adding Company Layer from $RepositoryUrl..."

$TempDir = "_mxagile_layer_temp"

# --- 1. Preliminary Checks ---
if (Test-Path $TempDir) {
    Write-Error "Error: Temporary directory '$TempDir' already exists. Please remove it and try again."
    return
}
$gitExists = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitExists) {
    Write-Error "Error: Git is not installed or not in your PATH. Please install Git to proceed."
    return
}

# --- 2. Clone Layer Repository ---
Write-Host "- Cloning layer repository..."
try {
    git clone --depth 1 $RepositoryUrl $TempDir
} catch {
    Write-Error "Error: Failed to clone repository. Please check the URL and your connection."
    if (Test-Path $TempDir) { Remove-Item -Recurse -Force -Path $TempDir }
    return
}

# --- 3. Validate Layer and Copy Files ---
$layerManifestPath = Join-Path $TempDir "layer.json"
if (-not (Test-Path $layerManifestPath)) {
    Write-Error "Error: Cloned repository is not a valid MxAgile layer (missing layer.json)."
    Remove-Item -Recurse -Force -Path $TempDir
    return
}

$layerManifest = Get-Content -Path $layerManifestPath | ConvertFrom-Json
$layerId = $layerManifest.id

if (-not $layerId) {
    Write-Error "Error: layer.json is missing the 'id' field."
    Remove-Item -Recurse -Force -Path $TempDir
    return
}

Write-Host "- Installing layer '$($layerManifest.name)' (id: $layerId)"

$LayersDir = Join-Path $ProjectRoot ".mxagile/layers"
$DestinationDir = Join-Path $LayersDir $layerId

if (Test-Path $DestinationDir) {
    Write-Warning "- Layer '$layerId' already exists. Overwriting..."
}

Copy-Item -Path (Join-Path $TempDir "*") -Destination $DestinationDir -Recurse -Force

# --- 4. Integration Logic (Future Enhancement) ---
Write-Host "- Integrating layer content..."
# TODO: Implement logic to merge glossaries.
# TODO: Implement logic to import Mendix modules from the layer's 'modules' directory via mxcli.
# For now, the files are just copied.

# --- 5. Clean up ---
Write-Host "- Cleaning up temporary files..."
Remove-Item -Recurse -Force -Path $TempDir

Write-Host "✅ Company Layer '$layerId' added successfully!"
