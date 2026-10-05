#Requires -Version 7
# MxAgile Story Spec Design Contract Provenance Schema — Tier 0 static validation
#
# Validates that planning/story-spec.schema.json formally defines design_contract_provenance
# with id_map support, including IdMapEntry with correct required fields, enum values, and
# additionalProperties: false for strict validation.
#
# Also validates that:
# - design_contract_provenance is NOT required at root (existing specs remain valid)
# - IdMapEntry has the right mapping_status enum (PENDING/DIRECT/MAPPED/EXCLUDED/COLLISION)
# - canonical_id allows null (Discovery-stage PENDING entries)
# - source_type enum covers all 7 artifact types
# - backward-compatible fields (mockup_id, revision) remain present
# - IdMapEntry is strict (additionalProperties: false)
# - sample Discovery/Collision/Refinement stage entries are structurally valid
#
# Run from repository root:  pwsh tests/test-story-spec-provenance.ps1

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

Write-Host "`nStory Spec Provenance Schema — $RepoRoot" -ForegroundColor Cyan

$schemaPath = Join-Path $RepoRoot 'planning\story-spec.schema.json'
$schema = Get-Content $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rawSchema = Get-Content $schemaPath -Raw -Encoding UTF8

# ──────────────────────────────────────────────────────────────
# A  design_contract_provenance property exists and is not required
# ──────────────────────────────────────────────────────────────
Write-Host "`n[A] design_contract_provenance: present but not required"
Assert ($schema.properties.PSObject.Properties.Name -contains 'design_contract_provenance') 'A1: schema has design_contract_provenance property'
Assert ($schema.required -notcontains 'design_contract_provenance') 'A2: design_contract_provenance is NOT in required[] (existing specs remain valid)'
Assert ($schema.additionalProperties -eq $false) 'A3: root schema still has additionalProperties: false'

# ──────────────────────────────────────────────────────────────
# B  Provenance object fields
# ──────────────────────────────────────────────────────────────
Write-Host "`n[B] design_contract_provenance object fields"
$prov = $schema.properties.design_contract_provenance
Assert ($null -ne $prov) 'B1: design_contract_provenance property is an object'
$provProps = $prov.properties.PSObject.Properties.Name
Assert ($provProps -contains 'source_system') 'B2: source_system field present'
Assert ($provProps -contains 'source_artifact') 'B3: source_artifact field present'
Assert ($provProps -contains 'source_revision') 'B4: source_revision field present'
Assert ($provProps -contains 'intake_date') 'B5: intake_date field present'
Assert ($provProps -contains 'intake_result') 'B6: intake_result field present'
Assert ($provProps -contains 'id_map') 'B7: id_map field present'
Assert ($provProps -contains 'mockup_id') 'B8: backward-compatible mockup_id field present'
Assert ($provProps -contains 'revision') 'B9: backward-compatible revision field present'

# ──────────────────────────────────────────────────────────────
# C  intake_result enum covers required values
# ──────────────────────────────────────────────────────────────
Write-Host "`n[C] intake_result enum"
$intakeResultEnum = $prov.properties.intake_result.enum
Assert ($intakeResultEnum -contains 'COMPLETE') 'C1: intake_result COMPLETE'
Assert ($intakeResultEnum -contains 'PARTIAL') 'C2: intake_result PARTIAL'
Assert ($intakeResultEnum -contains 'FAILED') 'C3: intake_result FAILED'
Assert ($intakeResultEnum -contains 'TRACEABILITY_ERROR') 'C4: intake_result TRACEABILITY_ERROR'

# ──────────────────────────────────────────────────────────────
# D  IdMapEntry definition exists and is strict
# ──────────────────────────────────────────────────────────────
Write-Host "`n[D] IdMapEntry definition"
Assert ($schema.definitions.PSObject.Properties.Name -contains 'IdMapEntry') 'D1: IdMapEntry defined in definitions'
$entry = $schema.definitions.IdMapEntry
Assert ($entry.additionalProperties -eq $false) 'D2: IdMapEntry has additionalProperties: false (strict)'
$entryRequired = $entry.required
Assert ($entryRequired -contains 'source_type') 'D3: source_type is required'
Assert ($entryRequired -contains 'source_id') 'D4: source_id is required'
Assert ($entryRequired -contains 'canonical_id') 'D5: canonical_id is required'
Assert ($entryRequired -contains 'mapping_status') 'D6: mapping_status is required'

# ──────────────────────────────────────────────────────────────
# E  mapping_status enum covers all 5 states
# ──────────────────────────────────────────────────────────────
Write-Host "`n[E] mapping_status enum"
$msEnum = $entry.properties.mapping_status.enum
Assert ($msEnum -contains 'PENDING') 'E1: mapping_status PENDING'
Assert ($msEnum -contains 'DIRECT') 'E2: mapping_status DIRECT'
Assert ($msEnum -contains 'MAPPED') 'E3: mapping_status MAPPED'
Assert ($msEnum -contains 'EXCLUDED') 'E4: mapping_status EXCLUDED'
Assert ($msEnum -contains 'COLLISION') 'E5: mapping_status COLLISION'

