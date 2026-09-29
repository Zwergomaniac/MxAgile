<#
.SYNOPSIS
    Runtime Strategy Tests: Local First, Docker By Verification Need

.DESCRIPTION
    Validates that MxAgile canonical guidance consistently implements the
    "Local First, Docker By Verification Need" runtime strategy across all
    canonical sources and generated projections.

    Test cases:
    A. Normal implementation selects local-first guidance
    B. UI-driven iteration selects local warm runtime
    C. Playwright does NOT imply Docker
    D. Styling changes do NOT imply Docker
    E. Page/microflow/nanoflow changes do NOT imply Docker
    F. Structural entity/association changes do NOT automatically imply Docker
    G. Container-parity verification MAY select Docker
    H. Deployable/container-build verification MAY select Docker
    I. Local-runtime failure allows justified Docker escalation
    J. Generated projections contain consistent runtime guidance
    K. Existing projects remain upgrade-compatible (safe defaults)
    L. UI-driven configuration and runtime strategy do not contradict each other
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

# Key canonical source paths
$runtimeStratPath    = Join-Path $ScriptDir ".mxagile/policies/runtime-strategy.md"
$devRuntimePath      = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$testWorkflowPath    = Join-Path $ScriptDir ".mxagile/policies/test-workflow.md"
$qualityGatePath     = Join-Path $ScriptDir ".mxagile/skills/quality-gate.md"
$orchestratorPath    = Join-Path $ScriptDir ".mxagile/orchestrator.md"
$uiAgentPath         = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$acceptanceAgentPath = Join-Path $ScriptDir ".mxagile/agents/acceptance-agent.md"
$implAgentPath       = Join-Path $ScriptDir ".mxagile/agents/implementation-agent.md"
$lifecyclePath       = Join-Path $ScriptDir ".mxagile/lifecycle.yaml"
$schemaPath          = Join-Path $ScriptDir ".mxagile/schemas/mxagile-project.schema.json"

# Generated projection paths (Claude platform)
$genQualityGatePath     = Join-Path $ScriptDir ".claude/skills/mxagile-quality-gate/SKILL.md"
$genUiAgentPath         = Join-Path $ScriptDir ".claude/agents/mxagile-ui-agent.md"
$genAcceptanceAgentPath = Join-Path $ScriptDir ".claude/agents/mxagile-acceptance-agent.md"

Write-Host ""
Write-Host "=== Runtime Strategy Tests: Local First, Docker By Verification Need ==="
Write-Host ""

# =========================================================================
# Canonical policy exists and declares the contract
# =========================================================================

Write-Host "--- Canonical policy: runtime-strategy.md ---"

Assert-True "runtime-strategy.md exists" `
    (Test-Path -LiteralPath $runtimeStratPath) `
    "Canonical policy not found: $runtimeStratPath"

Assert-FileContains "policy: declares LOCAL FIRST" `
    $runtimeStratPath '(?i)LOCAL FIRST'

Assert-FileContains "policy: declares DOCKER BY VERIFICATION NEED" `
    $runtimeStratPath '(?i)DOCKER BY VERIFICATION NEED'

Assert-FileContains "policy: defines escalation model with levels" `
    $runtimeStratPath '(?i)escalation model|Level 1|Level 2|Level 3|Level 4'

Assert-FileContains "policy: local runtime Level 3 defined" `
    $runtimeStratPath '(?i)Level 3'

Assert-FileContains "policy: Docker Level 4 defined" `
    $runtimeStratPath '(?i)Level 4'

Assert-FileContains "policy: decision table present" `
    $runtimeStratPath '(?i)decision table|need.*mechanism'

Write-Host ""

# =========================================================================
# A. Normal implementation selects local-first guidance
# =========================================================================

Write-Host "--- A: Normal implementation selects local-first ---"

Assert-FileContains "development-runtime: mxcli run --local preferred" `
    $devRuntimePath 'mxcli run --local'

Assert-FileContains "development-runtime: references runtime-strategy escalation" `
    $devRuntimePath '(?i)runtime.strategy|escalat'

Assert-FileContains "quality-gate: local runtime Step 5 preferred" `
    $qualityGatePath '(?i)mxcli run --local|lokal.*runtime|warmer.*runtime|local.*runtime'

Assert-FileContains "quality-gate: references runtime-strategy.md" `
    $qualityGatePath 'runtime-strategy'

Assert-FileContains "orchestrator: local runtime referenced in Verifying" `
    $orchestratorPath '(?i)mxcli run --local.*watch|lokal.*runtime|local.*runtime'

Assert-FileContains "orchestrator: references runtime-strategy.md" `
    $orchestratorPath 'runtime-strategy'

Write-Host ""

# =========================================================================
# B. UI-driven iteration selects local warm runtime
# =========================================================================

Write-Host "--- B: UI-driven iteration selects local warm runtime ---"

