#Requires -Version 7
# Cross-Contract Consistency Tests — Tier 0
# Detects drift between MxAgile schema definitions and MxMocketeer knowledge file.
# If MxAgile schema adds or changes a field/enum and the knowledge file is not updated,
# this test catches the drift.
#
# Also validates that migration fixtures cover the documented failure modes.
#
# Run from repository root:  pwsh tests/test-cross-contract-consistency.ps1

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

Write-Host "`nCross-Contract Consistency Tests — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# Canonical sources
# ──────────────────────────────────────────────────────────────
$pageSchema    = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/page.schema.json')
$revSchema     = ReadFile (Join-Path $RepoRoot '.mxagile/schemas/revision.schema.json')
$knowledgeFile = ReadFile (Join-Path $RepoRoot 'products/MxMocketeer/knowledge/design-contract.txt')
$systemPrompt  = ReadFile (Join-Path $RepoRoot 'products/MxMocketeer/system-prompt.md')

# ──────────────────────────────────────────────────────────────
# [1] required_action enum parity: schema ↔ knowledge file
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] required_action enum parity: page.schema.json ↔ design-contract.txt"
$requiredActionValues = @(
    'UPDATE_REQUIRED',
    'NEW_IMPLEMENTATION',
    'REMOVE_AS_SUPERSEDED',
    'REGRESSION_REQUIRED',
    'DISCOVERY_REQUIRED',
    'DECISION_REQUIRED',
    'NO_ACTION'
)
foreach ($v in $requiredActionValues) {
    $inSchema      = $pageSchema -match "`"$v`""
    $inKnowledge   = $knowledgeFile -match $v
    Assert ($inSchema)    "page schema defines: $v"
    Assert ($inKnowledge) "knowledge file documents: $v"
}

# ──────────────────────────────────────────────────────────────
# [2] required_action enum parity: revision.schema.json ↔ knowledge file
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] required_action enum parity: revision.schema.json ↔ design-contract.txt"
foreach ($v in $requiredActionValues) {
    $inRevSchema = $revSchema -match "`"$v`""
    Assert ($inRevSchema) "revision schema defines: $v"
}

# Both schemas have same required_action enum (they must stay in sync)
foreach ($v in $requiredActionValues) {
    $inPage = $pageSchema -match "`"$v`""
    $inRev  = $revSchema -match "`"$v`""
    Assert ($inPage -eq $inRev) "required_action enum consistent between page and revision schema: $v"
}

# ──────────────────────────────────────────────────────────────
# [3] Effect typed fields: schema ↔ knowledge file ↔ system-prompt
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Typed effect fields: schema ↔ knowledge file ↔ system-prompt"
$typedFields = @('required_action','downstream_artifacts','affected_roles','affected_screens','source_ids','status')
foreach ($f in $typedFields) {
    $inPageSchema     = $pageSchema -match "`"$f`""
    $inRevSchema      = $revSchema -match "`"$f`""
    $inKnowledge      = $knowledgeFile -match $f
    Assert ($inPageSchema)  "page schema has field: $f"
    Assert ($inRevSchema)   "revision schema has field: $f"
    Assert ($inKnowledge)   "knowledge file documents field: $f"
}

# system-prompt must reference required_action
Assert ($systemPrompt -match 'required_action') 'system-prompt references required_action'

