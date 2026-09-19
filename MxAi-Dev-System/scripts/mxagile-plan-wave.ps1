<#
.SYNOPSIS
    Generates a single, combined MDL script for all specifications in a given wave.
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$WaveId
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Planning wave '$WaveId'..."

# --- 1. Read Trace Index ---
$traceIndexFile = Join-Path $ProjectRoot ".mxagile/state/trace-index.json"
if (-not (Test-Path $traceIndexFile)) {
    Write-Error "Traceability index not found. Please run mxagile-build-trace-index.ps1 first."
    return
}
$traceIndex = Get-Content -Path $traceIndexFile | ConvertFrom-Json

# --- 2. Find Wave and its Specs ---
$waveInfo = $traceIndex.waves.$WaveId
if (-not $waveInfo) {
    Write-Error "Wave ID '$WaveId' not found in trace index."
    return
}

$specIds = $waveInfo.Spec
if (-not $specIds) {
    Write-Warning "Wave '$WaveId' contains no specs to plan."
    return
}

# Ensure specIds is always an array
if ($specIds -isnot [array]) {
    $specIds = @($specIds)
}

Write-Host "- Found $($specIds.Count) specs in wave: $($specIds -join ", ")"

# --- 3. Generate MDL for each Spec ---
$combinedMdlContent = "" # Initialize empty string for all MDL

foreach ($specId in $specIds) {
    $specInfo = $traceIndex.specs.$specId
    if (-not $specInfo) {
        Write-Warning "- Spec ID '$specId' from wave was not found in the index. Skipping."
        continue
    }

    $specFilePath = Join-Path $ProjectRoot $specInfo.path
    $specContent = Get-Content -Path $specFilePath

    $combinedMdlContent += "# --- MDL for Spec: $specId ---\n"

    # --- Replicated Logic from mxagile-plan.ps1 --- 
    # In a future version, this could be a shared function.

    # A) Parse ENTITY
    $entityLine = $specContent | Select-String -Pattern "^ENTITY: (.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
    if ($entityLine) {
        $firstParen = $entityLine.IndexOf('(')
        $lastParen = $entityLine.LastIndexOf(')')
        if ($firstParen -ge 0 -and $lastParen -gt $firstParen) {
            $entityName = $entityLine.Substring(0, $firstParen).Trim()
            $attributeString = $entityLine.Substring($firstParen + 1, $lastParen - $firstParen - 1)

            $mdlContent = 'CREATE PERSISTENT ENTITY MyModule."' + $entityName + '" (' + "`n"
            $attributes = $attributeString -split ','
            foreach ($attribute in $attributes) {
                if ($attribute.Trim() -ne '') {
                    $attrParts = $attribute.Trim() -split ':'
                    $attrName = $attrParts[0].Trim()
                    $attrType = $attrParts[1].Trim()
                    $mdlContent += '    "' + $attrName + '": ' + $attrType + ',' + "`n"
                }
            }
            $mdlContent = $mdlContent.TrimEnd(',\n') + "\n);\n\n"
            $combinedMdlContent += $mdlContent
        }
    }

    # B) Parse ASSOCIATION
    $assocLine = $specContent | Select-String -Pattern "^ASSOCIATION: (.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value }
    if ($assocLine) {
        # Example: Customer_Address (Customer 1 -> * Address)
        $assocName = ($assocLine -split '\(')[0].Trim()
        $mdlContent = 'CREATE ASSOCIATION MyModule."' + $assocName + '" FROM MyModule.Customer TO MyModule.Address;' + "`n`n" # This is highly simplified and needs proper parsing
        $combinedMdlContent += $mdlContent
    }
}

# --- 4. Save Combined MDL File ---
$plansDir = Join-Path $ProjectRoot "planning/plans"
if (-not (Test-Path $plansDir)) {
    New-Item -ItemType Directory -Path $plansDir | Out-Null
}

$outputMdlFile = Join-Path $plansDir "$($WaveId).mdl"
$combinedMdlContent | Set-Content -Path $outputMdlFile

Write-Host "✅ Combined wave plan generated successfully at: $outputMdlFile"