Assert-FileContains "runtime-strategy: ui_driven section present" `
    $runtimeStratPath '(?i)ui.driven|UI-Driven Integration'

Assert-FileContains "runtime-strategy: local runtime for UI iteration" `
    $runtimeStratPath '(?i)ui.*iteration.*local|edit.*render.*inspect'

Assert-FileNotContains "runtime-strategy: UI iteration does NOT require Docker" `
    $runtimeStratPath '(?i)ui.*iteration.*docker.*required|ui.*iteration.*muss.*docker'

Assert-FileContains "development-runtime: visual iteration listed as runtime-relevant" `
    $devRuntimePath '(?i)visual.*iteration'

Assert-FileContains "implementation-agent: UI-iteration uses warm runtime" `
    $implAgentPath '(?i)ui.*iteration|warm.*loop'

Write-Host ""

# =========================================================================
# C. Playwright does NOT imply Docker
# =========================================================================

Write-Host "--- C: Playwright does NOT imply Docker ---"

Assert-FileContains "runtime-strategy: Playwright does not require Docker" `
    $runtimeStratPath '(?i)playwright.*not.*docker|playwright.*does not.*require.*docker|playwright.*requires.*running.*application'

Assert-FileContains "runtime-strategy: Playwright against local runtime" `
    $runtimeStratPath '(?i)playwright.*local|browser.*local'

Assert-FileContains "test-workflow: runtime strategy section exists" `
    $testWorkflowPath '(?i)runtime.strategie|local first'

Assert-FileContains "test-workflow: Playwright does NOT imply Docker" `
    $testWorkflowPath '(?i)playwright.*keine.*docker|playwright.*does not.*require.*docker|playwright.*erfordern.*keine.*docker'

Assert-FileContains "acceptance-agent: references runtime-strategy" `
    $acceptanceAgentPath 'runtime-strategy'

Assert-FileNotContains "acceptance-agent: no Docker-App prerequisite hardcode" `
    $acceptanceAgentPath '(?i)docker.app laeuft \(quality.gate'

Write-Host ""

# =========================================================================
# D. Styling changes do NOT imply Docker
# =========================================================================

Write-Host "--- D: Styling changes do NOT imply Docker ---"

Assert-FileContains "runtime-strategy: styling/page change listed as NOT requiring Docker" `
    $runtimeStratPath '(?i)styling.*changed|page.*changed|seite.*gea'

Assert-FileNotContains "runtime-strategy: styling changes NOT hardcoded to Docker" `
    $runtimeStratPath '(?i)styling.*changed.*docker.*required|styling.*immer.*docker'

Write-Host ""

# =========================================================================
# E. Page/microflow/nanoflow changes do NOT imply Docker
# =========================================================================

Write-Host "--- E: Page/microflow/nanoflow changes do NOT imply Docker ---"

Assert-FileContains "runtime-strategy: microflow change listed as NOT requiring Docker" `
    $runtimeStratPath '(?i)microflow.*changed|microflow.*gea'

Assert-FileContains "runtime-strategy: page change listed as NOT requiring Docker" `
    $runtimeStratPath '(?i)page.*changed|seite.*gea'

Assert-FileNotContains "runtime-strategy: microflow change NOT hardcoded to Docker" `
    $runtimeStratPath '(?i)microflow.*changed.*docker.*required|microflow.*immer.*docker'

Write-Host ""

# =========================================================================
# F. Structural entity/association changes do NOT automatically imply Docker
# =========================================================================

Write-Host "--- F: Structural model changes do NOT automatically imply Docker ---"

Assert-FileContains "runtime-strategy: entity/association change addressed" `
    $runtimeStratPath '(?i)entity.*changed|association.*changed|structural.*model.*change'

Assert-FileContains "runtime-strategy: local runtime handles structural changes via restart" `
    $runtimeStratPath '(?i)auto.reconcile|auto.restart|local.*runtime.*restart|restart.*reconcil'

Assert-FileNotContains "runtime-strategy: no Entity-changed-implies-Docker rebuild requirement" `
    $runtimeStratPath '(?i)entity.*changed.*schedule.*docker|entity.*changed.*requires.*docker.*rebuild'

Write-Host ""

# =========================================================================
# G. Container-parity verification MAY select Docker
# =========================================================================

Write-Host "--- G: Container-parity may select Docker ---"

Assert-FileContains "runtime-strategy: container parity justifies Docker" `
    $runtimeStratPath '(?i)container.parity|container.*umgebung|container-environment parity'

Assert-FileContains "runtime-strategy: Docker for container parity listed" `
    $runtimeStratPath '(?i)container parity.*docker|docker.*container parity'

Assert-FileContains "test-workflow: Docker Level 4 section still present" `
    $testWorkflowPath '(?i)docker.*playwright.*test|docker.*build.*container'

Assert-FileContains "quality-gate: mxcli docker check preserved" `
    $qualityGatePath 'mxcli docker check'

Write-Host ""

# =========================================================================
# H. Deployable/container-build verification MAY select Docker
# =========================================================================

Write-Host "--- H: Deployable/container-build may select Docker ---"

Assert-FileContains "runtime-strategy: deployable-build justifies Docker" `
    $runtimeStratPath '(?i)deployable.build|container.*deploy|mxcli docker build'

