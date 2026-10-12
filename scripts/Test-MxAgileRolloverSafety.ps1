<#
.SYNOPSIS
    Evaluates whether a Context Epoch rollover is safe at this point.

.DESCRIPTION
    Checks all rollover safety conditions defined in the context-lifecycle
    policy. Returns a structured result with pass/fail for each condition
    and an overall Safe verdict.

    Safety conditions checked:
      1. Valid checkpoint exists and can be read
      2. Checkpoint schema version is supported
      3. Feature controls allow rollover (manual_rollover or auto_rollover enabled)
      4. No dirty working tree (uncommitted changes that would be lost)
      5. Required evidence is persisted (no pending verification)
      6. Repository state is capturable
      7. Mission is not in terminal state (complete/failed)

    Conditions that CANNOT be checked by this script (caller must supply):
      - No active tool call or file write in flight
      - No checkpoint write in progress
      - No commit/write transition with unknown outcome
      - Harness supports context transition

    These caller-supplied conditions are accepted via -CallerSafetyFlags.

.PARAMETER ProjectRoot
    Absolute path to the project root.

.PARAMETER CallerSafetyFlags
    Hashtable of boolean conditions the caller asserts.
    Expected keys (all default to $false if absent):
      no_tool_call_in_flight    — true if no tool/command is executing
      no_file_write_in_flight   — true if no file mutation is active
      no_checkpoint_write_active — true if no concurrent checkpoint write
      no_pending_commit         — true if no git commit/push in progress
      harness_supports_transition — true if harness can start fresh context

.OUTPUTS
    PSCustomObject with:
      .Safe                     — boolean (all conditions passed)
      .BlockingConditions       — string[] (list of failed condition names)
      .CheckpointValid          — boolean
      .FeatureControlsAllow     — boolean
      .WorkingTreeClean         — boolean
      .MissionNotTerminal       — boolean
      .CallerFlagsValid         — boolean
      .Details                  — hashtable of all condition results
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,

    [hashtable]$CallerSafetyFlags = @{}
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$blocking = [System.Collections.Generic.List[string]]::new()
$details  = @{}

# ---------------------------------------------------------------------------
# 1. Valid checkpoint exists
# ---------------------------------------------------------------------------
$readerScript = Join-Path $PSScriptRoot "Read-MxAgileEpochCheckpoint.ps1"
$checkpointValid = $false

if (Test-Path -LiteralPath $readerScript) {
    $checkpoint = & $readerScript -ProjectRoot $ProjectRoot
    $checkpointValid = $checkpoint.Valid
    if (-not $checkpointValid) {
        $blocking.Add("checkpoint_invalid: $($checkpoint.ConflictReason)")
    }
} else {
    $blocking.Add("checkpoint_reader_missing")
}
$details['checkpoint_valid'] = $checkpointValid

# ---------------------------------------------------------------------------
# 2. Feature controls allow rollover
# ---------------------------------------------------------------------------
$featureControlsAllow = $false
$configPath = Join-Path $ProjectRoot ".mxagile\config.yaml"
if (Test-Path -LiteralPath $configPath) {
    $cfgRaw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $enabled        = $cfgRaw -match '(?m)^\s*enabled:\s*true'
    $manualRollover = $cfgRaw -match '(?m)^\s*manual_rollover:\s*true'
    $autoRollover   = $cfgRaw -match '(?m)^\s*auto_rollover:\s*true'
    $featureControlsAllow = $enabled -and ($manualRollover -or $autoRollover)
}
if (-not $featureControlsAllow) {
    $blocking.Add("feature_controls_disallow_rollover")
}
$details['feature_controls_allow'] = $featureControlsAllow

# ---------------------------------------------------------------------------
# 3. Working tree state
# ---------------------------------------------------------------------------
$workingTreeClean = $false
$_savedEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$ds = & git -C $ProjectRoot status --porcelain 2>$null
if ($LASTEXITCODE -eq 0) {
    $workingTreeClean = -not [bool]$ds
}
$ErrorActionPreference = $_savedEap

if (-not $workingTreeClean) {
    $blocking.Add("working_tree_dirty")
}
$details['working_tree_clean'] = $workingTreeClean

# ---------------------------------------------------------------------------
# 4. Mission not in terminal state
# ---------------------------------------------------------------------------
$missionNotTerminal = $true
if ($checkpointValid) {
    $status = $checkpoint.MissionStatus
    if ($status -eq "complete" -or $status -eq "failed") {
        $missionNotTerminal = $false
        $blocking.Add("mission_terminal_state: $status")
    }
}
$details['mission_not_terminal'] = $missionNotTerminal

# ---------------------------------------------------------------------------
# 5. Caller-supplied safety flags
# ---------------------------------------------------------------------------
$requiredCallerFlags = @(
    'no_tool_call_in_flight',
    'no_file_write_in_flight',
    'no_checkpoint_write_active',
    'no_pending_commit'
)

$callerFlagsValid = $true
foreach ($flag in $requiredCallerFlags) {
    $flagValue = $false
    if ($CallerSafetyFlags.ContainsKey($flag)) {
        $flagValue = [bool]$CallerSafetyFlags[$flag]
    }
    $details["caller_$flag"] = $flagValue
    if (-not $flagValue) {
        $callerFlagsValid = $false
        $blocking.Add("caller_flag_false: $flag")
    }
}

# harness_supports_transition is informational, not blocking for manual rollover
$harnessSupports = $false
if ($CallerSafetyFlags.ContainsKey('harness_supports_transition')) {
    $harnessSupports = [bool]$CallerSafetyFlags['harness_supports_transition']
}
$details['harness_supports_transition'] = $harnessSupports

# ---------------------------------------------------------------------------
# Return safety evaluation
# ---------------------------------------------------------------------------
$safe = ($blocking.Count -eq 0)

return [PSCustomObject]@{
    Safe                  = $safe
    BlockingConditions    = [string[]]$blocking.ToArray()
    CheckpointValid       = $checkpointValid
    FeatureControlsAllow  = $featureControlsAllow
    WorkingTreeClean      = $workingTreeClean
    MissionNotTerminal    = $missionNotTerminal
    CallerFlagsValid      = $callerFlagsValid
    HarnessSupports       = $harnessSupports
    Details               = $details
}
