# MxAgile Canonical Artifact Schemas

**This document is the authoritative contract for MxAgile lifecycle artifacts.**

Schemas are implemented as JSON Schema files in `.mxagile/schemas/`.
All producers (templates, agents, conversion tools) and all consumers
(build_artifact_index.py, analyze.py, converge.py, etc.) must conform to these schemas.

---

## Design principles

1. **One canonical format per artifact type.** No parallel `.md`/`.yml` representations.
2. **`ID` is the primary key.** Uppercase. Must match the filename stem exactly.
   `requirements/REQ-042.yml` → `ID: REQ-042`.
3. **File extension is `.yml`** for all indexed artifacts.
4. **Indexer reads `ID`, relationship fields, and `action` (tasks).** All other fields
   are preserved in `content` and available to downstream tools.
5. **`additionalProperties: false`** is enforced by the schema to prevent silent drift.
6. **Provenance fields** (`source`, `migrated_from`, `migration_date`) are included in
   the schema — not bolted on after the fact.

---

## Requirement (`requirements/REQ-NNN.yml`)

Schema: `.mxagile/schemas/requirement.schema.json`

Represents an atomic, testable, traceable requirement.

**Required fields:**

| Field | Type | Description |
|---|---|---|
| `ID` | string | `REQ-NNN` pattern. Must match filename stem. |
| `title` | string | Short one-line title. |
| `description` | string | User story (`As a... I want... so that...`) or declarative statement. |

**Important optional fields:**

| Field | Type | Description |
|---|---|---|
| `status` | `draft\|accepted\|deferred\|superseded` | Default: `draft`. |
| `source` | `native\|legacy\|migrated` | Provenance. |
| `derivedFrom` | string (`PAGE-...`) | Page ID → creates `DERIVED_FROM` edge in artifact index. |
| `target_users` | array of `{role, description}` | Affected user roles. |
| `acceptance_criteria` | array of `{id, given, when, then}` | Testable ACs. |
| `business_rules` | array of `{id, rule, entity}` | Business constraints. |
| `business_context` | string | What problem this solves. |
| `out_of_scope` | array of strings | Explicit exclusions. |
| `open_items` | array of strings | Unresolved DECISION REQUIRED items. |
| `migrated_from` | string | Source path for migrated artifacts. |
| `migration_date` | string (YYYY-MM-DD) | Conversion date. |

**Artifact index consumption:**
- `ID` → primary key (falls back to filename stem)
- `derivedFrom` → `DERIVED_FROM` edge: Page → Requirement

**Example:**
```yaml
# Schema: .mxagile/schemas/requirement.schema.json
ID: REQ-001
title: "Customer order list"
description: "As a Customer, I want to see my recent orders, so that I can track delivery status."
status: accepted
source: native
derivedFrom: PAGE-001
target_users:
  - role: Customer
    description: "Views own orders only"
acceptance_criteria:
  - id: AC-001
    given: "Customer is logged in"
    when: "Customer opens the dashboard"
    then: "A list of their last 10 orders is displayed"
business_rules:
  - id: BR-001
    rule: "Only orders belonging to the logged-in customer are shown"
    entity: "Order"
open_items: []
```

---

## Spec (`specs/SPEC-NNN.yml`)

Schema: `.mxagile/schemas/spec.schema.json`

Represents a feature specification grouping one or more requirements into a logical
unit of work. A spec that is `status: accepted` authorises downstream task creation.

**Required fields:**

| Field | Type | Description |
|---|---|---|
| `ID` | string | `SPEC-NNN` pattern. Must match filename stem. |
| `title` | string | Short feature title. |
| `description` | string | High-level description of the feature and its value. |
| `requirements` | array of `REQ-...` strings | Min 1. Creates `IMPLEMENTED_BY` edges. |

**Important optional fields:**

| Field | Type | Description |
|---|---|---|
| `status` | `draft\|accepted\|superseded` | Default: `draft`. |
| `behavior` | string | Detailed behavior description (what, not how). |
| `business_rules` | array of strings | Feature-level business rules. |
| `out_of_scope` | array of strings | Explicit exclusions. |
| `open_items` | array of strings | Unresolved items. |
| `migrated_from` / `migration_date` | string | Provenance for migrated specs. |

**Artifact index consumption:**
- `ID` → primary key
- `requirements` list → `IMPLEMENTED_BY` edges: Requirement → Spec

**Example:**
```yaml
# Schema: .mxagile/schemas/spec.schema.json
ID: SPEC-001
title: "Recent Orders Widget"
description: "Build the 'Recent Orders' widget on the customer dashboard."
status: accepted
requirements:
  - REQ-001
behavior: >-
  The dashboard page displays a list of the customer's last 10 orders.
  Each row shows order number, date, and status. Clicking a row navigates
  to the order detail page.
business_rules:
  - "Show maximum 10 orders, sorted by date descending"
  - "Filter by logged-in customer account"
out_of_scope:
  - "Order cancellation is handled by a separate spec"
open_items: []
```

