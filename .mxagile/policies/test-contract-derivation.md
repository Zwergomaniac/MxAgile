# Test Contract Derivation

Policy for deriving a Test Contract (TC-NNN) from requirement acceptance criteria and an optional
Mocketeer Design Contract. Applied by `skills/test-contract.md`.

## Inputs

1. **Canonical requirement** (`requirements/REQ-NNN.yml`) — primary source. Must have at least one `acceptance_criteria` entry (Given/When/Then).
2. **Mocketeer Design Contract** (optional) — `id="mocketeer-spec"` JSON from intake. Enriches roles, permissions, and element-level traceability. See `policies/design-contract-intake.md`.

## Design Contract Source ID Containment

When a Design Contract is the upstream source, DC source IDs and canonical IDs occupy **separate namespaces** (see `policies/design-contract-intake.md` — Formal Identity Model). The test contract schema enforces this separation:

- **`requirement_ids`** — must contain ONLY canonical `requirements/REQ-NNN.yml` IDs.
  A test contract can only be derived AFTER a canonical requirement exists (produced in Refinement).
  Never write a DC source `REQ-NNN` value into `requirement_ids`.

- **`traceability.design_contract_elements`** (per proof point) — this is the ONLY location
  where DC source IDs (`REQ-NNN`, `DEC-NNN`, `PERM-NNN`, `ROLE-NNN`) may appear in a test contract.
  Use it to preserve the DC element IDs that each proof point originates from.

- **`design_contract_ref`** — stores `<mockup.id>@revision=<N>` (the overall contract reference).
  Not for individual DC element IDs.

The mapping from DC source ID to canonical ID must be resolved through
`design_contract_provenance.id_map` in the story spec before populating `requirement_ids`.
If no canonical mapping exists for a DC source ID yet, the test contract MUST NOT be created
for that requirement — wait until Refinement completes the canonical artifact and updates `id_map`.

**Example proof point with correct source provenance:**

```yaml
proof_points:
  - id: PP-001
    claim: "A ROLE-MANAGER user can create a site record."
    role: ROLE-MANAGER
    data_state: empty
    required_layers: [MODEL, RUNTIME]
    traceability:
      acceptance_clause_id: AC-001
      design_contract_elements: [REQ-066, DEC-024]   # DC source IDs — NOT canonical IDs
```

The canonical `requirement_ids` in the same contract references `REQ-068` (canonical), not `REQ-066`.

## Derivation Rules

### One test contract per requirement group

A test contract covers ONE requirement or a logically cohesive group of requirements that share
the same acceptance scope (e.g. a create + validation pair). Do not bundle unrelated requirements
into a single contract — it makes failure diagnosis ambiguous.

### One proof point per acceptance clause + role combination

For each AC in `acceptance_criteria`:
- If the AC involves a specific role: create one proof point per role in scope.
- If the AC is role-agnostic: create one proof point using role `ANY_AUTHENTICATED`.
- If a Design Contract is available and the AC maps to a capability (`can[]`): derive the role from the Design Contract's role definition.

### Negative proof points from `cannot[]`

For each entry in a role's `cannot[]`:
- Create a negative proof point with `role: !ROLE-NNN`.
- Assign `security_dimensions: [VISIBILITY, AUTHORIZATION]` (at minimum).
- `claim`: "A [role] user cannot [action]."
- Required layers: at minimum `[MODEL, FRONTEND]`.

### Layer assignment defaults

| Scenario type | Default required_layers |
|---|---|
| UI interaction (page, button, form) | MODEL, RUNTIME, FRONTEND |
| Business rule / validation | MODEL, RUNTIME |
| Calculation / aggregation | MODEL, BUILD |
| Navigation / accessibility | MODEL, FRONTEND |
| Role-restricted visibility | MODEL, FRONTEND |
| Authorization (execute) | MODEL, RUNTIME |
| Data scope / XPath filter | MODEL, RUNTIME, FRONTEND |
| Static structural presence | STATIC, MODEL |

These are defaults. The Verification Plan (VPL) overrides them with justified layer decisions.

### Security dimension assignment

Assign `security_dimensions` based on what the proof point exercises:

