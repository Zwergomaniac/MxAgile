# Skill: Verification Plan

Produce a Verification Plan (VPL-NNN) from a Test Contract (TC-NNN), selecting which evidence
layers must run for each proof point and why. Answers WHICH layers — not HOW tests are implemented.

## Timing

**The Verification Plan is produced at Verifying phase entry — after implementation, not during Refinement.**

Reason: the VPL answers "HOW should the implemented system now prove it?" — this requires knowing:
1. What was actually built (implementation checklist terminal state)
2. Which infrastructure is now available (RUNTIME, FRONTEND, BUILD)
3. Current model state for artifact name resolution

A **preliminary verification hint** may be recorded in the checklist item during Refinement
(e.g. `expected_layers: [MODEL, RUNTIME, FRONTEND]`) but is not the authoritative executable VPL.

The authoritative VPL is created or refreshed at the start of the Verifying phase.

## When to Run

1. At Verifying phase entry: create VPL for each TC-NNN in scope if not already present.
2. **REASSESS** (full regeneration): TC was updated (status: stale → reassessed → active), or requirement semantics changed. Supersede the existing VPL, create a new one from the updated TC.
3. **REMATERIALIZE** (binding refresh only): TC is still `active` but execution binding is stale — locator, adapter, or screen structure changed; or infrastructure availability changed. One or more PP has `execution_binding_stale: true`. Refresh `layer_assignments.test_generation_hint` and layer exclusions; do NOT supersede. Set status to `draft`; re-activate after refresh.
4. Skip if: VPL is `active` and no REASSESS or REMATERIALIZE trigger is present.

**REMATERIALIZE vs REASSESS — key distinction:**

REMATERIALIZE applies when:
- TC.status is `active`
- PP claims are unchanged
- Only execution binding changed (locator, screen name, component rename, infrastructure)
- Action: refresh VPL hints/exclusions only; TC unchanged

REASSESS applies when:
- TC.status is `stale` or `impacted`
- PP claims may need to change
- Action: first update TC; then create fresh VPL from updated TC

Do NOT supersede a VPL for a REMATERIALIZE trigger. Supersede only for REASSESS.
See `policies/verification-materialization.md` for the full revision impact action model.

**Clearing execution_binding_stale after REMATERIALIZE:**

After the refreshed VPL has been activated (status set to `active`):
1. For each PP in the TC that had `execution_binding_stale: true`, set it to `null`.
2. Write the updated TC-NNN.yaml with `execution_binding_stale: null`.

Do NOT clear `execution_binding_stale` before the VPL refresh is confirmed active.
If rematerialization is interrupted or the VPL stays in `draft`, execution_binding_stale
remains `true` — the REMATERIALIZE trigger is preserved for the next Verifying phase entry.

## Inputs Required

1. `planning/test-contracts/TC-NNN.yaml` — with `status: active`.
2. Current infrastructure assessment (see Step 1 below).
3. `planning/checklists/W*-implementation-checklist.yaml` — for artifact name resolution.

## Step 1 — Infrastructure Assessment

Before assigning layers, assess what is actually available NOW (post-implementation):

```yaml
infrastructure:
  MODEL: available        # always (mxcli present)
  BUILD: available | unavailable  # semantic build capability available?
  RUNTIME: available | unavailable | blocked
  FRONTEND: available | unavailable | blocked  # depends on RUNTIME
```

Record in the plan's `notes` field. Infrastructure status at VPL creation time is canonical
for this wave. If it changes later, refresh the VPL.

## Step 2 — Assign Layers Per Proof Point

For each proof point in the test contract:

1. Start with `required_layers` from the test contract as baseline.
2. For operation-aware proof points (`operation` field set):
   - Check `authorization_disposition` — EXPLICITLY_FORBIDDEN proof points always need
     MODEL (access rule absent) + FRONTEND (action not shown) at minimum.
   - Add RUNTIME for AUTHORIZATION dimension checks (server-side enforcement).
3. Check each required layer against infrastructure:
   - Unavailable required layer → `included: false`, `exclusion_reason: INFRASTRUCTURE_UNAVAILABLE` (gap, not decision).
4. For `optional_layers`: include if available and adds meaningful coverage not covered by required layers.
5. For security dimensions: confirm all dimension-required layers are included per `policies/verification-layers.md`.
6. BUILD layer: include only when semantic build capability is available AND the proof point benefits
   from semantic validation (XPath constraints, security expression, navigation reachability).
   Do not include BUILD merely to add coverage — it must serve a semantic purpose.

## Step 3 — Assign Campaign Type

For each proof point, set `campaign_type`:
- `REQUIREMENT`: default for proving an AC for a requirement
- `ROLE`: for proof points in a triggered role campaign (see `policies/acceptance-campaign.md`)
- `RISK_CHANGE_IMPACT`: for proof points flagged as regression candidates

## Step 4 — Regression Candidates

Identify proof points that should be promoted to the regression scope for future waves.
Apply principled selection — do NOT auto-promote every negative authorization proof:

**Promote as regression candidates when:**
- The proof point covers a severe escaped defect from prior history
- It covers a critical security boundary (shared authorization component, cross-role data scope)
- It covers a critical business workflow or calculation
- The covered artifact (entity, microflow) is high change-impact (shared by many features)
- Repeated historical regression has occurred at this boundary
- Explicit project policy marks this scope for permanent regression
- Negative authorization (`role: !ROLE-NNN`) at a critical security boundary — not all negative auth proofs qualify

**Do NOT promote:**
- Routine UI interaction proof points with no security significance
- Proof points for stable isolated features unlikely to be affected by future waves
- Every negative auth proof automatically (increases regression burden without proportional safety gain)

**Generated vs permanent distinction:**
- Generated acceptance tests: run in the current wave, produced by `skills/test-generate.md`
- Permanent regression candidates: promoted explicitly to `regression_scope[]` with documented reason
- These are distinct categories — a generated test does not automatically become permanent regression

Add promoted points to `regression_scope[]` with `promoted_from_wave: <W>` and `promotion_reason`.

## Step 5 — Write Plan

Write to `planning/verification-plans/VPL-NNN.yaml` using `schemas/verification-plan.schema.json`.

Set:
- `status: draft` until activated at the start of campaign execution
- `generated_at: <today>`
- `generated_by: verification-plan skill`

## Step 6 — Activate

Activate the VPL (set `status: active`) when the Acceptance Agent begins the first campaign.
Set the corresponding TC to `status: active` in the same step (if not already active).

## Output

`planning/verification-plans/VPL-NNN.yaml` — layer selection with rationale.

## Failure Cases

**Required layer unavailable:** Record `included: false`, `exclusion_reason: INFRASTRUCTURE_UNAVAILABLE`.
Flag as gap. The acceptance gate does NOT block on infrastructure gaps alone — but they must be visible.

**Proof point has no available layers:** `testability_classification: INFRASTRUCTURE_GAP` on the proof point.
Flag for resolution before acceptance gate passes.
