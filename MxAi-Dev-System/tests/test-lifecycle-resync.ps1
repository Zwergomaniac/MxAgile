<#
.SYNOPSIS
    Lifecycle Re-Sync & Interrupt/Resume Tests

.DESCRIPTION
    Validates that the MxAgile Lifecycle Re-Sync & Interrupt/Resume contract is
    consistently defined across all relevant framework files.

    Scenarios tested:
    A. Duplicate process-state keys are prevented by schema and policy
    B. Invalid lifecycle state detection is documented
    C. Fresh agent can reconstruct implementing/resume position from repository artifacts
    D. Observation interruption: start app -> phase unchanged -> resume implementation
    E. Clarification interruption: decision supplied -> affected gate re-evaluated
    F. Changed mockup: affected scope re-enters appropriate lifecycle work
    G. Unaffected work is preserved across interruptions
    H. Runtime startup never marks Verification complete
    I. Pause mid-wave preserves completed checklist items
    J. Agent does not unnecessarily reject legitimate user instructions
    K. UI-driven contract remains intact
    L. Warm-local-loop contract remains intact
    M. Existing lifecycle canon tests remain consistent
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

# File paths
$lifecycleYaml    = Join-Path $ScriptDir ".mxagile\lifecycle.yaml"
$orchestratorMd   = Join-Path $ScriptDir ".mxagile\orchestrator.md"
$resyncPolicyPath = Join-Path $ScriptDir ".mxagile\policies\lifecycle-resync.md"
$processSchemaPath= Join-Path $ScriptDir ".mxagile\schemas\process-state.schema.json"
$implAgentPath    = Join-Path $ScriptDir ".mxagile\agents\implementation-agent.md"
$uiAgentPath      = Join-Path $ScriptDir ".mxagile\agents\ui-agent.md"
$devRuntimePath   = Join-Path $ScriptDir ".mxagile\policies\development-runtime.md"
$discoverySkillPath = Join-Path $ScriptDir ".mxagile\skills\discovery.md"
$gateRefinePath   = Join-Path $ScriptDir ".mxagile\skills\gate-to-refinement.md"

Write-Host ""
Write-Host "=== Lifecycle Re-Sync & Interrupt/Resume Tests ==="
Write-Host ""

# =========================================================================
# A. Duplicate process-state keys prevention
# =========================================================================

Write-Host "--- A: Duplicate process-state keys cannot be produced ---"

Assert-True "process-state.schema.json exists" `
    (Test-Path -LiteralPath $processSchemaPath) `
    "Schema not found: $processSchemaPath"

if (Test-Path -LiteralPath $processSchemaPath) {
    $schemaContent = Get-Content -LiteralPath $processSchemaPath -Raw
    Assert-True "schema: phase field defined exactly once in wave" `
        ($schemaContent -match '"phase"') `
        "phase field not defined in process-state schema"
    Assert-True "schema: duplicate-key prevention rule documented" `
        ($schemaContent -match 'never append|append.*duplicate|CANONICAL UPDATE') `
        "Schema must document canonical update rule"
    Assert-True "schema: wave phase is enum of valid phases" `
        ($schemaContent -match '"discovery".*"refinement"|discovery.*refinement.*implementing') `
        "Schema must enumerate valid lifecycle phases"
}

Assert-FileContains "lifecycle-resync.md exists and documents anti-append rule" `
    $resyncPolicyPath 'gesamten Wave-Block|GESAMTEN Wave-Block|complete.*wave.*block'

Assert-FileContains "lifecycle-resync.md: anti-append rule explicitly stated" `
    $resyncPolicyPath 'Niemals.*anhaengen|Never.*append|anhaengen.*dupliziert'

Assert-FileContains "lifecycle.yaml: schema reference added" `
    $lifecycleYaml 'process-state.schema.json'

Assert-FileContains "lifecycle.yaml: canonical update rule documented" `
    $lifecycleYaml 'canonical_update_rule|never append|COMPLETE wave'

Assert-FileContains "orchestrator.md: process-state canonical update rule" `
    $orchestratorMd 'kanonische Aktualisierung|GESAMTEN Wave-Block'

Write-Host ""

# =========================================================================
# B. Invalid lifecycle state detection
# =========================================================================

Write-Host "--- B: Invalid lifecycle state is detected ---"

Assert-FileContains "lifecycle-resync.md: validation table exists" `
    $resyncPolicyPath 'Zustandsvalidierung|State Validation'

Assert-FileContains "lifecycle-resync.md: duplicate phase key detection" `
    $resyncPolicyPath 'Duplizierter phase-Key|duplicate.*phase|phase.*duplicate'

Assert-FileContains "lifecycle-resync.md: unknown lifecycle phase detection" `
    $resyncPolicyPath 'Unbekannte.*Phase|unknown.*phase|phase.*nicht in'

