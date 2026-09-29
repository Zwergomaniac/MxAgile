<#
.SYNOPSIS
    UI Parity Contract Tests: Multi-Dimensional Parity Verification

.DESCRIPTION
    Validates that MxAgile canonical guidance correctly implements the 7-dimension parity
    contract, aggregation rules, content parity, observe-before-mutate enforcement,
    source/target mockup lifecycle, legacy evidence upgrade, and targeted re-verification.

    Test cases:
    A. Seven parity dimensions defined in canonical schema
    B. Aggregation: overall PASS requires all required dimensions PASS
    C. Aggregation: single FAILED dimension causes overall FAIL
    D. Content parity is a first-class dimension (not screenshot-only)
    E. Mandatory regression scenario: visual PASS + content FAIL = overall FAIL
    F. Observe-Before-Mutate lifecycle defined and enforced
    G. Source mockup is immutable; target mockup is the active verification reference
    H. Legacy PASS result must not become 7x PASS automatically
    I. LEGACY_EVIDENCE status is defined and used for schema upgrade
    J. NOT_VERIFIED dimension blocks overall PASS when required=true
    K. Targeted re-verification: only verify gaps, not entire suite
    L. Parity reconciliation state tracks pages_remaining for resumability
    M. Req/Spec/Task depth upgrade: existing artifacts gain parity reference without bulk regen
    N. Content dimension requires DOM text evidence, not screenshot alone
    O. Role parity requires separate session per role
    P. Responsive parity requires viewport-specific evidence
    Q. Parity output goes to planning/parity/, not just ui-inventory/
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
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Expected pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

