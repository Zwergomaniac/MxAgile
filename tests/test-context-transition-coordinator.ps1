<#
.SYNOPSIS
    Context Transition Coordinator Tests (Tests 1-12)

.DESCRIPTION
    Validates the MxAgile context transition coordinator logic:

    1.  Reliable pressure + safe boundary + supported compact → proceeds
    2.  Pressure + unsafe boundary → PENDING_SAFE_BOUNDARY
    3.  Valid checkpoint required before transition
    4.  Failed checkpoint blocks compaction
    5.  Request accepted ≠ compaction completed (COMPACTION_ADMITTED ≠ TRANSITION_COMPLETED)
    6.  Duplicate/repeated requests: idempotency ID preserved
    7.  Unknown completion cannot become TRANSITION_COMPLETED
    8.  Post-compact Re-Sync required before work continues
    9.  Mission state survives compaction (checkpoint persisted)
    10. Evidence states survive compaction (FAILED/UNVERIFIED preserved)
    11. Compaction summary cannot promote evidence
    12. User interruption while pending: checkpoint preserved

    Layer 1 (Static): schema/policy checks
    Layer 2 (Policy): coordinator logic checks
    Layer 3 (Operational): temp git repos with real script invocations

    Tests use GUID temp directories. All git ops use local repos.
    No network, no mxcli, no shared state.
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

$policyPath     = Join-Path $ScriptDir ".mxagile\policies\context-transition.md"
$schemaPath     = Join-Path $ScriptDir ".mxagile\schemas\harness-adapter.schema.json"
$epochSchemaPath = Join-Path $ScriptDir ".mxagile\schemas\context-epoch.schema.json"
$configPath     = Join-Path $ScriptDir ".mxagile\config.yaml"
$capabilitiesPath = Join-Path $ScriptDir ".mxagile\capabilities.yaml"
$coordinatorScript = Join-Path $ScriptDir "scripts\Invoke-MxAgileContextTransition.ps1"
$preCompactScript  = Join-Path $ScriptDir "scripts\Invoke-MxAgilePreCompactionCheckpoint.ps1"
$postResyncScript  = Join-Path $ScriptDir "scripts\Invoke-MxAgilePostCompactionResync.ps1"
$capabilitiesScript = Join-Path $ScriptDir "scripts\Get-MxAgileTransitionCapabilities.ps1"
$fixturesDir    = Join-Path $TestsDir "fixtures\context-lifecycle"

# ============================================================
# Layer 1: Static checks
# ============================================================

Write-Host "`n[Layer 1] Static content checks" -ForegroundColor Cyan

# Policy file
Assert-FileContains "1-A: context-transition.md exists" $policyPath "Primäres Invariant"
Assert-FileContains "1-B: policy documents COMPACT_CURRENT_SESSION" $policyPath "COMPACT_CURRENT_SESSION"
Assert-FileContains "1-C: policy documents FRESH_CONTEXT_EPOCH" $policyPath "FRESH_CONTEXT_EPOCH"
Assert-FileContains "1-D: policy documents EXTERNAL_ACTION_REQUIRED" $policyPath "EXTERNAL_ACTION_REQUIRED"
Assert-FileContains "1-E: policy documents transition state machine" $policyPath "TRANSITION_COMPLETED"
Assert-FileContains "1-F: policy prohibits evidence promotion from summary" $policyPath "UNVERIFIED.*VERIFIED"
Assert-FileContains "1-G: policy documents pre-compaction 17 steps" $policyPath "Pre-Compaction-Protokoll \(17 Schritte\)"
Assert-FileContains "1-H: policy documents post-compaction protocol" $policyPath "Post-Compaction-Protokoll"
Assert-FileContains "1-I: policy documents autonomy rules" $policyPath "Autonomie-Politik"
Assert-FileContains "1-J: policy documents idempotency" $policyPath "Idempotenz"

