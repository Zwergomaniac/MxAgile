<#
.SYNOPSIS
    Context Epoch Schema & Policy Tests — Layer 1 and Layer 2

.DESCRIPTION
    Validates the MxAgile Context Lifecycle architecture:
    - Layer 1: Schema structure, required fields, evidence states, feature controls
    - Layer 2: Policy content, re-sync contract, rollover safety, backward compatibility

    Scenarios tested:
    A. Schema file exists and is valid JSON
    B. Schema requires schema_version, mission, scope, lifecycle, repository, context
    C. Evidence states VERIFIED/FAILED/UNVERIFIED/STALE/SUPERSEDED are defined
    D. UNVERIFIED semantics: "not equivalent to passed" is explicit in schema
    E. Context pressure states NORMAL/PRESSURE/ROLLOVER_RECOMMENDED/ROLLOVER_REQUIRED defined
    F. No secrets allowed — schema description warns about sensitive values
    G. Feature controls exist in config.yaml with correct defaults (all false)
    H. Feature controls require sequential enablement (auto_rollover after manual_rollover)
    I. Policy defines HOT/WARM/COLD context classes
    J. Policy defines re-synchronization protocol (14 steps)
    K. Policy defines rollover safety conditions
    L. Policy defines backward compatibility (enabled:false preserves prior behavior)
    M. Policy defines rollback procedure
    N. Policy references context-lifecycle docs
    O. Schema supports validity_scope on verified claims
    P. Schema supports stale_if_commit_changes flag
    Q. Valid fixture passes structural checks
    R. Invalid fixture (missing required fields) is structurally detectable
    S. Unknown schema version fixture is structurally detectable
    T. Stale evidence fixture preserves both stale and non-stale claims
    U. Repo-mismatch fixture preserves checkpoint on conflict
    V. UNVERIFIED-preserved fixture carries unverified claims across epochs
    W. config.yaml storage defaults match policy
    X. Schema additionalProperties: false prevents silent field drift
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
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -match $Pattern) "Expected pattern '$Pattern' not found in $FilePath"
    }
}

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

# File paths
$schemaPath       = Join-Path $ScriptDir ".mxagile\schemas\context-epoch.schema.json"
$policyPath       = Join-Path $ScriptDir ".mxagile\policies\context-lifecycle.md"
$configPath       = Join-Path $ScriptDir ".mxagile\config.yaml"
$fixturesDir      = Join-Path $TestsDir "fixtures\context-lifecycle"
$validFixture     = Join-Path $fixturesDir "checkpoint-valid.yaml"
$invalidFixture   = Join-Path $fixturesDir "checkpoint-invalid-missing-required.yaml"
$unknownVerFixture= Join-Path $fixturesDir "checkpoint-unknown-version.yaml"
$staleFixture     = Join-Path $fixturesDir "checkpoint-stale-evidence.yaml"
$mismatchFixture  = Join-Path $fixturesDir "checkpoint-repo-mismatch.yaml"
$unverifiedFixture= Join-Path $fixturesDir "checkpoint-unverified-preserved.yaml"

Write-Host ""
Write-Host "=== Context Epoch Schema & Policy Tests ===" -ForegroundColor Cyan
Write-Host ""

# ─── A. Schema file exists and is valid JSON ──────────────────────────────────
Write-Host "--- Layer 1: Schema Structure ---" -ForegroundColor Yellow

Assert-True "A: Schema file exists" (Test-Path -LiteralPath $schemaPath) "Missing: $schemaPath"

$schemaJson = $null
if (Test-Path -LiteralPath $schemaPath) {
    try {
        $schemaJson = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        Assert-True "A: Schema is valid JSON" $true ""
    } catch {
        Assert-True "A: Schema is valid JSON" $false "JSON parse error: $_"
    }
}

# ─── B. Required fields ────────────────────────────────────────────────────────
Assert-FileContains "B: schema_version required" $schemaPath '"schema_version"'
Assert-FileContains "B: mission required" $schemaPath '"mission"'
Assert-FileContains "B: scope required" $schemaPath '"scope"'
Assert-FileContains "B: lifecycle required" $schemaPath '"lifecycle"'
Assert-FileContains "B: repository required" $schemaPath '"repository"'
Assert-FileContains "B: context required" $schemaPath '"context"'

