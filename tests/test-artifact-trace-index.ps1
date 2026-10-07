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

    # --- Test 11: Edge provenance field present on DECLARED edges ---
    Write-Host "[TEST] Running: Edge provenance field"
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $sampleEdge = $indexJson.edges | Where-Object { $_.type -eq 'IMPLEMENTED_BY' } | Select-Object -First 1
    Assert-Condition ($null -ne $sampleEdge) "No IMPLEMENTED_BY edge found for provenance test."
    Assert-Condition ($null -ne $sampleEdge.provenance) "Edge provenance field is missing."
    Assert-Condition ($sampleEdge.provenance.type -eq 'DECLARED') "Edge provenance.type expected DECLARED, got: $($sampleEdge.provenance.type)"
    Assert-Condition ($sampleEdge.provenance.source -ne '') "Edge provenance.source is empty."
    Write-Host "[PASS] Edge provenance field"

    # --- Test 12: graph-state.yaml written after build ---
    Write-Host "[TEST] Running: graph-state.yaml written after build"
    $stateFilePath = Join-Path $TestDir ".mxagile\state\graph-state.yaml"
    Assert-Condition (Test-Path $stateFilePath) "graph-state.yaml was not written after build."
    $stateContent = Get-Content $stateFilePath -Raw
    Assert-Condition ($stateContent -match 'status: READY') "graph-state.yaml does not contain status: READY"
    Assert-Condition ($stateContent -match 'provider: artifact-index') "graph-state.yaml missing provider"
    Assert-Condition ($stateContent -match 'sha256:') "graph-state.yaml missing source_fingerprint"
    Write-Host "[PASS] graph-state.yaml written after build"

    # --- Test 13: DEPENDS_ON edge (task -> task) ---
    Write-Host "[TEST] Running: DEPENDS_ON Edge (task -> task)"
    $TaskDir = Join-Path $TestDir "planning\tasks"
    New-Item -ItemType Directory -Path $TaskDir -Force | Out-Null
    $task1Path = Join-Path $TaskDir "TASK-01.yml"
    $task2Path = Join-Path $TaskDir "TASK-02.yml"
    Set-Content -Path $task1Path -Value "ID: TASK-01`naction: First task`nspec: SPEC-02"
    $task2Content = @"
ID: TASK-02
action: Second task
spec: SPEC-02
depends_on: [TASK-01]
"@
    Set-Content -Path $task2Path -Value $task2Content
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $depEdge = $indexJson.edges | Where-Object { $_.from -eq 'TASK-02' -and $_.to -eq 'TASK-01' -and $_.type -eq 'DEPENDS_ON' }
    Assert-Condition ($depEdge) "DEPENDS_ON edge from TASK-02 to TASK-01 was not created."
    Assert-Condition ($depEdge.provenance.type -eq 'DECLARED') "DEPENDS_ON edge should be DECLARED."
    Write-Host "[PASS] DEPENDS_ON Edge"

    # --- Test 14: TRACES_TO edge (task -> req) ---
    Write-Host "[TEST] Running: TRACES_TO Edge (task -> req)"
    $task3Path = Join-Path $TaskDir "TASK-03.yml"
    $task3Content = @"
ID: TASK-03
action: Third task
spec: SPEC-02
req: [REQ-01]
"@
    Set-Content -Path $task3Path -Value $task3Content
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $tracesEdge = $indexJson.edges | Where-Object { $_.from -eq 'TASK-03' -and $_.to -eq 'REQ-01' -and $_.type -eq 'TRACES_TO' }
    Assert-Condition ($tracesEdge) "TRACES_TO edge from TASK-03 to REQ-01 was not created."
    Write-Host "[PASS] TRACES_TO Edge"

    # --- Test 15: test_contract node + COVERS (TC->REQ) and PLANS (VPL->TC) edges ---
    Write-Host "[TEST] Running: TestContract + VerificationPlan nodes and edges"
    $TCDir  = Join-Path $TestDir "planning\test-contracts"
    $VPLDir = Join-Path $TestDir "planning\verification-plans"
    New-Item -ItemType Directory -Path $TCDir  -Force | Out-Null
    New-Item -ItemType Directory -Path $VPLDir -Force | Out-Null
    $tcContent = @"
ID: TC-001
title: Calendar TC
requirement_ids: [REQ-01]
"@
    $vplContent = @"
ID: VPL-001
title: Calendar VPL
test_contract_id: TC-001
"@
    Set-Content -Path (Join-Path $TCDir  "TC-001.yaml")  -Value $tcContent
    Set-Content -Path (Join-Path $VPLDir "VPL-001.yaml") -Value $vplContent
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $tcNode  = $indexJson.nodes | Where-Object { $_.id -eq 'TC-001' }
    Assert-Condition ($tcNode) "TC-001 node not found in index."
    Assert-Condition ($tcNode.type -eq 'test_contract') "TC-001 type expected test_contract, got: $($tcNode.type)"
    $coversTC = $indexJson.edges | Where-Object { $_.from -eq 'TC-001' -and $_.to -eq 'REQ-01' -and $_.type -eq 'COVERS' }
    Assert-Condition ($coversTC) "COVERS edge from TC-001 to REQ-01 was not created."
    $plansEdge = $indexJson.edges | Where-Object { $_.from -eq 'VPL-001' -and $_.to -eq 'TC-001' -and $_.type -eq 'PLANS' }
    Assert-Condition ($plansEdge) "PLANS edge from VPL-001 to TC-001 was not created."
    Write-Host "[PASS] TestContract + VerificationPlan nodes and edges"

    # --- Test 16: Decision node + GOVERNS and GOVERNS_SCREEN edges ---
    Write-Host "[TEST] Running: Decision node + GOVERNS edges"
    $DecDir = Join-Path $TestDir "planning\decisions"
    New-Item -ItemType Directory -Path $DecDir -Force | Out-Null
    $decContent = @"
