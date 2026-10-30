<#
.SYNOPSIS
    Credential Discovery and Bootstrap Tests

.DESCRIPTION
    Validates that MxAgile canonical guidance implements the Credential Bootstrap
    contract: Discover before blocking, safe secrets, bootstrap only missing values,
    no credential mutation, auto-resume.

    Test cases:
    A. Project-local credential discovery occurs before blocker classification
    B. Existing .env.mendix configuration is discovered automatically
    C. Secret values never appear in reports/generated tracked artifacts
    D. Existing valid credentials are not requested again
    E. Missing required keys lead to a targeted user request
    F. Only missing keys are requested (not all keys)
    G. User is instructed to populate the canonical local secret mechanism
    H. Config/secret completion allows the blocked lifecycle step to resume
    I. Failed default credentials do NOT trigger automatic password reset
    J. Credential readiness state survives session re-sync without persisting secrets
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
$credDiscovPath   = Join-Path $ScriptDir ".mxagile/policies/credential-discovery.md"
$safetyRulesPath  = Join-Path $ScriptDir ".mxagile/policies/safety-rules.md"
$devRuntimePath   = Join-Path $ScriptDir ".mxagile/policies/development-runtime.md"
$discoveryAgentPath = Join-Path $ScriptDir ".mxagile/agents/discovery-agent.md"
$uiAgentPath = Join-Path $ScriptDir ".mxagile/agents/ui-agent.md"
$acceptanceAgentPath = Join-Path $ScriptDir ".mxagile/agents/acceptance-agent.md"
$qualityGatePath = Join-Path $ScriptDir ".mxagile/skills/quality-gate.md"
$projectSchemaPath = Join-Path $ScriptDir ".mxagile/schemas/mxagile-project.schema.json"
$orchestratorPath = Join-Path $ScriptDir ".mxagile/orchestrator.md"
$processStatePath = Join-Path $ScriptDir ".mxagile/schemas/process-state.schema.json"
$projectSchemaPath = Join-Path $ScriptDir ".mxagile/schemas/mxagile-project.schema.json"

# Generated projections (Claude)
$genAcceptancePath = Join-Path $ScriptDir ".claude/agents/mxagile-acceptance-agent.md"
$genUiAgentPath    = Join-Path $ScriptDir ".claude/agents/mxagile-ui-agent.md"
$genQualityGatePath = Join-Path $ScriptDir ".claude/skills/mxagile-quality-gate/SKILL.md"

Write-Host ""
Write-Host "=== Credential Discovery and Bootstrap Tests ==="
Write-Host ""

# =========================================================================
# Canonical policy exists
# =========================================================================

Write-Host "--- Canonical policy: credential-discovery.md ---"

Assert-True "credential-discovery.md exists" `
    (Test-Path -LiteralPath $credDiscovPath) `
    "Canonical policy not found: $credDiscovPath"

Assert-FileContains "policy: DISCOVER before blocking contract" `
    $credDiscovPath '(?i)DISCOVER.*RESOLVE|discover.*before.*block|discover.*before.*declaring'

Assert-FileContains "policy: discovery order defined" `
    $credDiscovPath '(?i)discovery order|inspect.*\.env\.mendix|\.env\.mendix.*first'

$discoveryPolicyContent = Get-Content -LiteralPath $credDiscovPath -Raw
$discoverySources = @(
    '.env.mendix',
    '.env*',
    'mxcli configuration',
    'Mendix runtime configuration',
    'Database configuration',
    'Company Layer configuration',
    'Project-local bootstrap scripts',
    'Documented bootstrap mechanisms'
)
$previousSourceIndex = -1
$discoveryOrderValid = $true
foreach ($source in $discoverySources) {
    $sourceIndex = $discoveryPolicyContent.IndexOf($source, [System.StringComparison]::OrdinalIgnoreCase)
    if ($sourceIndex -le $previousSourceIndex) {
        $discoveryOrderValid = $false
        break
    }
    $previousSourceIndex = $sourceIndex
}
Assert-True "policy: all canonical discovery sources retain their order" `
    $discoveryOrderValid "Expected the existing eight-source order from .env.mendix through documented bootstrap mechanisms"

Assert-FileContains "policy: configuration precedence defined" `
    $credDiscovPath '(?i)configuration precedence|precedence|\.env\.mendix.*wins|project-local.*wins'

