# Representative Fixture Contract

Defines what constitutes a complete representative fixture for scope-dependent verification,
and how fixture completeness governs evidence validity.

Complements:
- `policies/verification-scenario.md` — scenario derivation
- `policies/verification-gap-taxonomy.md` — FIXTURE_GAP gap type
- `policies/parity-finding-reconciliation.md` — FIXTURE_BLOCKED finding status
- `policies/evidence-levels.md` — evidence maturity levels
- `schemas/role_coverage.schema.json` — per-role coverage fields

---

## The Core Distinction

```
LOGIN_SUCCESS           → proves: authentication only
ROLE_ASSIGNED           → proves: role mapping only
HOME_ROUTE_CORRECT      → proves: role-based routing only
PAGE_REACHABLE          → proves: render / reachability only
EMPTY_NAVIGATION        → proves: NOTHING about correct scope restriction
```

None of the above constitutes:

```
DOMAIN_SCOPE_PROOF
```

A DOMAIN_SCOPE_PROOF requires a **representative fixture** — a complete fixture
that provides the scope context in which the role's scoped behavior can be observed.

---

## Representative Fixture Model

A representative fixture is the combination of:

```
IDENTITY
+ ROLE
+ DOMAIN_SCOPE           (if the role has a scope requirement)
+ REPRESENTATIVE_STATE   (data / organizational objects in scope)
+ POSITIVE_SCENARIO      (exercises the attributed behavior with scope context)
+ NEGATIVE_SCENARIO      (exercises out-of-scope isolation, where applicable)
= REPRESENTATIVE_FIXTURE
```

### Component Definitions

**IDENTITY**: A usable test or demo identity that can authenticate and be used in
automated verification. See `policies/credential-discovery.md` § test_identity
and `policies/test-identity-lifecycle.md`.

**ROLE**: The application role this fixture exercises. Corresponds to a `role_id` in
the role coverage schema. Must be the same role in which the attributed behavior is specified.

**DOMAIN_SCOPE**: The organizational or domain context within which the role operates.
A scoped role without a domain scope context cannot prove scope-dependent behavior.

Domain scope is applicable when:
- The role's requirements reference scope-dependent data access (e.g. "can only see own team's records")
- The mockup or design contract defines organizational scope for this role
- The role has `required_scope` set in role coverage (non-null, non-`app`)

Domain scope is NOT applicable when:
- The role has global/application-wide access (no scope restriction)
- The requirement explicitly states no scope restriction applies

**REPRESENTATIVE_STATE**: Sufficient seed data / pre-condition objects within the
DOMAIN_SCOPE to exercise the attributed behavior. An empty scope context is NOT
representative unless "empty" is specifically the scenario being verified.

**POSITIVE_SCENARIO**: At least one scenario that exercises the attributed behavior
with the full IDENTITY + ROLE + DOMAIN_SCOPE + REPRESENTATIVE_STATE context.

**NEGATIVE_SCENARIO** (where applicable): At least one scenario that demonstrates
access isolation — i.e., the role cannot access out-of-scope data. Required when
data isolation is an explicit requirement.

### Omission Rules

A fixture component may be omitted only when it is genuinely not applicable:

| Component | May be omitted when |
|---|---|
| DOMAIN_SCOPE | Role has global/app scope; `required_scope` is null or "app" |
| REPRESENTATIVE_STATE | The scenario specifically tests the empty-state behavior |
| NEGATIVE_SCENARIO | No explicit out-of-scope isolation requirement exists |

**Omission must be declared**, not silently absent. Record in the role coverage entry:
```yaml
domain_scope_not_applicable: true
domain_scope_omission_rationale: "Global admin role — no scope restriction"
```

---

## FIXTURE_GAP

A FIXTURE_GAP exists when a role requires scope-dependent verification and the
representative fixture is incomplete.

### FIXTURE_GAP Detection

A FIXTURE_GAP is present when ANY of the following conditions hold for a scoped role:

| Condition | FIXTURE_GAP type |
|---|---|
| `representative_scope_present: false` in role coverage | SCOPE_CONTEXT_ABSENT |
| A domain scope context exists but contains no representative in-scope data | REPRESENTATIVE_STATE_ABSENT |
| Test identity exists but cannot authenticate in the required scope context | IDENTITY_SCOPE_MISMATCH |
| Positive scenario exists but exercises only global/app-level behavior | SCOPE_SCENARIO_ABSENT |

### FIXTURE_GAP Propagation Rules

A FIXTURE_GAP is NOT informational. It is a **verification prerequisite** that must
propagate through the lifecycle.

**What a FIXTURE_GAP blocks:**
- DOMAIN_SCOPE_PROOF for the affected role
- Evidence claims that depend on scope-dependent behavior for the affected role
- Acceptance of scope-dependent parity findings as CONFIRMED for the affected role

**What a FIXTURE_GAP does NOT block:**
- Scope-independent verification for the same role (login, routing, global page access)
- Verification of other roles with complete fixtures
- Visual/layout/content parity for pages accessible without scope context
- Any finding that has been independently confirmed with a complete fixture

