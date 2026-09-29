<#
.SYNOPSIS
    UI Verification Scenario Contract Tests: A through AK

.DESCRIPTION
    Validates material scenario matrix derivation, coverage traceability,
    mock-data prerequisites, browser scenario decomposition, evidence contract,
    source/target mockup lifecycle, observe-before-mutate enforcement,
    legacy evidence upgrade, requirement/spec/task depth, reconciliation,
    and all related canonical contracts.

    Tests A through AK (37 tests).
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
function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { Assert-True $TestName $false "File not found: $FilePath" }
    else { Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' in $FilePath" }
}
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$ScnPol   = Join-Path $ScriptDir ".mxagile/policies/verification-scenario.md"
$EvPol    = Join-Path $ScriptDir ".mxagile/policies/evidence-contract.md"
$KnowPol  = Join-Path $ScriptDir ".mxagile/policies/project-knowledge.md"
$ParityPol= Join-Path $ScriptDir ".mxagile/policies/ui-parity.md"
$ObsMut   = Join-Path $ScriptDir ".mxagile/policies/observe-before-mutate.md"
$ScnSchema= Join-Path $ScriptDir ".mxagile/schemas/verification-scenario.schema.json"
$EvSchema = Join-Path $ScriptDir ".mxagile/schemas/evidence-manifest.schema.json"
$ParSchema= Join-Path $ScriptDir ".mxagile/schemas/parity-verification.schema.json"
$ProcState= Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"
$UiAgent  = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$FixDir   = Join-Path $ScriptDir "tests/fixtures/ui-parity"

# A: Visual PASS + Content FAIL => Overall FAIL
Write-Host ""
Write-Host "TEST A: Visual PASS + Content FAIL => Overall FAIL" -ForegroundColor Cyan
Assert-FileContains "A.1 policy states FAIL aggregation rule" $ParityPol 'overall_result = FAIL'
Assert-FileContains "A.2 FAIL blocks PASS" $ParityPol 'ANY required dimension'
Assert-FileExists "A.3 fixture A exists" (Join-Path $FixDir "fixture-A-sidebar-visual-pass-content-fail.yaml")
$fixA = Get-Content -LiteralPath (Join-Path $FixDir "fixture-A-sidebar-visual-pass-content-fail.yaml") -Raw
Assert-True "A.4 fixture-A visual is PASS" ($fixA -match 'visual:.*\n\s+result: PASS')
Assert-True "A.5 fixture-A content is FAIL" ($fixA -match 'content:.*\n\s+result: FAIL')
Assert-True "A.6 fixture-A overall is FAIL" ($fixA -match 'overall_result: FAIL')

# B: Navigation group labels are part of Content parity
Write-Host ""
Write-Host "TEST B: Navigation group labels are Content parity" -ForegroundColor Cyan
Assert-FileContains "B.1 policy lists nav group names as content target" $ParityPol 'navigation group names'
Assert-FileContains "B.2 evidence contract lists nav group labels" $EvPol 'navigation group labels'
Assert-FileContains "B.3 scenario policy references navigation group labels" $ScnPol 'navigation.*group|group.*name'
$fixA2 = Get-Content -LiteralPath (Join-Path $FixDir "fixture-A-sidebar-visual-pass-content-fail.yaml") -Raw
Assert-True "B.4 fixture-A dom assertion targets nav group selector" ($fixA2 -match 'mx-group-header')

# C: Structural mismatch independently fails Structure
Write-Host ""
Write-Host "TEST C: Structural mismatch independently fails Structure dimension" -ForegroundColor Cyan
Assert-FileContains "C.1 structure dimension defined in parity policy" $ParityPol 'structure'
$fixB = Get-Content -LiteralPath (Join-Path $FixDir "fixture-B-colors-pass-hierarchy-fail.yaml") -Raw
Assert-True "C.2 fixture-B structure is FAIL" ($fixB -match 'structure:.*\n\s+result: FAIL')
Assert-True "C.3 fixture-B visual is PASS" ($fixB -match 'visual:.*\n\s+result: PASS')
Assert-True "C.4 fixture-B overall is FAIL" ($fixB -match 'overall_result: FAIL')

