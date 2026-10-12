<#
.SYNOPSIS
    Context Lifecycle - Layer 3: Five MxAgile Golden Scenarios

.DESCRIPTION
    Validates that the context-lifecycle architecture correctly handles the
    five framework-level golden scenarios. All tests are static fixture checks
    against pre-defined YAML assertion files.

    GOLD-CTX-01: Scope and parity - wrong-role result must not be accepted
    GOLD-CTX-02: Studio Pro vs. headless - SP login != headless startup proof
    GOLD-CTX-03: Modeled security - evidence must remain evidence-based across epochs
    GOLD-CTX-04: Missing production integration - local fixture != productive API
    GOLD-CTX-05: Interrupt and resume - side request handled; no false assumptions
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

$fixturesDir = Join-Path $TestsDir "fixtures\context-lifecycle"
$policyPath  = Join-Path $ScriptDir ".mxagile\policies\context-lifecycle.md"
$schemaPath  = Join-Path $ScriptDir ".mxagile\schemas\context-epoch.schema.json"

$gold01 = Join-Path $fixturesDir "gold-01-scope-parity.yaml"
$gold02 = Join-Path $fixturesDir "gold-02-studio-vs-headless.yaml"
$gold03 = Join-Path $fixturesDir "gold-03-modeled-security.yaml"
$gold04 = Join-Path $fixturesDir "gold-04-missing-production.yaml"
$gold05 = Join-Path $fixturesDir "gold-05-interrupt-resume.yaml"

Write-Host ""
Write-Host "=== Context Lifecycle - Five Golden Scenarios ===" -ForegroundColor Cyan
Write-Host ""

# --- GOLD-CTX-01: Scope and Parity ---
Write-Host "--- GOLD-CTX-01: Scope and Parity ---" -ForegroundColor Yellow

Assert-True "GOLD-01: Fixture exists" (Test-Path -LiteralPath $gold01) "Missing: $gold01"
Assert-FileContains "GOLD-01.1: Wrong-role reclassified FAILED" $gold01 'GOLD-01\.1'
Assert-FileContains "GOLD-01.2: Invalid evidence preserved historically" $gold01 'GOLD-01\.2'
Assert-FileContains "GOLD-01.3: No next-requirement start before conflict resolved" $gold01 'GOLD-01\.3'
Assert-FileContains "GOLD-01.4: Scope mismatch in failed_claim" $gold01 'GOLD-01\.4'

# Policy must address scope-parity constraint
Assert-FileContains "GOLD-01: Policy covers evidence_state for wrong scope" $policyPath 'evidence_state|VERIFIED|scope|validity'

# Schema must carry validity_scope
Assert-FileContains "GOLD-01: Schema has validity_scope" $schemaPath '"validity_scope"'

# --- GOLD-CTX-02: Studio Pro vs. Headless Runtime ---
Write-Host ""
Write-Host "--- GOLD-CTX-02: Studio Pro vs. Headless Runtime ---" -ForegroundColor Yellow

Assert-True "GOLD-02: Fixture exists" (Test-Path -LiteralPath $gold02) "Missing: $gold02"
Assert-FileContains "GOLD-02.1: SP login not promoted to headless" $gold02 'GOLD-02\.1'
Assert-FileContains "GOLD-02.2: Headless path is UNVERIFIED" $gold02 'GOLD-02\.2'
Assert-FileContains "GOLD-02.3: validity_scope explicitly names Studio Pro" $gold02 'GOLD-02\.3'
Assert-FileContains "GOLD-02.4: acceptance_gate cannot pass on SP evidence alone" $gold02 'GOLD-02\.4'

# Policy must state COLD evidence is not summarized or promoted
Assert-FileContains "GOLD-02: Schema has validity_scope guard" $schemaPath '"validity_scope"'
Assert-FileContains "GOLD-02: UNVERIFIED != VERIFIED explicit" $schemaPath 'UNVERIFIED.*NOT.*equivalent|unavailable.*never.*equivalent'

# --- GOLD-CTX-03: Modeled Security ---
Write-Host ""
Write-Host "--- GOLD-CTX-03: Modeled Security ---" -ForegroundColor Yellow