# ──────────────────────────────────────────────────────────────
# [4] lifecycle_status enum: schema ↔ knowledge file
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] lifecycle_status enum parity: schema ↔ knowledge file"
$lifecycleValues = @('SOURCE','REFINED_TARGET','SUPERSEDED_TARGET')
foreach ($v in $lifecycleValues) {
    $inSchema    = $revSchema -match "`"$v`""
    Assert ($inSchema)    "revision schema has lifecycle_status: $v"
}
# Knowledge file must document SOURCE and REFINED_TARGET (primary lifecycle states)
$knowledgeLifecycle = @('SOURCE','REFINED_TARGET')
foreach ($v in $knowledgeLifecycle) {
    $inKnowledge = $knowledgeFile -match $v
    Assert ($inKnowledge) "knowledge file documents lifecycle_status: $v"
}

# ──────────────────────────────────────────────────────────────
# [5] Migration failure modes: knowledge file ↔ migration fixture
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] Migration failure modes: knowledge file ↔ migration fixture"
$migrationFixture = ReadFile (Join-Path $RepoRoot 'tests/fixtures/migration/unsafe-migration.json')
Assert ($migrationFixture -ne '') 'migration unsafe fixture exists'

$failureModes = @('SUCCESS','CONFLICT','AMBIGUOUS_SOURCE','PRESERVATION_FAILURE','INVALID_RESULT')
foreach ($m in $failureModes) {
    $inKnowledge = $knowledgeFile -match $m
    Assert ($inKnowledge) "knowledge file documents failure mode: $m"
}

# Unsafe fixture covers CONFLICT, AMBIGUOUS_SOURCE, PRESERVATION_FAILURE, INVALID_RESULT
$coveredInFixture = @('CONFLICT','AMBIGUOUS_SOURCE','PRESERVATION_FAILURE','INVALID_RESULT')
foreach ($m in $coveredInFixture) {
    Assert ($migrationFixture -match $m) "unsafe migration fixture covers failure mode: $m"
}

# ──────────────────────────────────────────────────────────────
# [6] Valid v1.0 migration input has all required IDs
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] Valid migration fixture — structural integrity"
$validInput = ReadFile (Join-Path $RepoRoot 'tests/fixtures/migration/valid-v1.0-input.json')
$validOutput = ReadFile (Join-Path $RepoRoot 'tests/fixtures/migration/expected-v1.1-output.json')

Assert ($validInput -ne '') 'valid v1.0 input fixture exists'
Assert ($validOutput -ne '') 'expected v1.1 output fixture exists'

$inputObj  = ParseJSON $validInput
$outputObj = ParseJSON $validOutput

Assert ($inputObj -ne $null)  'valid v1.0 input is valid JSON'
Assert ($outputObj -ne $null) 'expected v1.1 output is valid JSON'

if ($inputObj -ne $null -and $outputObj -ne $null) {
    # All IDs from input must be present in output (preservation)
    Assert ($validOutput -match 'REQ-001')      'output preserves REQ-001'
    Assert ($validOutput -match 'DEC-001')      'output preserves DEC-001'
    Assert ($validOutput -match 'ROLE-MANAGER') 'output preserves ROLE-MANAGER'
    Assert ($validOutput -match 'SCREEN-001')   'output preserves SCREEN-001'

    # v1.1 lifecycle defaults
    Assert ($validOutput -match 'lifecycle_status.*SOURCE|SOURCE.*lifecycle_status') 'output sets lifecycle_status: SOURCE'
    Assert ($validOutput -match 'active_target.*true|true.*active_target') 'output sets active_target: true (SOURCE)'
    Assert ($validOutput -match 'refinement_status.*ACCEPTED') 'output sets refinement_status: ACCEPTED'

    # Migration object present
    Assert ($validOutput -match 'migration') 'output has migration object'
    Assert ($validOutput -match 'from_schema_version.*1\.0|1\.0.*from_schema_version') 'output records from_schema_version: 1.0'

    # schema_version NOT changed to 1.1 (requires author confirmation)
    Assert ($validOutput -match '"schema_version": "1.0"') 'output does NOT auto-upgrade schema_version to 1.1'
}

# ──────────────────────────────────────────────────────────────
# [7] Schema v1.1 additions are in both schema and knowledge file
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] Schema v1.1 additions in knowledge file"
$v11Fields = @('lifecycle_status','refinement_status','active_target','change_scope','revision_history','revision_delta','preservation','platform_boundaries','role_coverage')
foreach ($f in $v11Fields) {
    Assert ($knowledgeFile -match $f) "knowledge file documents v1.1 field: $f"
}

# ──────────────────────────────────────────────────────────────
# [8] derived_page false rule: schema ↔ knowledge ↔ system-prompt
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] derived_page: false rule parity"
Assert ($pageSchema -match 'derived_page') 'page schema defines derived_page'
Assert ($knowledgeFile -match 'derived_page.*false|false.*derived_page') 'knowledge file documents derived_page: false rule'
Assert ($systemPrompt -match 'derived_page.*false') 'system-prompt enforces derived_page: false'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all cross-contract consistency checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — cross-contract consistency checks failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
