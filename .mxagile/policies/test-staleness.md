# Test Staleness Policy

Defines when a test contract, verification plan, or proof point transitions between
CURRENT, STALE, and IMPACTED states — and what must happen before stale artifacts are used.

## Status Vocabulary

### CURRENT

The artifact is consistent with all of its upstream sources:
- All referenced REQ-NNN are at the version used when the contract was derived.
- All referenced AC-NNN entries are unchanged.
- The referenced Design Contract revision (if any) has not changed.
- The verification plan was produced from the current test contract.

`status: active` with no staleness_cause.

### STALE

A direct upstream source has changed in a way that materially affects the proof obligation.

Triggers for test contract:
- An acceptance criterion (`acceptance_criteria[]`) in a referenced REQ-NNN was added, removed, or meaningfully changed.
- A business rule directly quoted in a proof point claim changed.
- A role's `can[]` or `cannot[]` list changed in the referenced Design Contract.

Triggers for individual proof point:
- The specific AC mapped in `traceability.acceptance_clause_id` changed.
- The role referenced changed permissions.

**When STALE:**
- Set `status: stale`, `staleness_cause: <reason>`.
- The stale contract or proof point MUST NOT be used as the basis for a new acceptance campaign.
- The contract must be reviewed and updated (or explicitly superseded) before the gate can pass.
- Do not delete the stale contract — preserve it as history; create a new or updated version.

### IMPACTED

An upstream artifact changed, but the impact on this test contract is not yet assessed.

Triggers:
- The Mocketeer mockup was updated (new revision in `mockup.revision`).
- A referenced REQ-NNN changed in scope or title but acceptance criteria appear similar.
- A Design Contract decision affecting a screen referenced by a proof point changed.

**When IMPACTED:**
- Set `status: impacted`, `staleness_cause: DESIGN_CONTRACT_CHANGED` or similar.
- An impact assessment is required: read the change, determine if proof points need updating.
- If no proof points are affected: update status to `active` with a review note.
- If proof points are affected: mark each affected point `status: stale` and proceed as above.
- Document the assessment result in the test contract notes field.

## Revision Impact Action Mapping

Revisions and changes produce one of five impact actions. Use the smallest justified action.
Full definitions: `policies/verification-materialization.md`.

| Action | TC status | PP status | VPL action | Evidence action |
|---|---|---|---|---|
| PRESERVE | unchanged `active` | unchanged | unchanged | reuse |
| EXTEND | unchanged `active`; new PPs appended | prior PPs unchanged; new PPs `active` | prior VPL unchanged; new VPL entries added | prior evidence valid; new evidence required for new PPs only |
| REASSESS | → `stale` or `impacted` | → per-PP `stale` if claim outdated | supersede; regenerate from updated TC | `STALE` — reexecute |
| REMATERIALIZE | unchanged `active` | unchanged; set `execution_binding_stale: true` | refresh layer assignments only | `STALE_REEXECUTION_REQUIRED` — reexecute |
| REEXECUTE | unchanged `active` | unchanged `active` | unchanged | `STALE_REEXECUTION_REQUIRED` — reexecute without test rewrite |
| INVALIDATE | → `superseded` | → `stale` or `deferred` | → `superseded` | historical record |

**Key distinction — EXTEND vs REASSESS:**

EXTEND applies when prior verification scope is confirmed valid AND product scope grows additively.
New PPs are added; existing PPs are NOT reconsidered. TC status remains `active`.

REASSESS applies when existing PP CLAIMS must be reconsidered — AC changed, business rule changed,
role permission contract changed.

If existing PPs are unaffected but new scope requires new PPs: use EXTEND.
If any existing PP claim must change: use REASSESS for those PPs (may co-exist with EXTEND for unaffected scope).

EXTEND does NOT affect existing PP/VPL/evidence. EXTEND does NOT require DECISION_REQUIRED when new scope is unambiguous.

**Key distinction — REMATERIALIZE vs REASSESS:**

REMATERIALIZE applies when the PP CLAIM is unchanged but the technical execution binding changed.
Locator change, screen restructure, widget rename, infrastructure availability change.

REASSESS applies when the PP CLAIM must be reconsidered.
Acceptance criteria changed, business rule changed, role permission contract changed.

REMATERIALIZE does NOT change TC status and does NOT require DECISION_REQUIRED.
REASSESS sets TC status to `stale` or `impacted` and may require DECISION_REQUIRED.

**Propagating NEEDS_RERUN:**

When `policies/impact-resolution.md` marks a TC as `NEEDS_RERUN`, this maps to impact action **REEXECUTE** — non-material (cosmetic) screen change, acceptance criteria unchanged:
- TC status remains `active`
- Evidence is marked `STALE_REEXECUTION_REQUIRED`
- VPL is unchanged (unless infrastructure changed)
- Do NOT set TC status to `impacted` for a NEEDS_RERUN signal

`NEEDS_RERUN` applies only to **non-material** screen changes (spacing, color, cosmetic layout).
For **material** screen changes with AC unchanged, `policies/impact-resolution.md` sets
`PP.execution_binding_stale: true` on affected proof points instead — this maps to **REMATERIALIZE**,
not REEXECUTE. See `policies/impact-resolution.md` Step 4 Case B vs Case C.

## Staleness Cascade

When a test contract is STALE (REASSESS action):
1. Its associated verification plan (VPL) is automatically IMPACTED — set `status: superseded` and generate a new plan from the updated contract.
2. Acceptance campaign results produced from this contract are LEGACY — valid only as historical record.
3. Evidence manifest entries pointing to stale proof points acquire `parity_result: STALE`.

When a test contract is IMPACTED but not yet assessed (REASSESS pending):
1. VPL remains `active` but is flagged for review before next campaign.
2. The Acceptance Agent must complete the impact assessment before running campaigns.
3. If assessment determines PP claims are unchanged: restore TC to `active`; VPL unchanged.

When impact action is REMATERIALIZE (PP unchanged, execution binding changed):
1. TC status remains `active`.
2. VPL is refreshed (locators, adapters, test_generation_hints only) — NOT superseded.
3. Set VPL `status: draft` while refreshing; re-activate after refresh.
4. Evidence is marked `STALE_REEXECUTION_REQUIRED` — rerun without test rewrite.
5. Do not reuse stale evidence — re-run even when the PP claim is unchanged.

## Propagation Detection

The Discovery Agent and Acceptance Agent must check for staleness at the start of each work session:

1. For each `planning/test-contracts/TC-NNN.yaml`:
   - Load the referenced REQ-NNN and compare `acceptance_criteria` checksums or modification dates.
   - If any referenced AC has changed since `derived_at`, mark test contract as `STALE`.

2. For each `planning/verification-plans/VPL-NNN.yaml`:
   - If the referenced test contract is `stale` or `superseded`, mark the plan as `superseded`.

3. For evidence manifest entries:
   - If the proof point is `stale`, set `parity_result: STALE` on existing entries.
   - Do not promote new evidence against a stale proof point.

## Non-Deletion Rule

Stale artifacts are preserved. They provide an audit trail of what was proven at what point in time.
Set `status: stale` or `status: superseded`. Delete only via explicit developer instruction.

## Regression Staleness

Proof points promoted to the regression scope of a later wave are IMPACTED whenever:
- The original requirement changes.
- A model change in the later wave affects an entity or microflow referenced by the proof point.

Regression candidates with `status: impacted` must be re-run before the later wave's acceptance gate passes.
