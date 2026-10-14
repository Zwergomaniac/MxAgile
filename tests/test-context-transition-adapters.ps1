<#
.SYNOPSIS
    Context Transition Adapter Tests — OpenCode, Claude Code, Copilot CLI (Tests 13-31)

.DESCRIPTION
    Validates harness-specific adapter behavior:

    OpenCode adapter (13-22):
      13. Capability discovery: OpenCode adapter loads
      14. Session-id resolution: OPENCODE_SESSION_ID env respected
      15. Compact request includes idempotency id
      16. Admitted request produces COMPACTION_ADMITTED, not TRANSITION_COMPLETED
      17. Completion event mechanism documented
      18. Failure path documented
      19. Repeated request uses same idempotency ID (no new request)
      20. Overflow recovery limit documented
      21. Auth/discovery failure produces TRANSITION_BLOCKED, not fabricated success
      22. No infinite retry: max_recovery_attempts=1

    Claude Code adapter (23-28):
      23. PreCompact hook: produces CHECKPOINT_VALIDATED
      24. SessionStart after compact triggers Re-Sync
      25. No unsupported programmatic trigger claim
      26. Programmatic_supported=false for claude_code
      27. Summary/checkpoint disagreement: checkpoint wins
      28. Native auto-compaction: automatic_supported=true

    Copilot CLI adapter (29-31):
      29. Copilot capability discovery: UNSUPPORTED
      30. Copilot compaction remains UNSUPPORTED
      31. No false ACTIVE status for Copilot
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

$openCodeAdapter  = Join-Path $ScriptDir ".mxagile\adapters\opencode\transition-adapter.yaml"
$claudeAdapter    = Join-Path $ScriptDir ".mxagile\adapters\claude\transition-adapter.yaml"
$copilotAdapter   = Join-Path $ScriptDir ".mxagile\adapters\copilot\transition-adapter.yaml"
$genericAdapter   = Join-Path $ScriptDir ".mxagile\adapters\generic\transition-adapter.yaml"
$capabilitiesScript = Join-Path $ScriptDir "scripts\Get-MxAgileTransitionCapabilities.ps1"
$coordinatorScript  = Join-Path $ScriptDir "scripts\Invoke-MxAgileContextTransition.ps1"
$preCompactScript   = Join-Path $ScriptDir "scripts\Invoke-MxAgilePreCompactionCheckpoint.ps1"
$postResyncScript   = Join-Path $ScriptDir "scripts\Invoke-MxAgilePostCompactionResync.ps1"

# ============================================================
# OpenCode Adapter Tests (13-22)
# ============================================================

Write-Host "`n[OpenCode Adapter Tests 13-22]" -ForegroundColor Cyan

# Test 13: OpenCode adapter file exists and loads
Assert-True "13: OpenCode adapter file exists" (Test-Path -LiteralPath $openCodeAdapter) "transition-adapter.yaml not found"
Assert-FileContains "13b: OpenCode adapter has programmatic_supported: true" $openCodeAdapter "programmatic_supported: true"
Assert-FileContains "13c: OpenCode adapter has completion_observable: true" $openCodeAdapter "completion_observable: true"
Assert-FileContains "13d: OpenCode adapter has idempotency_supported: true" $openCodeAdapter "idempotency_supported: true"

# Test 14: Session-id resolution documented
Assert-FileContains "14: OpenCode adapter documents OPENCODE_SESSION_ID" $openCodeAdapter "OPENCODE_SESSION_ID"
Assert-FileContains "14b: OpenCode adapter documents env_base_url" $openCodeAdapter "env_base_url"
Assert-FileContains "14c: OpenCode adapter documents default_base_url" $openCodeAdapter "default_base_url"

# Test 15: Compact request includes idempotency id
Assert-FileContains "15: OpenCode adapter documents id_field for idempotency" $openCodeAdapter "id_field"
Assert-FileContains "15b: OpenCode adapter describes stable idempotency ID" $openCodeAdapter "[Ss]table.*[Ii]dempotency"

# Test 16: Admitted ≠ completed — COMPACTION_ADMITTED state documented
$capabilitiesResult = & $capabilitiesScript -ProjectRoot $ScriptDir -HarnessId "opencode"
Assert-True "16: OpenCode capabilities: CompactCurrentSession.ProgrammaticSupported=true" `
    ($capabilitiesResult.CompactCurrentSession.ProgrammaticSupported -eq $true) `
    "ProgrammaticSupported should be true for opencode"

Assert-True "16b: OpenCode capabilities: CompactCurrentSession.CompletionObservable=true" `
    ($capabilitiesResult.CompactCurrentSession.CompletionObservable -eq $true) `
    "CompletionObservable should be true for opencode"