Assert-FileContains "lifecycle-resync.md: invalid gate result detection" `
    $resyncPolicyPath 'Ungueltiges Gate|invalid gate|not_recorded.*passed.*failed'

Assert-FileContains "lifecycle-resync.md: inconsistent phase/gate detection" `
    $resyncPolicyPath 'Inkonsistente Phase|implementing.*not_recorded|gate_to_ready.*not_recorded'

Assert-FileContains "lifecycle-resync.md: implementing without checklist detection" `
    $resyncPolicyPath 'Implementing ohne Checkliste|implementing.*no.*checklist|implementing.*checklist.*nicht'

Write-Host ""

# =========================================================================
# C. Fresh agent can reconstruct implementing/resume position
# =========================================================================

Write-Host "--- C: Fresh agent can reconstruct resume position ---"

Assert-FileContains "lifecycle-resync.md: startup re-sync algorithm defined" `
    $resyncPolicyPath 'Startup Re-Sync|startup.*re-sync|re-sync.*algorithm'

Assert-FileContains "lifecycle-resync.md: reads lifecycle.yaml" `
    $resyncPolicyPath 'lifecycle\.yaml'

Assert-FileContains "lifecycle-resync.md: reads process-state.yaml" `
    $resyncPolicyPath 'process-state\.yaml'

Assert-FileContains "lifecycle-resync.md: reads implementation checklist" `
    $resyncPolicyPath 'implementation-checklist|Implementierungs-Checkliste'

Assert-FileContains "lifecycle-resync.md: reads decisions.md" `
    $resyncPolicyPath 'decisions\.md'

Assert-FileContains "lifecycle-resync.md: no conversational memory required" `
    $resyncPolicyPath 'Konversationsspeicher.*nicht|kein.*Konversations|no conversational memory'

Assert-FileContains "lifecycle-resync.md: checklist is authoritative for resume position" `
    $resyncPolicyPath 'Checklisten.*autoritativ|checklist.*authoritativ|checklist.*authoritative'

Assert-FileContains "orchestrator.md: startup re-sync section present" `
    $orchestratorMd 'Startup Re-Sync'

Write-Host ""

# =========================================================================
# D. Observation interruption: phase unchanged
# =========================================================================

Write-Host "--- D: Observation interruption leaves lifecycle phase unchanged ---"

Assert-FileContains "lifecycle-resync.md: OBSERVATION class defined" `
    $resyncPolicyPath 'OBSERVATION'

Assert-FileContains "lifecycle-resync.md: start app is OBSERVATION" `
    $resyncPolicyPath 'Start.*App.*OBSERVATION|OBSERVATION.*Start.*App|start app'

Assert-FileContains "lifecycle-resync.md: OBSERVATION phase unchanged" `
    $resyncPolicyPath 'UNVERAENDERT|phase.*unchanged|unchanged.*phase'

Assert-FileContains "lifecycle-resync.md: OBSERVATION resumes from same position" `
    $resyncPolicyPath 'vorherige.*fortsetzen|selben Position|same position'

Assert-FileContains "orchestrator.md: OBSERVATION in interruption table" `
    $orchestratorMd 'OBSERVATION.*Phase UNVERAENDERT|OBSERVATION.*unchanged|OBSERVATION.*zeig'

Write-Host ""

# =========================================================================
# E. Clarification interruption: affected gate re-evaluated
# =========================================================================

Write-Host "--- E: Clarification interruption triggers re-evaluation of affected gate ---"

Assert-FileContains "lifecycle-resync.md: CLARIFICATION class defined" `
    $resyncPolicyPath 'CLARIFICATION'

Assert-FileContains "lifecycle-resync.md: decisions documented on clarification" `
    $resyncPolicyPath 'decisions\.md.*dokumentieren|Entscheidung.*dokumentieren'

Assert-FileContains "lifecycle-resync.md: clarification does not auto-pass gate" `
    $resyncPolicyPath 'Gate.*automatisch bestanden|gate.*auto.*pass|nicht automatisch.*Gate|Gate NICHT automatisch'

Assert-FileContains "lifecycle-resync.md: only affected gate re-evaluated" `
    $resyncPolicyPath 'nur.*betroffene.*Gate|betroffene.*Gate.*re-evaluier|only.*affected.*gate'

Write-Host ""

# =========================================================================
# F. Changed mockup: affected scope re-enters appropriate phase
# =========================================================================

Write-Host "--- F: Changed mockup triggers earliest-phase re-entry for affected scope ---"

Assert-FileContains "lifecycle-resync.md: CHANGE class defined" `
    $resyncPolicyPath '### CHANGE'

Assert-FileContains "lifecycle-resync.md: mockup change -> discovery" `
    $resyncPolicyPath 'input-resources.*ui-ux.*discovery|ui-ux.*Mockup.*discovery'

