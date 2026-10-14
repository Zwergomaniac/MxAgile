<#
.SYNOPSIS
    Context Lifecycle - Rollover, Pressure, Model Policy, and Adapter Tests

.DESCRIPTION
    Validates the remaining core Context Lifecycle architecture:

    Layer 1 (Static):
      A. Model-profiles.yaml structure and content
      B. Harness adapter schema structure and contract
      C. Context-epoch schema rollover_state field
      D. Config.yaml model profiles and natural boundary references
      E. Pilot configuration fixture

    Layer 2 (Policy):
      F. Model capability resolution hierarchy documented
      G. Pressure states complete (UNKNOWN through ROLLOVER_REQUIRED)
      H. Rollover safety conditions documented
      I. Natural boundary classes documented
      J. Feature control: auto_rollover disabled by default

    Layer 3 (Operational — uses temp git repos):
      K. Model policy resolution: harness overrides profile
      L. Model policy resolution: profile lookup by ModelId
      M. Model policy resolution: UNKNOWN when no data
      N. Pressure evaluation: UNKNOWN without measurement
      O. Pressure evaluation: UNKNOWN with measurement but no thresholds
      P. Pressure evaluation: NORMAL below threshold
      Q. Pressure evaluation: PRESSURE at threshold
      R. Pressure evaluation: ROLLOVER_RECOMMENDED
      S. Pressure evaluation: ROLLOVER_REQUIRED
      T. Rollover safety: blocked when feature controls disabled
      U. Rollover safety: blocked when working tree dirty
      V. Rollover safety: blocked when caller flags false
      W. Manual rollover: full operational roundtrip
      X. Manual rollover: blocked on terminal mission
      Y. Manual rollover: epoch ID increments correctly
      Z. Manual rollover: prior epoch archived

    Tests use GUID temp directories. All git operations use local repos.
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

# File paths
$modelProfilesPath  = Join-Path $ScriptDir ".mxagile\model-profiles.yaml"
$adapterSchemaPath  = Join-Path $ScriptDir ".mxagile\schemas\harness-adapter.schema.json"
$epochSchemaPath    = Join-Path $ScriptDir ".mxagile\schemas\context-epoch.schema.json"
$configPath         = Join-Path $ScriptDir ".mxagile\config.yaml"
$fixturesDir        = Join-Path $TestsDir "fixtures\context-lifecycle"
$pilotConfigFixture = Join-Path $fixturesDir "config-pilot-manual.yaml"
$ratioProfilesFix   = Join-Path $fixturesDir "model-profiles-with-ratios.yaml"
$adapterGwFixture   = Join-Path $fixturesDir "adapter-measurement-gateway.yaml"
$adapterNoMeasure   = Join-Path $fixturesDir "adapter-no-measurement.yaml"
$rolloverReadyFix   = Join-Path $fixturesDir "checkpoint-rollover-ready.yaml"
$policyPath         = Join-Path $ScriptDir ".mxagile\policies\context-lifecycle.md"
$docsPath           = Join-Path $ScriptDir "docs\context-lifecycle.md"

# Script paths
$modelPolicyScript  = Join-Path $ScriptDir "scripts\Get-MxAgileModelPolicy.ps1"
$pressureScript     = Join-Path $ScriptDir "scripts\Get-MxAgileContextPressure.ps1"
$safetyScript       = Join-Path $ScriptDir "scripts\Test-MxAgileRolloverSafety.ps1"
$rolloverScript     = Join-Path $ScriptDir "scripts\Invoke-MxAgileEpochRollover.ps1"
$writerScript       = Join-Path $ScriptDir "scripts\Write-MxAgileEpochCheckpoint.ps1"
$readerScript       = Join-Path $ScriptDir "scripts\Read-MxAgileEpochCheckpoint.ps1"

Write-Host ""
Write-Host "=== Context Lifecycle Rollover & Pressure Tests ===" -ForegroundColor Cyan
Write-Host ""

# ─── Preflight ───────────────────────────────────────────────────────────
Write-Host "--- Preflight ---" -ForegroundColor Yellow