# ─── C. Evidence states ────────────────────────────────────────────────────────
Assert-FileContains "C: VERIFIED state defined" $schemaPath '"VERIFIED"'
Assert-FileContains "C: FAILED state defined" $schemaPath '"FAILED"'
Assert-FileContains "C: UNVERIFIED state defined" $schemaPath '"UNVERIFIED"'
Assert-FileContains "C: STALE state defined" $schemaPath '"STALE"'
Assert-FileContains "C: SUPERSEDED state defined" $schemaPath '"SUPERSEDED"'

# ─── D. UNVERIFIED semantics ──────────────────────────────────────────────────
Assert-FileContains "D: UNVERIFIED != passed" $schemaPath 'UNVERIFIED.*NOT.*equivalent'

# ─── E. Pressure states ───────────────────────────────────────────────────────
Assert-FileContains "E: NORMAL pressure state" $schemaPath '"NORMAL"'
Assert-FileContains "E: PRESSURE state" $schemaPath '"PRESSURE"'
Assert-FileContains "E: ROLLOVER_RECOMMENDED state" $schemaPath '"ROLLOVER_RECOMMENDED"'
Assert-FileContains "E: ROLLOVER_REQUIRED state" $schemaPath '"ROLLOVER_REQUIRED"'

# ─── F. No secrets ─────────────────────────────────────────────────────────────
Assert-FileContains "F: Schema warns about secrets" $schemaPath 'credentials|sensitive|secret|NEVER store'

# ─── G. Feature controls in config ────────────────────────────────────────────
Assert-FileContains "G: context_lifecycle section in config" $configPath 'context_lifecycle:'
Assert-FileContains "G: enabled default false" $configPath 'enabled: false'
Assert-FileContains "G: checkpoint_resume default false" $configPath 'checkpoint_resume: false'
Assert-FileContains "G: manual_rollover default false" $configPath 'manual_rollover: false'
Assert-FileContains "G: pressure_recommendations default false" $configPath 'pressure_recommendations: false'
Assert-FileContains "G: auto_rollover default false" $configPath 'auto_rollover: false'

# ─── H. Sequential enablement guidance ────────────────────────────────────────
Assert-FileContains "H: Auto rollover requires manual_rollover first" $configPath 'manual_rollover.*proven|proven.*manual_rollover|auto_rollover.*after.*manual_rollover|checkpoint_resume.*manual_rollover.*auto_rollover'

# ─── I. HOT/WARM/COLD context classes ─────────────────────────────────────────
Write-Host ""
Write-Host "--- Layer 2: Policy Content ---" -ForegroundColor Yellow

Assert-FileContains "I: HOT CONTEXT defined" $policyPath 'HOT CONTEXT'
Assert-FileContains "I: WARM CONTEXT defined" $policyPath 'WARM CONTEXT'
Assert-FileContains "I: COLD EVIDENCE defined" $policyPath 'COLD'

# ─── J. Re-synchronization protocol ──────────────────────────────────────────
Assert-FileContains "J: Re-sync step: load durable contract" $policyPath 'Resume Contract laden|durable.*resume.*contract'
Assert-FileContains "J: Re-sync step: validate schema" $policyPath 'Schema.*Version validieren|schema.*validat'
Assert-FileContains "J: Re-sync step: verify repository identity" $policyPath 'Repository-Identit.t|repository.*identity'
Assert-FileContains "J: Re-sync step: mark stale" $policyPath 'STALE'
Assert-FileContains "J: Re-sync step: preserve FAILED and UNVERIFIED" $policyPath 'FAILED.*UNVERIFIED.*bewahren|UNVERIFIED.*FAILED.*bewahren|preserve.*FAILED|preserve.*UNVERIFIED'

# ─── K. Rollover safety conditions ───────────────────────────────────────────
Assert-FileContains "K: Rollover requires valid checkpoint" $policyPath 'schema-validiert.*Checkpoint|gültig.*Checkpoint|valid.*checkpoint'
Assert-FileContains "K: No tool call in flight" $policyPath 'Tool-Aufruf|tool.*call.*flight|kein kritisch'
Assert-FileContains "K: Rollover at safe boundary" $policyPath 'sichere.*Grenze|safe.*boundary'

# ─── L. Backward compatibility ────────────────────────────────────────────────
Assert-FileContains "L: enabled:false preserves prior behavior" $policyPath 'enabled.*false|enabled: false'
Assert-FileContains "L: No immediate migration required" $policyPath 'nicht.*sofort.*migrieren|keine.*Migration|not.*require.*migrat'

