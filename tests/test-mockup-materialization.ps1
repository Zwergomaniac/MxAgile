<#
.SYNOPSIS
    Mockup Materialization Contract Tests

.DESCRIPTION
    Validates the source materialization contract: static vs executable mockup classification,
    below-the-fold evidence, target evidence bundle, target/actual separation,
    equivalent state enforcement, legacy evidence reconciliation, and authoritative context.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir  = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestsDir
$PassCount   = 0
$FailCount   = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  FAIL: $TestName -- $Message" -ForegroundColor Red
        $script:FailCount++
        $script:FailDetails += "[$TestName] $Message"
    }
}
function Assert-FileContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -match $Pattern) "Pattern '$Pattern' not found in $FilePath" }
}
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$MatPol    = Join-Path $ScriptDir ".mxagile/policies/mockup-materialization.md"
$AnaPol    = Join-Path $ScriptDir ".mxagile/policies/mockup-analysis.md"
$PageSchema= Join-Path $ScriptDir ".mxagile/schemas/page.schema.json"
$EvSchema  = Join-Path $ScriptDir ".mxagile/schemas/evidence-manifest.schema.json"
$ParitySchema = Join-Path $ScriptDir ".mxagile/schemas/parity-verification.schema.json"
$EvidenceContract = Join-Path $ScriptDir ".mxagile/policies/evidence-contract.md"
$UiAgent   = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$FixDir    = Join-Path $ScriptDir "tests/fixtures/ui-parity"

# Test 1: Mockup type classification defined
Write-Host ""
Write-Host "TEST 1: Mockup type classification (static/executable/unknown)" -ForegroundColor Cyan
Assert-FileContains "1.1 materialization policy defines static type" $MatPol 'static'
Assert-FileContains "1.2 materialization policy defines executable type" $MatPol 'executable'
Assert-FileContains "1.3 page schema has mockup_type field" $PageSchema 'mockup_type'
Assert-FileContains "1.4 page schema has static/executable/unknown enum" $PageSchema '"static"'
Assert-FileContains "1.5 default is unknown (safe)" $PageSchema '"unknown"'
Assert-FileContains "1.6 mockup-analysis.md classifies mockup type" $AnaPol 'Typ klassifizieren'

# Test 2: Executable mockup contract — source inspection insufficient
Write-Host ""
Write-Host "TEST 2: Executable mockup — source inspection alone insufficient" -ForegroundColor Cyan
Assert-FileContains "2.1 materialization policy states source code reading alone is insufficient" $MatPol 'source-code reading alone is insufficient'
Assert-FileContains "2.2 mockup-analysis.md already requires browser execution" $AnaPol 'Playwright'
Assert-FileContains "2.3 materialization policy requires browser execution for executable" $MatPol 'browser execution.*Playwright'
Assert-FileExists "2.4 fixture Y exists (executable role-dependent labels)" (Join-Path $FixDir "fixture-Y-executable-mockup-role-dependent-labels.yaml")

# Test 3: Static mockup does not require scenario explosion
Write-Host ""
Write-Host "TEST 3: Static mockup does not require scenario explosion" -ForegroundColor Cyan
Assert-FileContains "3.1 materialization policy defines static mockup behavior" $MatPol 'Static Mockup Behavior'
Assert-FileContains "3.2 static mockup needs only one render per viewport" $MatPol 'single Playwright render per viewport'
Assert-FileExists "3.3 fixture X exists (static no explosion)" (Join-Path $FixDir "fixture-X-static-mockup-no-scenario-explosion.yaml")
$fixX = Get-Content -LiteralPath (Join-Path $FixDir "fixture-X-static-mockup-no-scenario-explosion.yaml") -Raw
Assert-True "3.4 fixture-X mockup_type is static" ($fixX -match 'mockup_type: static')

# Test 4: Below-the-fold evidence contract
Write-Host ""
Write-Host "TEST 4: Below-the-fold evidence — NOT VISIBLE != DOES NOT EXIST" -ForegroundColor Cyan
Assert-FileContains "4.1 materialization policy addresses below-the-fold" $MatPol 'Below-the-Fold'
Assert-FileContains "4.2 policy states NOT VISIBLE != DOES NOT EXIST" $MatPol 'NOT VISIBLE.*DOES NOT EXIST'
Assert-FileContains "4.3 policy requires DOM queries for navigation groups" $MatPol 'DOM queries.*navigation'
Assert-FileContains "4.4 mockup-analysis.md adds below-the-fold rule" $AnaPol 'Below-the-Fold'
Assert-FileExists "4.5 fixture AA exists (below-the-fold DOM)" (Join-Path $FixDir "fixture-AA-below-the-fold-evidence.yaml")

