#Requires -Version 7
# MxAgile Revision Lifecycle & GAP Verification — Tier 0 static validation
# Covers WP-02 through WP-21: revision model, effects, role coverage,
# platform boundaries, gap policy, quality gates, templates, contract migration.
# Run from repository root:  pwsh tests/test-revision-lifecycle.ps1

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

function ReadFile { param([string]$Path)
    if (Test-Path -LiteralPath $Path) { [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8) }
    else { '' }
}

function ParseJSON { param([string]$Path)
    $raw = ReadFile $Path
    if (-not $raw) { return $null }
    try { ConvertFrom-Json -InputObject $raw -Depth 20 -ErrorAction Stop }
    catch { $null }
}

Write-Host "`nMxAgile Revision Lifecycle Validation — $RepoRoot" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────
# [1] New canonical schema files exist (WP-11, WP-09, WP-10)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[1] New canonical schema files exist"
$newSchemas = @(
    '.mxagile/schemas/decision.schema.json',
    '.mxagile/schemas/platform_boundaries.schema.json',
    '.mxagile/schemas/role_coverage.schema.json'
)
foreach ($s in $newSchemas) {
    Assert (Test-Path (Join-Path $RepoRoot $s)) "Schema exists: $s"
}

# ──────────────────────────────────────────────────────────────
# [2] decision.schema.json structural validation (WP-11)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[2] decision.schema.json structure"
$dec = ParseJSON (Join-Path $RepoRoot '.mxagile/schemas/decision.schema.json')
Assert ($null -ne $dec) 'decision.schema.json parses as valid JSON'
if ($null -ne $dec) {
    Assert ($dec.title -match 'Decision') 'schema title contains Decision'
    Assert ($null -ne $dec.properties.ID) 'has ID property'
    Assert ($null -ne $dec.properties.status) 'has status property'
    $statusEnum = $dec.properties.status.enum
    Assert ($statusEnum -contains 'PROPOSED') 'status has PROPOSED'
    Assert ($statusEnum -contains 'CONFIRMED') 'status has CONFIRMED'
    Assert ($statusEnum -contains 'REJECTED') 'status has REJECTED'
    Assert ($statusEnum -contains 'SUPERSEDED') 'status has SUPERSEDED'
    Assert ($null -ne $dec.properties.decision_type) 'has decision_type property'
    $dtEnum = $dec.properties.decision_type.enum
    Assert ($dtEnum -contains 'mockup_refinement') 'decision_type has mockup_refinement'
    Assert ($dtEnum -contains 'platform_boundary') 'decision_type has platform_boundary'
    Assert ($dtEnum -contains 'gap_repair') 'decision_type has gap_repair'
    Assert ($null -ne $dec.properties.affected_requirements) 'has affected_requirements'
    Assert ($null -ne $dec.properties.design_contract_ref) 'has design_contract_ref'
    Assert ($null -ne $dec.properties.gap_ref) 'has gap_ref'
}

# ──────────────────────────────────────────────────────────────
# [3] platform_boundaries.schema.json structural validation (WP-10)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[3] platform_boundaries.schema.json structure"
$pb = ParseJSON (Join-Path $RepoRoot '.mxagile/schemas/platform_boundaries.schema.json')
Assert ($null -ne $pb) 'platform_boundaries.schema.json parses as valid JSON'
if ($null -ne $pb) {
    Assert ($pb.title -match '[Pp]latform') 'schema title contains Platform'
    # parity_rule enum
    $pbContent = ReadFile(Join-Path $RepoRoot '.mxagile/schemas/platform_boundaries.schema.json')
    Assert ($pbContent -match 'EXCLUDE_FROM_UI_PARITY') 'has EXCLUDE_FROM_UI_PARITY parity rule'
    Assert ($pbContent -match 'INCLUDE_IN_UI_PARITY') 'has INCLUDE_IN_UI_PARITY parity rule'
    Assert ($pbContent -match 'DO_NOT_MODIFY') 'has DO_NOT_MODIFY modification rule'
    Assert ($pbContent -match 'REUSE_PLATFORM_MODULE') 'has REUSE_PLATFORM_MODULE implementation rule'
}