# ──────────────────────────────────────────────────────────────
# F  source_type enum covers all 7 artifact types
# ──────────────────────────────────────────────────────────────
Write-Host "`n[F] source_type enum"
$stEnum = $entry.properties.source_type.enum
Assert ($stEnum -contains 'requirement') 'F1: source_type requirement'
Assert ($stEnum -contains 'decision') 'F2: source_type decision'
Assert ($stEnum -contains 'business_rule') 'F3: source_type business_rule'
Assert ($stEnum -contains 'role') 'F4: source_type role'
Assert ($stEnum -contains 'screen') 'F5: source_type screen'
Assert ($stEnum -contains 'flow') 'F6: source_type flow'
Assert ($stEnum -contains 'gap') 'F7: source_type gap'

# ──────────────────────────────────────────────────────────────
# G  canonical_id allows null (Discovery-stage PENDING entries)
# ──────────────────────────────────────────────────────────────
Write-Host "`n[G] canonical_id accepts null"
$cidType = $entry.properties.canonical_id.type
$cidAllowsNull = if ($cidType -is [array]) { $cidType -contains 'null' } else { $cidType -eq 'null' }
Assert ($cidAllowsNull) 'G1: canonical_id type allows null (for PENDING and COLLISION entries)'

# ──────────────────────────────────────────────────────────────
# H  source relationship fields present
# ──────────────────────────────────────────────────────────────
Write-Host "`n[H] source relationship fields"
$entryProps = $entry.properties.PSObject.Properties.Name
Assert ($entryProps -contains 'source_superseded_by') 'H1: source_superseded_by field present'
Assert ($entryProps -contains 'source_governs') 'H2: source_governs field present'
Assert ($entry.properties.source_governs.type -eq 'array') 'H3: source_governs is an array'

# ──────────────────────────────────────────────────────────────
# I  id_map references IdMapEntry
# ──────────────────────────────────────────────────────────────
Write-Host "`n[I] id_map → IdMapEntry reference"
$idMapItems = $prov.properties.id_map.items
Assert ($idMapItems.'$ref' -eq '#/definitions/IdMapEntry') 'I1: id_map items.$ref points to IdMapEntry'

# ──────────────────────────────────────────────────────────────
# J  Sample Discovery-stage PENDING entry is structurally valid
# ──────────────────────────────────────────────────────────────
Write-Host "`n[J] Sample Discovery-stage PENDING entry structure"
$discoveryEntry = @{
    source_type    = 'requirement'
    source_id      = 'REQ-066'
    source_status  = 'CONFIRMED_BY_STAKEHOLDER'
    canonical_id   = $null
    mapping_status = 'PENDING'
}
# Verify all keys are in the schema (no unknown fields)
$unknownFields = $discoveryEntry.Keys | Where-Object { $entryProps -notcontains $_ }
Assert (-not $unknownFields) 'J1: Discovery PENDING entry uses only schema-defined fields'
# Verify required fields all present
$missingRequired = $entryRequired | Where-Object { -not $discoveryEntry.ContainsKey($_) }
Assert (-not $missingRequired) 'J2: Discovery PENDING entry has all required fields'
Assert ($discoveryEntry.mapping_status -eq 'PENDING') 'J3: Discovery stage uses PENDING status'
Assert ($null -eq $discoveryEntry.canonical_id) 'J4: canonical_id is null in PENDING entry'

# ──────────────────────────────────────────────────────────────
# K  Sample COLLISION entry is structurally valid
# ──────────────────────────────────────────────────────────────
Write-Host "`n[K] Sample COLLISION entry structure"
$collisionEntry = @{
    source_type    = 'decision'
    source_id      = 'DEC-024'
    canonical_id   = $null
    mapping_status = 'COLLISION'
    collision_note = 'canonical DEC-024 is an unrelated Berechtigungsreport decision'
    source_governs = @('REQ-066')
}
$unknownFieldsC = $collisionEntry.Keys | Where-Object { $entryProps -notcontains $_ }
Assert (-not $unknownFieldsC) 'K1: COLLISION entry uses only schema-defined fields'
$missingRequiredC = $entryRequired | Where-Object { -not $collisionEntry.ContainsKey($_) }
Assert (-not $missingRequiredC) 'K2: COLLISION entry has all required fields'
Assert ($null -eq $collisionEntry.canonical_id) 'K3: canonical_id is null in COLLISION entry'
Assert ($collisionEntry.mapping_status -eq 'COLLISION') 'K4: COLLISION status set'

