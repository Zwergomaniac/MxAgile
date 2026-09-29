# Test suite for the consolidated artifact index builder (artifact-index.json).
# Covers: basic generation, content-based idempotency, change propagation, ghost nodes,
# page directory (planning/ui-inventory/), DERIVED_FROM, APPLIES_TO, COVERS edges,
# scenario nodes, and source_fingerprint.

try {

    # --- Setup ---
    $TestDir = Join-Path $env:TEMP "tmp-test-artifact-trace-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    if (Test-Path $TestDir) { Remove-Item -Recurse -Force $TestDir }
    New-Item -ItemType Directory -Path $TestDir | Out-Null

    $SpecDir   = Join-Path $TestDir "specs"
    $ReqDir    = Join-Path $TestDir "requirements"
    $PageDir   = Join-Path $TestDir "planning\ui-inventory"
    $ScenDir   = Join-Path $TestDir "planning\scenarios"
    New-Item -ItemType Directory -Path $SpecDir   | Out-Null
    New-Item -ItemType Directory -Path $ReqDir    | Out-Null
    New-Item -ItemType Directory -Path $PageDir   | Out-Null
    New-Item -ItemType Directory -Path $ScenDir   | Out-Null

    $PSScriptRoot       = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $BuilderScriptPath  = Join-Path $PSScriptRoot "..\scripts\build_artifact_index.py"
    $IndexPath          = Join-Path $TestDir ".mxagile\state\artifact-index.json"

    function Assert-Condition {
        param ($Condition, $Message)
        if (-not $Condition) { throw "Assertion Failed: $Message" }
    }

    function Get-IndexContent {
        # Return parsed JSON, stripping generated_at so content comparisons are stable.
        $raw = Get-Content $IndexPath -Raw | ConvertFrom-Json
        $raw.PSObject.Properties.Remove('generated_at')
        return ($raw | ConvertTo-Json -Depth 20 -Compress)
    }

    # --- Test 1: Deletion and Regeneration ---
    Write-Host "[TEST] Running: Deletion and Regeneration"
    & python $BuilderScriptPath $TestDir
    Assert-Condition (Test-Path $IndexPath) "Index file was not created on the first run."
    Remove-Item -Path $IndexPath
    & python $BuilderScriptPath $TestDir
    Assert-Condition (Test-Path $IndexPath) "Index file was not recreated after deletion."
    Write-Host "[PASS] Deletion and Regeneration"

    # --- Test 2: Content Idempotency (not file-hash, because generated_at changes) ---
    Write-Host "[TEST] Running: Content Idempotency"
    $content1 = Get-IndexContent
    & python $BuilderScriptPath $TestDir
    $content2 = Get-IndexContent
    Assert-Condition ($content1 -eq $content2) "Index content changed on second run with no file changes (idempotency broken)."
    Write-Host "[PASS] Content Idempotency"

    # --- Test 3: Change Propagation (spec file modified) ---
    Write-Host "[TEST] Running: Change Propagation"
    $specFilePath = Join-Path $SpecDir "SPEC-01.yml"
    Set-Content -Path $specFilePath -Value "ID: SPEC-01`nName: My First Spec"
    & python $BuilderScriptPath $TestDir
    $indexJson      = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $originalHash   = ($indexJson.nodes | Where-Object { $_.id -eq 'SPEC-01' }).hash
    Assert-Condition ($null -ne $originalHash) "Could not find SPEC-01 in index before change."
    Add-Content -Path $specFilePath -Value "`nDescription: A change"
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $newHash    = ($indexJson.nodes | Where-Object { $_.id -eq 'SPEC-01' }).hash
    Assert-Condition ($originalHash -ne $newHash) "Hash for modified SPEC-01 did not change."
    Write-Host "[PASS] Change Propagation"

    # --- Test 4: Ghost Node Detection ---
    Write-Host "[TEST] Running: Ghost Node Detection"
    Remove-Item -Path $specFilePath
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $ghostNode  = $indexJson.nodes | Where-Object { $_.id -eq 'SPEC-01' }
    Assert-Condition (-not $ghostNode) "Node for deleted SPEC-01 still exists in the index."
    Write-Host "[PASS] Ghost Node Detection"

    # --- Test 5: IMPLEMENTED_BY Edge (req -> spec) ---
    Write-Host "[TEST] Running: IMPLEMENTED_BY Edge (req -> spec)"
    $reqFilePath    = Join-Path $ReqDir "REQ-01.yml"
    $specFilePath   = Join-Path $SpecDir "SPEC-02.yml"
    Set-Content -Path $reqFilePath  -Value "ID: REQ-01`nName: A requirement"
    Set-Content -Path $specFilePath -Value "ID: SPEC-02`nName: Another spec`nrequirements: [REQ-01]"
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $edge       = $indexJson.edges | Where-Object { $_.from -eq 'REQ-01' -and $_.to -eq 'SPEC-02' -and $_.type -eq 'IMPLEMENTED_BY' }
    Assert-Condition ($edge) "IMPLEMENTED_BY edge from REQ-01 to SPEC-02 was not created."
    Write-Host "[PASS] IMPLEMENTED_BY Edge"

    # --- Test 6: Page node in planning/ui-inventory/ ---
    Write-Host "[TEST] Running: Page node from planning/ui-inventory/"
    $pageFilePath = Join-Path $PageDir "PAGE-CALENDAR.yaml"
    Set-Content -Path $pageFilePath -Value "page_id: PAGE-CALENDAR`npurpose: Calendar view"
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $pageNode   = $indexJson.nodes | Where-Object { $_.id -eq 'PAGE-CALENDAR' }
    Assert-Condition ($pageNode) "Page node PAGE-CALENDAR not found in index (expected in planning/ui-inventory/)."
    Write-Host "[PASS] Page node from planning/ui-inventory/"

    # --- Test 7: DERIVED_FROM Edge (page -> req via derivedFrom) ---
    Write-Host "[TEST] Running: DERIVED_FROM Edge"
    $req2FilePath = Join-Path $ReqDir "REQ-02.yml"
    Set-Content -Path $req2FilePath -Value "ID: REQ-02`nName: Calendar req`nderivationFrom: PAGE-CALENDAR"
    # Note: build_artifact_index checks 'derivedFrom' field
    Set-Content -Path $req2FilePath -Value "ID: REQ-02`nName: Calendar req`nderivedFrom: PAGE-CALENDAR"
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $dfEdge     = $indexJson.edges | Where-Object { $_.from -eq 'PAGE-CALENDAR' -and $_.to -eq 'REQ-02' -and $_.type -eq 'DERIVED_FROM' }
    Assert-Condition ($dfEdge) "DERIVED_FROM edge from PAGE-CALENDAR to REQ-02 was not created."
    Write-Host "[PASS] DERIVED_FROM Edge"

    # --- Test 8: APPLIES_TO Edge (req with screens[]) ---
    Write-Host "[TEST] Running: APPLIES_TO Edge"
    $req3FilePath = Join-Path $ReqDir "REQ-03.yml"
    Set-Content -Path $req3FilePath -Value "ID: REQ-03`nName: Multi-screen req`nscreens: [PAGE-CALENDAR]"
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $atEdge     = $indexJson.edges | Where-Object { $_.from -eq 'REQ-03' -and $_.to -eq 'PAGE-CALENDAR' -and $_.type -eq 'APPLIES_TO' }
    Assert-Condition ($atEdge) "APPLIES_TO edge from REQ-03 to PAGE-CALENDAR was not created."
    Write-Host "[PASS] APPLIES_TO Edge"

    # --- Test 9: Scenario node and COVERS edge ---
    Write-Host "[TEST] Running: Scenario node and COVERS edge"
    $scenFilePath = Join-Path $ScenDir "SCEN-01.yaml"
    $scenContent = @"
scenario_id: SCEN-01
screen_id: PAGE-CALENDAR
traceability:
  requirements: [REQ-01]
"@
    Set-Content -Path $scenFilePath -Value $scenContent
    & python $BuilderScriptPath $TestDir
    $indexJson  = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $scenNode   = $indexJson.nodes | Where-Object { $_.id -eq 'SCEN-01' }
    Assert-Condition ($scenNode) "Scenario node SCEN-01 not found in index."
    $coversEdge = $indexJson.edges | Where-Object { $_.from -eq 'SCEN-01' -and $_.to -eq 'REQ-01' -and $_.type -eq 'COVERS' }
    Assert-Condition ($coversEdge) "COVERS edge from SCEN-01 to REQ-01 was not created."
    $verifyEdge = $indexJson.edges | Where-Object { $_.from -eq 'PAGE-CALENDAR' -and $_.to -eq 'SCEN-01' -and $_.type -eq 'VERIFIED_BY' }
    Assert-Condition ($verifyEdge) "VERIFIED_BY edge from PAGE-CALENDAR to SCEN-01 was not created."
    Write-Host "[PASS] Scenario node and COVERS edge"

    # --- Test 10: source_fingerprint is present and stable ---
    Write-Host "[TEST] Running: source_fingerprint"
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    Assert-Condition ($indexJson.source_fingerprint -match '^sha256:[0-9a-f]{64}$') "source_fingerprint is missing or malformed."
    $fp1 = $indexJson.source_fingerprint
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $fp2 = $indexJson.source_fingerprint
    Assert-Condition ($fp1 -eq $fp2) "source_fingerprint changed between runs with no file changes."
    Write-Host "[PASS] source_fingerprint"

} catch {
    Write-Error "A test failed: $_"
    exit 1
} finally {
    if (Test-Path $TestDir) {
        Remove-Item -Recurse -Force $TestDir -ErrorAction SilentlyContinue
        Write-Host "[INFO] Cleaned up test directory."
    }
}

Write-Host "`n✅ All tests in test-artifact-trace-index.ps1 passed."
exit 0
