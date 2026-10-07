#Requires -Version 7
# MxMocketeer Refinement Transformation static validation — Tier 0
# Validates that the knowledge and agent files contain the required concepts
# for safe large-artifact refinement and targeted transformation.
#
# Behavioral cases A–K (as defined in the MxMocketeer Targeted Transformation spec):
#   A. LOCAL_EDIT          — one target changes; unrelated content preserved
#   B. CROSS_CUTTING_EDIT  — multiple targets, identical transformation; unrelated preserved
#   C. MISSING TARGET      — fail closed
#   D. AMBIGUOUS / UNEXPECTED TARGET — fail closed
#   E. SOURCE PRECONDITION MISMATCH  — fail closed
#   F. PRESERVATION FAILURE          — no accepted revision
#   G. STRUCTURAL_REFACTOR           — correctly classified, not silent replacement
#   H. FULL_REGENERATION             — explicitly gated
#   I. REVISION DELTA                — records only actual changes
#   J. BUSINESS FLOW PRESERVATION    — unrelated flows unchanged
#   K. STICKYHEADER FIXTURE          — CROSS_CUTTING_EDIT succeeds without full manual
#
# Run from repository root:
#   pwsh products/MxMocketeer/tests/test-transformations.ps1

param(
    [string]$ProductRoot = (Join-Path $PSScriptRoot '..')
)

$ProductRoot = (Resolve-Path $ProductRoot).Path
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

Write-Host "`nMxMocketeer Transformation Tests — $ProductRoot" -ForegroundColor Cyan

$rtPath   = Join-Path $ProductRoot 'knowledge/refinement-transformations.txt'
$spPath   = Join-Path $ProductRoot 'system-prompt.md'
$agentDir = Join-Path (Split-Path $ProductRoot -Parent | Split-Path -Parent) '.mxagile/agents/mocketeer-agent.md'

$rt = if (Test-Path $rtPath)   { Get-Content $rtPath   -Raw -Encoding UTF8 } else { '' }
$sp = if (Test-Path $spPath)   { Get-Content $spPath   -Raw -Encoding UTF8 } else { '' }
$ag = if (Test-Path $agentDir) { Get-Content $agentDir -Raw -Encoding UTF8 } else { '' }

# ──────────────────────────────────────────────────────────────
# [Precondition] Required file exists
# ──────────────────────────────────────────────────────────────
Write-Host "`n[0] Required files"
Assert (Test-Path $rtPath)   'knowledge/refinement-transformations.txt exists'
Assert (Test-Path $spPath)   'system-prompt.md exists'
Assert (Test-Path $agentDir) 'canonical mocketeer-agent.md exists'

# ──────────────────────────────────────────────────────────────
# [A] LOCAL_EDIT — defined with execution characteristics
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] LOCAL_EDIT definition and execution"
Assert ($rt -match 'LOCAL_EDIT')                               'A: LOCAL_EDIT defined in refinement-transformations.txt'
Assert ($rt -match 'LOCAL_EDIT[\s\S]{0,300}one.*target|one.*identified.*target|bounded.*change.*one|one.*uniquely' -or
        $rt -match 'one known.*target|uniquely.identified') 'A: LOCAL_EDIT defined as bounded single-target change'
Assert ($sp -match 'LOCAL_EDIT')                               'A: LOCAL_EDIT referenced in system prompt'
Assert ($rt -match 'Transformation Spec')                      'A: Transformation Spec concept defined'

# ──────────────────────────────────────────────────────────────
# [B] CROSS_CUTTING_EDIT — multiple targets, same transformation
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] CROSS_CUTTING_EDIT definition and execution"
Assert ($rt -match 'CROSS_CUTTING_EDIT')                       'B: CROSS_CUTTING_EDIT defined'
Assert ($rt -match 'multiple.*known.*target|same.*deterministic.*transformation|deterministic.*transformation.*multiple' -or
        $rt -match 'multiple known targets') 'B: CROSS_CUTTING_EDIT defined as multi-target identical transformation'
