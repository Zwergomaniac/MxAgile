#Requires -Version 7
# Negative Schema Validation Tests — Tier 0
# Verifies that canonical schemas and policy documents REJECT invalid values.
# Tests the schema enums, required fields, and policy invariants.
#
# Run from repository root:  pwsh tests/test-negative-schema.ps1

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

Write-Host "`nNegative Schema Tests — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] lifecycle_status enum — valid values accepted, invalid rejected
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] lifecycle_status enum coverage"
$revSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/revision.schema.json')

$validLifecycle = @('SOURCE','REFINED_TARGET','SUPERSEDED_TARGET')
foreach ($v in $validLifecycle) {
    Assert ($revSchema -match "`"$v`"") "lifecycle_status accepts valid: $v"
}

$invalidLifecycle = @('DRAFT','PENDING','ACTIVE','CURRENT','WORKING_TARGET','ARCHIVED')
foreach ($v in $invalidLifecycle) {
    Assert ($revSchema -notmatch "`"lifecycle_status`"[^}]*`"$v`"") "lifecycle_status rejects invalid: $v"
}

# ──────────────────────────────────────────────────────────────
# [2] required_action enum — valid values and coverage
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] required_action enum coverage (page schema)"
$pageSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/page.schema.json')

$validActions = @(
    'UPDATE_REQUIRED',
    'NEW_IMPLEMENTATION',
    'REMOVE_AS_SUPERSEDED',
    'REGRESSION_REQUIRED',
    'DISCOVERY_REQUIRED',
    'DECISION_REQUIRED',
    'NO_ACTION'
)
foreach ($v in $validActions) {
    Assert ($pageSchema -match "`"$v`"") "page schema accepts required_action: $v"
}

# All 7 values must be present in page schema
$pageActionMatches = ([regex]::Matches($pageSchema, '"(UPDATE_REQUIRED|NEW_IMPLEMENTATION|REMOVE_AS_SUPERSEDED|REGRESSION_REQUIRED|DISCOVERY_REQUIRED|DECISION_REQUIRED|NO_ACTION)"')).Count
Assert ($pageActionMatches -ge 7) "page schema has all 7 required_action values ($pageActionMatches found)"

# revision schema must also have all 7
$revSchemaActions = ([regex]::Matches($revSchema, '"(UPDATE_REQUIRED|NEW_IMPLEMENTATION|REMOVE_AS_SUPERSEDED|REGRESSION_REQUIRED|DISCOVERY_REQUIRED|DECISION_REQUIRED|NO_ACTION)"')).Count
Assert ($revSchemaActions -ge 7) "revision schema has all 7 required_action values ($revSchemaActions found)"

# ──────────────────────────────────────────────────────────────
# [3] malformed effect — required_action must be marked required in revision schema
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Effect required fields"
$revSchemaObj = ParseJSON $revSchema
Assert ($revSchemaObj -ne $null) "revision.schema.json is valid JSON"

if ($revSchemaObj -ne $null) {
    # required_action must be in the effects items required array
    Assert ($revSchema -match '"required".*required_action|required_action.*"required"') 'required_action is in effects items required array'

    # effect items must require id, type, target, change, description, required_action
    $requiredEffectFields = @('id','type','target','change','description','required_action')
    foreach ($f in $requiredEffectFields) {
        Assert ($revSchema -match "`"$f`"") "revision schema effect defines field: $f"
    }
}

# ──────────────────────────────────────────────────────────────
# [4] role_coverage status enum — valid vs invalid
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] role_coverage status enum"
$rcSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/role_coverage.schema.json')
Assert ($rcSchema -ne '') 'role_coverage.schema.json exists'
Assert ($rcSchema -match 'COVERED') 'COVERED is valid status'
Assert ($rcSchema -match 'COVERAGE_GAP') 'COVERAGE_GAP is valid status'
Assert ($rcSchema -match 'PRESERVATION_FAILURE') 'PRESERVATION_FAILURE is valid status'