Assert-FileContains "lifecycle-resync.md: IMPACT_REVIEW_REQUIRED vocabulary used" `
    $resyncPolicyPath 'IMPACT_REVIEW_REQUIRED'

Assert-FileContains "lifecycle-resync.md: CURRENT vocabulary for unaffected" `
    $resyncPolicyPath 'CURRENT.*bewahren|unbeeinflusste.*CURRENT|CURRENT.*unaffected'

Assert-FileContains "lifecycle.yaml: change_propagation mockup_changed -> discovery" `
    $lifecycleYaml 'mockup_changed'

Assert-FileContains "lifecycle.yaml: change_propagation vocabulary IMPACT_REVIEW_REQUIRED" `
    $lifecycleYaml 'IMPACT_REVIEW_REQUIRED'

Write-Host ""

# =========================================================================
# G. Unaffected work is preserved
# =========================================================================

Write-Host "--- G: Unaffected work is preserved across interruptions ---"

Assert-FileContains "lifecycle.yaml: return_routing preserves unaffected stories" `
    $lifecycleYaml 'Unaffected stories remain CURRENT|unaffected.*CURRENT'

Assert-FileContains "lifecycle-resync.md: unaffected scope preserved as CURRENT" `
    $resyncPolicyPath 'Unbeeinflusste.*CURRENT|unbeeinflusste.*CURRENT|Unbetroffene.*CURRENT'

Assert-FileContains "lifecycle-resync.md: no full wave restart required" `
    $resyncPolicyPath 'KEIN.*Lifecycle-Neustart|no.*full.*restart|gesamten Wave.*nicht neu starten'

Assert-FileContains "lifecycle-resync.md: completed checklist items preserved on pause" `
    $resyncPolicyPath 'abgeschlossene.*Items.*bewahren|status.*done.*bewahren|preserve.*done.*items'

Write-Host ""

# =========================================================================
# H. Runtime startup never marks Verification complete
# =========================================================================

Write-Host "--- H: Runtime startup never marks Verification complete ---"

Assert-FileContains "lifecycle-resync.md: verification boundary invariants listed" `
    $resyncPolicyPath 'Verifikationsgrenzen|Verification.*Boundary|Verifikations.*Invariant'

Assert-FileContains "lifecycle-resync.md: app start != verification started" `
    $resyncPolicyPath 'App-Start.*Verifikation|app.*start.*Verifikation|successful.*start.*Verif'

Assert-FileContains "lifecycle-resync.md: runtime inspection != UI-Agent Verify" `
    $resyncPolicyPath 'Runtime-Inspektion.*UI-Agent|runtime.*inspection.*UI-Agent'

Assert-FileContains "orchestrator.md: verification invariants section present" `
    $orchestratorMd 'Verification-Invarianten|Verifikation.*nicht.*ersetzbar'

Assert-FileContains "orchestrator.md: mxcli run succeeded != wave verified" `
    $orchestratorMd 'mxcli run.*verifiziert|run.*local.*verifiziert'

Write-Host ""

# =========================================================================
# I. Pause mid-wave preserves completed checklist items
# =========================================================================

Write-Host "--- I: Pause mid-wave preserves completed items ---"

Assert-FileContains "lifecycle-resync.md: PAUSE class defined" `
    $resyncPolicyPath '### PAUSE'

Assert-FileContains "lifecycle-resync.md: pause preserves done items" `
    $resyncPolicyPath 'status.*done.*bewahren|done.*items.*bewahren|abgeschlossene.*Items.*bewahren'

Assert-FileContains "lifecycle-resync.md: pause records paused_at/pause_reason/next_script" `
    $resyncPolicyPath 'paused_at.*pause_reason|paused_at.*next_script'

Assert-FileContains "lifecycle-resync.md: resume_from is supplementary not authoritative" `
    $resyncPolicyPath 'resume_from.*ergaenzend|ergaenzend.*Freitext|supplementary.*free-text'

Assert-FileContains "lifecycle-resync.md: checklist state is authoritative for resume" `
    $resyncPolicyPath 'Checklisten-Zustand.*autoritativ|checklist.*authoritative.*resume'

Write-Host ""

# =========================================================================
# J. Agent does not unnecessarily reject legitimate instructions
# =========================================================================

Write-Host "--- J: Agent does not unnecessarily reject legitimate instructions ---"

Assert-FileContains "lifecycle-resync.md: user authority section present" `
    $resyncPolicyPath 'Grundprinzip|USER.*Kontrolle|user.*control'

Assert-FileContains "lifecycle-resync.md: prefer execute over refuse" `
    $resyncPolicyPath 'Legitime Anfrage ausfuehren|Anfrage.*ausfuehren|perform.*request'

