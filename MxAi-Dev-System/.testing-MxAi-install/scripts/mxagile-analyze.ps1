# scripts/mxagile-analyze.ps1

param (
    [string]$ProjectRoot = (Get-Location).Path
)

Write-Host "Starting MxAgile repository analysis..."

# --- 1. Build and Load Index ---
$traceIndexScript = Join-Path $ProjectRoot "scripts/mxagile-build-trace-index.ps1"
if (-not (Test-Path $traceIndexScript)) {
    Write-Error "mxagile-build-trace-index.ps1 not found!"
    return
}
& $traceIndexScript # Ensure the index is up-to-date

$traceIndexFile = Join-Path $ProjectRoot ".mxagile/state/trace-index.json"
$traceIndex = Get-Content -Path $traceIndexFile | ConvertFrom-Json

$findings = @()


# --- 2. Perform Checks ---

# Check for orphan requirements (not in any spec)
$allReqsInSpecs = ($traceIndex.specs.psobject.Properties | ForEach-Object { $_.Value.requirements }) | Select-Object -Unique
$allReqIds = $traceIndex.requirements.psobject.Properties.Name
foreach ($reqId in $allReqIds) {
    if ($reqId -notin $allReqsInSpecs) {
        $findings += "[Orphan Requirement] Requirement '$reqId' is not referenced in any spec."
    }
}

# Check for orphan specs (no tasks)
$allSpecIdsInTasks = ($traceIndex.tasks.psobject.Properties | ForEach-Object { $_.Value.spec_id }) | Select-Object -Unique
$allSpecIds = $traceIndex.specs.psobject.Properties.Name
foreach ($specId in $allSpecIds) {
    if ($specId -notin $allSpecIdsInTasks) {
        $findings += "[Orphan Spec] Spec '$specId' has no associated tasks."
    }
}

# Check for specs with no requirements
foreach ($specId in $allSpecIds) {
    $spec = $traceIndex.specs.$specId
    if (-not $spec.requirements -or $spec.requirements.Count -eq 0) {
        $findings += "[Empty Spec] Spec '$specId' does not reference any requirements."
    }
}

# Check for broken task dependencies
$allTaskIds = $traceIndex.tasks.psobject.Properties.Name
foreach ($taskId in $allTaskIds) {
    $task = $traceIndex.tasks.$taskId
    if ($task.depends_on) {
        foreach ($dep in $task.depends_on) {
            if ($dep -notin $allTaskIds) {
                $findings += "[Broken Dependency] Task '$taskId' has a broken dependency on non-existent task '$dep'."
            }
        }
    }
}


# --- 3. Display Report ---
if ($findings.Count -gt 0) {
    Write-Warning "MxAgile analysis found $($findings.Count) issues:`n"
    $findings | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "MxAgile analysis complete. No consistency issues found."
}

