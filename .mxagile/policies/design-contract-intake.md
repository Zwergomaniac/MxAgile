# Design Contract Intake

Policy for consuming a Mocketeer Design Contract v1 as an upstream source during Discovery.
Applied by the Discovery Agent when an HTML mockup containing `id="mocketeer-spec"` is found.

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
- Map `req.id` → provenance in the canonical requirement (field `derivedFrom`).
- Map `req.status` → intake disposition per the table above.
- Do not create canonical REQ-NNN artifacts directly from Design Contract IDs. Discovery produces story specifications; canonical requirements are produced during Refinement.
- Record `design_contract_ref: <mockup.id>@revision=<mockup.revision>` in the story spec.

## Decisions and Business Rules

- `decisions[]` → document in story specification as refinement context with `source: design_contract`.
- `business_rules[]` → record as candidate acceptance criteria with `evidence: static`.
- Open decisions with status OPEN or ASSUMPTION_REQUIRES_APPROVAL → DECISION REQUIRED entries in story spec.

## Mendix Candidates

- `mendix_candidates` with `confirmed: true` → record as model-level hints for Discovery Agent model analysis.
- `confirmed: false` → **do not act on**. Flag as `ASSUMPTION [evidence:static] — unconfirmed technical candidate`. Do not scaffold from unconfirmed candidates.
- Discovery Agent verifies confirmed candidates against mxcli output; contradictions become DECISION REQUIRED.

## Provenance Recording

In the story specification, record:

```yaml
design_contract_provenance:
  mockup_id: <mockup.id>
  revision: <mockup.revision>
  intake_date: <YYYY-MM-DD>
  intake_result: COMPLETE | PARTIAL | FAILED
  partial_reason: <reason when PARTIAL>
```

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
