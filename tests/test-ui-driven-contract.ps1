<#
.SYNOPSIS
    UI-Driven Contract Tests

.DESCRIPTION
    Validates that the MxAgile Mockup-Driven UI Contract is consistently defined
    across all relevant framework files.

    Scenarios tested:
    A. Project config schema exists and is well-formed
    B. Discovery systematically inventories input-resources/ui-ux/
    C. Concern-specific source authority is documented in source-priority.md
    D. Gate-to-refinement includes concern-reconciliation precondition
    E. Gate-to-ready emits binding UI reference fields for page items
    F. Implementation-Agent reads mxagile-project.yaml and treats UI artifacts as binding
    G. UI-Agent Analyze captures typed navigation and interaction states
    H. UI-Agent Verify reports ui_fidelity result
    I. page.schema.json includes navigation and interaction_states
    J. mxagile-init.ps1 creates input-resources scaffold
    K. Project without mockup — no forced fidelity gate
    L. Input-resources README files referenced in init script
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
$schemaDir          = Join-Path $ScriptDir ".mxagile\schemas"
$projectSchemaPath  = Join-Path $schemaDir "mxagile-project.schema.json"
$pageSchemaPath     = Join-Path $schemaDir "page.schema.json"
$sourcePriorityPath = Join-Path $ScriptDir ".mxagile\policies\source-priority.md"
$discoverySkillPath = Join-Path $ScriptDir ".mxagile\skills\discovery.md"
$discoveryAgentPath = Join-Path $ScriptDir ".mxagile\agents\discovery-agent.md"
$uiAgentPath        = Join-Path $ScriptDir ".mxagile\agents\ui-agent.md"
$gateRefinePath     = Join-Path $ScriptDir ".mxagile\skills\gate-to-refinement.md"
$gateReadyPath      = Join-Path $ScriptDir ".mxagile\skills\gate-to-ready.md"
$implAgentPath      = Join-Path $ScriptDir ".mxagile\agents\implementation-agent.md"
$initScriptPath     = Join-Path $ScriptDir "scripts\mxagile-init.ps1"

Write-Host ""
Write-Host "=== UI-Driven Contract Tests ==="
Write-Host ""

# =========================================================================
# A. Project configuration schema
# =========================================================================

Write-Host "--- A: Project configuration schema ---"

Assert-True "mxagile-project.schema.json exists" `
    (Test-Path -LiteralPath $projectSchemaPath) `
    "Schema not found: $projectSchemaPath"

if (Test-Path -LiteralPath $projectSchemaPath) {
    $schemaContent = Get-Content -LiteralPath $projectSchemaPath -Raw
    Assert-True "schema: development.ui_driven defined" `
        ($schemaContent -match 'ui_driven') `
        "development.ui_driven not in schema"
    Assert-True "schema: source_authority defined" `
        ($schemaContent -match 'source_authority') `
        "source_authority not in schema"
    Assert-True "schema: ui.fidelity defined" `
        ($schemaContent -match 'fidelity') `
        "ui.fidelity not in schema"
    Assert-True "schema: fidelity has standard and high values" `
        ($schemaContent -match '"standard"' -and $schemaContent -match '"high"') `
        "fidelity must enumerate standard and high"
    Assert-True "schema: ui_visual concern defined" `
        ($schemaContent -match 'ui_visual') `
        "source_authority.ui_visual not in schema"
    Assert-True "schema: business_logic concern defined" `
        ($schemaContent -match 'business_logic') `
        "source_authority.business_logic not in schema"
}

Write-Host ""

# =========================================================================
# B. Discovery: systematic input-resources inventory
# =========================================================================

Write-Host "--- B: Discovery systematically inventories input-resources ---"

Assert-FileContains "discovery.md: inventories ui-ux/ explicitly" `
    $discoverySkillPath 'ui-ux'

Assert-FileContains "discovery.md: checks for index.html" `
    $discoverySkillPath 'index\.html'

Assert-FileContains "discovery.md: reads mxagile-project.yaml" `
    $discoverySkillPath 'mxagile-project\.yaml'

Assert-FileContains "discovery.md: ui_driven triggers mandatory UI-Agent" `
    $discoverySkillPath 'ui_driven'

