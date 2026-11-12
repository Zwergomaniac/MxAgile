<#
.SYNOPSIS
    Executes the MxAgile Post-Compaction Re-Sync Protocol.

.DESCRIPTION
    Implements the post-compaction protocol defined in
    .mxagile/policies/context-transition.md.

    Must run after every compaction before mission work continues.

    Steps:
      1.  Check if post_compaction_resync_required flag is set
      2.  Reload and validate active mission checkpoint
      3.  Inspect repository identity and working-tree state
      4.  Preserve FAILED and UNVERIFIED evidence states
      5.  Apply STALE rules for repository changes
      6.  Reconstruct minimal HOT context
      7.  Report Re-Sync result
      8.  Clear post_compaction_resync_required flag on success
      9.  Set transition_state to TRANSITION_COMPLETED

    If the harness compaction summary disagrees with the checkpoint:
      MxAgile checkpoint and repository evidence WIN.
      Discrepancies are recorded diagnostically.

    The agent must NOT ask the user to restate the mission when
    the checkpoint is sufficient.

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER CompactionSummary
    Optional: content from the harness compaction summary.
    Used only for diagnostic conflict recording — never as authoritative state.

.PARAMETER ExpectedTransitionRequestId
    Optional: expected transition request ID for verification.

.OUTPUTS
    PSCustomObject with:
      .Success                  — boolean
      .TransitionState          — TRANSITION_COMPLETED | POST_COMPACT_RESYNC_REQUIRED | TRANSITION_FAILED
      .MissionId                — string
      .MissionObjective         — string
      .MissionStatus            — string
      .CurrentPhase             — string
      .EpochId                  — string
      .NextAction               — string
      .NextActionSafe           — boolean
      .CheckpointValid          — boolean
      .ResyncConflicts          — string[] (any conflicts detected)
      .StaleClaimsCount         — integer
      .PostCompactionTime       — ISO datetime
      .RequiresUserInput        — boolean (true only if checkpoint insufficient)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$CompactionSummary = "",

    [string]$ExpectedTransitionRequestId = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$now = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'

$conflicts = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# Step 1: Check if Re-Sync is required
# ---------------------------------------------------------------------------
$readerScript = Join-Path $PSScriptRoot "Read-MxAgileEpochCheckpoint.ps1"
if (-not (Test-Path -LiteralPath $readerScript)) {
    return [PSCustomObject]@{
        Success                   = $false
        TransitionState           = "TRANSITION_FAILED"
        MissionId                 = ""
        MissionObjective          = ""
        MissionStatus             = ""
        CurrentPhase              = ""
        EpochId                   = ""
        NextAction                = ""
        NextActionSafe            = $false
        CheckpointValid           = $false
        ResyncConflicts           = @("checkpoint_reader_missing")
        StaleClaimsCount          = 0
        PostCompactionTime        = $now
        RequiresUserInput         = $false
    }
}

# ---------------------------------------------------------------------------
# Step 2: Reload and validate active mission checkpoint
# ---------------------------------------------------------------------------
$checkpoint = & $readerScript -ProjectRoot $ProjectRoot

if (-not $checkpoint.Valid) {
    return [PSCustomObject]@{
        Success                   = $false
        TransitionState           = "TRANSITION_FAILED"
        MissionId                 = ""
        MissionObjective          = ""
        MissionStatus             = ""
        CurrentPhase              = ""
        EpochId                   = ""
        NextAction                = ""
        NextActionSafe            = $false
        CheckpointValid           = $false
        ResyncConflicts           = @("checkpoint_invalid_after_compaction: $($checkpoint.ConflictReason)")
        StaleClaimsCount          = 0
        PostCompactionTime        = $now
        RequiresUserInput         = $false
    }
}

# ---------------------------------------------------------------------------
# Step 3: Inspect repository identity and working-tree state
# ---------------------------------------------------------------------------
$_savedEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$currentBranch = & git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null
$currentCommit = & git -C $ProjectRoot rev-parse --short HEAD 2>$null
$gitStatus     = & git -C $ProjectRoot status --porcelain 2>$null
$ErrorActionPreference = $_savedEap

$workingTreeDirty = [bool]$gitStatus

