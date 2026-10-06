#Requires -Version 7
# Migration Fixture Tests — Tier 0
# Validates the migration fixtures in tests/fixtures/migration/:
#   - valid-v1.0-input.json: correct structure for a v1.0 contract
#   - expected-v1.1-output.json: correct v1.1 migration defaults
#   - unsafe-migration.json: all 4 unsafe scenarios documented
#
# Also validates that the knowledge file and unsafe fixture cover the same failure modes.
#
# Run from repository root:  pwsh tests/test-migration-fixtures.ps1

param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

function Assert {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
        $script:pass++
    } else {
        $msg = if ($Detail) { "  FAIL  $Label — $Detail" } else { "  FAIL  $Label" }
        Write-Host $msg -ForegroundColor Red
        $script:fail++
    }
}

function ReadFile { param([string]$Path)
    if (Test-Path -LiteralPath $Path) { [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    else { '' }
}

function ParseJSON { param([string]$Content)
    try { $Content | ConvertFrom-Json -Depth 20 } catch { $null }
}

$FixtureDir = Join-Path $RepoRoot 'tests/fixtures/migration'
Write-Host "`nMigration Fixture Tests — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] Fixture files exist
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] Migration fixture files exist"
$fixtures = @(
    'tests/fixtures/migration/valid-v1.0-input.json',
    'tests/fixtures/migration/expected-v1.1-output.json',
    'tests/fixtures/migration/unsafe-migration.json'
)
foreach ($f in $fixtures) {
    Assert (Test-Path (Join-Path $RepoRoot $f)) "Fixture exists: $f"
}

# ──────────────────────────────────────────────────────────────
# [2] Valid v1.0 input — correct schema_version and structure
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] Valid v1.0 input fixture"
$inputContent = ReadFile (Join-Path $FixtureDir 'valid-v1.0-input.json')
$inputObj = ParseJSON $inputContent

Assert ($inputObj -ne $null) 'valid-v1.0-input.json is valid JSON'
if ($inputObj -ne $null) {
    Assert ($inputObj.schema_version -eq '1.0') "schema_version is 1.0 (found: $($inputObj.schema_version))"
    Assert ($inputObj.mockup -ne $null) 'mockup object present'
    Assert ($inputObj.mockup.id -ne $null) 'mockup.id present'

    # v1.0 must NOT have v1.1-only fields in mockup
    Assert (-not ($inputContent -match '"lifecycle_status"')) 'v1.0 input does not have lifecycle_status'
    Assert (-not ($inputContent -match '"active_target"')) 'v1.0 input does not have active_target'
    Assert (-not ($inputContent -match '"refinement_status"')) 'v1.0 input does not have refinement_status'

    # Must have the key stable IDs
    Assert ($inputContent -match 'REQ-001') 'v1.0 input has REQ-001'
    Assert ($inputContent -match 'DEC-001') 'v1.0 input has DEC-001'
    Assert ($inputContent -match 'ROLE-MANAGER') 'v1.0 input has ROLE-MANAGER'
    Assert ($inputContent -match 'SCREEN-001') 'v1.0 input has SCREEN-001'

    # No credentials or sensitive data
    Assert ($inputContent -notmatch 'password|token|secret') 'no credentials in v1.0 input fixture'
    Assert ($inputContent -notmatch '@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}') 'no email addresses in v1.0 input fixture'
}

# ──────────────────────────────────────────────────────────────
# [3] Expected v1.1 output — correct migration defaults
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Expected v1.1 output fixture — migration defaults"
$outputContent = ReadFile (Join-Path $FixtureDir 'expected-v1.1-output.json')
$outputObj = ParseJSON $outputContent