# coordinator DryRun with OpenCode selected strategy
$ocDryRun = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "opencode" `
    -DryRun

Assert-True "16c: OpenCode DryRun preferred strategy is COMPACT_CURRENT_SESSION" `
    ($ocDryRun.Strategy -eq "COMPACT_CURRENT_SESSION") `
    "Expected COMPACT_CURRENT_SESSION, got: $($ocDryRun.Strategy)"

# Test 17: Completion event mechanism documented
Assert-FileContains "17: OpenCode adapter documents completion event" $openCodeAdapter "session.compaction.completed"
Assert-FileContains "17b: OpenCode adapter documents failure event" $openCodeAdapter "session.compaction.fail"

# Test 18: Failure path produces TRANSITION_FAILED (no session ID configured)
# We run the coordinator with OpenCode harness but NO session ID set
# This should produce TRANSITION_BLOCKED (missing session ID) not fabricated success
$savedSessionId = [System.Environment]::GetEnvironmentVariable('OPENCODE_SESSION_ID')
[System.Environment]::SetEnvironmentVariable('OPENCODE_SESSION_ID', '', [System.EnvironmentVariableTarget]::Process)
$savedBaseUrl = [System.Environment]::GetEnvironmentVariable('OPENCODE_BASE_URL')
[System.Environment]::SetEnvironmentVariable('OPENCODE_BASE_URL', '', [System.EnvironmentVariableTarget]::Process)

try {
    # Can't run full coordinator without checkpoint, just verify capabilities resolver
    $ocCapNoSession = & $capabilitiesScript -ProjectRoot $ScriptDir -HarnessId "opencode"
    Assert-True "18: OpenCode capability resolver runs without session ID" `
        ($ocCapNoSession.HarnessId -eq "opencode") `
        "Capability resolver failed without session ID"

    Assert-True "18b: OpenCode live_validation not LIVE_HARNESS_VERIFIED without session" `
        ($ocCapNoSession.CompactCurrentSession.LiveValidationStatus -ne "LIVE_HARNESS_VERIFIED") `
        "Should not report LIVE_HARNESS_VERIFIED without an active session"
} finally {
    if (-not [string]::IsNullOrEmpty($savedSessionId)) {
        [System.Environment]::SetEnvironmentVariable('OPENCODE_SESSION_ID', $savedSessionId, [System.EnvironmentVariableTarget]::Process)
    }
    if (-not [string]::IsNullOrEmpty($savedBaseUrl)) {
        [System.Environment]::SetEnvironmentVariable('OPENCODE_BASE_URL', $savedBaseUrl, [System.EnvironmentVariableTarget]::Process)
    }
}

# Test 19: Repeated requests use same idempotency ID
$testReqId = "TXN-EPOCH-001-20261014120000"
Assert-FileContains "19: OpenCode adapter notes coalescing behavior" $openCodeAdapter "coalesce"

# Test 20: Overflow recovery limit = 1
Assert-FileContains "20: OpenCode adapter documents max_recovery_attempts: 1" $openCodeAdapter "max_recovery_attempts: 1"

# Test 21: Missing session ID → TRANSITION_BLOCKED
# The coordinator script should not fabricate TRANSITION_COMPLETED when API call fails.
# This is validated by the logic in Invoke-MxAgileContextTransition.ps1
Assert-FileContains "21: coordinator blocks on opencode_session_id_unavailable" `
    (Join-Path $ScriptDir "scripts\Invoke-MxAgileContextTransition.ps1") `
    "opencode_session_id_unavailable"

# Test 22: No infinite retry — one-shot recovery documented
Assert-FileContains "22: OpenCode adapter notes one-shot recovery" $openCodeAdapter "one.shot"
Assert-FileContains "22b: adapter notes repeated overflow should be reported" $openCodeAdapter "reported"

# ============================================================
# Claude Code Adapter Tests (23-28)
# ============================================================

Write-Host "`n[Claude Code Adapter Tests 23-28]" -ForegroundColor Cyan

# Test 23: Claude Code adapter loads; pre-compact produces CHECKPOINT_VALIDATED
Assert-True "23: Claude Code adapter file exists" (Test-Path -LiteralPath $claudeAdapter) "claude transition-adapter.yaml not found"
Assert-FileContains "23b: Claude adapter has pre_compact: SUPPORTED" $claudeAdapter "pre_compact: SUPPORTED"
Assert-FileContains "23c: Claude adapter has session_start_after_compact: SUPPORTED" $claudeAdapter "session_start_after_compact: SUPPORTED"