Assert-FileContains "discovery-agent.md: systematic input-resources step" `
    $discoveryAgentPath 'input-resources'

Assert-FileContains "discovery-agent.md: reads mxagile-project.yaml" `
    $discoveryAgentPath 'mxagile-project\.yaml'

Assert-FileContains "discovery-agent.md: ui_driven mandates UI-Agent" `
    $discoveryAgentPath 'ui_driven.*true|true.*ui_driven'

Write-Host ""

# =========================================================================
# C. Concern-specific source authority
# =========================================================================

Write-Host "--- C: Concern-specific source authority in source-priority.md ---"

Assert-FileContains "source-priority.md: concern-specific authority section" `
    $sourcePriorityPath 'source_authority'

Assert-FileContains "source-priority.md: ui_visual concern" `
    $sourcePriorityPath 'ui_visual'

Assert-FileContains "source-priority.md: ui_interaction concern" `
    $sourcePriorityPath 'ui_interaction'

Assert-FileContains "source-priority.md: navigation concern" `
    $sourcePriorityPath 'navigation'

Assert-FileContains "source-priority.md: business_logic concern" `
    $sourcePriorityPath 'business_logic'

Assert-FileContains "source-priority.md: data_rules concern" `
    $sourcePriorityPath 'data_rules'

Assert-FileContains "source-priority.md: no false DECISION REQUIRED for different concerns" `
    $sourcePriorityPath 'reiner Concern-Trennung|verschiedene Concerns'

Write-Host ""

# =========================================================================
# D. Gate-to-refinement: concern-reconciliation precondition
# =========================================================================

Write-Host "--- D: Gate-to-refinement includes concern-reconciliation ---"

Assert-FileContains "gate-to-refinement.md: ui_driven precondition present" `
    $gateRefinePath 'ui_driven'

Assert-FileContains "gate-to-refinement.md: concern-reconciliation required" `
    $gateRefinePath 'Concern-Reconciliation|source_authority'

Assert-FileContains "gate-to-refinement.md: no false DECISION REQUIRED from concern separation" `
    $gateRefinePath 'kein DECISION REQUIRED.*Concern|Concern.*kein DECISION REQUIRED'

Write-Host ""

# =========================================================================
# E. Gate-to-ready: binding UI reference fields in page checklist items
# =========================================================================

Write-Host "--- E: Gate-to-ready emits binding UI reference fields ---"

Assert-FileContains "gate-to-ready.md: source_mockup field in checklist" `
    $gateReadyPath 'source_mockup'

Assert-FileContains "gate-to-ready.md: ui_inventory field in checklist" `
    $gateReadyPath 'ui_inventory'

Assert-FileContains "gate-to-ready.md: layout_reference field in checklist" `
    $gateReadyPath 'layout_reference'

Assert-FileContains "gate-to-ready.md: fidelity field in checklist" `
    $gateReadyPath 'fidelity'

Assert-FileContains "gate-to-ready.md: page items get UI fields when ui_driven" `
    $gateReadyPath 'ui_driven.*true|type: page'

Assert-FileContains "gate-to-ready.md: UI fields make fidelity an obligation" `
    $gateReadyPath 'Implementierungspflicht|bindende'

Write-Host ""

# =========================================================================
# F. Implementation-Agent: reads mxagile-project.yaml, binding when ui_driven
# =========================================================================

Write-Host "--- F: Implementation-Agent consumes binding UI artifacts ---"

Assert-FileContains "implementation-agent.md: reads mxagile-project.yaml" `
    $implAgentPath 'mxagile-project\.yaml'

Assert-FileContains "implementation-agent.md: loads source_mockup when ui_driven" `
    $implAgentPath 'source_mockup'

Assert-FileContains "implementation-agent.md: loads ui_inventory when ui_driven" `
    $implAgentPath 'ui_inventory'

Assert-FileContains "implementation-agent.md: loads layout_reference screenshot" `
    $implAgentPath 'layout_reference'

Assert-FileContains "implementation-agent.md: binding vs advisory distinction" `
    $implAgentPath 'BINDEND|bindend'

