# scripts/mxagile-plan.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$SpecId
)

$ProjectRoot = (Get-Location).Path
Write-Host "Starting MxAgile planning for spec: $SpecId"

# --- 1. Find Spec and Requirement Files ---
$traceIndexFile = Join-Path $ProjectRoot ".mxagile/state/trace-index.json"
if (-not (Test-Path $traceIndexFile)) {
    Write-Error "Traceability index not found. Please run mxagile-build-trace-index.ps1 first."
    return
}
$traceIndex = Get-Content -Path $traceIndexFile | ConvertFrom-Json

$specInfo = $traceIndex.specs.$SpecId
if (-not $specInfo) {
    Write-Error "Spec ID '$SpecId' not found in trace index."
    return
}

$specFilePath = Join-Path $ProjectRoot $specInfo.path
Write-Host "Found Spec: $specFilePath"

# --- 2. Generate Domain Model MDL (Simplified) ---
Write-Host "Generating Domain Model MDL from spec..."

# This is a simplified parser. In a real scenario, this would be a robust
# function that deeply understands the spec file format.
$specContent = Get-Content -Path $specFilePath -Raw

# Example parsing logic (highly simplified):
# Assumes spec has a line like: ENTITY: MyEntity (Name: String, Age: Integer)
$entityLine = $specContent | Select-String -Pattern "^ENTITY: (.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value }

if ($entityLine) {
    $entityParts = $entityLine -split '[\(\)]'
    $entityName = $entityParts[0].Trim()
    $attributeString = $entityParts[1]

    $mdlContent = "CREATE PERSISTENT ENTITY MyModule.\"$entityName\" (\n"

    $attributes = $attributeString -split ','
    foreach ($attribute in $attributes) {
        $attrParts = $attribute.Trim() -split ':'
        $attrName = $attrParts[0].Trim()
        $attrType = $attrParts[1].Trim()
        $mdlContent += "    \"$attrName\": $attrType,\n"
    }

    # Remove trailing comma
    $mdlContent = $mdlContent.TrimEnd(',\n') + "\n);
"

    # --- 3. Save MDL File ---
    $plansDir = Join-Path $ProjectRoot "planning/plans"
    if (-not (Test-Path $plansDir)) {
        New-Item -ItemType Directory -Path $plansDir | Out-Null
    }

    $mdlFile = Join-Path $plansDir "$($SpecId)-domain-model.mdl"
    $mdlContent | Set-Content -Path $mdlFile

    Write-Host "Domain Model MDL generated at: $mdlFile"
    Write-Host "MDL Content:\n$mdlContent"
} else {
    Write-Warning "No 'ENTITY:' line found in spec file. Skipping domain model generation."
}