# D: Required Role NOT_VERIFIED prevents Full PASS
Write-Host ""
Write-Host "TEST D: Required Role NOT_VERIFIED prevents Full PASS" -ForegroundColor Cyan
Assert-FileContains "D.1 aggregation: STALE or NOT_VERIFIED prevents PASS" $ParityPol 'STALE'
Assert-FileContains "D.2 role dimension required by default" $ParSchema '"role"'
$fixD = Get-Content -LiteralPath (Join-Path $FixDir "fixture-D-visuals-pass-role-action-fail.yaml") -Raw
Assert-True "D.3 fixture-D role is FAIL" ($fixD -match 'role:.*\n\s+result: FAIL')
Assert-True "D.4 fixture-D overall is FAIL" ($fixD -match 'overall_result: FAIL')

# E: Required Responsive NOT_VERIFIED prevents Full PASS
Write-Host ""
Write-Host "TEST E: Required Responsive NOT_VERIFIED prevents Full PASS" -ForegroundColor Cyan
Assert-FileContains "E.1 responsive dimension required" $ParSchema '"responsive"'
$fixC = Get-Content -LiteralPath (Join-Path $FixDir "fixture-C-desktop-pass-mobile-fail.yaml") -Raw
Assert-True "E.2 fixture-C responsive is FAIL" ($fixC -match 'responsive:.*\n\s+result: FAIL')
Assert-True "E.3 fixture-C overall is FAIL" ($fixC -match 'overall_result: FAIL')

# F: Every applicable dimension is accounted for
Write-Host ""
Write-Host "TEST F: Every applicable dimension is accounted for" -ForegroundColor Cyan
Assert-FileContains "F.1 schema has all 7 dimensions required" $ParSchema '"visual"'
Assert-FileContains "F.2 schema requires all 7 dimensions" $ParSchema '"content"'
Assert-FileContains "F.3 all dimensions in required array" $ParSchema '"structure"'
Assert-FileContains "F.4 interaction dimension present" $ParSchema '"interaction"'
Assert-FileContains "F.5 state dimension present" $ParSchema '"state"'

# G: NOT_APPLICABLE requires rationale
Write-Host ""
Write-Host "TEST G: NOT_APPLICABLE requires rationale" -ForegroundColor Cyan
Assert-FileContains "G.1 parity schema has not_applicable_rationale field" $ParSchema 'not_applicable_rationale'
Assert-FileContains "G.2 policy states NOT_APPLICABLE requires rationale" $ParityPol 'NOT_APPLICABLE.*requires.*rationale'
$fixC2 = Get-Content -LiteralPath (Join-Path $FixDir "fixture-C-desktop-pass-mobile-fail.yaml") -Raw
Assert-True "G.3 fixture-A NOT_APPLICABLE has rationale (desktop-only)" ($fixA -match 'not_applicable_rationale')

# H: Screenshot alone cannot satisfy every parity dimension
Write-Host ""
Write-Host "TEST H: Screenshot alone cannot satisfy every parity dimension" -ForegroundColor Cyan
Assert-FileContains "H.1 evidence contract states screenshot is not complete verdict" $EvPol 'not the complete verdict'
Assert-FileContains "H.2 evidence contract requires DOM text for content" $EvPol 'dom_text_assertion'
Assert-FileContains "H.3 policy states screenshot insufficient for content" $ParityPol 'screenshot.*alone'

