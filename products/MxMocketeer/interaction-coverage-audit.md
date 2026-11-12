# Mocketeer Interaction Coverage Audit

## Audit Status

**FINDINGS — contract-only; REV37 fixture verification pending.** The requested
`20261104_fte-plannung_rev37_functional-gaps-closed.html` is not present in the
workspace. `input-resources/ui-ux/` contains only its README, and workspace searches
did not locate the named file. A broader `D:\Mendix` search timed out. No claim below
asserts that a particular field or behavior is present in REV37 or in its runtime.

The audit therefore evaluates what the published contract can transport, not what the
unavailable fixture actually declares. The eight case descriptions are taken from the
user's request and are not represented as REV37 evidence.

Sources inspected: the migrated Design Contract and Business Flow material now embedded
in `skills/mocketeer-design-contract/SKILL.md` and
`skills/mocketeer-business-flows/SKILL.md`, plus the MxAgile Business Flow, Page,
Revision, and Test Contract schemas and the Design Contract Intake, Test Contract
Derivation, Impact Resolution, and Test Staleness policies.

## Current Contract Surface

- `screens[].interaction_states[]` can declare a trigger, initial/resulting UI state,
  visual/data/navigation/permission effects, persistence, role references, and nested
  typed UI effects. Effects can have stable IDs, preconditions, source IDs, target,
  affected roles/screens, downstream artifacts, and required action.
- `flows[].steps[]` can declare user/system actions, actor roles, screen/requirement/
  decision references, conditional transitions, and an `effects[]` reference list.
- Roles and permissions can state capabilities and organizational/data scopes. Explicit
  `cannot[]` entries can produce negative authorization proof points.
- Revision deltas can identify changed effects, roles, screens, source IDs, and
  downstream artifacts. MxAgile marks affected Test Contracts for review and can derive
  positive/negative role proof points after canonical Requirements exist.

These are useful building blocks, but the documented top-level Design Contract has no
shared `effects[]` registry even though the Business Flow schema describes step
`effects[]` as references to `effects[]`. That reference boundary is not consistently
defined or validated. Further, `affected_roles` does not mean “these roles observe this
effect”; permission scope does not bind that scope to a specific notification or
observation. `status` values describe lifecycle/decision disposition, not a complete
DECLARED / INFERRED / OBSERVED / PROPOSED provenance model.

## Coverage Matrix

The matrix rates the published model only. It does not claim that the unavailable
REV37 fixture populates any of these fields.

Codes: `AE` = ALREADY_EXPRESSIBLE; `EN` = EXPRESSIBLE_BUT_NOT_NORMALIZED;
`RP` = PRESENT_ONLY_IN_REQUIREMENT_PROSE; `RT` = PRESENT_ONLY_IN_MOCKUP_RUNTIME;
`IM` = INFERRED_BY_MXAGILE; `NE` = NOT_EXPRESSIBLE as a first-class structured
relationship; `AM` = AMBIGUOUS / not verifiable from the missing fixture.

| Information element | 1 Transfer / decision | 2 User notification | 3 Revoked scope / save | 4 Team merge | 5 Historical month | 6 Center switch | 7 Team control | 8 Hierarchy sync |
|---|---|---|---|---|---|---|---|---|
| Actor identity (person or system) | EN | EN | EN | EN | EN | EN | EN | EN |
| Actor role | AE | AE | AE | AE | AE | AE | AE | AE |
| Interaction and trigger | EN | EN | EN | EN | EN | EN | EN | EN |
| Preconditions | EN | EN | EN | EN | EN | EN | EN | EN |
| Previous state | AE | EN | AE | EN | AE | EN | AE | EN |
| Business state change | EN | EN | EN | EN | EN | EN | EN | EN |
| Observer actor/role | EN | NE | EN | EN | EN | EN | EN | EN |
| Observer scope | EN | EN | EN | EN | EN | EN | EN | EN |
| Positive visible/business effect | EN | EN | EN | EN | EN | EN | EN | EN |
| Explicit effect-specific negative observers | NE | NE | EN | NE | EN | NE | EN | NE |
| Follow-up interaction | EN | EN | EN | EN | EN | EN | EN | EN |
| Multi-interaction causal link | EN | EN | EN | EN | EN | EN | EN | EN |
| Requirement references | AE | AE | AE | AE | AE | AE | AE | AE |
| Decision/business-rule references | EN | EN | EN | EN | EN | EN | EN | EN |
| Mendix candidates/downstream references | AE | AE | AE | AE | AE | AE | AE | AE |
| Test Contract derivable | EN | EN | EN | EN | EN | EN | EN | EN |
| Positive and negative role evidence | EN | EN | EN | EN | EN | EN | EN | EN |
| Revision reconciliation of the whole chain | EN | EN | EN | EN | EN | EN | EN | EN |
| DECLARED / INFERRED / OBSERVED / PROPOSED provenance | EN | EN | EN | EN | EN | EN | EN | EN |
| Actual REV37 declaration/runtime evidence | AM | AM | AM | AM | AM | AM | AM | AM |

