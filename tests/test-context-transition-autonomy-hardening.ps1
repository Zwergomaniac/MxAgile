<#
.SYNOPSIS
    Autonomy-First Compaction Hardening Regression Tests (Tests 41-50)

.DESCRIPTION
    Verifies that COMPACTION_USEFUL, COMPACTION_SKIPPED_UNSUPPORTED, and
    HARNESS_NATIVE_COMPACTION are never Human Gates, and that mission execution
    continues without user intervention when programmatic compaction is unavailable.

    41. Semantic boundary + unsupported compact → mission continues
    42. Pressure recommendation + unsupported compact → mission continues
    43. No '/compact' user request emitted for unsupported harness
    44. No fresh-session request emitted merely for token optimization
    45. COMPACTION_SKIPPED_UNSUPPORTED: IsHumanGate=false
    46. COMPACTION_SKIPPED_UNSUPPORTED: MissionContinues=true
    47. COMPACTION_SKIPPED_UNSUPPORTED: RequiredAction is empty (no gate message)
    48. OpenCode autonomous programmatic compaction: DiagnosticState=COMPACTION_AUTOMATABLE
    49. Claude Code hook path: DiagnosticState=COMPACTION_AUTOMATABLE, IsHumanGate=false
    50. Unavailable optimization cannot change evidence state (no TRANSITION_COMPLETED on skip)
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

$coordinatorScript  = Join-Path $ScriptDir "scripts\Invoke-MxAgileContextTransition.ps1"
$capabilitiesScript = Join-Path $ScriptDir "scripts\Get-MxAgileTransitionCapabilities.ps1"
$policyPath         = Join-Path $ScriptDir ".mxagile\policies\context-transition.md"
$epochSchemaPath    = Join-Path $ScriptDir ".mxagile\schemas\context-epoch.schema.json"

# ============================================================
# Tests 41-47: Unsupported harness → mission continues
# ============================================================

Write-Host "`n[Autonomy-First Tests 41-47: Unsupported harness]" -ForegroundColor Cyan

# Test 41: Semantic boundary + unsupported compact → mission continues
$result41 = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_RECOMMENDED" `
    -HarnessId "generic"

Assert-True "41: ROLLOVER_RECOMMENDED + generic → Success=true" `
    ($result41.Success -eq $true) `
    "Expected Success=true for ROLLOVER_RECOMMENDED + generic, got: $($result41.Success)"

Assert-True "41b: ROLLOVER_RECOMMENDED + generic → TransitionState=COMPACTION_SKIPPED_UNSUPPORTED" `
    ($result41.TransitionState -eq "COMPACTION_SKIPPED_UNSUPPORTED") `
    "Expected COMPACTION_SKIPPED_UNSUPPORTED, got: $($result41.TransitionState)"

# Test 42: Pressure recommendation + unsupported compact → mission continues
$result42 = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "generic"

Assert-True "42: ROLLOVER_REQUIRED + generic → Success=true" `
    ($result42.Success -eq $true) `
    "Expected Success=true for ROLLOVER_REQUIRED + generic, got: $($result42.Success)"

Assert-True "42b: ROLLOVER_REQUIRED + generic → TransitionState=COMPACTION_SKIPPED_UNSUPPORTED" `
    ($result42.TransitionState -eq "COMPACTION_SKIPPED_UNSUPPORTED") `
    "Expected COMPACTION_SKIPPED_UNSUPPORTED, got: $($result42.TransitionState)"

# Test 43: No '/compact' user request emitted
Assert-True "43: ROLLOVER_REQUIRED + generic: RequiredAction does not contain '/compact'" `
    ($result42.RequiredAction -notmatch '/compact') `
    "RequiredAction must not instruct user to type /compact: '$($result42.RequiredAction)'"

Assert-True "43b: ROLLOVER_RECOMMENDED + generic: RequiredAction does not contain '/compact'" `
    ($result41.RequiredAction -notmatch '/compact') `
    "RequiredAction must not instruct user to type /compact: '$($result41.RequiredAction)'"

# Also test copilot (other unsupported harness)
$result43c = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "copilot_cli"

Assert-True "43c: Copilot: RequiredAction does not contain '/compact'" `
    ($result43c.RequiredAction -notmatch '/compact') `
    "RequiredAction must not instruct user to type /compact: '$($result43c.RequiredAction)'"

