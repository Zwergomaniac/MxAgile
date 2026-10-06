# Test Defect Protection Policy

Defines how verification failures are classified to protect against acting on the wrong root cause.
Prevents incorrect model changes caused by stale or incorrect test expectations.
Distinguishes canonical defects (requiring a decision) from technical test defects (repairable without a decision).

## The Three Defect Classes

### APPLICATION_DEFECT

**Definition:** The test expectation is correct per the acceptance criteria, and the application
produced an incorrect result.

**Evidence:** The proof point claim matches the current active AC text. The application's behavior
contradicts it.

**Action:** The model must be corrected. The test contract and proof point remain valid.
Create a failing checklist item; route back to Implementing.

**Example:**
- AC: "A ROLE-MANAGER user can submit the create-site form and the record persists."
- Observed: form submits but no record appears in the list.
- Classification: APPLICATION_DEFECT (server-side persistence microflow missing or misconfigured).

---

### TEST_DEFECT

TEST_DEFECT has two sub-types:

#### CANONICAL_EXPECTATION_CHANGE

**Definition:** The canonical proof obligation (Test Contract / AC text) is outdated.
The test expectation no longer matches the current requirement. Application behavior may be correct.

**Action:** DECISION_REQUIRED before any change. The proof point must be reviewed and updated.
The model must NOT be changed based on this failure.

**Example:**
- AC updated: save now redirects directly; dialog removed from design.
- Proof point still expects dialog.
- Classification: CANONICAL_EXPECTATION_CHANGE → DECISION_REQUIRED.

#### TECHNICAL_TEST_DEFECT

**Definition:** The canonical proof obligation is correct, but the generated test implementation
is technically broken — a stale locator, wrong step sequence, outdated test data setup,
or broken infrastructure reference. The application's behavior is not the cause of the failure.

**Action:** Repair or regenerate the technical test implementation using `skills/test-generate.md`.
DECISION_REQUIRED is NOT required — the canonical expectation (TC claim, AC) is unchanged.
The regenerated test must be validated against the canonical claim before re-running.

**Example:**
- Proof point claim: "ROLE-MANAGER can submit create-site form."
- Playwright step fails because a locator changed after a widget rename (mx-name changed).
- The claim itself is still correct.
- Classification: TECHNICAL_TEST_DEFECT → repair locator, re-run. No DECISION_REQUIRED.

#### TEST_ADAPTER_GAP

**Definition:** The generated test implementation used a **forbidden or unsupported execution
adapter** — specifically, Mendix-internal browser APIs (`window.mx.data.*`, `window.mx.ui.*`,
`mx.ui.openForm`, `runtimeOperation` IDs, undocumented XAS calls) instead of real Playwright
user journeys or approved model inspection. The proof point obligation is correct. The failure is
caused by the wrong adapter choice, not by a missing infrastructure capability or an application
defect.

**Action:** Regenerate the test using approved adapters per `skills/test-generate.md` Forbidden
Adapters section:
- Replace Mendix JS API calls with real Playwright user journeys (`navigate`, `click`, `fill`,
  visible-state assertions).
- Replace FRONTEND authorization checks with RUNTIME `runtime_check:` blocks where appropriate.
- DECISION_REQUIRED is NOT required — the canonical expectation (TC claim, AC) is unchanged.
- Do **NOT** classify the Proof Point as `TEST_INFRASTRUCTURE_GAP` until all approved adapter
  alternatives (Playwright journey, RUNTIME layer) have been assessed and found genuinely
  unavailable for the required evidence.

**Example:**
- Proof point: "ROLE-MANAGER cannot delete a site record they do not own."
- Generated test calls `window.mx.data.remove(...)` and inspects the return value.
- Application behavior may be correct; the adapter is forbidden.
- Classification: TEST_ADAPTER_GAP → regenerate using `await page.click(...)` + assert server
  rejection, or a `runtime_check:` with `action: delete_entity`.
  No DECISION_REQUIRED. Do NOT reclassify as TEST_INFRASTRUCTURE_GAP.

