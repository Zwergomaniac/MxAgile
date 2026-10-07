# Test suite for graph_capability.py (provider-neutral KnowledgeGraph module).
# Covers: status(), build(), refresh(), query(), neighbors(), affected(), explain().
# Uses the same temp-directory fixture pattern as test-artifact-trace-index.ps1.

try {

    $TestDir = Join-Path $env:TEMP "tmp-test-graph-cap-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    if (Test-Path $TestDir) { Remove-Item -Recurse -Force $TestDir }
    New-Item -ItemType Directory -Path $TestDir | Out-Null

    $ReqDir  = Join-Path $TestDir "requirements"
    $SpecDir = Join-Path $TestDir "specs"
    $TaskDir = Join-Path $TestDir "planning\tasks"
    $PageDir = Join-Path $TestDir "planning\ui-inventory"
    $ScenDir = Join-Path $TestDir "planning\scenarios"
    foreach ($d in @($ReqDir, $SpecDir, $TaskDir, $PageDir, $ScenDir)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    $ScriptDir        = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
    if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
    $GraphCapPath     = Join-Path $ScriptDir "..\scripts\graph_capability.py"
    $BuilderPath      = Join-Path $ScriptDir "..\scripts\build_artifact_index.py"
    $IndexPath        = Join-Path $TestDir ".mxagile\state\artifact-index.json"
    $StateFilePath    = Join-Path $TestDir ".mxagile\state\graph-state.yaml"

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) { throw "Assertion Failed: $Message" }
    }

    function Invoke-GraphCap {
        param ([string[]]$GraphArgs)
        # Capture stdout only (stderr has [INFO]/[DEBUG] lines that pollute JSON output)
        $output = & python $GraphCapPath --path $TestDir @GraphArgs 2>$null
        return $output -join "`n"
    }

    # --- Setup: write minimal fixture artifacts ---
    Set-Content (Join-Path $ReqDir  "REQ-01.yml")       -Value "ID: REQ-01`nName: Req one"
    Set-Content (Join-Path $ReqDir  "REQ-02.yml")       -Value "ID: REQ-02`nName: Req two`nscreens: [PAGE-MAIN]"
    Set-Content (Join-Path $SpecDir "SPEC-01.yml")      -Value "ID: SPEC-01`nrequirements: [REQ-01]"
    Set-Content (Join-Path $TaskDir "TASK-01.yml")      -Value "ID: TASK-01`naction: Do it`nspec: SPEC-01"
    Set-Content (Join-Path $PageDir "PAGE-MAIN.yaml")   -Value "page_id: PAGE-MAIN`npurpose: Main page"
    $scenContent = @"
scenario_id: SCEN-01
screen_id: PAGE-MAIN
traceability:
  requirements: [REQ-01]
