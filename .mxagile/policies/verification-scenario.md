# Verification Scenario

Canonical contract for deriving, structuring, and executing material UI verification scenarios
in MxAgile.

## The Core Principle

Do NOT define UI acceptance as the Cartesian product:

```
all roles x all pages x all states x all viewports
```

DERIVE a material scenario matrix from the actual contracts:

```
Screen
  x materially distinct Role
  x required Data State
  x relevant Viewport
  x required Interaction
```

Schema: `.mxagile/schemas/verification-scenario.schema.json`  
File location: `planning/scenarios/<scenario-id>.yaml`

---

## Deriving the Material Scenario Matrix

Construct verification scenarios by answering:

1. **Which roles have materially different UI contracts for this screen?**  
   Two roles require separate scenarios when they differ in visibility, actions, editability, data scope, or navigation.  
   Two roles with demonstrably identical applicable UI contracts do NOT require duplicate scenarios.

2. **Which data states materially change what can be verified?**  
   An empty screen cannot prove populated-state parity.  
   An error state must be triggered to verify error parity.  
   Multiple data states may require separate scenarios or a single scenario with multiple steps.

3. **Which viewports are required by project contract?**  
   Default: desktop.  
   Mobile/tablet: only when responsive behavior is a declared requirement or known risk area.  
   Do not add viewport scenarios merely because a viewport exists.

4. **Which interactions are required acceptance criteria?**  
   Only materially required interactions from the Requirement acceptance clauses.

5. **What are the known risks?**  
   Areas where previous findings, regression history, or complexity suggest heightened scrutiny.

---

## Role Coverage Model

### When to Verify a Role Separately

A role requires separate verification when it has:
- Different navigation items (visibility or grouping)
- Different allowed actions (buttons visible/hidden)
- Different editability (input vs. display components)
- Different data scope (can only see own records vs. all records)
- Different workflow behavior

### When Not to Duplicate

If two roles (e.g., `Manager` and `SeniorManager`) have demonstrably identical UI contracts for
a given screen, a single scenario covering one role is sufficient — provided:
- The UI inventory documents identical contracts for both roles
- No Requirement or Spec identifies a difference
- The decision is recorded in the scenario's `decomposition.bounded_responsibility`

### Deriving From the UI Inventory

The `roles` field in each page YAML (`planning/ui-inventory/<PageName>.yaml`) declares which
roles are relevant. The scenario matrix starts from this list, then eliminates provably identical
pairs, then adds required role-specific scenarios.

---

## Data-State Coverage Model

| Data State | When Required |
|---|---|
| `empty` | When empty-state rendering is a declared Requirement or risk |
| `populated` | When the screen content depends on loaded entity data |
| `partial` | When partially loaded state is a business scenario |
| `error` | When validation/error rendering is a declared acceptance criterion |
| `any` | When the screen's contract is data-independent (e.g., static navigation) |

**Representative Mock Data is Mandatory for `populated` scenarios.** An empty screen cannot
prove populated-state parity. See Mock-Data Prerequisite Model below.

---

## Viewport Coverage Model

Required viewports for a scenario are derived from:
1. Project-declared `local_runtime.app_url` / Playwright config viewport profiles
2. Responsive requirements in the Spec/Requirement
3. Known responsive failure areas

Do NOT run viewport scenarios when responsive behavior is `NOT_APPLICABLE`.

When a viewport scenario is run: verify intended transformations (navigation collapse,
column reflow, card layout switch), not merely that the page renders.

---

## Mock-Data Prerequisite Model

### Mock Data as Evidence Prerequisite

Representative mock data is a PREREQUISITE for `populated` data-state scenarios, not a
screenshot detail. An unverified populated-state scenario cannot produce valid content,
structure, or role parity evidence.

### Ownership and Identity

Mock-data seeding may require a different identity (role) than the target verification identity.

Model the dependency chain explicitly:

```
bootstrap admin session (MENDIX_APP_ADMIN_USER)
    -> enable Developer identity (DEVELOPER_SEED_IDENTITY)
    -> execute mock data seed script
    -> switch to target role identity
    -> execute target verification scenario
```

Record:
- `prerequisites.mock_data_seed_identity` — the non-secret key reference for the seeder
- `prerequisites.mock_data_script` — the seed script path
- `prerequisites.mock_data_required: true`

Do NOT assume the bootstrap administrator can access every Developer/debug function.

### Partial Blocking

If mock data is unavailable for one scenario, block ONLY the scenarios that require it.

Do NOT block:
- Navigation scenarios
- Empty-state scenarios
- Login scenarios
- Role scenarios that are data-independent
- Scenarios with `data_state: any` or `data_state: empty`

### Bootstrap Sequence Example