---

## Task (`planning/tasks/TASK-NNN.yml`)

Schema: `.mxagile/schemas/task.schema.json`

Represents a concrete, actionable implementation task.

**Required fields:**

| Field | Type | Description |
|---|---|---|
| `ID` | string | `TASK-NNN` pattern. Must match filename stem. |
| `spec` | string (`SPEC-...`) | Parent spec. Creates `IMPLEMENTED_BY` edge: Spec → Task. |
| `action` | string | Short description. Used as display name in the artifact index. |

**Important optional fields:**

| Field | Type | Description |
|---|---|---|
| `req` | array of `REQ-...` strings | Direct requirement references. |
| `type` | enum | Mendix artifact category. |
| `detail` | string | Detailed implementation notes. |
| `status` | enum | Default: `pending`. |
| `depends_on` | array of `TASK-...` strings | Prerequisite tasks. |
| `test` | object `{role, steps, expected}` | Acceptance test. |
| `inspect` | object `{microflow, expect}` | mxcli model verification. |
| `migrated_from` / `migration_date` | string | Provenance for migrated tasks. |

**Artifact index consumption:**
- `ID` → primary key
- `spec` → `IMPLEMENTED_BY` edge: Spec → Task
- `action` → display name (falls back to `description` for backward compatibility)

**Example:**
```yaml
# Schema: .mxagile/schemas/task.schema.json
ID: TASK-001
spec: SPEC-001
req:
  - REQ-001
type: microflow
action: "Create datasource microflow for recent orders list"
detail: >-
  Create ACT_GetRecentOrders in the CustomerPortal module.
  Use XPath constraint $currentUser/Account = [%CurrentUser%].
  Limit result to 10 records, sorted by DeliveryDate descending.
status: pending
depends_on: []
test:
  role: Customer
  steps:
    - open: CustomerPortal.CustomerDashboard_Overview
  expected: "Recent orders list shows at most 10 rows belonging to the current user"
```

---

## Page (`pages/PAGE-NNN.yml`)

Schema: `.mxagile/schemas/page.schema.json` (existing)

See `page.schema.json` for the full field list. The Page artifact participates in
traceability as the upstream source of requirements.

**Artifact index consumption:**
- `page_id` field is read as `ID` (note: page.schema.json uses `page_id`, not `ID`)
- Pages create `DERIVED_FROM` edges when requirements reference them via `derivedFrom`

---

## Traceability chain

```
pages/PAGE-NNN.yml
    |  (derivedFrom)
    v  DERIVED_FROM edge
requirements/REQ-NNN.yml
    |  (requirements list in spec)
    v  IMPLEMENTED_BY edge
specs/SPEC-NNN.yml
    |  (spec field in task)
    v  IMPLEMENTED_BY edge
planning/tasks/TASK-NNN.yml
    |
    v  (artifact index)
.mxagile/state/artifact-index.json
```

---

## ID rules

| Artifact | Pattern | Example | Filename |
|---|---|---|---|
| Requirement | `REQ-NNN` (min 3 digits) | `REQ-001` | `requirements/REQ-001.yml` |
| Spec | `SPEC-NNN` (min 3 digits) | `SPEC-001` | `specs/SPEC-001.yml` |
| Task | `TASK-NNN` (min 3 digits) | `TASK-001` | `planning/tasks/TASK-001.yml` |
| Page | `PAGE-...` | `PAGE-01` | `pages/PAGE-01.yml` |

IDs are stable: once assigned, they do not change even if the artifact is moved or
superseded. The `status` field handles lifecycle transitions.

---

## Design Contract Source Identity and Canonical Mapping

When a Mocketeer Design Contract is consumed during Discovery, two identity spaces coexist.
Understanding the boundary prevents semantic cross-reference defects.

### Two Identity Namespaces

**Source Identity** (Design Contract namespace):
```
source_system:   mocketeer
source_artifact: <mockup.id>
source_revision: <mockup.revision>
source_type:     requirement | decision | role | screen | flow | gap
source_id:       REQ-066 | DEC-024 | ROLE-MANAGER | ...
```

**Canonical Identity** (project namespace):
```
canonical_type:  requirement | decision | ...
canonical_id:    REQ-068 | DEC-031 | ...   (assigned in Refinement)
```

A source `REQ-066` and a canonical `REQ-066` are DIFFERENT artifacts.
Equal IDs indicate a collision risk, NOT semantic identity.

### Source-to-Canonical Mapping

The mapping lives in `design_contract_provenance.id_map` within the story spec produced by Discovery.
It is populated incrementally:
- Discovery: source side complete; canonical side null / PENDING.
- Refinement: canonical artifacts created; `id_map` entries updated to MAPPED or DIRECT.

