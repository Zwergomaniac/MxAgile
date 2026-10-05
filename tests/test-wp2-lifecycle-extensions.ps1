#Requires -Version 7
# MxAgile WP2 Lifecycle Extensions — Tier 0 static validation
# Validates: schemas, policies, skills, agent extensions, lifecycle gates, adapter registrations.
# Run from repository root:  pwsh tests/test-wp2-lifecycle-extensions.ps1

param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

function Assert {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
        $script:pass++
    } else {
        $msg = if ($Detail) { "  FAIL  $Label — $Detail" } else { "  FAIL  $Label" }
        Write-Host $msg -ForegroundColor Red
        $script:fail++
    }
}

function FileContent { param([string]$Path)
    if (Test-Path $Path) { return Get-Content $Path -Raw -Encoding UTF8 }
    return ''
}

Write-Host "`nMxAgile WP2 Lifecycle Extensions Validation — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] Required new artifacts exist
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] Required WP2 artifacts exist"
$required = @(
    '.mxagile/schemas/test-contract.schema.json',
    '.mxagile/schemas/verification-plan.schema.json',
    '.mxagile/policies/design-contract-intake.md',
    '.mxagile/policies/test-contract-derivation.md',
    '.mxagile/policies/verification-layers.md',
    '.mxagile/policies/autonomous-remediation.md',
    '.mxagile/policies/test-staleness.md',
    '.mxagile/policies/acceptance-campaign.md',
    '.mxagile/policies/test-defect-protection.md',
    '.mxagile/skills/test-contract.md',
    '.mxagile/skills/verification-plan.md',
    '.mxagile/skills/test-generate.md'
)
foreach ($rel in $required) {
    Assert (Test-Path (Join-Path $RepoRoot $rel)) "Exists: $rel"
}

# ──────────────────────────────────────────────────────────────
# [2] Test Contract schema structural validation
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] Test Contract schema structure"
$tcSchema = Join-Path $RepoRoot '.mxagile/schemas/test-contract.schema.json'
if (Test-Path $tcSchema) {
    try {
        $tc = Get-Content $tcSchema -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert $true 'test-contract.schema.json parses as valid JSON'
        Assert ($tc.title -match 'Test Contract') 'schema title contains Test Contract'
        Assert ($null -ne $tc.properties.ID) 'schema has ID property'
        Assert ($null -ne $tc.properties.status) 'schema has status property'
        Assert ($null -ne $tc.properties.requirement_ids) 'schema has requirement_ids property'
        Assert ($null -ne $tc.properties.proof_points) 'schema has proof_points property'
        Assert ($null -ne $tc.definitions.proof_point) 'schema defines proof_point'
        Assert ($null -ne $tc.definitions.proof_point.properties.claim) 'proof_point has claim'
        Assert ($null -ne $tc.definitions.proof_point.properties.role) 'proof_point has role'
        Assert ($null -ne $tc.definitions.proof_point.properties.required_layers) 'proof_point has required_layers'
        Assert ($null -ne $tc.definitions.proof_point.properties.security_dimensions) 'proof_point has security_dimensions'
        # Operation-aware capability fields (Correction 2)
        Assert ($null -ne $tc.definitions.proof_point.properties.operation) 'proof_point has operation field'
        Assert ($null -ne $tc.definitions.proof_point.properties.authorization_disposition) 'proof_point has authorization_disposition'
        $authEnum = $tc.definitions.proof_point.properties.authorization_disposition.enum
        Assert ($authEnum -contains 'REQUIRED') 'authorization_disposition contains REQUIRED'
        Assert ($authEnum -contains 'EXPLICITLY_FORBIDDEN') 'authorization_disposition contains EXPLICITLY_FORBIDDEN'
        Assert ($authEnum -contains 'UNSPECIFIED') 'authorization_disposition contains UNSPECIFIED'
        Assert ($authEnum -contains 'UNKNOWN') 'authorization_disposition contains UNKNOWN'
        # Status enum
        $statusEnum = $tc.properties.status.enum
        Assert ($statusEnum -contains 'stale') 'status enum contains stale'
        Assert ($statusEnum -contains 'impacted') 'status enum contains impacted'
        Assert ($statusEnum -contains 'active') 'status enum contains active'
        # Layers
        $layerEnum = $tc.definitions.proof_point.properties.required_layers.items.enum
        Assert ($layerEnum -contains 'BUILD') "required_layers enum contains BUILD"
        Assert ($layerEnum -contains 'FRONTEND') "required_layers enum contains FRONTEND"
        Assert ($layerEnum -contains 'MODEL') "required_layers enum contains MODEL"
        # Security dimensions
        $dimEnum = $tc.definitions.proof_point.properties.security_dimensions.items.enum
        Assert ($dimEnum -contains 'VISIBILITY') 'security_dimensions contains VISIBILITY'
        Assert ($dimEnum -contains 'ACCESSIBILITY') 'security_dimensions contains ACCESSIBILITY'
        Assert ($dimEnum -contains 'AUTHORIZATION') 'security_dimensions contains AUTHORIZATION'
        Assert ($dimEnum -contains 'DATA_SCOPE') 'security_dimensions contains DATA_SCOPE'
        # Remediation states
        $remEnum = $tc.definitions.proof_point.properties.remediation_state.enum
        Assert ($remEnum -contains 'REQUIRED_BUT_UNAVAILABLE') 'remediation_state has REQUIRED_BUT_UNAVAILABLE'
        Assert ($remEnum -contains 'EXPLICITLY_FORBIDDEN_BUT_AVAILABLE') 'remediation_state has EXPLICITLY_FORBIDDEN_BUT_AVAILABLE'
        Assert ($remEnum -contains 'UNSPECIFIED_BUT_AVAILABLE') 'remediation_state has UNSPECIFIED_BUT_AVAILABLE'
        Assert ($remEnum -contains 'BUSINESS_EXPECTATION_UNKNOWN') 'remediation_state has BUSINESS_EXPECTATION_UNKNOWN'
    } catch {
        Assert $false 'test-contract.schema.json parses as valid JSON' "$_"
    }
}