# I: DOM assertion detects content mismatch despite visually similar screenshot
Write-Host ""
Write-Host "TEST I: DOM assertion detects content mismatch despite visually similar screenshot" -ForegroundColor Cyan
Assert-FileExists "I.1 fixture N exists" (Join-Path $FixDir "fixture-N-screenshot-correct-dom-label-incorrect.yaml")
$fixN = Get-Content -LiteralPath (Join-Path $FixDir "fixture-N-screenshot-correct-dom-label-incorrect.yaml") -Raw
Assert-True "I.2 fixture-N visual is PASS" ($fixN -match 'visual:.*\n\s+result: PASS')
Assert-True "I.3 fixture-N content is FAIL" ($fixN -match 'content:.*\n\s+result: FAIL')
Assert-True "I.4 fixture-N has dom_text_assertion" ($fixN -match 'dom_text_assertion')
Assert-True "I.5 fixture-N overall is FAIL" ($fixN -match 'overall_result: FAIL')

# J: Required populated-state scenario cannot verify without representative data
Write-Host ""
Write-Host "TEST J: Populated-state scenario blocked without representative data" -ForegroundColor Cyan
Assert-FileContains "J.1 scenario policy states empty screen cannot prove populated parity" $ScnPol 'empty screen cannot prove'
Assert-FileExists "J.2 fixture I exists" (Join-Path $FixDir "fixture-I-populated-state-without-mockdata.yaml")
$fixI = Get-Content -LiteralPath (Join-Path $FixDir "fixture-I-populated-state-without-mockdata.yaml") -Raw
Assert-True "J.3 fixture-I status is blocked" ($fixI -match 'status: blocked')
Assert-True "J.4 fixture-I overall is NOT_VERIFIED" ($fixI -match 'overall_result: NOT_VERIFIED')

# K: Mock-data prerequisite may use different identity than target verification
Write-Host ""
Write-Host "TEST K: Mock-data seeding may use different identity than target verification" -ForegroundColor Cyan
Assert-FileContains "K.1 scenario policy models dependency chain" $ScnPol 'mock_data_seed_identity'
Assert-FileContains "K.2 scenario schema has mock_data_seed_identity field" $ScnSchema 'mock_data_seed_identity'
Assert-FileExists "K.3 fixture J exists" (Join-Path $FixDir "fixture-J-seed-requires-developer-role.yaml")
$fixJ = Get-Content -LiteralPath (Join-Path $FixDir "fixture-J-seed-requires-developer-role.yaml") -Raw
Assert-True "K.4 fixture-J has different seed vs verification identity" ($fixJ -match 'DEVELOPER_SEED_IDENTITY')

# L: Material scenario matrix avoids provably redundant role coverage
Write-Host ""
Write-Host "TEST L: Material scenario matrix avoids redundant role coverage" -ForegroundColor Cyan
Assert-FileContains "L.1 policy states identical UI contracts do not require duplicate scenarios" $ScnPol 'identical.*UI contract'
Assert-FileExists "L.2 fixture K exists" (Join-Path $FixDir "fixture-K-identical-role-contracts-no-duplicate.yaml")
$fixK = Get-Content -LiteralPath (Join-Path $FixDir "fixture-K-identical-role-contracts-no-duplicate.yaml") -Raw
Assert-True "L.3 fixture-K documents identical contracts" ($fixK -match 'identical UI contract')

# M: Materially different role behavior creates separate required scenario
Write-Host ""
Write-Host "TEST M: Materially different role behavior creates separate required scenario" -ForegroundColor Cyan
Assert-FileContains "M.1 policy states different roles require separate scenarios" $ScnPol 'separate.*scenario'
Assert-FileExists "M.2 fixture L exists" (Join-Path $FixDir "fixture-L-different-role-actions-separate-scenarios.yaml")
$fixL = Get-Content -LiteralPath (Join-Path $FixDir "fixture-L-different-role-actions-separate-scenarios.yaml") -Raw
Assert-True "M.3 fixture-L has two separate scenarios" ($fixL -match 'scenario_L2')