Write-Host ""

# =========================================================================
# A. Project-local credential discovery occurs before blocker classification
# =========================================================================

Write-Host "--- A: Credential discovery before blocker classification ---"

Assert-FileContains "policy: must discover before blocking" `
    $credDiscovPath '(?i)declaring.*blocker.*is.*agent.*fault|without.*performing.*discovery.*is.*agent|declaring a blocker without'

Assert-FileContains "development-runtime: credential discovery before runtime start" `
    $devRuntimePath '(?i)credential.*discovery.*before.*runtime|discovery.*before.*runtime.*start'

Assert-FileContains "development-runtime: references credential-discovery policy" `
    $devRuntimePath 'credential-discovery'

Assert-FileContains "credential policy: runtime/browser preflight before escalation" `
    $credDiscovPath '(?i)Runtime and Browser Preflight|before starting a runtime|full discovery path'

Assert-FileContains "quality gate: credential discovery before runtime startup" `
    $qualityGatePath '(?is)Credential-Verfuegbarkeit vor dem.*Runtime-Start'

Assert-FileContains "acceptance agent: credential discovery before runtime/login" `
    $acceptanceAgentPath '(?i)credential-discovery\.md.*complete credential preflight|complete credential preflight'

Assert-FileContains "acceptance agent: exhausted discovery before USER_INPUT_REQUIRED" `
    $acceptanceAgentPath '(?i)full discovery path is exhausted'

Assert-FileContains "UI agent: credentials checked before runtime start and login" `
    $uiAgentPath '(?i)Vor Runtime-Start und vor dem ersten Playwright-/Browser-Login'

Assert-FileContains "generated acceptance agent: credential preflight is projected" `
    $genAcceptancePath '(?i)complete credential preflight'

Assert-FileContains "generated UI agent: early credential preflight is projected" `
    $genUiAgentPath '(?i)Runtime-Preparation ist vor dem Runtime-Start'

Assert-FileContains "generated quality gate: credential preflight is projected" `
    $genQualityGatePath '(?i)Credential-Verfuegbarkeit vor dem'

Assert-FileContains "project schema: .env.mendix is canonical credential default" `
    $projectSchemaPath '(?i)Default: \.env\.mendix \(gitignored\)'

Assert-FileContains "discovery-agent: credential discovery before runtime start" `
    $discoveryAgentPath '(?i)credential.*discovery|\.env\.mendix.*pruefen'

Assert-FileContains "orchestrator: credential bootstrap section present" `
    $orchestratorPath '(?i)credential bootstrap|prerequisite.*discovery|credential-discovery'

Write-Host ""

# =========================================================================
# B. Existing .env.mendix is discovered automatically
# =========================================================================

Write-Host "--- B: .env.mendix discovered automatically ---"

Assert-FileContains "policy: .env.mendix explicitly listed in discovery order" `
    $credDiscovPath '\.env\.mendix'

Assert-FileContains "policy: discover .env.mendix before asking developer" `
    $credDiscovPath '(?i)do not ask.*developer.*where.*credentials|do not ask.*before.*discovery'

Assert-FileContains "development-runtime: inspect .env.mendix before runtime" `
    $devRuntimePath '\.env\.mendix'

Assert-FileContains "safety-rules: .env.mendix stays local" `
    $safetyRulesPath '\.env\.mendix'

Write-Host ""

# =========================================================================
# C. Secret values never appear in reports/generated artifacts
# =========================================================================

Write-Host "--- C: Secret values never in reports/artifacts ---"

Assert-FileContains "safety-rules: never output secret values" `
    $safetyRulesPath '(?i)niemals ausgeben|never.*output.*secret|secret.*never.*output'

Assert-FileContains "safety-rules: never write secrets to tracked artifacts" `
    $safetyRulesPath '(?i)reports.*process-state|nicht.*versionieren|never.*tracked'

