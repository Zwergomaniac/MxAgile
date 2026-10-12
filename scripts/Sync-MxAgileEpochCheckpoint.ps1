<#
.SYNOPSIS
    Re-synchronizes a MxAgile Context Epoch checkpoint against actual repository state.

.DESCRIPTION
    Implements the 14-step re-synchronization protocol from:
    .mxagile/policies/context-lifecycle.md

    Steps performed by this script:
      1.  Load durable resume contract (.concord/context-epoch.yaml or planning/lifecycle fallback)
      2.  Validate schema_version — reject unknown versions safely
      3.  Read current repository identity, branch and commit
      4.  Compare checkpoint branch/commit against current state
      5.  Detect working-tree dirty state
      6.  Check referenced artifacts exist (best-effort for relative paths)
      7.  Mark STALE: verified claims with stale_if_commit_changes: true when commit changed
      8.  Preserve FAILED and UNVERIFIED states — never upgrade them
      9.  Write updated checkpoint atomically if any claims were marked STALE
     10.  Return deterministic sync result

    Evidence state invariants preserved:
      - FAILED stays FAILED (not resolved by sync)
      - UNVERIFIED stays UNVERIFIED (never upgraded to VERIFIED by sync)
      - STALE replaces VERIFIED only when stale_if_commit_changes: true AND commit changed

    Returns a PSCustomObject with sync result. Does not throw on conflict;
    instead sets SyncOk=false with ConflictType describing the issue.

.PARAMETER ProjectRoot
    Absolute path to the project root.
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
# Step 1-2: Load and validate checkpoint via reader
# ---------------------------------------------------------------------------
$readerScript = Join-Path $PSScriptRoot "Read-MxAgileEpochCheckpoint.ps1"
if (-not (Test-Path -LiteralPath $readerScript)) {
    throw "Read-MxAgileEpochCheckpoint.ps1 not found in $PSScriptRoot"
}

$checkpoint = & $readerScript -ProjectRoot $ProjectRoot

if (-not $checkpoint.Valid) {
    return [PSCustomObject]@{
        SyncOk          = $false
        ConflictType    = "checkpoint_invalid"
        ConflictDetail  = $checkpoint.ConflictReason
        StaleClaimCount = 0
        CheckpointPath  = $checkpoint.Path
        ResumeAction    = "Resolve checkpoint conflict before resuming: $($checkpoint.ConflictReason)"
    }
}

# ---------------------------------------------------------------------------
# Step 3-4: Read current repository state and compare
# ---------------------------------------------------------------------------
$currentBranch = "unknown"
$currentCommit = "unknown"
$currentDirty  = "unknown"

$_savedEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$b = & git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $b) { $currentBranch = ($b | Out-String).Trim() }

$c = & git -C $ProjectRoot rev-parse --short HEAD 2>$null
if ($LASTEXITCODE -eq 0 -and $c) { $currentCommit = ($c | Out-String).Trim() }

$ds = & git -C $ProjectRoot status --porcelain 2>$null
if ($LASTEXITCODE -eq 0) { $currentDirty = if ($ds) { "dirty" } else { "clean" } }

$ErrorActionPreference = $_savedEap

$checkpointBranch = $checkpoint.Branch
$checkpointCommit = $checkpoint.Commit
$commitChanged    = ($checkpointCommit -ne "unknown") -and ($currentCommit -ne "unknown") -and ($checkpointCommit -ne $currentCommit)
$branchChanged    = ($checkpointBranch -ne "unknown") -and ($currentBranch -ne "unknown") -and ($checkpointBranch -ne $currentBranch)

