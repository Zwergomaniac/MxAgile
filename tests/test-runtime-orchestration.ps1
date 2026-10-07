<#
.SYNOPSIS
    Runtime Orchestration Tests

.DESCRIPTION
    Validates the MxAgile autonomous runtime orchestration contracts introduced
    to fix the Rev5 reality test defects:

    A. Interactive warm development uses --watch
    B. Autonomous verification omits --watch
    C. db_name remains "default" under Core contract
    D. Tests cannot begin before APPLICATION_REACHABLE
    E. Authenticated tests cannot begin before AUTHENTICATED_SESSION_READY
    F. chrome-error:// from startup does not fail an application PP
    G. Stale OWNED runtime can be safely detected and handled
    H. FOREIGN/UNKNOWN mxcli process is never blindly killed
    I. Compatible owned runtime can be reused
    J. Incompatible runtime is not silently reused
    K. No arbitrary pkill/killall behavior introduced
    L. Generated agents/skills receive the corrected contract
    M. Local First / Docker by Need remains intact
    N. Lifecycle state not incorrectly advanced because a runtime started
    O. Existing DB-default regression coverage remains green
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

$policyPath      = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$profilePath     = Join-Path $ScriptDir ".mxagile/policies/local-runtime-profile.md"
$runtimeStrategy = Join-Path $ScriptDir ".mxagile/policies/runtime-strategy.md"
$testWorkflow    = Join-Path $ScriptDir ".mxagile/policies/test-workflow.md"
$lifecycleResync = Join-Path $ScriptDir ".mxagile/policies/lifecycle-resync.md"
$evidenceLevels  = Join-Path $ScriptDir ".mxagile/policies/evidence-levels.md"
$verifyLayers    = Join-Path $ScriptDir ".mxagile/policies/verification-layers.md"
$implAgentPath   = Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md"
$accAgentPath    = Join-Path $ScriptDir ".mxagile/agents/acceptance-agent.md"
$uiAgentPath     = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$discAgentPath   = Join-Path $ScriptDir ".mxagile/agents/discovery-agent.md"
$orchestrator    = Join-Path $ScriptDir ".mxagile/orchestrator.md"
$lifecycleYaml   = Join-Path $ScriptDir ".mxagile/lifecycle.yaml"
$qualityGate     = Join-Path $ScriptDir ".mxagile/skills/quality-gate.md"
$schemaPath      = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"

Write-Host ""
Write-Host "=== Runtime Orchestration Tests ==="
Write-Host ""

# =========================================================================
# Section A: Interactive warm development uses --watch
# =========================================================================

Write-Host "--- Section A: Interactive mode uses --watch ---"

Assert-FileContains "A.1 policy defines Interactive Implementation Mode" `
    $policyPath '(?i)Interactive Implementation Mode'

Assert-FileContains "A.2 interactive mode has --watch = PREFERRED" `
    $policyPath '(?si)Interactive Implementation Mode.*PREFERRED'

Assert-FileContains "A.3 interactive base command includes --watch" `
    $policyPath '(?si)Interactive.*base command.*mxcli run --local.*--watch'

Assert-FileContains "A.4 implementation-agent still uses --watch for warm loop" `
    $implAgentPath 'mxcli run --local.*--watch'

Write-Host ""

# =========================================================================
# Section B: Autonomous verification omits --watch
# =========================================================================

Write-Host "--- Section B: Autonomous verification omits --watch ---"

Assert-FileContains "B.1 policy defines Autonomous Verification Mode" `
    $policyPath '(?i)Autonomous Verification Mode'

Assert-FileContains "B.2 autonomous mode has --watch = NOT_USED" `
    $policyPath '(?si)Autonomous Verification Mode.*NOT_USED'

Assert-FileContains "B.3 autonomous base command is mxcli run --local without --watch" `
    $policyPath '(?si)Autonomous.*base command.*mxcli run --local -p'

Assert-FileContains "B.4 acceptance-agent uses autonomous mode" `
    $accAgentPath '(?i)autonomous mode|ohne.*--watch'

Assert-FileContains "B.5 ui-agent verify uses autonomous mode" `
    $uiAgentPath '(?i)autonomen Modus|autonomous mode'

Assert-FileContains "B.6 discovery-agent uses autonomous mode for browser evidence" `
    $discAgentPath '(?i)autonomen Modus|autonomous mode'