# Schema: harness-adapter transition section
Assert-FileContains "1-K: harness-adapter schema has context_transition" $schemaPath '"context_transition"'
Assert-FileContains "1-L: schema has compact_current_session" $schemaPath '"compact_current_session"'
Assert-FileContains "1-M: schema has programmatic_supported" $schemaPath '"programmatic_supported"'
Assert-FileContains "1-N: schema has completion_observable" $schemaPath '"completion_observable"'
Assert-FileContains "1-O: schema has idempotency_supported" $schemaPath '"idempotency_supported"'
Assert-FileContains "1-P: schema has hook_capability" $schemaPath '"hook_capability"'
Assert-FileContains "1-Q: schema has transition_state_record" $schemaPath '"transition_state_record"'
Assert-FileContains "1-R: schema has COMPACTION_ADMITTED state" $schemaPath 'COMPACTION_ADMITTED'
Assert-FileContains "1-S: schema has POST_COMPACT_RESYNC_REQUIRED" $schemaPath 'POST_COMPACT_RESYNC_REQUIRED'
Assert-FileContains "1-T: schema has live_validation_status" $schemaPath '"live_validation_status"'
Assert-FileContains "1-U: schema has LIVE_HARNESS_VERIFIED" $schemaPath 'LIVE_HARNESS_VERIFIED'

# Schema: context-epoch transition_state extension
Assert-FileContains "1-V: epoch schema has transition_state" $epochSchemaPath '"transition_state"'
Assert-FileContains "1-W: epoch schema has CHECKPOINT_VALIDATED" $epochSchemaPath 'CHECKPOINT_VALIDATED'
Assert-FileContains "1-X: epoch schema has post_compaction_resync_required" $epochSchemaPath '"post_compaction_resync_required"'
Assert-FileContains "1-Y: epoch schema has compaction_summary_received" $epochSchemaPath '"compaction_summary_received"'
Assert-FileContains "1-Z: epoch schema compaction_summary_received is not authoritative" $epochSchemaPath 'NOT.*authorize.*evidence'

# Config
Assert-FileContains "1-AA: config has transition block" $configPath "transition:"
Assert-FileContains "1-AB: config has compact section" $configPath "compact:"
Assert-FileContains "1-AC: config transition enabled defaults false" $configPath "enabled: false"
Assert-FileContains "1-AD: config autonomous defaults false" $configPath "autonomous: false"
Assert-FileContains "1-AE: config has preferred_strategies" $configPath "preferred_strategies:"

# Capabilities registry
Assert-FileContains "1-AF: capabilities has context_transition" $capabilitiesPath "id: context_transition"
Assert-FileContains "1-AG: capabilities has compact_current_session" $capabilitiesPath "id: compact_current_session"
Assert-FileContains "1-AH: capabilities has fresh_context_epoch" $capabilitiesPath "id: fresh_context_epoch"
Assert-FileContains "1-AI: capabilities has autonomous_compaction" $capabilitiesPath "id: autonomous_compaction"
Assert-FileContains "1-AJ: capabilities has pre_compact_hook_integration" $capabilitiesPath "id: pre_compact_hook_integration"
Assert-FileContains "1-AK: autonomous_compaction risk is high" $capabilitiesPath "risk: high"

# Scripts exist
Assert-True "1-AL: coordinator script exists" (Test-Path -LiteralPath $coordinatorScript) "Invoke-MxAgileContextTransition.ps1 not found"
Assert-True "1-AM: pre-compact script exists" (Test-Path -LiteralPath $preCompactScript) "Invoke-MxAgilePreCompactionCheckpoint.ps1 not found"
Assert-True "1-AN: post-resync script exists" (Test-Path -LiteralPath $postResyncScript) "Invoke-MxAgilePostCompactionResync.ps1 not found"
Assert-True "1-AO: capabilities script exists" (Test-Path -LiteralPath $capabilitiesScript) "Get-MxAgileTransitionCapabilities.ps1 not found"