# ──────────────────────────────────────────────────────────────
# [3] Verification Plan schema structural validation
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] Verification Plan schema structure"
$vplSchema = Join-Path $RepoRoot '.mxagile/schemas/verification-plan.schema.json'
if (Test-Path $vplSchema) {
    try {
        $vpl = Get-Content $vplSchema -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        Assert $true 'verification-plan.schema.json parses as valid JSON'
        Assert ($vpl.title -match 'Verification Plan') 'schema title contains Verification Plan'
        Assert ($null -ne $vpl.properties.ID) 'schema has ID property'
        Assert ($null -ne $vpl.properties.test_contract_id) 'schema has test_contract_id'
        Assert ($null -ne $vpl.properties.wave_id) 'schema has wave_id'
        Assert ($null -ne $vpl.properties.layer_assignments) 'schema has layer_assignments'
        Assert ($null -ne $vpl.definitions.layer_assignment) 'defines layer_assignment'
        Assert ($null -ne $vpl.definitions.layer_assignment.properties.layer_decisions) 'layer_assignment has layer_decisions'
        Assert ($vpl.properties.ID.pattern -match 'VPL') 'ID pattern contains VPL'
        $campEnum = $vpl.definitions.layer_assignment.properties.campaign_type.enum
        Assert ($campEnum -contains 'REQUIREMENT') 'campaign_type contains REQUIREMENT'
        Assert ($campEnum -contains 'ROLE') 'campaign_type contains ROLE'
        Assert ($campEnum -contains 'RISK_CHANGE_IMPACT') 'campaign_type contains RISK_CHANGE_IMPACT'
    } catch {
        Assert $false 'verification-plan.schema.json parses as valid JSON' "$_"
    }
}