Assert-FileContains "lifecycle-resync.md: only refuse for safety violations" `
    $resyncPolicyPath 'Safety-Regel|safety.*constraint|sicherheits'

Assert-FileContains "orchestrator.md: no overly rigid behavior" `
    $orchestratorMd 'kein.*uebertriebenes Ablehnen|Kein Agent.*ablehnen.*lediglich'

Assert-FileContains "orchestrator.md: runtime starten is valid in any phase" `
    $orchestratorMd 'Runtime starten.*jeder Phase|gueltige Anfragen in jeder Phase'

Write-Host ""

# =========================================================================
# K. UI-driven contract remains intact
# =========================================================================

Write-Host "--- K: UI-driven contract remains intact ---"

Assert-FileContains "lifecycle-resync.md: ui_driven change propagation defined" `
    $resyncPolicyPath 'ui_driven.*true|UI-Driven.*Projekte|ui.*driven.*projekt'

Assert-FileContains "lifecycle-resync.md: mockup change triggers UI-Agent re-analyze" `
    $resyncPolicyPath 'UI-Agent Analyze.*erneut|re-run.*UI-Agent.*Analyze|Analyze.*geaenderte Mockups'

Assert-FileContains "ui-agent.md: mxagile-project.yaml read still present" `
    $uiAgentPath 'mxagile-project\.yaml'

Assert-FileContains "ui-agent.md: ui_fidelity result block still present" `
    $uiAgentPath 'ui_fidelity'

Assert-FileContains "lifecycle.yaml: change_propagation mockup_changed example present" `
    $lifecycleYaml 'mockup_changed.*upstream|upstream.*input-resources/ui-ux'

Write-Host ""

# =========================================================================
# L. Warm-local-loop contract remains intact
# =========================================================================

Write-Host "--- L: Warm-local-loop contract remains intact ---"

Assert-FileContains "lifecycle-resync.md: runtime state is transient" `
    $resyncPolicyPath 'Runtime-Zustand.*Transient|transient.*runtime|runtime.*transient'

Assert-FileContains "lifecycle-resync.md: runtime state != lifecycle state" `
    $resyncPolicyPath 'Lifecycle-Zustand.*Persistent|Runtime-Zustand.*Transient'

Assert-FileContains "lifecycle-resync.md: runtime changes do not trigger phase transition" `
    $resyncPolicyPath 'Runtime-Zustandsaenderungen.*KEINEN Phasenwechsel|keine.*Phasenwechsel'

Assert-FileContains "development-runtime.md: warm loop guidance preserved" `
    $devRuntimePath 'mxcli run.*local.*watch|--watch'

Assert-FileContains "implementation-agent.md: warm loop section preserved" `
    $implAgentPath 'mxcli run.*local.*watch|--watch'

Assert-FileContains "orchestrator.md: warm local loop section preserved" `
    $orchestratorMd 'Warm Local Loop|Development Runtime.*Warm'

Write-Host ""

# =========================================================================
# M. Existing lifecycle canon tests remain consistent
# =========================================================================

Write-Host "--- M: Existing lifecycle canon is consistent with re-sync additions ---"

Assert-FileContains "lifecycle.yaml: schema_version still present" `
    $lifecycleYaml 'schema_version: 1'

Assert-FileContains "lifecycle.yaml: initial_phase still discovery" `
    $lifecycleYaml 'initial_phase: discovery'

Assert-FileContains "lifecycle.yaml: all 5 phases still present" `
    $lifecycleYaml 'discovery'
Assert-FileContains "lifecycle.yaml: refinement phase" `
    $lifecycleYaml 'refinement:'
Assert-FileContains "lifecycle.yaml: implementing phase" `
    $lifecycleYaml 'implementing:'
Assert-FileContains "lifecycle.yaml: verifying phase" `
    $lifecycleYaml 'verifying:'

Assert-FileContains "lifecycle.yaml: return_routing still present" `
    $lifecycleYaml 'return_routing'

Assert-FileContains "lifecycle.yaml: change_propagation still present" `
    $lifecycleYaml 'change_propagation'

Assert-FileContains "lifecycle.yaml: state_tracking still present" `
    $lifecycleYaml 'state_tracking'

Assert-FileContains "orchestrator.md: references lifecycle.yaml" `
    $orchestratorMd 'lifecycle\.yaml'

Assert-FileContains "lifecycle-resync.md references process-state.schema.json" `
    $resyncPolicyPath 'process-state.schema.json'

Assert-FileContains "process-state.schema.json references lifecycle-resync.md" `
    $processSchemaPath 'lifecycle-resync.md'

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== Lifecycle Re-Sync & Interrupt/Resume Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: Lifecycle Re-Sync contract is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: Lifecycle Re-Sync contract is consistently defined across all framework files." -ForegroundColor Green
    exit 0
}