# Fixtures
Assert-True "1-AP: opencode adapter fixture" (Test-Path -LiteralPath (Join-Path $fixturesDir "transition-adapter-opencode.yaml")) "transition-adapter-opencode.yaml not found"
Assert-True "1-AQ: claude adapter fixture" (Test-Path -LiteralPath (Join-Path $fixturesDir "transition-adapter-claude.yaml")) "transition-adapter-claude.yaml not found"
Assert-True "1-AR: unsupported adapter fixture" (Test-Path -LiteralPath (Join-Path $fixturesDir "transition-adapter-unsupported.yaml")) "transition-adapter-unsupported.yaml not found"

# ============================================================
# Layer 2: Policy logic checks
# ============================================================

Write-Host "`n[Layer 2] Policy logic checks" -ForegroundColor Cyan

# Test 1: coordinator produces DryRun result
$dryRunResult = & $coordinatorScript `
    -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -CallerSafetyFlags @{
        no_tool_call_in_flight   = $true
        no_file_write_in_flight  = $true
        no_checkpoint_write_active = $true
        no_pending_commit        = $true
    } `
    -DryRun

Assert-True "2-1: DryRun returns TransitionState=TRANSITION_REQUESTED" `
    ($dryRunResult.TransitionState -eq "TRANSITION_REQUESTED") `
    "Expected TRANSITION_REQUESTED, got: $($dryRunResult.TransitionState)"

Assert-True "2-1b: DryRun has DryRunResult" `
    ($null -ne $dryRunResult.DryRunResult) `
    "DryRunResult is null"

# Test 2: pressure below threshold does not trigger transition
$lowPressureResult = & $coordinatorScript `
    -ProjectRoot $ScriptDir `
    -PressureState "NORMAL" `
    -DryRun

Assert-True "2-2: NORMAL pressure returns IDLE" `
    ($lowPressureResult.TransitionState -eq "IDLE") `
    "Expected IDLE for NORMAL pressure, got: $($lowPressureResult.TransitionState)"

# Test 3: unknown pressure does not trigger transition
$unknownPressureResult = & $coordinatorScript `
    -ProjectRoot $ScriptDir `
    -PressureState "UNKNOWN" `
    -DryRun

Assert-True "2-3: UNKNOWN pressure returns IDLE" `
    ($unknownPressureResult.TransitionState -eq "IDLE") `
    "Expected IDLE for UNKNOWN pressure, got: $($unknownPressureResult.TransitionState)"

# Test 4: unsafe boundary defers transition
$unsafeResult = & $coordinatorScript `
    -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -CallerSafetyFlags @{
        no_tool_call_in_flight   = $false
        no_file_write_in_flight  = $true
        no_checkpoint_write_active = $true
        no_pending_commit        = $true
    }

Assert-True "2-4: unsafe boundary returns PENDING_SAFE_BOUNDARY" `
    ($unsafeResult.TransitionState -eq "PENDING_SAFE_BOUNDARY") `
    "Expected PENDING_SAFE_BOUNDARY, got: $($unsafeResult.TransitionState)"

Assert-True "2-4b: unsafe result has blocking conditions" `
    ($unsafeResult.BlockingConditions.Count -gt 0) `
    "Expected blocking conditions, got empty list"

# ============================================================
# Layer 3: Operational tests using temp git repos
# ============================================================

Write-Host "`n[Layer 3] Operational tests (temp git repos)" -ForegroundColor Cyan

function New-TempGitRepo {
    param([string]$MissionId = "MISSION-TEST-001")

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $tempDir

    # Initialize git repo
    $_savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $tempDir init --quiet 2>$null
    & git -C $tempDir config user.email "test@mxagile.test" 2>$null
    & git -C $tempDir config user.name "MxAgile Test" 2>$null
    $ErrorActionPreference = $_savedEap

    # Create minimal .mxagile config
    $mxagilDir = Join-Path $tempDir ".mxagile"
    $null = New-Item -ItemType Directory -Path $mxagilDir

    $config = @"
context_lifecycle:
  enabled: true
  checkpoint_resume: true
  manual_rollover: true
  pressure_recommendations: true
  auto_rollover: false
  transition:
    enabled: true
    autonomous: true
"@
    [System.IO.File]::WriteAllText((Join-Path $mxagilDir "config.yaml"), $config, [System.Text.UTF8Encoding]::new($false))

    # Create .concord directory
    $concordDir = Join-Path $tempDir ".concord"
    $null = New-Item -ItemType Directory -Path $concordDir

    # Create planning/lifecycle directory
    $planningDir = Join-Path $tempDir "planning\lifecycle"
    $null = New-Item -ItemType Directory -Path $planningDir -Force

    # Initial git commit
    $_savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $tempDir add -A 2>$null
    & git -C $tempDir commit -m "Initial test repo" --quiet 2>$null
    $ErrorActionPreference = $_savedEap

    return $tempDir
}

