<#
.SYNOPSIS
    Builds the artifact index and generates a traceability report for a given ID.
.DESCRIPTION
    This script orchestrates the end-to-end traceability workflow:
    1. It first calls the Python indexer (`build_artifact_index.py`) to scan the 
       workspace and build a fresh, canonical artifact graph.
    2. It then calls the Python query engine (`query_artifact_index.py`) to traverse
       the graph and generate a human-readable Markdown report.
.PARAMETER Id
    The ID of the artifact to trace (e.g., 'REQ-001', 'SP-001').
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$Id
)

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$ProjectRoot = Resolve-Path -Path (Join-Path $PSScriptRoot "..")

# --- Step 1: Build the Artifact Index ---
Write-Host "🚀 Step 1: Building canonical artifact index..."
$IndexerScriptPath = Join-Path $PSScriptRoot "build_artifact_index.py"

python $IndexerScriptPath $ProjectRoot

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed during indexing. Aborting trace."
    exit 1
}

Write-Host "✅ Index build complete."

# --- Step 2: Query the Index ---
Write-Host "
🚀 Step 2: Querying index to generate trace report for '$Id'..."
$QueryScriptPath = Join-Path $PSScriptRoot "query_artifact_index.py"

python $QueryScriptPath $Id --path $ProjectRoot

if ($LASTEXITCODE -ne 0) {
    Write-Error "Python script execution failed during querying."
    exit 1
}

Write-Host "✅ Trace report generated successfully."