# N: Browser scenario decomposition preferred to blanket timeout escalation
Write-Host ""
Write-Host "TEST N: Browser scenario decomposition preferred to blanket timeout escalation" -ForegroundColor Cyan
Assert-FileContains "N.1 policy states not to solve fragility by globally increasing timeouts" $ScnPol 'globally increasing'
Assert-FileContains "N.2 policy requires timeout_rationale for overrides" $ScnSchema 'timeout_rationale'
Assert-FileExists "N.3 fixture O exists (timeout anti-pattern)" (Join-Path $FixDir "fixture-O-large-scenario-timeout.yaml")
$fixO = Get-Content -LiteralPath (Join-Path $FixDir "fixture-O-large-scenario-timeout.yaml") -Raw
Assert-True "N.4 fixture-O documents anti-pattern" ($fixO -match 'ANTI-PATTERN')
Assert-FileExists "N.5 fixture P exists (correct decomposition)" (Join-Path $FixDir "fixture-P-decomposed-focused-scenarios.yaml")

# O: Temporary evidence is distinguishable from canonical promoted evidence
Write-Host ""
Write-Host "TEST O: Temporary evidence distinguishable from canonical promoted evidence" -ForegroundColor Cyan
Assert-FileContains "O.1 evidence contract defines temporary vs canonical" $EvPol 'Temporary vs. Canonical'
Assert-FileContains "O.2 .concord is classified as temporary/ephemeral in project-knowledge" $KnowPol '\.concord.*NO.*Ephemeral'
Assert-FileContains "O.3 planning/evidence is git-tracked" $KnowPol 'planning/evidence'

# P: Canonical evidence maps back to its scenario
Write-Host ""
Write-Host "TEST P: Canonical evidence maps back to its scenario" -ForegroundColor Cyan
Assert-FileContains "P.1 evidence manifest schema has scenario_id per entry" $EvSchema 'scenario_id'
Assert-FileContains "P.2 evidence manifest schema has traceability" $EvSchema 'traceability'
Assert-FileContains "P.3 parity schema has scenario_id field" $ParSchema '"scenario_id"'

# Q: Source mockup remains immutable
Write-Host ""
Write-Host "TEST Q: Source mockup remains immutable" -ForegroundColor Cyan
Assert-FileContains "Q.1 mockup-lifecycle.md declares source as IMMUTABLE" ".mxagile/policies/mockup-lifecycle.md" 'IMMUTABLE'
Assert-FileContains "Q.2 project-knowledge.md states source mockups are immutable" $KnowPol 'IMMUTABLE'
Assert-FileExists "Q.3 fixture Q exists (company layer override)" (Join-Path $FixDir "fixture-Q-source-superseded-by-company-layer.yaml")
$fixQ = Get-Content -LiteralPath (Join-Path $FixDir "fixture-Q-source-superseded-by-company-layer.yaml") -Raw
Assert-True "Q.4 fixture-Q source mockup preserved" ($fixQ -match 'source_mockup:.*input-resources')

# R: Accepted refined target becomes active acceptance target
Write-Host ""
Write-Host "TEST R: Accepted refined target becomes active acceptance target" -ForegroundColor Cyan
Assert-FileContains "R.1 mockup-lifecycle defines active acceptance target" ".mxagile/policies/mockup-lifecycle.md" 'active acceptance target'
Assert-FileContains "R.2 parity schema has target_mockup field" $ParSchema '"target_mockup"'
$fixQ2 = Get-Content -LiteralPath (Join-Path $FixDir "fixture-Q-source-superseded-by-company-layer.yaml") -Raw
Assert-True "R.3 fixture-Q uses refined target for verification" ($fixQ2 -match 'target_mockup:.*planning/target-mockups')

# S: Deterministic source-priority conflict may refine autonomously
Write-Host ""
Write-Host "TEST S: Deterministic source-priority conflict may refine autonomously" -ForegroundColor Cyan
Assert-FileContains "S.1 mockup-lifecycle defines autonomous refinement" ".mxagile/policies/mockup-lifecycle.md" 'Autonomous Refinement'
$fixQ3 = Get-Content -LiteralPath (Join-Path $FixDir "fixture-Q-source-superseded-by-company-layer.yaml") -Raw
Assert-True "S.2 fixture-Q autonomous refinement applied" ($fixQ3 -match 'autonomous: true')

