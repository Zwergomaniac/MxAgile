# scripts/install-mercedes.ps1

param (
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$MercedesGitUrl = "https://github.com/Mercedes-Benz/mxagile-layer-mercedes.git"
)

# 1. Safety Preflight: .mpr check
$mprFiles = Get-ChildItem -Path $ProjectRoot -Filter *.mpr
if ($mprFiles.Count -eq 0) {
    Write-Error "No .mpr file found in project root."
    exit 1
}
if ($mprFiles.Count -gt 1) {
    Write-Error "Multiple .mpr files found. Please ensure only one .mpr file exists."
    exit 1
}
Write-Host "Safety Preflight passed: Single .mpr file detected."

# 2. Call generic installer
Write-Host "Invoking generic MxAgile installer..."
& (Join-Path $PSScriptRoot "install-mxagile.ps1") -ProjectRoot $ProjectRoot

# 3. Resolve/Install Mercedes Layer
$layersDir = Join-Path $ProjectRoot ".mxagile/layers"
$mercedesLayerDir = Join-Path $layersDir "mercedes-benz"

if (Test-Path $mercedesLayerDir) {
    Write-Host "Mercedes layer already exists. Skipping clone."
} else {
    Write-Host "Fetching Mercedes-Benz Company Layer..."
    # Using fetch-layer.ps1 to handle resolution
    & (Join-Path $PSScriptRoot "fetch-layer.ps1") -LayerUrl $MercedesGitUrl -TargetDir $mercedesLayerDir
}

# 4. Idempotency/Isolation: Ensure no copying from ./company-layers/
$deprecatedDir = Join-Path $ProjectRoot "company-layers"
if (Test-Path $deprecatedDir) {
    Write-Warning "Deprecated 'company-layers' folder detected. Please manually remove it after migration."
}

Write-Host "Mercedes-Benz installation complete."