Assert-FileContains "runtime-strategy: Docker IS for section present" `
    $runtimeStratPath '(?i)docker is for|docker.*ist fuer|what docker is for'

Write-Host ""

# =========================================================================
# I. Local-runtime failure allows justified Docker escalation
# =========================================================================

Write-Host "--- I: Local-runtime failure allows justified escalation ---"

Assert-FileContains "runtime-strategy: justified escalation process defined" `
    $runtimeStratPath '(?i)justified escalation|escalat.*justif|begruendung|diagnos'

Assert-FileContains "runtime-strategy: what evidence is required must be stated" `
    $runtimeStratPath '(?i)what evidence|required.*evidence|evidence.*required'

Assert-FileContains "runtime-strategy: why local cannot provide it must be stated" `
    $runtimeStratPath '(?i)why.*current level.*cannot|State.*why|cannot provide'

Assert-FileContains "runtime-strategy: silent fallback forbidden" `
    $runtimeStratPath '(?i)silent.*fallback.*not|no.*silent.*fallback|nicht.*kommentarlos.*docker'

Write-Host ""

# =========================================================================
# J. Generated projections contain consistent runtime guidance
# =========================================================================

Write-Host "--- J: Generated projections consistent runtime guidance ---"

# Check Claude-projected quality-gate skill
Assert-True "generated quality-gate skill exists" `
    (Test-Path -LiteralPath $genQualityGatePath) `
    "Generated skill not found: $genQualityGatePath"

Assert-FileContains "generated quality-gate: local runtime step present" `
    $genQualityGatePath '(?i)mxcli run --local|lokal.*runtime|warmer.*runtime|local.*runtime'

Assert-FileContains "generated quality-gate: references runtime-strategy" `
    $genQualityGatePath 'runtime-strategy'

# Check Claude-projected ui-agent
Assert-True "generated ui-agent exists" `
    (Test-Path -LiteralPath $genUiAgentPath) `
    "Generated agent not found: $genUiAgentPath"

Assert-FileContains "generated ui-agent: verify mode not hardcoded to Docker" `
    $genUiAgentPath '(?i)applikation laeuft|application.*running|laeuft.*per.*browser|running.*browser'

Assert-FileNotContains "generated ui-agent: verify trigger does not require Docker-App" `
    $genUiAgentPath 'Trigger: Phase ist `verifying` und Docker-App laeuft\.'

# Check Claude-projected acceptance-agent
Assert-True "generated acceptance-agent exists" `
    (Test-Path -LiteralPath $genAcceptanceAgentPath) `
    "Generated agent not found: $genAcceptanceAgentPath"

Assert-FileContains "generated acceptance-agent: references runtime-strategy" `
    $genAcceptanceAgentPath 'runtime-strategy'

Assert-FileNotContains "generated acceptance-agent: no Docker-App hardcoded prerequisite" `
    $genAcceptanceAgentPath '(?i)- docker-app laeuft \(quality-gate hat bestanden\)'

Write-Host ""

# =========================================================================
# K. Existing projects remain upgrade-compatible (safe defaults)
# =========================================================================

Write-Host "--- K: Existing projects upgrade-compatible ---"

Assert-FileContains "schema: runtime section with local_first default" `
    $schemaPath '"local_first"'

Assert-FileContains "schema: runtime.verification field present" `
    $schemaPath '"verification"'

Assert-FileContains "schema: existing projects get local_first default" `
    $schemaPath '(?i)existing projects without.*local_first|absent.*local_first'

Assert-FileContains "runtime-strategy: safe default for existing projects" `
    $runtimeStratPath '(?i)existing projects.*local_first|without.*runtime.*local_first'

Write-Host ""

# =========================================================================
# L. UI-driven configuration and runtime strategy do not contradict
# =========================================================================

Write-Host "--- L: UI-driven config and runtime strategy do not contradict ---"

Assert-FileContains "runtime-strategy: ui_driven section uses local runtime loop" `
    $runtimeStratPath '(?i)UI-Driven Integration|ui_driven.*fast.*render|render.*inspect.*local'

Assert-FileContains "runtime-strategy: UI loop does not force Docker builds" `
    $runtimeStratPath '(?i)full deployment build|container rebuild'

Assert-FileContains "ui-agent: references runtime-strategy" `
    $uiAgentPath 'runtime-strategy'

Assert-FileContains "ui-agent: verify mode references local runtime option" `
    $uiAgentPath '(?i)local.*runtime|lokal.*runtime|mxcli run --local'

Assert-FileNotContains "ui-agent: verify mode hardcoded to Docker-App only" `
    $uiAgentPath 'Trigger: Phase ist `verifying` und Docker-App laeuft\.'

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Runtime Strategy Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Runtime strategy guidance is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Runtime strategy (Local First, Docker By Verification Need) is complete and consistent." -ForegroundColor Green
    exit 0
}
