# scripts/mxagile-plan.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$SpecId
)

$ProjectRoot = (Get-Location).Path
Write-Host "Starting MxAgile planning for spec: $SpecId"

# --- 1. Find Spec File ---
$specFilePath = ""
$specFileGuess = Join-Path $ProjectRoot "specs/$($SpecId)_*.spec"
$specFile = Get-Item -Path $specFileGuess -ErrorAction SilentlyContinue
if ($specFile) {
    $specFilePath = $specFile.FullName
} else {
    Write-Error "Spec file for ID '$SpecId' not found."
    return
}
Write-Host "Found Spec: $specFilePath"

# --- 2. Generate Domain Model MDL (Simplified) ---
Write-Host "Generating Domain Model MDL from spec..."

$specContent = Get-Content -Path $specFilePath -Raw

# Example parsing logic (highly simplified):
$entityLine = $specContent | Select-String -Pattern "^ENTITY: (.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value }

Write-Host "DEBUG: Raw entityLine is: [$entityLine]"

if ($entityLine) {
    $entityParts = $entityLine -split '[\(\)]'
    Write-Host "DEBUG: entityParts count is $($entityParts.Count)"
    for ($i = 0; $i -lt $entityParts.Length; $i++) {
        Write-Host "DEBUG: entityParts[$i] = '" + $entityParts[$i] + "'"
    }

    $entityName = $entityParts[0].Trim()
    $attributeString = $entityParts[1]
    
    Write-Host "DEBUG: entityName is: [$entityName]"
    Write-Host "DEBUG: attributeString is: [$attributeString]"

    $mdlContent = "CREATE PERSISTENT ENTITY MyModule.\"$entityName\" (\n"

    $attributes = $attributeString -split ','
    foreach ($attribute in $attributes) {
        Write-Host "DEBUG: Parsing attribute: [$attribute]"
        $attrParts = $attribute.Trim() -split ':'
        $attrName = $attrParts[0].Trim()
        $attrType = $attrParts[1].Trim()
        Write-Host "DEBUG:   -> Name: [$attrName], Type: [$attrType]"
        $mdlContent += "    \"$attrName\": $attrType,\n"
    }

    $mdlContent = $mdlContent.TrimEnd(',\n') + "\n);"

    # --- 3. Save MDL File ---
    $plansDir = Join-Path $ProjectRoot "planning/plans"
    if (-not (Test-Path $plansDir)) {
        New-Item -ItemType Directory -Path $plansDir | Out-Null
    }

    $mdlFile = Join-Path $plansDir "$($SpecId)-domain-model.mdl"
    $mdlContent | Set-Content -Path $mdlFile

    Write-Host "Domain Model MDL generated at: $mdlFile"

} else {
    Write-Warning "No 'ENTITY:' line found in spec file. Skipping domain model generation."
}