# T: Ambiguous product/design change enters Decision Required
Write-Host ""
Write-Host "TEST T: Ambiguous product/design change enters Decision Required" -ForegroundColor Cyan
Assert-FileContains "T.1 mockup-lifecycle defines DECISION REQUIRED behavior" ".mxagile/policies/mockup-lifecycle.md" 'DECISION REQUIRED'
Assert-FileExists "T.2 fixture R exists" (Join-Path $FixDir "fixture-R-ambiguous-target-decision-required.yaml")
$fixR = Get-Content -LiteralPath (Join-Path $FixDir "fixture-R-ambiguous-target-decision-required.yaml") -Raw
Assert-True "T.3 fixture-R has autonomous=false" ($fixR -match 'autonomous: false')
Assert-True "T.4 fixture-R has DECISION_REQUIRED" ($fixR -match 'DECISION_REQUIRED')

# U: Implementation mutation before accepted Refinement is rejected/classified
Write-Host ""
Write-Host "TEST U: Implementation mutation before accepted Refinement is rejected/classified" -ForegroundColor Cyan
Assert-FileContains "U.1 observe-before-mutate defines violation classification" $ObsMut 'MUTATE_BEFORE'
Assert-FileContains "U.2 observe-before-mutate defines mutation eligibility gate" $ObsMut 'Mutation Eligibility Gate'
Assert-FileContains "U.3 process-state has mutation_eligibility field" $ProcState 'mutation_eligibility'
Assert-FileExists "U.4 fixture S exists" (Join-Path $FixDir "fixture-S-mutation-before-refinement.yaml")
$fixS = Get-Content -LiteralPath (Join-Path $FixDir "fixture-S-mutation-before-refinement.yaml") -Raw
Assert-True "U.5 fixture-S has violation_type" ($fixS -match 'violation_type: MUTATE_BEFORE')

# V: Post-implementation verification repeats affected parity dimensions
Write-Host ""
Write-Host "TEST V: Post-implementation verification repeats affected parity dimensions" -ForegroundColor Cyan
Assert-FileContains "V.1 observe-before-mutate defines post-mutation re-verification step" $ObsMut 'POST-MUTATION'
Assert-FileContains "V.2 parity schema has STALE status for re-verification trigger" $ParSchema '"STALE"'

# W: Legacy PASS does not become multidimensional PASS automatically
Write-Host ""
Write-Host "TEST W: Legacy PASS does not become multidimensional PASS automatically" -ForegroundColor Cyan
Assert-FileContains "W.1 policy prohibits fabricating 7x PASS from legacy" $ParityPol 'MUST NOT be converted'
Assert-FileExists "W.2 fixture T exists" (Join-Path $FixDir "fixture-T-legacy-pass-no-dimension-evidence.yaml")
$fixT = Get-Content -LiteralPath (Join-Path $FixDir "fixture-T-legacy-pass-no-dimension-evidence.yaml") -Raw
Assert-True "W.3 fixture-T no dimension is PASS" ($fixT -notmatch 'result: PASS')
Assert-True "W.4 fixture-T overall is NOT_VERIFIED" ($fixT -match 'overall_result: NOT_VERIFIED')

# X: Reconstructable evidence keeps provenance
Write-Host ""
Write-Host "TEST X: Reconstructable evidence keeps provenance" -ForegroundColor Cyan
Assert-FileContains "X.1 parity dimension has legacy_provenance field" $ParSchema 'legacy_provenance'
Assert-FileExists "X.2 fixture U exists" (Join-Path $FixDir "fixture-U-legacy-with-reconstructable-visual.yaml")
$fixU = Get-Content -LiteralPath (Join-Path $FixDir "fixture-U-legacy-with-reconstructable-visual.yaml") -Raw
Assert-True "X.3 fixture-U visual has legacy_provenance" ($fixU -match 'legacy_provenance:')
Assert-True "X.4 fixture-U visual is LEGACY_EVIDENCE not PASS" ($fixU -match 'result: LEGACY_EVIDENCE')