# ──────────────────────────────────────────────────────────────
# L  Sample Refinement-completed MAPPED entry is structurally valid
# ──────────────────────────────────────────────────────────────
Write-Host "`n[L] Sample Refinement-completed MAPPED entry structure"
$mappedEntry = @{
    source_type    = 'decision'
    source_id      = 'DEC-024'
    canonical_type = 'decision'
    canonical_id   = 'DEC-031'
    mapping_status = 'MAPPED'
    collision_note = 'canonical DEC-024 was unrelated; new DEC-031 allocated'
    source_governs = @('REQ-066')
}
$unknownFieldsM = $mappedEntry.Keys | Where-Object { $entryProps -notcontains $_ }
Assert (-not $unknownFieldsM) 'L1: MAPPED entry uses only schema-defined fields'
$missingRequiredM = $entryRequired | Where-Object { -not $mappedEntry.ContainsKey($_) }
Assert (-not $missingRequiredM) 'L2: MAPPED entry has all required fields'
Assert ('DEC-031' -eq $mappedEntry.canonical_id) 'L3: canonical_id populated in MAPPED entry'
Assert ($mappedEntry.mapping_status -eq 'MAPPED') 'L4: MAPPED status set after Refinement'

# ──────────────────────────────────────────────────────────────
# M  Supersession entry is structurally valid
# ──────────────────────────────────────────────────────────────
Write-Host "`n[M] Supersession entry structure"
$supersededEntry = @{
    source_type         = 'requirement'
    source_id           = 'REQ-001'
    canonical_id        = $null
    mapping_status      = 'PENDING'
    source_superseded_by = 'REQ-007'
}
$unknownFieldsS = $supersededEntry.Keys | Where-Object { $entryProps -notcontains $_ }
Assert (-not $unknownFieldsS) 'M1: supersession entry uses only schema-defined fields'
Assert ($supersededEntry.source_superseded_by -eq 'REQ-007') 'M2: source_superseded_by field retains source relationship'

# ──────────────────────────────────────────────────────────────
# N  Malformed entry: unknown field would be rejected by additionalProperties: false
# ──────────────────────────────────────────────────────────────
Write-Host "`n[N] Malformed entry: unknown fields rejected"
$unknownField = 'related_decisions'
Assert ($entryProps -notcontains $unknownField) 'N1: related_decisions is NOT in IdMapEntry schema (would be rejected by additionalProperties: false)'
$anotherUnknown = 'dc_source_id_list'
Assert ($entryProps -notcontains $anotherUnknown) 'N2: dc_source_id_list is NOT in IdMapEntry schema (would be rejected)'

# ──────────────────────────────────────────────────────────────
# O  Existing story-spec root required fields unchanged
# ──────────────────────────────────────────────────────────────
Write-Host "`n[O] Existing required fields unchanged"
$rootRequired = $schema.required
Assert ($rootRequired -contains 'module') 'O1: module still required'
Assert ($rootRequired -contains 'title') 'O2: title still required'
Assert ($rootRequired -contains 'user_stories') 'O3: user_stories still required'
Assert ($rootRequired -contains 'status') 'O4: status still required'
Assert ($rootRequired -notcontains 'design_contract_provenance') 'O5: design_contract_provenance not required (backward compatible)'

# ──────────────────────────────────────────────────────────────
# P  Refinement agent owns mapping completion
# ──────────────────────────────────────────────────────────────
Write-Host "`n[P] Refinement agent and skill own mapping completion"
$ra = Get-Content (Join-Path $RepoRoot '.mxagile\agents\refinement-agent.md') -Raw -Encoding UTF8
$rs = Get-Content (Join-Path $RepoRoot '.mxagile\skills\refinement.md') -Raw -Encoding UTF8
Assert ($ra -match 'Design Contract Source-to-Canonical Mapping') 'P1: refinement-agent.md has Design Contract mapping section'
Assert ($ra -match 'PENDING.*reconcilieren|reconcilieren.*PENDING') 'P2: agent doc addresses PENDING entry reconciliation'
Assert ($ra -match 'COLLISION.*canonical ID|neue kanonische ID|allocate.*canonical') 'P3: agent doc addresses COLLISION resolution'
Assert ($ra -match 'CONFIRMED_BY_STAKEHOLDER|bestaettigte.*Quell-Entscheidung') 'P4: agent doc requires confirmed decisions to be canonicalized'
Assert ($ra -match 'Gate.*blockiert|blockiert.*Gate|gate.*NICHT.*bestanden') 'P5: agent doc states gate is blocked by unresolved material mappings'
Assert ($rs -match 'Design Contract Mapping|id_map') 'P6: refinement.md skill references id_map completion'
Assert ($rs -match 'PENDING.*COLLISION|COLLISION.*PENDING') 'P7: refinement.md step mentions PENDING and COLLISION states'

# ──────────────────────────────────────────────────────────────
# Q  Test Contract derivation only after canonical mapping complete
# ──────────────────────────────────────────────────────────────
Write-Host "`n[Q] Test Contract handoff safety"
$tcd = Get-Content (Join-Path $RepoRoot '.mxagile\policies\test-contract-derivation.md') -Raw -Encoding UTF8
Assert ($tcd -match 'canonical requirement.*REQ-NNN\.yml|REQ-NNN\.yml.*canonical') 'Q1: test-contract-derivation.md requires canonical requirement to exist before TC derivation'
Assert ($tcd -match 'requirement_ids.*canonical|canonical.*requirement_ids') 'Q2: requirement_ids in TC must be canonical IDs'
Assert ($tcd -match 'design_contract_elements.*DC source|DC source.*design_contract_elements') 'Q3: DC source IDs go to design_contract_elements, not requirement_ids'

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
