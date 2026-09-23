<#
.SYNOPSIS
    UI-Driven Readiness and Evidence Level Tests

.DESCRIPTION
    Validates that MxAgile canonical guidance correctly implements:
    - Evidence level classification (STATIC/MODEL/RUNTIME/BROWSER)
    - UI-driven Discovery gate (cannot PASS without browser evidence)
    - Mock-data and role readiness requirements
    - TECHNICAL_WORK vs DECISION_REQUIRED distinction
    - Deferred-scope behavior

    Test cases:
    K. UI-driven Full Discovery cannot PASS without required runtime evidence
    L. Model-only Discovery remains explicitly distinguishable
    M. Populated mockup scenarios require representative data
    N. Runtime role verification is not replaced by static role inspection
    O. UI-driven iteration prefers warm local runtime
    P. Playwright does not imply Docker (preserved from runtime-strategy)
    Q. Page/microflow/nanoflow/styling changes do not imply Docker (preserved)
    R. Structural model changes do not automatically imply Docker (preserved)
    S. Explicit container-parity verification may use Docker (preserved)
    T. Normal microflow implementation is not classified as DECISION REQUIRED
    U. Source/business ambiguity is correctly classified as DECISION REQUIRED
    V. One unresolved decision blocks only dependent scope
    W. Generated projections contain consistent guidance
    X. Existing projects remain upgrade-compatible
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

# Canonical source paths
$evidenceLevelsPath  = Join-Path $ScriptDir ".mxagile/policies/evidence-levels.md"
$credDiscovPath      = Join-Path $ScriptDir ".mxagile/policies/credential-discovery.md"
$runtimeStratPath    = Join-Path $ScriptDir ".mxagile/policies/runtime-strategy.md"
$discoveryAgentPath  = Join-Path $ScriptDir ".mxagile/agents/discovery-agent.md"
$uiAgentPath         = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$implAgentPath       = Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md"
$refinementAgentPath = Join-Path $ScriptDir ".mxagile/agents/refinement-agent.md"
$orchestratorPath    = Join-Path $ScriptDir ".mxagile/orchestrator.md"
$lifecyclePath       = Join-Path $ScriptDir ".mxagile/lifecycle.yaml"
$processStatePath    = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"
$projectSchemaPath   = Join-Path $ScriptDir ".mxagile/schemas/mxagile-project.schema.json"

# Generated projections (Claude)
$genImplAgentPath    = Join-Path $ScriptDir ".claude/agents/mxagile-implementation-agent.md"
$genUiAgentPath      = Join-Path $ScriptDir ".claude/agents/mxagile-ui-agent.md"
$genDiscoveryPath    = Join-Path $ScriptDir ".claude/agents/mxagile-discovery-agent.md"

Write-Host ""
Write-Host "=== UI-Driven Readiness and Evidence Level Tests ==="
Write-Host ""

# =========================================================================
# Canonical policy exists
# =========================================================================

Write-Host "--- Canonical policy: evidence-levels.md ---"

Assert-True "evidence-levels.md exists" `
    (Test-Path -LiteralPath $evidenceLevelsPath) `
    "Policy not found: $evidenceLevelsPath"

Assert-FileContains "policy: STATIC level defined" `
    $evidenceLevelsPath 'STATIC'

Assert-FileContains "policy: MODEL level defined" `
    $evidenceLevelsPath 'MODEL'

Assert-FileContains "policy: RUNTIME level defined" `
    $evidenceLevelsPath 'RUNTIME'

Assert-FileContains "policy: BROWSER level defined" `
    $evidenceLevelsPath 'BROWSER'

Write-Host ""

# =========================================================================
# K. UI-driven Full Discovery cannot PASS without runtime evidence
# =========================================================================

Write-Host "--- K: UI-driven Full Discovery requires browser evidence ---"

Assert-FileContains "evidence-levels: ui_driven Discovery requires browser evidence" `
    $evidenceLevelsPath '(?i)ui.driven.*true.*Full Discovery|Full Discovery.*browser|BROWSER.*runtime-testable'

Assert-FileContains "evidence-levels: no browser = NOT Full UI Discovery PASS" `
    $evidenceLevelsPath '(?i)not.*FULL UI DISCOVERY PASS|MODEL-ONLY DISCOVERY or PARTIAL|silently promoted'

Assert-FileContains "orchestrator: FULL_UI_DISCOVERY_PASS requires browser evidence" `
    $orchestratorPath '(?i)FULL_UI_DISCOVERY_PASS.*browser|browser.*FULL_UI_DISCOVERY_PASS'

Assert-FileContains "orchestrator: cannot declare Full UI Discovery PASS without browser evidence" `
    $orchestratorPath '(?i)darf NICHT deklariert werden ohne Browser|must not.*pass.*without browser'