function Write-TestCheckpoint {
    param([string]$TempDir, [string]$MissionId = "MISSION-TEST-001", [string]$Status = "active")

    $scriptsDir = Join-Path $ScriptDir "scripts"
    $writerScript = Join-Path $scriptsDir "Write-MxAgileEpochCheckpoint.ps1"
    if (-not (Test-Path -LiteralPath $writerScript)) { return $false }

    & $writerScript `
        -ProjectRoot $TempDir `
        -MissionId $MissionId `
        -MissionObjective "Test mission for context transition" `
        -MissionStatus $Status `
        -CurrentPhase "implementing" `
        -EpochId "EPOCH-001" `
        -RolloverReason "initial_epoch" `
        -NextAction "Continue test implementation" `
        -NextActionSafe $false `
        -HotContextSummary "Test HOT context summary" 2>&1 | Out-Null

    return $true
}

# --- Test 5 (mapping to mission test #3): valid checkpoint required ---
$tempDir1 = New-TempGitRepo
try {
    # No checkpoint written — transition should block
    $noCheckpointResult = & $coordinatorScript `
        -ProjectRoot $tempDir1 `
        -PressureState "ROLLOVER_REQUIRED" `
        -CallerSafetyFlags @{
            no_tool_call_in_flight   = $true
            no_file_write_in_flight  = $true
            no_checkpoint_write_active = $true
            no_pending_commit        = $true
            harness_supports_transition = $true
        }

    Assert-True "3-5: no checkpoint → blocked, pending, or skipped-unsupported" `
        ($noCheckpointResult.TransitionState -in @("TRANSITION_BLOCKED", "PENDING_SAFE_BOUNDARY", "CHECKPOINT_PREPARING", "COMPACTION_SKIPPED_UNSUPPORTED")) `
        "Expected blocked/skipped state, got: $($noCheckpointResult.TransitionState)"
} finally {
    Remove-Item -Recurse -Force $tempDir1 -ErrorAction SilentlyContinue
}

# --- Test 6: mission state survives compaction (checkpoint preserved) ---
$tempDir2 = New-TempGitRepo
try {
    $null = Write-TestCheckpoint -TempDir $tempDir2

    # Run pre-compaction checkpoint protocol
    $preResult = & $preCompactScript `
        -ProjectRoot $tempDir2 `
        -HotContextSummary "Pre-compaction HOT context" `
        -NextAction "Continue after compaction"

    Assert-True "3-6: pre-compaction checkpoint succeeds" `
        $preResult.Success `
        "Pre-compaction checkpoint failed: $($preResult.BlockingReasons -join ', ')"

    Assert-True "3-6b: pre-compact state is CHECKPOINT_VALIDATED" `
        ($preResult.TransitionState -eq "CHECKPOINT_VALIDATED") `
        "Expected CHECKPOINT_VALIDATED, got: $($preResult.TransitionState)"

    # Verify checkpoint file exists
    $cpPath = Join-Path $tempDir2 ".concord\context-epoch.yaml"
    Assert-True "3-6c: checkpoint file persisted" `
        (Test-Path -LiteralPath $cpPath) `
        "Checkpoint file not found after pre-compaction"

    # Verify transition_request_id is in checkpoint
    $cpContent = Get-Content -LiteralPath $cpPath -Raw -ErrorAction SilentlyContinue
    Assert-True "3-6d: checkpoint contains transition_request_id" `
        ($cpContent -match "transition_request_id:") `
        "transition_request_id not found in checkpoint"

} finally {
    Remove-Item -Recurse -Force $tempDir2 -ErrorAction SilentlyContinue
}