Assert ($rt -match 'Never.*CROSS_CUTTING.*FULL_REGENERATION|never.*classify.*CROSS_CUTTING.*FULL_REGEN' -or
        $sp -match 'Never.*CROSS_CUTTING.*FULL_REGENERATION|CROSS_CUTTING.*FULL_REGENERATION.*targets') 'B: invariant against misclassifying CROSS_CUTTING_EDIT as FULL_REGENERATION'
Assert ($rt -match 'StickyHeader')                             'B: StickyHeader year-change fixture present as canonical CROSS_CUTTING_EDIT example'

# ──────────────────────────────────────────────────────────────
# [C] MISSING TARGET — fail closed
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] Missing target — fail closed"
Assert ($rt -match 'NO TARGETS FOUND|no.*target.*found|match_count.*min|min.*required' -or
        $rt -match 'FAIL CLOSED|fail.*closed')                'C: fail-closed behavior defined for missing targets'
Assert ($rt -match 'STOP.*Target selector|STOP.*no.*target|no target.*STOP') 'C: STOP on missing target documented'

# ──────────────────────────────────────────────────────────────
# [D] AMBIGUOUS / UNEXPECTED TARGET — fail closed
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] Ambiguous / unexpected target — fail closed"
Assert ($rt -match 'UNEXPECTED MATCH COUNT|unexpected.*match|match_count.*max|max.*allowed' -or
        $rt -match 'max.*set.*AND.*match_count') 'D: fail-closed on unexpected match count defined'
Assert ($rt -match 'max.*allowed|max_count|match_constraint.*max') 'D: max match constraint defined'

# ──────────────────────────────────────────────────────────────
# [E] SOURCE PRECONDITION MISMATCH — fail closed
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] Source precondition mismatch — fail closed"
Assert ($rt -match 'PRECONDITION MISMATCH|precondition.*absent|precondition.*does not match|precondition.*not match' -or
        $rt -match 'precondition.*match') 'E: precondition mismatch defined as fail-closed condition'
Assert ($rt -match '"precondition"')      'E: precondition field defined in Transformation Spec schema'

# ──────────────────────────────────────────────────────────────
# [F] PRESERVATION FAILURE — no accepted revision
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] Preservation failure — revision blocked"
Assert ($rt -match 'FAILED.*STOP|preservation.*FAILED.*STOP|STOP.*do not create revision' -or
        $rt -match 'rollback.*failure|FAILED.*rollback') 'F: preservation FAILED blocks revision creation'
Assert ($rt -match 'rollback_on_failure')  'F: rollback_on_failure field defined in spec schema'
Assert ($rt -match 'NON-TARGET REGION.*expected to remain|non.target.*unchanged|non-target.*unchanged') 'F: non-target region preservation contract defined'

# ──────────────────────────────────────────────────────────────
# [G] STRUCTURAL_REFACTOR — correctly classified, not silent replacement
# ──────────────────────────────────────────────────────────────
Write-Host "`n[G] STRUCTURAL_REFACTOR classification"
Assert ($rt -match 'STRUCTURAL_REFACTOR')               'G: STRUCTURAL_REFACTOR defined'
Assert ($rt -match 'STRUCTURAL_REFACTOR[\s\S]{0,200}structure.*change|structure.*reorgani' -or
        $rt -match 'Structural reorganization')         'G: STRUCTURAL_REFACTOR defined as structural change'
Assert ($rt -match 'STRUCTURAL_REFACTOR[\s\S]{0,300}full.*HTML|output.*complete.*HTML|complete.*HTML.*output' -or
        $sp -match 'STRUCTURAL_REFACTOR.*preserve|FULL_REGEN.*STRUCTURAL.*preserve') 'G: STRUCTURAL_REFACTOR requires full HTML output with preservation'