# ---------------------------------------------------------------------------
# Step 6: Check referenced artifact paths (best-effort)
# ---------------------------------------------------------------------------
$missingArtifacts = @()
$raw = $checkpoint.RawYaml
if ($raw -match '(?m)path_or_reference:\s+"?([^"\r\n]+)"?') {
    # Multiple matches
    $artMatches = [regex]::Matches($raw, '(?m)path_or_reference:\s+"?([^"#\r\n]+)"?')
    foreach ($m in $artMatches) {
        $artifactPath = $m.Groups[1].Value.Trim()
        # Only check local relative paths (not URLs, not # fragments)
        if ($artifactPath -notmatch '^https?://' -and $artifactPath -notmatch '#') {
            $fullArtifactPath = Join-Path $ProjectRoot $artifactPath
            if (-not (Test-Path -LiteralPath $fullArtifactPath)) {
                $missingArtifacts += $artifactPath
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Step 7: Mark STALE — claims with stale_if_commit_changes: true when commit changed
# ---------------------------------------------------------------------------
$staleClaimCount = 0
$updatedYaml     = $raw

if ($commitChanged) {
    # Pattern: within a verified claim block, find evidence_state: VERIFIED followed by
    # stale_if_commit_changes: true (both fields appear with 2-space or 4-space indent,
    # as written by Write-MxAgileEpochCheckpoint.ps1).
    # Strategy: split by claim boundaries (list items), check each block, replace if needed.

    $lines      = $updatedYaml -split "`r?`n"
    $resultLines = [System.Collections.Generic.List[string]]::new()
    $inClaim     = $false
    $claimLines  = [System.Collections.Generic.List[string]]::new()
    $hasStale    = $false
    $hasVerified = $false

    foreach ($line in $lines) {
        # Detect start of a list item (claim) — "- claim:" with optional indentation
        if ($line -match '^\s*-\s+claim:') {
            # Flush previous claim block
            if ($inClaim -and $claimLines.Count -gt 0) {
                if ($hasStale -and $hasVerified) {
                    # Replace evidence_state: VERIFIED with STALE in this block
                    $blockText = ($claimLines | Out-String)
                    $blockText = $blockText -replace '(\s+evidence_state:\s+)VERIFIED', '${1}STALE'
                    $staleClaimCount++
                    $resultLines.Add($blockText.TrimEnd("`r`n"))
                } else {
                    foreach ($cl in $claimLines) { $resultLines.Add($cl) }
                }
            }
            $claimLines  = [System.Collections.Generic.List[string]]::new()
            $hasStale    = $false
            $hasVerified = $false
            $inClaim     = $true
        }

        if ($inClaim) {
            $claimLines.Add($line)
            if ($line -match 'evidence_state:\s+VERIFIED') { $hasVerified = $true }
            if ($line -match 'stale_if_commit_changes:\s+true') { $hasStale = $true }
        } else {
            $resultLines.Add($line)
        }
    }

    # Flush final claim block
    if ($inClaim -and $claimLines.Count -gt 0) {
        if ($hasStale -and $hasVerified) {
            $blockText = ($claimLines | Out-String)
            $blockText = $blockText -replace '(\s+evidence_state:\s+)VERIFIED', '${1}STALE'
            $staleClaimCount++
            $resultLines.Add($blockText.TrimEnd("`r`n"))
        } else {
            foreach ($cl in $claimLines) { $resultLines.Add($cl) }
        }
    }

    $updatedYaml = ($resultLines | Out-String).TrimEnd()
}

# ---------------------------------------------------------------------------
# Step 5, 8: Preserve all non-VERIFIED states (FAILED and UNVERIFIED must not change)
# The line-by-line approach above only modifies VERIFIED claims with stale_if_commit_changes.
# FAILED and UNVERIFIED lines are untouched.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Step 9: Write updated checkpoint atomically if anything changed
# ---------------------------------------------------------------------------
if ($staleClaimCount -gt 0) {
    $concordDir = Join-Path $ProjectRoot ".concord"
    if (-not (Test-Path -LiteralPath $concordDir -PathType Container)) {
        New-Item -ItemType Directory -Path $concordDir -Force | Out-Null
    }
    $targetPath = Join-Path $concordDir "context-epoch.yaml"
    $tmpPath    = Join-Path $concordDir "context-epoch.yaml.tmp"

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tmpPath, $updatedYaml, $utf8NoBom)

    if (Test-Path -LiteralPath $targetPath) {
        Remove-Item -LiteralPath $targetPath -Force
    }
    Move-Item -LiteralPath $tmpPath -Destination $targetPath -Force

    Write-Host "Sync: $staleClaimCount claim(s) marked STALE (commit $checkpointCommit -> $currentCommit). Checkpoint updated." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 10: Determine resume action and conflict type
# ---------------------------------------------------------------------------
$conflictType = $null
$conflictDetail = ""

if ($branchChanged) {
    $conflictType   = "branch_diverged"
    $conflictDetail = "Checkpoint branch '$checkpointBranch' != current branch '$currentBranch'. Do not continue blindly."
} elseif ($missingArtifacts.Count -gt 0) {
    $conflictType   = "missing_artifacts"
    $conflictDetail = "Artifact paths not found: $($missingArtifacts -join ', ')"
}

$resumeAction = $checkpoint.NextAction
if ($null -ne $conflictType) {
    $resumeAction = "Resolve conflict ($conflictType) before resuming. Detail: $conflictDetail"
}

return [PSCustomObject]@{
    SyncOk              = ($null -eq $conflictType)
    ConflictType        = $conflictType
    ConflictDetail      = $conflictDetail
    CheckpointBranch    = $checkpointBranch
    CurrentBranch       = $currentBranch
    CheckpointCommit    = $checkpointCommit
    CurrentCommit       = $currentCommit
    CommitChanged       = $commitChanged
    CurrentDirtyState   = $currentDirty
    StaleClaimCount     = $staleClaimCount
    MissingArtifacts    = $missingArtifacts
    CheckpointPath      = $checkpoint.Path
    EpochId             = $checkpoint.EpochId
    CurrentPhase        = $checkpoint.CurrentPhase
    PressureState       = $checkpoint.PressureState
    ResumeAction        = $resumeAction
}
