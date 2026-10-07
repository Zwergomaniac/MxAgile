<#
.SYNOPSIS
    AC Faithfulness Tests — Source-AC Traceability Contract

.DESCRIPTION
    Verifies that the source-traceability contract for Design Contract AC coverage
    is correctly defined and detectable.

    P0 REV-014 hardening: prevents silent semantic loss during requirement refinement.

    Tests:
      - Requirement schema has source_ac_coverage field
      - source_ac_coverage disposition enum is correct
      - design-contract-intake policy has AC COVERAGE COMPLETENESS section
      - refinement-agent enforces AC coverage check
      - complete coverage fixture passes deterministic validation
      - missing coverage fixture triggers TRACEABILITY_ERROR
      - backward compatibility: requirements without source_ac_coverage remain valid
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
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$ReqSchema    = Join-Path $RepoRoot '.mxagile/schemas/requirement.schema.json'
$IntakePolicy = Join-Path $RepoRoot '.mxagile/policies/design-contract-intake.md'
$RefAgent     = Join-Path $RepoRoot '.mxagile/agents/refinement-agent.md'
$FixComplete  = Join-Path $RepoRoot 'tests/fixtures/ac-faithfulness/fixture-complete-coverage.yaml'
$FixMissing   = Join-Path $RepoRoot 'tests/fixtures/ac-faithfulness/fixture-missing-coverage.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# SCHEMA: source_ac_coverage field defined
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCHEMA: source_ac_coverage in requirement schema" -ForegroundColor Cyan

Assert-FileExists "requirement schema exists" $ReqSchema
Assert-FileContains "schema defines source_ac_coverage" $ReqSchema "source_ac_coverage"
Assert-FileContains "schema defines disposition field" $ReqSchema '"disposition"'
Assert-FileContains "schema defines PRESERVED disposition" $ReqSchema "PRESERVED"
Assert-FileContains "schema defines REFINED disposition" $ReqSchema "REFINED"
Assert-FileContains "schema defines MERGED disposition" $ReqSchema "MERGED"
Assert-FileContains "schema defines SPLIT disposition" $ReqSchema "SPLIT"
Assert-FileContains "schema defines NOT_APPLICABLE disposition" $ReqSchema "NOT_APPLICABLE"
Assert-FileContains "schema defines exclusion_reason field" $ReqSchema "exclusion_reason"
Assert-FileContains "schema defines canonical_ac_ids field" $ReqSchema "canonical_ac_ids"
Assert-FileContains "schema source_ac_coverage is optional (array, not required)" $ReqSchema "source_ac_coverage"
Assert-FileContains "schema defines source_ac_ref on AC items" $ReqSchema "source_ac_ref"

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: AC COVERAGE COMPLETENESS section in design-contract-intake
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: AC COVERAGE COMPLETENESS" -ForegroundColor Cyan

Assert-FileContains "intake policy has AC COVERAGE COMPLETENESS section" $IntakePolicy "AC COVERAGE COMPLETENESS"
Assert-FileContains "intake policy defines PRESERVED disposition" $IntakePolicy "PRESERVED.*canonical AC|PRESERVED.*no significant"
Assert-FileContains "intake policy defines NOT_APPLICABLE requires exclusion_reason" $IntakePolicy "exclusion_reason.*required|exclusion_reason is required"
Assert-FileContains "intake policy: count-based check is insufficient" $IntakePolicy "equal.*counts.*NOT.*guarantee|counts do NOT guarantee"
Assert-FileContains "intake policy: missing coverage is TRACEABILITY_ERROR" $IntakePolicy "TRACEABILITY_ERROR"
Assert-FileContains "intake policy: backward compatibility for legacy requirements" $IntakePolicy "source: migrated.*exempt|exempt.*migrated"
Assert-FileContains "intake validation check 9: AC coverage completeness" $IntakePolicy "source_ac_coverage.*TRACEABILITY_ERROR"

# ─────────────────────────────────────────────────────────────────────────────
# AGENT: refinement-agent enforces AC coverage
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "AGENT: refinement-agent AC coverage enforcement" -ForegroundColor Cyan

Assert-FileContains "refinement-agent has AC coverage check" $RefAgent "AC-Quell-Traceability|AC COVERAGE"
Assert-FileContains "refinement-agent checks TRACEABILITY_ERROR" $RefAgent "TRACEABILITY_ERROR"
Assert-FileContains "refinement-agent requires exclusion_reason for NOT_APPLICABLE" $RefAgent "exclusion_reason"
Assert-FileContains "refinement-agent: count equality is not sufficient" $RefAgent "kein Beweis.*semantische|Anzahl.*kein"

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES: complete coverage passes
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE: complete AC coverage" -ForegroundColor Cyan

Assert-FileExists "complete coverage fixture exists" $FixComplete
$fixComplete = Get-Content -LiteralPath $FixComplete -Raw -ErrorAction SilentlyContinue
Assert-True "complete fixture: expected_validation is PASS" ($fixComplete -match "expected_validation: PASS")
Assert-True "complete fixture: all dispositions covered" ($fixComplete -match "disposition: PRESERVED")
Assert-True "complete fixture: SPLIT disposition present" ($fixComplete -match "disposition: SPLIT")
Assert-True "complete fixture: MERGED disposition present" ($fixComplete -match "disposition: MERGED")
Assert-True "complete fixture: canonical_ac_ids populated" ($fixComplete -match "canonical_ac_ids: \[")

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURES: missing coverage triggers TRACEABILITY_ERROR
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE: missing AC coverage triggers TRACEABILITY_ERROR" -ForegroundColor Cyan

Assert-FileExists "missing coverage fixture exists" $FixMissing
$fixMissing = Get-Content -LiteralPath $FixMissing -Raw -ErrorAction SilentlyContinue
Assert-True "missing fixture: expected_validation is FAIL" ($fixMissing -match "expected_validation: FAIL")
Assert-True "missing fixture: TRACEABILITY_ERROR recorded" ($fixMissing -match "TRACEABILITY_ERROR")
Assert-True "missing fixture: count-based detection noted" ($fixMissing -match "count.*detection|detection.*method|count.*4.*3")
Assert-True "missing fixture: REV-014 regression pattern documented" ($fixMissing -match "REV-014")
Assert-True "missing fixture: silent drop is the pattern" ($fixMissing -match "silently dropped|silent")

# ─────────────────────────────────────────────────────────────────────────────
# BACKWARD COMPATIBILITY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "BACKWARD COMPATIBILITY" -ForegroundColor Cyan

Assert-FileContains "schema: source_ac_coverage is not in required array" $ReqSchema '"required": \["ID", "title", "description"\]'
Assert-FileContains "intake policy: legacy requirements exempt" $IntakePolicy "migrated.*exempt|legacy.*exempt"

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