Assert-FileContains "discovery-agent: full discovery pass only with browser evidence" `
    $discoveryAgentPath '(?i)FULL UI DISCOVERY PASS.*nicht.*ohne.*BROWSER|FULL.*DISCOVERY.*PASS.*nicht.*deklariert'

Assert-FileContains "lifecycle.yaml: browser evidence required for ui_driven" `
    $lifecyclePath '(?i)browser.*evidence|FULL_UI_DISCOVERY'

Write-Host ""

# =========================================================================
# L. Model-only Discovery remains explicitly distinguishable
# =========================================================================

Write-Host "--- L: Model-only Discovery explicitly distinguishable ---"

Assert-FileContains "evidence-levels: MODEL_ONLY_DISCOVERY concept defined" `
    $evidenceLevelsPath '(?i)model.only|MODEL_ONLY|model.*only.*discovery'

Assert-FileContains "orchestrator: MODEL_ONLY_DISCOVERY state defined" `
    $orchestratorPath '(?i)MODEL_ONLY_DISCOVERY|MODEL-ONLY DISCOVERY'

Assert-FileContains "discovery-agent: model-only state defined" `
    $discoveryAgentPath '(?i)MODEL-ONLY DISCOVERY|MODEL_ONLY'

Assert-FileContains "lifecycle.yaml: MODEL_ONLY_DISCOVERY or PARTIAL_DISCOVERY listed" `
    $lifecyclePath '(?i)MODEL_ONLY|PARTIAL_DISCOVERY|partial.*discovery'

Write-Host ""

# =========================================================================
# M. Populated mockup scenarios require representative data
# =========================================================================

Write-Host "--- M: Populated scenarios require representative data ---"

Assert-FileContains "evidence-levels: populated state requires representative data" `
    $evidenceLevelsPath '(?i)representative.*data|populated.*mockup.*empty.*state'

Assert-FileContains "credential-discovery: mock data readiness concept" `
    $credDiscovPath '(?i)mock.data|mock_data|MOCK_DATA_UNAVAILABLE'

Assert-FileContains "ui-agent: representative data required for browser evidence" `
    $uiAgentPath '(?i)repraesentativ.*Daten|representative.*data|repraesentativer.*Daten-Zustand'

Assert-FileContains "discovery-agent: mock data readiness check" `
    $discoveryAgentPath '(?i)mock.*data|seed.*daten|repraesentativ'

Assert-FileContains "process-state schema: mock_data readiness field" `
    $processStatePath '(?i)mock_data'

Write-Host ""

# =========================================================================
# N. Runtime role verification not replaced by static role inspection
# =========================================================================

Write-Host "--- N: Runtime role verification not replaced by static inspection ---"

Assert-FileContains "evidence-levels: static role config != runtime role verification" `
    $evidenceLevelsPath '(?i)role.*verification|static.*role|role.*browser'

Assert-FileContains "ui-agent: browser evidence requires correct role session" `
    $uiAgentPath '(?i)korrekte.*Benutzerrolle|applicable.*role|role.*session|correct.*role'

Assert-FileContains "discovery-agent: test identity readiness check" `
    $discoveryAgentPath '(?i)test.identity|test.identit|Test-Identit'

Write-Host ""

# =========================================================================
# O. UI-driven iteration prefers warm local runtime
# =========================================================================

Write-Host "--- O: UI-driven iteration prefers warm local runtime ---"

Assert-FileContains "runtime-strategy: UI-driven selects local runtime" `
    $runtimeStratPath '(?i)UI-Driven Integration|ui_driven.*local|local.*ui_driven'

Assert-FileContains "evidence-levels: RUNTIME level uses mxcli run --local" `
    $evidenceLevelsPath '(?i)mxcli run --local|warm.*local.*runtime'

Assert-FileContains "discovery-agent: local runtime for UI readiness" `
    $discoveryAgentPath '(?i)mxcli run --local|warmer lokaler Runtime|lokal.*runtime'

Write-Host ""

# =========================================================================
# P-S. Runtime strategy preserved (from runtime-strategy tests)
# =========================================================================

Write-Host "--- P-S: Runtime strategy preserved (Playwright!=Docker, Docker by need) ---"

Assert-FileContains "P: Playwright does not require Docker" `
    $runtimeStratPath '(?i)playwright.*not.*require.*docker|playwright.*does not.*docker'

Assert-FileContains "Q: page/microflow changes do NOT imply Docker" `
    $runtimeStratPath '(?i)page.*changed|microflow.*changed'

Assert-FileContains "R: structural model changes do not automatically imply Docker" `
    $runtimeStratPath '(?i)entity.*changed|structural.*model.*change'

Assert-FileContains "S: container-parity may use Docker" `
    $runtimeStratPath '(?i)container.parity.*docker|docker.*container.parity'

Write-Host ""

# =========================================================================
# T. Normal microflow implementation is NOT DECISION REQUIRED
# =========================================================================

Write-Host "--- T: New microflow is TECHNICAL_WORK, not DECISION REQUIRED ---"

Assert-FileContains "implementation-agent: TECHNICAL_WORK vs DECISION_REQUIRED section" `
    $implAgentPath '(?i)Technische Arbeit.*DECISION REQUIRED|TECHNICAL.*WORK.*DECISION'