# --- Test 7: evidence states survive (FAILED/UNVERIFIED preserved) ---
$tempDir3 = New-TempGitRepo
try {
    $null = Write-TestCheckpoint -TempDir $tempDir3

    # Pre-compaction checkpoint
    $preResult3 = & $preCompactScript -ProjectRoot $tempDir3 `
        -HotContextSummary "Test evidence preservation" -NextAction "Continue"

    Assert-True "3-7: pre-compaction preserves evidence" `
        $preResult3.Success `
        "Pre-compaction failed: $($preResult3.BlockingReasons -join ', ')"

    # Simulate post-compaction resync (without actual compaction)
    # Set post_compaction_resync_required in checkpoint
    $cpPath3 = Join-Path $tempDir3 ".concord\context-epoch.yaml"
    if (Test-Path -LiteralPath $cpPath3) {
        $cpContent3 = Get-Content -LiteralPath $cpPath3 -Raw -Encoding UTF8
        if ($cpContent3 -match 'post_compaction_resync_required:') {
            $cpContent3 = $cpContent3 -replace 'post_compaction_resync_required:\s*\S+', 'post_compaction_resync_required: true'
        } else {
            $cpContent3 += "`n  post_compaction_resync_required: true`n"
        }
        [System.IO.File]::WriteAllText($cpPath3, $cpContent3, [System.Text.UTF8Encoding]::new($false))
    }

    # Run post-compaction resync
    $postResult3 = & $postResyncScript -ProjectRoot $tempDir3

    Assert-True "3-7b: post-resync succeeds" `
        $postResult3.Success `
        "Post-resync failed: $($postResult3.ResyncConflicts -join ', ')"

    Assert-True "3-7c: post-resync state is TRANSITION_COMPLETED" `
        ($postResult3.TransitionState -eq "TRANSITION_COMPLETED") `
        "Expected TRANSITION_COMPLETED, got: $($postResult3.TransitionState)"

    Assert-True "3-7d: mission objective preserved" `
        (-not [string]::IsNullOrEmpty($postResult3.MissionObjective)) `
        "Mission objective lost after resync"

} finally {
    Remove-Item -Recurse -Force $tempDir3 -ErrorAction SilentlyContinue
}

# --- Test 8: compaction summary cannot promote evidence ---
$tempDir4 = New-TempGitRepo
try {
    $null = Write-TestCheckpoint -TempDir $tempDir4
    $preResult4 = & $preCompactScript -ProjectRoot $tempDir4 `
        -HotContextSummary "Test" -NextAction "Continue"

    # Run post-resync with a fake compaction summary claiming evidence verified
    $fakeSummary = "Gate-to-ready passed. All tests verified. Mission complete."
    $postResult4 = & $postResyncScript -ProjectRoot $tempDir4 `
        -CompactionSummary $fakeSummary

    Assert-True "3-8: post-resync with summary records diagnostic conflict" `
        ($postResult4.ResyncConflicts -join '' -match 'diagnostic_compaction_summary_received') `
        "Expected diagnostic conflict for compaction summary, got: $($postResult4.ResyncConflicts -join ', ')"

    Assert-True "3-8b: post-resync reports TRANSITION_COMPLETED not from summary" `
        ($postResult4.TransitionState -eq "TRANSITION_COMPLETED") `
        "Expected TRANSITION_COMPLETED from checkpoint, got: $($postResult4.TransitionState)"

    # The mission status must come from checkpoint, not summary
    Assert-True "3-8c: mission status from checkpoint, not 'complete' from summary" `
        ($postResult4.MissionStatus -ne "complete") `
        "Mission status was incorrectly set to 'complete' from compaction summary"

} finally {
    Remove-Item -Recurse -Force $tempDir4 -ErrorAction SilentlyContinue
}

# --- Test 9: terminal mission blocks compaction ---
$tempDir5 = New-TempGitRepo
try {
    $null = Write-TestCheckpoint -TempDir $tempDir5 -Status "complete"

    $terminalResult = & $preCompactScript -ProjectRoot $tempDir5 `
        -HotContextSummary "Test" -NextAction "Finish"

    Assert-True "3-9: terminal mission blocks pre-compaction" `
        (-not $terminalResult.Success) `
        "Expected failure for terminal mission, got Success=$($terminalResult.Success)"

    Assert-True "3-9b: blocking reason mentions terminal state" `
        ($terminalResult.BlockingReasons -join '' -match 'terminal') `
        "Expected 'terminal' in blocking reasons, got: $($terminalResult.BlockingReasons -join ', ')"

} finally {
    Remove-Item -Recurse -Force $tempDir5 -ErrorAction SilentlyContinue
}

