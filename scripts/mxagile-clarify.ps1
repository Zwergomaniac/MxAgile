# scripts/mxagile-clarify.ps1

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$SpecId
)

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Generating clarification file for Spec ID: $SpecId..."

# --- 1. Load Trace Index ---
$traceIndexFile = Join-Path $ProjectRoot ".mxagile/state/artifact-trace-index.json"
if (-not (Test-Path $traceIndexFile)) {
    Write-Error "Artifact traceability index not found. Please run mxagile-build-trace-index.ps1 first."
    return
}
$traceIndex = Get-Content -Path $traceIndexFile | ConvertFrom-Json

# --- 2. Find the Spec ---
$specInfo = $traceIndex.specs.$SpecId
if (-not $specInfo) {
    Write-Error "Spec ID '$SpecId' not found in artifact trace index."
    return
}

# --- 3. Prepare File Path and Directory ---
$clarificationsDir = Join-Path $ProjectRoot "planning/clarifications"
if (-not (Test-Path $clarificationsDir)) {
    New-Item -ItemType Directory -Path $clarificationsDir | Out-Null
}
$outputFile = Join-Path $clarificationsDir "$($SpecId).clarification.md"

if (Test-Path $outputFile) {
    Write-Warning "Clarification file for '$SpecId' already exists at: $outputFile"
    return
}

# --- 4. Generate File Content ---
$specFileContent = Get-Content -Path (Join-Path $ProjectRoot $specInfo.path) -Raw

$clarificationContent = @"
# Clarification for Spec: $SpecId

This document is used to ask and answer questions regarding the specification to resolve ambiguities before implementation.

## Original Specification

**Description:** $($specInfo.Description)

```
$specFileContent
```

---

## Questions

*Question 1:* [Enter your question here]

*Stakeholder:* @[Name/Role of person to answer]

## Answers

*Answer 1:* [To be filled in by stakeholder]

"@

# --- 5. Write File and Confirm ---
$clarificationContent | Set-Content -Path $outputFile

Write-Host "✅ Clarification file generated successfully!"
Write-Host "Please edit the new file to add your questions: $outputFile"