# ──────────────────────────────────────────────────────────────
# [4] role_coverage.schema.json structural validation (WP-09)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[4] role_coverage.schema.json structure"
$rc = ParseJSON (Join-Path $RepoRoot '.mxagile/schemas/role_coverage.schema.json')
Assert ($null -ne $rc) 'role_coverage.schema.json parses as valid JSON'
if ($null -ne $rc) {
    $rcContent = ReadFile(Join-Path $RepoRoot '.mxagile/schemas/role_coverage.schema.json')
    Assert ($rcContent -match 'COVERED') 'has COVERED status'
    Assert ($rcContent -match 'COVERAGE_GAP') 'has COVERAGE_GAP status'
    Assert ($rcContent -match 'PRESERVATION_FAILURE') 'has PRESERVATION_FAILURE status'
    Assert ($rcContent -match 'overall_status') 'has overall_status field'
    Assert ($rcContent -match 'demo_mode_present') 'has demo_mode_present field'
    Assert ($rcContent -match 'representative_scope_present') 'has representative_scope_present field'
    Assert ($rcContent -match 'required_scope') 'has required_scope field'
}

# ──────────────────────────────────────────────────────────────
# [5] revision.schema.json lifecycle extensions (WP-02, WP-03, WP-04, WP-05)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[5] revision.schema.json lifecycle fields"
$rev = ParseJSON (Join-Path $RepoRoot '.mxagile/schemas/revision.schema.json')
Assert ($null -ne $rev) 'revision.schema.json parses as valid JSON'
$revContent = ReadFile(Join-Path $RepoRoot '.mxagile/schemas/revision.schema.json')
Assert ($revContent -match 'lifecycle_status') 'has lifecycle_status field'
Assert ($revContent -match 'SOURCE') 'lifecycle_status has SOURCE value'
Assert ($revContent -match 'REFINED_TARGET') 'lifecycle_status has REFINED_TARGET value'
Assert ($revContent -match 'SUPERSEDED_TARGET') 'lifecycle_status has SUPERSEDED_TARGET value'
Assert ($revContent -match 'refinement_status') 'has refinement_status field'
Assert ($revContent -match 'PROPOSED') 'refinement_status has PROPOSED value'
Assert ($revContent -match 'ACCEPTED') 'refinement_status has ACCEPTED value'
Assert ($revContent -match 'REJECTED') 'refinement_status has REJECTED value'
Assert ($revContent -match 'active_target') 'has active_target field'
Assert ($revContent -match 'change_scope') 'has change_scope field'
Assert ($revContent -match 'artifact_hash') 'has artifact_hash field'
Assert ($revContent -match 'revision_delta') 'has revision_delta object'
Assert ($revContent -match 'revision_history') 'has revision_history ledger'
Assert ($revContent -match 'preservation') 'has preservation object'
Assert ($revContent -match 'VERIFIED') 'preservation has VERIFIED status'
Assert ($revContent -match 'VERIFIED_WITH_LEDGER') 'preservation has VERIFIED_WITH_LEDGER status'
Assert ($revContent -match 'PARTIAL_EVIDENCE') 'preservation has PARTIAL_EVIDENCE status'
Assert ($revContent -match 'FAILED') 'preservation has FAILED status'

# ──────────────────────────────────────────────────────────────
# [6] page.schema.json interaction state extensions (WP-07, WP-08)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[6] page.schema.json interaction state & effects fields"
$pageContent = ReadFile(Join-Path $RepoRoot '.mxagile/schemas/page.schema.json')
Assert ($pageContent -ne '') 'page.schema.json exists and is non-empty'
Assert ($pageContent -match 'interaction_type') 'has interaction_type field'
Assert ($pageContent -match 'expandable_area') 'has expandable_area interaction type'
Assert ($pageContent -match 'modal') 'has modal interaction type'
Assert ($pageContent -match 'snippet') 'has snippet interaction type'
Assert ($pageContent -match '"trigger"') 'has trigger object'
Assert ($pageContent -match 'persistence') 'has persistence field'
Assert ($pageContent -match '"effects"') 'has effects array'
Assert ($pageContent -match 'effect_id') 'effect has effect_id field'
Assert ($pageContent -match 'effect_type') 'effect has effect_type field'
Assert ($pageContent -match 'expand') 'effect_type has expand value'
Assert ($pageContent -match 'collapse') 'effect_type has collapse value'
Assert ($pageContent -match 'derived_page') 'effect has derived_page field'
Assert ($pageContent -match 'platform_boundary') 'page has platform_boundary field'
Assert ($pageContent -match 'required_action') 'has required_action field'
Assert ($pageContent -match 'UPDATE_REQUIRED') 'required_action has UPDATE_REQUIRED'
Assert ($pageContent -match 'REMOVE_AS_SUPERSEDED') 'required_action has REMOVE_AS_SUPERSEDED'
Assert ($pageContent -match 'REGRESSION_REQUIRED') 'required_action has REGRESSION_REQUIRED'

