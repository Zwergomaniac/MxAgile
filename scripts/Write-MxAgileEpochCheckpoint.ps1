<#
.SYNOPSIS
    Writes a durable MxAgile Context Epoch checkpoint.

.DESCRIPTION
    Reads actual repository identity, branch, commit and dirty state.
    Optionally reads planning/lifecycle/process-state.yaml for current phase.
    Preserves existing evidence from prior checkpoint when -PreserveEvidence is set.
    Writes atomically: temp file first, validate required fields, then rename.
    Does not store secrets, credentials, or sensitive values.

    Primary operational store: .concord/context-epoch.yaml (gitignored).
    Explicit handoff copy:     planning/lifecycle/context-epoch.yaml  (git-tracked).
    Use -WriteHandoffCopy to create the handoff copy intentionally.

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER MissionId
    Unique mission identifier, e.g. MISSION-2026-W01-CTX.

.PARAMETER MissionObjective
    One-sentence mission goal.

.PARAMETER MissionStatus
    active | paused | interrupted | complete | failed

.PARAMETER Wave
    MxAgile wave, e.g. W01. Auto-detected from process-state.yaml if omitted.

.PARAMETER CurrentPhase
    MxAgile lifecycle phase. Auto-detected from process-state.yaml if omitted.

.PARAMETER EpochId
    Current epoch identifier, e.g. EPOCH-001.

.PARAMETER RolloverReason
    Why this epoch was started (initial_epoch | manual_rollover | ...).

.PARAMETER NextAction
    Human-readable description of the next safe action.

.PARAMETER NextActionSafe
    True if the next action can run without additional confirmation.

.PARAMETER NextChecklistItem
    Specific checklist item to resume from, e.g. W01-03.

.PARAMETER HotContextSummary
    1-3 sentence HOT context summary. Must not contain COLD evidence.

.PARAMETER VerifiedClaimsYaml
    Optional pre-formatted YAML block (list items, 2-space indent) for verified claims.

.PARAMETER FailedClaimsYaml
    Optional pre-formatted YAML block for failed claims.

.PARAMETER UnverifiedClaimsYaml
    Optional pre-formatted YAML block for unverified claims.

.PARAMETER DecisionsYaml
    Optional pre-formatted YAML block for decisions.

.PARAMETER PreserveEvidence
    If set, reads existing checkpoint and carries forward its evidence arrays.
    Parameters VerifiedClaimsYaml/FailedClaimsYaml/UnverifiedClaimsYaml/DecisionsYaml
    override specific sections; the rest are inherited from the existing checkpoint.

.PARAMETER WriteHandoffCopy
    Also writes planning/lifecycle/context-epoch.yaml (git-tracked handoff copy).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [string]$MissionId          = "",
    [string]$MissionObjective   = "MxAgile mission",
    [string]$MissionStatus      = "active",
    [string]$Wave               = "",
    [string]$CurrentPhase       = "",
    [string]$EpochId            = "EPOCH-001",
    [string]$RolloverReason     = "initial_epoch",
    [string]$NextAction         = "Re-sync and resume",
    [bool]$NextActionSafe       = $false,
    [string]$NextChecklistItem  = "",
    [string]$HotContextSummary  = "",

    [string]$VerifiedClaimsYaml   = "",
    [string]$FailedClaimsYaml     = "",
    [string]$UnverifiedClaimsYaml = "",
    [string]$DecisionsYaml        = "",

    [switch]$PreserveEvidence,
    [switch]$WriteHandoffCopy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "ProjectRoot not found: $ProjectRoot"
}

# ---------------------------------------------------------------------------
# Helper: escape a value for a YAML double-quoted scalar
# ---------------------------------------------------------------------------
function Format-YamlStr {
    param([string]$val)
    if ([string]::IsNullOrEmpty($val)) { return '""' }
    $esc = $val -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", ''
    return """$esc"""
}

# ---------------------------------------------------------------------------
# Read git state (best-effort; never throws on missing git)
# ---------------------------------------------------------------------------
$branch      = "unknown"
$commit      = "unknown"
$workingTree = "unknown"
$repoId      = ""

# Git calls: use Continue locally so native-command stderr never throws.
$_savedEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$b = & git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $b) { $branch = ($b | Out-String).Trim() }

$c = & git -C $ProjectRoot rev-parse --short HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $c) { $commit = ($c | Out-String).Trim() }

$d = & git -C $ProjectRoot status --porcelain 2>$null
if ($LASTEXITCODE -eq 0) { $workingTree = if ($d) { "dirty" } else { "clean" } }

$r = & git -C $ProjectRoot remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $r) { $repoId = ($r | Out-String).Trim() }

