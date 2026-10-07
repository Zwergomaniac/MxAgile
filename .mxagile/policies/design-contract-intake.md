# Design Contract Intake

Policy for consuming a Mocketeer Design Contract v1 as an upstream source during Discovery.
Applied by the Discovery Agent when an HTML mockup containing `id="mocketeer-spec"` is found.

## Formal Identity Model

Two distinct identity spaces exist when a Design Contract is consumed.

**SOURCE IDENTITY** — the identity of an element as defined by the upstream Design Contract:

```
source_system:   mocketeer
source_artifact: <mockup.id>         # e.g. acme-site-management
source_revision: <mockup.revision>   # e.g. 5
source_type:     requirement | decision | business_rule | role | screen | flow | gap
source_id:       <id>                # e.g. REQ-066, DEC-024
```

**CANONICAL IDENTITY** — the project-owned identity assigned during Refinement:

```
canonical_type:  requirement | decision | ...
canonical_id:    REQ-NNN | DEC-NNN | ...   # assigned by Refinement, never by intake
```

These two spaces are INDEPENDENT. A source `REQ-066` and a canonical `REQ-066` are different
artifacts unless a validated mapping explicitly establishes semantic identity.
**Equal IDs indicate a collision risk, NOT semantic identity.**

**SOURCE ID CONTAINMENT RULE (critical):**

Design Contract source IDs (`REQ-NNN`, `DEC-NNN`, `ROLE-NNN`, `PERM-NNN`, `SCREEN-NNN`)
MUST NOT be written into canonical artifact reference fields. Prohibited writes include:

- `derivedFrom` — only accepts `^PAGE-` IDs; DC source REQ-NNN is NOT a PAGE ID
- `requirement_ids`, `requirements`, `req` — canonical `requirements/REQ-NNN.yml` IDs only
- `acceptance_decisions` and any decision reference field — canonical IDs only
- `related_decisions` — this field does NOT exist in any canonical schema; it is an invented field
  that must never be created with DC source IDs masquerading as canonical IDs
- `specs`, `spec`, `depends_on` — canonical IDs only

The field `traceability.design_contract_elements` in test contract proof points is the ONLY
schema-authorized location for storing DC source IDs in canonical artifacts.

A bare source ID MUST NEVER be interpreted across identity spaces without a validated mapping.

## Prerequisites

Before treating a Design Contract as an intake source:

1. **Locate the contract block** — find `<script type="application/json" id="mocketeer-spec">` in the HTML `<head>`.
2. **Extract and parse JSON** — abort intake if JSON is malformed; record `INTAKE_FAILED: malformed_json`.
3. **Check schema version** — `schema_version` must be `1`. Higher versions: intake as STATIC-level evidence only; record `INTAKE_PARTIAL: unsupported_schema_version`.
4. **Verify minimum structure** — `mockup.id`, `mockup.revision`, `roles`, `requirements` must be present. Any missing: record `INTAKE_PARTIAL: incomplete_contract`.

## Source Priority

A valid Design Contract at revision ≥ 1 ranks as **Source Rank 1.5** (see `policies/source-priority.md`):
- Outranked only by a separate requirements document (Rank 1) when one exists.
- When no separate requirements document exists, treat Design Contract as the primary requirements source.
- When both exist, Design Contract supplements the requirements document; overlapping items follow the concern-based conflict resolution from `source-priority.md`.

## Status Mapping

Map Mocketeer statuses to intake dispositions:

| Design Contract Status | Intake Disposition |
|---|---|
| CONFIRMED_BY_SOURCE | Consume directly; mark `evidence: static` |
| CONFIRMED_BY_STAKEHOLDER | Consume directly; mark `evidence: static` |
| DERIVED | Consume; annotate as `ASSUMPTION [evidence:static]` |
| RECOMMENDATION | Consume as suggestion; flag for DECISION REQUIRED |
| ASSUMPTION_REQUIRES_APPROVAL | DECISION REQUIRED — do not treat as settled |
| CONFLICTING | DECISION REQUIRED — record both positions |
| OPEN | Document as open question; DECISION REQUIRED if blocking |
| ACCEPTED_RISK | Record; no DECISION REQUIRED |
| REJECTED | Do not intake; record as explicitly out-of-scope |
| SUPERSEDED | Do not intake the superseded entry |

