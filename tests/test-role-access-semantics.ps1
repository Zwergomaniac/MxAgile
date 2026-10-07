<#
.SYNOPSIS
    Role/Access Semantics Tests

.DESCRIPTION
    Verifies that structured access dimensions are defined in the test-contract schema
    and that the vocabulary is organization-neutral.

    P1 REV-014 hardening: structured access semantics for VISIBLE/NAVIGABLE/READ/WRITE/MANAGE.

    Tests:
      - test-contract schema defines access_dimensions
      - access_dimensions vocabulary: VISIBLE, NAVIGABLE, READ, WRITE, MANAGE, PLATFORM_OWNED
      - access_dimensions is optional (backward compatible)
      - intake policy defines STRUCTURED ACCESS SEMANTICS
      - fixtures demonstrate: READ, WRITE, NAVIGABLE without WRITE
      - no real project role names in schema or fixtures
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
    if (-not (Test-Path -LiteralPath $FilePath)) { Assert-True $TestName $false "File not found: $FilePath"; return }
    $content = [System.IO.File]::ReadAllText($FilePath)
    Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
}
function Assert-FileExists {
    param([string]$TestName, [string]$FilePath)
    Assert-True $TestName (Test-Path -LiteralPath $FilePath) "File not found: $FilePath"
}

$TcSchema     = Join-Path $RepoRoot '.mxagile/schemas/test-contract.schema.json'
$IntakePolicy = Join-Path $RepoRoot '.mxagile/policies/design-contract-intake.md'
$FixAccess    = Join-Path $RepoRoot 'tests/fixtures/role-access-semantics/fixture-access-dimensions.yaml'

# ─────────────────────────────────────────────────────────────────────────────
# SCHEMA: access_dimensions defined
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "SCHEMA: access_dimensions in test-contract proof_point" -ForegroundColor Cyan

Assert-FileContains "test-contract schema has access_dimensions" $TcSchema "access_dimensions"
Assert-FileContains "access_dimensions has VISIBLE" $TcSchema '"VISIBLE"'
Assert-FileContains "access_dimensions has NAVIGABLE" $TcSchema '"NAVIGABLE"'
Assert-FileContains "access_dimensions has READ" $TcSchema '"READ"'
Assert-FileContains "access_dimensions has WRITE" $TcSchema '"WRITE"'
Assert-FileContains "access_dimensions has MANAGE" $TcSchema '"MANAGE"'
Assert-FileContains "access_dimensions has PLATFORM_OWNED" $TcSchema '"PLATFORM_OWNED"'
Assert-FileContains "access_dimensions is backward compatible (optional)" $TcSchema "Backward compatible"

# ─────────────────────────────────────────────────────────────────────────────
# POLICY: STRUCTURED ACCESS SEMANTICS in intake policy
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "POLICY: STRUCTURED ACCESS SEMANTICS in design-contract-intake" -ForegroundColor Cyan

Assert-FileContains "intake policy has STRUCTURED ACCESS SEMANTICS section" $IntakePolicy "STRUCTURED ACCESS SEMANTICS"
Assert-FileContains "intake policy defines VISIBLE" $IntakePolicy "VISIBLE"
Assert-FileContains "intake policy defines NAVIGABLE" $IntakePolicy "NAVIGABLE"
Assert-FileContains "intake policy defines PLATFORM_OWNED" $IntakePolicy "PLATFORM_OWNED"
Assert-FileContains "intake policy: access_dimensions is optional" $IntakePolicy "access_dimensions.*OPTIONAL|OPTIONAL.*access_dimensions"
Assert-FileContains "intake policy: organization-neutral" $IntakePolicy "organization-neutral|organisation-neutral"
Assert-FileContains "intake policy: NAVIGABLE without WRITE" $IntakePolicy "NAVIGABLE.*without.*WRITE|NAVIGABLE.*no.*mutation"

# ─────────────────────────────────────────────────────────────────────────────
# PURITY: no real project roles in schema or fixtures
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PURITY: no real project role names in schema" -ForegroundColor Cyan

Assert-FileNotContains "schema does not contain CapTrack roles" $TcSchema "SITE_MANAGER|AppAdmin|CeKo|Eintragung"
Assert-FileNotContains "schema does not contain Mercedes roles" $TcSchema "MB_|Mercedes"

# ─────────────────────────────────────────────────────────────────────────────
# FIXTURE: access dimensions scenarios
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "FIXTURE: access dimensions scenarios" -ForegroundColor Cyan

Assert-FileExists "access dimensions fixture exists" $FixAccess
$fixAccessContent = Get-Content -LiteralPath $FixAccess -Raw -ErrorAction SilentlyContinue
Assert-True "fixture has ROLE-A READ only" ($fixAccessContent -match "access_dimensions: \[READ\]|ROLE-A.*READ")
Assert-True "fixture has ROLE-B READ+WRITE" ($fixAccessContent -match "READ.*WRITE|WRITE.*READ")
Assert-True "fixture has ROLE-C VISIBLE+NAVIGABLE without WRITE" ($fixAccessContent -match "VISIBLE.*NAVIGABLE|NAVIGABLE.*VISIBLE")
Assert-True "fixture: ROLE-C has no WRITE" ($fixAccessContent -match "no mutation authority|zonder.*mutation")
Assert-True "fixture has PLATFORM_OWNED example" ($fixAccessContent -match "PLATFORM_OWNED")
Assert-True "fixture: backward compatibility documented" ($fixAccessContent -match "backward_compatibility")
Assert-True "fixture: organization neutrality documented" ($fixAccessContent -match "organization_neutrality")
Assert-True "fixture uses generic ROLE-A not real project roles" ($fixAccessContent -match "ROLE-A")
Assert-FileNotContains "fixture does not contain real project roles" $FixAccess "SITE_MANAGER|AppAdmin|CeKo|Mercedes"

# ─────────────────────────────────────────────────────────────────────────────
# BACKWARD COMPATIBILITY: existing proof points valid without access_dimensions
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "BACKWARD COMPATIBILITY: access_dimensions optional" -ForegroundColor Cyan

Assert-FileContains "intake policy: absence of access_dimensions does not invalidate" $IntakePolicy "Backward compatible|backward.*compat"

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
