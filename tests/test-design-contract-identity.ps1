#Requires -Version 7
# MxAgile Design Contract Source Namespace and Canonical ID Mapping — Tier 0 static validation
#
# Validates that:
# - Source and canonical identity spaces are formally separated in policies and schemas
# - Source-to-canonical mapping format is defined and contains required fields
# - ID collision detection and allocation rules are present
# - Confirmed decisions must be dispositioned before intake can complete
# - Source IDs may not be written into canonical reference fields
# - Test contract receives canonical IDs and retains source provenance
# - Backward compatibility with legacy design_contract_ref format is addressed
#
# Run from repository root:  pwsh tests/test-design-contract-identity.ps1

param(
    [string]$RepoRoot = (Get-Location).Path
)

$RepoRoot = (Resolve-Path $RepoRoot).Path
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

Write-Host "`nDesign Contract Identity — $RepoRoot" -ForegroundColor Cyan

$dci  = Get-Content (Join-Path $RepoRoot '.mxagile\policies\design-contract-intake.md') -Raw -Encoding UTF8
$tcd  = Get-Content (Join-Path $RepoRoot '.mxagile\policies\test-contract-derivation.md') -Raw -Encoding UTF8
$da   = Get-Content (Join-Path $RepoRoot '.mxagile\agents\discovery-agent.md') -Raw -Encoding UTF8
$docs = Get-Content (Join-Path $RepoRoot 'docs\schemas.md') -Raw -Encoding UTF8
$reqSch = Get-Content (Join-Path $RepoRoot '.mxagile\schemas\requirement.schema.json') -Raw -Encoding UTF8
$tcSch  = Get-Content (Join-Path $RepoRoot '.mxagile\schemas\test-contract.schema.json') -Raw -Encoding UTF8

# ──────────────────────────────────────────────────────────────
# A  Explicit source namespace
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] Explicit source namespace"
Assert ($dci -match 'SOURCE IDENTITY|source_system|source_artifact') 'A1: design-contract-intake.md defines source identity fields'
Assert ($dci -match 'source_system.*mocketeer|mocketeer.*source_system') 'A2: source system explicitly named as mocketeer'
Assert ($dci -match 'source_revision') 'A3: source identity includes revision (multi-revision support)'
Assert ($dci -match 'source_type') 'A4: source identity includes source_type (requirement|decision|role|...)'
Assert ($docs -match 'SOURCE IDENTITY|source_system|Source Identity') 'A5: docs/schemas.md documents source identity namespace'

# ──────────────────────────────────────────────────────────────
# B  Explicit canonical namespace
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] Explicit canonical namespace"
Assert ($dci -match 'CANONICAL IDENTITY|canonical_type|canonical_id') 'B1: design-contract-intake.md defines canonical identity'
Assert ($dci -match 'assigned.*Refinement|Refinement.*assigned|canonical.*assigned.*during Refinement') 'B2: canonical IDs are assigned during Refinement, not intake'
Assert ($docs -match 'Canonical Identity|canonical_type|canonical_id') 'B3: docs/schemas.md documents canonical identity namespace'
Assert ($docs -match 'DIFFERENT artifacts|separate namespaces|different.*namespaces|two.*namespaces') 'B4: docs explicitly states source and canonical are different namespaces'

# ──────────────────────────────────────────────────────────────
# C  Source-to-canonical mapping
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] Source-to-canonical mapping"
Assert ($dci -match 'SOURCE-TO-CANONICAL MAPPING|id_map') 'C1: design-contract-intake.md has SOURCE-TO-CANONICAL MAPPING section'
Assert ($dci -match 'mapping_status') 'C2: id_map entries have mapping_status field'
Assert ($dci -match 'PENDING|mapping_status.*PENDING') 'C3: PENDING status defined (canonical ID not yet assigned)'
Assert ($dci -match 'DIRECT|mapping_status.*DIRECT') 'C4: DIRECT status defined (same semantic content confirmed)'
Assert ($dci -match 'MAPPED|mapping_status.*MAPPED') 'C5: MAPPED status defined (different canonical ID allocated)'
Assert ($dci -match 'EXCLUDED') 'C6: EXCLUDED status defined (explicitly excluded with justification)'
Assert ($docs -match 'id_map|SOURCE-TO-CANONICAL') 'C7: docs/schemas.md documents the mapping mechanism'

