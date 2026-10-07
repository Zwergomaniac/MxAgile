# Verification Materialization

Policy for when verification artifacts are created and when they are deliberately deferred.
Consumed by `skills/verification-plan.md`, `agents/acceptance-agent.md`, and
`policies/test-defect-protection.md`.

## The Materialization Problem

Materializing verification execution too early — before implementation details are stable —
creates work that must be redone when the implementation changes. This is test-harness churn,
not product verification.

A real-project reality test demonstrated an order-of-magnitude effort ratio between
test-harness work and actual implementation work. The primary cause was coupling
stable verification INTENT to volatile technical EXECUTION before implementation was stable.

## The Materialization Boundary

```
            STABLE VERIFICATION INTENT
            ──────────────────────────
            Requirement
            Test Contract (TC)
            Proof Points (PP)
            minimum_evidence_level per PP

            ═══════ MATERIALIZATION BOUNDARY ═══════

            IMPLEMENTATION-BOUND EXECUTION
            ──────────────────────────────
            Verification Plan (VPL)
            Executable test steps
            Playwright locators / adapters
            Runtime fixture / session setup
            Evidence artifacts
```

## Above the Boundary — Stable

TC and PP are created during **Refinement** because they answer:

> WHAT must be proven?

They do NOT depend on implementation details. A PP claim is independent of:

- Which locator addresses the button in the current build
- Which URL the page lives at after the current navigation model
- Which data seed script produces the required test data state
- Which screen structure widget names exist

TC and PP may persist unchanged across multiple waves.

## Below the Boundary — Implementation-Bound

VPL, executable tests, and Evidence are created/materialized when:

1. Implementation is sufficiently stable — checklist terminal state known
2. Infrastructure availability is known — RUNTIME/FRONTEND available?
3. Artifact names are known — microflow, page, entity names resolved
4. Screen structure is known — which widgets exist on which pages

## When NOT to Materialize

Do NOT create a VPL or executable Playwright steps during:

- Discovery phase
- Refinement phase
- Early implementation when significant structural changes are expected

A preliminary `expected_layers:` hint on a checklist item is a planning note, NOT a VPL.
It does not block gate-to-ready and is not the authoritative layer selection.

## Revision Impact Actions

When a change occurs, classify the required action per artifact. Use the smallest
justified action — never escalate automatically.

### PRESERVE

No action required.

Applies when: requirement semantics unchanged, PP claim unchanged, VPL layer decisions unchanged,
implementation unchanged for PP scope, evidence not stale.

Result:
- TC: no change
- PP: no change
- VPL: no change
- Executable test: reuse
- Evidence: reuse

### EXTEND

Existing verification intent is preserved AND new verification intent is added for
expanded scope.

Applies when:
- An existing Requirement is expanded with new acceptance criteria
- Product scope grows in a domain where an active TC already exists
- The existing TC/PP/VPL/evidence for prior scope remains fully valid
- New proof points are required only for the new/expanded scope

This is distinct from REASSESS: the existing TC claim is NOT reconsidered; it is preserved
exactly as-is. Only additive new proof points are introduced.

EXTEND must NOT:
- Invalidate existing PP/VPL/evidence for unaffected prior scope
- Rebuild or rematerialize prior executable tests
- Rerun prior proof points
- Change existing TC status if prior scope is unaffected

Result:
- TC: add new proof points for expanded scope; prior PPs unchanged; TC status remains `active`
- PP: existing PPs unchanged and at current status; new PPs appended for new scope
- VPL: existing VPL entries preserved; new VPL entries generated for new PPs when implementation is stable
- Executable test: prior tests unchanged; new tests generated only for new PPs
- Evidence: prior evidence preserved and valid; new evidence required only for new PPs

Key distinction — EXTEND vs REASSESS:

EXTEND applies when prior scope is confirmed valid and scope grows additively.
REASSESS applies when prior verification INTENT itself must be reconsidered.
If any existing PP claim must change, use REASSESS for the affected PPs (may co-exist with EXTEND for unaffected PPs).

EXTEND does NOT require DECISION_REQUIRED if the new scope is unambiguous.

### REASSESS

Verification INTENT must be reconsidered.

Applies when: requirement acceptance criteria changed materially, business rule changed,
role permission contract changed, design contract semantics changed.

Result:
- TC: review and update if affected; mark `stale` if claim is outdated
- PP: review and update affected proof points; mark per-PP `status: stale`
- VPL: supersede if TC is stale; regenerate from updated TC
- Executable test: regenerate from updated VPL
- Evidence: stale — reexecute against new contract

### REMATERIALIZE

Verification INTENT is unchanged. Technical execution binding changed.

Applies when:
- Screen structure changed (navigation, widget layout, component names)
- Locator(s) became stale (mx-name changed, component renamed, page restructured)
- Infrastructure availability changed (RUNTIME now available, FRONTEND now available)
- PP has `execution_binding_stale: true`
- Implementation changed but observable behavior claim is unaffected

Result:
- TC: **no change** — claim is valid
- PP: **no change** — claim is valid; set `execution_binding_stale: true` to signal refresh needed
- VPL: refresh layer assignments and test_generation_hints; status stays `active` or `draft → active`
- Executable test: regenerate locators/adapters from refreshed VPL
- Evidence: reexecute — prior evidence may be stale due to structural change

REMATERIALIZE does NOT require DECISION_REQUIRED.

### REEXECUTE

Test definition is valid. Existing evidence is stale because the covered implementation changed.

Applies when:
- PP claim is valid, VPL is valid
- The implementation of the covered scope changed (new wave, bug fix, refactor)
- Evidence was collected against a prior version of the implementation

