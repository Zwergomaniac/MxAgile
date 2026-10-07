<#
.SYNOPSIS
    EXTEND Semantics Tests

.DESCRIPTION
    Verifies that the EXTEND action is correctly defined and that
    existing PP/VPL/evidence are preserved when unaffected scope is extended.

    P1 REV-014 hardening: adds EXTEND to the verification economics vocabulary.

    Tests:
      - verification-materialization.md defines EXTEND
      - test-staleness.md defines EXTEND in revision impact table
      - EXTEND preserves existing PP/VPL/evidence
      - EXTEND only adds new PPs for new scope
      - EXTEND is NOT REASSESS
      - EXTEND is NOT REMATERIALIZE
      - fixture-K demonstrates EXTEND scenario correctly
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
$StalePol   = Join-Path $RepoRoot '.mxagile/policies/test-staleness.md'
$FixExtend  = Join-Path $RepoRoot 'tests/fixtures/verification-lifecycle/fixture-K-extend.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# MATERIALIZATION POLICY: EXTEND defined
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "MATERIALIZATION POLICY: EXTEND action defined" -ForegroundColor Cyan

Assert-FileContains "materialization policy defines EXTEND" $MatPolicy "### EXTEND"
Assert-FileContains "EXTEND: existing TC/PP/VPL/evidence preserved" $MatPolicy "EXTEND.*preserve|preserve.*EXTEND"
Assert-FileContains "EXTEND: TC status remains active" $MatPolicy "TC.*remains.*active|active.*TC.*EXTEND"
Assert-FileContains "EXTEND: new PPs appended only for new scope" $MatPolicy "new.*PP.*appended|appended.*new.*PP"
Assert-FileContains "EXTEND does NOT invalidate existing PPs" $MatPolicy "EXTEND must NOT|prior PPs unchanged"
Assert-FileContains "EXTEND does NOT rebuild prior tests" $MatPolicy "Rebuild or rematerialize prior|prior tests unchanged"
Assert-FileContains "EXTEND does NOT require DECISION_REQUIRED for unambiguous scope" $MatPolicy "DECISION_REQUIRED.*unambiguous|EXTEND.*NOT.*DECISION_REQUIRED"
Assert-FileContains "EXTEND differs from REASSESS" $MatPolicy "EXTEND.*REASSESS|REASSESS.*EXTEND"
Assert-FileContains "EXTEND in impact action decision table" $MatPolicy "extend.*new.*PP.*appended|prior.*AC.*valid.*extend"

# ─────────────────────────────────────────────────────────────────────────────
# TEST-STALENESS: EXTEND in revision impact table
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "TEST-STALENESS: EXTEND in revision impact vocabulary" -ForegroundColor Cyan

Assert-FileContains "test-staleness defines EXTEND" $StalePol "EXTEND"
Assert-FileContains "test-staleness EXTEND: TC remains active" $StalePol "EXTEND.*active|unchanged.*active.*EXTEND"
Assert-FileContains "test-staleness EXTEND: prior PPs unchanged" $StalePol "prior PPs unchanged|existing PPs unchanged"
Assert-FileContains "test-staleness EXTEND differs from REASSESS" $StalePol "EXTEND.*REASSESS"
Assert-FileContains "test-staleness EXTEND: prior evidence preserved" $StalePol "prior evidence.*valid|evidence.*preserved.*EXTEND"
Assert-FileContains "test-staleness EXTEND does NOT require DECISION_REQUIRED" $StalePol "EXTEND.*NOT.*DECISION_REQUIRED"

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURE K: EXTEND scenario
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE K: EXTEND scenario" -ForegroundColor Cyan

Assert-FileExists "fixture-K exists" $FixExtend
$fixK = Get-Content -LiteralPath $FixExtend -Raw -ErrorAction SilentlyContinue
Assert-True "K: action is extend" ($fixK -match "action: extend")
Assert-True "K: tc_action is extend" ($fixK -match "tc_action: extend")
Assert-True "K: tc_status_after is active" ($fixK -match "tc_status_after: active")
Assert-True "K: pp_action is extend" ($fixK -match "pp_action: extend")
Assert-True "K: prior PP-001 preserved" ($fixK -match "prior_pp_001_action: preserve")
Assert-True "K: prior PP-002 preserved" ($fixK -match "prior_pp_002_action: preserve")
Assert-True "K: evidence_action preserves prior" ($fixK -match "evidence_action: preserve_prior")
Assert-True "K: DECISION_REQUIRED must NOT be raised" ($fixK -match "DECISION_REQUIRED: must NOT")
Assert-True "K: PP-001 claim must NOT change (invariant)" ($fixK -match "PP-001 claim must NOT change")
Assert-True "K: PP-001/PP-002 evidence must NOT be invalidated (invariant)" ($fixK -match "PP-001.*PP-002.*evidence must NOT")
Assert-True "K: EXTEND is not REASSESS documented" ($fixK -match "extend_is_NOT_reassess")
Assert-True "K: EXTEND is not REMATERIALIZE documented" ($fixK -match "extend_is_NOT_rematerialize")

# ─────────────────────────────────────────────────────────────────────────────
# COMPLETE VOCABULARY CHECK
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "COMPLETE VOCABULARY: all 6 actions present" -ForegroundColor Cyan

Assert-FileContains "materialization policy has PRESERVE" $MatPolicy "### PRESERVE"
Assert-FileContains "materialization policy has EXTEND" $MatPolicy "### EXTEND"
Assert-FileContains "materialization policy has REASSESS" $MatPolicy "### REASSESS"
Assert-FileContains "materialization policy has REMATERIALIZE" $MatPolicy "### REMATERIALIZE"
Assert-FileContains "materialization policy has REEXECUTE" $MatPolicy "### REEXECUTE"
Assert-FileContains "materialization policy has INVALIDATE" $MatPolicy "### INVALIDATE"

Assert-FileContains "test-staleness has PRESERVE" $StalePol "PRESERVE"
Assert-FileContains "test-staleness has EXTEND" $StalePol "EXTEND"
Assert-FileContains "test-staleness has REASSESS" $StalePol "REASSESS"
Assert-FileContains "test-staleness has REMATERIALIZE" $StalePol "REMATERIALIZE"
Assert-FileContains "test-staleness has REEXECUTE" $StalePol "REEXECUTE"
Assert-FileContains "test-staleness has INVALIDATE" $StalePol "INVALIDATE"

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