Assert-True "Preflight: model-profiles.yaml exists"        (Test-Path -LiteralPath $modelProfilesPath) "Missing"
Assert-True "Preflight: harness-adapter.schema.json exists" (Test-Path -LiteralPath $adapterSchemaPath)  "Missing"
Assert-True "Preflight: Get-MxAgileModelPolicy.ps1 exists" (Test-Path -LiteralPath $modelPolicyScript)  "Missing"
Assert-True "Preflight: Get-MxAgileContextPressure.ps1"    (Test-Path -LiteralPath $pressureScript)     "Missing"
Assert-True "Preflight: Test-MxAgileRolloverSafety.ps1"    (Test-Path -LiteralPath $safetyScript)       "Missing"
Assert-True "Preflight: Invoke-MxAgileEpochRollover.ps1"   (Test-Path -LiteralPath $rolloverScript)     "Missing"

if ($FailCount -gt 0) {
    Write-Host "Preflight failed; cannot continue." -ForegroundColor Red
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════
# Layer 1: Static Structure Checks
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- A: Model Profiles Structure ---" -ForegroundColor Yellow

Assert-FileContains "A.1: profiles section exists"           $modelProfilesPath 'profiles:'
Assert-FileContains "A.2: claude-opus-4 profile defined"     $modelProfilesPath 'claude-opus-4:'
Assert-FileContains "A.3: context_window_tokens field"       $modelProfilesPath 'context_window_tokens:'
Assert-FileContains "A.4: fallback section exists"           $modelProfilesPath 'fallback:'
Assert-FileContains "A.5: policy_overrides section"          $modelProfilesPath 'policy_overrides:'
Assert-FileContains "A.6: 150k observation documented"       $modelProfilesPath '150k'
Assert-FileContains "A.7: generic-200k profile"              $modelProfilesPath 'generic-200k:'
Assert-FileContains "A.8: resolution hierarchy documented"   $modelProfilesPath 'harness.*profile.*fallback.*UNKNOWN|Resolution hierarchy'

Write-Host ""
Write-Host "--- B: Harness Adapter Schema ---" -ForegroundColor Yellow

$adapterJson = $null
try {
    $adapterJson = Get-Content -LiteralPath $adapterSchemaPath -Raw | ConvertFrom-Json
    Assert-True "B.1: Adapter schema is valid JSON" $true ""
} catch {
    Assert-True "B.1: Adapter schema is valid JSON" $false "Parse error: $_"
}

Assert-FileContains "B.2: model_capability defined"         $adapterSchemaPath '"model_capability"'
Assert-FileContains "B.3: context_measurement defined"      $adapterSchemaPath '"context_measurement"'
Assert-FileContains "B.4: harness_capability defined"       $adapterSchemaPath '"harness_capability"'
Assert-FileContains "B.5: transition_result defined"        $adapterSchemaPath '"transition_result"'
Assert-FileContains "B.6: can_start_fresh_context field"    $adapterSchemaPath '"can_start_fresh_context"'
Assert-FileContains "B.7: supports_epoch_transition"        $adapterSchemaPath '"supports_epoch_transition"'
Assert-FileContains "B.8: reliability enum"                 $adapterSchemaPath '"exact".*"estimate".*"stale"'
Assert-FileContains "B.9: adapter_version present"           $adapterSchemaPath '"adapter_version"'
Assert-FileContains "B.10: No hosted service"               $adapterSchemaPath 'No hosted service|No external network'

Write-Host ""
Write-Host "--- C: Context Epoch Schema - rollover_state ---" -ForegroundColor Yellow

Assert-FileContains "C.1: rollover_state field in schema"                $epochSchemaPath '"rollover_state"'
Assert-FileContains "C.2: not_applicable enum value"                     $epochSchemaPath '"not_applicable"'
Assert-FileContains "C.3: rollover_recommended enum"                     $epochSchemaPath '"rollover_recommended"'
Assert-FileContains "C.4: rollover_pending_safe_boundary enum"           $epochSchemaPath '"rollover_pending_safe_boundary"'
Assert-FileContains "C.5: rollover_ready enum"                           $epochSchemaPath '"rollover_ready"'
Assert-FileContains "C.6: rollover_performed enum"                       $epochSchemaPath '"rollover_performed"'
Assert-FileContains "C.7: rollover_blocked enum"                         $epochSchemaPath '"rollover_blocked"'
Assert-FileContains "C.8: rollover_unsupported_by_harness enum"          $epochSchemaPath '"rollover_unsupported_by_harness"'
Assert-FileContains "C.9: rollover_blocked_reasons array"                $epochSchemaPath '"rollover_blocked_reasons"'

Write-Host ""
Write-Host "--- D: Config - model profiles and boundary references ---" -ForegroundColor Yellow

Assert-FileContains "D.1: model_profiles reference in config"            $configPath 'model_profiles:'
Assert-FileContains "D.2: harness_adapter_schema reference"              $configPath 'harness_adapter_schema:'
Assert-FileContains "D.3: natural_rollover_boundaries list"              $configPath 'natural_rollover_boundaries:'
Assert-FileContains "D.4: discovery_to_implementation boundary"          $configPath 'discovery_to_implementation'
Assert-FileContains "D.5: implementation_to_verification boundary"       $configPath 'implementation_to_verification'
Assert-FileContains "D.6: pilot configuration documented"                $configPath 'Pilot configuration'

Write-Host ""
Write-Host "--- E: Pilot Configuration Fixture ---" -ForegroundColor Yellow

Assert-True "E.1: Pilot fixture exists" (Test-Path -LiteralPath $pilotConfigFixture) "Missing"
Assert-FileContains "E.2: enabled: true"                $pilotConfigFixture 'enabled: true'
Assert-FileContains "E.3: checkpoint_resume: true"      $pilotConfigFixture 'checkpoint_resume: true'
Assert-FileContains "E.4: manual_rollover: true"        $pilotConfigFixture 'manual_rollover: true'
Assert-FileContains "E.5: pressure_recommendations: true" $pilotConfigFixture 'pressure_recommendations: true'
Assert-FileContains "E.6: auto_rollover: false"         $pilotConfigFixture 'auto_rollover: false'

# ═══════════════════════════════════════════════════════════════════════════
# Layer 2: Policy Content Checks
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- F-J: Policy Content ---" -ForegroundColor Yellow

Assert-FileContains "F.1: Model-aware context management in docs"       $docsPath 'Model-Aware|model.aware|Model Capability'
Assert-FileContains "G.1: All five pressure states in schema"           $epochSchemaPath '"UNKNOWN".*"NORMAL".*"PRESSURE".*"ROLLOVER_RECOMMENDED".*"ROLLOVER_REQUIRED"'
Assert-FileContains "H.1: Safe boundary in docs or policy"             $docsPath 'Safe Rollover Boundaries|safe.*boundary|Unsafe Rollover'
Assert-FileContains "I.1: Natural boundary in config"                  $configPath 'natural_rollover_boundaries'
Assert-FileContains "J.1: auto_rollover false by default"              $configPath 'auto_rollover: false'

# ═══════════════════════════════════════════════════════════════════════════
# Layer 3: Operational Tests (temp git repos)
# ═══════════════════════════════════════════════════════════════════════════

function New-TempProject {
    $id  = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $env:TEMP "mxagile-ctx-rl-$id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & git -C $dir init -q 2>&1 | Out-Null
    & git -C $dir config user.email "test@mxagile.test" 2>&1 | Out-Null
    & git -C $dir config user.name  "MxAgile Test" 2>&1 | Out-Null
    & git -C $dir config core.autocrlf false 2>&1 | Out-Null
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

function Install-MxAgileConfig {
    param([string]$dir, [bool]$Enabled = $false, [bool]$ManualRollover = $false, [switch]$CommitSetup)
    $mxDir = Join-Path $dir ".mxagile"
    New-Item -ItemType Directory -Path $mxDir -Force | Out-Null
    $enabledStr = if ($Enabled) { "true" } else { "false" }
    $mrStr      = if ($ManualRollover) { "true" } else { "false" }
    $cfg = @"
context_lifecycle:
  enabled: $enabledStr
  checkpoint_resume: $enabledStr
  manual_rollover: $mrStr
  pressure_recommendations: false
  auto_rollover: false
  pressure_thresholds:
    pressure_tokens: null
    rollover_recommended_tokens: null
    rollover_required_tokens: null
"@
    $cfgPath = Join-Path $mxDir "config.yaml"
    [System.IO.File]::WriteAllText($cfgPath, $cfg, [System.Text.UTF8Encoding]::new($false))

    # Create .gitignore with .concord/ (operational store is always gitignored)
    $giPath = Join-Path $dir ".gitignore"
    [System.IO.File]::WriteAllText($giPath, ".concord/`r`n", [System.Text.UTF8Encoding]::new($false))

    if ($CommitSetup) {
        & git -C $dir add . 2>&1 | Out-Null
        & git -C $dir commit -m "setup" -q 2>&1 | Out-Null
    }
}

function Install-ModelProfiles {
    param([string]$dir, [bool]$WithRatios = $false)
    $mxDir = Join-Path $dir ".mxagile"
    New-Item -ItemType Directory -Path $mxDir -Force | Out-Null
    $ratioBlock = if ($WithRatios) {
        @"
policy_overrides:
  working_budget_ratio: 0.60
  pressure_ratio: 0.60
  rollover_recommended_ratio: 0.75
  rollover_required_ratio: 0.90
  safety_reserve_tokens: 20000
"@
    } else {
        @"
policy_overrides:
  working_budget_ratio: null
  pressure_ratio: null
  rollover_recommended_ratio: null
  rollover_required_ratio: null
  safety_reserve_tokens: null
"@
    }
    $profiles = @"
profiles:
  test-model-200k:
    context_window_tokens: 200000
  test-model-128k:
    context_window_tokens: 128000
fallback:
  context_window_tokens: null
$ratioBlock
"@
    $pPath = Join-Path $mxDir "model-profiles.yaml"
    [System.IO.File]::WriteAllText($pPath, $profiles, [System.Text.UTF8Encoding]::new($false))
}

# ─── K: Model policy - harness overrides profile ────────────────────────
Write-Host ""
Write-Host "--- K: Model policy - harness overrides profile ---" -ForegroundColor Yellow

$tempK = $null
try {
    $tempK = New-TempProject
    Install-ModelProfiles $tempK

    $result = & $modelPolicyScript -ProjectRoot $tempK -ModelId "test-model-200k" -HarnessContextWindow 250000
    Assert-True "K.1: Harness context window used (250000)" ($result.ContextWindow -eq 250000) "Got: $($result.ContextWindow)"
    Assert-True "K.2: CapabilitySource is harness"          ($result.CapabilitySource -eq "harness") "Got: $($result.CapabilitySource)"
    Assert-True "K.3: Resolved is true"                     $result.Resolved "Resolved was false"
} catch {
    Assert-True "K: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempK) { Remove-TempProject $tempK }
}

# ─── L: Model policy - profile lookup by ModelId ────────────────────────
Write-Host ""
Write-Host "--- L: Model policy - profile lookup ---" -ForegroundColor Yellow

$tempL = $null
try {
    $tempL = New-TempProject
    Install-ModelProfiles $tempL

    $result = & $modelPolicyScript -ProjectRoot $tempL -ModelId "test-model-128k"
    Assert-True "L.1: Profile context window 128000"   ($result.ContextWindow -eq 128000)  "Got: $($result.ContextWindow)"
    Assert-True "L.2: CapabilitySource is profile"     ($result.CapabilitySource -eq "profile") "Got: $($result.CapabilitySource)"
} catch {
    Assert-True "L: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempL) { Remove-TempProject $tempL }
}

# ─── M: Model policy - UNKNOWN when no data ─────────────────────────────
Write-Host ""
Write-Host "--- M: Model policy - UNKNOWN ---" -ForegroundColor Yellow

$tempM = $null
try {
    $tempM = New-TempProject
    Install-ModelProfiles $tempM

    $result = & $modelPolicyScript -ProjectRoot $tempM
    Assert-True "M.1: Resolved is false (no model info)"  (-not $result.Resolved) "Resolved was true"
    Assert-True "M.2: ContextWindow is null"               ($null -eq $result.ContextWindow) "Got: $($result.ContextWindow)"
    Assert-True "M.3: CapabilitySource is unknown"         ($result.CapabilitySource -eq "unknown") "Got: $($result.CapabilitySource)"
    Assert-True "M.4: PolicySource is unconfigured"        ($result.PolicySource -eq "unconfigured") "Got: $($result.PolicySource)"
} catch {
    Assert-True "M: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempM) { Remove-TempProject $tempM }
}

# ─── N: Pressure - UNKNOWN without measurement ──────────────────────────
Write-Host ""
Write-Host "--- N: Pressure - UNKNOWN without measurement ---" -ForegroundColor Yellow

$tempN = $null
try {
    $tempN = New-TempProject
    Install-MxAgileConfig $tempN
    Install-ModelProfiles $tempN -WithRatios $true

    $result = & $pressureScript -ProjectRoot $tempN
    Assert-True "N.1: PressureState is UNKNOWN"           ($result.PressureState -eq "UNKNOWN") "Got: $($result.PressureState)"
    Assert-True "N.2: Reason mentions no measurement"     ($result.Reason -match 'measurement|No reliable') "Got: $($result.Reason)"
} catch {
    Assert-True "N: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempN) { Remove-TempProject $tempN }
}

# ─── O: Pressure - UNKNOWN with measurement but no thresholds ───────────
Write-Host ""
Write-Host "--- O: Pressure - UNKNOWN, measurement but no thresholds ---" -ForegroundColor Yellow

$tempO = $null
try {
    $tempO = New-TempProject
    Install-MxAgileConfig $tempO
    Install-ModelProfiles $tempO -WithRatios $false

    $result = & $pressureScript -ProjectRoot $tempO -EstimatedContextTokens 160000 -TokenSource "user_supplied" -ModelId "test-model-200k"
    Assert-True "O.1: PressureState is UNKNOWN"           ($result.PressureState -eq "UNKNOWN") "Got: $($result.PressureState)"
    Assert-True "O.2: Reason mentions no thresholds"      ($result.Reason -match 'threshold') "Got: $($result.Reason)"
} catch {
    Assert-True "O: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempO) { Remove-TempProject $tempO }
}

# ─── P: Pressure - NORMAL below threshold ───────────────────────────────
Write-Host ""
Write-Host "--- P: Pressure - NORMAL ---" -ForegroundColor Yellow

$tempP = $null
try {
    $tempP = New-TempProject
    Install-MxAgileConfig $tempP
    Install-ModelProfiles $tempP -WithRatios $true

    # 60% of 200000 = 120000 is pressure threshold; 100000 is below
    $result = & $pressureScript -ProjectRoot $tempP -EstimatedContextTokens 100000 -TokenSource "gateway_measurement" -ModelId "test-model-200k"
    Assert-True "P.1: PressureState is NORMAL"            ($result.PressureState -eq "NORMAL") "Got: $($result.PressureState)"
    Assert-True "P.2: ContextRatio is 0.5"                ($result.ContextRatio -eq 0.5) "Got: $($result.ContextRatio)"
} catch {
    Assert-True "P: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempP) { Remove-TempProject $tempP }
}

# ─── Q: Pressure - PRESSURE at threshold ────────────────────────────────
Write-Host ""
Write-Host "--- Q: Pressure - PRESSURE ---" -ForegroundColor Yellow

$tempQ = $null
try {
    $tempQ = New-TempProject
    Install-MxAgileConfig $tempQ
    Install-ModelProfiles $tempQ -WithRatios $true

    # 60% of 200000 = 120000; 130000 is at or above PRESSURE, below REC (150000)
    $result = & $pressureScript -ProjectRoot $tempQ -EstimatedContextTokens 130000 -TokenSource "gateway_measurement" -ModelId "test-model-200k"
    Assert-True "Q.1: PressureState is PRESSURE"          ($result.PressureState -eq "PRESSURE") "Got: $($result.PressureState)"
} catch {
    Assert-True "Q: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempQ) { Remove-TempProject $tempQ }
}

# ─── R: Pressure - ROLLOVER_RECOMMENDED ─────────────────────────────────
Write-Host ""
Write-Host "--- R: Pressure - ROLLOVER_RECOMMENDED ---" -ForegroundColor Yellow

$tempR = $null
try {
    $tempR = New-TempProject
    Install-MxAgileConfig $tempR
    Install-ModelProfiles $tempR -WithRatios $true

    # 75% of 200000 = 150000; 160000 is at or above ROLLOVER_RECOMMENDED, below REQ (180000)
    $result = & $pressureScript -ProjectRoot $tempR -EstimatedContextTokens 160000 -TokenSource "user_supplied" -ModelId "test-model-200k"
    Assert-True "R.1: PressureState is ROLLOVER_RECOMMENDED" ($result.PressureState -eq "ROLLOVER_RECOMMENDED") "Got: $($result.PressureState)"
    Assert-True "R.2: ContextRatio is 0.8"                   ($result.ContextRatio -eq 0.8) "Got: $($result.ContextRatio)"
} catch {
    Assert-True "R: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempR) { Remove-TempProject $tempR }
}

# ─── S: Pressure - ROLLOVER_REQUIRED ────────────────────────────────────
Write-Host ""
Write-Host "--- S: Pressure - ROLLOVER_REQUIRED ---" -ForegroundColor Yellow

$tempS = $null
try {
    $tempS = New-TempProject
    Install-MxAgileConfig $tempS
    Install-ModelProfiles $tempS -WithRatios $true

    # 90% of 200000 = 180000; 190000 is at or above ROLLOVER_REQUIRED
    $result = & $pressureScript -ProjectRoot $tempS -EstimatedContextTokens 190000 -TokenSource "harness_reported" -ModelId "test-model-200k"
    Assert-True "S.1: PressureState is ROLLOVER_REQUIRED"  ($result.PressureState -eq "ROLLOVER_REQUIRED") "Got: $($result.PressureState)"
} catch {
    Assert-True "S: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempS) { Remove-TempProject $tempS }
}

# ─── T: Safety - blocked when feature controls disabled ─────────────────
Write-Host ""
Write-Host "--- T: Safety - feature controls block ---" -ForegroundColor Yellow

$tempT = $null
try {
    $tempT = New-TempProject
    Install-MxAgileConfig $tempT -Enabled $false -ManualRollover $false

    # Write a checkpoint so the reader finds something
    & $writerScript -ProjectRoot $tempT -MissionId "MISSION-T" -EpochId "EPOCH-001" -NextAction "test"

    $callerFlags = @{
        no_tool_call_in_flight     = $true
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }
    $result = & $safetyScript -ProjectRoot $tempT -CallerSafetyFlags $callerFlags
    Assert-True "T.1: Safety.Safe is false"                (-not $result.Safe) "Safe was true"
    Assert-True "T.2: feature_controls in blocking"        ($result.BlockingConditions -join '|' | Select-String -Pattern 'feature_controls' -Quiet) "Not found in blocking"
} catch {
    Assert-True "T: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempT) { Remove-TempProject $tempT }
}

# ─── U: Safety - blocked when working tree dirty ────────────────────────
Write-Host ""
Write-Host "--- U: Safety - working tree dirty ---" -ForegroundColor Yellow

$tempU = $null
try {
    $tempU = New-TempProject
    Install-MxAgileConfig $tempU -Enabled $true -ManualRollover $true

    & $writerScript -ProjectRoot $tempU -MissionId "MISSION-U" -EpochId "EPOCH-001" -NextAction "test"

    # Make working tree dirty
    $dirtyFile = Join-Path $tempU "dirty.txt"
    [System.IO.File]::WriteAllText($dirtyFile, "dirty`r`n", [System.Text.UTF8Encoding]::new($false))

    $callerFlags = @{
        no_tool_call_in_flight     = $true
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }
    $result = & $safetyScript -ProjectRoot $tempU -CallerSafetyFlags $callerFlags
    Assert-True "U.1: Safety.Safe is false"                (-not $result.Safe) "Safe was true"
    Assert-True "U.2: working_tree_dirty in blocking"      ($result.BlockingConditions -join '|' | Select-String -Pattern 'working_tree' -Quiet) "Not in blocking"
} catch {
    Assert-True "U: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempU) { Remove-TempProject $tempU }
}

# ─── V: Safety - blocked when caller flags false ────────────────────────
Write-Host ""
Write-Host "--- V: Safety - caller flags false ---" -ForegroundColor Yellow

$tempV = $null
try {
    $tempV = New-TempProject
    Install-MxAgileConfig $tempV -Enabled $true -ManualRollover $true

    & $writerScript -ProjectRoot $tempV -MissionId "MISSION-V" -EpochId "EPOCH-001" -NextAction "test"

    # Deliberately leave no_tool_call_in_flight false
    $callerFlags = @{
        no_tool_call_in_flight     = $false
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }
    $result = & $safetyScript -ProjectRoot $tempV -CallerSafetyFlags $callerFlags
    Assert-True "V.1: Safety.Safe is false"                (-not $result.Safe) "Safe was true"
    Assert-True "V.2: caller_flag in blocking"             ($result.BlockingConditions -join '|' | Select-String -Pattern 'caller_flag' -Quiet) "Not in blocking"
} catch {
    Assert-True "V: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempV) { Remove-TempProject $tempV }
}

# ─── W: Manual rollover - full operational roundtrip ────────────────────
Write-Host ""
Write-Host "--- W: Manual rollover - full roundtrip ---" -ForegroundColor Yellow

$tempW = $null
try {
    $tempW = New-TempProject
    Install-MxAgileConfig $tempW -Enabled $true -ManualRollover $true -CommitSetup

    & $writerScript -ProjectRoot $tempW `
        -MissionId "MISSION-W-ROLLOVER" `
        -MissionObjective "Test rollover roundtrip" `
        -EpochId "EPOCH-001" `
        -NextAction "Proceed to W01-03"

    $callerFlags = @{
        no_tool_call_in_flight     = $true
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }

    $result = & $rolloverScript `
        -ProjectRoot $tempW `
        -RolloverReason "manual_rollover" `
        -NextAction "Resume at W01-03 after rollover" `
        -NextActionSafe $false `
        -NextChecklistItem "W01-03" `
        -HotContextSummary "Mission: rollover test. Next: W01-03." `
        -CallerSafetyFlags $callerFlags

    Assert-True "W.1: Rollover success"                    $result.Success "Success was false. Blocking: $($result.BlockingConditions -join '; ')"
    Assert-True "W.2: RolloverState is rollover_performed" ($result.RolloverState -eq "rollover_performed") "Got: $($result.RolloverState)"
    Assert-True "W.3: PriorEpochId is EPOCH-001"          ($result.PriorEpochId -eq "EPOCH-001") "Got: $($result.PriorEpochId)"
    Assert-True "W.4: NewEpochId is EPOCH-002"            ($result.NewEpochId -eq "EPOCH-002") "Got: $($result.NewEpochId)"
    Assert-True "W.5: CheckpointPath is non-empty"        (-not [string]::IsNullOrEmpty($result.CheckpointPath)) "Empty"
    Assert-True "W.6: HandoffPath is non-empty"           (-not [string]::IsNullOrEmpty($result.HandoffPath)) "Empty"
    Assert-True "W.7: RequiredAction mentions re-sync"    ($result.RequiredAction -match 'Re-sync|Sync') "Got: $($result.RequiredAction)"

    # Verify the new checkpoint reads correctly
    $newCp = & $readerScript -ProjectRoot $tempW
    Assert-True "W.8: New checkpoint valid"                $newCp.Valid "Invalid: $($newCp.ConflictReason)"
    Assert-True "W.9: New epoch is EPOCH-002"              ($newCp.EpochId -eq "EPOCH-002") "Got: $($newCp.EpochId)"
    Assert-True "W.10: Mission ID preserved"               ($newCp.MissionId -eq "MISSION-W-ROLLOVER") "Got: $($newCp.MissionId)"

    # Verify previous_epochs entry
    $cpContent = Get-Content -LiteralPath $result.CheckpointPath -Raw -Encoding UTF8
    Assert-True "W.11: previous_epochs contains EPOCH-001" ($cpContent -match 'EPOCH-001') "EPOCH-001 not in previous_epochs"
    Assert-True "W.12: rollover_reason recorded"           ($cpContent -match 'manual_rollover') "manual_rollover not found"
} catch {
    Assert-True "W: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempW) { Remove-TempProject $tempW }
}

# ─── X: Manual rollover - blocked on terminal mission ───────────────────
Write-Host ""
Write-Host "--- X: Manual rollover - terminal mission ---" -ForegroundColor Yellow

$tempX = $null
try {
    $tempX = New-TempProject
    Install-MxAgileConfig $tempX -Enabled $true -ManualRollover $true -CommitSetup

    & $writerScript -ProjectRoot $tempX `
        -MissionId "MISSION-X-DONE" `
        -MissionStatus "complete" `
        -EpochId "EPOCH-003" `
        -NextAction "none"

    $callerFlags = @{
        no_tool_call_in_flight     = $true
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }

    $result = & $rolloverScript -ProjectRoot $tempX -CallerSafetyFlags $callerFlags
    Assert-True "X.1: Rollover failed (terminal)"          (-not $result.Success) "Success was true"
    Assert-True "X.2: RolloverState is rollover_blocked"   ($result.RolloverState -eq "rollover_blocked") "Got: $($result.RolloverState)"
    Assert-True "X.3: Blocking mentions terminal"          ($result.BlockingConditions -join '|' | Select-String -Pattern 'terminal|complete' -Quiet) "Not in blocking"
} catch {
    Assert-True "X: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempX) { Remove-TempProject $tempX }
}

# ─── Y: Manual rollover - epoch ID increments correctly ─────────────────
Write-Host ""
Write-Host "--- Y: Epoch ID increment ---" -ForegroundColor Yellow

$tempY = $null
try {
    $tempY = New-TempProject
    Install-MxAgileConfig $tempY -Enabled $true -ManualRollover $true -CommitSetup

    & $writerScript -ProjectRoot $tempY `
        -MissionId "MISSION-Y" `
        -EpochId "EPOCH-009" `
        -NextAction "test"

    $callerFlags = @{
        no_tool_call_in_flight     = $true
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }

    $result = & $rolloverScript -ProjectRoot $tempY -CallerSafetyFlags $callerFlags
    Assert-True "Y.1: NewEpochId is EPOCH-010"            ($result.NewEpochId -eq "EPOCH-010") "Got: $($result.NewEpochId)"
} catch {
    Assert-True "Y: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempY) { Remove-TempProject $tempY }
}

# ─── Z: Manual rollover - prior epoch archived ──────────────────────────
Write-Host ""
Write-Host "--- Z: Prior epoch archived ---" -ForegroundColor Yellow

$tempZ = $null
try {
    $tempZ = New-TempProject
    Install-MxAgileConfig $tempZ -Enabled $true -ManualRollover $true -CommitSetup

    & $writerScript -ProjectRoot $tempZ `
        -MissionId "MISSION-Z" `
        -EpochId "EPOCH-005" `
        -NextAction "test"

    $callerFlags = @{
        no_tool_call_in_flight     = $true
        no_file_write_in_flight    = $true
        no_checkpoint_write_active = $true
        no_pending_commit          = $true
    }

    $result = & $rolloverScript -ProjectRoot $tempZ -CallerSafetyFlags $callerFlags

    $archivePath = Join-Path $tempZ ".concord\context-epoch-EPOCH-005.yaml"
    Assert-True "Z.1: Archive file exists"                 (Test-Path -LiteralPath $archivePath) "Missing: $archivePath"
    Assert-True "Z.2: Archive contains EPOCH-005"          ((Get-Content -LiteralPath $archivePath -Raw -Encoding UTF8) -match 'EPOCH-005') "EPOCH-005 not in archive"
} catch {
    Assert-True "Z: No unexpected exception" $false "Exception: $_"
} finally {
    if ($null -ne $tempZ) { Remove-TempProject $tempZ }
}

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== Rollover & Pressure Tests Summary ===" -ForegroundColor Cyan
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
exit 0

