# Observe Before Mutate

Enforceable lifecycle contract for MxAgile. An agent MUST NOT modify UI artifacts
(SCSS, widgets, page structure, content) before completing multi-dimensional parity analysis
and passing the Refinement gate for those changes.

## The Rule

```
OBSERVE FIRST. ANALYSE FULLY. DECIDE. THEN MUTATE.
```

Implemented as a lifecycle gate before any implementation mutation that affects UI.

## The Enforced Lifecycle

```
1. BASELINE CAPTURE
   Capture the current application state via UI-Agent Verify mode.
   Record parity-verification results for all affected pages.
   This is READ-ONLY — no model or SCSS changes at this step.

2. COMPLETE PARITY ANALYSIS
   Evaluate all 7 parity dimensions (see policies/ui-parity.md).
   Record each dimension result separately.
   Identify which dimensions PASS, FAIL, or are NOT_VERIFIED.

3. DISCOVERY RECONCILIATION
   If deviations reveal mismatches between the UI inventory and the running app:
   - Update the UI inventory to reflect the current state
   - Flag conflicts with the mockup/target as DECISION REQUIRED
   Do NOT change SCSS or widgets to force the inventory to match.

4. REFINEMENT ACCEPTED
   Present deviations and proposed corrections to the developer.
   Obtain Refinement gate PASS (gate-to-ready) for the planned changes.
   Widget or content changes must be declared in the Refinement decision.

5. IMPLEMENTATION MUTATION ALLOWED
   Only after steps 1-4 are complete may SCSS, widget, or content changes be applied.
   Record the pre-mutation parity state as the baseline for post-mutation comparison.

6. POST-MUTATION RE-VERIFICATION
   After mutation: re-run affected parity dimensions.
   Confirm the mutation achieved the intended improvement without introducing regressions.
```

## Classification of Violations

An agent that performs steps out of order is in a **LIFECYCLE VIOLATION** state:

| Violation | Description | Required Action |
|---|---|---|
| `MUTATE_BEFORE_OBSERVE` | SCSS or widget changed before parity baseline captured | Revert mutation; complete baseline capture first |
| `MUTATE_BEFORE_ANALYSE` | SCSS or widget changed after screenshot but before full dimensional analysis | Complete dimensional analysis; redo mutation decision |
| `MUTATE_BEFORE_REFINEMENT` | Mutation applied before Refinement gate accepted | Revert mutation; obtain Refinement acceptance |
| `ANALYSE_WITHOUT_BASELINE` | Dimensional analysis attempted without BROWSER evidence baseline | Capture baseline first; analysis without browser evidence has no standing |

## What Counts as a Mutation

UI mutations subject to this rule:
- Any SCSS or CSS change affecting visual presentation
- Any widget type change (e.g., Text Box → Dynamic Text)
- Any page structure change (section reordering, component addition/removal)
- Any content change (label text, button caption, navigation name, column header)
- Any role-access change affecting visible elements

NOT mutations (do not require this gate):
- Domain model changes (entities, associations, attributes) that have no direct UI impact
- Backend logic changes (microflows, nanoflows) with no UI component changes
- Configuration changes that do not affect rendered UI

## Non-Secret Lifecycle State Recording

Record the current Observe-Before-Mutate lifecycle state in `process-state.yaml` under
`prerequisite_state.observe_before_mutate_stage`:

| State | Meaning |
|---|---|
| `not_started` | No parity baseline captured yet |
| `baseline_captured` | Parity verification completed (browser evidence) |
| `analysis_complete` | All 7 dimensions evaluated and recorded |
| `reconciliation_complete` | Inventory updated; conflicts flagged |
| `refinement_accepted` | gate-to-ready passed for planned mutations |
| `mutation_allowed` | All pre-mutation gates passed; mutation may proceed |
| `post_mutation_pending` | Mutation applied; post-mutation re-verification not yet done |
| `complete` | Post-mutation re-verification passed |
| `violation_detected` | A lifecycle violation was detected; requires manual resolution |

## REAL CapTrack Finding

In the REAL acceptance run, SCSS was modified before the parity analysis was complete and
before Refinement had accepted the planned corrections. This led to:

- Incomplete evidence baseline
- Inability to prove which deviations the SCSS change was intended to fix
- Risk of fixing visual appearance while leaving content/structural deviations undetected

This policy prevents that failure mode by making the observation sequence enforced, not advisory.

## Integration with Parity Schema

When a violation is detected:
- Set `prerequisite_state.observe_before_mutate_stage: violation_detected`
- Record the violation type in `prerequisite_state.blocked_operation`
- Do NOT proceed with further mutations
- Surface the violation to the developer
- Await explicit developer decision before continuing
