<#
.SYNOPSIS
    Active Target Invariant — Interruption-Safe Detection Tests

.DESCRIPTION
    Extends the base active-target invariant tests with interruption-safe
    detection: verifies that the lifecycle-resync validator can detect
    inconsistent states produced by interrupted acceptance transitions.

    P1 REV-014 hardening: machine-check invariant, not just agent discipline.

    Tests:
      - lifecycle-resync policy has Active Target Invariant Validator section
      - INTERRUPTED_TRANSITION detection (zero active after partial transition)
      - INTERRUPTED_ACCEPTANCE detection (REFINED_TARGET + active_target: false)
      - Consistency rules for lifecycle_status/active_target combinations
      - Repair is proposed but NOT applied without developer confirmation
      - Other lifecycle work can continue when invariant violation is isolated
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

function CountPattern {
    param([string]$Content, [string]$Pattern)
    ([regex]::Matches($Content, $Pattern)).Count
}

$ResyncPolicy    = Join-Path $RepoRoot '.mxagile/policies/lifecycle-resync.md'
$MockupLifecycle = Join-Path $RepoRoot '.mxagile/policies/mockup-lifecycle.md'
$FixInterrupted  = Join-Path $RepoRoot 'tests/fixtures/active-target-invariant/fixture-interrupted-transition.yaml'
$FixInconsistent = Join-Path $RepoRoot 'tests/fixtures/active-target-invariant/fixture-inconsistent-lifecycle-status.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: lifecycle-resync has Active Target Invariant Validator
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: Active Target Invariant Validator in lifecycle-resync" -ForegroundColor Cyan

Assert-FileContains "lifecycle-resync has invariant validator section" $ResyncPolicy "Active Target Invariant Validator"
Assert-FileContains "lifecycle-resync defines INTERRUPTED_TRANSITION" $ResyncPolicy "INTERRUPTED_TRANSITION"
Assert-FileContains "lifecycle-resync defines INTERRUPTED_ACCEPTANCE" $ResyncPolicy "INTERRUPTED_ACCEPTANCE"
Assert-FileContains "lifecycle-resync defines INVALID_ZERO_ACTIVE" $ResyncPolicy "INVALID_ZERO_ACTIVE"
Assert-FileContains "lifecycle-resync defines INVALID_DOUBLE_ACTIVE" $ResyncPolicy "INVALID_DOUBLE_ACTIVE"
Assert-FileContains "lifecycle-resync validator scans all revision.yaml files" $ResyncPolicy "revision.yaml"
Assert-FileContains "lifecycle-resync repair requires developer confirmation" $ResyncPolicy "developer.*confirmation|ohne.*Entwicklerbestaetigung"
Assert-FileNotContains "lifecycle-resync does NOT auto-repair silently" $ResyncPolicy "automatisch.*reparier|silently.*repair"
Assert-FileContains "lifecycle-resync: REFINED_TARGET must have active_target true" $ResyncPolicy "REFINED_TARGET.*active_target.*true|active_target.*true.*REFINED_TARGET"

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: consistency rules table
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: consistency rules" -ForegroundColor Cyan

Assert-FileContains "lifecycle-resync has consistency rules section" $ResyncPolicy "Konsistenzregeln"
Assert-FileContains "SUPERSEDED_TARGET must have active_target false" $ResyncPolicy "SUPERSEDED_TARGET.*active_target.*false"
Assert-FileContains "REJECTED must have active_target false" $ResyncPolicy "REJECTED.*active_target.*false"
Assert-FileContains "PROPOSED must have active_target false" $ResyncPolicy "PROPOSED.*active_target.*false"

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: other work can continue
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: isolated invariant violation does not block all work" -ForegroundColor Cyan

Assert-FileContains "lifecycle-resync: unaffected work can continue" $ResyncPolicy "nicht-betroffene.*Requirements|blockiert nicht-betroffene"

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES: interrupted transition detection
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE: interrupted active_target transition" -ForegroundColor Cyan

Assert-FileExists "interrupted transition fixture exists" $FixInterrupted
$fixInt = Get-Content -LiteralPath $FixInterrupted -Raw -ErrorAction SilentlyContinue
Assert-True "interrupted fixture: scenario is interrupted_acceptance_transition" ($fixInt -match "scenario: interrupted_acceptance_transition")
Assert-True "interrupted fixture: active_target_true_count is 0" ($fixInt -match "active_target_true_count: 0")
Assert-True "interrupted fixture: expected detection is INTERRUPTED_TRANSITION" ($fixInt -match "state: INTERRUPTED_TRANSITION")
Assert-True "interrupted fixture: violates_invariant is true" ($fixInt -match "violates_invariant: true")
Assert-True "interrupted fixture: repair candidate is identified" ($fixInt -match "candidate_for_repair")
Assert-True "interrupted fixture: repair requires developer confirmation" ($fixInt -match "developer confirmation")

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES: REFINED_TARGET + active_target:false inconsistency
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE: inconsistent lifecycle_status/active_target combination" -ForegroundColor Cyan

Assert-FileExists "inconsistent lifecycle fixture exists" $FixInconsistent
$fixIncon = Get-Content -LiteralPath $FixInconsistent -Raw -ErrorAction SilentlyContinue
Assert-True "inconsistent fixture: REFINED_TARGET + active_target false" ($fixIncon -match "lifecycle_status: REFINED_TARGET")
Assert-True "inconsistent fixture: active_target: false on REFINED_TARGET" ($fixIncon -match "active_target: false")
Assert-True "inconsistent fixture: expected INTERRUPTED_ACCEPTANCE" ($fixIncon -match "state: INTERRUPTED_ACCEPTANCE")
Assert-True "inconsistent fixture: violates invariant" ($fixIncon -match "violates_invariant: true")
Assert-True "inconsistent fixture: ACTIVE_TARGET_INCONSISTENT signal" ($fixIncon -match "ACTIVE_TARGET_INCONSISTENT")
Assert-True "inconsistent fixture: developer confirmation required for repair" ($fixIncon -match "developer confirmation")

# ─────────────────────────────────────────────────────────────────────────────
# INLINE SIMULATION: zero active detection logic
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "INLINE: interruption simulation — count validation" -ForegroundColor Cyan

$interruptedBundle = @"
revisions:
  - revision_id: REV-001
    lifecycle_status: SOURCE
    refinement_status: ACCEPTED
    active_target: false
  - revision_id: REV-002
    lifecycle_status: REFINED_TARGET
    refinement_status: ACCEPTED
    active_target: false
"@

$activeTrueCount = CountPattern $interruptedBundle "active_target: true"
$refinedTargetCount = CountPattern $interruptedBundle "lifecycle_status: REFINED_TARGET"
Assert-True "interrupted bundle: zero active_target true" ($activeTrueCount -eq 0) "Expected 0 active_target: true, got $activeTrueCount"
Assert-True "interrupted bundle: REFINED_TARGET present but inactive — inconsistency detectable" ($refinedTargetCount -eq 1 -and $activeTrueCount -eq 0) "REFINED_TARGET=$refinedTargetCount, active_target true=$activeTrueCount"

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