# ──────────────────────────────────────────────────────────────
# [7] task.schema.json repair type (WP-14)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[7] task.schema.json repair task extensions"
$taskContent = ReadFile(Join-Path $RepoRoot '.mxagile/schemas/task.schema.json')
Assert ($taskContent -match '"repair"') 'task type enum has repair'
Assert ($taskContent -match 'gap_ids') 'repair has gap_ids'
Assert ($taskContent -match 'gap_classifications') 'repair has gap_classifications'
Assert ($taskContent -match 'INTERACTION_GAP') 'gap_classifications has INTERACTION_GAP'
Assert ($taskContent -match 'ROLE_COVERAGE_GAP') 'gap_classifications has ROLE_COVERAGE_GAP'
Assert ($taskContent -match 'PLATFORM_BOUNDARY_VIOLATION') 'gap_classifications has PLATFORM_BOUNDARY_VIOLATION'
Assert ($taskContent -match 'target_reference') 'repair has target_reference'
Assert ($taskContent -match 'target_revision') 'target_reference has target_revision'
Assert ($taskContent -match '"completion"') 'repair has completion object'
Assert ($taskContent -match 'original_gap_fixed') 'completion has original_gap_fixed'
Assert ($taskContent -match 'active_target_used') 'completion has active_target_used'
Assert ($taskContent -match 'artifacts_consistent') 'completion has artifacts_consistent'

# ──────────────────────────────────────────────────────────────
# [8] New canonical policy files exist (WP-12, WP-02 lifecycle)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[8] New canonical policy files exist"
$newPolicies = @(
    '.mxagile/policies/gap-verification-repair.md',
    '.mxagile/policies/mockup-lifecycle.md',
    '.mxagile/policies/impact-resolution.md'
)
foreach ($p in $newPolicies) {
    Assert (Test-Path (Join-Path $RepoRoot $p)) "Policy exists: $p"
}

# ──────────────────────────────────────────────────────────────
# [9] gap-verification-repair.md content (WP-12, WP-15)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[9] gap-verification-repair.md content checks"
$gap = ReadFile(Join-Path $RepoRoot '.mxagile/policies/gap-verification-repair.md')
Assert ($gap -match 'VISUAL_GAP') 'defines VISUAL_GAP classification'
Assert ($gap -match 'INTERACTION_GAP') 'defines INTERACTION_GAP classification'
Assert ($gap -match 'ROLE_GAP') 'defines ROLE_GAP classification'
Assert ($gap -match 'PLATFORM_BOUNDARY_GAP') 'defines PLATFORM_BOUNDARY_GAP classification'
Assert ($gap -match 'CRITICAL') 'defines CRITICAL severity'
Assert ($gap -match 'MATERIAL') 'defines MATERIAL severity'
Assert ($gap -match 'COSMETIC') 'defines COSMETIC severity'
Assert ($gap -match 'DETECTED.*CLASSIFIED|CLASSIFIED.*DETECTED') 'has GAP lifecycle state machine'
Assert ($gap -match 'VERIFIED_REPAIRED|VERIFIED') 'defines final VERIFIED state'
Assert ($gap -match 'Step 1') 'has Step 1 of 14-step workflow'
Assert ($gap -match 'Step 14') 'has Step 14 of 14-step workflow'
Assert ($gap -match 'done.*ALLE|alle.*done.*erfuellt|alle.*Verifikationsschritte') 'completion requires ALL steps'
Assert ($gap -match 'Invent.*FORBIDDEN|FORBIDDEN.*new requirement|reclassif.*FORBIDDEN') 'forbids inventing new requirement for GAP'
Assert ($gap -match 'Platform Boundary') 'addresses platform boundary GAPs'
Assert ($gap -match 'Role Coverage') 'addresses role coverage GAPs'
Assert ($gap -match 'scoped.*role|role.*scope|organisational|scope context') 'addresses scoped role coverage generically'

