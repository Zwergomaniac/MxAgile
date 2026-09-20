# scripts/mxagile-init.ps1

param (
    [string]$ProjectRoot = (Get-Location).Path
)

Write-Host "Starting MxAgile initialization in: $ProjectRoot"

# --- Core Directories ---
$mxAgileDir = Join-Path $ProjectRoot ".mxagile"
$specsDir = Join-Path $ProjectRoot "specs"
$reqsDir = Join-Path $ProjectRoot "requirements"
$tasksDir = Join-Path $ProjectRoot "planning/tasks"

$dirsToCreate = @(
    $mxAgileDir,
    $specsDir,
    $reqsDir,
    $tasksDir,
    (Join-Path $mxAgileDir "state"),
    (Join-Path $mxAgileDir "schemas"),
    (Join-Path $mxAgileDir "templates"),
    (Join-Path $mxAgileDir "layers")
)

foreach ($dir in $dirsToCreate) {
    if (-not (Test-Path $dir)) {
        Write-Host "Creating directory: $dir"
        New-Item -ItemType Directory -Path $dir | Out-Null
    } else {
        Write-Host "Directory exists, skipping: $dir"
    }
}

# --- Company Layer Selection ---
$layersDir = Join-Path $mxAgileDir "layers"
$availableLayers = Get-ChildItem -Path $layersDir -Directory | Where-Object { $_.Name -ne '_template' } | ForEach-Object { $_.Name }

if ($availableLayers.Count -gt 0) {
    Write-Host "Found available company layers: $($availableLayers -join ", ")"
    $choice = Read-Host "Do you want to install a company-specific layer? (y/n)"

    if ($choice -eq 'y') {
        $layerName = Read-Host "Enter the name of the layer to install"
        if ($availableLayers -contains $layerName) {
            $layerPath = Join-Path $layersDir $layerName
            Write-Host "Installing layer: $layerName from $layerPath..." 
            # TODO: Add file copy/overlay logic here
        } else {
            Write-Warning "Layer '$layerName' not found. Continuing with generic setup."
        }
    }
}

Write-Host "MxAgile initialization complete."

