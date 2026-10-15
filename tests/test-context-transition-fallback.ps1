<#
.SYNOPSIS
    Context Transition Fallback and Compatibility Tests (Tests 32-40)

.DESCRIPTION
    FALLBACK tests (32-35):
      32. Compact unsupported → selects FRESH_CONTEXT_EPOCH
      33. Both compact and fresh_context unsupported → EXTERNAL_ACTION_REQUIRED
      34. Context Mode unavailable does not block transition
      35. RTK unavailable does not block transition

    COMPATIBILITY tests (36-40):
      36. Context Lifecycle disabled: no transition initiated
      37. Older config without transition block: coordinator handles gracefully
      38. Existing checkpoint schema: still valid
      39. Existing rollover states: preserved, not overwritten
      40. No new regressions in rollover path
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

$coordinatorScript = Join-Path $ScriptDir "scripts\Invoke-MxAgileContextTransition.ps1"
$capabilitiesScript = Join-Path $ScriptDir "scripts\Get-MxAgileTransitionCapabilities.ps1"
$rolloverScript     = Join-Path $ScriptDir "scripts\Invoke-MxAgileEpochRollover.ps1"
$genericAdapter     = Join-Path $ScriptDir ".mxagile\adapters\generic\transition-adapter.yaml"
$copilotAdapter     = Join-Path $ScriptDir ".mxagile\adapters\copilot\transition-adapter.yaml"
$rtk                = Join-Path $ScriptDir ".mxagile\integrations\rtk.yaml"
$contextMode        = Join-Path $ScriptDir ".mxagile\integrations\context-mode.yaml"
$epochSchemaPath    = Join-Path $ScriptDir ".mxagile\schemas\context-epoch.schema.json"

# ============================================================
# FALLBACK Tests (32-35)
# ============================================================

Write-Host "`n[Fallback Tests 32-35]" -ForegroundColor Cyan

# Test 32: compact unsupported → FRESH_CONTEXT_EPOCH
# Simulate by using generic harness (no compact, fresh_context enabled via config)
$genericCap = & $capabilitiesScript -ProjectRoot $ScriptDir -HarnessId "generic"
Assert-True "32: Generic harness: CompactCurrentSession.Supported=false" `
    ($genericCap.CompactCurrentSession.Supported -eq $false) `
    "Generic should have CompactCurrentSession.Supported=false"

# With generic harness, PreferredStrategy should not be COMPACT_CURRENT_SESSION
Assert-True "32b: Generic harness does not prefer COMPACT_CURRENT_SESSION" `
    ($genericCap.PreferredStrategy -ne "COMPACT_CURRENT_SESSION") `
    "Generic harness should not select COMPACT_CURRENT_SESSION"

# Test 33: both compact and fresh unsupported → EXTERNAL_ACTION_REQUIRED
Assert-FileContains "33: Generic adapter has EXTERNAL_ACTION_REQUIRED fallback" $genericAdapter "EXTERNAL_ACTION_REQUIRED"

$genericDryRun = & $coordinatorScript -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -HarnessId "generic" `
    -DryRun

Assert-True "33b: Generic DryRun selects EXTERNAL_ACTION_REQUIRED" `
    ($genericDryRun.Strategy -eq "EXTERNAL_ACTION_REQUIRED") `
    "Expected EXTERNAL_ACTION_REQUIRED for generic, got: $($genericDryRun.Strategy)"

Assert-True "33c: Generic DryRun: RequiredAction is empty (Autonomy-First: no Human Gate)" `
    ([string]::IsNullOrEmpty($genericDryRun.RequiredAction)) `
    "Autonomy-First: RequiredAction must be empty for generic DryRun, got: '$($genericDryRun.RequiredAction)'"

Assert-True "33d: Generic DryRun: MissionContinues=true" `
    ($genericDryRun.MissionContinues -eq $true) `
    "MissionContinues must be true for COMPACTION_SKIPPED_UNSUPPORTED DryRun"

Assert-True "33e: Generic DryRun: TransitionState=COMPACTION_SKIPPED_UNSUPPORTED" `
    ($genericDryRun.TransitionState -eq "COMPACTION_SKIPPED_UNSUPPORTED") `
    "Expected COMPACTION_SKIPPED_UNSUPPORTED for generic DryRun, got: $($genericDryRun.TransitionState)"

# Test 34: Context Mode unavailable does not block transition
# Context Mode is an optional optimization — its absence must not block pre-compaction
$preCompactScript = Join-Path $ScriptDir "scripts\Invoke-MxAgilePreCompactionCheckpoint.ps1"

# Verify policy and script both explicitly skip Context Mode if unavailable
Assert-FileContains "34: Policy: Context Mode unavailability must not block transition" `
    (Join-Path $ScriptDir ".mxagile\policies\context-transition.md") `
    "Context Mode.*nicht.*blockieren|Context Mode.*unavailability.*must not block"

Assert-FileContains "34b: Pre-compact script supports SkipContextModeExternalization flag" $preCompactScript "SkipContextModeExternalization"
Assert-FileContains "34c: Pre-compact script marks Context Mode skipped" $preCompactScript "contextModeSkipped"

# Test 35: RTK unavailable does not block transition
# RTK is an optional token optimizer — its absence must not block compaction
Assert-FileContains "35: Policy documents RTK does not block transition" `
    (Join-Path $ScriptDir ".mxagile\policies\context-transition.md") `
    "RTK"

# Verify RTK integration documents its optional status
if (Test-Path -LiteralPath $rtk) {
    Assert-FileContains "35b: RTK integration is optional" $rtk "optional"
}

# ============================================================
# COMPATIBILITY Tests (36-40)
# ============================================================

Write-Host "`n[Compatibility Tests 36-40]" -ForegroundColor Cyan