### Case Findings

1. **Internal transfer and accept/reject notification.** Flow steps can identify role
   actors and decision branches; requirements, decisions, screens, and downstream
   artifacts have reference fields. The model does not bind the notification effect to
   an allowed observer role plus a particular scope, nor record excluded scopes as
   negative observers. The next decision step is not guaranteed to reference the
   notification effect.
2. **Per-user re-entry notification.** Role-level permissions and session persistence
   do not express a per-user notification identity/dismissal key or prove that one
   user's acknowledgement leaves another user's notification intact. This is a
   material state/data rule, not just a visual notification effect.
3. **Scope revoked during editing.** A no-permission state, permission effect, and
   negative UPDATE/EXECUTE proof point are available. The contract does not state that
   authorization is re-evaluated at save against current scope while the old page stays
   open; this requires an explicit business assertion and runtime/model evidence.
4. **Team deletion/merge.** Business rules, data semantics, flows, and downstream
   references can describe the move. There is no normalized set of source/target
   entities and invariants tying people, movements, planning values, and every affected
   view into one reviewable effect chain.
5. **Historical month.** Read-only/disabled states and permission rules can describe
   preserved navigation and blocked writes. A month lifecycle precondition that
   overrides otherwise valid roles across every mutating action is not a normalized
   shared guard in the documented interaction contract.
6. **Center/context switch.** A role-switch interaction and local/session persistence
   can be described. The ordered save-old-context, load-new-data-space, recompute-scope,
   and rebuild-role/department/team views sequence is not an explicit transaction or
   linked state transition in the contract.
7. **Team control changes role/owner.** Role-dependent UI states and permissions can
   describe available actions. The contract does not normalize which observer sees
   which changed action under which scope, or require those views to update together.
8. **HierarchyTree team synchronization.** A system action/integration call, business
   rule, requirement, and Mendix candidate can be recorded. The model does not require
   a synchronization trigger, ownership/idempotency rule, assignment-independent
   visibility rule, and affected view to be linked as one effect chain.

## Minimal Contract Decision

**Do not add `scenarios[]`.** Existing `flows[]`, interaction states, and typed effects
are the right homes for this information. Normalize the existing relationship first:
each flow step's `effects[]` must resolve to a stable nested `effect_id`, and ordinary
step ordering/branches should continue to use flow transitions rather than parallel
`caused_by` / `next_interaction` links.

If the REV37 read-only audit confirms the stated requirements, the smallest likely
extension is an optional effect-level observation declaration that records observer
role, observation scope, and expected visibility (positive or explicitly negative),
plus a separate provenance value `DECLARED | INFERRED | OBSERVED | PROPOSED` for
interaction/effect assertions. Keep existing effect `status` for lifecycle and do not
promote INFERRED or OBSERVED facts to DECLARED. This is a **recommendation only**;
no schema was changed because the missing REV37 may already carry product-specific
`interaction_metadata` that must be reconciled before defining compatibility.

## Reconciliation and Evidence Rules

- Compare declared Design Contract facts, MxAgile inferences, and observed mockup/app
  behavior as separate inputs. Preserve source, revision, and observation origin.
- Reconcile the affected interaction/effect IDs and their flow links; do not mark an
  entire unrelated Test Contract stale merely because the mockup revision changed.
- Derive positive and negative Test Contract proof points only from explicit declared
  role/scope assertions. An omitted observer is UNKNOWN, not implicitly forbidden.
- A confirmed Requirement/Decision/Business Rule remains the authority for its own
  concern. Mockup runtime behavior is OBSERVED evidence, not proof of PO intent.

## Follow-up Needed

Re-run the fixture-specific matrix against the exact REV37 HTML before applying any
schema change. For each of the eight cases, record source IDs, actual interaction/effect
IDs, whether the statement is DECLARED/INFERRED/OBSERVED/PROPOSED, and the referenced
screen/flow/requirement/decision/business rule. Update the recommendation only from
that evidence.