# ──────────────────────────────────────────────────────────────
# D  Source relationships preserved separately
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] Source relationships preserved"
Assert ($dci -match 'source_superseded_by|supersession.*source|source.*supersession') 'D1: source supersession chain preserved in id_map'
Assert ($dci -match 'source_governs|governs.*source|source.*governs') 'D2: source governance relationships preserved in id_map'
Assert ($dci -match 'source graph remains reconstructable|reconstructable') 'D3: policy explicitly states source graph remains reconstructable'
Assert ($docs -match 'source graph remains reconstructable|source.*reconstructable') 'D4: docs/schemas.md confirms source graph reconstructable'

# ──────────────────────────────────────────────────────────────
# E  ID collision handling
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] ID collision handling"
Assert ($dci -match 'COLLISION|mapping_status.*COLLISION|collision_note') 'E1: COLLISION status defined for source-ID-occupies-canonical-ID case'
Assert ($dci -match 'allocate.*new canonical|new canonical ID|allocate a new') 'E2: collision requires new canonical ID allocation'
Assert ($dci -match 'do not renumber|Do not renumber') 'E3: source IDs must not be renumbered'
Assert ($dci -match 'overwrite the existing canonical|do NOT overwrite|Do not overwrite') 'E4: existing canonical artifact must not be overwritten'
Assert ($dci -match 'equal IDs.*collision|ID equality.*collision|Equal IDs.*COLLISION|equal.*IDs.*not.*identity') 'E5: equal IDs ≠ semantic identity (collision risk stated)'

# ──────────────────────────────────────────────────────────────
# F  Decision import completeness
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] Decision import completeness"
Assert ($dci -match 'DECISION IMPORT COMPLETENESS') 'F1: design-contract-intake.md has DECISION IMPORT COMPLETENESS section'
Assert ($dci -match 'CONFIRMED_BY_STAKEHOLDER|CONFIRMED_BY_SOURCE') 'F2: confirmed decision statuses named in completeness section'
Assert ($dci -match 'materially governs') 'F3: completeness condition scoped to decisions that materially govern requirements'
Assert ($dci -match 'TRACEABILITY_ERROR') 'F4: undispositioned confirmed decision causes TRACEABILITY_ERROR'

# ──────────────────────────────────────────────────────────────
# G  Semantic matching (not ID equality)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[G] Semantic matching before DIRECT mapping"
Assert ($dci -match 'SEMANTIC MATCHING|semantic.*identity|semantic.*equi') 'G1: policy requires semantic matching before DIRECT mapping'
Assert ($dci -match 'Equal IDs.*different content|different content.*equal IDs|IDs match.*content differs') 'G2: policy distinguishes ID match from content match'

# ──────────────────────────────────────────────────────────────
# H  Source IDs must not appear in canonical reference fields
# ──────────────────────────────────────────────────────────────
Write-Host "`n[H] Source ID containment — canonical fields must not accept source IDs"
Assert ($dci -match 'SOURCE ID CONTAINMENT RULE|CONTAINMENT RULE') 'H1: design-contract-intake.md has SOURCE ID CONTAINMENT RULE'
Assert ($dci -match 'derivedFrom.*DC source|derivedFrom.*NOT a PAGE|derivedFrom.*DC source REQ') 'H2: derivedFrom explicitly excluded for DC source IDs'
Assert ($dci -match 'requirement_ids.*canonical|canonical.*requirement_ids') 'H3: requirement_ids must be canonical only'
Assert ($dci -match 'related_decisions.*invented field|related_decisions.*not.*exist|related_decisions.*invalid|invented field.*related_decisions') 'H4: related_decisions is identified as a non-existent invented field'
Assert ($tcd -match 'Design Contract Source ID Containment') 'H5: test-contract-derivation.md has source ID containment section'
Assert ($tcd -match 'requirement_ids.*canonical|canonical.*REQ-NNN.*requirement_ids') 'H6: test-contract-derivation.md states requirement_ids must be canonical'
Assert ($tcd -match 'design_contract_elements.*ONLY|ONLY.*design_contract_elements') 'H7: design_contract_elements is the only location for DC source IDs in test contracts'

