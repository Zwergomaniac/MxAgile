<#
.SYNOPSIS
    Gradle Dependency-Sync Stall Diagnosis Tests: A through I

.DESCRIPTION
    Validates the bounded stall diagnosis and safe recovery contract for Gradle lock
    contention during mxcli dependency sync. Ensures active builds are not killed,
    slow-but-progressing sync is not classified as stalled, and hard-kill requires
    positive stale-owner evidence.
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

$GradlePol   = Join-Path $ScriptDir ".mxagile/policies/local-runtime-profile.md"
$DevRuntime  = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$ProcSchema  = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"

# TEST A: Active dependency resolution is not killed
Write-Host ""
Write-Host "TEST A: Active dependency resolution is not killed" -ForegroundColor Cyan
Assert-FileContains "A.1 policy defines active state as forward progress observed" $GradlePol 'active.*forward progress'
Assert-FileContains "A.2 ACTIVE_BUILD owner classification prohibits termination" $GradlePol 'ACTIVE_BUILD.*Do NOT terminate'
Assert-FileContains "A.3 process-state schema has active state in dependency_sync_state enum" $ProcSchema '"active"'

# TEST B: Slow but progressing resolution is NOT classified STALLED
Write-Host ""
Write-Host "TEST B: Slow but progressing resolution is not classified STALLED" -ForegroundColor Cyan
Assert-FileContains "B.1 policy defines long_running as slow-but-progressing" $GradlePol 'long_running.*progress'
Assert-FileContains "B.2 policy states stalled requires absence of progress, not just elapsed time" $GradlePol 'stalled.*absence of forward progress'
Assert-FileContains "B.3 policy defines forward progress signals explicitly" $GradlePol 'Forward progress signals'
Assert-FileContains "B.4 process-state schema has long_running state" $ProcSchema '"long_running"'
Assert-FileContains "B.5 policy states long_running must NOT be classified stalled" $GradlePol 'long_running.*NOT.*classified.*stalled'

# TEST C: Lock contention with active owner blocks safely
Write-Host ""
Write-Host "TEST C: Lock contention with active build owner blocks safely" -ForegroundColor Cyan
Assert-FileContains "C.1 policy defines lock_contended state" $GradlePol 'lock_contended'
Assert-FileContains "C.2 ACTIVE_BUILD classification blocks and does not terminate" $GradlePol 'ACTIVE_BUILD'
Assert-FileContains "C.3 recovery ladder Step 4 escalates to developer for ACTIVE_BUILD" $GradlePol 'ACTIVE_BUILD.*UNIDENTIFIED'
Assert-FileContains "C.4 process-state has lock_contended state" $ProcSchema '"lock_contended"'

# TEST D: Proven leftover owner enters safe recovery
Write-Host ""
Write-Host "TEST D: Proven leftover (STALE_LEFTOVER) owner enters recovery" -ForegroundColor Cyan
Assert-FileContains "D.1 policy defines STALE_LEFTOVER classification" $GradlePol 'STALE_LEFTOVER'
Assert-FileContains "D.2 STALE_LEFTOVER eligible for safe recovery" $GradlePol 'eligible for safe recovery'
Assert-FileContains "D.3 recovery ladder recommends gradle --stop for STALE_LEFTOVER" $GradlePol 'gradle --stop'
Assert-FileContains "D.4 process-state has stale_leftover in owner classification enum" $ProcSchema '"stale_leftover"'

# TEST E: Unrelated Gradle/Java processes are never terminated
Write-Host ""
Write-Host "TEST E: Unrelated Gradle/Java processes are never terminated" -ForegroundColor Cyan
Assert-FileContains "E.1 policy prohibits killing all Java processes" $GradlePol 'Kill all Java processes'
Assert-FileContains "E.2 policy prohibits killing all Gradle daemons without owner check" $GradlePol 'Kill all Gradle daemons'
Assert-FileContains "E.3 hard-kill requires specific stale owner PID only" $GradlePol 'only the specific stale owner PID'
Assert-FileContains "E.4 development-runtime.md states MUST NOT automatically kill arbitrary processes" $DevRuntime 'MUST NOT automatically kill'

# TEST F: Lock files are never blindly deleted
Write-Host ""
Write-Host "TEST F: Lock files are never blindly deleted" -ForegroundColor Cyan
Assert-FileContains "F.1 policy prohibits deleting lock files as startup routine" $GradlePol 'Delete.*lock.*startup'
Assert-FileContains "F.2 policy states lock file deletion only after confirming no live process" $GradlePol 'no writes in progress'
Assert-FileNotContains "F.3 policy does not recommend blanket lock deletion as normal recovery" $GradlePol 'delete.*lock.*always|always.*delete.*lock'

# TEST G: Second local run after clean shutdown succeeds
Write-Host ""
Write-Host "TEST G: Second local run after clean shutdown succeeds" -ForegroundColor Cyan
Assert-FileContains "G.1 repeated-run contract defined" $GradlePol 'Repeated-Run Contract'
Assert-FileContains "G.2 no active processes AND no held locks: proceed normally" $GradlePol 'NO active processes.*NO held locks.*proceed'

# TEST H: Second local run after interrupted lifecycle enters bounded diagnosis
Write-Host ""
Write-Host "TEST H: Second run after interrupted lifecycle enters bounded diagnosis, not indefinite wait" -ForegroundColor Cyan
Assert-FileContains "H.1 repeated-run contract covers interrupted lifecycle" $GradlePol 'stopped or interrupted'
Assert-FileContains "H.2 held locks trigger Safe Recovery Ladder, not indefinite wait" $GradlePol 'held locks.*Safe Recovery Ladder'
Assert-FileContains "H.3 concurrent run prevention is defined" $GradlePol 'Concurrent run prevention'

# TEST I: Recovery state is reported clearly
Write-Host ""
Write-Host "TEST I: Recovery state is reported clearly to agent/developer" -ForegroundColor Cyan
Assert-FileContains "I.1 policy requires reporting lock file path and owner classification" $GradlePol 'lock file path.*owner classification'
Assert-FileContains "I.2 process-state records dependency_sync_state for session resumability" $ProcSchema 'dependency_sync_state'
Assert-FileContains "I.3 process-state records dependency_sync_owner_classification" $ProcSchema 'dependency_sync_owner_classification'
Assert-FileContains "I.4 hard termination must be recorded in blocked_operation with evidence" $GradlePol 'recorded in.*blocked_operation.*evidence'

# ADDITIONAL: mxcli upstream finding is explicit and actionable
Write-Host ""
Write-Host "TEST UPSTREAM: mxcli upstream finding is concrete and actionable" -ForegroundColor Cyan
Assert-FileContains "UP.1 upstream finding requests PID exposure from mxcli" $GradlePol 'Expose the PID'
Assert-FileContains "UP.2 upstream finding requests structured stall event from mxcli" $GradlePol 'dependency_sync_stalled'
Assert-FileContains "UP.3 upstream finding requests bounded sync timeout from mxcli" $GradlePol 'bounded sync timeout'

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