## Role Intake

For each role in `roles[]`:
- Create a role entry in the story specification: role ID, label, `can[]`, `cannot[]`.
- `can[]` items map to **positive authorization requirements** — testable via AUTHORIZATION security dimension.
- `cannot[]` items map to **explicit negative authorization requirements** — each becomes a negative proof point in the test contract (role prefix `!ROLE-NNN`).
- Do not infer additional permissions beyond what the contract states.
- If a role appears in `permissions[]` but not in `roles[]`, record as `DECISION REQUIRED`.

## Requirement Intake

For each requirement in `requirements[]`:
- Record `req.id` as source provenance in `design_contract_provenance.id_map` (see SOURCE-TO-CANONICAL MAPPING).
  Do NOT write `req.id` into any canonical artifact field (`derivedFrom`, `requirement_ids`, etc.).
- Map `req.status` → intake disposition per the table above.
- Do not create canonical `REQ-NNN.yml` artifacts directly from Design Contract IDs.
  Discovery produces story specifications; canonical requirements are produced during Refinement.
- Record `design_contract_ref: <mockup.id>@revision=<mockup.revision>` in the story spec.
- When a source requirement has a `superseded_by` relationship pointing to another source ID,
  record both as separate `id_map` entries and record the source-level supersession in the story spec.
  Do not resolve the supersession to canonical IDs here — that happens in Refinement.

## Decisions and Business Rules

- `decisions[]` → document in story specification as refinement context with `source: design_contract`.
  Record each decision in `design_contract_provenance.id_map` with `source_type: decision`.
  Confirmed decisions (CONFIRMED_BY_STAKEHOLDER or CONFIRMED_BY_SOURCE) that materially govern
  a requirement MUST be explicitly dispositioned before intake can be COMPLETE.
  See DECISION IMPORT COMPLETENESS.
- `business_rules[]` → record as candidate acceptance criteria with `evidence: static`.
- Open decisions with status OPEN or ASSUMPTION_REQUIRES_APPROVAL → DECISION REQUIRED entries in story spec.

## Mendix Candidates

- `mendix_candidates` with `confirmed: true` → record as model-level hints for Discovery Agent model analysis.
- `confirmed: false` → **do not act on**. Flag as `ASSUMPTION [evidence:static] — unconfirmed technical candidate`. Do not scaffold from unconfirmed candidates.
- Discovery Agent verifies confirmed candidates against mxcli output; contradictions become DECISION REQUIRED.

## SOURCE-TO-CANONICAL MAPPING

For every imported Design Contract element that participates in canonical processing, maintain
a machine-readable `id_map` in `design_contract_provenance`. The map is populated in two phases:
- **Discovery (intake phase):** source identity is recorded; `canonical_id: null`, status `PENDING`.
- **Refinement:** canonical artifact is created/identified; `canonical_id` is populated, status `MAPPED` or `DIRECT`.

Supported `source_type` values: `requirement`, `decision`, `business_rule`, `role`, `screen`, `flow`, `gap`.

Do not create canonical artifacts for purely informational elements unless framework semantics require them.

`mapping_status` values:

| Status | Meaning |
|---|---|
| `PENDING` | Source element recorded; no canonical artifact exists yet |
| `DIRECT` | Source ID and canonical ID are the same; semantic identity confirmed |
| `MAPPED` | Source ID maps to a different canonical ID (collision or reassignment) |
| `EXCLUDED` | Explicitly excluded with documented justification |
| `COLLISION` | Source ID matches an existing canonical ID that is semantically unrelated |

**COLLISION HANDLING:**
When a source ID is already occupied canonically by an unrelated artifact:
1. Set `mapping_status: COLLISION` for the entry.
2. Allocate a new canonical ID during Refinement (do not renumber the source ID).
3. Preserve the source identity in full.
4. Resolve all imported relationships that reference this source ID through the allocated mapping.
Do not overwrite the existing canonical artifact. Do not treat ID equality as semantic identity.

**SEMANTIC MATCHING:**
Before marking `mapping_status: DIRECT`, confirm that both the source element and the canonical
artifact represent the same real-world decision or requirement. Equal IDs with different content
indicate a COLLISION, not a direct match.