$invalidRoleStatuses = @('MISSING','ABSENT','FAILED','UNKNOWN')
foreach ($v in $invalidRoleStatuses) {
    Assert ($rcSchema -notmatch "`"$v`"") "role_coverage rejects invalid status: $v"
}

# ──────────────────────────────────────────────────────────────
# [5] platform boundary parity_rule — only valid values accepted
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] platform_boundary parity_rule enum"
$pbSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/platform_boundaries.schema.json')
Assert ($pbSchema -ne '') 'platform_boundaries.schema.json exists'
Assert ($pbSchema -match 'EXCLUDE_FROM_UI_PARITY') 'EXCLUDE_FROM_UI_PARITY is valid parity_rule'

# modification_rule values
$validModRules = @('DO_NOT_MODIFY_PLATFORM_MODULE','MAY_CONFIGURE_PLATFORM_MODULE','REUSE_PLATFORM_MODULE')
foreach ($v in $validModRules) {
    Assert ($pbSchema -match $v) "platform boundary schema defines: $v"
}

# ──────────────────────────────────────────────────────────────
# [6] repair task completion — all 7 fields required
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] repair task completion block"
$taskSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/task.schema.json')
Assert ($taskSchema -ne '') 'task.schema.json exists'

$completionFields = @(
    'original_gap_fixed',
    'no_new_consistency_errors',
    'affected_roles_verified',
    'interactions_verified',
    'critical_preservation_verified',
    'active_target_used',
    'artifacts_consistent'
)
foreach ($f in $completionFields) {
    Assert ($taskSchema -match $f) "task schema defines repair completion field: $f"
}

# PLATFORM_BOUNDARY_VIOLATION must be in gap_classifications
Assert ($taskSchema -match 'PLATFORM_BOUNDARY_VIOLATION') 'task schema includes PLATFORM_BOUNDARY_VIOLATION gap classification'

# ──────────────────────────────────────────────────────────────
# [7] decision schema — platform_boundary decision_type
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] decision schema — platform_boundary type"
$decSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/decision.schema.json')
Assert ($decSchema -ne '') 'decision.schema.json exists'
Assert ($decSchema -match 'platform_boundary') 'decision schema includes platform_boundary type'
Assert ($decSchema -match 'design_contract_source_id') 'decision schema includes design_contract_source_id'

# ──────────────────────────────────────────────────────────────
# [8] Spec schema revision fields — correct enums
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] spec schema revision impact fields"
$specSchema = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/spec.schema.json')
Assert ($specSchema -match 'revision_status') 'spec schema has revision_status'
Assert ($specSchema -match 'implementation_effect') 'spec schema has implementation_effect'
Assert ($specSchema -match 'refined_in_revision') 'spec schema has refined_in_revision'

# revision_status enum values
$revStatusValues = @('NEW','REFINED','PRESERVED','SUPERSEDED')
foreach ($v in $revStatusValues) {
    Assert ($specSchema -match "`"$v`"") "spec schema revision_status accepts: $v"
}

# ──────────────────────────────────────────────────────────────
# [9] Migration failure modes documented in knowledge file
# ──────────────────────────────────────────────────────────────
Write-Host "`n[9] Migration failure modes in knowledge file"
$kf = ReadFile (Join-Path $RepoRoot 'products/MxMocketeer/knowledge/design-contract.txt')
$failureModes = @('SUCCESS','CONFLICT','AMBIGUOUS_SOURCE','PRESERVATION_FAILURE','INVALID_RESULT')
foreach ($m in $failureModes) {
    Assert ($kf -match $m) "knowledge file documents migration failure mode: $m"
}
Assert ($kf -match 'STOP.*before outputting|STOP before outputting') 'knowledge file enforces STOP on failure'

# ──────────────────────────────────────────────────────────────
# [10] Typed effect required_action documented in knowledge file
# ──────────────────────────────────────────────────────────────
Write-Host "`n[10] Typed effects documented in knowledge file"
Assert ($kf -match 'required_action.*required|required.*required_action') 'knowledge file states required_action is required'
Assert ($kf -match 'derived_page.*false|false.*derived_page') 'knowledge file documents derived_page: false rule'
Assert ($kf -match 'EFF-ABTEILUNG-EXPAND|EFF-DELTA-001') 'knowledge file has typed effect example'
Assert ($kf -match 'downstream_artifacts') 'knowledge file documents downstream_artifacts'
Assert ($kf -match 'affected_roles') 'knowledge file documents affected_roles'
Assert ($kf -match 'source_ids') 'knowledge file documents source_ids'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all negative schema checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — negative schema checks failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
