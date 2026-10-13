<#
.SYNOPSIS
    Execution-Environment Intent Tests

.DESCRIPTION
    Validates the execution-intent policy and its integration with the
    operating-mode detection framework and orchestrator Startup Re-Sync.

    All tests are static/contract -- no real Studio Pro or Concord MCP
    installation required.

    Scenarios:
    1.  Studio Pro detected + Concord MCP detected + unresolved intent
        -> clarification required.
    2.  Studio Pro detected + Concord MCP NOT detected
        -> no clarification from weak signal alone.
    3.  Studio Pro NOT detected + Concord MCP detected
        -> no Studio-Pro/live clarification.
    4.  Detection UNKNOWN
        -> UNKNOWN must not be treated as positive detection.
    5.  Both detected + explicit Studio Pro/live user intent
        -> no clarification; use requested mode.
    6.  Both detected + explicit normal/headless intent
        -> no clarification; respect user choice.
    7.  Both detected + previously confirmed Studio Pro/live
        -> do not ask again while environment remains applicable.
    8.  Both detected + previously confirmed normal/headless
        -> do not ask again merely because strong signal still exists.
    9.  Previous Studio Pro/live intent + Studio Pro/live capability disappears
        -> changed environment is surfaced; no false live state.
    10. Execution-mode clarification does not satisfy lifecycle gates.
    11. Execution-mode clarification does not change mission completion.
    12. Execution-mode clarification does not alter evidence states.
    13. Re-Sync preserves a still-valid user execution choice.
    14. Explicit user instruction wins over inferred/recommended environment mode.
    15. Existing SP-on / LIVE-SP-CURRENT behavior remains backward compatible.
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

function Assert-FileNotContains {
    param([string]$TestName, [string]$FilePath, [string]$Pattern)
    $content = Get-Content -LiteralPath $FilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Assert-True $TestName $false "File not found: $FilePath"
    } else {
        Assert-True $TestName ($content -notmatch $Pattern) "Forbidden pattern '$Pattern' found in $FilePath"
    }
}

$intentPolicyPath = Join-Path $ScriptDir '.mxagile\policies\execution-intent.md'
$orchestratorPath = Join-Path $ScriptDir '.mxagile\orchestrator.md'
$capabilitiesPath = Join-Path $ScriptDir '.mxagile\capabilities.yaml'

Write-Host ''
Write-Host '=== Execution-Environment Intent Tests ==='
Write-Host ''

# =========================================================================
# Prerequisites: canonical files must exist
# =========================================================================

Write-Host '--- Prerequisites: required files exist ---'

Assert-True 'prereq: execution-intent.md exists' `
    (Test-Path -LiteralPath $intentPolicyPath) `
    "Canonical policy not found: $intentPolicyPath"

Assert-True 'prereq: capabilities.yaml exists' `
    (Test-Path -LiteralPath $capabilitiesPath) `
    "Capability registry not found: $capabilitiesPath"

Assert-True 'prereq: orchestrator.md exists' `
    (Test-Path -LiteralPath $orchestratorPath) `
    "Orchestrator not found: $orchestratorPath"

Write-Host ''

# =========================================================================
# Core invariant: ENVIRONMENT CAPABILITY != USER INTENT
# =========================================================================

Write-Host '--- Core Invariant ---'

Assert-FileContains 'INV.1: policy states environment capability != user intent' `
    $intentPolicyPath 'ENVIRONMENT CAPABILITY.*USER INTENT|ENVIRONMENT CAPABILITY.{0,10}USER INTENT'

Assert-FileContains 'INV.2: policy: detected does NOT authorize automatic choice' `
    $intentPolicyPath '(?i)does NOT authorize|not.*authorize.*automatic'

Assert-FileContains 'INV.3: policy defines execution_intent as separate from environment' `
    $intentPolicyPath 'execution_intent|Execution Intent'

Assert-FileContains 'INV.4: policy defines environment detection as separate concept' `
    $intentPolicyPath 'Environment Detection|environment detection'

Write-Host ''

# =========================================================================
# Scenario 1: Strong signal + unresolved intent -> ask once
# =========================================================================

Write-Host '--- Scenario 1: Strong signal + unresolved intent -> clarification required ---'

Assert-FileContains '1.1: policy defines strong signal' `
    $intentPolicyPath '(?i)Strong Signal'

Assert-FileContains '1.2: strong signal requires both Studio Pro AND Concord MCP' `
    $intentPolicyPath '(?i)LIVE-SP-CURRENT.*Concord MCP|Concord MCP.*LIVE-SP-CURRENT|studio_pro.*detected.*concord_mcp.*detected'