**Lifecycle propagation:** A FIXTURE_GAP recorded in Discovery MUST be carried forward:

```
Discovery (FIXTURE_GAP recorded)
  → Refinement: gap must appear in story specification as verification_gap: FIXTURE_GAP
    → gate-to-ready: FIXTURE_GAP for a scoped role is a testability blocker unless
                     the gap is resolved or explicitly deferred with rationale
      → Verification Planning: VPL must note FIXTURE_GAP as a prerequisite
        → Verification: scope-dependent proof points must have status FIXTURE_BLOCKED
          → Parity Campaign: FIXTURE_BLOCKED evidence must not be promoted to CONFIRMED
            → Completion Assessment: FIXTURE_GAP must be reflected in coverage status
```

A FIXTURE_GAP does not disappear because subsequent phases progress. It remains
as an open prerequisite until the gap is resolved.

### FIXTURE_GAP Resolution

A FIXTURE_GAP is resolved when:
1. A representative scope context has been created (organizational object, domain entity).
2. Representative in-scope data exists within that context.
3. The test identity can authenticate and access the scope context.
4. A positive scenario exercising the attributed behavior can be executed.

On resolution:
1. Update `representative_scope_present: true` in role coverage.
2. Update `fixture_contract_complete: true` in role coverage.
3. Remove `verification_gap: FIXTURE_GAP` from the story specification.
4. Re-execute all proof points that were previously FIXTURE_BLOCKED.
5. Replace FIXTURE_BLOCKED evidence with valid proof.

---

## Evidence Validity Rules for Scope-Dependent Proof

### VALID_FOR_ROLE_ONLY_NOT_SCOPE

Evidence is classified as `VALID_FOR_ROLE_ONLY_NOT_SCOPE` when:
- The verification used the correct role, but
- The domain scope context was absent or incomplete, and
- The behavior being proved depends on scope context.

**Effect:** The evidence proves role-level behavior (login, routing, global page access) but
NOT scope-dependent behavior. It is not discarded — its valid dimensions are preserved.

```yaml
evidence_scope: VALID_FOR_ROLE_ONLY_NOT_SCOPE
proves:
  - authentication: true
  - role_routing: true
  - scope_dependent_data_filtering: false  # requires DOMAIN_SCOPE_PROOF
  - scope_dependent_navigation: false
```

### TEST_FIXTURE_INVALID

Evidence is classified as `TEST_FIXTURE_INVALID` when:
- The verification used an identity that could not authenticate in the required context, OR
- The domain scope context existed but contained no representative data when data is required, OR
- A role was impersonated but the actual Mendix application role assignment was absent.

**Effect:** The evidence does NOT prove anything about the attributed behavior. It may
still be stored historically to document what was observed. Claims based on
TEST_FIXTURE_INVALID evidence must not be promoted to CONFIRMED.

### Historical Evidence Preservation

Evidence classified as VALID_FOR_ROLE_ONLY_NOT_SCOPE or TEST_FIXTURE_INVALID is
NOT automatically discarded.

Preserve the evidence with its classification. When a valid proof later becomes
available (FIXTURE_GAP resolved), the new evidence SUPERSEDES the prior evidence for
the scope-dependent dimensions. The prior evidence remains in the evidence history with
`lifecycle_stage: superseded` and `superseded_by` pointing to the new valid proof.

This allows audits to trace the evidence history without creating false impressions
of when scope-dependent behavior was actually confirmed.

---

## EMPTY_NAVIGATION Rule

```
EMPTY_NAVIGATION  ≠  correct scope restriction proof
```

An empty navigation (no items visible, empty data grid, empty list) observed during
verification with an incomplete fixture is NOT evidence that scope restriction is working.

An empty navigation can result from:
- Correct scope restriction (intended) → VALID if representative data exists in scope and is absent from other roles
- Absent domain scope context → incomplete fixture
- Missing seed data → incomplete state
- Application defect → should show items but does not

An agent MUST NOT classify EMPTY_NAVIGATION as correct scope restriction behavior without:
1. A complete representative fixture (representative_scope_present: true AND in-scope data exists)
2. Verification that the empty navigation does not appear for the in-scope data
3. Optionally: verification that out-of-scope data does NOT appear (negative scenario)

---

## Integration with Mockup Scenario Analysis

When a mockup or design contract contains role/scope scenario semantics, the
representative fixture requirements for that role must be derived. See
`policies/mockup-analysis.md` § Scenario Semantic Extraction.

The mockup may reveal that scoped behavior is required (e.g., "Role X sees only own
team records") without defining the concrete fixture objects. The fixture object
definitions are project-owned; the requirement for a complete fixture is framework-driven.

---

## Integration Points

- `schemas/role_coverage.schema.json` — `representative_scope_present`, `fixture_contract_complete`, `fixture_gap_reason`
- `policies/verification-gap-taxonomy.md` — FIXTURE_GAP gap type classification
- `policies/parity-finding-reconciliation.md` — FIXTURE_BLOCKED finding status
- `policies/test-identity-lifecycle.md` — test identity authorization and cleanup
- `policies/mockup-analysis.md` — scenario semantic extraction creates fixture preconditions