**GENERIC FIXTURE EXAMPLE:**

Source contract: `REQ-001 superseded_by REQ-007`, `DEC-004 governs REQ-007`.
Canonical project already contains unrelated `REQ-007` and `DEC-004`.

Expected `id_map` after intake:

```yaml
id_map:
  - source_type: requirement
    source_id: REQ-001
    canonical_id: null
    mapping_status: PENDING
    source_superseded_by: REQ-007          # source-level supersession preserved
  - source_type: requirement
    source_id: REQ-007
    canonical_id: null                      # new ID will be allocated; not existing REQ-007
    mapping_status: COLLISION
    collision_note: "canonical REQ-007 is unrelated"
  - source_type: decision
    source_id: DEC-004
    canonical_id: null                      # new ID will be allocated; not existing DEC-004
    mapping_status: COLLISION
    collision_note: "canonical DEC-004 is unrelated"
    source_governs: [REQ-007]              # source-level relationship preserved
```

After Refinement allocates new canonical IDs (e.g., `REQ-012` for source `REQ-007`,
`DEC-009` for source `DEC-004`):
- Canonical relationship: `REQ-001` superseded_by `REQ-012`, `DEC-009` governs `REQ-012`.
- Source relationship remains reconstructable from `id_map`.
- No canonical reference points to the pre-existing unrelated `REQ-007` or `DEC-004`.

## CROSS-REFERENCE RESOLUTION

When importing a source relationship (e.g., `req.superseded_by`, `dec.affected_requirements`):

1. **Retain the source reference** with explicit namespace in `id_map` (e.g., `source_superseded_by: REQ-007`).
2. **Resolve the source target** through the `id_map` to find its canonical mapping.
3. **Write a canonical reference** only after a valid canonical mapping (`MAPPED` or `DIRECT`) exists.
4. **If no canonical mapping exists** yet, the canonical reference field remains unpopulated until Refinement.

Never copy a Design Contract ID directly into a canonical reference field because it
syntactically resembles a canonical ID.

Canonical fields that accept only canonical IDs:
- `requirement.derivedFrom` — `^PAGE-` IDs only (never source REQ-NNN)
- `test-contract.requirement_ids` — canonical `REQ-NNN.yml` IDs only
- `revision.acceptance_decisions` — canonical `planning/decisions/DEC-NNN.md` IDs only

## DECISION IMPORT COMPLETENESS

A Design Contract decision with status `CONFIRMED_BY_STAKEHOLDER` or `CONFIRMED_BY_SOURCE`
that materially governs an imported requirement must not remain referenced only through prose.

Before reporting intake `COMPLETE`, the following must hold for every confirmed material decision:

A. **Mapped** to an existing semantically equivalent canonical decision (`mapping_status: DIRECT`); OR  
B. **Imported** as a new canonical decision during Refinement (`mapping_status: MAPPED` with `canonical_id` populated); OR  
C. **Explicitly excluded** with a justified disposition (`mapping_status: EXCLUDED`, `exclusion_reason` populated) that leaves no unresolved canonical reference.

If none of A/B/C applies, the intake MUST NOT return `COMPLETE`.
See INTAKE RESULT SEMANTICS for the appropriate status.

## Provenance Recording

In the story specification, record:

```yaml
design_contract_provenance:
  mockup_id: <mockup.id>
  revision: <mockup.revision>
  source_system: mocketeer
  intake_date: <YYYY-MM-DD>
  intake_result: COMPLETE | PARTIAL | FAILED | TRACEABILITY_ERROR
  partial_reason: <reason when PARTIAL>
  id_map:
    - source_type: requirement | decision | business_rule | role | screen | flow | gap
      source_id: <DC element ID>
      source_revision: <mockup.revision>   # part of source identity; supports multi-revision reconciliation
      canonical_type: requirement | decision | ...
      canonical_id: <canonical ID or null>
      mapping_status: PENDING | DIRECT | MAPPED | EXCLUDED | COLLISION
      collision_note: <when COLLISION>
      exclusion_reason: <when EXCLUDED>
      source_superseded_by: <source ID>    # optional; preserves source supersession chain
      source_governs: [<source IDs>]       # optional; preserves source governance relationships
```