Assert-FileContains "policy: secret values excluded from Context Mode and agent handoffs" `
    $credDiscovPath '(?i)Context Mode.*agent handoffs|agent handoffs.*Context Mode'

Assert-FileContains "safety-rules: credentials excluded from Context Mode and agent handoffs" `
    $safetyRulesPath '(?is)Credential-Werte.*Context-Mode.*Session-Zusammenfassungen.*Agent-/Subagent-Handoffs'

Assert-FileContains "policy: local .env.mendix status check does not expose values" `
    $credDiscovPath '(?i)gitignored.*not a prohibition|checked locally.*required key names|Do not emit its contents'

Assert-FileContains "policy: .env.mendix.example is not a credential source" `
    $credDiscovPath '(?i)versioned template'

Assert-FileContains "policy: .env.mendix.example placeholders are unusable" `
    $credDiscovPath '(?i)never treat its placeholders as usable credentials'

Assert-FileContains "R2: complete discovered credentials permit autonomous continuation" `
    $credDiscovPath '(?i)continue autonomously'

Assert-FileContains "R3/R4: EMPTY or missing source does not stop discovery" `
    $credDiscovPath '(?i)missing file or EMPTY key is not a reason'

Assert-FileContains "R5: exhausted discovery permits one targeted escalation" `
    $credDiscovPath '(?i)After all sources are exhausted'

Assert-FileContains "R5: escalation is a single targeted request" `
    $credDiscovPath '(?i)one targeted request'

Assert-FileContains "R6: failed login does not reveal or re-request credentials" `
    $credDiscovPath '(?i)do not reveal or request those values again'

Assert-FileContains "R7/R8: Context Mode and agent handoffs exclude credential values" `
    $safetyRulesPath '(?is)Credential-Werte.*Context-Mode.*Session-Zusammenfassungen.*Agent-/Subagent-Handoffs'

Assert-FileContains "policy: report only readiness metadata (PRESENT/MISSING/etc)" `
    $credDiscovPath 'PRESENT'

Assert-FileContains "policy: MISSING classification defined" `
    $credDiscovPath 'MISSING'

Assert-FileContains "policy: never include secret values in reports" `
    $credDiscovPath '(?i)NEVER include.*secret|secret.*values.*never.*reports'

Assert-FileContains "process-state schema: prerequisite_state never stores credentials" `
    $processStatePath '(?i)never.*secret|credential.*value|secret.*value'

Write-Host ""

# =========================================================================
# D. Existing valid credentials are not requested again
# =========================================================================

Write-Host "--- D: Existing valid credentials not re-requested ---"

Assert-FileContains "policy: do not request already configured values" `
    $credDiscovPath '(?i)not.*request.*keys.*already.*PRESENT|do not ask.*recreate|NOT.*request.*already'

Assert-FileContains "policy: only missing/empty keys requested" `
    $credDiscovPath '(?i)only.*missing.*keys|request.*only.*missing|missing.*keys.*only'

Assert-FileContains "policy: one request per configuration state" `
    $credDiscovPath '(?i)one request per|not repeatedly ask|do not repeat'

Write-Host ""

# =========================================================================
# E. Missing required keys lead to a targeted user request
# =========================================================================

Write-Host "--- E: Missing keys lead to targeted user request ---"

Assert-FileContains "policy: targeted request for missing keys" `
    $credDiscovPath '(?i)missing.*keys.*request|request.*only.*missing|ask.*user.*missing'

Assert-FileContains "policy: request names the canonical secret file" `
    $credDiscovPath '(?i)name.*canonical.*file|\.env\.mendix.*request|request.*\.env\.mendix'

Assert-FileContains "policy: request states non-secret purpose of each key" `
    $credDiscovPath '(?i)non-secret purpose|purpose.*of.*each.*key|key.*purpose'

Write-Host ""

# =========================================================================
# F. Only missing keys are requested (not all keys)
# =========================================================================

Write-Host "--- F: Only missing keys requested ---"

Assert-FileContains "policy: only missing keys requested" `
    $credDiscovPath '(?i)only.*missing.*keys|request.*only.*those.*missing|do not.*ask.*recreate'