Assert-FileContains "B.7 quality-gate uses autonomous mode for verification" `
    $qualityGate '(?i)autonomen Verifikationsmodus|autonomous.*verification'

Assert-FileContains "B.8 test-workflow uses autonomous mode" `
    $testWorkflow '(?i)autonomen Modus|autonomous'

Assert-FileContains "B.9 orchestrator verifying section uses autonomous mode" `
    $orchestrator '(?i)autonomen.*Modus|autonomous.*mode'

Assert-FileContains "B.10 lifecycle.yaml verifying mentions autonomous mode" `
    $lifecycleYaml '(?i)autonomous mode'

Assert-FileContains "B.11 mode selection table present" `
    $policyPath '(?i)Mode Selection'

Assert-FileContains "B.12 Watch-Mode Decision table present" `
    $policyPath '(?i)Watch-Mode Decision'

Write-Host ""

# =========================================================================
# Section C: db_name remains "default" under Core contract
# =========================================================================

Write-Host "--- Section C: DB default preserved ---"

Assert-FileContains "C.1 Core autonomous default is 'default'" `
    $policyPath '(?i)MXAGILE_CORE_DEFAULT|Core autonomous default.*default'

Assert-FileContains "C.2 effective command includes --db-name default" `
    $policyPath '(?i)--db-name default'

Assert-FileContains "C.3 autonomous effective command includes --db-name" `
    $policyPath '(?si)Autonomous Verification.*--db-name'

Write-Host ""

# =========================================================================
# Section D: Tests cannot begin before APPLICATION_REACHABLE
# =========================================================================

Write-Host "--- Section D: Readiness gate enforced ---"

Assert-FileContains "D.1 Readiness Gate Contract section exists" `
    $policyPath '(?i)## Readiness Gate Contract'

Assert-FileContains "D.2 APPLICATION_REACHABLE required before Playwright" `
    $policyPath '(?i)APPLICATION_REACHABLE.*Playwright|Playwright.*APPLICATION_REACHABLE'

Assert-FileContains "D.3 BROWSER_RENDERED required before DOM interaction" `
    $policyPath '(?i)BROWSER_RENDERED.*DOM interaction|DOM interaction.*BROWSER_RENDERED'

Assert-FileContains "D.4 prohibited inferences list exists" `
    $policyPath '(?i)Prohibited Inferences'

Assert-FileContains "D.5 mxcli process existence is not readiness" `
    $policyPath '(?i)mxcli process existence'

Assert-FileContains "D.6 BUILD_SUCCEEDED is not readiness" `
    $policyPath '(?i)BUILD_SUCCEEDED.*not.*readiness|Prohibited.*BUILD_SUCCEEDED'

Assert-FileContains "D.7 fixed sleep not readiness" `
    $policyPath '(?i)sleep.*delay|Fixed sleep'

Assert-FileContains "D.8 readiness validation sequence defined" `
    $policyPath '(?i)Readiness Validation Sequence'

Assert-FileContains "D.9 acceptance-agent references readiness gate" `
    $accAgentPath '(?i)Readiness Gate|APPLICATION_REACHABLE'

Write-Host ""

# =========================================================================
# Section E: Authenticated tests wait for AUTHENTICATED_SESSION_READY
# =========================================================================

Write-Host "--- Section E: Authenticated session gate ---"

Assert-FileContains "E.1 AUTHENTICATED_SESSION_READY in readiness gate levels" `
    $policyPath '(?si)Gate Levels.*AUTHENTICATED_SESSION_READY'

Assert-FileContains "E.2 role scenario requires authenticated session" `
    $policyPath '(?i)AUTHENTICATED_SESSION_READY.*Role scenario|authenticated tests'

Write-Host ""

# =========================================================================
# Section F: Runtime failure does not fail application proof points
# =========================================================================

Write-Host "--- Section F: Test failure classification ---"

Assert-FileContains "F.1 Test Failure Classification section exists" `
    $policyPath '(?i)## Test Failure Classification'

Assert-FileContains "F.2 RUNTIME_STARTUP_FAILURE defined" `
    $policyPath 'RUNTIME_STARTUP_FAILURE'

Assert-FileContains "F.3 RUNTIME_READINESS_FAILURE defined" `
    $policyPath 'RUNTIME_READINESS_FAILURE'

Assert-FileContains "F.4 TEST_INFRASTRUCTURE_GAP defined" `
    $policyPath 'TEST_INFRASTRUCTURE_GAP'