```yaml
# planning/scenarios/SCN-CAPTRACK-SEED.yaml
scenario_id: SCN-CAPTRACK-SEED
screen_id: PAGE-SEED-UTILITY
role: Developer
data_state: any
verification_dimensions: [state]
prerequisites:
  mock_data_required: false
  requires_authenticated_session: true
decomposition:
  bounded_responsibility: "Seed representative CapTrack mock data for subsequent scenarios"
status: required

# planning/scenarios/SCN-CAPTRACK-PLANNING-ADMIN-POPULATED.yaml
scenario_id: SCN-CAPTRACK-PLANNING-ADMIN-POPULATED
screen_id: PAGE-PLANNING-OVERVIEW
role: Admin
data_state: populated
verification_dimensions: [visual, content, structure, state, interaction, role]
prerequisites:
  mock_data_required: true
  mock_data_seed_identity: DEVELOPER_SEED_IDENTITY
  mock_data_script: scripts/seed-captrack-mock-data.ps1
  depends_on_scenarios: [SCN-CAPTRACK-SEED]
status: required
```

---

## Test Identity Capability

Test identities should declare non-secret capability metadata to enable correct scenario
prerequisite resolution:

| Capability | Meaning |
|---|---|
| `can_seed_mock_data` | Identity can execute the mock data bootstrap script |
| `can_verify_admin_ui` | Identity can access admin/management screens |
| `can_verify_planning_ui` | Identity can access planning/reporting screens |
| `expected_application_role` | The Mendix application role this identity holds |

Record in a project-level credentials declaration (Company Layer / `.env.mendix`), not in
tracked project files. Only reference capability flags by name — never values.

---

## Browser Scenario Decomposition

### Prefer Focused Scenarios

A scenario has BOUNDED RESPONSIBILITY:
- One materially distinct role
- One page or coherent flow (not an entire application tour)
- One representative data state
- One relevant viewport set

Scenarios that span many roles, many pages, and many states in one script:
- Exceed reasonable execution limits
- Are fragile (early failure aborts everything)
- Produce ambiguous evidence (which step failed?)
- Cannot be partially re-run

### Condition-Based Waits

Prefer:
```
wait for target element to appear
wait for navigation outcome (URL change or element presence)
wait for rendered content (DOM assertion when content appears)
wait for target state (button enabled, error visible)
```

Over:
```
sleep(5000)  -- no
waitForTimeout(10000)  -- no, unless documented reason
```

### Timeout Policy

Do NOT solve large-test fragility by globally increasing all timeouts.

Differentiate:

| Timeout Type | Purpose | Default guidance |
|---|---|---|
| `assertion_timeout_ms` | DOM assertion / element presence | Project default (e.g., 5000ms) |
| `navigation_timeout_ms` | Page navigation / readiness | Application startup-aware (e.g., 15000ms) |
| `scenario_timeout_ms` | Entire scenario execution | Proportional to scenario complexity |

Rules:
1. A timeout increase must have a `timeout_rationale` explaining the genuine reason
2. A timeout increase must NOT compensate for poor scenario decomposition
3. If a scenario consistently needs extended timeouts, decompose it first
4. Scenario-level timeout is the outermost bound; element-level timeouts are tighter

### Parallelism Safety

Do NOT run scenarios in parallel by default.

Concurrent agent/test execution against shared project resources creates:
- False evidence (session contamination)
- Data corruption (concurrent writes to planning records)
- Non-deterministic results

Parallel execution is allowed ONLY when:
- `decomposition.parallelism_safe: true` is declared
- `decomposition.parallelism_rationale` explains why no shared mutable resource is at risk
- Evidence directories are scenario-scoped (no shared output paths)

Common shared resources to audit before enabling parallelism:
- One application session
- One database
- Test data (same entity records)
- planning/ directory files
- Evidence directories with shared filenames

---

## Coverage Traceability

Every mandatory UI acceptance clause must map to at least one verification scenario.

### Completeness Check

Before Full UI Acceptance PASS is allowed:

1. List all acceptance clauses from applicable Requirements/Specs
2. For each clause: identify the scenario that covers it
3. For each scenario: confirm `status: completed` and `parity_result: PASS`
4. Any clause without a covering scenario is a **coverage gap**

Coverage gaps must remain visible in `process-state.yaml` under `coverage_matrix_state.uncovered_clauses`.

### Coverage Status Per Scenario

| Status | Meaning |
|---|---|
| `required` | Must be executed for Full UI Acceptance PASS |
| `completed` | Executed and evidence recorded |
| `partial` | Some dimensions done; remaining in gaps |
| `blocked` | Cannot run due to missing prerequisites |
| `not_applicable` | Coverage demonstrably not needed (reason documented) |
| `superseded` | Replaced by another scenario (reference the new one) |

Full UI acceptance cannot PASS when any `required` scenario is not `completed`.

---

## Scenario Staleness

A `completed` scenario with `parity_result: PASS` becomes `STALE` when:
- The active target mockup version changes
- The Requirement acceptance clause changes
- The Widget/component selection changes materially
- The role contract changes

Stale scenarios require targeted re-verification before they can return to `completed`.

Record `parity_result: STALE` in the scenario file and in the evidence manifest entry.

A STALE required scenario prevents Full UI Acceptance PASS.