Assert-FileContains "implementation-agent.md: high fidelity section order binding" `
    $implAgentPath 'fidelity.*high|high.*fidelity'

Assert-FileContains "implementation-agent.md: navigation binding when ui_driven" `
    $implAgentPath 'Navigationsfluss.*JA|navigation.*bindend|navigation.*BINDEND'

Write-Host ""

# =========================================================================
# G. UI-Agent Analyze: typed navigation and interaction_states
# =========================================================================

Write-Host "--- G: UI-Agent Analyze captures typed navigation and interaction states ---"

Assert-FileContains "ui-agent.md: reads mxagile-project.yaml" `
    $uiAgentPath 'mxagile-project\.yaml'

Assert-FileContains "ui-agent.md: Analyze captures typed navigation" `
    $uiAgentPath 'navigation.*Array|Typisierte Navigation'

Assert-FileContains "ui-agent.md: Analyze captures interaction_states" `
    $uiAgentPath 'interaction_states|Interaction-States'

Assert-FileContains "ui-agent.md: Analyze saves layout_reference screenshot" `
    $uiAgentPath 'layout_reference'

Assert-FileContains "ui-agent.md: Analyze captures visual_priority for actions" `
    $uiAgentPath 'visual_priority'

Assert-FileContains "ui-agent.md: Mandatory when ui_driven and mockup found" `
    $uiAgentPath 'ui_driven.*true.*PFLICHT|PFLICHT.*ui_driven'

Write-Host ""

# =========================================================================
# H. UI-Agent Verify: reports ui_fidelity result
# =========================================================================

Write-Host "--- H: UI-Agent Verify reports ui_fidelity ---"

Assert-FileContains "ui-agent.md: Verify has semantic fidelity comparison" `
    $uiAgentPath 'Fidelity.*Pruefung|semantischen.*Vergleich|Seitenstruktur.*Gruppen'

Assert-FileContains "ui-agent.md: ui_fidelity result block in output" `
    $uiAgentPath 'ui_fidelity'

Assert-FileContains "ui-agent.md: fidelity result PASS/WARNING/FAIL" `
    $uiAgentPath '`PASS`|result: PASS'

Assert-FileContains "ui-agent.md: navigation checked in Verify" `
    $uiAgentPath 'Navigations-Pruefung'

Assert-FileContains "ui-agent.md: interaction states checked in Verify" `
    $uiAgentPath 'Interaction-State-Pruefung'

Assert-FileContains "ui-agent.md: material deviation definition" `
    $uiAgentPath 'material|Material'

Assert-FileNotContains "ui-agent.md: no pixel-diff or numerical scores" `
    $uiAgentPath 'pixel.*score|similarity.*percent|Pixel.*Schwellwert'

Write-Host ""

# =========================================================================
# I. page.schema.json: navigation and interaction_states
# =========================================================================

Write-Host "--- I: page.schema.json has navigation and interaction_states ---"

if (Test-Path -LiteralPath $pageSchemaPath) {
    $pageSchema = Get-Content -LiteralPath $pageSchemaPath -Raw
    Assert-True "page.schema.json: navigation array defined" `
        ($pageSchema -match '"navigation"') `
        "navigation array not in page schema"
    Assert-True "page.schema.json: navigation has action_id" `
        ($pageSchema -match 'action_id') `
        "action_id not in navigation schema"
    Assert-True "page.schema.json: navigation has leads_to_page" `
        ($pageSchema -match 'leads_to_page') `
        "leads_to_page not in navigation schema"
    Assert-True "page.schema.json: navigation has condition" `
        ($pageSchema -match 'condition') `
        "condition not in navigation schema"
    Assert-True "page.schema.json: interaction_states array defined" `
        ($pageSchema -match '"interaction_states"') `
        "interaction_states not in page schema"
    Assert-True "page.schema.json: interaction_states has state_id" `
        ($pageSchema -match 'state_id') `
        "state_id not in interaction_states schema"
    Assert-True "page.schema.json: layout_reference field defined" `
        ($pageSchema -match 'layout_reference') `
        "layout_reference not in page schema"
    Assert-True "page.schema.json: visual_priority on actions" `
        ($pageSchema -match 'visual_priority') `
        "visual_priority not in action schema"
} else {
    Assert-True "page.schema.json exists" $false "page.schema.json not found: $pageSchemaPath"
}

Write-Host ""

# =========================================================================
# J. mxagile-init.ps1: creates input-resources scaffold
# =========================================================================

Write-Host "--- J: mxagile-init.ps1 creates input-resources scaffold ---"

Assert-FileContains "mxagile-init.ps1: creates input-resources directory" `
    $initScriptPath 'input-resources'