Assert-FileContains "F.5 chrome-error pattern must not fail app PP" `
    $policyPath '(?i)chrome-error'

Assert-FileContains "F.6 proof points remain UNEXECUTED on startup failure" `
    $policyPath '(?i)UNEXECUTED'

Assert-FileContains "F.7 mandatory classification before attribution" `
    $policyPath '(?i)Mandatory Classification Before Attribution'

Assert-FileContains "F.8 demo-user failures from unavailable app not classified as defects" `
    $policyPath '(?i)demo-user.*application.*MUST NOT|Demo-user switch.*unavailable'

Write-Host ""

# =========================================================================
# Section G: Stale OWNED runtime detection and handling
# =========================================================================

Write-Host "--- Section G: Runtime ownership model ---"

Assert-FileContains "G.1 Runtime Ownership Model section exists" `
    $policyPath '(?i)## Runtime Ownership Model'

Assert-FileContains "G.2 OWNED_RUNTIME classification defined" `
    $policyPath 'OWNED_RUNTIME'

Assert-FileContains "G.3 STALE_OWNED_RUNTIME classification defined" `
    $policyPath 'STALE_OWNED_RUNTIME'

Assert-FileContains "G.4 ownership evidence requires minimum TWO signals" `
    $policyPath '(?i)TWO'

Assert-FileContains "G.5 stale process detection before startup" `
    $policyPath '(?i)Stale Process Detection Before Startup'

Write-Host ""

# =========================================================================
# Section H: FOREIGN/UNKNOWN never killed
# =========================================================================

Write-Host "--- Section H: Foreign/unknown process safety ---"

Assert-FileContains "H.1 FOREIGN_RUNTIME classification defined" `
    $policyPath 'FOREIGN_RUNTIME'

Assert-FileContains "H.2 UNKNOWN_RUNTIME classification defined" `
    $policyPath 'UNKNOWN_RUNTIME'

Assert-FileContains "H.3 FOREIGN not terminated" `
    $policyPath '(?i)FOREIGN_RUNTIME.*NOT terminate|Do NOT terminate.*FOREIGN'

Assert-FileContains "H.4 UNKNOWN not terminated" `
    $policyPath '(?i)UNKNOWN_RUNTIME.*NOT terminate|Do NOT terminate.*UNKNOWN'

Write-Host ""

# =========================================================================
# Section I: Compatible owned runtime reuse
# =========================================================================

Write-Host "--- Section I: Runtime reuse ---"

Assert-FileContains "I.1 REUSABLE_RUNTIME classification defined" `
    $policyPath 'REUSABLE_RUNTIME'

Assert-FileContains "I.2 reuse when safe instruction present" `
    $policyPath '(?i)reuse.*safe|compatible.*reuse'

Write-Host ""

# =========================================================================
# Section J: Incompatible runtime not silently reused
# =========================================================================

Write-Host "--- Section J: Incompatible runtime rejection ---"

Assert-FileContains "J.1 compatibility must include project/config/db" `
    $policyPath '(?i)project path.*db_name|project.*config.*db'

Write-Host ""

# =========================================================================
# Section K: No arbitrary pkill/killall
# =========================================================================

Write-Host "--- Section K: No blind process killing ---"

Assert-FileContains "K.1 pkill prohibited" `
    $policyPath '(?i)pkill mxcli'

Assert-FileContains "K.2 killall prohibited" `
    $policyPath '(?i)killall mxcli'

Assert-FileContains "K.3 termination rules section exists" `
    $policyPath '(?i)Termination Rules'

Assert-FileContains "K.4 process not killed merely because executable is mxcli" `
    $policyPath '(?i)executable is mxcli'

Assert-FileContains "K.5 process not killed merely because old" `
    $policyPath '(?i)It is old'

Assert-FileContains "K.6 process not killed merely because port occupied" `
    $policyPath '(?i)port is occupied'

Write-Host ""

# =========================================================================
# Section L: Generated projections carry corrected contract
# =========================================================================

Write-Host "--- Section L: Generated projections updated ---"