---

### TEST_INFRASTRUCTURE_GAP

**Definition:** The test could not run due to a missing or broken piece of infrastructure —
not because the application or expectation is wrong.

**Evidence:** Test runner error, missing credentials, Playwright not configured,
database not seeded, RUNTIME layer not available.

**Action:** Fix the infrastructure gap. Neither the model nor the test contract is changed.
Record as a gap in the verification plan. Acceptance gate remains `pending` until resolved.

**Guard — TEST_ADAPTER_GAP is NOT TEST_INFRASTRUCTURE_GAP:**
A test that used a forbidden adapter (`window.mx.data.*`, `window.mx.ui.*`, etc.) and failed
is a `TEST_ADAPTER_GAP`, not a `TEST_INFRASTRUCTURE_GAP`. Classify as `TEST_INFRASTRUCTURE_GAP`
only after all supported adapter alternatives (Playwright user journey, RUNTIME `runtime_check:`)
have been assessed and found genuinely unavailable for the required evidence. Do not use
`TEST_INFRASTRUCTURE_GAP` as a default when a forbidden adapter was the actual cause.

---

## Classification Protocol

When a proof point fails, classify before acting:

```
1. Did the test runner complete execution?
   NO  → TEST_INFRASTRUCTURE_GAP (stop; fix infrastructure)
   YES → continue to step 2

2. Is the proof point claim consistent with the current AC text?
   YES → continue to step 3
   NO  → CANONICAL_EXPECTATION_CHANGE (DECISION_REQUIRED; no model change)
   UNCLEAR → BUSINESS_EXPECTATION_UNKNOWN (DECISION_REQUIRED; no action)

3. Did the test use a forbidden adapter?
   (window.mx.data.*, window.mx.ui.*, runtimeOperation IDs, XAS calls —
   see skills/test-generate.md Forbidden Adapters section)
   YES → TEST_ADAPTER_GAP (regenerate with approved adapter; do NOT classify as
         TEST_INFRASTRUCTURE_GAP without first assessing Playwright / RUNTIME alternatives)
   NO  → continue to step 4

4. Did the test fail due to a locator/step/setup issue (stale locator, wrong step sequence,
   outdated test data setup) rather than an actual application behavior difference?
   YES → TECHNICAL_TEST_DEFECT (repair/regenerate test; no DECISION_REQUIRED)
   NO  → APPLICATION_DEFECT (route to Implementing)
```

---

## Protection Rules

1. **Never change the model based on an unclassified failure.** Classification is mandatory.
2. **CANONICAL_EXPECTATION_CHANGE requires developer confirmation** before proof point is updated.
3. **TECHNICAL_TEST_DEFECT may be repaired** (regenerate locators/steps) without DECISION_REQUIRED.
4. **APPLICATION_DEFECT routes to Implementing** via the standard return routing in `lifecycle.yaml`.
5. **TEST_INFRASTRUCTURE_GAP does not route anywhere** — it is an infrastructure task, not a code defect.
   **TEST_ADAPTER_GAP is NOT TEST_INFRASTRUCTURE_GAP** — a forbidden adapter is a generation error,
   not a missing infrastructure capability. Always assess Playwright / RUNTIME alternatives before
   concluding the evidence path is unavailable.
6. **Model must NOT be changed based on a TEST_DEFECT** (either sub-type) before classification is confirmed.

## Evidence Preservation

When a failure is classified, evidence MUST be preserved regardless of classification.
Evidence of a TEST_DEFECT is as valuable as evidence of an APPLICATION_DEFECT.
Do not delete or overwrite evidence artifacts during reclassification or test repair.

## Regression Defects

When a proof point from the regression scope fails in a later wave:
- Apply the same classification protocol.
- Additional question: did a model change in this wave cause the regression?
  YES → APPLICATION_DEFECT routed to current wave's Implementing.
  NO  → DECISION_REQUIRED to determine root cause before routing.