# ──────────────────────────────────────────────────────────────
# [4] Policy: design-contract-intake.md
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] Policy: design-contract-intake.md"
$dcIntake = FileContent (Join-Path $RepoRoot '.mxagile/policies/design-contract-intake.md')
Assert ($dcIntake -match 'mocketeer-spec') 'references mocketeer-spec script block'
Assert ($dcIntake -match 'Source Rank 1\.5') 'defines Source Rank 1.5'
Assert ($dcIntake -match 'CONFIRMED_BY_SOURCE') 'maps CONFIRMED_BY_SOURCE status'
Assert ($dcIntake -match 'ASSUMPTION_REQUIRES_APPROVAL') 'maps ASSUMPTION_REQUIRES_APPROVAL'
Assert ($dcIntake -match 'cannot\[\]') 'handles cannot[] negative permissions'
Assert ($dcIntake -match 'design_contract_provenance') 'specifies design_contract_provenance recording'
Assert ($dcIntake -match 'Read-only') 'states mockup is read-only during intake'
# Correction 2: operation-aware intake
Assert ($dcIntake -match 'Operation-Level|operation.*level|CANNOT UPDATE.*CANNOT READ|CAN READ.*CAN UPDATE' -or
        $dcIntake -match 'Inference prohibition|inference.*prohibited') `
    'states operation inference prohibition'
Assert ($dcIntake -match 'EXPLICITLY_FORBIDDEN') 'maps cannot[] to EXPLICITLY_FORBIDDEN disposition'
Assert ($dcIntake -match 'UNSPECIFIED') 'maps not-mentioned to UNSPECIFIED (not FORBIDDEN)'

# ──────────────────────────────────────────────────────────────
# [5] Policy: verification-layers.md — all five layers + four dimensions
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] Policy: verification-layers.md — layer + dimension definitions"
$vl = FileContent (Join-Path $RepoRoot '.mxagile/policies/verification-layers.md')
Assert ($vl -match 'STATIC') 'defines STATIC layer'
Assert ($vl -match 'MODEL') 'defines MODEL layer'
Assert ($vl -match 'BUILD') 'defines BUILD layer'
Assert ($vl -match 'RUNTIME') 'defines RUNTIME layer'
Assert ($vl -match 'FRONTEND') 'defines FRONTEND layer'
Assert ($vl -match 'VISIBILITY') 'defines VISIBILITY dimension'
Assert ($vl -match 'ACCESSIBILITY') 'defines ACCESSIBILITY dimension'
Assert ($vl -match 'AUTHORIZATION') 'defines AUTHORIZATION dimension'
Assert ($vl -match 'DATA_SCOPE') 'defines DATA_SCOPE dimension'
$dimCount = @('VISIBILITY','ACCESSIBILITY','AUTHORIZATION','DATA_SCOPE') |
    Where-Object { $vl -match $_ } | Measure-Object | Select-Object -ExpandProperty Count
Assert ($dimCount -eq 4) "all four security dimensions appear in document ($dimCount found)"
Assert ($vl -match 'Dimension.*Layer Mapping' -or $vl -match 'Dimension.*×.*Layer') 'includes dimension-layer mapping table'
# Correction 4: BUILD defined semantically, not via hypothetical command
Assert ($vl -notmatch 'mxcli build-validation') 'BUILD definition does not reference hypothetical mxcli build-validation command'
Assert ($vl -match 'execution.*adapter|adapter.*execution|toolchain' -or $vl -match 'INFRASTRUCTURE_UNAVAILABLE') `
    'BUILD notes environment-dependent toolchain'

# ──────────────────────────────────────────────────────────────
# [6] Policy: autonomous-remediation.md — corrected state semantics
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] Policy: autonomous-remediation.md — corrected remediation states"
$ar = FileContent (Join-Path $RepoRoot '.mxagile/policies/autonomous-remediation.md')
Assert ($ar -match 'REQUIRED_BUT_UNAVAILABLE') 'defines REQUIRED_BUT_UNAVAILABLE'
Assert ($ar -match 'EXPLICITLY_FORBIDDEN_BUT_AVAILABLE') 'defines EXPLICITLY_FORBIDDEN_BUT_AVAILABLE'
Assert ($ar -match 'UNSPECIFIED_BUT_AVAILABLE') 'defines UNSPECIFIED_BUT_AVAILABLE'
Assert ($ar -match 'BUSINESS_EXPECTATION_UNKNOWN') 'defines BUSINESS_EXPECTATION_UNKNOWN'
Assert ($ar -match 'DECISION_REQUIRED') 'references DECISION_REQUIRED escalation'
# Correction 1: EXPLICITLY_FORBIDDEN_BUT_AVAILABLE is now auto-remediable when unambiguous
Assert ($ar -match 'EXPLICITLY_FORBIDDEN_BUT_AVAILABLE.*PERMITTED|Permitted.*EXPLICITLY_FORBIDDEN' -or
        ($ar -match 'EXPLICITLY_FORBIDDEN_BUT_AVAILABLE' -and $ar -match 'PERMITTED')) `
    'EXPLICITLY_FORBIDDEN_BUT_AVAILABLE allows auto-remediation when unambiguous'
# UNSPECIFIED and UNKNOWN must still be PROHIBITED
Assert ($ar -match 'UNSPECIFIED.*PROHIBITED|PROHIBITED.*UNSPECIFIED' -or
        ($ar -match 'UNSPECIFIED_BUT_AVAILABLE' -and $ar -match 'PROHIBITED')) `
    'UNSPECIFIED_BUT_AVAILABLE is PROHIBITED for auto-remediation'
