<#
.SYNOPSIS
    Context Lifecycle - Operational Roundtrip Tests (Layer 1/Tier 1)

.DESCRIPTION
    Proves the operational checkpoint/resume path with actual script execution.

    A. Write/read roundtrip    — writer creates valid checkpoint; reader returns correct fields
    B. Atomic-write safety     — .tmp file never read; prior checkpoint survives corrupted .tmp
    C. Repository re-sync      — stale_if_commit_changes claims become STALE after commit change
    D. Evidence preservation   — VERIFIED/FAILED/UNVERIFIED states unchanged when commit same
    E. Pressure UNKNOWN        — missing measurement => pressure_state UNKNOWN
    F. Fresh-context simulation — subprocess reads checkpoint written in parent; fields accessible

    Tests use GUID temp directories in $env:TEMP. All git operations use a local
    git repo initialized in the temp directory. No network, no mxcli, no shared state.

    Documented harness gap (see F): a live harness restart (new Claude session starting
    from only the checkpoint and repo instructions) cannot be automated here. The
    subprocess simulation verifies file persistence and reader correctness; it does not
    verify full agent context re-hydration from a clean harness start.
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

$writerScript = Join-Path $ScriptDir "scripts\Write-MxAgileEpochCheckpoint.ps1"
$readerScript = Join-Path $ScriptDir "scripts\Read-MxAgileEpochCheckpoint.ps1"
$syncScript   = Join-Path $ScriptDir "scripts\Sync-MxAgileEpochCheckpoint.ps1"

# ─── Preflight: scripts exist ─────────────────────────────────────────────
Write-Host ""
Write-Host "=== Context Lifecycle Operational Tests ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "--- Preflight: scripts exist ---" -ForegroundColor Yellow

Assert-True "Preflight: writer script exists" (Test-Path -LiteralPath $writerScript) "Missing: $writerScript"
Assert-True "Preflight: reader script exists" (Test-Path -LiteralPath $readerScript) "Missing: $readerScript"
Assert-True "Preflight: sync script exists"   (Test-Path -LiteralPath $syncScript)   "Missing: $syncScript"

if ($FailCount -gt 0) {
    Write-Host "Preflight failed; cannot continue." -ForegroundColor Red
    exit 1
}

# ─── Helper: create temp project dir with git repo ────────────────────────
function New-TempProject {
    $id  = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $env:TEMP "mxagile-ctx-op-$id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # Init a minimal git repo
    & git -C $dir init -q 2>&1 | Out-Null
    & git -C $dir config user.email "test@mxagile.test" 2>&1 | Out-Null
    & git -C $dir config user.name  "MxAgile Test" 2>&1 | Out-Null
    # Disable autocrlf to prevent LF->CRLF warnings from surfacing as PS errors
    & git -C $dir config core.autocrlf false 2>&1 | Out-Null

    # Initial commit (CRLF line endings so no conversion warning)
    $readme = Join-Path $dir "README.md"
    [System.IO.File]::WriteAllText($readme, "# test`r`n", [System.Text.UTF8Encoding]::new($false))
    & git -C $dir add . 2>&1 | Out-Null
    & git -C $dir commit -m "init" -q 2>&1 | Out-Null

    return $dir
}

