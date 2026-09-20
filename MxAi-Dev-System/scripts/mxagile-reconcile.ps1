# scripts/mxagile-reconcile.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$SpecId
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Preparing agent prompt for reconciling Spec ID: $SpecId..."

# --- 1. Load Trace Index and Find File Paths ---
$traceIndexPath = Join-Path $ProjectRoot ".mxagile/state/artifact-trace-index.json"
if (-not (Test-Path $traceIndexPath)) {
    Write-Error "Artifact trace index not found at '$traceIndexPath'. Run the planner first."
    return
}
$traceIndex = Get-Content -Path $traceIndexPath | ConvertFrom-Json

$specEntry = $traceIndex.specs.$SpecId

if (-not $specEntry) {
    Write-Error "Spec with ID '$SpecId' not found in artifact trace index."
    return
}

$specFilePath = Join-Path $ProjectRoot $specEntry.path
$clarificationDir = Join-Path $ProjectRoot "planning/clarifications"
if (Test-Path $clarificationDir) {
    $clarificationFile = Get-ChildItem -Path $clarificationDir -Filter "$($SpecId).clarification.md" -Recurse
} else {
    Write-Warning "Clarification directory not found at '$clarificationDir'."
    $clarificationFile = $null
}

if (-not (Test-Path $specFilePath)) {
    Write-Error "Original spec file '$($specEntry.path)' not found."
    return
}
if (-not $clarificationFile) {
    Write-Error "Clarification file for '$SpecId' not found. Run mxagile-clarify.ps1 first."
    return
}

# --- 2. Read File Contents ---
$specContent = Get-Content -Path $specFilePath -Raw
$clarificationContent = Get-Content -Path $clarificationFile.FullName -Raw


# --- 3. Generate Final Agent Prompt ---
$finalPrompt = @"
# AI AGENT TASK: Reconcile Mendix Specification

You are an expert Mendix developer. Your task is to update an original Mendix specification (`.yml`) file based on the questions and answers provided in a clarification document.

## Instructions:

1.  **Read Carefully:** Read the original specification and the entire Q&A in the clarification file.
2.  **Incorporate Answers:** Modify the original spec content to incorporate the decisions and information from the 'Answers' section.
3.  **Clean Up:** Remove any ambiguity that has now been resolved (e.g., replace `???` with the correct type).
4.  **Output Only Spec Content:** Your final output should be only the complete, updated content for the `.yml` file. Do not include `id:` or other metadata that is already defined. Output only the YAML content of the file.

## Original Specification File Content (`$($specEntry.path)`):

```yaml
$specContent
```

## Clarification File Content:

```markdown
$clarificationContent
```

## YOUR TASK STARTS NOW ##

(Output only the final, updated YAML content for the specification file below this line)
"@

# --- 4. Output Prompt to Console ---
Write-Host "✅ Agent prompt prepared. Copy the text below and provide it to the AI agent."
Write-Host "-----------------------------------------------------------------"
Write-Host $finalPrompt
Write-Host "-----------------------------------------------------------------"