Assert ($ar -match 'BUSINESS_EXPECTATION_UNKNOWN.*PROHIBITED|PROHIBITED.*BUSINESS_EXPECTATION_UNKNOWN' -or
        ($ar -match 'BUSINESS_EXPECTATION_UNKNOWN' -and $ar -match 'PROHIBITED')) `
    'BUSINESS_EXPECTATION_UNKNOWN is PROHIBITED for auto-remediation'
# Security alone does NOT require extra decision when expectation is explicit
Assert ($ar -match 'Security relevance alone|security.*alone') `
    'states security relevance alone does not require extra decision'

# ──────────────────────────────────────────────────────────────
# [7] Policy: test-staleness.md — three statuses
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] Policy: test-staleness.md — staleness states"
$ts = FileContent (Join-Path $RepoRoot '.mxagile/policies/test-staleness.md')
Assert ($ts -match 'CURRENT') 'defines CURRENT status'
Assert ($ts -match 'STALE') 'defines STALE status'
Assert ($ts -match 'IMPACTED') 'defines IMPACTED status'
Assert ($ts -match 'Non-Deletion Rule|MUST NOT') 'includes preservation rule'

# ──────────────────────────────────────────────────────────────
# [8] Policy: acceptance-campaign.md — corrected ROLE campaign gating
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] Policy: acceptance-campaign.md — campaign types + ROLE trigger"
$ac = FileContent (Join-Path $RepoRoot '.mxagile/policies/acceptance-campaign.md')
Assert ($ac -match 'REQUIREMENT Campaign|REQUIREMENT') 'defines REQUIREMENT campaign'
Assert ($ac -match 'ROLE Campaign|ROLE') 'defines ROLE campaign'
Assert ($ac -match 'RISK_CHANGE_IMPACT') 'defines RISK_CHANGE_IMPACT campaign'
Assert ($ac -match 'acceptance_gate|acceptance-gate') 'references acceptance gate'
Assert ($ac -match 'campaign_type|campaign-type') 'defines campaign type schema'
# Correction 6: ROLE campaign requires explicit trigger
Assert ($ac -match 'Trigger|trigger|triggered|ONLY when') 'ROLE campaign requires explicit trigger'
Assert ($ac -match 'must NOT automatically|not.*automatically|small.*change.*NOT') `
    'states small change must not auto-trigger ROLE campaign'
Assert ($ac -match 'Evidence reuse|evidence.*reuse|reuse.*CURRENT') `
    'states evidence may be reused when CURRENT'

# ──────────────────────────────────────────────────────────────
# [9] Policy: test-defect-protection.md — three classes + technical repair
# ──────────────────────────────────────────────────────────────
Write-Host "`n[9] Policy: test-defect-protection.md — defect classes + technical repair"
$tdp = FileContent (Join-Path $RepoRoot '.mxagile/policies/test-defect-protection.md')
Assert ($tdp -match 'APPLICATION_DEFECT') 'defines APPLICATION_DEFECT'
Assert ($tdp -match 'TEST_DEFECT') 'defines TEST_DEFECT'
Assert ($tdp -match 'TEST_INFRASTRUCTURE_GAP') 'defines TEST_INFRASTRUCTURE_GAP'
Assert ($tdp -match 'mandatory') 'states classification is mandatory'
Assert ($tdp -match 'BUSINESS_EXPECTATION_UNKNOWN') 'cross-references BUSINESS_EXPECTATION_UNKNOWN'
# Correction 8: technical test repair vs canonical change
Assert ($tdp -match 'TECHNICAL_TEST_DEFECT|technical.*test.*defect|locator.*stale|stale.*locator') `
    'distinguishes technical test defect from canonical expectation change'
Assert ($tdp -match 'repair|regenerat') 'allows repair/regeneration of technical test without DECISION_REQUIRED'
Assert ($tdp -match 'canonical.*expectation|canonical.*claim|canonical.*Test Contract') `
    'requires DECISION_REQUIRED only for canonical expectation changes'