# ──────────────────────────────────────────────────────────────
# [H] FULL_REGENERATION — explicitly gated, not default
# ──────────────────────────────────────────────────────────────
Write-Host "`n[H] FULL_REGENERATION — explicitly gated"
Assert ($rt -match 'FULL_REGENERATION')                   'H: FULL_REGENERATION defined'
Assert ($rt -match 'FULL_REGENERATION[\s\S]{0,300}safe.*when|safe when|explicitly.*justif' -or
        $rt -match 'must.*explicitly.*justify.*FULL_REGENERATION') 'H: FULL_REGENERATION requires explicit justification for existing large mockup'
Assert ($rt -match 'Unsafe when|unsafe.*large.*mockup|large.*mockup.*unsafe') 'H: explicitly marks FULL_REGENERATION as unsafe for large existing mockups'

# ──────────────────────────────────────────────────────────────
# [I] REVISION DELTA — records only actual changes
# ──────────────────────────────────────────────────────────────
Write-Host "`n[I] Revision delta records only actual changes"
Assert ($rt -match 'delta.*records.*only.*actually.changed|only.*actually.changed.*IDs|actually-changed' -or
        $rt -match 'revision_delta[\s\S]{0,300}only.*actual|actual.*changes.*only') 'I: revision_delta records only actually-changed IDs (not all targeted elements)'
Assert ($rt -match 'Revision Lifecycle Integration')       'I: revision lifecycle integration section present'
Assert ($ag -match 'tatsaechlich.*geaenderte|tatsaechlich.*geaenderten|nur.*tatsaechlich') 'I: mocketeer-agent records only actually-changed IDs in revision_history'

# ──────────────────────────────────────────────────────────────
# [J] BUSINESS FLOW PRESERVATION — unrelated flows unchanged
# ──────────────────────────────────────────────────────────────
Write-Host "`n[J] Business flow preservation for unrelated flows"
Assert ($rt -match 'business_flow_impact')                 'J: business_flow_impact field defined in spec schema'
Assert ($rt -match 'NONE.*presentation.only|presentation.only.*NONE|NONE.*flow.*semantics.*unchanged' -or
        $rt -match 'business_flow_impact.*NONE') 'J: NONE value defined for presentation-only changes'
Assert ($rt -match 'must NOT.*fabricate.*Business Flow|must NOT.*flow.*changes|presentation.only.*must NOT' -or
        $rt -match 'NONE.*no.*Flow.*effects|no.*FLOW.*STORY.*IMPLEMENTATION') 'J: presentation-only change must not fabricate Business Flow entries'
Assert ($ag -match 'business_flow_impact.*NONE|NONE.*keine.*Flow.*Story.*Implementation|keine.*Flow-.*Story') 'J: mocketeer-agent implements NONE flow impact as no-op for flow effects'

# ──────────────────────────────────────────────────────────────
# [K] STICKYHEADER FIXTURE — year-change succeeds as CROSS_CUTTING_EDIT
# ──────────────────────────────────────────────────────────────
Write-Host "`n[K] StickyHeader fixture — canonical CROSS_CUTTING_EDIT case"
Assert ($rt -match 'StickyHeader Year.Change|StickyHeader.*year.change|year.*StickyHeader' -or
        $rt -match 'StickyHeader.*canonical.*fixture|canonical.*fixture.*StickyHeader') 'K: StickyHeader year-change documented as canonical fixture'
Assert ($rt -match 'StickyHeader[\s\S]{0,400}CROSS_CUTTING_EDIT')  'K: StickyHeader fixture classified as CROSS_CUTTING_EDIT'
Assert ($rt -match 'TEXT_REPLACE.*2024.*2025|2024.*2025.*TEXT_REPLACE' -or
        $rt -match "precondition.*2024|2024.*precondition") 'K: fixture demonstrates precondition (2024) and replacement (2025)'
Assert ($rt -match 'must NOT hard.code.*StickyHeader|generic.*CROSS_CUTTING.*StickyHeader.*proves' -or
        $rt -match 'StickyHeader.*proves it works|fixture.*generic.*path') 'K: fixture explicitly proves the generic CROSS_CUTTING_EDIT path, not a special case'