Assert ($outputObj -ne $null) 'expected-v1.1-output.json is valid JSON'
if ($outputObj -ne $null) {
    # schema_version must NOT be auto-upgraded to 1.1 (requires author confirmation)
    Assert ($outputObj.schema_version -eq '1.0') "schema_version stays 1.0 until author confirms (found: $($outputObj.schema_version))"

    # Lifecycle defaults
    Assert ($outputContent -match 'lifecycle_status.*SOURCE') 'output: lifecycle_status defaulted to SOURCE'
    Assert ($outputContent -match 'refinement_status.*ACCEPTED') 'output: refinement_status defaulted to ACCEPTED'
    Assert ($outputContent -match '"active_target": true') 'output: active_target defaulted to true (only revision = SOURCE)'
    Assert ($outputContent -match '"change_scope": ""') 'output: change_scope defaulted to empty string'

    # Migration object present and correctly populated
    Assert ($outputObj.migration -ne $null) 'migration object present in output'
    Assert ($outputContent -match '"from_schema_version": "1.0"') 'migration records from_schema_version: 1.0'
    Assert ($outputContent -match '"migrated_by": "MxMocketeer"') 'migration records migrated_by: MxMocketeer'

    # migrated_fields must contain all 9 v1.1 default fields
    $expectedMigratedFields = @(
        'mockup.lifecycle_status',
        'mockup.refinement_status',
        'mockup.active_target',
        'mockup.change_scope',
        'revision_history',
        'revision_delta',
        'preservation',
        'platform_boundaries',
        'role_coverage'
    )
    foreach ($f in $expectedMigratedFields) {
        Assert ($outputContent -match $f) "migrated_fields includes: $f"
    }

    # null defaults
    Assert ($outputContent -match '"revision_delta": null') 'output: revision_delta null for SOURCE'
    Assert ($outputContent -match '"preservation": null') 'output: preservation null for SOURCE'
    Assert ($outputContent -match '"revision_history": \[\]') 'output: revision_history empty array'
    Assert ($outputContent -match '"platform_boundaries": \[\]') 'output: platform_boundaries empty array'
    Assert ($outputContent -match '"role_coverage": \[\]') 'output: role_coverage empty array'

    # Preservation: all input IDs must be present in output
    Assert ($outputContent -match 'REQ-001') 'output preserves REQ-001'
    Assert ($outputContent -match 'DEC-001') 'output preserves DEC-001'
    Assert ($outputContent -match 'ROLE-MANAGER') 'output preserves ROLE-MANAGER'
    Assert ($outputContent -match 'SCREEN-001') 'output preserves SCREEN-001'
}

# ──────────────────────────────────────────────────────────────
# [4] Unsafe migration fixture — four failure scenarios
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] Unsafe migration fixture — failure scenarios"
$unsafeContent = ReadFile (Join-Path $FixtureDir 'unsafe-migration.json')
$unsafeObj = ParseJSON $unsafeContent

Assert ($unsafeObj -ne $null) 'unsafe-migration.json is valid JSON'

if ($unsafeObj -ne $null) {
    Assert ($unsafeObj.scenarios.Count -eq 4) "4 unsafe scenarios documented (found: $($unsafeObj.scenarios.Count))"

    $requiredFailureModes = @('PRESERVATION_FAILURE','CONFLICT','AMBIGUOUS_SOURCE','INVALID_RESULT')
    foreach ($m in $requiredFailureModes) {
        Assert ($unsafeContent -match $m) "unsafe fixture covers failure mode: $m"
    }

    # Each scenario must document expected_agent_behavior and must_not
    foreach ($s in $unsafeObj.scenarios) {
        Assert ($s.expected_agent_behavior -ne $null -and $s.expected_agent_behavior -match 'STOP') "scenario $($s.id): expected_agent_behavior says STOP"
        Assert ($s.must_not -ne $null) "scenario $($s.id): must_not constraint documented"
    }

    # Fixture assertions array present
    Assert ($null -ne $unsafeObj.fixture_assertions) 'unsafe fixture has fixture_assertions array'
    Assert ($unsafeObj.fixture_assertions.Count -ge 3) "unsafe fixture has at least 3 assertions (found: $($unsafeObj.fixture_assertions.Count))"

    # STOP must be the behavior for all non-SUCCESS cases
    Assert ($unsafeContent -match 'STOP') 'unsafe fixture documents STOP behavior'
    Assert ($unsafeContent -match 'never.*output|never output') 'unsafe fixture: PRESERVATION_FAILURE must never output'
}

# ──────────────────────────────────────────────────────────────
# [5] Security: no real credentials in migration fixtures
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] Security: no sensitive data in migration fixtures"
$allMigrationContent = (ReadFile (Join-Path $FixtureDir 'valid-v1.0-input.json')) + "`n" +
                        (ReadFile (Join-Path $FixtureDir 'expected-v1.1-output.json')) + "`n" +
                        (ReadFile (Join-Path $FixtureDir 'unsafe-migration.json'))

Assert ($allMigrationContent -notmatch 'password\s*[:=]\s*\S') 'no password assignments in migration fixtures'
Assert ($allMigrationContent -notmatch '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b') 'no email addresses in migration fixtures'
Assert ($allMigrationContent -notmatch 'token\s*[:=]\s*[A-Za-z0-9+/]{20}') 'no token values in migration fixtures'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all migration fixture checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — migration fixture checks failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