# ──────────────────────────────────────────────────────────────
# [10] evidence-levels.md: BUILD layer present + corrected
# ──────────────────────────────────────────────────────────────
Write-Host "`n[10] evidence-levels.md: BUILD layer present and correctly defined"
$el = FileContent (Join-Path $RepoRoot '.mxagile/policies/evidence-levels.md')
Assert ($el -match 'BUILD') 'BUILD level defined'
Assert ($el -match 'LEVEL 2\.5') 'BUILD is Level 2.5'
Assert ($el -match 'testability.gate|testability gate') 'testability gate row in evidence table'
Assert ($el -match 'acceptance.gate') 'acceptance gate row in evidence table'
Assert ($el -notmatch 'mxcli build-validation') 'does not reference hypothetical mxcli build-validation'
Assert ($el -match 'NOT equivalent to BUILD|not.*BUILD|mxcli check.*NOT') 'states mxcli check alone is not BUILD'

# ──────────────────────────────────────────────────────────────
# [11] gate-to-ready.md: Testability Gate (TC only, no VPL requirement)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[11] gate-to-ready.md: Testability Gate section"
$gtr = FileContent (Join-Path $RepoRoot '.mxagile/skills/gate-to-ready.md')
Assert ($gtr -match 'Testability Gate') 'Testability Gate section present'
Assert ($gtr -match 'TC-NNN') 'references TC-NNN test contract IDs'
Assert ($gtr -match 'NOT_APPLICABLE') 'defines NOT_APPLICABLE deferral'
Assert ($gtr -match 'MANUAL_ONLY') 'defines MANUAL_ONLY deferral'
Assert ($gtr -match 'testability_gate') 'references testability_gate in process-state'
# Correction 3: VPL not required at gate-to-ready
Assert ($gtr -match 'VPL.*NOT required|Verification Plan.*NOT required|not.*required.*VPL' -or
        $gtr -match 'NOT required.*VPL|NOT required here') `
    'states VPL is not required at gate-to-ready'

# ──────────────────────────────────────────────────────────────
# [12] acceptance-agent.md: WP2 + corrections
# ──────────────────────────────────────────────────────────────
Write-Host "`n[12] acceptance-agent.md: WP2 structure + corrections"
$aa = FileContent (Join-Path $RepoRoot '.mxagile/agents/acceptance-agent.md')
Assert ($aa -match 'REQUIREMENT Campaign|REQUIREMENT campaigns') 'runs REQUIREMENT campaigns'
Assert ($aa -match 'ROLE Campaign|ROLE campaigns') 'runs ROLE campaigns'
Assert ($aa -match 'RISK_CHANGE_IMPACT') 'runs RISK_CHANGE_IMPACT campaigns'
Assert ($aa -match 'APPLICATION_DEFECT') 'knows APPLICATION_DEFECT'
Assert ($aa -match 'TEST_DEFECT') 'knows TEST_DEFECT'
Assert ($aa -match 'DECISION_REQUIRED') 'raises DECISION_REQUIRED'
Assert ($aa -match 'remediation_state|Autonomous Remediation') 'applies autonomous remediation policy'
Assert ($aa -match 'acceptance.gate|acceptance_gate') 'writes acceptance gate result'
Assert ($aa -match 'staleness|Staleness') 'checks for staleness'
# Correction 3: VPL creation at Verifying entry
Assert ($aa -match 'VPL.*creation|verification.*plan.*creat|skills/verification-plan') `
    'creates VPL at Verifying entry (not during Refinement)'
# Correction 6: ROLE campaign is triggered only
Assert ($aa -match 'Triggered Only|triggered.*only|trigger.*condition|ONLY when triggered') `
    'ROLE campaign is triggered only'
# Correction 9: Resume semantics — verify CURRENT before reuse
Assert ($aa -match 'Resume Semantics|reuse.*rules|CURRENT.*reuse|verify.*CURRENT') `
    'has resume semantics with CURRENT verification'
Assert ($aa -match 'all.*following.*verified|verified.*before.*reuse|verify.*before.*reuse') `
    'states evidence must be verified before reuse'