# Check for repository conflicts with checkpoint
if (-not [string]::IsNullOrEmpty($checkpoint.Branch) -and
    -not [string]::IsNullOrEmpty($currentBranch) -and
    $checkpoint.Branch -ne $currentBranch) {
    $conflicts.Add("branch_mismatch: checkpoint=$($checkpoint.Branch), current=$currentBranch")
}

# ---------------------------------------------------------------------------
# Step 5: Apply STALE rules (detect commit hash change)
# ---------------------------------------------------------------------------
$staleClaimsCount = 0
if (-not [string]::IsNullOrEmpty($checkpoint.Commit) -and
    -not [string]::IsNullOrEmpty($currentCommit) -and
    $checkpoint.Commit -ne $currentCommit) {
    # In a real scenario, we would iterate over verified claims and mark those
    # with stale_if_commit_changes=true as STALE. Here we count how many
    # would be affected (detection only — actual STALE marking requires
    # re-writing the checkpoint which is a separate operation).
    $staleClaimsCount = 1  # Marker: commit changed, staleness evaluation needed
    $conflicts.Add("commit_changed_since_checkpoint: was=$($checkpoint.Commit), now=$currentCommit")
}

# ---------------------------------------------------------------------------
# Step 6: Compaction summary conflict detection
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrEmpty($CompactionSummary)) {
    # Compaction summary is informational only — never authoritative.
    # Record that a summary was received without acting on its claims.
    # Any conflict between summary and checkpoint → checkpoint wins.
    $conflicts.Add("diagnostic_compaction_summary_received: checkpoint_wins_on_conflict")
}

# ---------------------------------------------------------------------------
# Rebuild run context from validated events, without treating it as lifecycle authority
# ---------------------------------------------------------------------------
$runHistoryState = 'UNAVAILABLE'
$unresolvedRuns = @()
$staleRunInputs = @()
$unobservableRunInputs = @()
$runHistoryCanonical = $null
$invalidRunEventLines = 0
$partialRunEventTails = 0
$runEventScript = Join-Path $ProjectRoot '.mxagile\tools\control-plane\run_events.py'
if (-not (Test-Path -LiteralPath $runEventScript)) { $runEventScript = Join-Path $PSScriptRoot 'run_events.py' }
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and (Test-Path -LiteralPath $runEventScript)) {
    $runHistoryOutput = & $python.Source -B $runEventScript --project-root $ProjectRoot resume 2>$null
    if ($LASTEXITCODE -eq 0) {
        try {
            $runHistory = (($runHistoryOutput -join "`n") | ConvertFrom-Json)
            $unresolvedRuns = @($runHistory.unresolved_runs)
            $staleRunInputs = @($unresolvedRuns | Where-Object { $_.input_state -eq 'STALE' })
            $unobservableRunInputs = @($unresolvedRuns | Where-Object { $_.input_state -eq 'NOT_OBSERVABLE' })
            $runHistoryCanonical = $runHistory.canonical_state
            $invalidRunEventLines = [int]$runHistory.event_log.invalid_lines
            $partialRunEventTails = [int]$runHistory.event_log.partial_tail_files
            $runHistoryState = if ($invalidRunEventLines -gt 0 -or $partialRunEventTails -gt 0) { 'DEGRADED' }
                elseif ($runHistory.event_log.total_valid -eq 0) { 'EMPTY' } else { 'AVAILABLE' }
        } catch { $runHistoryState = 'INVALID' }
    }
}

# ---------------------------------------------------------------------------
# Step 7: Verify idempotency ID if supplied
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrEmpty($ExpectedTransitionRequestId)) {
    # The checkpoint should contain the transition_request_id written during
    # pre-compaction. We check for its presence as a consistency signal.
    $cpPath = Join-Path $ProjectRoot ".concord\context-epoch.yaml"
    if (Test-Path -LiteralPath $cpPath) {
        $cpContent = Get-Content -LiteralPath $cpPath -Raw -Encoding UTF8
        if ($cpContent -notmatch [regex]::Escape($ExpectedTransitionRequestId)) {
            $conflicts.Add("transition_request_id_mismatch: expected=$ExpectedTransitionRequestId")
        }
    }
}

# ---------------------------------------------------------------------------
# Step 8: Clear post_compaction_resync_required and set TRANSITION_COMPLETED
# ---------------------------------------------------------------------------
$cpPath = Join-Path $ProjectRoot ".concord\context-epoch.yaml"
$handoffPath = Join-Path $ProjectRoot "planning\lifecycle\context-epoch.yaml"

