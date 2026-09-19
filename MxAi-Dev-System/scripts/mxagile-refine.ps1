# scripts/mxagile-refine.ps1

$ProjectRoot = (Get-Location).Path
Write-Host "🚀 Starting MxAgile refinement analysis..."

# --- 1. Load Baseline State from Trace Index ---
$traceIndexFile = Join-Path $ProjectRoot ".mxagile/state/trace-index.json"
if (-not (Test-Path $traceIndexFile)) {
    Write-Error "Traceability index not found. Please run mxagile-build-trace-index.ps1 first."
    return
}
$traceIndex = Get-Content -Path $traceIndexFile | ConvertFrom-Json
$baselineRefinements = $traceIndex.refinements

# --- 2. Scan Current State of Refinements Directory ---
$refinementsDir = Join-Path $ProjectRoot "refinements"
if (-not (Test-Path $refinementsDir)) {
    Write-Warning "No 'refinements' directory found. Nothing to analyze."
    return
}
$currentFiles = Get-ChildItem -Path $refinementsDir -Filter "*.yml" -Recurse

# --- 3. Compare Current State vs. Baseline ---
$report = @{
    New = [System.Collections.ArrayList]@()
    Changed = [System.Collections.ArrayList]@()
    Unchanged = [System.Collections.ArrayList]@()
    Deleted = [System.Collections.ArrayList]@()
}

$indexedFiles = @{ }
$baselineRefinements.psobject.properties | ForEach-Object {
    $indexedFiles[$_.Name] = $_.Value
}

foreach ($file in $currentFiles) {
    # Helper function to parse ID from YAML file
    $id = Get-Content -Path $file.FullName | Select-String -Pattern "^ID: (.*)" | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
    if (-not $id) { 
        Write-Warning "File $($file.Name) is missing an ID and will be skipped."
        continue
    }

    $currentHash = Get-FileHash -Algorithm SHA256 -Path $file.FullName | Select-Object -ExpandProperty Hash

    if ($indexedFiles.ContainsKey($id)) {
        $baselineHash = $indexedFiles[$id].FileHash
        if ($currentHash -eq $baselineHash) {
            [void]$report.Unchanged.Add($file.Name)
        } else {
            [void]$report.Changed.Add($file.Name)
        }
        # Remove from the list of indexed files to track what's left (for deletions)
        $indexedFiles.Remove($id)
    } else {
        [void]$report.New.Add($file.Name)
    }
}

# Any files remaining in indexedFiles have been deleted
$indexedFiles.Keys | ForEach-Object { [void]$report.Deleted.Add($_) }

# --- 4. Generate Report ---
Write-Host "Refinement analysis complete. Generating report..."
$reportPath = Join-Path $ProjectRoot "refinement-report.md"

$reportContent = @"
# MxAgile Refinement Report

This report summarizes the changes detected in the 'refinements' directory since the last baseline.

## Summary

| Status      | Count |
|-------------|-------|
| New         | $($report.New.Count) |
| Changed     | $($report.Changed.Count) |
| Unchanged   | $($report.Unchanged.Count) |
| Deleted     | $($report.Deleted.Count) |

## Details

### New Files
$($report.New -join "
- ")

### Changed Files
$($report.Changed -join "
- ")

### Deleted Files
$($report.Deleted -join "
- ")

"@

# Add a leading ' - ' if the lists are not empty
if ($report.New.Count -gt 0) { $reportContent = $reportContent.Replace("New Files
", "New Files
- ") }
if ($report.Changed.Count -gt 0) { $reportContent = $reportContent.Replace("Changed Files
", "Changed Files
- ") }
if ($report.Deleted.Count -gt 0) { $reportContent = $reportContent.Replace("Deleted Files
", "Deleted Files
- ") }

$reportContent | Set-Content -Path $reportPath

Write-Host "✅ Report generated successfully at: $reportPath"
"@