# Correction 5: locator strategy
Assert ($aa -match 'getByRole|accessible.*role|locator.*prefer') `
    'uses accessible locator strategy (not just mx-name)'

# ──────────────────────────────────────────────────────────────
# [13] discovery-agent.md: Design Contract intake + operation awareness
# ──────────────────────────────────────────────────────────────
Write-Host "`n[13] discovery-agent.md: Design Contract intake"
$da = FileContent (Join-Path $RepoRoot '.mxagile/agents/discovery-agent.md')
Assert ($da -match 'design-contract-intake') 'references design-contract-intake policy'
Assert ($da -match 'mocketeer-spec') 'references mocketeer-spec detection'
Assert ($da -match 'cannot\[\]') 'handles cannot[] from Design Contract'
Assert ($da -match 'test_contract_signal') 'emits test_contract_signal for Refinement'
Assert ($da -match 'BUILD') 'references BUILD evidence level'

# ──────────────────────────────────────────────────────────────
# [14] lifecycle.yaml: WP2 extensions + VPL timing correction
# ──────────────────────────────────────────────────────────────
Write-Host "`n[14] lifecycle.yaml: WP2 extensions + VPL timing"
$lc = FileContent (Join-Path $RepoRoot '.mxagile/lifecycle.yaml')
Assert ($lc -match 'testability_gate') 'testability_gate in state_tracking'
Assert ($lc -match 'acceptance_gate') 'acceptance_gate in state_tracking'
Assert ($lc -match 'test-contract') 'lifecycle references test-contract skill'
Assert ($lc -match 'Test Contracts') 'verifying phase mentions Test Contracts'
Assert ($lc -match 'Verification Plans') 'verifying phase mentions Verification Plans'
Assert ($lc -match 'acceptance-campaigns') 'verifying outputs include acceptance-campaigns'
Assert ($lc -match 'design_contract_changed') 'change_propagation includes design_contract_changed'
Assert ($lc -match 'acceptance_defect_application') 'change_propagation includes APPLICATION_DEFECT routing'
# Correction 3: VPL in verifying sub-steps, not in refinement outputs
Assert ($lc -match 'verification_plan_creation') 'VPL creation is a verifying sub-step'
Assert ($lc -match 'Verification Plans.*Verifying|verification-plan.*Verifying|VPL.*after' -or
        $lc -match 'Verification Plan.*Verifying entry') `
    'VPL is produced at Verifying entry (after implementation)'
# VPL must NOT be listed as a refinement output
$refinementSection = if ($lc -match '(?s)refinement:.*?next: \[ready\]') { $Matches[0] } else { '' }
Assert ($refinementSection -notmatch 'verification-plans.*VPL|VPL-NNN\.yaml.*Verification Plan output') `
    'Refinement does not list VPL as a committed output'

# ──────────────────────────────────────────────────────────────
# [15] skills.yaml adapter: WP2 skills registered
# ──────────────────────────────────────────────────────────────
Write-Host "`n[15] skills.yaml adapter: WP2 skills registered"
$sy = FileContent (Join-Path $RepoRoot '.mxagile/adapters/claude/skills.yaml')
Assert ($sy -match 'test-contract') 'test-contract skill registered'
Assert ($sy -match 'verification-plan') 'verification-plan skill registered'
Assert ($sy -match 'test-generate') 'test-generate skill registered'

# ──────────────────────────────────────────────────────────────
# [16] Skill content checks (including corrections)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[16] Skill content checks"
$tcSkill = FileContent (Join-Path $RepoRoot '.mxagile/skills/test-contract.md')
Assert ($tcSkill -match 'TC-NNN') 'test-contract skill uses TC-NNN IDs'
Assert ($tcSkill -match 'PP-[0-9]|PP-NNN') 'test-contract skill uses PP-NNN IDs'
Assert ($tcSkill -match 'test-staleness|staleness') 'test-contract skill references staleness policy'
Assert ($tcSkill -match 'Testability Classification') 'test-contract skill classifies testability'

$vplSkill = FileContent (Join-Path $RepoRoot '.mxagile/skills/verification-plan.md')
Assert ($vplSkill -match 'VPL-NNN') 'verification-plan skill uses VPL-NNN IDs'
Assert ($vplSkill -match 'INFRASTRUCTURE_UNAVAILABLE') 'verification-plan skill handles unavailable layers'
# Correction 3: VPL timing
Assert ($vplSkill -match 'Verifying.*entry|after.*implementation|post-implementation') `
    'verification-plan skill runs at Verifying entry (post-implementation)'
# Correction 7: Principled regression candidates
Assert ($vplSkill -match 'Do NOT.*auto|not.*auto.*promot|principled') `
    'verification-plan skill uses principled regression promotion'