ID: DEC-001
title: Calendar visibility
affected_requirements: [REQ-01]
affected_screens: [PAGE-CALENDAR]
"@
    Set-Content -Path (Join-Path $DecDir "DEC-001.yml") -Value $decContent
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $decNode = $indexJson.nodes | Where-Object { $_.id -eq 'DEC-001' }
    Assert-Condition ($decNode) "DEC-001 node not found in index."
    Assert-Condition ($decNode.type -eq 'decision') "DEC-001 type expected decision, got: $($decNode.type)"
    $govEdge  = $indexJson.edges | Where-Object { $_.from -eq 'DEC-001' -and $_.to -eq 'REQ-01' -and $_.type -eq 'GOVERNS' }
    Assert-Condition ($govEdge) "GOVERNS edge from DEC-001 to REQ-01 was not created."
    $govScrEdge = $indexJson.edges | Where-Object { $_.from -eq 'DEC-001' -and $_.to -eq 'PAGE-CALENDAR' -and $_.type -eq 'GOVERNS_SCREEN' }
    Assert-Condition ($govScrEdge) "GOVERNS_SCREEN edge from DEC-001 to PAGE-CALENDAR was not created."
    Write-Host "[PASS] Decision node + GOVERNS edges"

    # --- Test 17: COVERS_SPEC edge (scenario -> spec) ---
    Write-Host "[TEST] Running: COVERS_SPEC Edge (scenario -> spec)"
    $scen2FilePath = Join-Path $ScenDir "SCEN-02.yaml"
    $scen2Content = @"
scenario_id: SCEN-02
screen_id: PAGE-CALENDAR
traceability:
  requirements: [REQ-01]
  specs: [SPEC-02]
"@
    Set-Content -Path $scen2FilePath -Value $scen2Content
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $covSpecEdge = $indexJson.edges | Where-Object { $_.from -eq 'SCEN-02' -and $_.to -eq 'SPEC-02' -and $_.type -eq 'COVERS_SPEC' }
    Assert-Condition ($covSpecEdge) "COVERS_SPEC edge from SCEN-02 to SPEC-02 was not created."
    Write-Host "[PASS] COVERS_SPEC Edge"

    # --- Test 18: DEPENDS_ON_SCN edge (scenario -> scenario) ---
    Write-Host "[TEST] Running: DEPENDS_ON_SCN Edge"
    $scen3FilePath = Join-Path $ScenDir "SCEN-03.yaml"
    $scen3Content = @"
scenario_id: SCEN-03
screen_id: PAGE-CALENDAR
prerequisites:
  depends_on_scenarios: [SCEN-01]
traceability:
  requirements: [REQ-01]
"@
    Set-Content -Path $scen3FilePath -Value $scen3Content
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $depScnEdge = $indexJson.edges | Where-Object { $_.from -eq 'SCEN-03' -and $_.to -eq 'SCEN-01' -and $_.type -eq 'DEPENDS_ON_SCN' }
    Assert-Condition ($depScnEdge) "DEPENDS_ON_SCN edge from SCEN-03 to SCEN-01 was not created."
    Write-Host "[PASS] DEPENDS_ON_SCN Edge"

    # --- Test 19: SUPERSEDED_BY edge (decision -> decision) ---
    Write-Host "[TEST] Running: SUPERSEDED_BY Edge"
    $dec2Content = @"
ID: DEC-002
title: Calendar visibility v2
superseded_by: DEC-001
"@
    Set-Content -Path (Join-Path $DecDir "DEC-002.yml") -Value $dec2Content
    & python $BuilderScriptPath $TestDir
    $indexJson = Get-Content $IndexPath -Raw | ConvertFrom-Json
    $supEdge = $indexJson.edges | Where-Object { $_.from -eq 'DEC-002' -and $_.to -eq 'DEC-001' -and $_.type -eq 'SUPERSEDED_BY' }
    Assert-Condition ($supEdge) "SUPERSEDED_BY edge from DEC-002 to DEC-001 was not created."
    Write-Host "[PASS] SUPERSEDED_BY Edge"

    # --- Test 20: validate_edge_coverage.py passes ---
    Write-Host "[TEST] Running: Edge coverage validator"
    $ValidatorPath = Join-Path $PSScriptRoot "..\scripts\validate_edge_coverage.py"
    & python $ValidatorPath --path (Split-Path $BuilderScriptPath -Parent | Split-Path -Parent)
    Assert-Condition ($LASTEXITCODE -eq 0) "validate_edge_coverage.py reported failures (edge/schema drift detected)."
    Write-Host "[PASS] Edge coverage validator"

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