# ──────────────────────────────────────────────────────────────
# [10] mockup-lifecycle.md content (WP-02)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[10] mockup-lifecycle.md lifecycle model"
$ml = ReadFile(Join-Path $RepoRoot '.mxagile/policies/mockup-lifecycle.md')
Assert ($ml -match 'SOURCE') 'defines SOURCE lifecycle status'
Assert ($ml -match 'REFINED_TARGET') 'defines REFINED_TARGET lifecycle status'
Assert ($ml -match 'SUPERSEDED_TARGET') 'defines SUPERSEDED_TARGET lifecycle status'
Assert ($ml -match 'active_target') 'references active_target invariant'
Assert ($ml -match '[Ee]xactly one|exactly one|genau eine') 'states exactly-one active_target invariant'
Assert ($ml -match 'Platform Boundary') 'references platform boundary scope rule'
Assert ($ml -match 'MB_SSO') 'explicitly names MB_SSO as platform boundary'
Assert ($ml -match '[Ll]ogin|[Aa]nmeldung') 'identifies login screens as platform boundary'

# ──────────────────────────────────────────────────────────────
# [11] impact-resolution.md revision propagation (WP-05 impact)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[11] impact-resolution.md revision propagation"
$ir = ReadFile(Join-Path $RepoRoot '.mxagile/policies/impact-resolution.md')
Assert ($ir -match 'revision|Revision') 'references revision propagation'
Assert ($ir -match 'REV-|revision.*flag|--revision') 'references --revision flag or REV-NNN'
Assert ($ir -match 'active.*[Tt]arget|active_target') 'references active target during propagation'
Assert ($ir -match '[Nn]on.?[Mm]aterial|non_material') 'defines non-material change shortcut'

# ──────────────────────────────────────────────────────────────
# [12] mocketeer-agent.md exists (WP-23 new agent)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[12] mocketeer-agent.md canonical source"
$ma = ReadFile(Join-Path $RepoRoot '.mxagile/agents/mocketeer-agent.md')
Assert ($ma -ne '') 'mocketeer-agent.md exists and is non-empty'
Assert ($ma -match '[Ii]ntake|intake') 'has intake phase'
Assert ($ma -match 'Platform Boundary|platform.boundary') 'has platform boundary classification'
Assert ($ma -match '[Rr]evision') 'handles revision lifecycle'
Assert ($ma -match 'create_revision.py') 'references create_revision.py script'
Assert ($ma -match '[Dd]eveloper.*[Cc]onfirm|[Dd]eveloper.*[Gg]enehmigung|[Bb]estaetigung|developer confirmation') 'requires developer confirmation'

# ──────────────────────────────────────────────────────────────
# [13] Agent files reference new policies (WP-16..20)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[13] Agent files reference new policies"
$agents = @{
    'discovery-agent.md'       = @('Platform Boundary', 'Rollenmmodell|Rollen.*Coverage|role.*coverage', 'interaction.*state|Interaction.*Typ')
    'refinement-agent.md'      = @('revision_delta|Revision Delta', 'required_action', 'SUPERSEDED')
    'ui-agent.md'              = @('platform_boundary', 'derived_page.*false', 'expandable_area')
    'implementation-agent.md'  = @('active_target', 'PLATFORM_BOUNDARY', 'Effect.to.Checklist|Effect-to-Checklist')
    'acceptance-agent.md'      = @('active_target|Active Target', 'GAP.*Verification|gap.*verification', 'gap-verification-repair')
}
foreach ($agentFile in $agents.Keys) {
    $agentContent = ReadFile(Join-Path $RepoRoot ".mxagile/agents/$agentFile")
    foreach ($pattern in $agents[$agentFile]) {
        Assert ($agentContent -match $pattern) "$agentFile matches: $pattern"
    }
}

# ──────────────────────────────────────────────────────────────
# [14] Quality gate WP-21 revision checks (WP-21)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[14] Quality gate WP-21 revision checks"
$gtr = ReadFile(Join-Path $RepoRoot '.mxagile/skills/gate-to-refinement.md')
Assert ($gtr -match 'Mockup Revision Checks|WP-21') 'gate-to-refinement has WP-21 revision checks section'
Assert ($gtr -match 'active_target') 'gate-to-refinement checks active_target uniqueness'
Assert ($gtr -match '[Ll]edger|revision_history') 'gate-to-refinement checks ledger'
Assert ($gtr -match '[Ee]ffect.*referenz|referenzi.*valid|Effects referenziell') 'gate-to-refinement checks effect referential integrity'
Assert ($gtr -match '[Rr]ollen.Coverage|role.coverage') 'gate-to-refinement checks role coverage'
Assert ($gtr -match '[Pp]lattformgrenzen|platform.*bekannt|platform.*boundaries') 'gate-to-refinement checks platform boundaries'