function Remove-TempProject {
    param([string]$dir)
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ─── A: Write/read roundtrip ─────────────────────────────────────────────
Write-Host ""
Write-Host "--- A: Write/read roundtrip ---" -ForegroundColor Yellow

$tempA = $null
try {
    $tempA = New-TempProject

    & $writerScript `
        -ProjectRoot $tempA `
        -MissionId "MISSION-A-TEST" `
        -MissionObjective "Roundtrip test mission" `
        -MissionStatus "active" `
        -EpochId "EPOCH-001" `
        -NextAction "Continue with test step 2" `
        -NextActionSafe $false

    $checkpointPath = Join-Path $tempA ".concord\context-epoch.yaml"
    Assert-True "A.1: Checkpoint file created" (Test-Path -LiteralPath $checkpointPath) "File not found: $checkpointPath"

    $content = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8
    Assert-True "A.2: schema_version 1.0 present" ($content -match 'schema_version:.*"1\.0"') "schema_version not found"
    Assert-True "A.3: mission id present" ($content -match 'MISSION-A-TEST') "mission id not found"
    Assert-True "A.4: pressure_state is UNKNOWN" ($content -match 'pressure_state:\s+UNKNOWN') "pressure_state not UNKNOWN"
    Assert-True "A.5: No .tmp file remains" (-not (Test-Path -LiteralPath ($checkpointPath + ".tmp"))) "tmp file still exists"

    $result = & $readerScript -ProjectRoot $tempA
    Assert-True "A.6: Reader returns valid result" $result.Valid "Reader returned invalid: $($result.ConflictReason)"
    Assert-True "A.7: Reader MissionId matches" ($result.MissionId -eq "MISSION-A-TEST") "Got: $($result.MissionId)"
    Assert-True "A.8: Reader EpochId correct" ($result.EpochId -eq "EPOCH-001") "Got: $($result.EpochId)"
    Assert-True "A.9: Reader PressureState UNKNOWN" ($result.PressureState -eq "UNKNOWN") "Got: $($result.PressureState)"
    Assert-True "A.10: Reader NextAction accessible" ($result.NextAction -match "Continue with test step 2") "Got: $($result.NextAction)"
} catch {
    Assert-True "A: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempA) { Remove-TempProject $tempA }
}

# ─── B: Atomic-write safety ───────────────────────────────────────────────
Write-Host ""
Write-Host "--- B: Atomic-write safety ---" -ForegroundColor Yellow

$tempB = $null
try {
    $tempB = New-TempProject

    # Write first valid checkpoint
    & $writerScript `
        -ProjectRoot $tempB `
        -MissionId "MISSION-B-VALID" `
        -MissionObjective "Prior valid checkpoint" `
        -EpochId "EPOCH-001" `
        -NextAction "Step from prior checkpoint"

    $concordDir = Join-Path $tempB ".concord"
    $checkpointPath = Join-Path $concordDir "context-epoch.yaml"
    $tmpPath        = Join-Path $concordDir "context-epoch.yaml.tmp"

    Assert-True "B.1: Prior valid checkpoint exists" (Test-Path -LiteralPath $checkpointPath) "Missing: $checkpointPath"

    # Simulate interrupted write: manually place a corrupted .tmp file
    [System.IO.File]::WriteAllText($tmpPath, "CORRUPTED - not valid yaml", [System.Text.UTF8Encoding]::new($false))
    Assert-True "B.2: Corrupted .tmp file created" (Test-Path -LiteralPath $tmpPath) "tmp file not created"

    # Reader must read the .yaml (not the .tmp) and see the valid prior checkpoint
    $result = & $readerScript -ProjectRoot $tempB
    Assert-True "B.3: Reader ignores .tmp; reads valid checkpoint" $result.Valid "Reader returned invalid: $($result.ConflictReason)"
    Assert-True "B.4: Prior checkpoint content preserved" ($result.MissionId -eq "MISSION-B-VALID") "Got: $($result.MissionId)"

    # Clean up the .tmp
    Remove-Item -LiteralPath $tmpPath -Force
} catch {
    Assert-True "B: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempB) { Remove-TempProject $tempB }
}

# ─── C: Repository re-sync staleness ─────────────────────────────────────
Write-Host ""
Write-Host "--- C: Repository re-sync (stale evidence on commit change) ---" -ForegroundColor Yellow

$tempC = $null
try {
    $tempC = New-TempProject

    # Write checkpoint with a verified claim that should become STALE on commit change
    $verifiedYaml = @'
- claim: "Module security policy compliant"
  evidence_reference: "tests/fixtures/security-policy-result.yaml"
  verification_method: "manual review"
  evidence_state: VERIFIED
  stale_if_commit_changes: true
'@

    & $writerScript `
        -ProjectRoot $tempC `
        -MissionId "MISSION-C-STALE" `
        -MissionObjective "Staleness test mission" `
        -EpochId "EPOCH-001" `
        -VerifiedClaimsYaml $verifiedYaml `
        -NextAction "Continue implementation"

    # Verify initial state
    $checkpointPath = Join-Path $tempC ".concord\context-epoch.yaml"
    $content = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8
    Assert-True "C.1: Initial claim is VERIFIED" ($content -match 'evidence_state:\s+VERIFIED') "Initial VERIFIED not found"

    # Create a new commit in the temp repo (changes HEAD commit)
    $newFile = Join-Path $tempC "change.txt"
    [System.IO.File]::WriteAllText($newFile, "change`r`n", [System.Text.UTF8Encoding]::new($false))
    & git -C $tempC add . 2>&1 | Out-Null
    & git -C $tempC commit -m "change" -q 2>&1 | Out-Null

    # Run sync
    $syncResult = & $syncScript -ProjectRoot $tempC

    Assert-True "C.2: Sync returns CommitChanged=true" ($syncResult.CommitChanged -eq $true) "CommitChanged was: $($syncResult.CommitChanged)"
    Assert-True "C.3: StaleClaimCount is 1" ($syncResult.StaleClaimCount -eq 1) "StaleClaimCount was: $($syncResult.StaleClaimCount)"

    # Verify the checkpoint was updated
    $updatedContent = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8
    Assert-True "C.4: Claim is now STALE" ($updatedContent -match 'evidence_state:\s+STALE') "STALE not found after sync"
    Assert-True "C.5: stale_if_commit_changes still true" ($updatedContent -match 'stale_if_commit_changes:\s+true') "stale_if_commit_changes missing"
} catch {
    Assert-True "C: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempC) { Remove-TempProject $tempC }
}

# ─── D: Evidence preservation ────────────────────────────────────────────
Write-Host ""
Write-Host "--- D: Evidence preservation (VERIFIED/FAILED/UNVERIFIED unchanged without commit change) ---" -ForegroundColor Yellow

$tempD = $null
try {
    $tempD = New-TempProject

    $verifiedYaml = @'
- claim: "Gate passed for W01"
  evidence_reference: "planning/lifecycle/process-state.yaml"
  verification_method: "gate skill"
  evidence_state: VERIFIED
  stale_if_commit_changes: false
'@

    $failedYaml = @'
- claim: "Integration test for external API"
  evidence_reference: "N/A"
  failure_summary: "External service not available in test environment"
  remediation_state: deferred
  evidence_state: FAILED
'@

    $unverifiedYaml = @'
- claim: "Auto-rollover is harness-safe"
  reason: harness_limitation
  evidence_state: UNVERIFIED
'@

    & $writerScript `
        -ProjectRoot $tempD `
        -MissionId "MISSION-D-PRESERVE" `
        -EpochId "EPOCH-001" `
        -VerifiedClaimsYaml $verifiedYaml `
        -FailedClaimsYaml $failedYaml `
        -UnverifiedClaimsYaml $unverifiedYaml `
        -NextAction "Continue"

    # Run sync WITHOUT creating a new commit (commit is unchanged)
    $syncResult = & $syncScript -ProjectRoot $tempD

    Assert-True "D.1: Sync OK (no branch conflict)" $syncResult.SyncOk "SyncOk=false: $($syncResult.ConflictDetail)"
    Assert-True "D.2: CommitChanged=false" ($syncResult.CommitChanged -eq $false) "CommitChanged was true"
    Assert-True "D.3: StaleClaimCount=0" ($syncResult.StaleClaimCount -eq 0) "Unexpected stale count: $($syncResult.StaleClaimCount)"

    $content = Get-Content -LiteralPath (Join-Path $tempD ".concord\context-epoch.yaml") -Raw -Encoding UTF8
    Assert-True "D.4: VERIFIED claim preserved" ($content -match 'evidence_state:\s+VERIFIED') "VERIFIED not found"
    Assert-True "D.5: FAILED claim preserved" ($content -match 'evidence_state:\s+FAILED') "FAILED not found"
    Assert-True "D.6: UNVERIFIED claim preserved" ($content -match 'evidence_state:\s+UNVERIFIED') "UNVERIFIED not found"
} catch {
    Assert-True "D: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempD) { Remove-TempProject $tempD }
}

# ─── E: Pressure UNKNOWN ─────────────────────────────────────────────────
Write-Host ""
Write-Host "--- E: Pressure UNKNOWN (no measurement available) ---" -ForegroundColor Yellow

$tempE = $null
try {
    $tempE = New-TempProject

    & $writerScript `
        -ProjectRoot $tempE `
        -MissionId "MISSION-E-PRESSURE" `
        -EpochId "EPOCH-001" `
        -NextAction "Continue"

    # No token measurement provided => pressure_state must be UNKNOWN
    $content = Get-Content -LiteralPath (Join-Path $tempE ".concord\context-epoch.yaml") -Raw -Encoding UTF8
    Assert-True "E.1: pressure_state is UNKNOWN" ($content -match 'pressure_state:\s+UNKNOWN') "pressure_state not UNKNOWN: $($content -match 'pressure_state')"
    Assert-True "E.2: context_token_source is unknown" ($content -match 'context_token_source:\s+unknown') "context_token_source not unknown"

    # Reader also returns UNKNOWN
    $result = & $readerScript -ProjectRoot $tempE
    Assert-True "E.3: Reader.PressureState=UNKNOWN" ($result.PressureState -eq "UNKNOWN") "Got: $($result.PressureState)"
} catch {
    Assert-True "E: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempE) { Remove-TempProject $tempE }
}

# ─── F: Fresh-context simulation ─────────────────────────────────────────
Write-Host ""
Write-Host "--- F: Fresh-context simulation (subprocess reads checkpoint) ---" -ForegroundColor Yellow
Write-Host "    Note: Simulates context B loading checkpoint from context A." -ForegroundColor DarkGray
Write-Host "    Remaining gap: live harness restart (new agent session) not automated." -ForegroundColor DarkGray

$tempF = $null
try {
    $tempF = New-TempProject

    # Context A: write checkpoint with specific next action
    & $writerScript `
        -ProjectRoot $tempF `
        -MissionId "MISSION-F-FRESH" `
        -MissionObjective "Fresh context simulation mission" `
        -EpochId "EPOCH-002" `
        -NextAction "Resume at W01-03 implementation step" `
        -NextActionSafe $true `
        -NextChecklistItem "W01-03"

    Assert-True "F.1: Checkpoint exists after context A write" `
        (Test-Path -LiteralPath (Join-Path $tempF ".concord\context-epoch.yaml")) `
        "Checkpoint file missing"

    # Context B simulation: run reader in a subprocess (fresh PowerShell process)
    # This simulates a new agent session reading only the durable checkpoint.
    $psExe = "powershell.exe"
    if (Get-Command "pwsh.exe" -ErrorAction SilentlyContinue) { $psExe = "pwsh.exe" }

    $readerCmd = "& '$readerScript' -ProjectRoot '$tempF' | ConvertTo-Json -Depth 5"
    $output = & $psExe -NoProfile -NonInteractive -Command $readerCmd 2>$null

    Assert-True "F.2: Subprocess read succeeded (non-null output)" (-not [string]::IsNullOrWhiteSpace($output)) "Subprocess produced no output"

    if (-not [string]::IsNullOrWhiteSpace($output)) {
        $resultObj = $output | ConvertFrom-Json
        Assert-True "F.3: Subprocess result.Valid=true" ($resultObj.Valid -eq $true) "Valid=false. ConflictReason: $($resultObj.ConflictReason)"
        Assert-True "F.4: Subprocess reads MissionId correctly" ($resultObj.MissionId -eq "MISSION-F-FRESH") "Got: $($resultObj.MissionId)"
        Assert-True "F.5: Subprocess reads EpochId=EPOCH-002" ($resultObj.EpochId -eq "EPOCH-002") "Got: $($resultObj.EpochId)"
        Assert-True "F.6: Subprocess NextAction accessible" ($resultObj.NextAction -match "W01-03") "Got: $($resultObj.NextAction)"
    }
} catch {
    Assert-True "F: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempF) { Remove-TempProject $tempF }
}

# ─── Summary ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Operational Tests Summary ===" -ForegroundColor Cyan
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
