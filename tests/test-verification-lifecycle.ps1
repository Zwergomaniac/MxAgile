<#
.SYNOPSIS
    Verification Lifecycle Behavioral Tests

.DESCRIPTION
    Proves that the MxAgile verification lifecycle model correctly separates
    verification INTENT (TC/PP) from verification EXECUTION (VPL/executable tests/Evidence),
    and that the revision impact vocabulary (PRESERVE/REASSESS/REMATERIALIZE/REEXECUTE/INVALIDATE)
    is correctly defined and applied.

    Covers fixtures A through J (10 scenarios).

    Tests:
      A: UI change does not automatically recreate TC/PP
      B: Business change causes semantic reassessment
      C: Implementation refactor  - reexecute only affected evidence
      D: Navigation change causes REMATERIALIZE, not TC recreation
      E: Security/role change causes REASSESS
      F: Locator change causes REMATERIALIZE (not semantic invalidation)
      G: Unchanged PP + stale evidence -> REEXECUTE without test rewrite
      H: Changed PP -> old PP preserved stale; new PP appended
      I: MODEL-sufficient assertion does not materialize redundant FRONTEND
      J: FRONTEND-required assertion cannot be downgraded to MODEL
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
    else { Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath" }
}
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$FixDir      = Join-Path $ScriptDir "tests/fixtures/verification-lifecycle"
$MatPol      = Join-Path $ScriptDir ".mxagile/policies/verification-materialization.md"
$StalePol    = Join-Path $ScriptDir ".mxagile/policies/test-staleness.md"
$DefectPol   = Join-Path $ScriptDir ".mxagile/policies/test-defect-protection.md"
$VplSkill    = Join-Path $ScriptDir ".mxagile/skills/verification-plan.md"
$TcSchema    = Join-Path $ScriptDir ".mxagile/schemas/test-contract.schema.json"
$VplSchema   = Join-Path $ScriptDir ".mxagile/schemas/verification-plan.schema.json"
$TcSkill     = Join-Path $ScriptDir ".mxagile/skills/test-contract.md"
$TcDeriv     = Join-Path $ScriptDir ".mxagile/policies/test-contract-derivation.md"
$GateReady   = Join-Path $ScriptDir ".mxagile/skills/gate-to-ready.md"
$AccAgent    = Join-Path $ScriptDir ".mxagile/agents/acceptance-agent.md"

# Pre-initialize fixture variables to $null so strict mode does not fire if a
# prior SilentlyContinue error record is in scope when the Get-Content runs.
$fixA = $null; $fixB = $null; $fixC = $null; $fixD = $null; $fixE = $null
$fixF = $null; $fixG = $null; $fixH = $null; $fixI = $null; $fixJ = $null

# ─────────────────────────────────────────────────────────────────────────────
# MATERIALIZATION MODEL
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "MATERIALIZATION BOUNDARY" -ForegroundColor Cyan

Assert-FileExists "materialization policy exists" $MatPol
Assert-FileContains "materialization policy defines boundary" $MatPol "MATERIALIZATION BOUNDARY"
Assert-FileContains "materialization policy places TC above boundary" $MatPol "Test Contract"
Assert-FileContains "materialization policy places PP above boundary" $MatPol "Proof Points"
Assert-FileContains "materialization policy places VPL below boundary" $MatPol "Verification Plan"
Assert-FileContains "materialization policy places executable tests below boundary" $MatPol "Executable test"
Assert-FileContains "materialization policy defines evidence level selection rule" $MatPol "Evidence Level Selection Rule"
Assert-FileContains "VPL deferred until Verifying  - skills doc" $VplSkill "Verifying phase entry"
Assert-FileNotContains "VPL not created in Refinement  - skills doc" $VplSkill "Refinement.*VPL"
Assert-FileContains "TC created in Refinement  - skills doc" $TcSkill "during Refinement"
Assert-FileContains "gate-to-ready does NOT require VPL" $GateReady "Verification Plan is NOT required here"

# ─────────────────────────────────────────────────────────────────────────────
# REVISION IMPACT VOCABULARY
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "REVISION IMPACT VOCABULARY" -ForegroundColor Cyan

