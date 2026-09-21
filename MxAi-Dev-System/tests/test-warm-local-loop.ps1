<#
.SYNOPSIS
    Warm Local Development Loop Tests

.DESCRIPTION
    Validates that MxAgile canonical guidance supports warm local development
    runtime during Implementing while preserving Verification integrity.

    What is tested:
    A. Canonical guidance knows mxcli run --local and --watch
    B. Implementation-Agent prefers/reuses warm runtime for iterative development
    C. Runtime is not mandatory for every MDL operation
    D. Runtime startup during Implementing does not transition lifecycle to Verifying
    E. Successful local startup does not satisfy formal Verification
    F. Docker verification remains intact
    G. Database guidance does not hardcode HSQLDB or PostgreSQL universally
    H. UI-driven implementation can use warm runtime without premature Verification
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

$policyPath     = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$implAgentPath  = Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md"
$orchestratorPath = Join-Path $ScriptDir ".mxagile/orchestrator.md"
$lifecyclePath  = Join-Path $ScriptDir ".mxagile/lifecycle.yaml"
$qualityGatePath = Join-Path $ScriptDir ".mxagile/skills/quality-gate.md"
$readmePath     = Join-Path $ScriptDir ".mxagile/README.md"

Write-Host ""
Write-Host "=== Warm Local Development Loop Tests ==="
Write-Host ""

# =========================================================================
# Section A: Canonical guidance knows mxcli run --local and --watch
# =========================================================================

Write-Host "--- Section A: mxcli run --local and --watch awareness ---"

Assert-True "development-runtime.md exists" `
    (Test-Path -LiteralPath $policyPath) `
    "Canonical policy not found: $policyPath"

Assert-FileContains "policy: knows mxcli run --local" `
    $policyPath 'mxcli run --local'

Assert-FileContains "policy: knows --watch flag" `
    $policyPath '--watch'

Assert-FileContains "policy: preferred command includes --watch" `
    $policyPath 'mxcli run --local.*--watch'

Assert-FileContains "implementation-agent: references development-runtime policy" `
    $implAgentPath 'development-runtime'

Assert-FileContains "implementation-agent: knows mxcli run --local" `
    $implAgentPath 'mxcli run --local'

Assert-FileContains "implementation-agent: knows --watch" `
    $implAgentPath '--watch'

Write-Host ""

# =========================================================================
# Section B: Implementation-Agent prefers/reuses warm runtime
# =========================================================================

Write-Host "--- Section B: Warm runtime preference and reuse ---"

Assert-FileContains "policy: runtime reuse semantics" `
    $policyPath '(?i)reuse'

Assert-FileContains "policy: detect existing runtime" `
    $policyPath '(?i)detect'

Assert-FileContains "policy: keep warm/available" `
    $policyPath '(?i)keep.*available'

Assert-FileContains "policy: avoid restart cycles" `
    $policyPath '(?i)avoid.*restart'

Assert-FileContains "implementation-agent: warm loop section exists" `
    $implAgentPath '(?i)warm.*local.*loop'

Write-Host ""

# =========================================================================
# Section C: Runtime not mandatory for every MDL operation
# =========================================================================

Write-Host "--- Section C: Runtime is conditional, not mandatory ---"

Assert-FileContains "policy: runtime NOT blindly started" `
    $policyPath '(?i)not.*blindly|nicht.*pauschal'

Assert-FileContains "policy: enum/domain-model work listed as not needing runtime" `
    $policyPath '(?i)enum|domain.model.construction'

Assert-FileContains "policy: pages/navigation listed as runtime-relevant" `
    $policyPath '(?i)pages.*navigation|navigation.*pages'

Assert-FileContains "implementation-agent: conditional runtime start" `
    $implAgentPath '(?i)nicht pauschal|when.*runtime'

Write-Host ""

# =========================================================================
# Section D: Runtime does not transition lifecycle to Verifying
# =========================================================================

Write-Host "--- Section D: No lifecycle transition from runtime ---"

Assert-FileContains "policy: runtime state independent of lifecycle" `
    $policyPath '(?i)must not.*lifecycle.*transition|must not.*cause.*lifecycle'

Assert-FileContains "policy: two state dimensions" `
    $policyPath '(?i)lifecycle.*state|runtime.*state'

Assert-FileContains "orchestrator: verification invariants section exists" `
    $orchestratorPath '(?i)verification.*invariant'

Assert-FileContains "orchestrator: runtime state does not trigger phase change" `
    $orchestratorPath '(?i)keinen phasenwechsel|no.*phase.*transition'

Assert-FileContains "lifecycle.yaml: implementing mentions development feedback" `
    $lifecyclePath '(?si)implementing:.*development\s+feedback'