# Test 44: No fresh-session request emitted merely for token optimization
Assert-True "44: ROLLOVER_REQUIRED + generic: RequiredAction does not say 'Start a new session'" `
    ($result42.RequiredAction -notmatch 'Start.{0,20}new session|neue.{0,20}Session') `
    "RequiredAction must not request new session for optimization: '$($result42.RequiredAction)'"

Assert-True "44b: ROLLOVER_RECOMMENDED + generic: RequiredAction does not say 'Start a new session'" `
    ($result41.RequiredAction -notmatch 'Start.{0,20}new session|neue.{0,20}Session') `
    "RequiredAction must not request new session for optimization: '$($result41.RequiredAction)'"

# Test 45: COMPACTION_SKIPPED_UNSUPPORTED: IsHumanGate=false
Assert-True "45: IsHumanGate=false for ROLLOVER_REQUIRED + generic" `
    ($result42.IsHumanGate -eq $false) `
    "IsHumanGate must be false for COMPACTION_SKIPPED_UNSUPPORTED"

Assert-True "45b: IsHumanGate=false for ROLLOVER_RECOMMENDED + generic" `
    ($result41.IsHumanGate -eq $false) `
    "IsHumanGate must be false for COMPACTION_SKIPPED_UNSUPPORTED"

# Test 46: COMPACTION_SKIPPED_UNSUPPORTED: MissionContinues=true
Assert-True "46: MissionContinues=true for ROLLOVER_REQUIRED + generic" `
    ($result42.MissionContinues -eq $true) `
    "MissionContinues must be true for COMPACTION_SKIPPED_UNSUPPORTED"

Assert-True "46b: MissionContinues=true for ROLLOVER_RECOMMENDED + generic" `
    ($result41.MissionContinues -eq $true) `
    "MissionContinues must be true for COMPACTION_SKIPPED_UNSUPPORTED"

# Test 47: RequiredAction is empty (no gate message)
Assert-True "47: RequiredAction is empty for ROLLOVER_REQUIRED + generic" `
    ([string]::IsNullOrEmpty($result42.RequiredAction)) `
    "RequiredAction must be empty for COMPACTION_SKIPPED_UNSUPPORTED, got: '$($result42.RequiredAction)'"

Assert-True "47b: RequiredAction is empty for ROLLOVER_RECOMMENDED + generic" `
    ([string]::IsNullOrEmpty($result41.RequiredAction)) `
    "RequiredAction must be empty for COMPACTION_SKIPPED_UNSUPPORTED, got: '$($result41.RequiredAction)'"

# ============================================================
# Tests 48-49: Autonomous paths still work
# ============================================================

Write-Host "`n[Autonomy-First Tests 48-49: Autonomous paths preserved]" -ForegroundColor Cyan

# Test 48: OpenCode DryRun: DiagnosticState=COMPACTION_AUTOMATABLE
$result48 = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "opencode" `
    -DryRun

Assert-True "48: OpenCode DryRun: DiagnosticState=COMPACTION_AUTOMATABLE" `
    ($result48.DiagnosticState -eq "COMPACTION_AUTOMATABLE") `
    "Expected COMPACTION_AUTOMATABLE for OpenCode DryRun, got: $($result48.DiagnosticState)"

Assert-True "48b: OpenCode DryRun: MissionContinues=true" `
    ($result48.MissionContinues -eq $true) `
    "MissionContinues must be true for OpenCode DryRun"

Assert-True "48c: OpenCode DryRun: IsHumanGate=false" `
    ($result48.IsHumanGate -eq $false) `
    "IsHumanGate must be false for OpenCode DryRun"

Assert-True "48d: OpenCode DryRun: Strategy=COMPACT_CURRENT_SESSION" `
    ($result48.Strategy -eq "COMPACT_CURRENT_SESSION") `
    "OpenCode should prefer COMPACT_CURRENT_SESSION, got: $($result48.Strategy)"

# Test 49: Claude Code DryRun: COMPACTION_AUTOMATABLE, IsHumanGate=false
$result49 = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "claude_code" `
    -DryRun

Assert-True "49: Claude Code DryRun: DiagnosticState=COMPACTION_AUTOMATABLE" `
    ($result49.DiagnosticState -eq "COMPACTION_AUTOMATABLE") `
    "Expected COMPACTION_AUTOMATABLE for Claude Code DryRun, got: $($result49.DiagnosticState)"