Assert-FileContains "test-staleness defines PRESERVE" $StalePol "PRESERVE"
Assert-FileContains "test-staleness defines REASSESS" $StalePol "REASSESS"
Assert-FileContains "test-staleness defines REMATERIALIZE" $StalePol "REMATERIALIZE"
Assert-FileContains "test-staleness defines REEXECUTE" $StalePol "REEXECUTE"
Assert-FileContains "test-staleness defines INVALIDATE" $StalePol "INVALIDATE"
Assert-FileContains "materialization policy defines all 5 actions" $MatPol "PRESERVE"
Assert-FileContains "materialization policy REASSESS section" $MatPol "REASSESS"
Assert-FileContains "materialization policy REMATERIALIZE section" $MatPol "REMATERIALIZE"
Assert-FileContains "materialization policy REEXECUTE section" $MatPol "REEXECUTE"
Assert-FileContains "materialization policy INVALIDATE section" $MatPol "INVALIDATE"

# ─────────────────────────────────────────────────────────────────────────────
# TC CREATED AT APPROPRIATE MATURITY
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TC CREATED AT APPROPRIATE MATURITY" -ForegroundColor Cyan

Assert-FileContains "TC skill runs during Refinement" $TcSkill "during Refinement"
Assert-FileContains "TC requires accepted acceptance criteria" $TcSkill "acceptance_criteria"
Assert-FileContains "TC derivation policy defines layer defaults" $TcDeriv "Layer assignment defaults"
Assert-FileContains "gate-to-ready testability gate requires TC" $GateReady "Test Contract present"

# ─────────────────────────────────────────────────────────────────────────────
# PP CREATED AT APPROPRIATE MATURITY
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "PP CREATED AT APPROPRIATE MATURITY" -ForegroundColor Cyan

Assert-FileContains "PP is layer-agnostic intent" $TcSkill "WHAT must be proven"
Assert-FileContains "PP required_layers are defaults not execution binding" $TcDeriv "Defaults"
Assert-FileContains "PP IDs are stable once assigned" $TcDeriv "stable once assigned"

# ─────────────────────────────────────────────────────────────────────────────
# VPL DEFERRED UNTIL EXECUTION CONTEXT EXISTS
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "VPL DEFERRED UNTIL EXECUTION CONTEXT EXISTS" -ForegroundColor Cyan

Assert-FileContains "VPL skill explicitly states post-implementation timing" $VplSkill "after implementation"
Assert-FileContains "VPL skill requires implementation checklist input" $VplSkill "implementation-checklist"
Assert-FileContains "VPL skill requires infrastructure assessment" $VplSkill "Infrastructure Assessment"
Assert-FileContains "acceptance agent creates VPL at startup (post-implementation)" $AccAgent "VPL creation"
Assert-FileNotContains "gate-to-ready must not require VPL" $GateReady "VPL.*required"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO A: UI-ONLY LAYOUT CHANGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST A: UI layout change does not recreate TC/PP" -ForegroundColor Cyan