Assert-FileContains "policy: do not ask for existing keys" `
    $credDiscovPath '(?i)NOT.*request.*keys.*already.*PRESENT|do not.*overwrite.*existing'

Write-Host ""

# =========================================================================
# G. User instructed to populate canonical secret mechanism, not chat
# =========================================================================

Write-Host "--- G: User populates canonical file, not chat ---"

Assert-FileContains "policy: instruct to populate .env.mendix (not chat)" `
    $credDiscovPath '(?i)populate.*\.env\.mendix|directly.*in.*\.env\.mendix'

Assert-FileContains "policy: do not send secrets in chat" `
    $credDiscovPath '(?i)not.*send.*secret.*chat|do not.*paste.*secret.*chat'

Assert-FileContains "policy: example request pattern present" `
    $credDiscovPath '(?i)example.*request|request.*pattern|runtime verification.*ready.*except'

Write-Host ""

# =========================================================================
# H. Config/secret completion allows blocked lifecycle step to resume
# =========================================================================

Write-Host "--- H: Auto-resume after secret completion ---"

Assert-FileContains "policy: auto-resume contract defined" `
    $credDiscovPath '(?i)auto.resume|Auto-Resume|resume.*automatically'

Assert-FileContains "policy: developer does not need to give new command" `
    $credDiscovPath '(?i)developer.*must not.*need.*new.*command|agent.*owns.*continuation|developer.*NOT.*need'

Assert-FileContains "policy: blocked operation recorded for resume" `
    $credDiscovPath '(?i)blocked.*operation|resume.*point|retain.*blocked'

Assert-FileContains "process-state schema: blocked_operation field present" `
    $processStatePath '(?i)blocked_operation'

Assert-FileContains "process-state schema: prerequisite_state present" `
    $processStatePath '(?i)prerequisite_state'

Write-Host ""

# =========================================================================
# I. Failed default credentials do NOT trigger automatic password reset
# =========================================================================

Write-Host "--- I: Failed default credentials do NOT trigger password reset ---"

Assert-FileContains "policy: credential mutation prohibition" `
    $credDiscovPath '(?i)credential mutation prohibition|mutation.*prohibition'

Assert-FileContains "policy: ALTER USER explicitly forbidden" `
    $credDiscovPath '(?i)ALTER USER'

Assert-FileContains "policy: password reset explicitly forbidden" `
    $credDiscovPath '(?i)password reset|password.*reset.*forbidden'

Assert-FileContains "policy: failed default does NOT authorize mutation" `
    $credDiscovPath '(?i)failed.*default.*does not authorize|failed.*credential.*does.*not.*authorize'

Assert-FileContains "safety-rules: credential mutation prohibition" `
    $safetyRulesPath '(?i)credential.mutations.verbot|Credential-Mutations-Verbot|ALTER USER'

Assert-FileContains "development-runtime: no ALTER USER or password reset" `
    $devRuntimePath '(?i)ALTER USER|credential mutation|passwort.reset'

Write-Host ""

# =========================================================================
# J. Credential readiness state survives session re-sync without persisting secrets
# =========================================================================

Write-Host "--- J: Readiness state survives re-sync, secrets not persisted ---"

Assert-FileContains "process-state schema: runtime_config state field" `
    $processStatePath '(?i)runtime_config'

Assert-FileContains "process-state schema: states do not include credential values" `
    $processStatePath '(?i)NEVER store credential|never.*secret.*values'

Assert-FileContains "policy: readiness survives session re-sync" `
    $credDiscovPath '(?i)readiness.*survives.*session|session re.sync|state.*survives'

Assert-FileContains "policy: agent must not retain secrets between sessions" `
    $credDiscovPath '(?i)must not retain.*secret|not retain.*actual secret|agent.*must not.*retain'

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Credential Discovery Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Credential discovery guidance is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Credential discovery and bootstrap guidance is complete and consistent." -ForegroundColor Green
    exit 0
}