## AC COVERAGE COMPLETENESS

When creating or refining canonical Requirements from a Design Contract source, every
acceptance criterion in the source requirement must be explicitly accounted for.

This is a **semantic completeness guarantee** — counting canonical ACs is not sufficient.
A source requirement with 4 ACs refined into 4 differently-worded canonical ACs may still
lose material constraints if the refinement silently drops or distorts a single AC.

**For every source requirement with acceptance_criteria[]:**

1. For each source AC (identified by `id` or positional index), create a `source_ac_coverage`
   entry in the canonical Requirement with the following disposition:

   | Disposition | Meaning |
   |---|---|
   | `PRESERVED` | Source AC carried into canonical AC with no significant change. `canonical_ac_ids` must reference at least one canonical AC. |
   | `REFINED` | Source AC substantially preserved but re-expressed. Semantic meaning retained. `canonical_ac_ids` must reference the refined canonical AC(s). |
   | `MERGED` | Source AC combined with one or more other source ACs into a single canonical AC. `canonical_ac_ids` references the merged canonical AC. All merged source ACs must each have a `MERGED` entry pointing to the same canonical AC. |
   | `SPLIT` | Source AC expressed as multiple canonical ACs. `canonical_ac_ids` references all resulting canonical ACs. |
   | `NOT_APPLICABLE` | Source AC explicitly excluded. `exclusion_reason` is required and must explain why (e.g. scope boundary, platform ownership, already covered by another canonical artifact). |

2. **Completeness invariant:** Every source AC that is not `NOT_APPLICABLE` must appear in at
   least one canonical AC's `source_ac_ref` field AND must have a `source_ac_coverage` entry.

3. **Detection rule:** A `source_ac_coverage` array whose length differs from the source
   requirement's `acceptance_criteria` count is a coverage deficit signal. However, equal
   counts do NOT guarantee coverage — each entry must be semantically verified.

4. **Validation gate:** Before Refinement may accept a canonical Requirement as complete,
   every source AC in the Design Contract must have a `source_ac_coverage` entry with a
   non-null `disposition`. A missing or incomplete `source_ac_coverage` when the Requirement
   was derived from a Design Contract is a `TRACEABILITY_ERROR`.

5. **Backward compatibility:** Requirements without `source_ac_coverage` remain valid.
   The field is required only when `source: native` and the Requirement was derived from a
   Design Contract (i.e. `design_contract_provenance` is present in the parent story-spec).
   Requirements with `source: migrated` or `source: legacy` are exempt.

See `schemas/requirement.schema.json` for the `source_ac_coverage` field definition.

## DECISION QUALIFICATION

Not every observation in a Design Contract represents a canonical Decision. Promoting
mockup observations and implementation wording into canonical Decisions without sufficient
justification inflates the decision backlog and creates false DECISION REQUIRED blockers.

**A Design Contract element should be promoted to a canonical Decision (DEC-NNN) if and only
if ALL of the following criteria are satisfied:**

1. **Meaningful choice exists between alternatives.**
   There must be at least two viable alternatives that a product owner could reasonably choose.
   If only one option makes sense given the constraints, it is not a decision — it is a
   derivable fact.

2. **Choice represents product/business/stakeholder intent.**
   The choice must originate from a stakeholder preference, business rule, or product strategy —
   not merely from the UI appearance or the technical implementation mechanism.
   "Button is blue" is not a decision; "primary action uses the brand color" may be if a
   meaningful alternative exists.

3. **Choice is implementation-independent.**
   The decision must remain meaningful independently of the concrete implementation
   mechanism, widget, or framework. A choice that changes only the technical realization
   without affecting observable behavior is implementation detail, not a canonical Decision.

4. **Choice is not already expressed as a canonical Requirement or business rule.**
   If the substance of the choice is already captured in a Requirement's acceptance criteria
   or business_rules[], creating a separate Decision duplicates the canonical source.
   Reference the existing Requirement instead.

**Non-decision examples (do not promote):**

- Widget selection: "We use a DataGrid here" — implementation detail
- Cosmetic appearance derived from DS conventions: "Buttons follow Atlas style" — framework default
- Behavior derivable from requirements: "Clicking Save validates first" — expressed in AC-003
- Single-option constraint: "Admin can delete records" with no alternative — becomes a Requirement