$ParitySchema   = Join-Path $ScriptDir ".mxagile/schemas/parity-verification.schema.json"
$ParityPol      = Join-Path $ScriptDir ".mxagile/policies/ui-parity.md"
$ObsMut         = Join-Path $ScriptDir ".mxagile/policies/observe-before-mutate.md"
$MockupLife     = Join-Path $ScriptDir ".mxagile/policies/mockup-lifecycle.md"
$UiAgent        = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$ProcState      = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"
$PageSchema     = Join-Path $ScriptDir ".mxagile/schemas/page.schema.json"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: Seven parity dimensions defined in canonical schema" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "A.1 parity schema has visual dimension" $ParitySchema '"visual"'
Assert-FileContains "A.2 parity schema has content dimension" $ParitySchema '"content"'
Assert-FileContains "A.3 parity schema has structure dimension" $ParitySchema '"structure"'
Assert-FileContains "A.4 parity schema has state dimension" $ParitySchema '"state"'
Assert-FileContains "A.5 parity schema has interaction dimension" $ParitySchema '"interaction"'
Assert-FileContains "A.6 parity schema has responsive dimension" $ParitySchema '"responsive"'
Assert-FileContains "A.7 parity schema has role dimension" $ParitySchema '"role"'
Assert-FileContains "A.8 policy defines 7 dimensions table" $ParityPol 'visual.*colors|visual.*styling'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Aggregation requires all required dimensions to PASS for overall PASS" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "B.1 schema description states PASS requires all required dimensions pass" $ParitySchema 'all REQUIRED dimensions'
Assert-FileContains "B.2 policy defines PASS aggregation rule" $ParityPol 'overall_result = PASS'
Assert-FileContains "B.3 policy states required dimension rules" $ParityPol 'required.*dimensions'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: Single FAILED dimension causes overall FAIL" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "C.1 policy states FAIL aggregation rule" $ParityPol 'overall_result = FAIL'
Assert-FileContains "C.2 policy states ANY required FAILED causes overall FAIL" $ParityPol 'ANY required dimension'
Assert-FileContains "C.3 schema has FAIL status in overall_result enum" $ParitySchema '"FAIL"'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST D: Content parity is a first-class dimension" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "D.1 policy defines content dimension with DOM text requirement" $ParityPol 'dom_text'
Assert-FileContains "D.2 policy states screenshot alone is insufficient for content" $ParityPol 'screenshots.*alone|screenshot alone'
Assert-FileContains "D.3 schema has dom_text as evidence type" $ParitySchema 'dom_text'
Assert-FileContains "D.4 ui-agent.md requires DOM text extraction for content" $UiAgent 'DOM-Text-Extraktion'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST E: Mandatory regression scenario — visual PASS + content FAIL = overall FAIL" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "E.1 policy documents mandatory regression scenario" $ParityPol 'Mandatory Regression Scenario'
Assert-FileContains "E.2 policy example shows visual=PASS and content=FAIL" $ParityPol 'visual.*PASS'
Assert-FileContains "E.3 policy example shows overall=FAIL when content fails" $ParityPol 'overall_result: FAIL'
Assert-FileContains "E.4 schema has regression_scenario field for test documentation" $ParitySchema 'regression_scenario'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST F: Observe-Before-Mutate lifecycle defined and enforced" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "F.1 observe-before-mutate policy exists with the rule" $ObsMut 'OBSERVE FIRST'
Assert-FileContains "F.2 policy defines MUTATE_BEFORE_OBSERVE violation" $ObsMut 'MUTATE_BEFORE_OBSERVE'
Assert-FileContains "F.3 policy defines the 6-step enforced lifecycle" $ObsMut 'BASELINE CAPTURE'
Assert-FileContains "F.4 process-state has observe_before_mutate_stage field" $ProcState 'observe_before_mutate_stage'
Assert-FileContains "F.5 ui-agent references observe-before-mutate policy" $UiAgent 'observe-before-mutate'
Assert-FileContains "F.6 violation_detected state is defined" $ProcState 'violation_detected'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST G: Source mockup immutable; target mockup is active verification reference" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "G.1 mockup-lifecycle.md defines source as immutable" $MockupLife 'IMMUTABLE'
Assert-FileContains "G.2 policy defines target mockup as active acceptance target" $MockupLife 'active acceptance target'
Assert-FileContains "G.3 page schema has target_mockup field" $PageSchema 'target_mockup'
Assert-FileContains "G.4 parity schema has both source_mockup and target_mockup fields" $ParitySchema '"target_mockup"'
Assert-FileContains "G.5 ui-agent uses target_mockup for verification" $UiAgent 'target_mockup'
Assert-FileContains "G.6 policy prohibits modifying source mockup" $MockupLife 'Never modify'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST H: Legacy PASS result must not become 7x PASS automatically" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "H.1 ui-parity.md explicitly prohibits fabricating 7x PASS from legacy" $ParityPol 'MUST NOT be converted'
Assert-FileContains "H.2 LEGACY_EVIDENCE status is defined for migration" $ParityPol 'LEGACY_EVIDENCE'
Assert-FileContains "H.3 policy shows correct upgrade example with NOT_VERIFIED" $ParityPol 'NOT_VERIFIED'
Assert-FileContains "H.4 schema has LEGACY_EVIDENCE in parity_dimension result enum" $ParitySchema '"LEGACY_EVIDENCE"'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST I: LEGACY_EVIDENCE status supports schema upgrade with provenance" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "I.1 parity dimension schema has legacy_provenance field" $ParitySchema 'legacy_provenance'
Assert-FileContains "I.2 evidence_upgrade_state in parity schema" $ParitySchema 'evidence_upgrade'
Assert-FileContains "I.3 evidence_upgrade_state has schema_upgraded flag" $ParitySchema 'schema_upgraded'
Assert-FileContains "I.4 evidence_upgrade_state has gaps array" $ParitySchema '"gaps"'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST J: NOT_VERIFIED required dimension blocks overall PASS" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "J.1 schema overall_result description states NOT_VERIFIED blocks PASS" $ParitySchema 'NOT_VERIFIED'
Assert-FileContains "J.2 policy states NOT_VERIFIED required dimension must prevent PASS" $ParityPol 'NOT_VERIFIED.*prevent|prevent.*PASS'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST K: Targeted re-verification verifies only gaps" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "K.1 ui-parity.md defines lazy reconciliation" $ParityPol 'Lazy Reconciliation'
Assert-FileContains "K.2 lazy reconciliation only runs for NOT_VERIFIED or LEGACY_EVIDENCE" $ParityPol 'NOT_VERIFIED or LEGACY_EVIDENCE'
Assert-FileContains "K.3 evidence_upgrade.targeted_reverification_required flag exists" $ParitySchema 'targeted_reverification_required'
Assert-FileContains "K.4 evidence_upgrade.remaining_scenarios for resumability" $ParitySchema 'remaining_scenarios'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST L: Parity reconciliation state tracks resumability" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "L.1 process-state has parity_reconciliation block" $ProcState 'parity_reconciliation'
Assert-FileContains "L.2 reconciliation block has pages_remaining array" $ProcState 'pages_remaining'
Assert-FileContains "L.3 reconciliation block has mode field (lazy/full)" $ProcState '"lazy"'
Assert-FileContains "L.4 reconciliation block has overall_result for status tracking" $ProcState '"in_progress"'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST M: Req/Spec/Task artifacts gain parity reference without bulk regeneration" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "M.1 ui-parity.md states targeted re-verification supports lazy reconciliation" $ParityPol 'lazy'
Assert-FileContains "M.2 evidence_upgrade.reverification_completed tracks completion" $ParitySchema 'reverification_completed'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST N: Content dimension requires DOM text evidence" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "N.1 ui-agent.md requires DOM text extraction for content dimension" $UiAgent 'dom_text'
Assert-FileContains "N.2 policy lists navigation group names as content targets" $ParityPol 'navigation group names'
Assert-FileContains "N.3 policy lists column headers as content targets" $ParityPol 'column header'
Assert-FileContains "N.4 policy lists button captions as content targets" $ParityPol 'button caption'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST O: Role parity requires separate session per role" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "O.1 policy requires separate Playwright session per role" $ParityPol 'separate Playwright'
Assert-FileContains "O.2 ui-agent.md verifying modus runs separate role sessions" $UiAgent 'Rollenspezifische'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST P: Responsive parity requires viewport-specific evidence" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "P.1 policy requires viewport-specific screenshot for responsive" $ParityPol 'viewport-specific screenshot'
Assert-FileContains "P.2 ui-agent.md runs multiple viewports for responsive dimension" $UiAgent 'Viewport'
Assert-FileContains "P.3 parity schema has viewport field" $ParitySchema '"viewport"'
Assert-FileContains "P.4 policy derives required viewports from requirements, not unconditionally" $ParityPol 'Required viewports are derived'
Assert-FileContains "P.5 policy does NOT mandate desktop+phone unconditionally" $ParityPol 'Do NOT require desktop'
Assert-FileContains "P.6 policy states responsive NOT_APPLICABLE when no responsive requirement" $ParityPol 'responsive.*NOT_APPLICABLE|NOT_APPLICABLE.*for those screens'

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST Q: Parity output goes to planning/parity/, legacy stays in ui-inventory/" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Assert-FileContains "Q.1 ui-agent.md outputs parity files to planning/parity/" $UiAgent 'planning/parity/'
Assert-FileContains "Q.2 ui-agent.md preserves legacy comparison.yaml" $UiAgent 'Legacy'
Assert-FileContains "Q.3 ui-parity.md references parity schema file location" $ParityPol 'parity-verification.schema.json'

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
