<#
.SYNOPSIS
    Performs a complete Context Epoch rollover.

.DESCRIPTION
    Implements the 10-step manual rollover process:
      1.  Determine current mission/lifecycle state
      2.  Ensure no unsafe operation is in flight
      3.  Persist required evidence
      4.  Write durable operational checkpoint
      5.  Validate the checkpoint
      6.  Record rollover reason
      7.  Close the current Context Epoch
      8.  Create/increment the next Epoch identity
      9.  Expose the state required for a fresh agent context
      10. Require resume/re-sync before work continues

    Manual rollover never silently declares mission completion.

    If the harness cannot start a fresh context:
      - Produces a deterministic rollover-ready state
      - Does not pretend a context transition occurred
      - Preserves the checkpoint
      - Exposes the required human/harness action

    Rollover state machine:
      rollover_recommended → rollover_ready → rollover_performed
                           → rollover_blocked (if safety fails)
                           → rollover_unsupported_by_harness

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER RolloverReason
    Why this rollover is being performed.
    manual_rollover | pressure_recommendation_accepted |
    lifecycle_boundary | interruption_boundary | auto_rollover

.PARAMETER NextAction
    Human-readable description of the next safe action after rollover.

.PARAMETER NextActionSafe
    True if the next action can start without additional confirmation.

.PARAMETER NextChecklistItem
    Specific checklist item to resume from (e.g. W01-03).

.PARAMETER HotContextSummary
    1-3 sentence HOT context summary for the new epoch.

.PARAMETER CallerSafetyFlags
    Hashtable of boolean safety conditions the caller asserts.
    See Test-MxAgileRolloverSafety.ps1 for required keys.

.PARAMETER Force
    Skip safety check. Use only in exceptional recovery scenarios.

.OUTPUTS
    PSCustomObject with:
      .Success           — boolean
      .RolloverState     — string (rollover_performed | rollover_blocked | rollover_unsupported_by_harness)
      .PriorEpochId      — string (e.g. EPOCH-001)
      .NewEpochId        — string (e.g. EPOCH-002)
      .CheckpointPath    — string (operational checkpoint path)
      .HandoffPath       — string (git-tracked handoff copy path)
      .Reason            — string (rollover reason)
      .BlockingConditions — string[] (if blocked)
      .RequiredAction    — string (what the user/harness must do next)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$RolloverReason = "manual_rollover",

    [string]$NextAction = "Re-sync and resume from new epoch checkpoint",

    [bool]$NextActionSafe = $false,

    [string]$NextChecklistItem = "",

    [string]$HotContextSummary = "",

    [hashtable]$CallerSafetyFlags = @{},

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# Step 1: Determine current mission/lifecycle state
# ---------------------------------------------------------------------------
$readerScript = Join-Path $PSScriptRoot "Read-MxAgileEpochCheckpoint.ps1"
if (-not (Test-Path -LiteralPath $readerScript)) {
    return [PSCustomObject]@{
        Success            = $false
        RolloverState      = "rollover_blocked"
        PriorEpochId       = ""
        NewEpochId         = ""
        CheckpointPath     = ""
        HandoffPath        = ""
        Reason             = $RolloverReason
        BlockingConditions = @("checkpoint_reader_missing")
        RequiredAction     = "Read-MxAgileEpochCheckpoint.ps1 not found in $PSScriptRoot"
    }
}

$currentCheckpoint = & $readerScript -ProjectRoot $ProjectRoot

if (-not $currentCheckpoint.Valid) {
    return [PSCustomObject]@{
        Success            = $false
        RolloverState      = "rollover_blocked"
        PriorEpochId       = ""
        NewEpochId         = ""
        CheckpointPath     = ""
        HandoffPath        = ""
        Reason             = $RolloverReason
        BlockingConditions = @("no_valid_checkpoint: $($currentCheckpoint.ConflictReason)")
        RequiredAction     = "Write a valid checkpoint before rollover."
    }
}

$priorEpochId    = $currentCheckpoint.EpochId
$missionId       = $currentCheckpoint.MissionId
$missionObj      = $currentCheckpoint.MissionObjective
$missionStatus   = $currentCheckpoint.MissionStatus
$currentPhase    = $currentCheckpoint.CurrentPhase

# Guard: never silently declare mission completion
if ($missionStatus -eq "complete" -or $missionStatus -eq "failed") {
    return [PSCustomObject]@{
        Success            = $false
        RolloverState      = "rollover_blocked"
        PriorEpochId       = $priorEpochId
        NewEpochId         = ""
        CheckpointPath     = ""
        HandoffPath        = ""
        Reason             = $RolloverReason
        BlockingConditions = @("mission_terminal: $missionStatus")
        RequiredAction     = "Mission is in terminal state '$missionStatus'. Rollover is not applicable."
    }
}