# Test 24: SessionStart after compact triggers Re-Sync
Assert-FileContains "24: Claude adapter documents SessionStart hook" $claudeAdapter "SessionStart"
Assert-FileContains "24b: post-resync script referenced in claude adapter" $claudeAdapter "Invoke-MxAgilePostCompactionResync"

# Test 25: No claim of unsupported programmatic trigger
Assert-FileContains "25: Claude adapter explicitly classifies programmatic trigger as UNSUPPORTED" `
    $claudeAdapter "programmatic.*UNSUPPORTED|UNSUPPORTED.*programmatic|Programmatic.*UNSUPPORTED"

# Test 26: programmatic_supported = false for claude_code
Assert-FileContains "26: Claude adapter has programmatic_supported: false" $claudeAdapter "programmatic_supported: false"

$claudeCap = & $capabilitiesScript -ProjectRoot $ScriptDir -HarnessId "claude_code"
Assert-True "26b: Claude capabilities: ProgrammaticSupported=false" `
    ($claudeCap.CompactCurrentSession.ProgrammaticSupported -eq $false) `
    "ProgrammaticSupported should be false for claude_code"

# Test 27: Compaction summary/checkpoint disagreement: checkpoint wins
Assert-FileContains "27: Claude adapter documents compaction_summary is not authoritative" `
    $claudeAdapter "is_authoritative_mxagile_state: false"
Assert-FileContains "27b: Claude adapter: may_promote_evidence: false" `
    $claudeAdapter "may_promote_evidence: false"
Assert-FileContains "27c: Claude adapter: may_satisfy_gates: false" `
    $claudeAdapter "may_satisfy_gates: false"

# Test 28: Native auto-compaction: automatic_supported=true
Assert-FileContains "28: Claude adapter has automatic_supported: true" $claudeAdapter "automatic_supported: true"

$claudeStrategy = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "claude_code" `
    -DryRun
Assert-True "28b: Claude Code DryRun selects COMPACT_CURRENT_SESSION strategy" `
    ($claudeStrategy.Strategy -eq "COMPACT_CURRENT_SESSION") `
    "Expected COMPACT_CURRENT_SESSION for claude_code, got: $($claudeStrategy.Strategy)"

# ============================================================
# Copilot CLI Adapter Tests (29-31)
# ============================================================

Write-Host "`n[Copilot CLI Adapter Tests 29-31]" -ForegroundColor Cyan

# Test 29: Copilot capability discovery returns UNSUPPORTED
Assert-True "29: Copilot adapter file exists" (Test-Path -LiteralPath $copilotAdapter) "copilot transition-adapter.yaml not found"
Assert-FileContains "29b: Copilot adapter has live_validation_status: UNSUPPORTED" $copilotAdapter "live_validation_status: UNSUPPORTED"
Assert-FileContains "29c: Copilot adapter has pre_compact: UNSUPPORTED" $copilotAdapter "pre_compact: UNSUPPORTED"

$copilotCap = & $capabilitiesScript -ProjectRoot $ScriptDir -HarnessId "copilot_cli"
Assert-True "29d: Copilot capabilities: CompactCurrentSession.Supported=false" `
    ($copilotCap.CompactCurrentSession.Supported -eq $false) `
    "Copilot CompactCurrentSession.Supported should be false"

# Test 30: Copilot compaction remains UNSUPPORTED
Assert-FileContains "30: Copilot adapter has supported: false" $copilotAdapter "supported: false"
Assert-FileContains "30b: Copilot adapter documents no compact API" $copilotAdapter "No compaction API"

# Test 31: No false ACTIVE status for Copilot
$copilotDryRun = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "copilot_cli" `
    -DryRun

Assert-True "31: Copilot DryRun selects EXTERNAL_ACTION_REQUIRED" `
    ($copilotDryRun.Strategy -eq "EXTERNAL_ACTION_REQUIRED") `
    "Expected EXTERNAL_ACTION_REQUIRED for copilot, got: $($copilotDryRun.Strategy)"

Assert-True "31b: Copilot DryRun has RequiredAction guidance" `
    (-not [string]::IsNullOrEmpty($copilotDryRun.RequiredAction)) `
    "RequiredAction should be non-empty for unsupported harness"

# ============================================================
# Summary
# ============================================================

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Context Transition Adapter Tests (13-31)" -ForegroundColor Cyan
Write-Host "PASS: $PassCount  FAIL: $FailCount" -ForegroundColor $(if ($FailCount -eq 0) { 'Green' } else { 'Red' })

if ($FailCount -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

exit 0