| What is tested | Dimensions |
|---|---|
| Whether a UI element is shown / hidden per role | VISIBILITY |
| Whether a page or action can be reached at all | ACCESSIBILITY |
| Whether the system allows or blocks an action when executed | AUTHORIZATION |
| Whether the user sees only their permitted data | DATA_SCOPE |

Multiple dimensions may apply. Assign all that are relevant — they are independent, not a hierarchy.
See `policies/verification-layers.md` for full dimension semantics.

### Proof point ID assignment

Assign sequential PP-NNN IDs within the contract. IDs must be stable once assigned.
Do not reuse or renumber IDs when adding new proof points — append new PP-NNN at the end.

## Testability Classification

Before finalizing the contract, classify each proof point:

- **TESTABLE_AUTO**: All required layers can run via mxcli / Playwright with current tooling.
- **TESTABLE_MANUAL**: At least one required layer requires human action (e.g. physical device, external system not available in test environment).
- **NOT_APPLICABLE**: Proof point is described but not applicable to the current wave scope. Set `status: not_applicable`.
- **INFRASTRUCTURE_GAP**: Required layer exists in policy but tooling is not configured. Record as a gap; do not block gate — flag for resolution.

## Operation-Level Proof Points

When requirements or Design Contract specify per-operation permissions, create operation-aware proof points.

### Standard Operations

| Operation | Meaning in Mendix context |
|---|---|
| READ | Can view/query entity instances |
| CREATE | Can create new entity instances |
| UPDATE | Can modify existing entity instances |
| DELETE | Can delete entity instances |
| EXECUTE | Can call a microflow / trigger an action |

Domain-specific operations are allowed when the application domain requires them.

### Derivation Rules for Operations

For each [role + resource + operation] tuple that has an explicit disposition:
1. Create a dedicated proof point
2. Set `operation` to the specific operation value
3. Set `authorization_disposition` per the canonical source:
   - From Design Contract `can[]` → `REQUIRED`
   - From Design Contract `cannot[]` → `EXPLICITLY_FORBIDDEN`
   - Not mentioned → `UNSPECIFIED`
4. Assign `required_layers` based on operation type:
   - READ/WRITE operations on entities → MODEL + RUNTIME
   - EXECUTE (microflow action) → MODEL + RUNTIME
   - UI-level action visibility → MODEL + FRONTEND
   - Data scope per operation → MODEL + RUNTIME + FRONTEND (DATA_SCOPE dimension)

### Inference Prohibition

These inferences are strictly forbidden:
- `CANNOT UPDATE` does NOT imply `CANNOT READ`
- `CAN READ` does NOT imply `CAN UPDATE`
- `CANNOT DELETE` does NOT imply `CANNOT CREATE`

Each operation's disposition must be independently derived from the canonical source.
When the source is silent about a specific operation: `authorization_disposition: UNSPECIFIED`.

### Holistic vs. Operation-Aware

When the canonical source does not distinguish operations (e.g. `can[CAP-SITE-MANAGE]` without
operation breakdown): create a holistic proof point without `operation` field.

Operation-aware proof points coexist with holistic ones. An AC may produce one holistic proof point
plus several operation-specific ones when the source provides that level of detail.

## Preservation Rule

Once a proof point is `active`, its `id` and `claim` must not change.
If the claim changes (requirement revised), set `status: stale`, add `staleness_cause: ACCEPTANCE_CRITERIA_CHANGED`,
and create a new proof point with the updated claim. Preserve the old proof point as stale.

## Output Location

Canonical location: `planning/test-contracts/TC-NNN.yaml`
Temporary scratch during derivation: `.concord/scratch/tc-draft-<wave>.yaml` (gitignored)

## Testability Gate (gate-to-ready)

gate-to-ready checks that for each REQ-NNN in scope:
- A test contract exists (`planning/test-contracts/TC-NNN.yaml`)
- The contract has status `draft` or `active` (not `stale` or `superseded`)
- Each proof point has a testability classification

If no test contract exists:
- The gate allows proceeding ONLY if `testability: NOT_APPLICABLE` or `testability: MANUAL_ONLY`
  is recorded in the checklist item with an explicit justification.
- Undocumented absence is a gate blocker.