**Decision examples (promote):**

- Data retention period: 30 days vs 90 days vs user-configurable — meaningful alternatives, product intent
- Role can self-assign: YES vs NO with different access implications — stakeholder choice, implementation-independent
- Multi-tenancy scope: per-center vs per-team — materially different architectures, product-driven

**Checklist behavior:** Use this as a review boundary before creating DEC-NNN artifacts.
When a Design Contract element satisfies fewer than all four criteria, record it as a
Requirement, business rule, or open question instead.

## STRUCTURED ACCESS SEMANTICS

When a Design Contract's `can[]` or `cannot[]` lists express access with navigation/visibility
semantics distinct from data authorization, structured `access_dimensions` may be recorded on
the corresponding Test Contract proof points.

**Access dimension vocabulary (organization-neutral):**

| Dimension | Meaning |
|---|---|
| `VISIBLE` | Role can see the element/screen/data without necessarily being able to interact with it. |
| `NAVIGABLE` | Role can navigate to the screen/element without mutation authority — read-only navigation. |
| `READ` | Role can read/inspect data records. |
| `WRITE` | Role can create or modify records. |
| `MANAGE` | Role has administrative or lifecycle-control authority over a resource. |
| `PLATFORM_OWNED` | Access governed by an external platform module — not tested at application level; out of scope for TC. |

**Usage rules:**

- `access_dimensions` is OPTIONAL on proof points. Absent means "not structured."
- Multiple dimensions may apply to one proof point.
- `NAVIGABLE` without `WRITE` represents a read-only navigation claim — distinct from `WRITE`.
- `PLATFORM_OWNED` means the access concern is excluded from MxAgile TC scope; record the
  exclusion explicitly rather than silently omitting the proof point.
- Do not encode company-specific or project-specific role names in dimension names.
- Backward compatible — existing proof points without `access_dimensions` remain valid.

See `schemas/test-contract.schema.json` for the `access_dimensions` field definition.

## CANONICAL ID DISCOVERY

Before allocating new canonical IDs (REQ-NNN, DEC-NNN, etc.) during Refinement, the
occupied ID space must be derived deterministically from canonical artifacts — not from
memory, manual counters, or an independent registry.

**Authoritative ID discovery algorithm:**

```
Occupied REQ IDs: scan requirements/*.yml, extract ID fields
Occupied DEC IDs: scan planning/decisions/DEC-NNN.md and planning/decisions/DEC-NNN.yml files
Occupied TC IDs:  scan planning/test-contracts/TC-NNN.yaml, extract ID fields
Occupied VPL IDs: scan planning/verification-plans/VPL-NNN.yaml
```

If `scripts/build_artifact_index.py` is available and the graph state is READY, query:
`python scripts/build_artifact_index.py` to obtain the artifact index — this is faster but
not the authoritative source. The canonical artifact files are always authoritative.

**Allocation rules:**

1. The NEXT available ID is `MAX(occupied) + 1` for the namespace.
2. IDs are NEVER recycled from deleted artifacts.
3. A collision registry entry (`mapping_status: COLLISION`) does NOT allocate the new canonical
   ID — it only records that one is needed. Allocation happens explicitly during Refinement.
4. After allocation, verify that no existing canonical artifact in `requirements/`, `planning/`,
   etc. already uses the allocated ID before writing the new artifact.
5. An `id_map` entry pointing to a canonical ID that does not exist as a file is a
   `TRACEABILITY_ERROR`.

**Consistency validation (run before Refinement gate):**

| Check | Pass condition |
|---|---|
| All `MAPPED` id_map entries resolve to real canonical artifacts | `canonical_id` file exists at expected path |
| All `DIRECT` id_map entries have semantically confirmed identity | canonical artifact content confirms match |
| No two `MAPPED`/`DIRECT` entries map to the same canonical ID | 1:1 canonical ID uniqueness |
| No `COLLISION` entry has `canonical_id` populated before Refinement allocation | allocation only during Refinement |
| After Refinement: no `PENDING` entry remains for material confirmed elements | all confirmed material elements dispositioned |

## INTAKE VALIDATION