Assert-FileContains "mxagile-init.ps1: creates ui-ux subdirectory" `
    $initScriptPath 'ui-ux'

Assert-FileContains "mxagile-init.ps1: creates input-resources README.md" `
    $initScriptPath 'InputReadme|input-resources.*README'

Assert-FileContains "mxagile-init.ps1: creates ui-ux README.md" `
    $initScriptPath 'UiUxReadme|ui-ux.*README'

Assert-FileContains "mxagile-init.ps1: preserves existing user content" `
    $initScriptPath 'preserving|exists.*skipping|not.*Test-Path'

Assert-FileContains "mxagile-init.ps1: creates mxagile-project.yaml" `
    $initScriptPath 'mxagile-project\.yaml'

Assert-FileContains "mxagile-init.ps1: mxagile-project.yaml idempotent" `
    $initScriptPath 'ProjectConfig.*exists.*preserving|preserving.*ProjectConfig'

Write-Host ""

# =========================================================================
# K. Project without mockup — no forced fidelity gate
# =========================================================================

Write-Host "--- K: No forced fidelity gate when mockup absent ---"

Assert-FileContains "gate-to-refinement.md: UI-Inventar conditional on mockups" `
    $gateRefinePath 'wenn Mockups.*vorhanden|existieren\)'

Assert-FileContains "discovery.md: no mockup is not a blocker" `
    $discoverySkillPath 'falls vorhanden|wenn.*Mockup|ohne.*Mockup|kein.*Blocker'

Assert-FileContains "ui-agent.md: Analyze only when mockup present" `
    $uiAgentPath 'Mockup.*vorhanden|vorhanden.*Mockup'

Write-Host ""

# =========================================================================
# L. Input-resources README files
# =========================================================================

Write-Host "--- L: Input-resources README files exist ---"

$inputReadmePath  = Join-Path $ScriptDir "input-resources\README.md"
$uiUxReadmePath   = Join-Path $ScriptDir "input-resources\ui-ux\README.md"

Assert-True "input-resources/README.md exists" `
    (Test-Path -LiteralPath $inputReadmePath) `
    "File not found: $inputReadmePath"

Assert-True "input-resources/ui-ux/README.md exists" `
    (Test-Path -LiteralPath $uiUxReadmePath) `
    "File not found: $uiUxReadmePath"

if (Test-Path -LiteralPath $uiUxReadmePath) {
    $uiUxContent = Get-Content -LiteralPath $uiUxReadmePath -Raw
    Assert-True "ui-ux/README.md: explains what belongs here" `
        ($uiUxContent -match '\.html|Mockup') `
        "ui-ux README must mention HTML mockups"
    Assert-True "ui-ux/README.md: explains what does NOT belong here" `
        ($uiUxContent -match 'NICHT|nicht.*abgelegt') `
        "ui-ux README must explain what not to store here"
}

Write-Host ""

# =========================================================================
# Final summary
# =========================================================================

Write-Host "=== UI-Driven Contract Test Results ==="
Write-Host "  PASS: $PassCount" -ForegroundColor Green
if ($FailCount -gt 0) {
    Write-Host "  FAIL: $FailCount" -ForegroundColor Red
    foreach ($detail in $FailDetails) {
        Write-Host "    $detail" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "TEST FAILED: UI-Driven Contract is missing or inconsistent." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "TEST PASSED: UI-Driven Contract is consistently defined across all framework files." -ForegroundColor Green
    exit 0
}
