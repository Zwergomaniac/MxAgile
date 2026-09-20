# scripts/mxagile-plan.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$SpecId
)

$ProjectRoot = (Get-Location).Path
Write-Host "Starting MxAgile planning for spec: $SpecId"

# --- 1. Load Trace Index ---
$traceIndexPath = Join-Path $ProjectRoot ".mxagile/state/artifact-trace-index.json"
if (-not (Test-Path -LiteralPath $traceIndexPath)) {
    Write-Error "Artifact trace index not found at '$traceIndexPath'."
    return
}

$traceIndex = Get-Content -Path $traceIndexPath | ConvertFrom-Json
Write-Host "Loaded trace index."

# --- 2. Find Spec in Index ---
# Note: Accessing nested properties on a PSCustomObject requires parentheses
$specInfo = ($traceIndex.specs).$SpecId
if (-not $specInfo) {
    Write-Error "Spec with ID '$SpecId' not found in artifact trace index."
    return
}

$specFilePath = Join-Path $ProjectRoot $specInfo.path
if (-not (Test-Path -LiteralPath $specFilePath)) {
    Write-Error "Spec file not found at path specified in artifact trace index: '$specFilePath'."
    return
}

Write-Host "Found Spec: $specFilePath"

# --- 3. Read and Print Spec Content ---
Write-Host "Reading spec content..."
$specContent = Get-Content -Path $specFilePath -Raw

Write-Host "--- Spec Content ---"
Write-Host $specContent
Write-Host "--- End Spec Content ---"