Assert-FileContains "implementation-agent: new microflow listed as TECHNICAL WORK" `
    $implAgentPath '(?i)Neuer Microflow.*TECHNISCHE ARBEIT|new.*microflow.*TECHNICAL WORK'

Assert-FileNotContains "implementation-agent: microflow NOT listed as DECISION REQUIRED" `
    $implAgentPath '(?i)Neuer Microflow.*DECISION REQUIRED'

Assert-FileContains "implementation-agent: guiding question defined" `
    $implAgentPath '(?i)Weiss ich WAS.*gebaut|Do I know WHAT'

Assert-FileContains "refinement-agent: DECISION REQUIRED vs technical work distinction" `
    $refinementAgentPath '(?i)Technische Arbeit.*nicht DECISION REQUIRED|technical work.*not.*DECISION REQUIRED'

Write-Host ""

# =========================================================================
# U. Source/business ambiguity IS DECISION REQUIRED
# =========================================================================

Write-Host "--- U: Business ambiguity is correctly DECISION REQUIRED ---"

Assert-FileContains "implementation-agent: missing business semantics = DECISION REQUIRED" `
    $implAgentPath '(?i)Fehlende Geschaeftssemantik.*DECISION REQUIRED|missing.*business.*DECISION REQUIRED'

Assert-FileContains "implementation-agent: source conflict = DECISION REQUIRED" `
    $implAgentPath '(?i)Widerspruch.*DECISION REQUIRED|source.*conflict.*DECISION REQUIRED'

Assert-FileContains "discovery-agent: missing business semantics marked DECISION REQUIRED" `
    $discoveryAgentPath '(?i)DECISION REQUIRED'

Write-Host ""

# =========================================================================
# V. One unresolved decision blocks only dependent scope
# =========================================================================

Write-Host "--- V: One unresolved decision blocks only dependent scope ---"

Assert-FileContains "refinement-agent: defer only dependent scope" `
    $refinementAgentPath '(?i)Defer Only Dependent Scope|nur.*davon.*abhaengigen.*Scope.*blockieren'

Assert-FileContains "orchestrator: defer only dependent scope on DECISION REQUIRED" `
    $orchestratorPath '(?i)ruecklauf|failed.*items|nur.*failed.*items'

Write-Host ""

# =========================================================================
# W. Generated projections contain consistent guidance
# =========================================================================

Write-Host "--- W: Generated projections contain consistent guidance ---"

Assert-True "generated implementation-agent exists" `
    (Test-Path -LiteralPath $genImplAgentPath) `
    "Generated agent not found: $genImplAgentPath"

Assert-FileContains "generated implementation-agent: TECHNICAL_WORK distinction" `
    $genImplAgentPath '(?i)Technische Arbeit|TECHNICAL.*WORK'

Assert-True "generated ui-agent exists" `
    (Test-Path -LiteralPath $genUiAgentPath) `
    "Generated agent not found: $genUiAgentPath"

Assert-FileContains "generated ui-agent: evidence level concept" `
    $genUiAgentPath '(?i)evidence|evidenz|STATIC|BROWSER'

Assert-True "generated discovery-agent exists" `
    (Test-Path -LiteralPath $genDiscoveryPath) `
    "Generated agent not found: $genDiscoveryPath"

Assert-FileContains "generated discovery-agent: credential discovery" `
    $genDiscoveryPath '(?i)credential.discovery|\.env\.mendix'

Write-Host ""

# =========================================================================
# X. Existing projects remain upgrade-compatible
# =========================================================================

Write-Host "--- X: Existing projects remain upgrade-compatible ---"

Assert-FileContains "project-schema: prerequisites section optional (has defaults)" `
    $projectSchemaPath '(?i)prerequisite.*optional|default.*\.env\.mendix|credential_source.*default'

Assert-FileContains "project-schema: require_browser_evidence has default true" `
    $projectSchemaPath '(?i)require_browser_evidence.*default|default.*true.*browser'

Assert-FileContains "evidence-levels: standard discovery (ui_driven=false) does not require browser" `
    $evidenceLevelsPath '(?i)standard.*ui_driven.*false|non.ui.driven|standard.*discovery'

Assert-FileContains "lifecycle.yaml: gate_variants are alternatives, not all required" `
    $lifecyclePath '(?i)FULL_UI_DISCOVERY|PARTIAL_DISCOVERY|MODEL_ONLY'

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== UI-Driven Readiness Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: UI-driven readiness and evidence level guidance is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: UI-driven readiness, evidence levels and DECISION REQUIRED classification are complete and consistent." -ForegroundColor Green
    exit 0
}
