# Skill: Test Contract Derivation

Derive a canonical Test Contract (TC-NNN) from a requirement and optional Mocketeer Design Contract.
Produces WHAT must be proven. Does not specify HOW — that is `skills/verification-plan.md`.

## When to Run

Run this skill during Refinement for each requirement with accepted acceptance criteria,
or when a Mocketeer Design Contract becomes available during Discovery.
Re-run when a requirement's acceptance criteria change (see `policies/test-staleness.md`).

## Inputs Required

1. `requirements/REQ-NNN.yml` — must have `acceptance_criteria[]` with at least one Given/When/Then entry.
2. Mocketeer Design Contract JSON (optional) — from `input-resources/ui-ux/*.html` intake.
   Must have passed intake per `policies/design-contract-intake.md`.

## Step 1 — Assess Derivation Readiness

Before creating the contract:
- [ ] REQ-NNN has `status: accepted` or `status: draft` with explicit developer approval.
- [ ] At least one acceptance criterion is Given/When/Then structured.
- [ ] If Design Contract available: intake status is COMPLETE or PARTIAL-with-roles.

If requirements are not ready: record a DECISION_REQUIRED and stop. Do not derive a partial contract
from incomplete ACs — partial contracts cause test gaps that are worse than no contract.

## Step 2 — Enumerate Proof Points

For each `acceptance_criteria` entry in the requirement:

1. Identify the ROLE(s) in scope — from the Given clause or the Design Contract `roles[]`.
   If no role is specified and the requirement has `target_users`: use each target user as a role.
   If no role context at all: use `role: ANY_AUTHENTICATED`.

2. Identify the DATA_STATE — from the Given clause:
   - "no existing records" → `empty`
   - "with existing record" → `populated`
   - "with incomplete data" → `partial`
   - "when an error occurs" → `error`
   - Unspecified → `any`

3. Write the CLAIM as an observable outcome. Use this template:
   "A [role] user [can/cannot] [action] [in/when] [data_state] state."
   Do not include test steps in the claim.

4. Assign required layers per `policies/test-contract-derivation.md` defaults.

5. Assign security dimensions when the AC involves visibility, navigation, execution, or data access.

6. For each role's `cannot[]` in the Design Contract: add a negative proof point per rule in
   `policies/test-contract-derivation.md → Negative proof points from cannot[]`.

## Step 3 — Assign IDs

Assign PP-001, PP-002, ... sequentially. IDs are stable once assigned — never renumber.
Contract ID: next available TC-NNN from `planning/test-contracts/`.

## Step 4 — Testability Classification

For each proof point, classify:
- TESTABLE_AUTO — all required layers are runnable with current tooling
- TESTABLE_MANUAL — requires human action for at least one layer
- NOT_APPLICABLE — proof point is out of scope for this wave
- INFRASTRUCTURE_GAP — required layer tooling not configured

If any proof point is INFRASTRUCTURE_GAP: record the gap in the contract `notes` field.
Do not remove the proof point — it remains as an unmet obligation.

## Step 5 — Write Contract

Write to `planning/test-contracts/TC-NNN.yaml` using `schemas/test-contract.schema.json`.

Set:
- `status: draft` (transitions to `active` when the Verification Plan is produced)
- `derived_at: <today>`
- `derived_by: test-contract skill`
- `design_contract_ref: <mockup_id>@revision=<N>` if Design Contract was used

## Step 6 — Gate Signal

After writing: emit signal to `skills/verification-plan.md` that TC-NNN is ready for layer planning.

## Output

`planning/test-contracts/TC-NNN.yaml` — canonical proof obligation.

## Preservation Rule

See `policies/test-staleness.md`. When a requirement AC changes: mark the contract `stale`,
create a new version with updated proof points, preserve the old contract (do not delete).