Assert-FileContains '1.3: policy: unresolved intent + strong signal -> ask once' `
    $intentPolicyPath '(?i)ask exactly once|GENAU EINE Frage|ask.*once'

Assert-FileContains '1.4: orchestrator: Schritt 1b executes clarification for unresolved intent' `
    $orchestratorPath '(?i)Intent unaufgeloest|unresolved|unaufgeloest'

Assert-FileContains '1.5: orchestrator: Schritt 1b is part of Startup Re-Sync' `
    $orchestratorPath '(?i)Schritt 1b|1b.*Ausfuehrungs'

Write-Host ''

# =========================================================================
# Scenario 2: Weak signal only -> no clarification
# =========================================================================

Write-Host '--- Scenario 2: Weak signal (Studio Pro only) -> no clarification ---'

Assert-FileContains '2.1: policy defines weak signal' `
    $intentPolicyPath '(?i)Weak Signal'

Assert-FileContains '2.2: policy: weak signal -> do NOT interrupt work' `
    $intentPolicyPath '(?i)Do NOT interrupt|no.*interrupt|normal work'

Assert-FileContains '2.3: policy: weak = Studio Pro detected + Concord MCP not detected' `
    $intentPolicyPath '(?i)Studio Pro detected.*Concord MCP NOT|LIVE-SP-CURRENT.*NOT detected|not detected or unknown'

Assert-FileContains '2.4: orchestrator: Concord MCP not detected -> Schritt 2 direkt' `
    $orchestratorPath '(?i)NEIN.*Schwaches Signal|Schwaches Signal.*Schritt 2|not detected.*direct'

Write-Host ''

# =========================================================================
# Scenario 3: Studio Pro not detected + Concord MCP detected -> no clarification
# =========================================================================

Write-Host '--- Scenario 3: Studio Pro not detected -> no Studio-Pro/live clarification ---'

Assert-FileContains '3.1: policy: strong signal requires LIVE-SP-CURRENT (not just Concord MCP)' `
    $intentPolicyPath 'LIVE-SP-CURRENT'

Assert-FileContains '3.2: policy suppression: operating mode not LIVE-SP-CURRENT -> no question' `
    $intentPolicyPath '(?i)LIVE-SP-CURRENT.*headless|CLOSED-AUTONOM.*no question|operating mode is not LIVE'

Assert-FileContains '3.3: orchestrator: only if LIVE-SP-CURRENT -> evaluate intent' `
    $orchestratorPath '(?i)nur.*LIVE-SP-CURRENT|only.*LIVE-SP-CURRENT|Betriebsmodus.*LIVE-SP-CURRENT'

Write-Host ''

# =========================================================================
# Scenario 4: Detection UNKNOWN -> must not be treated as positive
# =========================================================================

Write-Host '--- Scenario 4: Detection UNKNOWN -> not treated as detected ---'

Assert-FileContains '4.1: policy: unknown is a distinct state' `
    $intentPolicyPath '`unknown`|state: unknown|unknown.*inaccessible'

Assert-FileContains '4.2: policy: unknown MUST NOT become detected' `
    $intentPolicyPath '(?i)MUST NOT.*become.*detected|unknown.*not.*detected|unknown.*not.*positive'

Assert-FileContains '4.3: policy: unknown alone does not trigger strong-signal prompt' `
    $intentPolicyPath '(?i)UNKNOWN alone.*not trigger|unknown.*does not trigger'

Write-Host ''

# =========================================================================
# Scenario 5: Both detected + explicit Studio Pro/live -> no clarification
# =========================================================================

Write-Host '--- Scenario 5: Explicit Studio Pro/live intent -> no clarification ---'

Assert-FileContains '5.1: policy defines Explicit User Intent as a suppression condition' `
    $intentPolicyPath '(?i)Explicit User Intent|source: explicit_user'

Assert-FileContains '5.2: policy: explicit intent -> do NOT ask; honor stated preference' `
    $intentPolicyPath '(?i)Do NOT ask\. Honor|Honor the stated preference|Do NOT ask.*Honor'

Assert-FileContains '5.3: policy: suppress when current request contains explicit preference' `
    $intentPolicyPath '(?i)current request.*explicit|suppress.*explicit.*preference'

Write-Host ''

# =========================================================================
# Scenario 6: Both detected + explicit normal/headless -> no clarification
# =========================================================================

Write-Host '--- Scenario 6: Explicit normal/headless intent -> respected without question ---'

Assert-FileContains '6.1: policy: normal_headless is a valid intent value' `
    $intentPolicyPath 'normal_headless'

Assert-FileContains '6.2: policy: explicit headless instruction overrides strong signal' `
    $intentPolicyPath '(?i)headless.*without question|user.*says.*headless|normal_headless.*without question'