Before Discovery intake may report `COMPLETE`, validate all of the following:

1. Every canonical reference field in story spec entries contains a canonical ID or null — never a DC source ID.
2. Every source relationship target in the Design Contract exists as a source element within the same contract.
3. Every source-to-canonical mapping (`MAPPED` or `DIRECT`) resolves to a real canonical artifact.
4. Every confirmed (`CONFIRMED_BY_STAKEHOLDER` or `CONFIRMED_BY_SOURCE`) material decision is dispositioned (A, B, or C in DECISION IMPORT COMPLETENESS).
5. No source ID is written as a canonical ID without a validated `DIRECT` mapping entry.
6. No ID collision is silently treated as identity — all collisions have `mapping_status: COLLISION` in `id_map`.
7. Source supersession chains are recorded in `id_map` as `source_superseded_by` entries.
8. Prose alone is not the sole holder of a required source-to-canonical mapping.
9. Every canonical Requirement derived from a Design Contract has a `source_ac_coverage` entry for every material source AC. Missing or incomplete `source_ac_coverage` when source ACs exist is a `TRACEABILITY_ERROR`. (See AC COVERAGE COMPLETENESS.)

## INTAKE RESULT SEMANTICS

| Condition | Result |
|---|---|
| All validation checks pass | `COMPLETE` |
| JSON malformed | `INTAKE_FAILED: malformed_json` |
| Unsupported schema version | `INTAKE_PARTIAL: unsupported_schema_version` |
| Missing required top-level fields | `INTAKE_PARTIAL: incomplete_contract` |
| Confirmed material decision with no canonical disposition | `TRACEABILITY_ERROR` |
| Source-to-canonical mapping unresolvable | `TRACEABILITY_ERROR` |
| ID collision detected without new canonical allocation | `TRACEABILITY_ERROR` |
| Sufficient content with minor gaps | `PARTIAL` (with `partial_reason`) |

**A `TRACEABILITY_ERROR` blocks Refinement from starting.** The error must be resolved before
the intake can be upgraded to `COMPLETE` or `PARTIAL`. Refinement must not begin with a known
wrong canonical reference.

`BLOCKED`, `PARTIAL`, `DECISION_REQUIRED` are all valid states that allow selective continued work.
`TRACEABILITY_ERROR` is distinct: it indicates a semantic cross-reference defect that, if ignored,
would cause a downstream canonical artifact to reference the wrong entity.

## Preservation Warning

The Discovery Agent MUST NOT modify the HTML mockup or its embedded Design Contract.
The mockup is a Rank 1.5 source — read-only during intake. Any suggested changes go to the backlog as stakeholder feedback, not as agent edits.

## Operation-Level Capability Intake

Design Contract v1 `can[]` and `cannot[]` express capabilities that may imply operations.

During intake, map capabilities to standard operations (READ/CREATE/UPDATE/DELETE/EXECUTE) only
when the capability name or context makes the mapping **unambiguous**. Do not infer operation
relationships from other operations.

**Inference prohibition (strictly enforced):**
- `cannot[CAP-UPDATE]` does NOT imply `cannot[CAP-READ]`
- `can[CAP-READ]` does NOT imply `can[CAP-UPDATE]`
- `cannot[CAP-DELETE]` does NOT imply `cannot[CAP-CREATE]`
- Each operation's disposition must be independently derived from the canonical source

**Authorization disposition per capability entry:**
- Entry in `can[]`: `authorization_disposition: REQUIRED` for the stated capability/operation
- Entry in `cannot[]`: `authorization_disposition: EXPLICITLY_FORBIDDEN` for the stated capability/operation
- Not mentioned in either list: `authorization_disposition: UNSPECIFIED` — never infer FORBIDDEN

When a capability name does not map unambiguously to a standard operation:
- Record the capability as-is without an `operation` field
- Mark `authorization_disposition: UNSPECIFIED` for all operations not explicitly covered
- Let Test Contract derivation make the explicit operation assignment when needed

## Test Contract Generation Trigger

When intake is COMPLETE (or PARTIAL with sufficient content), the Discovery Agent signals the
`skills/test-contract.md` skill that a Design Contract is available as upstream source.
The test contract derivation uses the `roles[]`, `requirements[]`, and `permissions[]` arrays
to generate proof points. See `policies/test-contract-derivation.md`.