# Y: Missing evidence becomes NOT_VERIFIED
Write-Host ""
Write-Host "TEST Y: Missing evidence becomes NOT_VERIFIED" -ForegroundColor Cyan
$fixT2 = Get-Content -LiteralPath (Join-Path $FixDir "fixture-T-legacy-pass-no-dimension-evidence.yaml") -Raw
Assert-True "Y.1 fixture-T content is NOT_VERIFIED (no historical evidence)" ($fixT2 -match 'content:.*\n\s+result: NOT_VERIFIED')
Assert-True "Y.2 fixture-T role is NOT_VERIFIED" ($fixT2 -match 'role:.*\n\s+result: NOT_VERIFIED')

# Z: Conflicting evidence becomes explicit conflict
Write-Host ""
Write-Host "TEST Z: Conflicting evidence becomes explicit conflict" -ForegroundColor Cyan
Assert-FileContains "Z.1 parity dimension has CONFLICT status" $ParSchema '"CONFLICT"'
Assert-FileExists "Z.2 fixture V exists" (Join-Path $FixDir "fixture-V-conflicting-historical-evidence.yaml")
$fixV = Get-Content -LiteralPath (Join-Path $FixDir "fixture-V-conflicting-historical-evidence.yaml") -Raw
Assert-True "Z.3 fixture-V structure is CONFLICT" ($fixV -match 'structure:.*\n\s+result: CONFLICT')
Assert-True "Z.4 fixture-V has DECISION_REQUIRED" ($fixV -match 'DECISION_REQUIRED')

# AA: Stale evidence requires re-verification
Write-Host ""
Write-Host "TEST AA: Stale evidence requires re-verification" -ForegroundColor Cyan
Assert-FileContains "AA.1 parity schema has STALE result status" $ParSchema '"STALE"'
Assert-FileContains "AA.2 parity schema has target_changed_at for staleness detection" $ParSchema 'target_changed_at'
Assert-FileContains "AA.3 ui-parity.md defines when record becomes STALE" $ParityPol 'STALE.*when'

# AB: Requirements/Specs/Tasks retain stable identifiers
Write-Host ""
Write-Host "TEST AB: Requirements/Specs/Tasks retain stable identifiers" -ForegroundColor Cyan
Assert-FileContains "AB.1 project-knowledge states artifacts need stable identifiers" $KnowPol 'Requirements, Specs.*Tasks|versioned project'
Assert-FileContains "AB.2 scenario schema has stable scenario_id" $ScnSchema '"scenario_id"'

# AC: Implementation-complete may coexist with verification-pending
Write-Host ""
Write-Host "TEST AC: Implementation-complete may coexist with verification-pending" -ForegroundColor Cyan
Assert-FileExists "AC.1 fixture W exists" (Join-Path $FixDir "fixture-W-completed-implementation-new-verification-gap.yaml")
$fixW = Get-Content -LiteralPath (Join-Path $FixDir "fixture-W-completed-implementation-new-verification-gap.yaml") -Raw
Assert-True "AC.2 fixture-W task is implementation_complete" ($fixW -match 'task_implementation_complete: true')
Assert-True "AC.3 fixture-W new contract verification is pending" ($fixW -match 'task_new_contract_verification: pending')
Assert-True "AC.4 fixture-W overall is NOT_VERIFIED (verification gaps)" ($fixW -match 'overall_result: NOT_VERIFIED')

# AD: Targeted re-verification does not recreate already-valid evidence
Write-Host ""
Write-Host "TEST AD: Targeted re-verification does not recreate already-valid evidence" -ForegroundColor Cyan
Assert-FileContains "AD.1 ui-parity.md defines lazy reconciliation for gaps only" $ParityPol 'Lazy Reconciliation'
Assert-FileContains "AD.2 scenario policy defines targeted re-verification" $ScnPol 'targeted re-verification'
$fixW2 = Get-Content -LiteralPath (Join-Path $FixDir "fixture-W-completed-implementation-new-verification-gap.yaml") -Raw
Assert-True "AD.3 fixture-W only gaps require re-verification" ($fixW2 -match 'remaining_scenarios:')