Assert ($vplSkill -match 'Generated.*permanent|generated.*distinct.*permanent|permanent regression') `
    'skill distinguishes generated tests from permanent regression'

$tgSkill = FileContent (Join-Path $RepoRoot '.mxagile/skills/test-generate.md')
Assert ($tgSkill -match 'inspect:') 'test-generate skill produces inspect blocks'
Assert ($tgSkill -match 'playwright:') 'test-generate skill produces Playwright steps'
# Correction 5: Playwright locator strategy
Assert ($tgSkill -match 'getByRole|accessible.*role|getByLabel') 'test-generate uses accessible locators'
Assert ($tgSkill -match 'mx-name.*fallback|fallback.*mx-name') 'mx-name is fallback not default'
Assert ($tgSkill -match 'Locator preference|preference.*order') 'skill defines locator preference order'
# Correction 4: BUILD uses execution_adapter not specific command
Assert ($tgSkill -match 'execution_adapter|toolchain|build.*semantic') `
    'BUILD layer uses semantic/adapter approach (not hard-coded command)'
# Correction 8: TECHNICAL_TEST_DEFECT repair
Assert ($tgSkill -match 'TECHNICAL_TEST_DEFECT|regenerat|repair') `
    'test-generate supports regeneration on TECHNICAL_TEST_DEFECT'

# ──────────────────────────────────────────────────────────────
# [17] Derivation policy: operation-level rules
# ──────────────────────────────────────────────────────────────
Write-Host "`n[17] test-contract-derivation.md: operation-level rules"
$tcd = FileContent (Join-Path $RepoRoot '.mxagile/policies/test-contract-derivation.md')
Assert ($tcd -match 'Operation-Level|Operation.*Proof|operation.*level') 'defines operation-level proof points'
Assert ($tcd -match 'READ') 'mentions READ operation'
Assert ($tcd -match 'CREATE') 'mentions CREATE operation'
Assert ($tcd -match 'UPDATE') 'mentions UPDATE operation'
Assert ($tcd -match 'DELETE') 'mentions DELETE operation'
Assert ($tcd -match 'EXECUTE') 'mentions EXECUTE operation'
Assert ($tcd -match 'Inference Prohibition|inference.*prohibit|CANNOT UPDATE.*CANNOT READ' -or
        $tcd -match 'CAN READ.*CAN UPDATE') 'states operation inference prohibition'
Assert ($tcd -match 'independently.*derived|derived.*independently') `
    'each operation must be independently derived'

# ──────────────────────────────────────────────────────────────
# [18] WP3 — Maturity intake: design-contract-intake.md extensions
# ──────────────────────────────────────────────────────────────
Write-Host "`n[18] WP3 — Maturity intake: design-contract-intake.md"
$dci = FileContent (Join-Path $RepoRoot '.mxagile/policies/design-contract-intake.md')

# Readiness mapping table
Assert ($dci -match 'HANDOFF_READY') 'intake maps HANDOFF_READY readiness value'
Assert ($dci -match 'REFINEMENT_REQUIRED') 'intake maps REFINEMENT_REQUIRED readiness value'
Assert ($dci -match 'PROTOTYPE_READY') 'intake maps PROTOTYPE_READY readiness value'
Assert ($dci -match 'BLOCKED') 'intake maps BLOCKED readiness value'

# HANDOFF_READY does not bypass MxAgile gates
Assert ($dci -match 'not.*bypass|bypass.*not|gates remain authoritative') `
    'HANDOFF_READY does not bypass MxAgile lifecycle gates'

# Legacy / absent assessment
Assert ($dci -match 'absent.*legacy|legacy.*unassessed|without.*assessment|legacy.*intact') `
    'intake handles legacy contracts without assessment block'