# Test 5: Target evidence bundle concept
Write-Host ""
Write-Host "TEST 5: Target evidence bundle defined" -ForegroundColor Cyan
Assert-FileContains "5.1 materialization policy defines target evidence bundle" $MatPol 'Target Evidence Bundle'
Assert-FileContains "5.2 target evidence bundle is per parity dimension" $MatPol 'Parity Dimension.*Required Target Evidence'

# Test 6: Target vs actual evidence separation
Write-Host ""
Write-Host "TEST 6: Target vs actual evidence separated in manifest" -ForegroundColor Cyan
Assert-FileContains "6.1 evidence manifest schema has target_evidence field" $EvSchema 'target_evidence'
Assert-FileContains "6.2 evidence manifest schema has actual_evidence field" $EvSchema 'actual_evidence'
Assert-FileContains "6.3 evidence artifact schema has source field (mockup/application)" $EvSchema '"source"'
Assert-FileContains "6.4 source enum has mockup and application values" $EvSchema '"mockup"'
Assert-FileContains "6.5 materialization policy defines target vs actual separation" $MatPol 'Target vs Actual Evidence Separation'

# Test 7: Equivalent state enforcement
Write-Host ""
Write-Host "TEST 7: Equivalent state enforcement — target role must match actual role" -ForegroundColor Cyan
Assert-FileContains "7.1 materialization policy defines equivalent state contract" $MatPol 'Equivalent State Enforcement'
Assert-FileContains "7.2 policy prohibits cross-role comparison" $MatPol 'Do NOT compare'
Assert-FileExists "7.3 fixture Z exists (equivalent state enforcement)" (Join-Path $FixDir "fixture-Z-equivalent-state-enforcement.yaml")
$fixZ = Get-Content -LiteralPath (Join-Path $FixDir "fixture-Z-equivalent-state-enforcement.yaml") -Raw
Assert-True "7.4 fixture-Z marks cross-role scenario as invalid" ($fixZ -match 'valid: false')

# Test 8: Existing target evidence reused before regenerating
Write-Host ""
Write-Host "TEST 8: Existing target evidence reused before regenerating" -ForegroundColor Cyan
$UiParityPol = Join-Path $ScriptDir ".mxagile/policies/ui-parity.md"
Assert-FileContains "8.1 ui-parity.md leaves validated dimensions untouched (reuse)" $UiParityPol 'Leave validated dimensions untouched'
Assert-FileContains "8.2 ui-parity.md defines REUSABLE classification (preserve)" $UiParityPol 'REUSABLE'
Assert-FileExists "8.3 fixture AB exists (target evidence reuse)" (Join-Path $FixDir "fixture-AB-target-evidence-reuse.yaml")
$fixAB = Get-Content -LiteralPath (Join-Path $FixDir "fixture-AB-target-evidence-reuse.yaml") -Raw
Assert-True "8.4 fixture-AB classifies unchanged evidence as REUSABLE" ($fixAB -match 'classification: REUSABLE')
Assert-True "8.5 fixture-AB classifies stale evidence for regeneration only" ($fixAB -match 'classification: STALE')

# Test 9: Legacy mockup evidence reconciliation
Write-Host ""
Write-Host "TEST 9: Legacy mockup evidence reconciliation" -ForegroundColor Cyan
Assert-FileContains "9.1 materialization policy defines legacy mockup evidence reconciliation" $MatPol 'Legacy Mockup Evidence Reconciliation'
Assert-FileContains "9.2 policy does not hard-code .concord/screenshots/mockup as canonical" $MatPol 'legacy.*locations'
Assert-FileExists "9.3 fixture AC exists (legacy screenshot promoted)" (Join-Path $FixDir "fixture-AC-legacy-target-screenshot-promoted.yaml")
$fixAC = Get-Content -LiteralPath (Join-Path $FixDir "fixture-AC-legacy-target-screenshot-promoted.yaml") -Raw
Assert-True "9.4 fixture-AC classifies as HISTORICAL_EVIDENCE with provenance" ($fixAC -match 'HISTORICAL_EVIDENCE')