Assert-FileContains "lifecycle.yaml: implementing mentions not formal verification" `
    $lifecyclePath '(?i)not formal verification|not.*formal.*verif'

Write-Host ""

# =========================================================================
# Section E: Successful local startup does not satisfy Verification
# =========================================================================

Write-Host "--- Section E: Local runtime != Verification ---"

Assert-FileContains "policy: app start != verification" `
    $policyPath '(?i)starts.*successfully.*verification|start.*not.*verification'

Assert-FileContains "policy: mxcli run --local succeeds != wave verified" `
    $policyPath '(?i)mxcli run --local.*wave verified'

Assert-FileContains "quality-gate: local runtime does not replace quality gate" `
    $qualityGatePath '(?i)development.*runtime|mxcli run --local'

Assert-FileContains "quality-gate: references development-runtime policy" `
    $qualityGatePath 'development-runtime'

Assert-FileContains "implementation-agent: runtime feedback is not verification" `
    $implAgentPath '(?i)kein.*verification.*ersatz|nicht.*verifikation|kein.*verifikationsnachweis'

Write-Host ""

# =========================================================================
# Section F: Docker verification remains intact
# =========================================================================

Write-Host "--- Section F: Docker verification preserved ---"

Assert-FileContains "quality-gate: docker build/start still required" `
    $qualityGatePath '(?i)docker.*build|docker.*start'

Assert-FileContains "quality-gate: must pass before UI/Acceptance" `
    $qualityGatePath '(?i)muss bestehen'

Assert-FileContains "orchestrator: verifying still requires quality gate" `
    $orchestratorPath '(?i)quality.*gate.*sequenziell|quality.*gate.*voraussetzung'

# Docker check commands still present in consistency-check policy
$consistencyPath = Join-Path $ScriptDir ".mxagile/policies/consistency-check.md"
Assert-FileContains "consistency-check: mxcli docker check preserved" `
    $consistencyPath 'mxcli docker check'

Write-Host ""

# =========================================================================
# Section G: No hardcoded database default
# =========================================================================

Write-Host "--- Section G: Database guidance not hardcoded ---"

Assert-FileContains "policy: database section exists" `
    $policyPath '(?i)## database'

Assert-FileNotContains "policy: no hardcoded hsqldb default" `
    $policyPath '(?i)default.*hsqldb|always.*use.*hsqldb|universell.*hsqldb'

Assert-FileNotContains "policy: no hardcoded postgresql default" `
    $policyPath '(?i)default.*postgresql|always.*use.*postgres|universell.*postgres'

Assert-FileContains "policy: preference order for database" `
    $policyPath '(?i)preference.*order|projekt.*konfiguration|project.*configuration'

Assert-FileContains "policy: supports fallback options" `
    $policyPath '(?i)fallback|--db-type'

Write-Host ""

# =========================================================================
# Section H: UI-driven warm loop without premature Verification
# =========================================================================

Write-Host "--- Section H: UI-driven warm loop ---"

Assert-FileContains "policy: pages listed as runtime-relevant" `
    $policyPath '(?i)pages'

Assert-FileContains "policy: visual iteration listed as runtime-relevant" `
    $policyPath '(?i)visual.*iteration'

Assert-FileContains "policy: UI inventory obligations mentionable" `
    $policyPath '(?i)mockup|ui.inventory|ui.*obligation'

Assert-FileContains "implementation-agent: UI-Iteration in runtime-relevant list" `
    $implAgentPath '(?i)ui.*iteration'

# UI-Agent formal verify still phase-gated to Verifying
$uiAgentPath = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
Assert-FileContains "ui-agent: verify mode still gated to verifying phase" `
    $uiAgentPath '(?i)verifying.*docker|trigger.*verifying'

Write-Host ""

# =========================================================================
# Section I: Cross-reference integrity
# =========================================================================

Write-Host "--- Section I: Cross-reference integrity ---"

Assert-FileContains "README.md: lists development-runtime.md" `
    $readmePath 'development-runtime'

Assert-FileContains "orchestrator: references development-runtime policy" `
    $orchestratorPath 'development-runtime'

Assert-FileContains "policy: three-concern table present" `
    $policyPath '(?si)Model Validation.*Development Runtime.*Formal Verification'

Assert-FileContains "policy: recovery section exists" `
    $policyPath '(?i)## recovery|recover'

Assert-FileContains "policy: lifecycle boundary section exists" `
    $policyPath '(?i)## lifecycle boundary'

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Warm Local Development Loop Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Warm local loop guidance is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Warm local development loop guidance is complete and consistent." -ForegroundColor Green
    exit 0
}
