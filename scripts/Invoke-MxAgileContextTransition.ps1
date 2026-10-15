<#
.SYNOPSIS
    Main coordinator for MxAgile autonomous context transitions.

.DESCRIPTION
    Coordinates the complete context transition lifecycle:
      1. Resolve transition capabilities for the current harness
      2. Evaluate pressure state
      3. Check safe-boundary conditions
      4. Execute pre-compaction checkpoint protocol
      5. Request/trigger transition via preferred strategy
      6. Monitor completion (where observable)
      7. Update transition state machine

    Transition strategies (in preference order, configurable):
      COMPACT_CURRENT_SESSION  — harness-native compaction, same session
      FRESH_CONTEXT_EPOCH      — fresh context, preserve mission via checkpoint
      EXTERNAL_ACTION_REQUIRED — no autonomous path available

    Safety invariants (never violated):
      - No transition during unsafe operation
      - No transition without valid checkpoint
      - No fabricated TRANSITION_COMPLETED
      - No evidence promotion from compaction summary
      - One pending transition at a time

    Policy: .mxagile/policies/context-transition.md

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER PressureState
    Current context pressure state from Get-MxAgileContextPressure.ps1.
    If not supplied, ROLLOVER_REQUIRED is assumed (caller asserts pressure).

.PARAMETER CallerSafetyFlags
    Hashtable of boolean conditions the caller asserts (safe boundary).
    Keys: no_tool_call_in_flight, no_file_write_in_flight,
          no_checkpoint_write_active, no_pending_commit,
          harness_supports_transition

.PARAMETER HarnessId
    Override harness detection.

.PARAMETER TransitionRequestId
    Idempotency ID. Generated if not supplied.

.PARAMETER HotContextSummary
    HOT context summary for the new epoch.

.PARAMETER NextAction
    Next safe action after transition.

.PARAMETER NextActionSafe
    True if the next action can start without additional confirmation.

.PARAMETER NextChecklistItem
    Specific checklist item to resume from.

.PARAMETER Force
    Skip safety check. Use only in exceptional recovery scenarios.

.PARAMETER DryRun
    Evaluate readiness without executing the transition.

.OUTPUTS
    PSCustomObject with:
      .Success              — boolean
      .TransitionState      — final transition state
      .Strategy             — selected strategy
      .HarnessId            — detected harness
      .TransitionRequestId  — idempotency ID
      .CheckpointPath       — checkpoint path
      .HandoffPath          — handoff copy path
      .BlockingConditions   — string[] if blocked
      .RequiredAction       — what to do next (for EXTERNAL_ACTION_REQUIRED)
      .DiagnosticState      — Autonomy-First classification (see vocabulary)
      .MissionContinues     — true unless CONTEXT_EXHAUSTION_BLOCKING
      .IsHumanGate          — true only for CONTEXT_EXHAUSTION_BLOCKING
      .DryRunResult         — readiness summary (when DryRun=true)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$PressureState = "ROLLOVER_REQUIRED",

    [hashtable]$CallerSafetyFlags = @{},

    [string]$HarnessId = "",

    [string]$TransitionRequestId = "",

    [string]$HotContextSummary = "",

    [string]$NextAction = "Re-sync and continue mission after context transition",

    [bool]$NextActionSafe = $false,

    [string]$NextChecklistItem = "",

    [switch]$Force,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# Step 1: Resolve transition capabilities
# ---------------------------------------------------------------------------
$capabilitiesScript = Join-Path $PSScriptRoot "Get-MxAgileTransitionCapabilities.ps1"
$capabilities = $null
if (Test-Path -LiteralPath $capabilitiesScript) {
    $resolveArgs = @{ ProjectRoot = $ProjectRoot }
    if (-not [string]::IsNullOrEmpty($HarnessId)) { $resolveArgs['HarnessId'] = $HarnessId }
    $capabilities = & $capabilitiesScript @resolveArgs
}

$resolvedHarnessId = if ($null -ne $capabilities) { $capabilities.HarnessId } else { 'generic' }
$preferredStrategy = if ($null -ne $capabilities) { $capabilities.PreferredStrategy } else { 'EXTERNAL_ACTION_REQUIRED' }

# ---------------------------------------------------------------------------
# Step 2: Check if transition enabled and pressure warrants action
# ---------------------------------------------------------------------------
$actionablePressure = @('ROLLOVER_RECOMMENDED', 'ROLLOVER_REQUIRED')
if ($PressureState -notin $actionablePressure) {
    return [PSCustomObject]@{
        Success             = $false
        TransitionState     = "IDLE"
        DiagnosticState     = $null
        MissionContinues    = $true
        IsHumanGate         = $false
        Strategy            = $preferredStrategy
        HarnessId           = $resolvedHarnessId
        TransitionRequestId = $TransitionRequestId
        CheckpointPath      = ""
        HandoffPath         = ""
        BlockingConditions  = @("pressure_not_actionable: $PressureState")
        RequiredAction      = "Transition not required at current pressure level ($PressureState)."
        DryRunResult        = $null
    }
}