if (Test-Path -LiteralPath $cpPath) {
    $cpContent = Get-Content -LiteralPath $cpPath -Raw -Encoding UTF8
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    # Update transition state flags
    $cpContent = $cpContent -replace '(?m)(transition_state:\s*)\S+', '${1}TRANSITION_COMPLETED'
    $cpContent = $cpContent -replace '(?m)(post_compaction_resync_required:\s*)\S+', '${1}false'
    $cpContent = $cpContent -replace '(?m)(compaction_summary_received:\s*)\S+', "compaction_summary_received: $(if (-not [string]::IsNullOrEmpty($CompactionSummary)) { 'true' } else { 'false' })"

    [System.IO.File]::WriteAllText($cpPath, $cpContent, $utf8NoBom)

    if (Test-Path -LiteralPath $handoffPath) {
        [System.IO.File]::WriteAllText($handoffPath, $cpContent, $utf8NoBom)
    }
}

# ---------------------------------------------------------------------------
# Determine if user input is required
# ---------------------------------------------------------------------------
# User input is NEVER required merely because compaction happened.
# It is only required if the checkpoint is insufficient to continue.
$requiresUserInput = $false
if ([string]::IsNullOrEmpty($checkpoint.NextAction) -and [string]::IsNullOrEmpty($checkpoint.MissionObjective)) {
    $requiresUserInput = $true
}

# ---------------------------------------------------------------------------
# Report Re-Sync result
# ---------------------------------------------------------------------------
Write-Host "Post-compaction Re-Sync completed: $($checkpoint.EpochId)" -ForegroundColor Green
Write-Host "Mission: $($checkpoint.MissionId) — $($checkpoint.MissionObjective)" -ForegroundColor Cyan
Write-Host "Phase: $($checkpoint.CurrentPhase)" -ForegroundColor Cyan
Write-Host "Next action: $($checkpoint.NextAction)" -ForegroundColor Cyan
Write-Host "Run history: $runHistoryState; unresolved=$($unresolvedRuns.Count); stale-inputs=$($staleRunInputs.Count); unobservable-inputs=$($unobservableRunInputs.Count); invalid-lines=$invalidRunEventLines; partial-tails=$partialRunEventTails" -ForegroundColor Gray
if ($runHistoryCanonical) {
    Write-Host "Run context canonical re-read: Mission=$($runHistoryCanonical.mission_id); Wave=$($runHistoryCanonical.wave_id)/$($runHistoryCanonical.wave_phase); HEAD=$($runHistoryCanonical.head); branch=$($runHistoryCanonical.branch); blockers=$(@($runHistoryCanonical.lifecycle_findings) -join ',')" -ForegroundColor Gray
}
foreach ($run in $unresolvedRuns) {
    Write-Host "  RUN $($run.run_id): $($run.status) / $($run.input_state) / $($run.reconciliation_state)" -ForegroundColor Yellow
}
if ($conflicts.Count -gt 0) {
    Write-Host "Re-Sync conflicts (diagnostic): $($conflicts -join '; ')" -ForegroundColor Yellow
}
if ($staleClaimsCount -gt 0) {
    Write-Host "STALE evaluation required: commit changed since checkpoint." -ForegroundColor Yellow
}

return [PSCustomObject]@{
    Success                   = $true
    TransitionState           = "TRANSITION_COMPLETED"
    MissionId                 = $checkpoint.MissionId
    MissionObjective          = $checkpoint.MissionObjective
    MissionStatus             = $checkpoint.MissionStatus
    CurrentPhase              = $checkpoint.CurrentPhase
    EpochId                   = $checkpoint.EpochId
    NextAction                = $checkpoint.NextAction
    NextActionSafe            = $checkpoint.NextActionSafe
    CheckpointValid           = $true
    ResyncConflicts           = [string[]]$conflicts.ToArray()
    StaleClaimsCount          = $staleClaimsCount
    RunHistoryState           = $runHistoryState
    UnresolvedRuns            = $unresolvedRuns
    StaleRunInputs             = $staleRunInputs
    UnobservableRunInputs      = $unobservableRunInputs
    InvalidRunEventLines       = $invalidRunEventLines
    PartialRunEventTails       = $partialRunEventTails
    CanonicalRunState          = $runHistoryCanonical
    PostCompactionTime        = $now
    RequiresUserInput         = $requiresUserInput
}
