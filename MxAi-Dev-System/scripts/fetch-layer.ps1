<#
.SYNOPSIS
    Fetches and installs a company-specific layer into the project.

.DESCRIPTION
    Clones a Git repository, validates the layer manifest, installs it to .mxagile/layers/,
    and generates an agent-readable manifest.
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$RepositoryUrl,

    [string]$Ref = "main"
)

$ProjectRoot = (Get-Location).Path
$LayersDir = Join-Path $ProjectRoot ".mxagile/layers"
$TempDir = Join-Path $ProjectRoot ".mxagile/tmp_layer"

Write-Host "📥 Fetching Company Layer from $RepositoryUrl (Ref: $Ref)..."

# --- 1. Prepare Directory ---
if (-not (Test-Path $LayersDir)) { New-Item -ItemType Directory -Path $LayersDir -Force }
if (Test-Path $TempDir) { Remove-Item -Recurse -Force -Path $TempDir }

# --- 2. Clone ---
try {
    git clone --depth 1 --branch $Ref $RepositoryUrl $TempDir
} catch {
    Write-Error "Error: Failed to clone repository."
    return
}

# --- 3. Validate ---
$layerManifestPath = Join-Path $TempDir "layer.json"
if (-not (Test-Path $layerManifestPath)) {
    Write-Error "Error: Missing layer.json."
    Remove-Item -Recurse -Force -Path $TempDir
    return
}

$layerManifest = Get-Content -Path $layerManifestPath | ConvertFrom-Json
$layerId = $layerManifest.id
$layerName = $layerManifest.name

# --- 4. Install ---
$DestinationDir = Join-Path $LayersDir $layerId
if (Test-Path $DestinationDir) {
    Write-Warning "Layer '$layerId' already exists. Keeping existing version."
    Remove-Item -Recurse -Force -Path $TempDir
    return
}

New-Item -ItemType Directory -Path $DestinationDir -Force
Copy-Item -Path (Join-Path $TempDir "*") -Destination $DestinationDir -Recurse -Force

# --- 5. Generate Manifest ---
$StateDir = Join-Path $ProjectRoot ".mxagile/state"
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force }
$ManifestFilePath = Join-Path $StateDir "manifest.$layerId.md"

$manifestContent = "# Layer: $layerName ($layerId)`n`nInstalled from $RepositoryUrl`n`n"
$manifestContent | Out-File -FilePath $ManifestFilePath -Encoding utf8

# --- 6. Cleanup ---
Remove-Item -Recurse -Force -Path $TempDir
Write-Host "✅ Layer '$layerName' installed successfully."