$ErrorActionPreference = $_savedEap

# ---------------------------------------------------------------------------
# Auto-detect phase and wave from process-state.yaml
# ---------------------------------------------------------------------------
$detectedPhase = if ([string]::IsNullOrEmpty($CurrentPhase)) { "unknown" } else { $CurrentPhase }
$detectedWave  = $Wave

$processStatePath = Join-Path $ProjectRoot "planning\lifecycle\process-state.yaml"
if ((([string]::IsNullOrEmpty($CurrentPhase)) -or ([string]::IsNullOrEmpty($Wave))) -and
    (Test-Path -LiteralPath $processStatePath)) {
    $psContent = Get-Content -LiteralPath $processStatePath -Raw -Encoding UTF8
    if ([string]::IsNullOrEmpty($Wave) -and $psContent -match '(?m)^(W\d+):') {
        $detectedWave = $Matches[1]
    }
    $wk = if ([string]::IsNullOrEmpty($detectedWave)) { '' } else { $detectedWave }
    if ([string]::IsNullOrEmpty($CurrentPhase) -and
        $psContent -match "(?m)^\s+phase:\s+(discovery|refinement|ready|implementing|verifying|done)") {
        $detectedPhase = $Matches[1]
    }
}

# ---------------------------------------------------------------------------
# Preserve existing evidence from prior checkpoint
# ---------------------------------------------------------------------------
$existingVerified   = $VerifiedClaimsYaml
$existingFailed     = $FailedClaimsYaml
$existingUnverified = $UnverifiedClaimsYaml
$existingDecisions  = $DecisionsYaml

if ($PreserveEvidence) {
    $existingPaths = @(
        (Join-Path $ProjectRoot ".concord\context-epoch.yaml"),
        (Join-Path $ProjectRoot "planning\lifecycle\context-epoch.yaml")
    )
    foreach ($ep in $existingPaths) {
        if (Test-Path -LiteralPath $ep) {
            $ec = Get-Content -LiteralPath $ep -Raw -Encoding UTF8
            if ([string]::IsNullOrEmpty($existingVerified))   { $existingVerified   = Extract-YamlBlock $ec 'verified' }
            if ([string]::IsNullOrEmpty($existingFailed))     { $existingFailed     = Extract-YamlBlock $ec 'failed' }
            if ([string]::IsNullOrEmpty($existingUnverified)) { $existingUnverified = Extract-YamlBlock $ec 'unverified' }
            if ([string]::IsNullOrEmpty($existingDecisions))  { $existingDecisions  = Extract-YamlBlock $ec 'decisions' }
            break
        }
    }
}

# ---------------------------------------------------------------------------
# Read config feature controls
# ---------------------------------------------------------------------------
$featureEnabled          = $false
$checkpointResumeEnabled = $false
$manualRolloverEnabled   = $false
$pressureRecsEnabled     = $false
$autoRolloverEnabled     = $false

$configPath = Join-Path $ProjectRoot ".mxagile\config.yaml"
if (Test-Path -LiteralPath $configPath) {
    $cfgRaw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    if ($cfgRaw -match '(?m)^\s*enabled:\s*true')              { $featureEnabled          = $true }
    if ($cfgRaw -match '(?m)^\s*checkpoint_resume:\s*true')    { $checkpointResumeEnabled = $true }
    if ($cfgRaw -match '(?m)^\s*manual_rollover:\s*true')      { $manualRolloverEnabled   = $true }
    if ($cfgRaw -match '(?m)^\s*pressure_recommendations:\s*true') { $pressureRecsEnabled = $true }
    if ($cfgRaw -match '(?m)^\s*auto_rollover:\s*true')        { $autoRolloverEnabled     = $true }
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($MissionId)) {
    $MissionId = "MISSION-$(Get-Date -Format 'yyyy-MM-dd')"
}
$now     = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
$today   = Get-Date -Format 'yyyy-MM-dd'

# YAML field helpers
$missionIdQ      = Format-YamlStr $MissionId
$missionObjQ     = Format-YamlStr $MissionObjective
$repoIdQ         = Format-YamlStr $repoId
$branchQ         = Format-YamlStr $branch
$commitQ         = Format-YamlStr $commit
$nextActionQ     = Format-YamlStr $NextAction
$hotSummaryQ     = Format-YamlStr $HotContextSummary
$checklistItemQ  = Format-YamlStr $NextChecklistItem
$safeStr         = if ($NextActionSafe) { 'true' } else { 'false' }
$featureEnabledStr     = if ($featureEnabled)          { 'true' } else { 'false' }
$cpResumeStr           = if ($checkpointResumeEnabled) { 'true' } else { 'false' }
$manualRolloverStr     = if ($manualRolloverEnabled)   { 'true' } else { 'false' }
$pressureRecsStr       = if ($pressureRecsEnabled)     { 'true' } else { 'false' }
$autoRolloverStr       = if ($autoRolloverEnabled)     { 'true' } else { 'false' }