# ---------------------------------------------------------------------------
# DryRun: report readiness without executing (evaluated before safety check)
# ---------------------------------------------------------------------------
if ($DryRun) {
    $autonomousPossible = if ($null -ne $capabilities) { $capabilities.AutonomousCompactionPossible } else { $false }
    # COMPACTION_AUTOMATABLE is based on harness capability (can it automate?), independent of config flag.
    $harnessCanAutomate = ($null -ne $capabilities) -and (
        ($capabilities.CompactCurrentSession.ProgrammaticSupported -and $capabilities.CompactCurrentSession.CompletionObservable) -or
        ($capabilities.CompactCurrentSession.AutomaticSupported -and $capabilities.Hooks.PreCompact -eq 'SUPPORTED')
    )
    $dryRunDiagnostic   = if ($preferredStrategy -eq 'EXTERNAL_ACTION_REQUIRED') { 'COMPACTION_SKIPPED_UNSUPPORTED' } `
                          elseif ($harnessCanAutomate) { 'COMPACTION_AUTOMATABLE' } `
                          else { 'COMPACTION_USEFUL' }
    $readiness = @{
        HarnessId              = $resolvedHarnessId
        PreferredStrategy      = $preferredStrategy
        PressureState          = $PressureState
        SafeBoundaryMet        = $true
        AutonomousPossible     = $autonomousPossible
        CapabilitiesLoaded     = ($null -ne $capabilities -and $capabilities.AdapterLoaded)
        DiagnosticState        = $dryRunDiagnostic
    }
    return [PSCustomObject]@{
        Success             = $true
        TransitionState     = if ($preferredStrategy -eq 'EXTERNAL_ACTION_REQUIRED') { 'COMPACTION_SKIPPED_UNSUPPORTED' } else { 'TRANSITION_REQUESTED' }
        DiagnosticState     = $dryRunDiagnostic
        MissionContinues    = $true
        IsHumanGate         = $false
        Strategy            = $preferredStrategy
        HarnessId           = $resolvedHarnessId
        TransitionRequestId = "DRY_RUN"
        CheckpointPath      = ""
        HandoffPath         = ""
        BlockingConditions  = @()
        RequiredAction      = if ($preferredStrategy -eq 'EXTERNAL_ACTION_REQUIRED') { "" } else { "DryRun: would execute $preferredStrategy" }
        DryRunResult        = $readiness
    }
}

# ---------------------------------------------------------------------------
# Autonomy-First: no autonomous path → COMPACTION_SKIPPED_UNSUPPORTED (NOT a Human Gate)
# ---------------------------------------------------------------------------
if ($preferredStrategy -eq 'EXTERNAL_ACTION_REQUIRED' -and -not $Force) {
    return [PSCustomObject]@{
        Success             = $true
        TransitionState     = "COMPACTION_SKIPPED_UNSUPPORTED"
        DiagnosticState     = "COMPACTION_SKIPPED_UNSUPPORTED"
        MissionContinues    = $true
        IsHumanGate         = $false
        Strategy            = "EXTERNAL_ACTION_REQUIRED"
        HarnessId           = $resolvedHarnessId
        TransitionRequestId = ""
        CheckpointPath      = ""
        HandoffPath         = ""
        BlockingConditions  = @()
        RequiredAction      = ""
        DryRunResult        = $null
        DiagnosticNote      = "Compaction beneficial but no autonomous trigger on $resolvedHarnessId. Native harness auto-compaction applies if available. Mission continues."
    }
}