# ─── M. Rollback procedure ────────────────────────────────────────────────────
Assert-FileContains "M: Rollback section exists" $policyPath 'Rollback'
Assert-FileContains "M: context-epoch.yaml preserved on rollback" $policyPath 'context-epoch.yaml.*nicht löschen|context-epoch.yaml.*aufbewahren|preserve.*context-epoch'

# ─── N. Policy references docs ────────────────────────────────────────────────
Assert-FileContains "N: Policy references docs/context-lifecycle.md" $policyPath 'docs/context-lifecycle'

# ─── O. validity_scope field ──────────────────────────────────────────────────
Assert-FileContains "O: validity_scope in schema" $schemaPath '"validity_scope"'

# ─── P. stale_if_commit_changes field ────────────────────────────────────────
Assert-FileContains "P: stale_if_commit_changes in schema" $schemaPath '"stale_if_commit_changes"'

# ─── Q. Valid fixture structural check ───────────────────────────────────────
Write-Host ""
Write-Host "--- Layer 1: Fixture Structural Checks ---" -ForegroundColor Yellow

Assert-FileContains "Q: Valid fixture has schema_version 1.0" $validFixture 'schema_version.*"1\.0"'
Assert-FileContains "Q: Valid fixture has mission" $validFixture 'mission:'
Assert-FileContains "Q: Valid fixture has context epoch" $validFixture 'epoch_id:.*EPOCH-'
Assert-FileContains "Q: Valid fixture has pressure_state NORMAL" $validFixture 'pressure_state: NORMAL'

# ─── R. Invalid fixture detectable ────────────────────────────────────────────
Assert-FileNotContains "R: Invalid fixture lacks schema_version" $invalidFixture 'schema_version:'
Assert-FileNotContains "R: Invalid fixture lacks scope" $invalidFixture '^scope:'
Assert-FileNotContains "R: Invalid fixture lacks context" $invalidFixture '^context:'

# ─── S. Unknown version fixture detectable ────────────────────────────────────
Assert-FileContains "S: Unknown-version fixture has non-1.0 version" $unknownVerFixture 'schema_version:.*"99\.'

# ─── T. Stale evidence fixture ────────────────────────────────────────────────
Assert-FileContains "T: Stale fixture has stale_if_commit_changes: true" $staleFixture 'stale_if_commit_changes: true'
Assert-FileContains "T: Stale fixture has stale_if_commit_changes: false" $staleFixture 'stale_if_commit_changes: false'
Assert-FileContains "T: Stale fixture notes different commits" $staleFixture 'abc1234'

# ─── U. Repo-mismatch fixture ─────────────────────────────────────────────────
Assert-FileContains "U: Mismatch fixture has different branch" $mismatchFixture 'feature/context-lifecycle'
Assert-FileContains "U: Mismatch fixture documents expected behavior" $mismatchFixture 'conflict.*branch.*diverged|branch_diverged'

# ─── V. UNVERIFIED preserved fixture ─────────────────────────────────────────
Assert-FileContains "V: UNVERIFIED fixture carries EPOCH-002" $unverifiedFixture 'EPOCH-002'
Assert-FileContains "V: UNVERIFIED claims present" $unverifiedFixture 'evidence_state: UNVERIFIED'
Assert-FileContains "V: UNVERIFIED blocking claim present" $unverifiedFixture 'blocking_or_non_blocking: blocking'
Assert-FileContains "V: Acceptance gate blocked by UNVERIFIED" $unverifiedFixture 'current_state: blocked'

# ─── W. Storage config defaults match policy ─────────────────────────────────
Assert-FileContains "W: Config storage canonical_dir" $configPath 'planning/lifecycle'
Assert-FileContains "W: Config storage epoch_filename" $configPath 'context-epoch.yaml'
Assert-FileContains "W: Config storage scratch_dir" $configPath '\.concord/scratch'

# ─── X. additionalProperties: false ──────────────────────────────────────────
Assert-FileContains "X: Schema uses additionalProperties false" $schemaPath '"additionalProperties".*false'

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  PASS: $PassCount" -ForegroundColor Green
Write-Host "  FAIL: $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { 'Red' } else { 'Green' })

if ($FailDetails.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "  $detail" -ForegroundColor Red
    }
}

if ($FailCount -gt 0) {
    exit 1
}