# Format evidence blocks (empty list vs. populated list)
function Format-ClaimsBlock {
    param([string]$yaml, [string]$key)
    if ([string]::IsNullOrEmpty($yaml)) {
        return "${key}: []"
    }
    # yaml is a pre-formatted block of list items
    return "${key}:`n$yaml"
}

$verifiedBlock   = Format-ClaimsBlock $existingVerified   'verified'
$failedBlock     = Format-ClaimsBlock $existingFailed     'failed'
$unverifiedBlock = Format-ClaimsBlock $existingUnverified 'unverified'
$decisionsBlock  = Format-ClaimsBlock $existingDecisions  'decisions'

$waveStr = if ([string]::IsNullOrEmpty($detectedWave)) { '' } else { "`n  wave: $detectedWave" }
$checklistStr = ''
if (-not [string]::IsNullOrEmpty($NextChecklistItem)) {
    $checklistStr = "`n  checklist_item: $checklistItemQ"
}

# ---------------------------------------------------------------------------
# Build YAML content
# ---------------------------------------------------------------------------
$yaml = @"
schema_version: "1.0"

mission:
  id: $missionIdQ
  objective: $missionObjQ
  status: $MissionStatus
  started: "$today"$waveStr

scope:
  project: $(Format-YamlStr $ProjectRoot)

lifecycle:
  current_phase: $detectedPhase
  active_context_epoch: $EpochId
  interrupted: false

repository:
  repository_identity: $repoIdQ
  branch: $branchQ
  commit: $commitQ
  working_tree_state: $workingTree
  checkpoint_time: "$now"

$verifiedBlock

$failedBlock

$unverifiedBlock

$decisionsBlock

open_gates: []

user_overrides: []

artifacts: []

next_action:
  description: $nextActionQ
  safe_to_run: $safeStr
  prerequisites: []$checklistStr

context:
  epoch_id: $EpochId
  rollover_reason: $RolloverReason
  pressure_state: UNKNOWN
  context_token_source: unknown
  hot_context_summary: $hotSummaryQ
  epoch_started: "$now"
  feature_controls_at_checkpoint:
    enabled: $featureEnabledStr
    checkpoint_resume: $cpResumeStr
    manual_rollover: $manualRolloverStr
    pressure_recommendations: $pressureRecsStr
    auto_rollover: $autoRolloverStr
"@

# ---------------------------------------------------------------------------
# Write atomically: temp file -> validate -> rename
# ---------------------------------------------------------------------------
$concordDir = Join-Path $ProjectRoot ".concord"
if (-not (Test-Path -LiteralPath $concordDir -PathType Container)) {
    New-Item -ItemType Directory -Path $concordDir -Force | Out-Null
}

$targetPath = Join-Path $concordDir "context-epoch.yaml"
$tmpPath    = Join-Path $concordDir "context-epoch.yaml.tmp"

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($tmpPath, $yaml, $utf8NoBom)

# Validate required fields exist in tmp before committing
$written = Get-Content -LiteralPath $tmpPath -Raw -Encoding UTF8
$requiredFields = @('schema_version', 'mission:', 'scope:', 'lifecycle:', 'repository:', 'context:')
foreach ($field in $requiredFields) {
    if ($written -notmatch [regex]::Escape($field)) {
        Remove-Item -LiteralPath $tmpPath -Force
        throw "Checkpoint validation failed: required field '$field' not found in output. Tmp file removed."
    }
}

# Atomic rename: replace target with tmp
if (Test-Path -LiteralPath $targetPath) {
    Remove-Item -LiteralPath $targetPath -Force
}
Move-Item -LiteralPath $tmpPath -Destination $targetPath -Force

Write-Host "Checkpoint written: $targetPath" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Optional: handoff copy to planning/lifecycle/
# ---------------------------------------------------------------------------
if ($WriteHandoffCopy) {
    $handoffDir = Join-Path $ProjectRoot "planning\lifecycle"
    if (-not (Test-Path -LiteralPath $handoffDir -PathType Container)) {
        New-Item -ItemType Directory -Path $handoffDir -Force | Out-Null
    }
    $handoffPath = Join-Path $handoffDir "context-epoch.yaml"
    [System.IO.File]::WriteAllText($handoffPath, $yaml, $utf8NoBom)
    Write-Host "Handoff copy written: $handoffPath" -ForegroundColor Cyan
}