# ---------------------------------------------------------------------------
# Step 2: Ensure no unsafe operation is in flight
# ---------------------------------------------------------------------------
if (-not $Force) {
    $safetyScript = Join-Path $PSScriptRoot "Test-MxAgileRolloverSafety.ps1"
    if (Test-Path -LiteralPath $safetyScript) {
        $safety = & $safetyScript -ProjectRoot $ProjectRoot -CallerSafetyFlags $CallerSafetyFlags
        if (-not $safety.Safe) {
            # Determine if harness limitation vs. genuine block
            $isHarnessOnly = ($safety.BlockingConditions.Count -eq 1) -and
                             ($safety.BlockingConditions[0] -match 'harness_supports_transition')
            $rolloverState = if ($isHarnessOnly) { "rollover_unsupported_by_harness" } else { "rollover_blocked" }

            return [PSCustomObject]@{
                Success            = $false
                RolloverState      = $rolloverState
                PriorEpochId       = $priorEpochId
                NewEpochId         = ""
                CheckpointPath     = ""
                HandoffPath        = ""
                Reason             = $RolloverReason
                BlockingConditions = $safety.BlockingConditions
                RequiredAction     = "Resolve blocking conditions before rollover: $($safety.BlockingConditions -join '; ')"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Step 3-6: Persist evidence and write rollover checkpoint
# ---------------------------------------------------------------------------
# Increment epoch ID
$newEpochNum = 1
if ($priorEpochId -match 'EPOCH-(\d+)') {
    $newEpochNum = [int]$Matches[1] + 1
}
$newEpochId = "EPOCH-{0:D3}" -f $newEpochNum

# Build previous_epochs entry for the prior epoch
$now = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$priorEpochEntry = @"
  - epoch_id: $priorEpochId
    rolled_over: "$now"
    rollover_reason: $RolloverReason
"@

# Archive current operational checkpoint before overwriting
$concordDir     = Join-Path $ProjectRoot ".concord"
$currentCpPath  = Join-Path $concordDir "context-epoch.yaml"
$archivePath    = Join-Path $concordDir "context-epoch-$priorEpochId.yaml"

if (Test-Path -LiteralPath $currentCpPath) {
    Copy-Item -LiteralPath $currentCpPath -Destination $archivePath -Force
}

# Write the new epoch checkpoint using the writer
$writerScript = Join-Path $PSScriptRoot "Write-MxAgileEpochCheckpoint.ps1"
if (-not (Test-Path -LiteralPath $writerScript)) {
    return [PSCustomObject]@{
        Success            = $false
        RolloverState      = "rollover_blocked"
        PriorEpochId       = $priorEpochId
        NewEpochId         = $newEpochId
        CheckpointPath     = ""
        HandoffPath        = ""
        Reason             = $RolloverReason
        BlockingConditions = @("checkpoint_writer_missing")
        RequiredAction     = "Write-MxAgileEpochCheckpoint.ps1 not found."
    }
}

& $writerScript `
    -ProjectRoot $ProjectRoot `
    -MissionId $missionId `
    -MissionObjective $missionObj `
    -MissionStatus $missionStatus `
    -CurrentPhase $currentPhase `
    -EpochId $newEpochId `
    -RolloverReason $RolloverReason `
    -NextAction $NextAction `
    -NextActionSafe $NextActionSafe `
    -NextChecklistItem $NextChecklistItem `
    -HotContextSummary $HotContextSummary `
    -PreserveEvidence `
    -WriteHandoffCopy

# ---------------------------------------------------------------------------
# Step 5: Validate the new checkpoint
# ---------------------------------------------------------------------------
$newCheckpoint = & $readerScript -ProjectRoot $ProjectRoot
if (-not $newCheckpoint.Valid) {
    return [PSCustomObject]@{
        Success            = $false
        RolloverState      = "rollover_blocked"
        PriorEpochId       = $priorEpochId
        NewEpochId         = $newEpochId
        CheckpointPath     = ""
        HandoffPath        = ""
        Reason             = $RolloverReason
        BlockingConditions = @("post_rollover_checkpoint_invalid: $($newCheckpoint.ConflictReason)")
        RequiredAction     = "New checkpoint failed validation. Prior checkpoint archived at $archivePath"
    }
}

# ---------------------------------------------------------------------------
# Step 7-8: Inject previous_epochs into the checkpoint
# ---------------------------------------------------------------------------
$cpPath     = Join-Path $concordDir "context-epoch.yaml"
$handoffDir = Join-Path $ProjectRoot "planning\lifecycle"
$handoffPath = Join-Path $handoffDir "context-epoch.yaml"

$cpContent = Get-Content -LiteralPath $cpPath -Raw -Encoding UTF8

# Insert previous_epochs after active_context_epoch line
$cpContent = $cpContent -replace '(active_context_epoch:\s+\S+)', "`$1`n  previous_epochs:`n$priorEpochEntry"

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($cpPath, $cpContent, $utf8NoBom)

# Update handoff copy too
if (Test-Path -LiteralPath $handoffPath) {
    [System.IO.File]::WriteAllText($handoffPath, $cpContent, $utf8NoBom)
}

# ---------------------------------------------------------------------------
# Step 9-10: Expose state and require re-sync
# ---------------------------------------------------------------------------
$checkpointPath = $cpPath
$handoffResult  = if (Test-Path -LiteralPath $handoffPath) { $handoffPath } else { "" }

Write-Host "Rollover complete: $priorEpochId -> $newEpochId (reason: $RolloverReason)" -ForegroundColor Green
Write-Host "Checkpoint: $checkpointPath" -ForegroundColor Cyan
if ($handoffResult) {
    Write-Host "Handoff: $handoffResult" -ForegroundColor Cyan
}
Write-Host "REQUIRED: Re-sync before continuing work." -ForegroundColor Yellow

return [PSCustomObject]@{
    Success            = $true
    RolloverState      = "rollover_performed"
    PriorEpochId       = $priorEpochId
    NewEpochId         = $newEpochId
    CheckpointPath     = $checkpointPath
    HandoffPath        = $handoffResult
    Reason             = $RolloverReason
    BlockingConditions = @()
    RequiredAction     = "Re-sync required before continuing work. Run Sync-MxAgileEpochCheckpoint.ps1 -ProjectRoot '$ProjectRoot'"
}