# ──────────────────────────────────────────────────────────────
# I  Discovery agent namespace guard
# ──────────────────────────────────────────────────────────────
Write-Host "`n[I] Discovery agent ID namespace guard"
Assert ($da -match 'ID NAMESPACE GUARD') 'I1: discovery-agent.md has ID NAMESPACE GUARD'
Assert ($da -match 'separate namespace|different namespace') 'I2: agent doc states source and canonical are separate namespaces'
Assert ($da -match 'DO NOT.*copy DC source IDs|never.*copy.*source.*IDs|DO NOT.*copy.*source ID') 'I3: agent doc prohibits copying source IDs to canonical fields'
Assert (($da -match 'CONFIRMED_BY_STAKEHOLDER|CONFIRMED_BY_SOURCE') -and ($da -match 'dispositioned')) 'I4: agent doc requires confirmed decisions to be dispositioned'

# ──────────────────────────────────────────────────────────────
# J  Intake validation and result semantics
# ──────────────────────────────────────────────────────────────
Write-Host "`n[J] Intake validation and result semantics"
Assert ($dci -match 'INTAKE VALIDATION') 'J1: design-contract-intake.md has INTAKE VALIDATION section'
Assert ($dci -match 'INTAKE RESULT SEMANTICS') 'J2: design-contract-intake.md has INTAKE RESULT SEMANTICS section'
Assert ($dci -match 'TRACEABILITY_ERROR.*blocks|blocks.*Refinement|TRACEABILITY_ERROR.*block') 'J3: TRACEABILITY_ERROR blocks Refinement'
Assert ($dci -match 'canonical reference field.*canonical ID|canonical.*never.*source ID|source ID.*never.*canonical') 'J4: intake validation verifies no source IDs in canonical fields'
Assert ($dci -match 'collision.*COLLISION.*id_map|id_map.*COLLISION|silently.*collision') 'J5: intake validation catches silent collisions'

# ──────────────────────────────────────────────────────────────
# K  Test contract canonical ID + source provenance
# ──────────────────────────────────────────────────────────────
Write-Host "`n[K] Test contract: canonical IDs + source provenance"
Assert ($tcSch -match '"design_contract_elements"') 'K1: test-contract schema has design_contract_elements field'
Assert ($tcSch -match '"requirement_ids"') 'K2: test-contract schema has requirement_ids field'
Assert ($tcSch -match 'pattern.*REQ-') 'K3: requirement_ids entries must match REQ- pattern (canonical)'
Assert ($tcd -match 'canonical.*requirement.*REQ-NNN\.yml|REQ-NNN\.yml.*canonical') 'K4: test-contract-derivation.md states TC requires canonical requirement to exist first'
Assert ($tcd -match 'design_contract_elements.*DC source|DC source.*design_contract_elements') 'K5: test-contract-derivation.md places DC source IDs in design_contract_elements'

# ──────────────────────────────────────────────────────────────
# L  Requirement schema: derivedFrom accepts only PAGE- IDs
# ──────────────────────────────────────────────────────────────
Write-Host "`n[L] Requirement schema: derivedFrom is PAGE- only (never DC source IDs)"
Assert ($reqSch -match '"pattern".*"\\^PAGE-"|\^PAGE-') 'L1: requirement.schema.json derivedFrom pattern is ^PAGE-'
Assert ($dci -notmatch 'derivedFrom.*Map.*req\.id|Map.*req\.id.*derivedFrom') 'L2: intake policy no longer instructs writing req.id to derivedFrom'

# ──────────────────────────────────────────────────────────────
# M  Source revision as part of source identity
# ──────────────────────────────────────────────────────────────
Write-Host "`n[M] Source revision is part of source identity"
Assert ($dci -match 'source_revision') 'M1: source_revision is a named field in source identity'
Assert ($dci -match 'multi-revision reconciliation|revision.*source identity|source identity.*revision') 'M2: source_revision supports multi-revision reconciliation'

# ──────────────────────────────────────────────────────────────
# N  Two source artifacts may have same ID without collision
# ──────────────────────────────────────────────────────────────
Write-Host "`n[N] Source identity includes artifact context (two sources may share IDs)"
Assert ($dci -match 'source_artifact|source_system.*source_artifact') 'N1: source identity includes source_artifact to distinguish different contracts'
Assert ($docs -match 'source_artifact|two.*source.*same ID|two different.*REQ-001') 'N2: docs/schemas.md confirms source artifact is part of identity'