$gtrd = ReadFile(Join-Path $RepoRoot '.mxagile/skills/gate-to-ready.md')
Assert ($gtrd -match 'Mockup Revision.*Checks|WP-21') 'gate-to-ready has WP-21 revision checks section'
Assert ($gtrd -match '[Rr]equirements.*refined|refined.*requirements') 'gate-to-ready checks requirements refined'
Assert ($gtrd -match '[Rr]ollenverlust|role.*loss|unexpected.*role') 'gate-to-ready checks for unexpected role losses'
Assert ($gtrd -match 'target_revision') 'gate-to-ready checks target_revision in checklists'
Assert ($gtrd -match '[Rr]egression.*geplant|planned.*regression') 'gate-to-ready checks regressions planned'
Assert ($gtrd -match 'COVERAGE_GAP') 'gate-to-ready checks for COVERAGE_GAP blocks'

# ──────────────────────────────────────────────────────────────
# [15] New canonical templates exist (WP-27)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[15] New canonical templates exist"
$newTemplates = @(
    '.mxagile/templates/generic/decisions/template.yml',
    '.mxagile/templates/generic/ui-inventory/template.yaml',
    '.mxagile/templates/generic/revisions/template.yaml',
    '.mxagile/templates/generic/role-coverage/template.yaml',
    '.mxagile/templates/generic/repair-tasks/template.yaml'
)
foreach ($t in $newTemplates) {
    Assert (Test-Path (Join-Path $RepoRoot $t)) "Template exists: $t"
}

# ──────────────────────────────────────────────────────────────
# [16] Template content validation (WP-27)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[16] Template content validation"
$decTpl = ReadFile(Join-Path $RepoRoot '.mxagile/templates/generic/decisions/template.yml')
Assert ($decTpl -match 'DEC-001') 'decision template has DEC-001 ID'
Assert ($decTpl -match 'decision_type') 'decision template has decision_type'
Assert ($decTpl -match 'gap_ref') 'decision template has gap_ref'

$uiTpl = ReadFile(Join-Path $RepoRoot '.mxagile/templates/generic/ui-inventory/template.yaml')
Assert ($uiTpl -match 'PAGE-001') 'ui-inventory template has PAGE-001 ID'
Assert ($uiTpl -match 'interaction_states') 'ui-inventory template has interaction_states'
Assert ($uiTpl -match 'effects') 'ui-inventory template has effects'
Assert ($uiTpl -match 'derived_page.*false') 'ui-inventory template has derived_page: false'
Assert ($uiTpl -match 'platform_boundary') 'ui-inventory template has platform_boundary'

$revTpl = ReadFile(Join-Path $RepoRoot '.mxagile/templates/generic/revisions/template.yaml')
Assert ($revTpl -match 'lifecycle_status') 'revision template has lifecycle_status'
Assert ($revTpl -match 'active_target') 'revision template has active_target'
Assert ($revTpl -match 'revision_history') 'revision template has revision_history'
Assert ($revTpl -match 'create_revision.py') 'revision template warns about create_revision.py'

$rcTpl = ReadFile(Join-Path $RepoRoot '.mxagile/templates/generic/role-coverage/template.yaml')
Assert ($rcTpl -match 'COVERAGE_GAP') 'role-coverage template references COVERAGE_GAP'
Assert ($rcTpl -match 'demo_mode_present') 'role-coverage template has demo_mode_present'
Assert ($rcTpl -match 'representative_scope_present') 'role-coverage template has representative_scope_present'

$repairTpl = ReadFile(Join-Path $RepoRoot '.mxagile/templates/generic/repair-tasks/template.yaml')
Assert ($repairTpl -match 'type: repair') 'repair-task template has type: repair'
Assert ($repairTpl -match 'completion') 'repair-task template has completion block'
Assert ($repairTpl -match 'active_target_used') 'repair-task template has active_target_used in completion'
Assert ($repairTpl -match 'REFINED_TARGET') 'repair-task template references REFINED_TARGET'

# ──────────────────────────────────────────────────────────────
# [17] Requirements template revision fields (WP-27)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[17] Requirements template revision fields"
$reqTpl = ReadFile(Join-Path $RepoRoot '.mxagile/templates/generic/requirements/template.yml')
Assert ($reqTpl -match 'revision_status') 'requirements template has revision_status field'
Assert ($reqTpl -match 'implementation_effect') 'requirements template has implementation_effect field'
Assert ($reqTpl -match 'test_effect') 'requirements template has test_effect field'