Assert-True "GOLD-03: Fixture exists" (Test-Path -LiteralPath $gold03) "Missing: $gold03"
Assert-FileContains "GOLD-03.1: Security claim becomes STALE on commit change" $gold03 'GOLD-03\.1'
Assert-FileContains "GOLD-03.2: STALE claim must be re-evaluated" $gold03 'GOLD-03\.2'
Assert-FileContains "GOLD-03.3: Non-affected claims remain VERIFIED" $gold03 'GOLD-03\.3'
Assert-FileContains "GOLD-03.4: STALE transition recorded in resume contract" $gold03 'GOLD-03\.4'

# Schema must have stale_if_commit_changes
Assert-FileContains "GOLD-03: Schema has stale_if_commit_changes" $schemaPath '"stale_if_commit_changes"'

# Policy must describe staleness trigger on commit change
Assert-FileContains "GOLD-03: Policy covers STALE on commit change" $policyPath 'STALE|stale_if_commit_changes|Commit-Hash|changed.*commit'

# --- GOLD-CTX-04: Missing Production Integration ---
Write-Host ""
Write-Host "--- GOLD-CTX-04: Missing Production Integration ---" -ForegroundColor Yellow

Assert-True "GOLD-04: Fixture exists" (Test-Path -LiteralPath $gold04) "Missing: $gold04"
Assert-FileContains "GOLD-04.1: validity_scope states LOCAL FIXTURE ONLY" $gold04 'GOLD-04\.1'
Assert-FileContains "GOLD-04.2: acceptance_gate cannot pass on fixture evidence" $gold04 'GOLD-04\.2'
Assert-FileContains "GOLD-04.3: Productive API is UNVERIFIED" $gold04 'GOLD-04\.3'
Assert-FileContains "GOLD-04.4: Local fixture not reclassified on rollover" $gold04 'GOLD-04\.4'

# Policy: rollover must not promote/demote evidence
Assert-FileContains "GOLD-04: Policy forbids evidence promotion on rollover" $policyPath 'nie.*aufgewertet|aufgewertet|not.*promote|never.*promote|rollover.*muss.*nicht'

# Schema: unverified must have reason field
Assert-FileContains "GOLD-04: Schema unverified_claim has reason" $schemaPath '"reason"'
Assert-FileContains "GOLD-04: evidence_unavailable reason defined" $schemaPath '"evidence_unavailable"'

# --- GOLD-CTX-05: Interrupt and Resume ---
Write-Host ""
Write-Host "--- GOLD-CTX-05: Interrupt and Resume ---" -ForegroundColor Yellow

Assert-True "GOLD-05: Fixture exists" (Test-Path -LiteralPath $gold05) "Missing: $gold05"
Assert-FileContains "GOLD-05.1: Phase remains implementing after OBSERVATION" $gold05 'GOLD-05\.1'
Assert-FileContains "GOLD-05.2: Resume at W01-03, not restart" $gold05 'GOLD-05\.2'
Assert-FileContains "GOLD-05.3: Gate not triggered by OBSERVATION" $gold05 'GOLD-05\.3'
Assert-FileContains "GOLD-05.4: Re-sync before continuing" $gold05 'GOLD-05\.4'
Assert-FileContains "GOLD-05.5: OBSERVATION not recorded as user_override" $gold05 'GOLD-05\.5'
Assert-FileContains "GOLD-05.6: Epoch unchanged after OBSERVATION" $gold05 'GOLD-05\.6'

# Policy: OBSERVATION class defined
Assert-FileContains "GOLD-05: Policy defines OBSERVATION interrupt class" $policyPath 'OBSERVATION'
Assert-FileContains "GOLD-05: Policy states phase unchanged after OBSERVATION" $policyPath 'Lifecycle-Phase.*unver|phase.*unchanged|UNVERAENDERT|unverandert'

# Policy: re-sync required before resume
Assert-FileContains "GOLD-05: Policy requires re-sync before resume" $policyPath 'Re-Sync.*vor.*Fortfahren|re-synchronisier.*bevor|resync.*before.*continu'

# ---
Write-Host ""
Write-Host "=== Golden Scenarios Summary ===" -ForegroundColor Cyan
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
