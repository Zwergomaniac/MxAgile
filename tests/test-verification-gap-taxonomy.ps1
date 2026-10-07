<#
.SYNOPSIS
    Verification Gap Taxonomy Tests

.DESCRIPTION
    Verifies that the four gap classifications are correctly defined,
    that NO_TC_YET does NOT trigger automatic materialization,
    and that each classification maps to the correct impact action.

    P0 REV-014 hardening: prevents all-requirements-as-TEST_BINDING_GAP classification error.

    Tests:
      - Gap taxonomy policy exists and defines all four types
      - NO_TC_YET does NOT trigger TC/PP/VPL/test/evidence
      - VERIFICATION_COVERAGE_GAP maps to EXTEND candidate
      - TEST_BINDING_GAP maps to REMATERIALIZE
      - EVIDENCE_STALE maps to REEXECUTE
      - Materialization policy references gap taxonomy
      - Fixtures correctly demonstrate each classification
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

$TaxPolicy   = Join-Path $RepoRoot '.mxagile/policies/verification-gap-taxonomy.md'
$MatPolicy   = Join-Path $RepoRoot '.mxagile/policies/verification-materialization.md'
$StalePol    = Join-Path $RepoRoot '.mxagile/policies/test-staleness.md'
$DiscAgent   = Join-Path $RepoRoot '.mxagile/agents/discovery-agent.md'
$FixNoTc     = Join-Path $RepoRoot 'tests/fixtures/verification-gap-taxonomy/fixture-no-tc-yet.yaml'
$FixCovGap   = Join-Path $RepoRoot 'tests/fixtures/verification-gap-taxonomy/fixture-coverage-gap.yaml'
$FixBindGap  = Join-Path $RepoRoot 'tests/fixtures/verification-gap-taxonomy/fixture-test-binding-gap.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: gap taxonomy defined
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: verification-gap-taxonomy.md" -ForegroundColor Cyan

Assert-FileExists "gap taxonomy policy exists" $TaxPolicy
Assert-FileContains "taxonomy defines NO_TC_YET" $TaxPolicy "NO_TC_YET"
Assert-FileContains "taxonomy defines VERIFICATION_COVERAGE_GAP" $TaxPolicy "VERIFICATION_COVERAGE_GAP"
Assert-FileContains "taxonomy defines TEST_BINDING_GAP" $TaxPolicy "TEST_BINDING_GAP"
Assert-FileContains "taxonomy defines EVIDENCE_STALE" $TaxPolicy "EVIDENCE_STALE"
Assert-FileContains "taxonomy has classification decision table" $TaxPolicy "Classification Decision Table"
Assert-FileContains "taxonomy references verification-materialization" $TaxPolicy "verification-materialization"

# ─────────────────────────────────────────────────────────────────────────────
# NO_TC_YET: does NOT trigger cascade
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "NO_TC_YET: must NOT trigger automatic materialization" -ForegroundColor Cyan

Assert-FileContains "NO_TC_YET does NOT trigger TC" $TaxPolicy "NOT automatically trigger TC|NO_TC_YET.*authorize.*TC|Creating a TC"
Assert-FileContains "NO_TC_YET does NOT create PP" $TaxPolicy "Creating Proof Points|NOT.*PP|PP.*NOT"
Assert-FileContains "NO_TC_YET does NOT create VPL" $TaxPolicy "Creating a VPL|NOT.*VPL|VPL.*NOT"
Assert-FileContains "NO_TC_YET late materialization invariant" $TaxPolicy "Late-Materialization Invariant"
Assert-FileContains "late materialization: no automatic TC cascade" $TaxPolicy "NO automatic TC"
Assert-FileContains "late materialization: no automatic evidence" $TaxPolicy "NO automatic Evidence|NO.*Evidence.*collection"

# ─────────────────────────────────────────────────────────────────────────────
# CLASSIFICATION MAPPING
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "CLASSIFICATION: gap type to action mapping" -ForegroundColor Cyan

Assert-FileContains "taxonomy: VERIFICATION_COVERAGE_GAP -> EXTEND" $TaxPolicy "VERIFICATION_COVERAGE_GAP.*EXTEND|EXTEND.*VERIFICATION_COVERAGE"
Assert-FileContains "taxonomy: TEST_BINDING_GAP -> REMATERIALIZE" $TaxPolicy "TEST_BINDING_GAP.*REMATERIALIZE|REMATERIALIZE.*TEST_BINDING"
Assert-FileContains "taxonomy: EVIDENCE_STALE -> REEXECUTE" $TaxPolicy "EVIDENCE_STALE.*REEXECUTE|REEXECUTE.*EVIDENCE_STALE"
Assert-FileContains "taxonomy: NO_TC_YET -> deferred" $TaxPolicy "TC creation is deferred|deferred until"

# ─────────────────────────────────────────────────────────────────────────────
# DISTINCTION: VERIFICATION_COVERAGE_GAP vs NO_TC_YET
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "DISTINCTION: NO_TC_YET vs VERIFICATION_COVERAGE_GAP" -ForegroundColor Cyan