The artifact trace index (`.mxagile/state/artifact-index.json`) records relationships within the
canonical namespace. Source-level relationships are preserved in `id_map` entries
(`source_superseded_by`, `source_governs`) so the source graph remains reconstructable.

### Collision Handling

When a Design Contract source ID is already occupied canonically by an unrelated artifact:

1. Set `mapping_status: COLLISION` with `collision_note`.
2. During Refinement, allocate a new canonical ID (e.g., source `REQ-007` → canonical `REQ-012`).
3. Preserve source identity; do not renumber source IDs.
4. Resolve all relationships referencing this source ID through the allocated mapping.

### Source ID Containment — Where DC Source IDs May and May Not Appear

| Location | May contain DC source IDs? | Notes |
|---|---|---|
| `design_contract_provenance.id_map[].source_id` | YES | The designated store |
| `test-contract.proof_points[].traceability.design_contract_elements` | YES | Per proof point |
| `design_contract_ref` (any artifact) | YES — partial | `<mockup.id>@revision=<N>` only, not element IDs |
| `requirement.derivedFrom` | NO | `^PAGE-` IDs only |
| `test-contract.requirement_ids` | NO | Canonical `REQ-NNN.yml` IDs only |
| `revision.acceptance_decisions` | NO | Canonical `planning/decisions/DEC-NNN.md` IDs only |
| Any invented field (`related_decisions`, etc.) | NO | Not a valid schema field in any canonical artifact |

### Intake Failure Semantics

A confirmed Design Contract decision (`CONFIRMED_BY_STAKEHOLDER` / `CONFIRMED_BY_SOURCE`) that
materially governs an imported requirement must be dispositioned before intake reports `COMPLETE`.
Valid dispositions: DIRECT mapping to existing canonical decision, MAPPED (new canonical decision
created in Refinement), or EXCLUDED (with explicit justification).

If an undispositioned confirmed material decision exists, intake reports `TRACEABILITY_ERROR`.
Refinement MUST NOT start with a known wrong or unresolved canonical reference.

### Concise Worked Example

Source contract `acme/rev5`:
- `REQ-001` (superseded_by `REQ-007`) → story spec entry, `id_map PENDING`
- `REQ-007` → collision with canonical `REQ-007` (unrelated) → `id_map COLLISION`
- `DEC-004` governs `REQ-007` → collision with canonical `DEC-004` (unrelated) → `id_map COLLISION`

After Refinement:
- Source `REQ-001` → canonical `REQ-001` (DIRECT, same content)
- Source `REQ-007` → canonical `REQ-012` (MAPPED, new allocation due to collision)
- Source `DEC-004` → canonical `DEC-009` (MAPPED, new allocation due to collision)
- Canonical `REQ-012` has `superseded_by: REQ-001` (resolved from source `REQ-001`)
- Canonical `DEC-009` governs `REQ-012` (resolved from source mapping)
- Pre-existing canonical `REQ-007` and `DEC-004` untouched.

Full policy: `.mxagile/policies/design-contract-intake.md`.

---

## Legacy and migration

Legacy DFC-AI artifacts at `planning/stories/REQ-*.md` are NOT indexed by
`build_artifact_index.py`. They must be converted by `scripts/canonicalize_artifacts.py`
(orchestrated via `scripts/migrate-stories.ps1`) to produce canonical `.yml` files.

A project is not fully native until `artifact_canonicalization: complete` in
`.mxagile/migration/state.yaml`.

See `.mxagile/skills/migration.md` for the canonicalization lifecycle.

---

## Producer/consumer alignment

| Component | Produces | Consumes | Status |
|---|---|---|---|
| `templates/generic/requirements/template.yml` | `requirements/*.yml` | — | canonical |
| `templates/generic/specs/template.yml` | `specs/*.yml` | — | canonical |
| `templates/generic/tasks/template.yaml` | `planning/tasks/*.yml` | — | canonical |
| `templates/generic/requirements/template.md` | `planning/stories/*.md` | — | discovery authoring format, not indexed |
| `scripts/build_artifact_index.py` | `.mxagile/state/artifact-index.json` | `requirements/*.yml`, `specs/*.yml`, `planning/tasks/*.yml`, `pages/*.yml` | aligned |
| `scripts/canonicalize_artifacts.py` | `requirements/*.yml`, `planning/tasks/*.yml` | `planning/stories/*.md`, `planning/checklists/*.yaml` | canonical converter |
| `scripts/migrate-stories.ps1` | — | calls `canonicalize_artifacts.py` | orchestrator |
| `.mxagile/skills/migration.md` | — | describes canonicalization process | aligned |
| `docs/schemas.md` | — | authoritative contract | this document |
