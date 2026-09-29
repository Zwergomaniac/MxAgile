# scripts/mxagile-plan-wave.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$WaveId
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Preparing agent prompt for Wave ID: $WaveId..."

# --- 1. Load Trace Index ---
$traceIndexFile = Join-Path $ProjectRoot ".mxagile/state/artifact-trace-index.json"
if (-not (Test-Path $traceIndexFile)) {
    Write-Error "Artifact traceability index not found. Please run mxagile-build-trace-index.ps1 first."
    return
}
$traceIndex = Get-Content -Path $traceIndexFile | ConvertFrom-Json

# --- 2. Find Wave and its Specs ---
$waveInfo = $traceIndex.waves.$WaveId
if (-not $waveInfo) {
    Write-Error "Wave ID '$WaveId' not found in artifact trace index."
    return
}

$specIds = $waveInfo.SPECS
if (-not ($specIds -and $specIds.Count -gt 0)) {
    Write-Warning "Wave '$WaveId' contains no specs to plan."
    return
}

# --- 3. Collect Content from all Specs ---
$allSpecsContent = [System.Collections.ArrayList]@()
foreach ($specId in $specIds) {
    $specInfo = $traceIndex.specs.$specId
    if ($specInfo) {
        $specPath = Join-Path $ProjectRoot $specInfo.path
        if (Test-Path $specPath) {
            $content = Get-Content -Path $specPath -Raw
            [void]$allSpecsContent.Add("--- Start of Spec: $specId ---
$content
--- End of Spec: $specId ---")
        }
    }
}

# --- 4. Generate Final Agent Prompt ---
$finalPrompt = @"
# AI AGENT TASK: Generate Consolidated Mendix Domain Model

You are an expert Mendix developer. Your task is to create a single, valid Mendix Definition Language (MDL) script from the multiple specification files provided below.

## Instructions:

1.  **Consolidate Entities:** If multiple specs define attributes for the same entity, merge them into a single `CREATE PERSISTENT ENTITY` block.
2.  **Identify Conflicts:** If you find any direct contradictions (e.g., the same attribute defined with two different types), stop and report the conflict clearly.
3.  **Quote All Identifiers:** Ensure all entity, attribute, and association names are quoted (e.g., `"Customer"`).
4.  **Output Only MDL:** Your final output should be only the complete, valid MDL script. Do not include any other text or explanation.

## Specification Contents:

$($allSpecsContent -join "`n`n")


## YOUR TASK STARTS NOW ##

(Output only the final, consolidated MDL script below this line)
"@

# --- 5. Output Prompt to Console ---
Write-Host "✅ Agent prompt prepared. Copy the text below and provide it to the AI agent."
Write-Host "-----------------------------------------------------------------"
Write-Host $finalPrompt
Write-Host "-----------------------------------------------------------------"

