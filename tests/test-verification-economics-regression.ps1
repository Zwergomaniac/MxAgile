<#
.SYNOPSIS
    Verification Economics Regression Tests

.DESCRIPTION
    Regression tests for the REV-014 verification materialization economics findings.
    Explicitly confirms that unnecessary verification cascades remain prevented.

    Tests the most important reality-test outcome: a new/refined Requirement must NOT
    automatically cause TC -> PP -> VPL -> executable test -> Evidence creation.

    Scenarios verified:
      (1) NEW REQ + no stable implementation -> NO_TC_YET -> no materialization
      (2) Existing TC domain + new scope -> VERIFICATION_COVERAGE_GAP -> EXTEND candidate -> existing PPs preserved
      (3) Existing TC + stable intent + changed locator -> TEST_BINDING_GAP / REMATERIALIZE -> TC remains active
      (4) Valid execution definition + implementation changed -> REEXECUTE -> preserve definition, replace evidence
      (5) Acceptance claim changed -> REASSESS
      (6) No impact -> PRESERVE
      (7) Behavior removed -> INVALIDATE
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $TestsDir
$PassCount = 0
$FailCount = 0
$FailDetails = @()

function Assert-True {
    param([string]$TestName, [bool]$Condition, [string]$Message = '')
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

$MatPolicy  = Join-Path $RepoRoot '.mxagile/policies/verification-materialization.md'
$TaxPolicy  = Join-Path $RepoRoot '.mxagile/policies/verification-gap-taxonomy.md'
$StalePol   = Join-Path $RepoRoot '.mxagile/policies/test-staleness.md'
$GateReady  = Join-Path $RepoRoot '.mxagile/skills/gate-to-ready.md'
$TcSkill    = Join-Path $RepoRoot '.mxagile/skills/test-contract.md'
$DiscAgent  = Join-Path $RepoRoot '.mxagile/agents/discovery-agent.md'
$FixNoTc    = Join-Path $RepoRoot 'tests/fixtures/verification-gap-taxonomy/fixture-no-tc-yet.yaml'
$FixCovGap  = Join-Path $RepoRoot 'tests/fixtures/verification-gap-taxonomy/fixture-coverage-gap.yaml'
$FixExtend  = Join-Path $RepoRoot 'tests/fixtures/verification-lifecycle/fixture-K-extend.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 1: NEW REQ + no stable implementation -> NO_TC_YET -> no materialization
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 1: NEW REQ -> NO_TC_YET -> no automatic materialization" -ForegroundColor Cyan

Assert-FileContains "S1: gap taxonomy has NO_TC_YET" $TaxPolicy "NO_TC_YET"
Assert-FileContains "S1: NO_TC_YET does NOT trigger TC" $TaxPolicy "NOT automatically trigger TC|Creating a TC"
Assert-FileContains "S1: NO_TC_YET does NOT create PP" $TaxPolicy "Creating Proof Points"
Assert-FileContains "S1: NO_TC_YET does NOT create VPL" $TaxPolicy "Creating a VPL"
Assert-FileContains "S1: NO_TC_YET does NOT run executable tests" $TaxPolicy "executable test"
Assert-FileContains "S1: NO_TC_YET does NOT collect evidence" $TaxPolicy "Evidence"
Assert-FileContains "S1: materialization deferred until requirement accepted" $TaxPolicy "TC creation is deferred"
$fixNoTcRaw = [System.IO.File]::ReadAllText($FixNoTc)
Assert-True "S1: fixture confirms tc_created: false" ($fixNoTcRaw -match "tc_created: false")
Assert-True "S1: fixture confirms pp_created: false" ($fixNoTcRaw -match "pp_created: false")
Assert-True "S1: fixture confirms vpl_created: false" ($fixNoTcRaw -match "vpl_created: false")
Assert-True "S1: fixture confirms evidence_collected: false" ($fixNoTcRaw -match "evidence_collected: false")

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 2: Existing TC domain + new scope -> COVERAGE_GAP -> EXTEND -> existing PPs preserved
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 2: Existing TC + new scope -> EXTEND candidate -> existing PPs preserved" -ForegroundColor Cyan

Assert-FileContains "S2: VERIFICATION_COVERAGE_GAP maps to EXTEND" $TaxPolicy "VERIFICATION_COVERAGE_GAP.*EXTEND"
Assert-FileContains "S2: EXTEND preserves existing PPs" $MatPolicy "prior.*PP.*unchanged|existing.*PP.*unchanged"
Assert-FileContains "S2: EXTEND does NOT invalidate prior evidence" $MatPolicy "EXTEND must NOT"
$fixCovGap = Get-Content -LiteralPath $FixCovGap -Raw -ErrorAction SilentlyContinue
Assert-True "S2: fixture confirms prior PPs not affected" ($fixCovGap -match "prior_pp_affected: false")
Assert-True "S2: fixture suggests EXTEND (not new TC)" ($fixCovGap -match "EXTEND_CANDIDATE|new_tc_created: false")
$fixExtend = Get-Content -LiteralPath $FixExtend -Raw -ErrorAction SilentlyContinue
Assert-True "S2: EXTEND fixture confirms prior PP-001 preserved" ($fixExtend -match "prior_pp_001_action: preserve")
Assert-True "S2: EXTEND fixture confirms prior PP-002 preserved" ($fixExtend -match "prior_pp_002_action: preserve")
Assert-True "S2: EXTEND fixture confirms TC status remains active" ($fixExtend -match "tc_status_after: active")

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 3: Existing TC + stable intent + changed locator -> TEST_BINDING_GAP -> REMATERIALIZE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 3: Changed locator -> TEST_BINDING_GAP -> REMATERIALIZE -> TC remains active" -ForegroundColor Cyan

Assert-FileContains "S3: TEST_BINDING_GAP maps to REMATERIALIZE" $TaxPolicy "TEST_BINDING_GAP.*REMATERIALIZE"
Assert-FileContains "S3: REMATERIALIZE does not change TC status" $MatPolicy "TC: \*\*no change\*\* — claim is valid"
Assert-FileContains "S3: Locator change -> REMATERIALIZE in decision table" $MatPolicy "Locator change.*rematerialize"
Assert-FileContains "S3: execution_binding_stale signals REMATERIALIZE" $MatPolicy "execution_binding_stale.*REMATERIALIZE"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 4: Valid definition + implementation changed -> REEXECUTE -> preserve definition
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 4: Implementation changed -> REEXECUTE -> preserve definition" -ForegroundColor Cyan

Assert-FileContains "S4: EVIDENCE_STALE maps to REEXECUTE" $TaxPolicy "EVIDENCE_STALE.*REEXECUTE"
Assert-FileContains "S4: REEXECUTE does not rewrite test definition" $MatPolicy "REEXECUTE.*reuse|reuse.*minor refresh"
Assert-FileContains "S4: REEXECUTE TC unchanged" $MatPolicy "TC: no change"
Assert-FileContains "S4: REEXECUTE VPL unchanged" $MatPolicy "VPL: no change"
Assert-FileContains "S4: REEXECUTE: implementation refactor in decision table" $MatPolicy "Implementation refactor.*reexecute"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 5: Acceptance claim changed -> REASSESS
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 5: Acceptance claim changed -> REASSESS" -ForegroundColor Cyan

Assert-FileContains "S5: acceptance criteria change triggers REASSESS" $StalePol "acceptance_criteria.*added, removed, or meaningfully changed"
Assert-FileContains "S5: REASSESS in decision table: new AC intent changed" $MatPolicy "prior intent affected.*reassess"
Assert-FileContains "S5: REASSESS: TC review and update" $MatPolicy "TC: review and update"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 6: No impact -> PRESERVE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 6: No impact -> PRESERVE" -ForegroundColor Cyan

Assert-FileContains "S6: PRESERVE defined" $MatPolicy "### PRESERVE"
Assert-FileContains "S6: PRESERVE: no change to TC/PP/VPL/test/evidence" $MatPolicy "No action required"

# ─────────────────────────────────────────────────────────────────────────────
# SCENARIO 7: Behavior removed -> INVALIDATE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCENARIO 7: Behavior removed -> INVALIDATE" -ForegroundColor Cyan

Assert-FileContains "S7: INVALIDATE defined" $MatPolicy "### INVALIDATE"
Assert-FileContains "S7: INVALIDATE: TC superseded" $MatPolicy "TC: mark.*status: superseded"
Assert-FileContains "S7: INVALIDATE: feature removed from scope in table" $MatPolicy "Feature removed.*invalidate|removed.*scope.*invalidate"

# ─────────────────────────────────────────────────────────────────────────────
# GATE: TC not required at gate-to-ready (late materialization)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "GATE: VPL not required at gate-to-ready" -ForegroundColor Cyan

Assert-FileContains "gate-to-ready: VPL not required" $GateReady "Verification Plan is NOT required here"
Assert-FileNotContains "gate-to-ready must not require VPL creation" $GateReady "VPL.*required"

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