$genAccAgent  = Join-Path $ScriptDir ".claude/agents/mxagile-acceptance-agent.md"
$genUiAgent   = Join-Path $ScriptDir ".claude/agents/mxagile-ui-agent.md"
$genDiscAgent = Join-Path $ScriptDir ".claude/agents/mxagile-discovery-agent.md"
$genQualGate  = Join-Path $ScriptDir ".claude/skills/mxagile-quality-gate/SKILL.md"

Assert-FileContains "L.1 generated acceptance-agent has autonomous mode" `
    $genAccAgent '(?i)autonomous mode|ohne.*--watch'

Assert-FileContains "L.2 generated ui-agent has autonomous mode" `
    $genUiAgent '(?i)autonomen Modus|autonomous'

Assert-FileContains "L.3 generated discovery-agent has autonomous mode" `
    $genDiscAgent '(?i)autonomen Modus|autonomous'

Assert-FileContains "L.4 generated quality-gate references Runtime Modes" `
    $genQualGate '(?i)Runtime Modes|autonomen Verifikationsmodus'

Write-Host ""

# =========================================================================
# Section M: Local First / Docker by Need intact
# =========================================================================

Write-Host "--- Section M: Local First preserved ---"

Assert-FileContains "M.1 runtime-strategy still LOCAL FIRST" `
    $runtimeStrategy '(?i)LOCAL FIRST'

Assert-FileContains "M.2 development-runtime still references local warm loop" `
    $policyPath '(?i)mxcli run --local.*--watch'

Assert-FileContains "M.3 Docker only on escalation" `
    $runtimeStrategy '(?i)docker.*container.parity|container.*parity'

Write-Host ""

# =========================================================================
# Section N: Lifecycle not advanced by runtime startup
# =========================================================================

Write-Host "--- Section N: Lifecycle boundary preserved ---"

Assert-FileContains "N.1 runtime state does not cause lifecycle transition" `
    $policyPath '(?i)MUST NOT.*lifecycle.*transition|MUST NOT.*cause.*lifecycle'

Assert-FileContains "N.2 lifecycle-resync: runtime transient" `
    $lifecycleResync '(?i)transient'

Assert-FileContains "N.3 lifecycle-resync: ownership classification on resume" `
    $lifecycleResync '(?i)Ownership.*Klassifikation|ownership.*classification'

Write-Host ""

# =========================================================================
# Section O: DB-default coverage green
# =========================================================================

Write-Host "--- Section O: DB-default regression ---"

Assert-FileContains "O.1 autonomous effective command still has --db-name default" `
    $policyPath '(?i)--db-name default'

Assert-FileContains "O.2 DB_IDENTITY_CONTROL_UNAVAILABLE still defined" `
    $policyPath 'DB_IDENTITY_CONTROL_UNAVAILABLE'

Assert-FileContains "O.3 .mpr-derived db_name still prohibited" `
    $policyPath '(?i)NOT.*derive.*database name.*mpr|NOT.*mpr.*derived'

Write-Host ""

# =========================================================================
# Section P: Schema fields for runtime mode and ownership
# =========================================================================

Write-Host "--- Section P: Process-state schema updated ---"

$schemaContent = Get-Content -LiteralPath $schemaPath -Raw -ErrorAction SilentlyContinue
if ($null -eq $schemaContent) {
    Assert-True "P.0 schema file exists" $false "File not found: $schemaPath"
} else {
    Assert-True "P.1 runtime_mode field defined" `
        ($schemaContent -match '"runtime_mode"') "runtime_mode not found in schema"
    Assert-True "P.2 runtime_mode includes interactive enum" `
        ($schemaContent -match '"interactive"') "interactive enum not found"
    Assert-True "P.3 runtime_mode includes autonomous enum" `
        ($schemaContent -match '"autonomous"') "autonomous enum not found"
    Assert-True "P.4 runtime_ownership field defined" `
        ($schemaContent -match '"runtime_ownership"') "runtime_ownership not found in schema"
    Assert-True "P.5 runtime_ownership includes stale_owned enum" `
        ($schemaContent -match '"stale_owned"') "stale_owned enum not found"
    Assert-True "P.6 runtime_owner_pid field defined" `
        ($schemaContent -match '"runtime_owner_pid"') "runtime_owner_pid not found in schema"
}

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=" * 60
$total = $PassCount + $FailCount
Write-Host "RESULTS: $PassCount passed, $FailCount failed out of $total tests"
if ($FailCount -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    $FailDetails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