"@
    Set-Content (Join-Path $ScenDir "SCEN-01.yaml") -Value $scenContent

    # --- Test 1: status() returns MISSING before first build ---
    Write-Host "[TEST] Running: status() returns MISSING before build"
    $statusOut = Invoke-GraphCap @("status")
    Assert-Condition ($statusOut -match '"status"') "status() did not return JSON with status field."
    Assert-Condition (($statusOut -match 'MISSING') -or ($statusOut -match 'DISABLED')) "Expected MISSING or DISABLED before first build."
    Write-Host "[PASS] status() MISSING before build"

    # --- Test 2: build() succeeds and index is created ---
    Write-Host "[TEST] Running: build() creates index"
    $buildOut = Invoke-GraphCap @("build")
    Assert-Condition ($buildOut -match '"success"') "build() did not return JSON."
    Assert-Condition ($buildOut -match '"success": true') "build() reported failure: $buildOut"
    Assert-Condition (Test-Path $IndexPath) "artifact-index.json not found after build()."
    Write-Host "[PASS] build() creates index"

    # --- Test 3: status() returns READY after build ---
    Write-Host "[TEST] Running: status() returns READY after build"
    $statusOut = Invoke-GraphCap @("status")
    Assert-Condition ($statusOut -match 'READY') "Expected READY status after build, got: $statusOut"
    Assert-Condition ($statusOut -match '"node_count"') "status() missing node_count."
    Assert-Condition ($statusOut -match '"edge_count"') "status() missing edge_count."
    Write-Host "[PASS] status() READY after build"

    # --- Test 4: refresh() is a no-op when index is current ---
    Write-Host "[TEST] Running: refresh() no-op when current"
    $refreshOut = Invoke-GraphCap @("refresh")
    Assert-Condition ($refreshOut -match 'current') "Expected 'current' message from refresh when index is up to date."
    Write-Host "[PASS] refresh() no-op"

    # --- Test 5: query() returns filtered nodes by type ---
    Write-Host "[TEST] Running: query() by type"
    $queryOut = Invoke-GraphCap @("query", "--type", "requirement")
    $queryJson = $queryOut | ConvertFrom-Json
    Assert-Condition ($queryJson.Count -eq 2) "Expected 2 requirement nodes, got $($queryJson.Count)."
    $ids = $queryJson | ForEach-Object { $_.id }
    Assert-Condition ($ids -contains 'REQ-01') "REQ-01 not in query results."
    Assert-Condition ($ids -contains 'REQ-02') "REQ-02 not in query results."
    Write-Host "[PASS] query() by type"

    # --- Test 6: query() by id pattern ---
    Write-Host "[TEST] Running: query() by id pattern"
    $queryOut = Invoke-GraphCap @("query", "--id", "REQ-01")
    $queryJson = $queryOut | ConvertFrom-Json
    Assert-Condition ($queryJson.Count -eq 1) "Expected 1 result for id=REQ-01, got $($queryJson.Count)."
    Assert-Condition ($queryJson[0].id -eq 'REQ-01') "Wrong id in result."
    Write-Host "[PASS] query() by id pattern"

    # --- Test 7: neighbors() returns outgoing edges ---
    Write-Host "[TEST] Running: neighbors() outgoing"
    $nbrOut = Invoke-GraphCap @("neighbors", "REQ-01", "--direction", "out")
    $nbrJson = $nbrOut | ConvertFrom-Json
    Assert-Condition ($null -ne $nbrJson.outgoing) "neighbors() missing outgoing key."
    # REQ-01 is target of IMPLEMENTED_BY from SPEC-01 (incoming), not outgoing
    # REQ-01 has outgoing? No — SPEC-01.requirements contains REQ-01, so IMPLEMENTED_BY goes REQ-01→SPEC-01
    # Wait: edge is (REQ-01 -> SPEC-01, IMPLEMENTED_BY). So outgoing of REQ-01 should include SPEC-01.
    $outIds = $nbrJson.outgoing | ForEach-Object { $_.node.id }
    Assert-Condition ($outIds -contains 'SPEC-01') "Expected SPEC-01 in outgoing neighbors of REQ-01."
    Write-Host "[PASS] neighbors() outgoing"

    # --- Test 8: affected() finds downstream nodes ---
    Write-Host "[TEST] Running: affected() BFS"
    $affOut = Invoke-GraphCap @("affected", "REQ-01")
    $affJson = $affOut | ConvertFrom-Json
    Assert-Condition ($null -ne $affJson.affected) "affected() missing 'affected' key."
    $affIds = $affJson.affected | ForEach-Object { $_.id }
    # REQ-01 -> SPEC-01 -> TASK-01 should be in affected set
    Assert-Condition ($affIds -contains 'SPEC-01') "SPEC-01 not in affected set for REQ-01."
    Assert-Condition ($affIds -contains 'TASK-01') "TASK-01 not in affected set for REQ-01."
    Write-Host "[PASS] affected() BFS"

    # --- Test 9: explain() returns edge with provenance ---
    Write-Host "[TEST] Running: explain() edge provenance"
    $explainOut = Invoke-GraphCap @("explain", "REQ-01", "SPEC-01")
    $explainJson = $explainOut | ConvertFrom-Json
    Assert-Condition ($explainJson.Count -gt 0) "explain() returned no edges for REQ-01->SPEC-01."
    Assert-Condition ($null -ne $explainJson[0].provenance) "explain() edge missing provenance field."
    Assert-Condition ($explainJson[0].provenance.type -eq 'DECLARED') "Expected DECLARED provenance for IMPLEMENTED_BY."
    Write-Host "[PASS] explain() edge provenance"

    # --- Test 10: refresh() rebuilds after file change ---
    Write-Host "[TEST] Running: refresh() rebuilds when stale"
    Add-Content (Join-Path $ReqDir "REQ-01.yml") -Value "`nDescription: Updated"
    $refreshOut = Invoke-GraphCap @("refresh")
    Assert-Condition ($refreshOut -match '"success": true') "refresh() failed after file change: $refreshOut"
    Write-Host "[PASS] refresh() rebuilds when stale"

    # --- Test 11: paths() finds directed path between two connected nodes ---
    Write-Host "[TEST] Running: paths() between REQ-01 and TASK-01"
    # Fixture: REQ-01 -> SPEC-01 -> TASK-01 is the edge chain (IMPLEMENTED_BY + REALIZES)
    # Re-run build to ensure index is current after the REQ-01 update
    $null = Invoke-GraphCap @("build") 2>$null
    $pathsOut = Invoke-GraphCap @("paths", "REQ-01", "TASK-01", "--max-depth", "5")
    Assert-Condition ($pathsOut -match '"paths"') "paths() did not return JSON with 'paths' key."
    $pathsJson = $pathsOut | ConvertFrom-Json
    Assert-Condition ($pathsJson.paths.Count -gt 0) "Expected at least 1 path from REQ-01 to TASK-01."
    # Verify the path actually passes through SPEC-01
    $pathNodes = $pathsJson.paths[0] | ForEach-Object { $_.node_id }
    Assert-Condition ($pathNodes -contains 'SPEC-01') "Expected path to include SPEC-01 as intermediate node."
    Write-Host "[PASS] paths() finds directed path"

    # --- Test 12: disabled graph (provider=none) returns DISABLED ---
    Write-Host "[TEST] Running: disabled graph returns DISABLED"
    $MxagileDir = Join-Path $TestDir ".mxagile"
    if (-not (Test-Path $MxagileDir)) { New-Item -ItemType Directory -Path $MxagileDir -Force | Out-Null }
    Set-Content (Join-Path $MxagileDir "config.yaml") -Value "knowledge_graph:`n  provider: none"
    $disabledOut = Invoke-GraphCap @("status")
    Assert-Condition ($disabledOut -match 'DISABLED') "Expected DISABLED when provider=none, got: $disabledOut"
    # Data operations must return empty results, not errors
    $queryDisabledOut = Invoke-GraphCap @("query", "--type", "requirement")
    $queryDisabledJson = $queryDisabledOut | ConvertFrom-Json
    Assert-Condition ($queryDisabledJson.Count -eq 0) "query() with DISABLED provider should return empty list."
    Write-Host "[PASS] disabled graph returns DISABLED and empty data"

    # --- Test 13: failed-provider fallback — corrupt index falls back gracefully ---
    Write-Host "[TEST] Running: failed-provider fallback"
    # Restore provider=artifact-index so fallback behavior applies
    Set-Content (Join-Path $MxagileDir "config.yaml") -Value "knowledge_graph:`n  provider: artifact-index"
    # Corrupt the index file
    $IndexDir = Join-Path $TestDir ".mxagile\state"
    if (-not (Test-Path $IndexDir)) { New-Item -ItemType Directory -Path $IndexDir -Force | Out-Null }
    Set-Content (Join-Path $IndexDir "artifact-index.json") -Value "NOT_VALID_JSON{"
    $affFallbackOut = Invoke-GraphCap @("affected", "REQ-01")
    # Must return a valid JSON response (not crash), and include fallback indicator or empty affected
    $affFallbackJson = $affFallbackOut | ConvertFrom-Json
    Assert-Condition ($null -ne $affFallbackJson) "affected() with corrupt index must return valid JSON."
    Assert-Condition ($null -ne $affFallbackJson.affected) "affected() fallback must include 'affected' key."
    Write-Host "[PASS] failed-provider fallback returns gracefully"

    # --- Test 14: non-canonical edges cannot establish lifecycle truth ---
    Write-Host "[TEST] Running: non-canonical edges cannot establish lifecycle truth"
    # Rebuild a clean index
    Remove-Item (Join-Path $IndexDir "artifact-index.json") -ErrorAction SilentlyContinue
    $null = Invoke-GraphCap @("build") 2>$null
    # The index should contain REQ-01. Now verify the index is advisory only:
    # REQ-01 appears in the index as READY — but the lifecycle gate is canonical YAML, not graph.
    # Test: query() returns REQ-01 as an indexed node...
    $reqNodes = (Invoke-GraphCap @("query", "--id", "REQ-01") | ConvertFrom-Json)
    Assert-Condition ($reqNodes.Count -eq 1) "REQ-01 should appear in rebuilt index."
    # ...but the graph has no authority to override canonical YAML — verified by checking
    # that there is no 'lifecycle_status' or 'handoff_ready' field asserted in the graph node.
    # (Graph nodes carry structural facts, not lifecycle decisions.)
    $reqNode = $reqNodes[0]
    $graphAssertsHandoff = ($reqNode.PSObject.Properties.Name -contains 'handoff_ready') -or
                           ($reqNode.PSObject.Properties.Name -contains 'lifecycle_status')
    Assert-Condition (-not $graphAssertsHandoff) "Graph node must not carry lifecycle_status or handoff_ready — those are canonical YAML authority only."
    Write-Host "[PASS] non-canonical edges carry no lifecycle authority"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    if (Test-Path $TestDir) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
        Write-Host "[INFO] Cleaned up test directory."
    }
}

Write-Host "`n[OK] All tests in test-graph-capability.ps1 passed."
exit 0