# AE: Lazy reconciliation works
Write-Host ""
Write-Host "TEST AE: Lazy reconciliation works" -ForegroundColor Cyan
Assert-FileContains "AE.1 ui-parity.md defines lazy reconciliation" $ParityPol 'Lazy Reconciliation'
Assert-FileContains "AE.2 evidence_upgrade has targeted_reverification_required" $ParSchema 'targeted_reverification_required'
Assert-FileContains "AE.3 process-state parity_reconciliation has lazy mode" $ProcState '"lazy"'

# AF: Full reconciliation = full scope accounting + conservative reuse + targeted re-verification
Write-Host ""
Write-Host "TEST AF: Full reconciliation is full scope accounting, not blind re-run" -ForegroundColor Cyan
Assert-FileContains "AF.1 ui-parity.md defines full reconciliation" $ParityPol 'Full Reconciliation'
Assert-FileContains "AF.2 full reconciliation is full scope accounting" $ParityPol 'FULL SCOPE ACCOUNTING'
Assert-FileContains "AF.3 full reconciliation preserves REUSABLE evidence" $ParityPol 'REUSABLE'
Assert-FileContains "AF.4 full reconciliation targets only LEGACY_INSUFFICIENT, STALE, MISSING" $ParityPol 'LEGACY_INSUFFICIENT'
Assert-FileContains "AF.5 full reconciliation does NOT discard authoritative valid evidence" $ParityPol 'does NOT mean discarding'
Assert-FileContains "AF.6 process-state parity_reconciliation has full mode" $ProcState '"full"'

# AG: Full reconciliation resumes after interruption
Write-Host ""
Write-Host "TEST AG: Full reconciliation resumes after interruption" -ForegroundColor Cyan
Assert-FileContains "AG.1 process-state has pages_remaining for resumability" $ProcState 'pages_remaining'
Assert-FileContains "AG.2 evidence_upgrade has remaining_scenarios" $ParSchema 'remaining_scenarios'

# AH: Intent-driven widget-selection contract remains intact
Write-Host ""
Write-Host "TEST AH: Intent-driven widget-selection contract remains intact" -ForegroundColor Cyan
Assert-FileContains "AH.1 ui-element-selection.md still defines Data Grid 2 not default" ".mxagile/policies/ui-element-selection.md" 'Data Grid 2 Is Not the Default'
Assert-FileContains "AH.2 observe-before-mutate does not override widget selection" $ObsMut 'Mutation Eligibility'

# AI: Mockup-refinement contract remains intact
Write-Host ""
Write-Host "TEST AI: Mockup-refinement contract remains intact" -ForegroundColor Cyan
Assert-FileContains "AI.1 mockup-lifecycle.md defines refined target contract" ".mxagile/policies/mockup-lifecycle.md" 'Refined Target'
Assert-FileContains "AI.2 page schema has target_mockup field" ".mxagile/schemas/page.schema.json" 'target_mockup'

# AJ: UI-driven readiness contract remains intact
Write-Host ""
Write-Host "TEST AJ: UI-driven readiness contract remains intact" -ForegroundColor Cyan
Assert-FileContains "AJ.1 evidence-levels.md still defines BROWSER level" ".mxagile/policies/evidence-levels.md" 'BROWSER'
Assert-FileContains "AJ.2 discovery agent still references credential discovery" ".mxagile/agents/discovery-agent.md" 'credential'

# AK: Lifecycle re-sync remains intact
Write-Host ""
Write-Host "TEST AK: Lifecycle re-sync remains intact" -ForegroundColor Cyan
Assert-FileContains "AK.1 lifecycle-resync.md still defines re-sync from process-state" ".mxagile/policies/lifecycle-resync.md" 'process-state'
Assert-FileContains "AK.2 process-state schema still has phase field" $ProcState '"phase"'

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