Assert ($dci -match 'Do not.*infer HANDOFF_READY|not.*infer.*HANDOFF_READY') `
    'intake does not infer HANDOFF_READY from missing assessment'

# Gap mapping
Assert ($dci -match 'Gap Mapping|gap.*mapping') 'intake defines gap mapping to MxAgile concepts'
Assert ($dci -match 'MISSING_BUSINESS_RULE') 'maps MISSING_BUSINESS_RULE gap category'
Assert ($dci -match 'SECURITY_UNCLEAR') 'maps SECURITY_UNCLEAR gap category'
Assert ($dci -match 'INCOMPLETE_DATA_SCOPE') 'maps INCOMPLETE_DATA_SCOPE gap category'
Assert ($dci -match 'UNTESTABLE_REQUIREMENT') 'maps UNTESTABLE_REQUIREMENT gap category'
Assert ($dci -match 'gap_ref') 'preserves gap_ref provenance in routing'
Assert ($dci -match 'visual.*cosmetic|cosmetic.*not.*block|minor.*visual') `
    'minor visual gaps do not automatically block Testability Gate'

# Dimension intake
Assert ($dci -match 'BLOCKED.*DECISION_REQUIRED|dimension.*BLOCKED') 'BLOCKED dimension triggers DECISION_REQUIRED'
Assert ($dci -match 'UNEXPLORED.*open question|open question.*UNEXPLORED') 'UNEXPLORED dimension recorded as open question'

# Provenance extension
Assert ($dci -match 'maturity_assessed') 'provenance extended with maturity_assessed field'
Assert ($dci -match 'blocking_gaps') 'provenance records blocking_gaps'
Assert ($dci -match 'prototype_readiness.*provenance|provenance.*prototype_readiness') `
    'provenance records prototype_readiness value'

# Reconciliation on later revision
Assert ($dci -match 'Reconciliation|reconcil') 'intake defines reconciliation on later revision'
Assert ($dci -match 'test-staleness|IMPACTED') 'reconciliation marks IMPACTED per staleness policy'
Assert ($dci -match 'unrelated.*not.*reset|not.*reset.*unrelated') 'reconciliation does not reset unrelated work'

# ──────────────────────────────────────────────────────────────
# [19] WP3 — HANDOFF_READY intake does not bypass gates
# ──────────────────────────────────────────────────────────────
Write-Host "`n[19] WP3 — HANDOFF_READY does not bypass MxAgile gates"
$dciContent = FileContent (Join-Path $RepoRoot '.mxagile/policies/design-contract-intake.md')
$mhContent  = FileContent (Join-Path $RepoRoot 'products/MxMocketeer/knowledge/mxagile-handoff.txt')

Assert ($dciContent -match 'does NOT bypass|not bypass.*gate|gates remain') `
    'design-contract-intake: HANDOFF_READY does not bypass gates'
Assert ($mhContent -match 'gates remain authoritative|not bypass.*gate|does NOT bypass') `
    'mxagile-handoff.txt: gates remain authoritative'

# ──────────────────────────────────────────────────────────────
# [20] No company-specific content in WP2/WP3 files
# ──────────────────────────────────────────────────────────────
Write-Host "`n[20] No company-specific content in WP2/WP3 files"
$banned = @('Mercedes', 'mercedes', 'Daimler', 'daimler', 'MBUI', 'MB_UI', 'MB_SSO', 'MBTech',
            'CapTrack', 'KidsCompass', 'mbrepo', 'mercedes-benz')
$wp2Files = @(
    '.mxagile/schemas/test-contract.schema.json',
    '.mxagile/schemas/verification-plan.schema.json',
    '.mxagile/policies/design-contract-intake.md',
    '.mxagile/policies/test-contract-derivation.md',
    '.mxagile/policies/verification-layers.md',
    '.mxagile/policies/autonomous-remediation.md',
    '.mxagile/policies/test-staleness.md',
    '.mxagile/policies/acceptance-campaign.md',
    '.mxagile/policies/test-defect-protection.md',
    '.mxagile/skills/test-contract.md',
    '.mxagile/skills/verification-plan.md',
    '.mxagile/skills/test-generate.md'
) | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ }
foreach ($term in $banned) {
    $hits = $wp2Files | Where-Object {
        (Get-Content $_ -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) -match [regex]::Escape($term)
    } | ForEach-Object { Split-Path $_ -Leaf }
    Assert ($hits.Count -eq 0) "No '$term' in WP2 policy/schema/skill files" ($hits -join ', ')
}

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all WP2 checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — WP2 validation failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
