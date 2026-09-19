<#
.SYNOPSIS
    Adds a company-specific layer to the MxAgile project.

.DESCRIPTION
    This script downloads a company layer from a Git repository, integrates it
    into the project, and creates a manifest file for agent awareness.

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
$layerName = $layerManifest.name

if (-not $layerId) {
    Write-Error "Error: layer.json is missing the 'id' field."
    Remove-Item -Recurse -Force -Path $TempDir
    return
}

Write-Host "- Installing layer '$layerName' (id: $layerId)"

$LayersDir = Join-Path $ProjectRoot ".mxagile/layers"
$DestinationDir = Join-Path $LayersDir $layerId

if (Test-Path $DestinationDir) {
    Write-Warning "- Layer '$layerId' already exists. Overwriting..."
    Remove-Item -Recurse -Force -Path $DestinationDir
}

New-Item -ItemType Directory -Path $DestinationDir -Force
Copy-Item -Path (Join-Path $TempDir "*") -Destination $DestinationDir -Recurse -Force

# --- 4. Generate Agent-Readable Manifest ---
Write-Host "- Generating layer manifest for agent awareness..."
$StateDir = Join-Path $ProjectRoot ".mxagile/state"
if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir -Force
}
$ManifestFilePath = Join-Path $StateDir "manifest.$layerId.md"

$manifestContent = @()
$manifestContent += "# Layer Manifest: $layerName ($layerId)"
$manifestContent += ""
$manifestContent += "This manifest summarizes the contents of the newly added company layer."
$manifestContent += ""

if (Test-Path (Join-Path $DestinationDir "glossary.md")) {
    $manifestContent += "- **Glossary:** A `glossary.md` is provided."
}
if (Test-Path (Join-Path $DestinationDir "platform-modules.md")) {
    $manifestContent += "- **Platform Modules:** `platform-modules.md` defines standard modules."
}

# Check for skills
$SkillsDir = Join-Path $DestinationDir "skills"
if (Test-Path $SkillsDir) {
    $skills = Get-ChildItem -Path $SkillsDir -Directory
    if ($skills) {
        $manifestContent += "- **Agent Skills:** The following skills are available:"
        foreach ($skill in $skills) {
            $manifestContent += "  - $($skill.Name)"
        }
    }
}

$manifestContent | Out-File -FilePath $ManifestFilePath -Encoding utf8

# --- 5. Clean up ---
Write-Host "- Cleaning up temporary files..."
Remove-Item -Recurse -Force -Path $TempDir

# --- 6. Final Output ---
Write-Host "✅ Company Layer '$layerName' added successfully!"
Write-Host ""
Write-Host "ACTION REQUIRED FOR AGENT:"
Write-Host "To update your context, please read the generated manifest file:"
Write-Host (Resolve-Path -Path $ManifestFilePath -Relative)
