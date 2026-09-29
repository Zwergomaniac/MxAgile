<#
.SYNOPSIS
    System-Check Semantic Correctness Tests

.DESCRIPTION
    Regression coverage for three semantic issues found during the second REAL CapTrack
    acceptance run:
      1. FULLY_NATIVE (migration axis) must not imply reconciliation is complete.
      2. Historical phase reconstruction must not authorize implementation resume when
         canonical state and mutation_eligibility are absent.
      3. evidence_gaps_count: 0 must not imply evidence completeness when legacy mockup
         evidence is present but unreconciled.
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

$SysCheck  = Join-Path $ScriptDir ".mxagile/skills/system-check.md"
$ReconPol  = Join-Path $ScriptDir ".mxagile/policies/reconciliation.md"
$ObmPol    = Join-Path $ScriptDir ".mxagile/policies/observe-before-mutate.md"

# ---------------------------------------------------------------------------
# TEST A: Migration axis and reconciliation axis are separate concerns (Issue 1)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST A: FULLY_NATIVE (migration axis) does not imply reconciliation complete" -ForegroundColor Cyan

Assert-FileContains "A.1 Section F has migration-axis-only note" `
    $SysCheck 'Migration Axis.*Reconciliation Axis|migration axis.*orthogonal'

Assert-FileContains "A.2 Note states FULLY_NATIVE may still require reconciliation" `
    $SysCheck 'FULLY_NATIVE.*may still require.*reconciliation'

Assert-FileContains "A.3 Note directs to Section I for reconciliation requirements" `
    $SysCheck 'Section I.*Lifecycle State.*Reconciliation Detection'

Assert-FileContains "A.4 YAML project_lifecycle_state has migration-axis-only comment" `
    $SysCheck 'migration axis only.*FULLY_NATIVE.*does not imply'

Assert-FileContains "A.5 lifecycle_state section is separate from project_structure section" `
    $SysCheck 'lifecycle_state:[\s\S]{1,200}canonical_state_present'

# ---------------------------------------------------------------------------
# TEST B: No implementation resume without canonical state + mutation_eligibility (Issue 2)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST B: Implementation resume blocked when canonical state is absent" -ForegroundColor Cyan

Assert-FileContains "B.1 Next Steps has rule for canonical_state_present false + implementing phase" `
    $SysCheck 'canonical_state_present.*false.*implementing|canonical_state_present.*false.*AND.*reconstructed'

Assert-FileContains "B.2 Next Steps states implementation MUST NOT resume on historical reconstruction alone" `
    $SysCheck 'MUST NOT resume.*historical|historical.*reconstruction.*alone'

Assert-FileContains "B.3 reconciliation_required_before_implementation in YAML lifecycle_state block" `
    $SysCheck 'reconciliation_required_before_implementation'

Assert-FileContains "B.4 Next Steps requires mutation_eligibility established before implementation action" `
    $SysCheck 'mutation_eligibility.*before any implementation'

Assert-FileContains "B.5 reconciliation.md requires canonical state before resuming (fresh agent contract)" `
    $ReconPol 'planning/lifecycle/process-state.yaml'

# ---------------------------------------------------------------------------
# TEST C: evidence_gaps_count 0 does not imply completeness with legacy evidence (Issue 3)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "TEST C: Legacy evidence unreconciled -- zero canonical gaps is not evidence completeness" -ForegroundColor Cyan

Assert-FileContains "C.1 Section I checks .concord/screenshots/mockup/ for legacy content" `
    $SysCheck '\.concord/screenshots/mockup/'

Assert-FileContains "C.2 Section I defines LEGACY_EVIDENCE_UNRECONCILED: true condition" `
    $SysCheck 'LEGACY_EVIDENCE_UNRECONCILED.*true'

Assert-FileContains "C.3 legacy_evidence_unreconciled field in machine-readable YAML block" `
    $SysCheck 'legacy_evidence_unreconciled: true \| false'

Assert-FileContains "C.4 Section I states evidence_gaps_count 0 does NOT mean evidence complete when legacy unreconciled" `
    $SysCheck 'evidence_gaps_count.*0.*does NOT mean|0.*does NOT mean.*evidence.*complete'

Assert-FileContains "C.5 Next Steps has LEGACY_EVIDENCE_UNRECONCILED action" `
    $SysCheck 'legacy_evidence_unreconciled.*true[\s\S]{1,400}Reconcile and promote legacy evidence'

Assert-FileContains "C.6 Next Steps states evidence_gaps_count 0 does NOT indicate completeness in unreconciled state" `
    $SysCheck 'evidence_gaps_count.*0.*does NOT indicate evidence completeness'

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