Assert-FileContains '6.3: policy: user override priority stated' `
    $intentPolicyPath '(?i)User Override Priority|user.*override.*priority'

Write-Host ''

# =========================================================================
# Scenario 7: Both detected + previously confirmed Studio Pro/live -> no repeat ask
# =========================================================================

Write-Host '--- Scenario 7: Previously confirmed Studio Pro/live -> no repeat ask ---'

Assert-FileContains '7.1: policy defines session decision state persistence' `
    $intentPolicyPath '(?i)Session Decision State|process-state\.yaml.*execution_intent'

Assert-FileContains '7.2: policy Re-Sync Case A: resolved + environment unchanged -> no ask' `
    $intentPolicyPath '(?i)Case A.*resolved|intent.*already.*resolved.*environment.*unchanged'

Assert-FileContains '7.3: orchestrator Schritt 1b: resolved + signals unchanged -> Schritt 2 direkt' `
    $orchestratorPath '(?i)aufgeloest.*Umgebungssignale.*unveraendert|resolved.*unchanged.*direct'

Write-Host ''

# =========================================================================
# Scenario 8: Both detected + previously confirmed normal/headless -> no repeat ask
# =========================================================================

Write-Host '--- Scenario 8: Previously confirmed normal/headless -> no repeat ask ---'

Assert-FileContains '8.1: policy Re-Sync Case C: normal/headless prior choice -> no repeat ask' `
    $intentPolicyPath '(?i)Case C|normal.*headless.*previously.*chosen|prior choice.*still valid'

Assert-FileContains '8.2: policy: do NOT ask repeatedly because strong signal remains' `
    $intentPolicyPath '(?i)do NOT repeatedly ask|not.*ask.*merely.*strong signal remains'

Write-Host ''

# =========================================================================
# Scenario 9: Previous live intent + capability disappears -> surface change
# =========================================================================

Write-Host '--- Scenario 9: Live intent + capability gone -> surface changed environment ---'

Assert-FileContains '9.1: policy Re-Sync Case B: live intent + capability gone -> surface change' `
    $intentPolicyPath '(?i)Case B|capability.*disappeared|studio pro.*disappeared|concord mcp.*gone'

Assert-FileContains '9.2: policy: do NOT silently continue as if live execution available' `
    $intentPolicyPath '(?i)do NOT silently.*live|not.*silently.*pretend.*live'

Assert-FileContains '9.3: policy: report discrepancy when mode unavailable' `
    $intentPolicyPath '(?i)report.*discrepancy|surface.*changed environment|report.*change'

Assert-FileContains '9.4: orchestrator Schritt 1b: Re-Sync surface changed environment stated' `
    $orchestratorPath '(?i)Studio Pro.*oder Concord.*nicht mehr|capability.*not.*detected.*report'

Write-Host ''

# =========================================================================
# Scenario 10: Clarification does not satisfy lifecycle gates
# =========================================================================

Write-Host '--- Scenario 10: Clarification does not satisfy lifecycle gates ---'

Assert-FileContains '10.1: policy: question must not satisfy lifecycle gate' `
    $intentPolicyPath '(?i)satisfy.*lifecycle gate|MUST NOT.*lifecycle.*gate'

Assert-FileContains '10.2: policy: question must not change mission phase' `
    $intentPolicyPath '(?i)mission phase.*or.*completion|does not change.*mission'

Assert-FileContains '10.3: orchestrator Schritt 1b: no lifecycle gate stated' `
    $orchestratorPath '(?i)kein Lifecycle-Gate|no.*lifecycle.*gate|erfuellt KEIN.*Gate'

Write-Host ''

# =========================================================================
# Scenario 11: Clarification does not change mission completion
# =========================================================================

Write-Host '--- Scenario 11: Clarification does not change mission completion ---'

Assert-FileContains '11.1: policy: clarification must not change mission completion' `
    $intentPolicyPath '(?i)mission.*completion|does not change.*mission'

Assert-FileContains '11.2: policy: continue original mission after clarification' `
    $intentPolicyPath '(?i)continue.*original mission|urspruenglichen Auftrag.*fortsetzen'

Write-Host ''

# =========================================================================
# Scenario 12: Clarification does not alter evidence states
# =========================================================================

Write-Host '--- Scenario 12: Clarification does not alter evidence states ---'

Assert-FileContains '12.1: policy: must not promote UNVERIFIED/FAILED/STALE evidence' `
    $intentPolicyPath '(?i)UNVERIFIED.*FAILED.*STALE|evidence states|promote.*evidence'

