<#
.SYNOPSIS
    Reads and validates a MxAgile Context Epoch checkpoint.

.DESCRIPTION
    Loads context-epoch.yaml from the operational store (.concord/) or,
    as fallback, the handoff store (planning/lifecycle/).
    Validates schema_version and required fields.
    Returns a PSCustomObject with all checkpoint fields, or throws on error.

    Evidence states (VERIFIED/FAILED/UNVERIFIED/STALE/SUPERSEDED) are
    preserved verbatim — this reader does not upgrade or downgrade any state.

    UNKNOWN pressure state is returned as-is; callers must not treat it as NORMAL.

.PARAMETER ProjectRoot
    Absolute path to the project root.

.OUTPUTS
    PSCustomObject with:
      .Valid           — boolean
      .Path            — path of file read
      .SchemaVersion   — "1.0" (or other)
      .MissionId       — string
      .MissionStatus   — string
      .MissionObjective — string
      .CurrentPhase    — string
      .EpochId         — string
      .Branch          — string
      .Commit          — string
      .WorkingTreeState — string
      .CheckpointTime  — string
      .PressureState   — string (UNKNOWN | NORMAL | PRESSURE | ...)
      .NextAction      — string
      .NextActionSafe  — bool
      .RawYaml         — full YAML text (for downstream processing)
      .ConflictReason  — set when Valid=false
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

# ---------------------------------------------------------------------------
# Locate checkpoint file (operational store preferred, handoff store fallback)
# ---------------------------------------------------------------------------
$candidatePaths = @(
    (Join-Path $ProjectRoot ".concord\context-epoch.yaml"),
    (Join-Path $ProjectRoot "planning\lifecycle\context-epoch.yaml")
)

$checkpointPath = $null
foreach ($p in $candidatePaths) {
    if (Test-Path -LiteralPath $p) {
        $checkpointPath = $p
        break
    }
}

if ($null -eq $checkpointPath) {
    return [PSCustomObject]@{
        Valid          = $false
        Path           = $null
        ConflictReason = "No checkpoint found. Checked: $($candidatePaths -join '; ')"
    }
}

# ---------------------------------------------------------------------------
# Read and basic-validate
# ---------------------------------------------------------------------------
$raw = $null
try {
    $raw = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8
} catch {
    return [PSCustomObject]@{
        Valid          = $false
        Path           = $checkpointPath
        ConflictReason = "Cannot read checkpoint file: $_"
    }
}

if ([string]::IsNullOrWhiteSpace($raw)) {
    return [PSCustomObject]@{
        Valid          = $false
        Path           = $checkpointPath
        ConflictReason = "Checkpoint file is empty."
    }
}

# Require schema_version first (version guard before reading further)
if ($raw -notmatch 'schema_version:\s*"([^"]+)"') {
    return [PSCustomObject]@{
        Valid          = $false
        Path           = $checkpointPath
        RawYaml        = $raw
        ConflictReason = "Missing schema_version field. Checkpoint may be malformed."
    }
}
$schemaVersion = $Matches[1]

if ($schemaVersion -ne "1.0") {
    return [PSCustomObject]@{
        Valid          = $false
        Path           = $checkpointPath
        SchemaVersion  = $schemaVersion
        RawYaml        = $raw
        ConflictReason = "Unsupported schema_version '$schemaVersion'. Manual migration required. Do not read further."
    }
}

# Required top-level sections
$requiredSections = @('mission:', 'scope:', 'lifecycle:', 'repository:', 'context:')
foreach ($sec in $requiredSections) {
    if ($raw -notmatch [regex]::Escape($sec)) {
        return [PSCustomObject]@{
            Valid          = $false
            Path           = $checkpointPath
            SchemaVersion  = $schemaVersion
            RawYaml        = $raw
            ConflictReason = "Required section '$sec' not found. Checkpoint is malformed."
        }
    }
}

# ---------------------------------------------------------------------------
# Extract scalar fields via regex (YAML simple scalars and quoted strings)
# ---------------------------------------------------------------------------
function Get-YamlScalar {
    param([string]$content, [string]$key)
    # Match: key: "value" or key: value (unquoted)
    if ($content -match "(?m)^\s+${key}:\s+`"([^`"]*)`"") { return $Matches[1] }
    if ($content -match "(?m)^\s+${key}:\s+(\S[^\r\n]*)") { return $Matches[1].Trim() }
    return ""
}

$missionId        = Get-YamlScalar $raw 'id'
$missionStatus    = Get-YamlScalar $raw 'status'
$missionObjective = Get-YamlScalar $raw 'objective'
$currentPhase     = Get-YamlScalar $raw 'current_phase'
$epochId          = Get-YamlScalar $raw 'epoch_id'
$branch           = Get-YamlScalar $raw 'branch'
$commit           = Get-YamlScalar $raw 'commit'
$workingTreeState = Get-YamlScalar $raw 'working_tree_state'
$checkpointTime   = Get-YamlScalar $raw 'checkpoint_time'
$pressureState    = Get-YamlScalar $raw 'pressure_state'
$nextActionDesc   = Get-YamlScalar $raw 'description'
$safeToRun        = (Get-YamlScalar $raw 'safe_to_run') -eq 'true'

if ([string]::IsNullOrEmpty($pressureState)) { $pressureState = "UNKNOWN" }

# ---------------------------------------------------------------------------
# Return validated result
# ---------------------------------------------------------------------------
return [PSCustomObject]@{
    Valid             = $true
    Path              = $checkpointPath
    SchemaVersion     = $schemaVersion
    MissionId         = $missionId
    MissionStatus     = $missionStatus
    MissionObjective  = $missionObjective
    CurrentPhase      = $currentPhase
    EpochId           = $epochId
    Branch            = $branch
    Commit            = $commit
    WorkingTreeState  = $workingTreeState
    CheckpointTime    = $checkpointTime
    PressureState     = $pressureState
    NextAction        = $nextActionDesc
    NextActionSafe    = $safeToRun
    RawYaml           = $raw
    ConflictReason    = ""
}