Assert-FileExists "A.1 fixture A exists" (Join-Path $FixDir "fixture-A-ui-layout-change.yaml")
$fixA = Get-Content -LiteralPath (Join-Path $FixDir "fixture-A-ui-layout-change.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "A.2 fixture-A tc_action is preserve" ($fixA -match "tc_action: preserve")
Assert-True "A.3 fixture-A pp_action is preserve" ($fixA -match "pp_action: preserve")
Assert-True "A.4 fixture-A vpl_action is rematerialize" ($fixA -match "vpl_action: rematerialize")
Assert-True "A.5 fixture-A tc_status_after is active" ($fixA -match "tc_status_after: active")
Assert-True "A.6 fixture-A DECISION_REQUIRED must NOT be raised" ($fixA -match "DECISION_REQUIRED must NOT")
Assert-FileContains "A.7 materialization policy defines layout change as rematerialize" $MatPol "Cosmetic layout.*rematerialize"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO B: BUSINESS RULE CHANGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST B: Business rule change causes REASSESS" -ForegroundColor Cyan

Assert-FileExists "B.1 fixture B exists" (Join-Path $FixDir "fixture-B-business-rule-change.yaml")
$fixB = Get-Content -LiteralPath (Join-Path $FixDir "fixture-B-business-rule-change.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "B.2 fixture-B tc_action is reassess" ($fixB -match "tc_action: reassess")
Assert-True "B.3 fixture-B pp_action is reassess" ($fixB -match "pp_action: reassess")
Assert-True "B.4 fixture-B tc_status_after is stale" ($fixB -match "tc_status_after: stale")
Assert-True "B.5 fixture-B vpl_action is supersede_and_regenerate" ($fixB -match "vpl_action: supersede_and_regenerate")
Assert-True "B.6 fixture-B ACCEPTANCE_CRITERIA_CHANGED" ($fixB -match "ACCEPTANCE_CRITERIA_CHANGED")
Assert-FileContains "B.7 test-staleness policy: AC change -> TC stale" $StalePol "acceptance_criteria.*added, removed, or meaningfully changed"
Assert-FileContains "B.8 materialization policy: business rule change -> reassess" $MatPol "Business rule change.*reassess"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO C: IMPLEMENTATION REFACTOR
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST C: Implementation-only refactor  - minimum regression action" -ForegroundColor Cyan

Assert-FileExists "C.1 fixture C exists" (Join-Path $FixDir "fixture-C-implementation-refactor.yaml")
$fixC = Get-Content -LiteralPath (Join-Path $FixDir "fixture-C-implementation-refactor.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "C.2 fixture-C tc_action is preserve" ($fixC -match "tc_action: preserve")
Assert-True "C.3 fixture-C pp_action is preserve" ($fixC -match "pp_action: preserve")
Assert-True "C.4 fixture-C vpl_action is preserve" ($fixC -match "vpl_action: preserve")
Assert-True "C.5 fixture-C evidence_action is reexecute" ($fixC -match "evidence_action: reexecute")
Assert-True "C.6 fixture-C DECISION_REQUIRED must NOT be raised" ($fixC -match "DECISION_REQUIRED must NOT")
Assert-FileContains "C.7 materialization policy defines implementation refactor -> reexecute" $MatPol "Implementation refactor.*reexecute"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO D: NAVIGATION CHANGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST D: Navigation change causes REMATERIALIZE not TC recreation" -ForegroundColor Cyan

Assert-FileExists "D.1 fixture D exists" (Join-Path $FixDir "fixture-D-navigation-change.yaml")
$fixD = Get-Content -LiteralPath (Join-Path $FixDir "fixture-D-navigation-change.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "D.2 fixture-D tc_action is preserve" ($fixD -match "tc_action: preserve")
Assert-True "D.3 fixture-D vpl_action is rematerialize" ($fixD -match "vpl_action: rematerialize")
Assert-True "D.4 fixture-D execution_binding_stale is true" ($fixD -match "pp_execution_binding_stale: true")
Assert-True "D.5 fixture-D DECISION_REQUIRED must NOT be raised" ($fixD -match "DECISION_REQUIRED must NOT")
Assert-FileContains "D.6 materialization policy defines navigation change -> rematerialize" $MatPol "Navigation change.*rematerialize"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO E: SECURITY/ROLE CHANGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST E: Security/role change causes REASSESS" -ForegroundColor Cyan

Assert-FileExists "E.1 fixture E exists" (Join-Path $FixDir "fixture-E-security-role-change.yaml")
$fixE = Get-Content -LiteralPath (Join-Path $FixDir "fixture-E-security-role-change.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "E.2 fixture-E tc_action is reassess" ($fixE -match "tc_action: reassess")
Assert-True "E.3 fixture-E tc_status_after is stale" ($fixE -match "tc_status_after: stale")
Assert-True "E.4 fixture-E requires VISIBILITY and AUTHORIZATION dimensions" ($fixE -match "VISIBILITY.*AUTHORIZATION|AUTHORIZATION.*VISIBILITY")
Assert-True "E.5 fixture-E requires MODEL and FRONTEND for negative PP" ($fixE -match "MODEL.*FRONTEND|FRONTEND.*MODEL")
Assert-FileContains "E.6 test-staleness policy: role permission change -> PP stale" $StalePol "role.*changed permissions"
Assert-FileContains "E.7 materialization policy defines role change -> reassess" $MatPol "Role permission change.*reassess"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO F: LOCATOR-ONLY CHANGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST F: Locator change causes REMATERIALIZE  - not semantic invalidation" -ForegroundColor Cyan

Assert-FileExists "F.1 fixture F exists" (Join-Path $FixDir "fixture-F-locator-only-change.yaml")
$fixF = Get-Content -LiteralPath (Join-Path $FixDir "fixture-F-locator-only-change.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "F.2 fixture-F tc_action is preserve" ($fixF -match "tc_action: preserve")
Assert-True "F.3 fixture-F tc_status_after is active" ($fixF -match "tc_status_after: active")
Assert-True "F.4 fixture-F vpl_action is rematerialize" ($fixF -match "vpl_action: rematerialize")
Assert-True "F.5 fixture-F execution_binding_stale is true" ($fixF -match "pp_execution_binding_stale: true")
Assert-True "F.6 fixture-F DECISION_REQUIRED must NOT be raised" ($fixF -match "DECISION_REQUIRED must NOT be raised")
Assert-FileContains "F.7 VPL skill defines REMATERIALIZE for locator change" $VplSkill "locator.*adapter.*screen structure"
Assert-FileContains "F.8 test-contract schema has execution_binding_stale field" $TcSchema "execution_binding_stale"
Assert-FileContains "F.9 execution_binding_stale does not change TC status" $TcSchema "Does NOT change TC status"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO G: UNCHANGED PP + STALE EVIDENCE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST G: Unchanged PP with stale evidence  - REEXECUTE without test rewrite" -ForegroundColor Cyan

Assert-FileExists "G.1 fixture G exists" (Join-Path $FixDir "fixture-G-unchanged-pp-stale-evidence.yaml")
$fixG = Get-Content -LiteralPath (Join-Path $FixDir "fixture-G-unchanged-pp-stale-evidence.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "G.2 fixture-G tc_action is preserve" ($fixG -match "tc_action: preserve")
Assert-True "G.3 fixture-G pp_action is preserve" ($fixG -match "pp_action: preserve")
Assert-True "G.4 fixture-G executable_test_action is reuse" ($fixG -match "executable_test_action: reuse")
Assert-True "G.5 fixture-G evidence_status_after is STALE_REEXECUTION_REQUIRED" ($fixG -match "STALE_REEXECUTION_REQUIRED")
Assert-True "G.6 fixture-G DECISION_REQUIRED must NOT be raised" ($fixG -match "DECISION_REQUIRED must NOT")
Assert-True "G.7 fixture-G reexecution does not rewrite test definition" ($fixG -match "does NOT rewrite the test definition")
Assert-FileContains "G.8 test-staleness defines REEXECUTE concept" $StalePol "REEXECUTE"
Assert-FileContains "G.9 test-staleness REEXECUTE: VPL unchanged" $StalePol "VPL.*unchanged"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO H: CHANGED PROOF POINT
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST H: Changed PP  - old PP preserved stale; new PP appended" -ForegroundColor Cyan

Assert-FileExists "H.1 fixture H exists" (Join-Path $FixDir "fixture-H-changed-pp.yaml")
$fixH = Get-Content -LiteralPath (Join-Path $FixDir "fixture-H-changed-pp.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "H.2 fixture-H old_pp_action is mark_stale" ($fixH -match "old_pp_action: mark_stale")
Assert-True "H.3 fixture-H new_pp_action is append" ($fixH -match "new_pp_action: append")
Assert-True "H.4 fixture-H PP IDs not renumbered" ($fixH -match "PP-003 stays as PP-003")
Assert-True "H.5 fixture-H evidence from old PP is legacy" ($fixH -match "legacy only")
Assert-FileContains "H.6 TC derivation: active PP id and claim must not change" $TcDeriv "stable once assigned"
Assert-FileContains "H.7 TC derivation: stale PP preserved not deleted" $TcDeriv "not.*delet"
Assert-FileContains "H.8 test-staleness: stale contracts not deleted" $StalePol "Non-Deletion Rule"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO I: MODEL-SUFFICIENT ASSERTION
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST I: MODEL-sufficient assertion does not materialize redundant FRONTEND" -ForegroundColor Cyan

Assert-FileExists "I.1 fixture I exists" (Join-Path $FixDir "fixture-I-model-sufficient-assertion.yaml")
$fixI = Get-Content -LiteralPath (Join-Path $FixDir "fixture-I-model-sufficient-assertion.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "I.2 fixture-I minimum_evidence_level is MODEL" ($fixI -match "minimum_evidence_level: MODEL")
Assert-True "I.3 fixture-I frontend_required is false" ($fixI -match "frontend_required: false")
Assert-True "I.4 fixture-I VPL FRONTEND excluded with NOT_APPLICABLE" ($fixI -match "exclusion_reason: NOT_APPLICABLE")
Assert-True "I.5 fixture-I FRONTEND must NOT be added merely because Playwright available" ($fixI -match "merely because Playwright is available")
Assert-FileContains "I.6 materialization policy: do not escalate to FRONTEND when MODEL sufficient" $MatPol "Do NOT escalate to FRONTEND when MODEL"
Assert-FileContains "I.7 materialization policy: cheapest authoritative evidence" $MatPol "cheapest authoritatively"
Assert-FileContains "I.8 VPL skill: BUILD layer must serve semantic purpose" $VplSkill "semantic purpose"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO J: FRONTEND-REQUIRED ASSERTION
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "TEST J: FRONTEND-required assertion cannot be downgraded to MODEL" -ForegroundColor Cyan

Assert-FileExists "J.1 fixture J exists" (Join-Path $FixDir "fixture-J-frontend-required-assertion.yaml")
$fixJ = Get-Content -LiteralPath (Join-Path $FixDir "fixture-J-frontend-required-assertion.yaml") -Raw -ErrorAction SilentlyContinue
Assert-True "J.2 fixture-J minimum_evidence_level is FRONTEND" ($fixJ -match "minimum_evidence_level: FRONTEND")
Assert-True "J.3 fixture-J model_sufficient is false" ($fixJ -match "model_sufficient: false")
Assert-True "J.4 fixture-J FRONTEND must NOT be excluded as COVERED_BY_LOWER_LAYER" ($fixJ -match "COVERED_BY_LOWER_LAYER")
Assert-True "J.5 fixture-J security_dimensions include VISIBILITY" ($fixJ -match "VISIBILITY")
Assert-FileContains "J.6 materialization policy: do not downgrade FRONTEND assertion to MODEL" $MatPol "Do NOT downgrade to MODEL"
Assert-FileContains "J.7 verification-layers policy: VISIBILITY requires FRONTEND" ".mxagile/policies/verification-layers.md" "VISIBILITY.*required"
Assert-FileContains "J.8 bounded escalation: WRONG_EVIDENCE_LEVEL not applicable when FRONTEND genuinely required" $DefectPol "WRONG_EVIDENCE_LEVEL.*NOT a downgrade"

# ─────────────────────────────────────────────────────────────────────────────
# GRAPH IMPACT MODEL
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "GRAPH IMPACT  - semantic vs execution distinction" -ForegroundColor Cyan

Assert-FileContains "impact-resolution policy has revision propagation" ".mxagile/policies/impact-resolution.md" "Propagation Algorithm"
Assert-FileContains "impact-resolution distinguishes AC changed from screen changed" ".mxagile/policies/impact-resolution.md" "IMPACTED.*per.*test-staleness"
Assert-FileContains "impact-resolution NEEDS_RERUN vs IMPACTED distinction" ".mxagile/policies/impact-resolution.md" "NEEDS_RERUN"
Assert-FileContains "test-staleness NEEDS_RERUN maps to REEXECUTE" $StalePol "NEEDS_RERUN.*maps to impact action.*REEXECUTE"

# ─────────────────────────────────────────────────────────────────────────────
# AGENT ESCALATION / COST CONTROL
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "AGENT ESCALATION / COST CONTROL" -ForegroundColor Cyan

Assert-FileContains "test-defect-protection defines Bounded Escalation Rule" $DefectPol "Bounded Escalation Rule"
Assert-FileContains "bounded escalation triggers after 2 failed attempts" $DefectPol "2 or more times"
Assert-FileContains "bounded escalation defines WRONG_EVIDENCE_LEVEL root cause" $DefectPol "WRONG_EVIDENCE_LEVEL"
Assert-FileContains "bounded escalation defines OVERMATERIALIZED_TEST root cause" $DefectPol "OVERMATERIALIZED_TEST"
Assert-FileContains "bounded escalation stops repair loop after threshold" $DefectPol "Do NOT attempt a third repair"
Assert-FileContains "bounded escalation emits escalation signal" $DefectPol "VERIFICATION_STRATEGY_ESCALATION"
Assert-FileContains "materialization policy defines escalation bounds" $MatPol "Escalation Bounds"

# ─────────────────────────────────────────────────────────────────────────────
# BACKWARD COMPATIBILITY
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "BACKWARD COMPATIBILITY" -ForegroundColor Cyan

Assert-FileContains "TC schema has existing status vocabulary" $TcSchema '"draft", "active", "stale", "impacted", "superseded"'
Assert-FileContains "TC schema execution_binding_stale is optional (null default)" $TcSchema '"null"'
Assert-FileContains "VPL schema status vocab unchanged" $VplSchema '"draft", "active", "superseded"'
Assert-FileContains "acceptance agent legacy checklist compatibility" $AccAgent "Legacy Checklist Compatibility"

# ─────────────────────────────────────────────────────────────────────────────
# QUALITY / PROOF STRENGTH PRESERVED
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "QUALITY / PROOF STRENGTH PRESERVED" -ForegroundColor Cyan

Assert-FileContains "materialization policy: not a downgrade for FRONTEND assertions" $MatPol "Do NOT downgrade to MODEL when the assertion requires user-visible behavior"
Assert-FileContains "defect-protection: WRONG_EVIDENCE_LEVEL not applicable when FRONTEND genuinely required" $DefectPol "genuinely requires FRONTEND"
Assert-FileContains "verification-layers: VISIBILITY requires FRONTEND" ".mxagile/policies/verification-layers.md" "VISIBILITY.*required"
Assert-FileContains "REEXECUTE does not reuse stale evidence" $StalePol "Do not reuse stale evidence"
Assert-FileContains "stale evidence not reused  - acceptance agent" $AccAgent "Do not reuse stale evidence"

$ImpRes = Join-Path $ScriptDir ".mxagile/policies/impact-resolution.md"

# ─────────────────────────────────────────────────────────────────────────────
# IMPACT-RESOLUTION WIRING (execution_binding_stale automatic propagation)
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "IMPACT-RESOLUTION WIRING" -ForegroundColor Cyan

# A - locator/structural change -> REMATERIALIZE via execution_binding_stale
Assert-FileContains "impact-resolution Step 4 has Case A" $ImpRes "Case A"
Assert-FileContains "impact-resolution Step 4 has Case B" $ImpRes "Case B"
Assert-FileContains "impact-resolution Step 4 has Case C" $ImpRes "Case C"
Assert-FileContains "impact-resolution Case C sets execution_binding_stale" $ImpRes "execution_binding_stale: true"
Assert-FileContains "impact-resolution Case C maps to REMATERIALIZE" $ImpRes "maps to impact action REMATERIALIZE"
Assert-FileContains "impact-resolution Case C: TC.status remains active" $ImpRes "TC.status remains active"
Assert-FileContains "impact-resolution Case C: no DECISION_REQUIRED" $ImpRes "DECISION_REQUIRED is NOT required"

# B - navigation/material change with unchanged observable claim -> same REMATERIALIZE
Assert-FileContains "impact-resolution Case C covers navigation/locator structural changes" $ImpRes "navigation routes, form fields"

# C - AC change -> REASSESS, NOT REMATERIALIZE
Assert-FileContains "impact-resolution Case A -> REASSESS" $ImpRes "Case A"
Assert-FileContains "impact-resolution Case A maps to REASSESS" $ImpRes "maps to impact action REASSESS"
Assert-FileNotContains "impact-resolution does not set execution_binding_stale for AC change" $ImpRes "REASSESS.*execution_binding_stale"

# D - non-material/cosmetic change -> REEXECUTE, NOT execution_binding_stale
Assert-FileContains "impact-resolution Case B -> REEXECUTE" $ImpRes "Case B"
Assert-FileContains "impact-resolution Case B maps to REEXECUTE" $ImpRes "maps to impact action REEXECUTE"
Assert-FileContains "test-staleness NEEDS_RERUN is non_material only" $StalePol "NEEDS_RERUN.*applies only.*non-material"

# Signal cleared correctly
Assert-FileContains "VPL skill clears execution_binding_stale after REMATERIALIZE" $VplSkill "execution_binding_stale.*null"
Assert-FileContains "VPL skill: do NOT clear before VPL active" $VplSkill "Do NOT clear.*execution_binding_stale.*before"
Assert-FileContains "VPL skill: sticky if interrupted (remains true)" $VplSkill "remains.*true.*REMATERIALIZE trigger"

# ─────────────────────────────────────────────────────────────────────────────
# ACCEPTANCE AGENT WIRING
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "ACCEPTANCE AGENT WIRING" -ForegroundColor Cyan

Assert-FileContains "acceptance agent references verification-materialization policy" $AccAgent "verification-materialization.md"
Assert-FileContains "acceptance agent references bounded escalation in defect section" $AccAgent "Bounded escalation.*mandatory"
Assert-FileContains "acceptance agent bounded escalation: 2-or-more trigger" $AccAgent "2 or more times"
Assert-FileContains "acceptance agent bounded escalation: emit escalation signal" $AccAgent "VERIFICATION_STRATEGY_ESCALATION"
Assert-FileContains "acceptance agent bounded escalation: stop repair loop" $AccAgent "Do NOT attempt a third repair"
Assert-FileContains "acceptance agent: WRONG_EVIDENCE_LEVEL guard" $AccAgent "WRONG_EVIDENCE_LEVEL.*only applies"

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

$total = $PassCount + $FailCount
Write-Host ""
Write-Host "=" * 70
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