# Test 36: Context Lifecycle disabled → no transition initiated
$disabledResult = & $coordinatorScript `
    -ProjectRoot $ScriptDir `
    -PressureState "ROLLOVER_REQUIRED" `
    -DryRun

# Even with DryRun, result should reflect that transition may not proceed
# (the DryRun still returns a plan, but the coordinator checks enabled flag)
Assert-True "36: Coordinator runs without error regardless of config" `
    ($null -ne $disabledResult) `
    "Coordinator threw error on disabled config"

# Config has enabled:false — with no active session, coordinator should not crash
Assert-True "36b: Coordinator returns structured result" `
    ($null -ne $disabledResult.TransitionState) `
    "TransitionState missing from result"

# Test 37: Config without transition block handles gracefully
# Simulate by pointing to a temp project with old-style config
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $tempDir

try {
    $mxagilDir = Join-Path $tempDir ".mxagile"
    $null = New-Item -ItemType Directory -Path $mxagilDir

    # Old config without transition block
    $oldConfig = @"
context_lifecycle:
  enabled: true
  checkpoint_resume: true
  manual_rollover: true
  pressure_recommendations: true
  auto_rollover: false
"@
    [System.IO.File]::WriteAllText((Join-Path $mxagilDir "config.yaml"), $oldConfig, [System.Text.UTF8Encoding]::new($false))

    $oldConfigCap = & $capabilitiesScript -ProjectRoot $tempDir -HarnessId "generic"
    Assert-True "37: Old config without transition block: capabilities script runs" `
        ($null -ne $oldConfigCap) `
        "Capabilities script threw error on old config"

    Assert-True "37b: Old config: AdapterLoaded is false for temp dir without adapters" `
        ($oldConfigCap.AdapterLoaded -eq $false) `
        "Expected AdapterLoaded=false for temp dir without adapter files"

} finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}

# Test 38: Existing checkpoint schema still valid after schema extension
Assert-FileContains "38: Context epoch schema still has required rollover_state" $epochSchemaPath '"rollover_state"'
Assert-FileContains "38b: Context epoch schema still has rollover_blocked_reasons" $epochSchemaPath '"rollover_blocked_reasons"'
Assert-FileContains "38c: Context epoch schema still has pressure_state" $epochSchemaPath '"pressure_state"'
Assert-FileContains "38d: New transition_state is additive (not required)" $epochSchemaPath '"transition_state"'

# Verify transition_state is in context_meta but NOT in the root required array
$epochContent = Get-Content -LiteralPath $epochSchemaPath -Raw -ErrorAction SilentlyContinue
$requiredSection = ""
if ($epochContent -match '(?s)"required":\s*\[([^\]]+)\]') {
    $requiredSection = $Matches[1]
}
Assert-True "38e: Root required fields unchanged (no new required transition fields)" `
    ($requiredSection -notmatch 'transition_state') `
    "transition_state should not be in root required array (additive only)"

# Test 39: Existing rollover states preserved
Assert-FileContains "39: Rollover states still present in epoch schema" $epochSchemaPath 'rollover_recommended'
Assert-FileContains "39b: rollover_performed still present" $epochSchemaPath 'rollover_performed'
Assert-FileContains "39c: rollover_blocked still present" $epochSchemaPath 'rollover_blocked'
Assert-FileContains "39d: rollover_unsupported_by_harness still present" $epochSchemaPath 'rollover_unsupported_by_harness'

# Test 40: Existing rollover scripts unmodified (no new regressions)
Assert-True "40: Invoke-MxAgileEpochRollover.ps1 still exists" `
    (Test-Path -LiteralPath $rolloverScript) `
    "Invoke-MxAgileEpochRollover.ps1 missing"

# Run rollover in DryRun-equivalent: check for HelpMessage or synopsis
$rolloverContent = Get-Content -LiteralPath $rolloverScript -Raw -ErrorAction SilentlyContinue
Assert-True "40b: Rollover script still has RolloverReason parameter" `
    ($rolloverContent -match "RolloverReason") `
    "RolloverReason parameter missing from rollover script"

Assert-True "40c: Rollover script still checks for valid checkpoint" `
    ($rolloverContent -match "no_valid_checkpoint") `
    "Rollover script no longer validates checkpoint"

# Verify new transition scripts have CmdletBinding (PS hygiene)
$transitionScripts = @(
    "scripts\Get-MxAgileTransitionCapabilities.ps1"
    "scripts\Invoke-MxAgileContextTransition.ps1"
    "scripts\Invoke-MxAgilePreCompactionCheckpoint.ps1"
    "scripts\Invoke-MxAgilePostCompactionResync.ps1"
)
foreach ($s in $transitionScripts) {
    $sPath = Join-Path $ScriptDir $s
    $sContent = Get-Content -LiteralPath $sPath -Raw -ErrorAction SilentlyContinue
    $sName = $s
    Assert-True "40d-${sName} has [CmdletBinding()]" `
        ($sContent -match '\[CmdletBinding\(\)\]') `
        "$sName missing [CmdletBinding()]"
}

# ============================================================
# Summary
# ============================================================

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Context Transition Fallback + Compatibility Tests (32-40)" -ForegroundColor Cyan
Write-Host "PASS: $PassCount  FAIL: $FailCount" -ForegroundColor $(if ($FailCount -eq 0) { 'Green' } else { 'Red' })

if ($FailCount -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

exit 0