Assert-FileContains '12.2: policy: no Context Epoch rollover from clarification' `
    $intentPolicyPath '(?i)Context Epoch rollover|kein.*Context-Epoch-Rollover'

Assert-FileContains '12.3: orchestrator: no Epoch-Rollover from Schritt 1b' `
    $orchestratorPath '(?i)Context-Epoch-Rollover|Epoch.*Rollover.*nicht'

Write-Host ''

# =========================================================================
# Scenario 13: Re-Sync preserves still-valid user execution choice
# =========================================================================

Write-Host '--- Scenario 13: Re-Sync preserves still-valid user choice ---'

Assert-FileContains '13.1: policy defines Re-Sync behavior section' `
    $intentPolicyPath '(?i)Re-Sync Behavior'

Assert-FileContains '13.2: policy Case A: prior resolved choice preserved when environment unchanged' `
    $intentPolicyPath '(?i)Use the resolved intent as-is|resolved.*as-is|prior.*choice.*preserved'

Assert-FileContains '13.3: policy: session state specifies environment_basis for comparison' `
    $intentPolicyPath 'environment_basis'

Write-Host ''

# =========================================================================
# Scenario 14: Explicit user instruction wins over environment inference
# =========================================================================

Write-Host '--- Scenario 14: Explicit user instruction wins over environment ---'

Assert-FileContains '14.1: policy: explicit instruction priority over signal' `
    $intentPolicyPath '(?i)higher priority.*environment signal|wins.*environment|override.*priority'

Assert-FileContains '14.2: policy: headless user request -> normal_headless without question' `
    $intentPolicyPath '(?i)user says.*headless|headless.*normal_headless|headless.*without question'

Assert-FileContains '14.3: policy: live user request -> studio_pro_live without question' `
    $intentPolicyPath '(?i)user says.*Studio Pro.*without question|studio_pro_live.*without question'

Write-Host ''

# =========================================================================
# Scenario 15: Existing SP-on / LIVE-SP-CURRENT behavior backward compatible
# =========================================================================

Write-Host '--- Scenario 15: Existing SP-on backward compatibility ---'

Assert-FileContains '15.1: policy: LIVE-SP-CURRENT coexistence contract remains intact' `
    $intentPolicyPath '(?i)LIVE-SP-CURRENT.*coexistence|coexistence.*intact|consistency-check'

Assert-FileContains '15.2: policy: operating-mode detection not replaced by this policy' `
    $intentPolicyPath '(?i)does not replace.*operating-mode|operating-mode.*detection.*intact|not replace'

Assert-FileContains '15.3: orchestrator Schritt 1 unchanged; Schritt 1b is additive' `
    $orchestratorPath 'Schritt 1 .*Betriebsmodus'

Assert-FileContains '15.4: policy: intent resolution is on top of SP-on, not instead of it' `
    $intentPolicyPath '(?i)on top|intent-resolution layer'

Write-Host ''

# =========================================================================
# Detection mechanism: Concord MCP via tool namespace
# =========================================================================

Write-Host '--- Detection Mechanism ---'

Assert-FileContains 'DET.1: policy: Concord MCP detected via mcp__concord-v2-mcp__ tools' `
    $intentPolicyPath 'mcp__concord-v2-mcp__'

Assert-FileContains 'DET.2: capabilities: concord_mcp registered' `
    $capabilitiesPath 'id: concord_mcp'

Assert-FileContains 'DET.3: capabilities: concord_mcp availability via tool namespace' `
    $capabilitiesPath 'mcp__concord-v2-mcp__'

Assert-FileContains 'DET.4: capabilities: studio_pro_mcp registered' `
    $capabilitiesPath 'id: studio_pro_mcp'

Assert-FileContains 'DET.5: policy: configuration evidence alone not sufficient for detected' `
    $intentPolicyPath '(?i)Configuration evidence alone.*MUST NOT.*detected|configuration.*not.*sufficient'

Assert-FileContains 'DET.6: policy: detection limitation for non-Claude Code environments' `
    $intentPolicyPath '(?i)Detection limitation|outside Claude Code'

Write-Host ''

# =========================================================================
# Summary
# =========================================================================

Write-Host '=== Execution-Intent Test Summary ==='
Write-Host "  PASS: $PassCount"
Write-Host "  FAIL: $FailCount"

if ($FailDetails.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failures:'
    foreach ($d in $FailDetails) {
        Write-Host "  $d" -ForegroundColor Red
    }
}

Write-Host ''

if ($FailCount -gt 0) {
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'RESULT: PASS' -ForegroundColor Green
    exit 0
}
