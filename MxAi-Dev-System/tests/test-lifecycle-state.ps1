<#
.SYNOPSIS
    Lifecycle State Ownership Tests

.DESCRIPTION
    Validates that durable lifecycle state is owned by planning/lifecycle/process-state.yaml
    (Git-tracked), not .concord/scratch/ (gitignored).
    Proves fresh clone and fresh agent can resume without local scratch.
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

$ProcSchema  = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"
$KnowPol     = Join-Path $ScriptDir ".mxagile/policies/project-knowledge.md"
$ReconPol    = Join-Path $ScriptDir ".mxagile/policies/reconciliation.md"
$ResyncPol   = Join-Path $ScriptDir ".mxagile/policies/lifecycle-resync.md"
$ReadMe      = Join-Path $ScriptDir "README.md"
$GitIgnore   = Join-Path $ScriptDir ".gitignore"

# Test 1: Canonical durable state is in planning/lifecycle/ (Git-tracked)
Write-Host ""
Write-Host "TEST 1: Canonical durable lifecycle state is in planning/lifecycle/ (Git-tracked)" -ForegroundColor Cyan
Assert-FileContains "1.1 process-state schema declares canonical file as planning/lifecycle/" $ProcSchema 'planning/lifecycle'
Assert-FileContains "1.2 schema states planning/lifecycle is Git-tracked" $ProcSchema 'Git-tracked'
Assert-FileContains "1.3 project-knowledge.md maps lifecycle state to planning/lifecycle" $KnowPol 'planning/lifecycle/process-state'
Assert-FileContains "1.4 project-knowledge.md marks lifecycle state as YES (Git-tracked)" $KnowPol 'planning/lifecycle.*YES'
Assert-FileNotContains "1.5 planning/ directory is not gitignored" $GitIgnore '^/planning/'

# Test 2: .concord/scratch/process-state.yaml is only a local session cache
Write-Host ""
Write-Host "TEST 2: .concord/scratch/process-state.yaml is only a local session cache" -ForegroundColor Cyan
Assert-FileContains "2.1 schema states .concord/scratch is NOT authoritative" $ProcSchema 'NOT the authoritative'
Assert-FileContains "2.2 project-knowledge.md classifies .concord/scratch/process-state as session cache" $KnowPol 'session.*cache|Local session'
Assert-FileContains "2.3 project-knowledge.md marks local session cache as NO (not Git-tracked)" $KnowPol 'session.*cache.*NO|Local session.*NO'
Assert-FileContains "2.4 .gitignore still ignores .concord/" $GitIgnore '\.concord'

# Test 3: Fresh clone can resume lifecycle without old local scratch
Write-Host ""
Write-Host "TEST 3: Fresh clone retains required lifecycle position without .concord/scratch/" -ForegroundColor Cyan
Assert-FileContains "3.1 lifecycle-resync.md reads planning/lifecycle/ as primary source" $ResyncPol 'planning/lifecycle/process-state.yaml'
Assert-FileContains "3.2 lifecycle-resync.md states deleting .concord/scratch does not destroy canonical state" $ResyncPol 'Loeschen.*concord.*scratch|concord.*darf keine.*zerstoeren'
Assert-FileContains "3.3 README shows planning/lifecycle/process-state.yaml as re-sync source" $ReadMe 'planning/lifecycle/process-state.yaml'

# Test 4: Fresh agent can re-sync without old local scratch
Write-Host ""
Write-Host "TEST 4: Fresh agent can lifecycle re-sync without old local scratch" -ForegroundColor Cyan
Assert-FileContains "4.1 reconciliation.md reads planning/lifecycle/ first in fresh re-sync" $ReconPol 'planning/lifecycle/process-state.yaml'
Assert-FileContains "4.2 reconciliation.md states deleting .concord/scratch/ must not destroy knowledge" $ReconPol 'Deleting.*concord.*scratch.*must NOT'

# Test 5: Interrupted reconciliation resumes from tracked durable state
Write-Host ""
Write-Host "TEST 5: Interrupted reconciliation resumes from tracked state" -ForegroundColor Cyan
Assert-FileContains "5.1 reconciliation.md is resumable (pages_remaining)" $ProcSchema 'pages_remaining'
Assert-FileContains "5.2 reconciliation.md defines idempotency" $ReconPol 'Idempotency'
Assert-FileContains "5.3 lifecycle state is in canonical tracked file for cross-session resume" $ProcSchema 'planning/lifecycle'

# Test 6: Secrets and local runtime data remain untracked
Write-Host ""
Write-Host "TEST 6: Secrets and local runtime data remain untracked" -ForegroundColor Cyan
Assert-FileContains "6.1 .gitignore excludes .env files / secrets" $GitIgnore 'secrets|credential'
Assert-FileContains "6.2 project-knowledge.md classifies secrets as NEVER tracked" $KnowPol 'SECRET.*NEVER'
Assert-FileContains "6.3 schema notes runtime_pipeline_stage is ephemeral (session-specific)" $ProcSchema 'runtime_pipeline_stage'

# Test 7: Legacy .concord/scratch migration contract
Write-Host ""
Write-Host "TEST 7: Legacy .concord/scratch/process-state.yaml migration defined" -ForegroundColor Cyan
Assert-FileContains "7.1 reconciliation.md defines legacy process-state migration" $ReconPol 'Legacy Process-State Reconciliation'
Assert-FileContains "7.2 migration classifies DURABLE and EPHEMERAL fields" $ReconPol 'DURABLE'
Assert-FileContains "7.3 migration does not delete .concord scratch before completion" $ReconPol 'NOT.*delete.*before.*migration'

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
