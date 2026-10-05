# Acceptance Campaign Policy

Defines how proof points from test contracts are grouped into acceptance campaigns, run by the
Acceptance Agent. A campaign is a coherent execution unit with a single pass/fail outcome.

## Campaign Types

### REQUIREMENT Campaign

Scope: all proof points in ONE test contract that cover a specific requirement.

Use when: verifying that a single requirement is fully satisfied — all ACs, all roles, all data states.

Assembly:
1. Load `planning/test-contracts/TC-NNN.yaml` for the target requirement.
2. Filter `proof_points[]` to those with `traceability.acceptance_clause_id` matching the requirement's ACs.
3. Include both positive (`role: ROLE-NNN`) and negative (`role: !ROLE-NNN`) proof points.
4. For operation-aware proof points: include each [role + operation] proof point independently.
5. Execute all required layers per the verification plan (VPL).
6. Campaign result: PASS only when all proof points in scope pass their required layers.

Output: `planning/acceptance-campaigns/<wave>/<REQ-NNN>-campaign-result.yaml`

**This is the default campaign type for changed requirements in a wave.**

---

### ROLE Campaign

Scope: all proof points across all test contracts that involve a specific role — positive and negative.

**Triggers (explicit required — not automatic):**

A ROLE campaign is run ONLY when one of the following applies:
- Explicit role acceptance is requested (stakeholder sign-off on a role's behavior)
- A security-sensitive cross-cutting change was made (e.g. role model restructured, new role added, XPath constraint changed)
- A release or review policy requires horizontal role validation before release
- The role's capability contract itself changed (new `can[]`/`cannot[]` entries)
- An explicit campaign request from the developer or a project policy rule
- Other justified framework rule documented in the wave's process-state

**A small unrelated UI change must NOT automatically execute every proof point for every involved role.**

Evidence reuse: when evidence for a proof point is still CURRENT (TC unchanged, implementation unchanged for that scope, evidence not stale), reuse the existing result. Do not re-run identical proof point + layer combinations.

Assembly:
1. Load all `TC-NNN.yaml` in scope for the trigger.
2. Filter proof points where `role == ROLE-NNN` OR `role == !ROLE-NNN`.
3. Reuse CURRENT evidence from prior REQUIREMENT campaigns where applicable.
4. Execute only proof points not already verified with CURRENT evidence.
5. Campaign result: PASS only when the role's full capability contract passes.

Output: `planning/acceptance-campaigns/<wave>/ROLE-<id>-campaign-result.yaml`

---

### RISK_CHANGE_IMPACT Campaign

Scope: proof points affected by a specific change or risk identified during Verifying or post-implementation.

Use when: a change to one requirement may silently break adjacent requirements or roles.
Examples: changing an XPath constraint, renaming a microflow, adding a new permission to a role.

Assembly:
1. Identify the change (requirement changed, model artifact changed, Design Contract revision bumped).
2. Load all test contracts that reference the changed artifact.
3. Filter proof points that exercise the changed concern.
4. Execute only the required layers for affected proof points.
5. Evidence reuse: reuse CURRENT evidence for unaffected proof points.
6. Campaign result: PASS only when all affected proof points pass.

Output: `planning/acceptance-campaigns/<wave>/RISK-<change-ref>-campaign-result.yaml`

---

## Evidence Reuse (All Campaign Types)

Before re-running a proof point, check whether existing evidence is reusable:
- Test Contract for the proof point has `status: active` (not stale/impacted)
- The model implementation for the covered scope has not changed since the evidence was collected
- The evidence artifact is not marked `parity_result: STALE`
- The evidence was collected against the current wave's model state

Only when all conditions are met: reuse the existing result without re-running.

---

## Campaign Result Schema

Each campaign produces a YAML result file:

```yaml
campaign_id: CAMP-W01-REQ-001
campaign_type: REQUIREMENT
wave_id: W01
test_contract_id: TC-001
target_id: REQ-001  # or ROLE-MANAGER, or RISK-CHANGE-XYZ
status: PASS | FAIL | PARTIAL | BLOCKED
run_at: 2026-10-05
proof_point_results:
  - proof_point_id: PP-001
    operation: READ          # present if operation-aware proof point
    authorization_disposition: REQUIRED   # present if set in TC
    status: PASS | FAIL | PARTIAL | BLOCKED
    layer_results:
      MODEL: PASS
      RUNTIME: PASS
      FRONTEND: PASS
    defect_classification: null  # or APPLICATION_DEFECT | TEST_DEFECT | TEST_INFRASTRUCTURE_GAP
    remediation_state: null      # or REQUIRED_BUT_UNAVAILABLE | etc.
    evidence_refs: []
    evidence_reused: false       # true if reused from prior PASS
    notes: ""
gate_outcome:
  acceptance_gate: passed | failed | pending
  blocking_items: []
  pending_decisions: []
```

---

## Campaign Execution Order

Within a wave's Verifying phase:

1. Run REQUIREMENT campaigns — establishes per-requirement pass/fail baseline.
2. Run RISK_CHANGE_IMPACT campaigns if applicable — validates regression scope.
3. Run ROLE campaigns ONLY when triggered per conditions above.

Evidence from (1) may be reused in (2) and (3) when the conditions above are met.

---

## Acceptance Gate

The acceptance gate passes when:
- All REQUIREMENT campaigns for the wave's scope have `status: PASS`
- All triggered ROLE campaigns have `status: PASS`
- No `DECISION_REQUIRED` items remain open in `pending_decisions`
- No proof point has unresolved `remediation_state` in {UNSPECIFIED_BUT_AVAILABLE, BUSINESS_EXPECTATION_UNKNOWN}

Record in `.concord/scratch/process-state.yaml`:
```yaml
waves.W01.gates.acceptance_gate: passed | failed | pending
```