Assert-FileContains "taxonomy distinguishes NO_TC_YET from COVERAGE_GAP" $TaxPolicy "NO_TC_YET.*domain.*exists|domain.*no.*TC"
Assert-FileContains "COVERAGE_GAP: TC exists in domain but scope incomplete" $TaxPolicy "VERIFICATION_COVERAGE_GAP.*TC.*domain|domain.*existing.*TC"

# ─────────────────────────────────────────────────────────────────────────────
# MATERIALIZATION POLICY: references gap taxonomy
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "MATERIALIZATION POLICY: references gap taxonomy" -ForegroundColor Cyan

Assert-FileContains "materialization policy references gap taxonomy" $MatPolicy "verification-gap-taxonomy"
Assert-FileContains "materialization policy: NO_TC_YET no action" $MatPolicy "NO_TC_YET.*No action|No action.*NO_TC_YET"
Assert-FileContains "materialization policy: COVERAGE_GAP -> EXTEND" $MatPolicy "VERIFICATION_COVERAGE_GAP.*EXTEND"
Assert-FileContains "materialization policy: TEST_BINDING_GAP -> REMATERIALIZE" $MatPolicy "TEST_BINDING_GAP.*REMATERIALIZE"
Assert-FileContains "materialization policy: EVIDENCE_STALE -> REEXECUTE" $MatPolicy "EVIDENCE_STALE.*REEXECUTE"

# ─────────────────────────────────────────────────────────────────────────────
# DISCOVERY AGENT: records gap classification
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "DISCOVERY AGENT: records gap classification" -ForegroundColor Cyan

Assert-FileContains "discovery agent references gap taxonomy policy" $DiscAgent "verification-gap-taxonomy"
Assert-FileContains "discovery agent records NO_TC_YET" $DiscAgent "NO_TC_YET"
Assert-FileContains "discovery agent: NO_TC_YET does NOT trigger TC creation" $DiscAgent "KEINE TC.*Erstellung|TC.*NICHT.*NO_TC_YET"

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURES: gap taxonomy scenarios" -ForegroundColor Cyan

Assert-FileExists "NO_TC_YET fixture exists" $FixNoTc
$fixNoTc = Get-Content -LiteralPath $FixNoTc -Raw -ErrorAction SilentlyContinue
Assert-True "NO_TC_YET fixture: classification is NO_TC_YET" ($fixNoTc -match "classification: NO_TC_YET")
Assert-True "NO_TC_YET fixture: tc_created: false" ($fixNoTc -match "tc_created: false")
Assert-True "NO_TC_YET fixture: pp_created: false" ($fixNoTc -match "pp_created: false")
Assert-True "NO_TC_YET fixture: vpl_created: false" ($fixNoTc -match "vpl_created: false")
Assert-True "NO_TC_YET fixture: evidence_collected: false" ($fixNoTc -match "evidence_collected: false")

Assert-FileExists "VERIFICATION_COVERAGE_GAP fixture exists" $FixCovGap
$fixCovGap = Get-Content -LiteralPath $FixCovGap -Raw -ErrorAction SilentlyContinue
Assert-True "COVERAGE_GAP fixture: classification is VERIFICATION_COVERAGE_GAP" ($fixCovGap -match "classification: VERIFICATION_COVERAGE_GAP")
Assert-True "COVERAGE_GAP fixture: new_tc_created: false" ($fixCovGap -match "new_tc_created: false")
Assert-True "COVERAGE_GAP fixture: extend existing TC" ($fixCovGap -match "extend_existing_tc: true|EXTEND_CANDIDATE")
Assert-True "COVERAGE_GAP fixture: related_tc_id recorded" ($fixCovGap -match "related_tc_id")

Assert-FileExists "TEST_BINDING_GAP fixture exists" $FixBindGap
$fixBindGap = Get-Content -LiteralPath $FixBindGap -Raw -ErrorAction SilentlyContinue
Assert-True "TEST_BINDING_GAP fixture: classification is TEST_BINDING_GAP" ($fixBindGap -match "classification: TEST_BINDING_GAP")
Assert-True "TEST_BINDING_GAP fixture: action is REMATERIALIZE" ($fixBindGap -match "action: REMATERIALIZE")
Assert-True "TEST_BINDING_GAP fixture: NOT REASSESS" ($fixBindGap -match "not_reassess|NOT.*REASSESS")
Assert-True "EVIDENCE_STALE fixture: classification in same file" ($fixBindGap -match "classification: EVIDENCE_STALE")
Assert-True "EVIDENCE_STALE fixture: action is REEXECUTE" ($fixBindGap -match "action: REEXECUTE")
Assert-True "EVIDENCE_STALE vs TEST_BINDING_GAP distinction documented" ($fixBindGap -match "TEST_BINDING_GAP.*binding.*missing|binding.*missing.*TEST_BINDING")

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