# Test 10: Authoritative context resolves discrepancy before calling FAIL
Write-Host ""
Write-Host "TEST 10: Authoritative context (Requirement/Decision) resolves apparent discrepancy" -ForegroundColor Cyan
Assert-FileContains "10.1 materialization policy defines authoritative context check" $MatPol 'Authoritative Context Before Parity'
Assert-FileContains "10.2 policy lists Decision as resolving context" $MatPol 'Accepted Decision'
Assert-FileExists "10.3 fixture AD exists (decision resolves discrepancy)" (Join-Path $FixDir "fixture-AD-requirement-resolves-discrepancy.yaml")
$fixAD = Get-Content -LiteralPath (Join-Path $FixDir "fixture-AD-requirement-resolves-discrepancy.yaml") -Raw
Assert-True "10.4 fixture-AD results in PASS because Decision resolves apparent FAIL" ($fixAD -match 'result: PASS')

# Test 11: Refined target supersedes source for parity
Write-Host ""
Write-Host "TEST 11: Accepted refined target supersedes source for parity" -ForegroundColor Cyan
Assert-FileContains "11.1 materialization policy states active target is authoritative" $MatPol 'active.*target.*authoritative|refined.*target.*authoritative'
Assert-FileExists "11.2 fixture AE exists (refined target supersedes source)" (Join-Path $FixDir "fixture-AE-refined-target-supersedes-source.yaml")
$fixAE = Get-Content -LiteralPath (Join-Path $FixDir "fixture-AE-refined-target-supersedes-source.yaml") -Raw
Assert-True "11.3 fixture-AE parity compares against refined target not source" ($fixAE -match 'planning/target-mockups')

# Test 12: Legacy paths are not Core requirements
Write-Host ""
Write-Host "TEST 12: Legacy paths not required by Core" -ForegroundColor Cyan
Assert-FileExists "12.1 fixture AF exists (no legacy paths in core)" (Join-Path $FixDir "fixture-AF-no-legacy-paths-in-core.yaml")
$fixAF = Get-Content -LiteralPath (Join-Path $FixDir "fixture-AF-no-legacy-paths-in-core.yaml") -Raw
Assert-True "12.2 fixture-AF states sprints/decisions.md is legacy" ($fixAF -match 'sprints/decisions.*LEGACY')
Assert-True "12.3 fixture-AF states .concord/screenshots/mockup is legacy source" ($fixAF -match '\.concord.*LEGACY')

# Test 13: UI-Agent policy reference updated
Write-Host ""
Write-Host "TEST 13: UI-Agent references mockup-materialization policy" -ForegroundColor Cyan
Assert-FileContains "13.1 ui-agent.md references mockup-materialization policy" $UiAgent 'mockup-materialization.md'

# Test 14: Immutable comparison identity and visual capture provenance
Write-Host ""
Write-Host "TEST 14: Immutable comparison identity and atomic capture provenance" -ForegroundColor Cyan
Assert-FileContains "14.1 parity schema requires identity and matrix for schema v2" $ParitySchema 'schema_version.*2.*comparison_identity|comparison_identity.*evidence_matrix'
Assert-FileContains "14.2 comparison identity records canonical path, revision, fingerprint, page, role/state, app/model revision" $ParitySchema 'canonical_mockup_path.*revision.*fingerprint.*target_page.*roles.*states.*app_revision.*model_revision'
Assert-FileContains "14.3 changed identity is explicit REFERENCE_DRIFT" $ParitySchema 'REFERENCE_DRIFT'
Assert-FileContains "14.4 evidence manifest records capture groups" $EvSchema 'capture_groups'
Assert-FileContains "14.5 capture group binds capture_id and same-capture screenshot/snapshots" $EvSchema 'capture_id.*screenshot_path.*snapshots'
$evidenceSchema = Get-Content -LiteralPath $EvSchema -Raw | ConvertFrom-Json
Assert-True "14.5.1 capture groups distinguish mockup from application" `
    (@($evidenceSchema.definitions.capture_group.properties.capture_source.enum) -contains 'mockup' -and
     @($evidenceSchema.definitions.capture_group.properties.capture_source.enum) -contains 'application') `
    "capture_source enum must contain mockup and application"