Assert ($rt -match "business_flow_impact.*NONE.*StickyHeader|StickyHeader.*business_flow_impact.*NONE" -or
        $rt -match 'year.*header.*presentation.only|presentation.only.*year.*header') 'K: StickyHeader year change confirmed as presentation-only (no flow impact)'

# ──────────────────────────────────────────────────────────────
# [Extra] Execution boundary — M365 vs file-capable agent
# ──────────────────────────────────────────────────────────────
Write-Host "`n[Extra] Execution boundary and handoff"
Assert ($rt -match 'Handoff Format|handoff.*format|machine-readable handoff') 'Extra: handoff format defined for file-capable agent execution'
Assert ($rt -match 'mocketeer-transformation-spec|mocketeer.transformation.spec') 'Extra: mocketeer-transformation-spec element name defined'
Assert ($rt -match 'handoff_target')            'Extra: handoff_target field defined in spec schema'
Assert ($ag -match 'Phase 6|phase.*6|Phase.*6') 'Extra: mocketeer-agent has Phase 6 (Transformation Spec Execution)'
Assert ($ag -match 'EINZIGE.*autorisierte|einzig.*autorisiert|only.*authorized.*path' -or
        $ag -match 'einzige.*autorisierte.*Weg|autorisierte.*Weg') 'Extra: Phase 6 is the only authorized path for HTML file mutation'
Assert ($ag -match 'mocketeer-transformation-spec|transformation-spec')  'Extra: mocketeer-agent reads the transformation-spec handoff element'

# ──────────────────────────────────────────────────────────────
# [Extra] Spec schema completeness
# ──────────────────────────────────────────────────────────────
Write-Host "`n[Extra] Transformation Spec schema fields"
$schemaFields = @(
    '"spec_id"',
    '"change_class"',
    '"source_revision"',
    '"target_revision"',
    '"intent"',
    '"operations"',
    '"op_id"',
    '"operation"',
    '"target_selector"',
    '"precondition"',
    '"replacement"',
    '"match_constraint"',
    '"preservation_scope"',
    '"affected_contract_ids"',
    '"affected_flows"',
    '"affected_screens"',
    '"business_flow_impact"',
    '"rollback_on_failure"',
    '"handoff_target"'
)
foreach ($field in $schemaFields) {
    Assert ($rt -match [regex]::Escape($field)) "Schema field $field defined"
}

# ──────────────────────────────────────────────────────────────
# [Extra] Operation types complete
# ──────────────────────────────────────────────────────────────
Write-Host "`n[Extra] Operation types"
$opTypes = @('TEXT_REPLACE', 'ATTRIBUTE_SET', 'ELEMENT_REMOVE', 'ELEMENT_ADD')
foreach ($op in $opTypes) {
    Assert ($rt -match $op) "Operation type $op defined"
}

# ──────────────────────────────────────────────────────────────
# [Extra] Product boundary — Phase 6 scoped to LOCAL/CROSS_CUTTING only
# ──────────────────────────────────────────────────────────────
Write-Host "`n[Extra] Phase 6 scope constraints"
Assert ($ag -match 'FULL_REGENERATION.*NICHT|NOT.*FULL_REGENERATION|phase.*6.*NICHT.*FULL_REGEN' -or
        $ag -match 'darf NICHT.*FULL_REGENERATION|Phase 6 darf NICHT') 'Phase 6 explicitly excludes FULL_REGENERATION'
Assert ($ag -match 'STRUCTURAL_REFACTOR.*NICHT|NOT.*STRUCTURAL_REFACTOR|Phase 6 darf NICHT.*STRUCTURAL' -or
        $ag -match 'darf NICHT.*STRUCTURAL') 'Phase 6 explicitly excludes STRUCTURAL_REFACTOR'
Assert ($ag -match 'ohne valide Transformation Spec|without.*valid.*Transformation Spec|no.*Transformation Spec') 'Phase 6 must not mutate without a valid Transformation Spec'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all transformation tests passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — transformation tests failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