# ---------------------------------------------------------------------------
# Step 3: Check safe-boundary conditions
# ---------------------------------------------------------------------------
if (-not $Force) {
    $safetyScript = Join-Path $PSScriptRoot "Test-MxAgileRolloverSafety.ps1"
    if (Test-Path -LiteralPath $safetyScript) {
        $safety = & $safetyScript -ProjectRoot $ProjectRoot -CallerSafetyFlags $CallerSafetyFlags
        if (-not $safety.Safe) {
            # Record as pending safe boundary
            return [PSCustomObject]@{
                Success             = $false
                TransitionState     = "PENDING_SAFE_BOUNDARY"
                DiagnosticState     = "COMPACTION_USEFUL"
                MissionContinues    = $true
                IsHumanGate         = $false
                Strategy            = $preferredStrategy
                HarnessId           = $resolvedHarnessId
                TransitionRequestId = $TransitionRequestId
                CheckpointPath      = ""
                HandoffPath         = ""
                BlockingConditions  = $safety.BlockingConditions
                RequiredAction      = "Transition deferred to next safe boundary. Resolve: $($safety.BlockingConditions -join '; ')"
                DryRunResult        = $null
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Step 4: Pre-compaction checkpoint protocol
# ---------------------------------------------------------------------------
$preCompactScript = Join-Path $PSScriptRoot "Invoke-MxAgilePreCompactionCheckpoint.ps1"
if (-not (Test-Path -LiteralPath $preCompactScript)) {
    return [PSCustomObject]@{
        Success             = $false
        TransitionState     = "TRANSITION_BLOCKED"
        DiagnosticState     = $null
        MissionContinues    = $false
        IsHumanGate         = $false
        Strategy            = $preferredStrategy
        HarnessId           = $resolvedHarnessId
        TransitionRequestId = $TransitionRequestId
        CheckpointPath      = ""
        HandoffPath         = ""
        BlockingConditions  = @("pre_compaction_script_missing")
        RequiredAction      = "Invoke-MxAgilePreCompactionCheckpoint.ps1 not found."
        DryRunResult        = $null
    }
}

$preCompactResult = & $preCompactScript `
    -ProjectRoot $ProjectRoot `
    -TransitionRequestId $TransitionRequestId `
    -HotContextSummary $HotContextSummary `
    -NextAction $NextAction `
    -NextActionSafe $NextActionSafe `
    -NextChecklistItem $NextChecklistItem

if (-not $preCompactResult.Success) {
    return [PSCustomObject]@{
        Success             = $false
        TransitionState     = $preCompactResult.TransitionState
        DiagnosticState     = $null
        MissionContinues    = $false
        IsHumanGate         = $false
        Strategy            = $preferredStrategy
        HarnessId           = $resolvedHarnessId
        TransitionRequestId = $preCompactResult.TransitionRequestId
        CheckpointPath      = $preCompactResult.CheckpointPath
        HandoffPath         = $preCompactResult.HandoffPath
        BlockingConditions  = $preCompactResult.BlockingReasons
        RequiredAction      = "Pre-compaction checkpoint failed. Do not proceed with compaction."
        DryRunResult        = $null
    }
}

$resolvedTransitionId = $preCompactResult.TransitionRequestId

# ---------------------------------------------------------------------------
# Step 5: Execute transition based on preferred strategy
# ---------------------------------------------------------------------------

if ($preferredStrategy -eq 'COMPACT_CURRENT_SESSION') {

    # Harness-specific execution
    if ($resolvedHarnessId -eq 'opencode') {
        # OpenCode: programmatic compact API
        $sessionId = [System.Environment]::GetEnvironmentVariable('OPENCODE_SESSION_ID')
        $baseUrl   = [System.Environment]::GetEnvironmentVariable('OPENCODE_BASE_URL')
        if ([string]::IsNullOrEmpty($baseUrl)) { $baseUrl = 'http://localhost:4096' }

        if ([string]::IsNullOrEmpty($sessionId)) {
            return [PSCustomObject]@{
                Success             = $false
                TransitionState     = "TRANSITION_BLOCKED"
                DiagnosticState     = "COMPACTION_AUTOMATABLE"
                MissionContinues    = $false
                IsHumanGate         = $false
                Strategy            = 'COMPACT_CURRENT_SESSION'
                HarnessId           = $resolvedHarnessId
                TransitionRequestId = $resolvedTransitionId
                CheckpointPath      = $preCompactResult.CheckpointPath
                HandoffPath         = $preCompactResult.HandoffPath
                BlockingConditions  = @("opencode_session_id_unavailable")
                RequiredAction      = "Set OPENCODE_SESSION_ID environment variable."
                DryRunResult        = $null
            }
        }

        $compactBody = @{ id = $resolvedTransitionId } | ConvertTo-Json -Compress
        $compactUrl  = "$baseUrl/api/session/$sessionId/compact"

        $httpResult  = $null
        $_savedEap   = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $response = Invoke-RestMethod -Uri $compactUrl -Method POST `
                -ContentType 'application/json' -Body $compactBody -TimeoutSec 30
            $httpResult = @{ Success = $true; Response = $response }
        } catch {
            $httpResult = @{ Success = $false; Error = $_.Exception.Message }
        }
        $ErrorActionPreference = $_savedEap

        if (-not $httpResult.Success) {
            return [PSCustomObject]@{
                Success             = $false
                TransitionState     = "TRANSITION_FAILED"
                DiagnosticState     = "COMPACTION_AUTOMATABLE"
                MissionContinues    = $false
                IsHumanGate         = $false
                Strategy            = 'COMPACT_CURRENT_SESSION'
                HarnessId           = $resolvedHarnessId
                TransitionRequestId = $resolvedTransitionId
                CheckpointPath      = $preCompactResult.CheckpointPath
                HandoffPath         = $preCompactResult.HandoffPath
                BlockingConditions  = @("opencode_compact_api_failed: $($httpResult.Error)")
                RequiredAction      = "OpenCode compact API call failed. Check OpenCode is running. Checkpoint preserved."
                DryRunResult        = $null
            }
        }

        # Request admitted. Completion is async (session.compaction.* events).
        return [PSCustomObject]@{
            Success             = $true
            TransitionState     = "COMPACTION_ADMITTED"
            DiagnosticState     = "COMPACTION_AUTOMATABLE"
            MissionContinues    = $true
            IsHumanGate         = $false
            Strategy            = 'COMPACT_CURRENT_SESSION'
            HarnessId           = $resolvedHarnessId
            TransitionRequestId = $resolvedTransitionId
            CheckpointPath      = $preCompactResult.CheckpointPath
            HandoffPath         = $preCompactResult.HandoffPath
            BlockingConditions  = @()
            RequiredAction      = "Compaction admitted by OpenCode. Await session.compaction.completed event. Re-Sync required after completion."
            DryRunResult        = $null
        }

    } elseif ($resolvedHarnessId -eq 'claude_code') {
        # Claude Code: native auto-compaction via PreCompact + SessionStart hooks.
        # No programmatic trigger — harness manages compaction transparently.
        return [PSCustomObject]@{
            Success             = $true
            TransitionState     = "CHECKPOINT_VALIDATED"
            DiagnosticState     = "COMPACTION_AUTOMATABLE"
            MissionContinues    = $true
            IsHumanGate         = $false
            Strategy            = 'COMPACT_CURRENT_SESSION'
            HarnessId           = $resolvedHarnessId
            TransitionRequestId = $resolvedTransitionId
            CheckpointPath      = $preCompactResult.CheckpointPath
            HandoffPath         = $preCompactResult.HandoffPath
            BlockingConditions  = @()
            RequiredAction      = "Checkpoint validated. Claude Code will compact automatically. SessionStart hook triggers Re-Sync in new session. Programmatic trigger is UNSUPPORTED."
            DryRunResult        = $null
        }

    } else {
        # Generic: compaction is not programmatically available. Should have been
        # caught by the early COMPACTION_SKIPPED_UNSUPPORTED path above, but
        # if reached via Force, fall through to FRESH_CONTEXT_EPOCH.
        $preferredStrategy = 'FRESH_CONTEXT_EPOCH'
    }
}

if ($preferredStrategy -eq 'FRESH_CONTEXT_EPOCH') {
    # Fresh context: checkpoint ready for a new session.
    # Autonomy-First: this is informational guidance, not a Human Gate.
    # Mission continues; a new session can be started when convenient.
    return [PSCustomObject]@{
        Success             = $true
        TransitionState     = "FRESH_CONTEXT_READY"
        DiagnosticState     = "COMPACTION_USEFUL"
        MissionContinues    = $true
        IsHumanGate         = $false
        Strategy            = 'FRESH_CONTEXT_EPOCH'
        HarnessId           = $resolvedHarnessId
        TransitionRequestId = $resolvedTransitionId
        CheckpointPath      = $preCompactResult.CheckpointPath
        HandoffPath         = $preCompactResult.HandoffPath
        BlockingConditions  = @()
        RequiredAction      = ""
        DryRunResult        = $null
        DiagnosticNote      = "Checkpoint ready for fresh session at: $($preCompactResult.HandoffPath). Not a gate — mission continues."
    }
}

# Unreachable under normal conditions (caught by early COMPACTION_SKIPPED_UNSUPPORTED).
# Defensive fallback only.
return [PSCustomObject]@{
    Success             = $true
    TransitionState     = "COMPACTION_SKIPPED_UNSUPPORTED"
    DiagnosticState     = "COMPACTION_SKIPPED_UNSUPPORTED"
    MissionContinues    = $true
    IsHumanGate         = $false
    Strategy            = 'EXTERNAL_ACTION_REQUIRED'
    HarnessId           = $resolvedHarnessId
    TransitionRequestId = $resolvedTransitionId
    CheckpointPath      = if ($null -ne $preCompactResult) { $preCompactResult.CheckpointPath } else { "" }
    HandoffPath         = if ($null -ne $preCompactResult) { $preCompactResult.HandoffPath } else { "" }
    BlockingConditions  = @()
    RequiredAction      = ""
    DryRunResult        = $null
    DiagnosticNote      = "No autonomous transition path. Mission continues. Native harness auto-compaction applies if available."
}