Assert-FileContains "14.5.2 promoted capture groups require a BOUND identity" $EvSchema 'status.*BOUND'
Assert-FileContains "14.6 capture group records session, run, role, screen, URL and cleanliness" $EvSchema 'session_id'
Assert-FileContains "14.6.1 capture group records run ID and role" $EvSchema 'run_id'
Assert-FileContains "14.6.2 capture group records runtime URL and target screen" $EvSchema 'runtime_url'
Assert-FileContains "14.6.3 capture group records cleanliness state" $EvSchema 'cleanliness_state'
Assert-FileContains "14.7 promoted capture cleanliness is schema constrained" $EvSchema 'const.*clean'
Assert-FileContains "14.8 evidence contract rejects filename/timestamp pairing" $EvidenceContract 'Similar filenames, nearby timestamps'
Assert-FileContains "14.8.1 evidence contract requires explicit capture identity" $EvidenceContract 'do NOT establish capture identity'
Assert-FileContains "14.9 visual promotion requires opened reference and actual screenshots" $EvidenceContract 'reference and actual screenshots were opened'
Assert-FileContains "14.9.1 visual promotion requires actual visual inspection" $EvidenceContract 'visually\s+inspected'
Assert-FileContains "14.10 visual target must be rendered in a browser" $MatPol 'active target must be rendered in a browser'
Assert-FileContains "14.10.1 visual target binds the accepted revision" $MatPol 'accepted revision, role'
Assert-FileExists "14.11 REV-17/REV-9 reference-drift fixture exists" (Join-Path $FixDir "fixture-AO-rev17-selected-rev9-reference-drift.yaml")
$fixAO = Get-Content -LiteralPath (Join-Path $FixDir "fixture-AO-rev17-selected-rev9-reference-drift.yaml") -Raw
Assert-True "14.12 wrong revision is blocked as REFERENCE_DRIFT" ($fixAO -match 'revision: REV-17' -and $fixAO -match 'revision: REV-9' -and $fixAO -match 'status: REFERENCE_DRIFT') "fixture misses the revision-drift state"
Assert-True "14.13 unopened screenshots and unpaired DOM cannot claim visual PASS" ($fixAO -match 'screenshot_opened: false' -and $fixAO -match 'capture_id: null' -and $fixAO -match 'visual_whole_screen_parity: NOT_VERIFIED') "fixture does not block unreviewed/unpaired visual evidence"
Assert-True "14.14 drifted forensic run has no promotion or implementation scope" ($fixAO -match 'promotion: blocked' -and $fixAO -match 'implementation_scope: none' -and $fixAO -match 'overall_result: NOT_VERIFIED') "fixture allows downstream scope from invalid evidence"
Assert-FileContains "14.15 evidence artifacts bind to capture_id" $EvSchema 'capture_id'
Assert-FileContains "14.16 capture group repeats the immutable comparison identity" $EvSchema 'capture_group.*comparison_identity|comparison_identity.*runtime_url'
Assert-FileContains "14.17 separate capture groups are linked from evidence entries" $EvSchema 'capture_groups'
Assert-FileContains "14.18 legacy whole-screen PASS without paired inspected evidence is not current" $EvidenceContract 'not current evidence'
$manifestSchemaObject = Get-Content -LiteralPath $EvSchema -Raw | ConvertFrom-Json
$entryConditions = @($manifestSchemaObject.definitions.evidence_entry.allOf)
$captureCondition = $entryConditions | Where-Object {
    $conditionIf = $_.PSObject.Properties['if'].Value
    $null -ne $conditionIf.properties.PSObject.Properties['capture_groups']
} | Select-Object -First 1
$captureThen = if ($null -ne $captureCondition) { $captureCondition.then } else { $null }
Assert-True "14.19 evidence entries with capture groups require a shared comparison identity" `
    ($null -ne $captureThen -and @($captureThen.required) -contains 'comparison_identity') `
    "Capture-group conditional must require comparison_identity"
Assert-True "14.20 target and actual artifacts require capture_id when groups exist" `
    ($null -ne $captureThen -and @($captureThen.properties.target_evidence.items.required) -contains 'capture_id' -and @($captureThen.properties.actual_evidence.items.required) -contains 'capture_id') `
    "Capture-group conditional must require capture_id on target_evidence and actual_evidence items"

# ---------------------------------------------------------------------------
$total = $PassCount + $FailCount
Write-Host ""
Write-Host "=" * 60
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