# ──────────────────────────────────────────────────────────────
# O  Canonical supersession chain resolves
# ──────────────────────────────────────────────────────────────
Write-Host "`n[O] Canonical supersession resolves through mapping"
Assert ($dci -match 'canonical relationship.*resolves|canonical.*superseded_by.*resolved|resolved.*canonical') 'O1: canonical supersession relationship is resolved through id_map'
Assert ($docs -match 'canonical.*superseded_by|superseded_by.*canonical|canonical.*supersession') 'O2: docs/schemas.md shows canonical supersession example'

# ──────────────────────────────────────────────────────────────
# P  Backward compatibility with legacy dc_ref format
# ──────────────────────────────────────────────────────────────
Write-Host "`n[P] Backward compatibility"
Assert ($dci -match 'dc_id|backward.compat|legacy.*design_contract_ref|Backward|backward') 'P1: design-contract-intake.md addresses backward compatibility with legacy dc_id format'
Assert ($dci -match 'ambiguity.*cannot.*resolved|migration.*traceability debt|traceability debt') 'P2: unresolvable legacy ambiguity reported as migration/traceability debt'

# ──────────────────────────────────────────────────────────────
# Q  Story spec schema formally defines design_contract_provenance
# ──────────────────────────────────────────────────────────────
Write-Host "`n[Q] Story spec schema: design_contract_provenance formally defined"
$sssPath = Join-Path $RepoRoot 'planning\story-spec.schema.json'
$sss = Get-Content $sssPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($sss.properties.PSObject.Properties.Name -contains 'design_contract_provenance') 'Q1: story-spec.schema.json has design_contract_provenance property'
Assert ($sss.required -notcontains 'design_contract_provenance') 'Q2: design_contract_provenance not required (backward compatible)'
Assert ($sss.definitions.PSObject.Properties.Name -contains 'IdMapEntry') 'Q3: IdMapEntry defined in schema definitions'
$ent = $sss.definitions.IdMapEntry
Assert ($ent.additionalProperties -eq $false) 'Q4: IdMapEntry has additionalProperties: false (strict validation)'
$msEnum = $ent.properties.mapping_status.enum
Assert (($msEnum -contains 'PENDING') -and ($msEnum -contains 'COLLISION') -and ($msEnum -contains 'MAPPED')) 'Q5: mapping_status enum has PENDING, COLLISION, MAPPED'
$cidType = $ent.properties.canonical_id.type
$cidAllowsNull = if ($cidType -is [array]) { $cidType -contains 'null' } else { $cidType -eq 'null' }
Assert ($cidAllowsNull) 'Q6: canonical_id allows null (Discovery-stage PENDING entries valid)'

# ──────────────────────────────────────────────────────────────
# R  Refinement agent owns mapping completion
# ──────────────────────────────────────────────────────────────
Write-Host "`n[R] Refinement agent and skill own mapping completion"
$ra = Get-Content (Join-Path $RepoRoot '.mxagile\agents\refinement-agent.md') -Raw -Encoding UTF8
$rs = Get-Content (Join-Path $RepoRoot '.mxagile\skills\refinement.md') -Raw -Encoding UTF8
Assert ($ra -match 'Design Contract Source-to-Canonical Mapping') 'R1: refinement-agent.md has mapping ownership section'
Assert ($ra -match 'PENDING') 'R2: agent doc addresses PENDING entry reconciliation'
Assert ($ra -match 'COLLISION') 'R3: agent doc addresses COLLISION resolution'
Assert (($ra -match 'CONFIRMED_BY_STAKEHOLDER') -and ($ra -match 'canonisieren|canonicalize')) 'R4: agent doc canonicalizes confirmed decisions'
Assert ($ra -match 'Gate.*blockiert|gate.*NICHT.*bestanden') 'R5: gate is blocked by unresolved material mappings'
Assert ($rs -match 'Design Contract Mapping|id_map') 'R6: refinement.md has id_map completion step'

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
Write-Host "`n========================================"
if ($fail -eq 0) {
    Write-Host "  PASS: $pass   FAIL: $fail — all checks passed" -ForegroundColor Green
} else {
    Write-Host "  PASS: $pass   FAIL: $fail — validation failed" -ForegroundColor Red
}
Write-Host "========================================`n"

exit ($fail -gt 0 ? 1 : 0)