Result:
- TC: no change
- PP: no change
- VPL: no change (unless infrastructure changed)
- Executable test: reuse or minor refresh
- Evidence: re-run — classify existing evidence as `STALE_REEXECUTION_REQUIRED`; do not reuse

REEXECUTE does NOT require DECISION_REQUIRED.

### INVALIDATE

Test Contract or Proof Point no longer represents required business behavior.

Applies when:
- Requirement is removed from scope
- Business behavior was fundamentally redesigned (not refined)
- TC/PP claim represents a business intent that is explicitly no longer required

Result:
- TC: mark `status: superseded`
- PP: mark `status: deferred` or `status: stale`
- VPL: mark `status: superseded`
- Executable test: retire
- Evidence: historical record only; mark as SUPERSEDED

INVALIDATE requires developer confirmation (DECISION_REQUIRED) when the boundary between
REASSESS and INVALIDATE is unclear.

## Impact Action Decision Table

| Change Type | TC | PP | VPL | Evidence |
|---|---|---|---|---|
| Cosmetic layout only (spacing, color) | preserve | preserve | rematerialize | reexecute |
| Screen restructure (same behavior) | preserve | preserve | rematerialize | reexecute |
| Locator change (widget rename) | preserve | preserve `+` execution_binding_stale | rematerialize | reexecute |
| Navigation change (same screens, new routes) | preserve | preserve `+` execution_binding_stale | rematerialize | reexecute |
| Implementation refactor (same observable behavior) | preserve | preserve | preserve | reexecute |
| New acceptance criterion — prior scope valid | extend | extend (new PP appended; prior PPs unchanged) | extend (new VPL entries only) | prior evidence valid; new evidence for new PPs |
| New acceptance criterion — prior intent affected | reassess | reassess (affected PPs) | regenerate affected | stale for affected PPs |
| Business rule change | reassess | reassess | regenerate | stale |
| Role permission change | reassess | reassess affected | regenerate | stale |
| Feature removed from scope | invalidate | invalidate | supersede | historical |

## Evidence Level Selection Rule

For each PP, use the **cheapest authoritatively sufficient evidence level**:

| What the PP asserts | Minimum authoritative level |
|---|---|
| Entity structure, attribute type, access rule PRESENT | MODEL |
| XPath validity, navigation reachability, security consistency | BUILD |
| Server-side runtime enforcement, microflow execution result | RUNTIME |
| UI element visible/hidden per role | FRONTEND |
| User interaction flow, navigation outcome | FRONTEND |
| Validation error display, redirect behavior | FRONTEND |
| User-observable state after interaction | FRONTEND |
| Data scope: scoped records returned per role | MODEL (XPath) + RUNTIME + optional FRONTEND confirm |

**Do NOT escalate to FRONTEND when MODEL authoritatively proves the assertion.**

**Do NOT downgrade to MODEL when the assertion requires user-visible behavior.**

MODEL confirms structure and rules. FRONTEND confirms what the user sees and can do.
These are NOT interchangeable, and neither implies the other.

## Escalation Bounds

When FRONTEND verification repeatedly fails — see the bounded escalation rule in
`policies/test-defect-protection.md`.

The verification materialization budget is not unlimited. An agent spending more cycles on
test-harness repair than on product verification has inverted the economics.

After exceeding the bounded repair threshold:

1. Does MODEL evidence already prove the PP's intended property?
   - YES: accept MODEL evidence; defer FRONTEND repair to a specific infrastructure task
   - NO: the assertion requires FRONTEND — surface the infrastructure blocker explicitly

2. Is the VPL correct for this PP's minimum evidence level?
   - If VPL includes FRONTEND where MODEL is sufficient: reclassify as COVERED_BY_LOWER_LAYER
   - If VPL correctly requires FRONTEND: the blocker is infrastructure, not overmaterialization

3. Emit `VERIFICATION_STRATEGY_ESCALATION` with root cause to developer.

## VPL Creation vs REMATERIALIZE Decision

At Verifying phase entry, for each PP:

```
FOR each PP in TC:
  WHAT is the minimum authoritative evidence level for this PP claim?
  IS that level available? (infrastructure check)
  IF yes: include in VPL as required layer
  IF no: exclusion_reason: INFRASTRUCTURE_UNAVAILABLE; flag as gap

  IF PP.execution_binding_stale == true:
    → REMATERIALIZE (refresh locators/adapters only; claim unchanged)
  ELIF TC.status == stale:
    → REASSESS (review intent first; regenerate from updated TC)
  ELSE:
    → Normal VPL creation
```

## Verification Gap Taxonomy

Before applying an impact action, classify why verification is insufficient using:

`policies/verification-gap-taxonomy.md`

| Gap type | Applicable action(s) |
|---|---|
| `NO_TC_YET` | No action — defer until Requirement is accepted and Testability Gate passes |
| `VERIFICATION_COVERAGE_GAP` | EXTEND — add new PPs to existing TC for expanded scope |
| `TEST_BINDING_GAP` | REMATERIALIZE — refresh VPL/locators; PP claim unchanged |
| `EVIDENCE_STALE` | REEXECUTE — rerun without rewriting tests |

A new Requirement classified as `NO_TC_YET` does NOT automatically trigger TC/PP/VPL/
executable test / Evidence creation. Premature materialization against a DRAFT or
not-yet-stable Requirement is test-harness churn.

## Relationship to Test Staleness Policy

This policy defines the impact ACTION vocabulary (PRESERVE/EXTEND/REASSESS/REMATERIALIZE/REEXECUTE/INVALIDATE).

`policies/test-staleness.md` defines the TC/PP STATUS vocabulary (active/stale/impacted/superseded)
and how each revision impact action maps to artifact statuses.

Together they form the complete revision impact model.