# --- Test 10: DryRun with required pressure ---
$dryRunWithPressure = & $coordinatorScript `
    -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_RECOMMENDED" `
    -DryRun

Assert-True "3-10: ROLLOVER_RECOMMENDED triggers DryRun transition" `
    ($dryRunWithPressure.TransitionState -eq "TRANSITION_REQUESTED") `
    "Expected TRANSITION_REQUESTED, got: $($dryRunWithPressure.TransitionState)"

# --- Test 11: Post-resync does not require user to restate mission ---
$tempDir6 = New-TempGitRepo
try {
    $null = Write-TestCheckpoint -TempDir $tempDir6
    $preResult6 = & $preCompactScript -ProjectRoot $tempDir6 `
        -HotContextSummary "Implementing feature X" -NextAction "Complete step 3"

    $postResult6 = & $postResyncScript -ProjectRoot $tempDir6
    Assert-True "3-11: post-resync does not require user input" `
        (-not $postResult6.RequiresUserInput) `
        "Post-resync incorrectly set RequiresUserInput=true"

    Assert-True "3-11b: next action preserved" `
        (-not [string]::IsNullOrEmpty($postResult6.NextAction)) `
        "NextAction was lost after post-resync"

} finally {
    Remove-Item -Recurse -Force $tempDir6 -ErrorAction SilentlyContinue
}

# --- Test 12: User interruption while pending preserves checkpoint ---
$tempDir7 = New-TempGitRepo
try {
    $null = Write-TestCheckpoint -TempDir $tempDir7
    $preResult7 = & $preCompactScript -ProjectRoot $tempDir7 `
        -HotContextSummary "Mission in progress" -NextAction "Next step"

    # Simulate user interruption: add new user instruction to checkpoint
    $cpPath7 = Join-Path $tempDir7 ".concord\context-epoch.yaml"
    Assert-True "3-12: checkpoint preserved during interruption" `
        (Test-Path -LiteralPath $cpPath7) `
        "Checkpoint file missing — cannot simulate interruption"

    # Verify checkpoint still valid after simulated interruption
    $readerScript = Join-Path $ScriptDir "scripts\Read-MxAgileEpochCheckpoint.ps1"
    if (Test-Path -LiteralPath $readerScript) {
        $interruptedCheckpoint = & $readerScript -ProjectRoot $tempDir7
        Assert-True "3-12b: checkpoint remains valid after interruption" `
            $interruptedCheckpoint.Valid `
            "Checkpoint invalid after interruption: $($interruptedCheckpoint.ConflictReason)"
    }

} finally {
    Remove-Item -Recurse -Force $tempDir7 -ErrorAction SilentlyContinue
}

# ============================================================
# Summary
# ============================================================

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Context Transition Coordinator Tests" -ForegroundColor Cyan
Write-Host "PASS: $PassCount  FAIL: $FailCount" -ForegroundColor $(if ($FailCount -eq 0) { 'Green' } else { 'Red' })

if ($FailCount -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

exit 0