# ──────────────────────────────────────────────────────────────
# [18] Contract migration section in design-contract.txt (WP-25)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[18] Contract migration section (WP-25)"
$dc = ReadFile(Join-Path $RepoRoot 'products/MxMocketeer/knowledge/design-contract.txt')
Assert ($dc -match '[Cc]ontract Migration') 'design-contract.txt has Contract Migration section'
Assert ($dc -match 'from_schema_version') 'migration object has from_schema_version field'
Assert ($dc -match '"1.0"') 'migration section references v1.0'
Assert ($dc -match 'migrated_fields') 'migration object has migrated_fields'
Assert ($dc -match 'lifecycle_status.*SOURCE|SOURCE.*lifecycle_status') 'migration defaults lifecycle_status to SOURCE'
Assert ($dc -match 'active_target.*true|true.*active_target') 'migration defaults active_target to true'
Assert ($dc -match '[Pp]reserve.*existing ID|existing.*ID.*unchanged') 'migration preserves existing IDs'
Assert ($dc -match 'schema_version.*confirmed|confirmed.*schema_version') 'schema_version upgrade requires confirmation'

# ──────────────────────────────────────────────────────────────
# [19] system-prompt.md v1.0 handling note (WP-25)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[19] system-prompt.md v1.0 contract handling"
$sp = ReadFile(Join-Path $RepoRoot 'products/MxMocketeer/system-prompt.md')
Assert ($sp -match '1\.0.*SOURCE|SOURCE.*1\.0') 'system-prompt treats 1.0 as SOURCE revision'
Assert ($sp -match 'migration.*defaults|migration default') 'system-prompt references migration defaults'
Assert ($sp -match '[Nn]ever.*schema_version|confirm.*schema_version') 'system-prompt requires confirmation before schema_version upgrade'

# ──────────────────────────────────────────────────────────────
# [20] Platform projections include mocketeer-agent (WP-28)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[20] Platform projections include mocketeer-agent"
$projections = @(
    '.claude/agents/mxagile-mocketeer-agent.md'
)
foreach ($p in $projections) {
    $full = Join-Path $RepoRoot $p
    Assert (Test-Path $full) "Projection exists: $p"
    if (Test-Path $full) {
        $content = ReadFile $full
        Assert ($content -match 'GENERATED') "$p carries GENERATED header"
    }
}

# Verify gate projections are updated
$gateProjections = @(
    '.claude/skills/mxagile-gate-to-refinement/SKILL.md',
    '.claude/skills/mxagile-gate-to-ready/SKILL.md',
    '.github/skills/mxagile-gate-to-refinement/SKILL.md',
    '.github/skills/mxagile-gate-to-ready/SKILL.md'
)
foreach ($p in $gateProjections) {
    $full = Join-Path $RepoRoot $p
    Assert (Test-Path $full) "Gate projection exists: $p"
    if (Test-Path $full) {
        $content = ReadFile $full
        Assert ($content -match 'WP-21|Mockup Revision') "Gate projection $p contains WP-21 checks"
    }
}

# ──────────────────────────────────────────────────────────────
# [21] No company-specific content in new canonical files (Security)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[21] No company-specific content in new canonical policy/schema/skill files"
$banned = @('Mercedes', 'mercedes', 'Daimler', 'daimler', 'MBUI', 'MB_UI', 'MBTech',
            'KidsCompass', 'mbrepo', 'mercedes-benz')
$newFiles = @(
    '.mxagile/schemas/decision.schema.json',
    '.mxagile/schemas/platform_boundaries.schema.json',
    '.mxagile/schemas/role_coverage.schema.json',
    '.mxagile/policies/gap-verification-repair.md',
    '.mxagile/agents/mocketeer-agent.md',
    '.mxagile/templates/generic/decisions/template.yml',
    '.mxagile/templates/generic/repair-tasks/template.yaml'
) | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ }
foreach ($term in $banned) {
    $hits = $newFiles | Where-Object {
        (Get-Content $_ -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) -match [regex]::Escape($term)
    } | ForEach-Object { Split-Path $_ -Leaf }
    Assert ($hits.Count -eq 0) "No '$term' in new canonical files" ($hits -join ', ')
}

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all revision lifecycle checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — revision lifecycle validation failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