## Maturity Assessment Intake

When the Design Contract contains an `assessment` block, consume it as upstream evidence.

### Readiness Mapping

| `development_handoff_readiness` | MxAgile behavior |
|---|---|
| `HANDOFF_READY` | Proceed with higher confidence; fewer gaps expected |
| `REFINEMENT_REQUIRED` | Import available content; route unresolved gaps to Refinement |
| `PROTOTYPE_READY` | Import what is available; expect significant Discovery work |
| `BLOCKED` | Surface material blockers explicitly; do not advance past Discovery until resolved |
| absent / legacy | Treat as unassessed; apply standard intake rules. Do not infer HANDOFF_READY |

`HANDOFF_READY` is upstream evidence — it does NOT bypass any MxAgile lifecycle gate.
MxAgile gates remain the authoritative decision point for development lifecycle progression.

### Gap Mapping

Map unresolved gaps (`resolution_state: OPEN`) to MxAgile refinement concepts.
Preserve the original `gap_ref` in any DECISION REQUIRED or open question entry.

| Gap category | MxAgile routing |
|---|---|
| `MISSING_BUSINESS_RULE` | Refinement open question / DECISION REQUIRED |
| `AMBIGUITY` | DECISION REQUIRED |
| `CONFLICT` | Source conflict — DECISION REQUIRED (both positions) |
| `SECURITY_UNCLEAR` | Role/security refinement input |
| `INCOMPLETE_DATA_SCOPE` | Security/role clarification — may affect negative proof points |
| `UNTESTABLE_REQUIREMENT` | Testability concern in Test Contract derivation |
| `INCOMPLETE_ROLE_CAPABILITY` | Role contract gap; affects can/cannot proof points |
| `MISSING_VALIDATION` | Refinement open question |
| `MISSING_EDGE_CASE` | Refinement checklist item |
| Visual / cosmetic gaps | Do not automatically block Testability Gate — minor visual preferences are not Testability blockers |

### Dimension Status Intake

Dimensions with `BLOCKED` or `CONFLICTING` status warrant DECISION REQUIRED entries.
Dimensions with `PARTIAL` status may proceed but record the partial coverage explicitly.
Dimensions with `UNEXPLORED` status — record as open question; do not assume SUFFICIENT.

### Provenance Extension

Extend the `design_contract_provenance` record when an assessment block is present:

```yaml
design_contract_provenance:
  mockup_id: <mockup.id>
  revision: <mockup.revision>
  intake_date: <YYYY-MM-DD>
  intake_result: COMPLETE | PARTIAL | FAILED
  partial_reason: <reason when PARTIAL>
  maturity_assessed: true | false          # provenance: prototype_readiness captured when maturity_assessed=true
  prototype_readiness: <value if present>  # provenance records prototype_readiness from assessment
  development_handoff_readiness: <value if present>
  blocking_gaps: [<gap_ids>]
```

### Reconciliation on Later Revision

When a new mockup revision arrives:
1. Re-run intake with the updated `mockup.revision`.
2. Compare `assessment.gaps` — OPEN → RESOLVED transitions may close story-spec open questions.
3. New or reopened gaps → mark affected Requirements/Test Contracts IMPACTED per `policies/test-staleness.md`.
4. Do not reset unrelated confirmed MxAgile work; scope changes to affected stories only.

## BACKWARD COMPATIBILITY

Existing consumer artifacts may contain an older `design_contract_ref` representation:

```yaml
design_contract_ref:
  dc_id: <DC element ID>
  revision: <N>
  mockup_id: <mockup.id>
```

Interpret this format as: `source_id: <dc_id>`, `source_revision: <revision>`, `source_artifact: <mockup_id>`.
Do not silently assume a bare `related_decisions` or `refs` entry came from the Design Contract.

When ambiguity cannot be resolved — for example, a bare `REQ-NNN` in an existing artifact with no
surrounding context identifying whether it is a DC source ID or a canonical ID — report as
**migration/traceability debt**. Do not automatically rewrite the artifact; surface the debt for
explicit resolution. Project-authored prose in unknown state must not be auto-migrated.