Assert-True "49b: Claude Code DryRun: IsHumanGate=false" `
    ($result49.IsHumanGate -eq $false) `
    "IsHumanGate must be false for Claude Code DryRun"

Assert-True "49c: Claude Code DryRun: MissionContinues=true" `
    ($result49.MissionContinues -eq $true) `
    "MissionContinues must be true for Claude Code DryRun"

# Verify Claude Code capabilities still show autonomous path
$cap49 = & $capabilitiesScript -ProjectRoot $ScriptDir -HarnessId "claude_code"
Assert-True "49d: Claude Code: CompactionAutomatable=true" `
    ($cap49.CompactionAutomatable -eq $true) `
    "Claude Code CompactionAutomatable must be true, got: $($cap49.CompactionAutomatable)"

# ============================================================
# Test 50: Unavailable optimization cannot change evidence or mission state
# ============================================================

Write-Host "`n[Autonomy-First Test 50: Evidence isolation]" -ForegroundColor Cyan

# COMPACTION_SKIPPED_UNSUPPORTED must never report TRANSITION_COMPLETED
Assert-True "50: ROLLOVER_REQUIRED + generic: TransitionState != TRANSITION_COMPLETED" `
    ($result42.TransitionState -ne "TRANSITION_COMPLETED") `
    "COMPACTION_SKIPPED_UNSUPPORTED must not set TRANSITION_COMPLETED"

Assert-True "50b: ROLLOVER_RECOMMENDED + generic: TransitionState != TRANSITION_COMPLETED" `
    ($result41.TransitionState -ne "TRANSITION_COMPLETED") `
    "COMPACTION_SKIPPED_UNSUPPORTED must not set TRANSITION_COMPLETED"

# DiagnosticState must be COMPACTION_SKIPPED_UNSUPPORTED (not evidence-promoting states)
Assert-True "50c: DiagnosticState is COMPACTION_SKIPPED_UNSUPPORTED (not TRANSITION_COMPLETED)" `
    ($result42.DiagnosticState -eq "COMPACTION_SKIPPED_UNSUPPORTED") `
    "DiagnosticState must be COMPACTION_SKIPPED_UNSUPPORTED, got: $($result42.DiagnosticState)"

# Policy must document the 5 diagnostic states
Assert-FileContains "50d: Policy documents COMPACTION_USEFUL" $policyPath "COMPACTION_USEFUL"
Assert-FileContains "50e: Policy documents COMPACTION_AUTOMATABLE" $policyPath "COMPACTION_AUTOMATABLE"
Assert-FileContains "50f: Policy documents COMPACTION_SKIPPED_UNSUPPORTED" $policyPath "COMPACTION_SKIPPED_UNSUPPORTED"
Assert-FileContains "50g: Policy documents HARNESS_NATIVE_COMPACTION" $policyPath "HARNESS_NATIVE_COMPACTION"
Assert-FileContains "50h: Policy documents CONTEXT_EXHAUSTION_BLOCKING" $policyPath "CONTEXT_EXHAUSTION_BLOCKING"

# Schema must contain the new diagnostic states
Assert-FileContains "50i: Schema contains COMPACTION_SKIPPED_UNSUPPORTED" $epochSchemaPath "COMPACTION_SKIPPED_UNSUPPORTED"
Assert-FileContains "50j: Schema contains CONTEXT_EXHAUSTION_BLOCKING" $epochSchemaPath "CONTEXT_EXHAUSTION_BLOCKING"
Assert-FileContains "50k: Schema contains diagnostic_state field" $epochSchemaPath '"diagnostic_state"'
Assert-FileContains "50l: Schema contains is_human_gate field" $epochSchemaPath '"is_human_gate"'
Assert-FileContains "50m: Schema contains mission_continues field" $epochSchemaPath '"mission_continues"'

# Policy must state autonomy-first invariant
Assert-FileContains "50n: Policy states AUTONOMY HAS PRIORITY" $policyPath "AUTONOMY HAS PRIORITY"

# ============================================================
# Summary
# ============================================================

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Autonomy-First Compaction Hardening Tests (41-50)" -ForegroundColor Cyan
Write-Host "PASS: $PassCount  FAIL: $FailCount" -ForegroundColor $(if ($FailCount -eq 0) { 'Green' } else { 'Red' })

if ($FailCount -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

exit 0
