# scripts/mxagile-reconcile.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$SpecId
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Preparing agent prompt for reconciling Spec ID: $SpecId..."

# --- 1. Find Spec and Clarification Files ---
$specFile = Get-ChildItem -Path (Join-Path $ProjectRoot "specs") -Filter "$($SpecId).spec" -Recurse
$clarificationFile = Get-ChildItem -Path (Join-Path $ProjectRoot "planning/clarifications") -Filter "$($SpecId).clarification.md" -Recurse

if (-not $specFile) {
    Write-Error "Original spec file for '$SpecId' not found."
    return
}
if (-not $clarificationFile) {
    Write-Error "Clarification file for '$SpecId' not found. Run mxagile-clarify.ps1 first."
    return
}

# --- 2. Read File Contents ---
$specContent = Get-Content -Path $specFile.FullName -Raw
$clarificationContent = Get-Content -Path $clarificationFile.FullName -Raw


# --- 3. Generate Final Agent Prompt ---
$finalPrompt = @"
# AI AGENT TASK: Reconcile Mendix Specification

You are an expert Mendix developer. Your task is to update an original Mendix specification (`.spec`) file based on the questions and answers provided in a clarification document.

## Instructions:

1.  **Read Carefully:** Read the original spec and the entire Q&A in the clarification file.
2.  **Incorporate Answers:** Modify the original spec content to incorporate the decisions and information from the 'Answers' section.
3.  **Clean Up:** Remove any ambiguity that has now been resolved (e.g., replace `???` with the correct type).
4.  **Output Only Spec Content:** Your final output should be only the complete, updated content for the `.spec` file. Do not include `ID:` or other metadata if it's already defined. Output only the parts that would be in the file.

## Original .spec File Content:

```
$specContent
```

## Clarification File Content:

```
$clarificationContent
```

## YOUR TASK STARTS NOW ##

(Output only the final, updated content for the .spec file below this line)
"@

# --- 4. Output Prompt to Console ---
Write-Host "✅ Agent prompt prepared. Copy the text below and provide it to the AI agent."
Write-Host "-----------------------------------------------------------------"
Write-Host $finalPrompt
Write-Host "-----------------------------------------------------------------"
