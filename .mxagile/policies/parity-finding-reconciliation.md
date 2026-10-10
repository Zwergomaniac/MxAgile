# Parity Finding Reconciliation

Governs the mandatory reconciliation step between evidence collection and remediation in
parity, conformance, acceptance, and regression verification runs.

Applies to: Acceptance Agent, UI Agent (Verify mode), and any agent producing parity
or verification findings from observed evidence.

Related policies:
- `policies/ui-parity.md` — parity dimensions, evidence requirements, aggregation rules
- `policies/source-priority.md` — authority hierarchy; concern-specific resolution
- `policies/autonomous-remediation.md` — remediation state eligibility
- `policies/verification-layers.md` — security dimensions: VISIBILITY/ACCESSIBILITY/AUTHORIZATION/DATA_SCOPE
- `policies/observe-before-mutate.md` — enforced lifecycle; `finding_reconciliation_complete` stage
- `policies/impact-resolution.md` — finding classification vocabulary; prohibitions P1–P3

---

## 1. Observation vs. Interpretation

Every finding must explicitly separate what was observed from what is inferred.

**OBSERVATION** — what runtime, DOM, screenshot, test, or repository evidence directly demonstrates.

**INTERPRETATION** — what the agent believes the observation means relative to requirements or design.

```
OBSERVATION: "Button 'Export' is absent in role Manager's navigation."
INTERPRETATION: "REQ-042 § 3.1 requires this button for Manager; its absence is a violation."
```

An OBSERVATION is recorded as a parity deviation or test result.
An INTERPRETATION becomes a finding claim only after the cited authoritative source is resolved
and read (§ 2 below).

**An observation must never become an implementation instruction** without an explicit interpretation
step supported by authoritative contract evidence. The path:

```
observed difference -> assumed requirement violation -> implementation
```

is forbidden without the contract resolution step.

---

## 2. Requirement ID Authority

Before an agent may claim that an observation violates REQ-NNN, DEC-NNN, ADR-NNN, AC-NNN,
or any other authoritative identifier:

1. **Resolve the canonical source.** Locate and read the artifact at its canonical path
   (`requirements/REQ-NNN.yml`, `decisions/DEC-NNN.yml`, or equivalent).
2. **Confirm the claim.** Verify that the canonical source explicitly describes the
   behavior the finding claims it requires or forbids.
3. **Cite only what the source states.** Do not extend, infer, or extrapolate from adjacent
   clauses, neighboring identifier numbers, mockup content, filenames, or identifier patterns.

**Prohibited inference sources when citing an identifier:**
- Nearby mockup sections
- Identifier numbering or patterns (REQ-006 must not be inferred from REQ-005)
- Earlier reports or session memory
- Plausible-sounding descriptions
- Inferred feature relationships

**When the canonical source cannot be located or does not support the claim:**
- Classify the finding as `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK` (§ 3).
- Record which identifier was cited in the original observation and which canonical path was checked.
- Do not proceed with remediation based on the unsupported identifier.

**Mis-cited identifiers are evidence-integrity defects.** Correct the citation before remediation
proceeds. This rule applies to all finding types: parity deviations, test failures, defect reports,
and gap analyses.

---

## 3. Finding Classification

After evidence collection and before remediation, classify each finding. Use the most conservative
classification the evidence supports.

### CONFIRMED_REQUIREMENT_VIOLATION

Criteria (all must hold):
- The observation is supported by direct evidence (DOM assertion, runtime test, screenshot with selector).
- The authoritative canonical source has been resolved and read (§ 2).
- The canonical source explicitly and without contradiction states the required or forbidden behavior.
- The behavior is within the current accepted scope (§ 4 planning-state check passed).

**Eligible for remediation** per `policies/autonomous-remediation.md`: map to
`REQUIRED_BUT_UNAVAILABLE` or `EXPLICITLY_FORBIDDEN_BUT_AVAILABLE` as appropriate.

### CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK

Criteria:
- A concrete observable difference exists between the running application and a target artifact
  (mockup, design, specification).
- The authoritative contract source has not yet been resolved, is absent, or does not
  conclusively support or refute the observation.

**Not eligible for autonomous remediation.** Raise `DECISION_REQUIRED` for contract resolution.
Maps to `CONFLICT` in the parity schema (`policies/ui-parity.md` § Canonical Dimension Statuses).

### VERIFICATION_OUTSTANDING

Criteria:
- The relevant behavior has not been verified in the current session, or prior evidence is stale
  or absent.

**Not a defect.** Maps to `NOT_VERIFIED` in the parity schema.
Must never be reported as FAILED, DEFECT, or NON-COMPLIANT solely due to absence of evidence.
Not eligible for remediation — complete the verification first.

### INFORMATIONAL_COVERAGE_GAP

Criteria:
- The behavior belongs to planned, future, deferred, or out-of-current-scope functionality.
- Or: a verification gap exists but the concern is not a mandatory current acceptance clause.

**Informational only.** No remediation action. Document in the coverage matrix
(`process-state.yaml coverage_matrix_state.uncovered_clauses`).
Must not appear in current compliance or defect metrics.

---

## 4. Planning-State Awareness

Before reporting a missing capability as a current defect, resolve whether it is within
the current accepted scope.

1. Check `planning/lifecycle/process-state.yaml` for the current wave's accepted scope.
2. Check the relevant REQ-NNN or TASK-NNN `status` field — is it `accepted`/`in_progress`
   or `planned`/`deferred`/`future`?
3. Check task or work-package assignments for explicit deferral to a later wave.

**If the item is outside current accepted scope:**
- Classify as `INFORMATIONAL_COVERAGE_GAP`, not `CONFIRMED_REQUIREMENT_VIOLATION`.
- Report with note "Planned/deferred: [wave or reference]" — not as a compliance failure.

Appearing in a mockup or future-state design does NOT make an item current scope.
A feature shown in a roadmap mockup but not accepted in the current wave must be classified
as informational.

---

## 5. Parity Difference ≠ Compliance Defect

A visual, structural, content, state, interaction, responsive, or role difference is initially
a **parity observation** — the result of comparing the running application to a target artifact.

It becomes a **compliance defect** only when all three conditions are met:

1. Authoritative contract evidence confirms the behavior is required or forbidden (§ 2).
2. The behavior is within the current accepted scope (§ 4).
3. Finding classification (§ 3) produces `CONFIRMED_REQUIREMENT_VIOLATION`.

A parity difference that does not satisfy all three conditions must not be reported as:
- "the application is not compliant with [requirement]"
- "this violates REQ-NNN"
- "this must be fixed before the application can be accepted"

unless all three conditions are met.

---

## 6. Authorization Is Orthogonal to Navigation Visibility

When a parity finding concerns role-based visibility, access, or navigation, distinguish:

**Presentation finding:** An element is shown or hidden differently from the expected configuration.
Evidence: UI screenshot, DOM assertion, navigation inventory comparison.

**Authorization finding:** An action, resource, or operation is permitted or denied at the server level.
Evidence: server response to a direct action or URL access, XPath constraint inspection (mxcli),
access rule model check.

**The separation rule:**
- A navigation item unexpectedly visible is a **presentation** finding.
- An action executable by a role that should not be able to execute it is an **authorization** finding.
- Confirming that navigation is hidden does NOT confirm that the underlying action is secured.
- Confirming that navigation is visible does NOT confirm that the underlying action is unsecured.

Both must be checked independently when a role-based parity difference is found in an
operation-sensitive context. See `policies/verification-layers.md` security dimensions:
VISIBILITY, ACCESSIBILITY, AUTHORIZATION, DATA_SCOPE.

**Remediation scope:** A presentation fix (hide button, remove navigation item) does not satisfy
an authorization requirement, and an authorization fix does not automatically satisfy a
presentation requirement.

---

## 7. Remediation Eligibility Before Acting on Large Reports

Before implementing fixes from a parity or acceptance report containing multiple findings:

1. **Classify each finding** per § 3 above.
2. **Separate eligible from ineligible findings:**
   - `CONFIRMED_REQUIREMENT_VIOLATION` → apply `policies/autonomous-remediation.md` rules.
   - `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK` → DECISION_REQUIRED; do not implement.
   - `VERIFICATION_OUTSTANDING` → complete verification first; do not implement.
   - `INFORMATIONAL_COVERAGE_GAP` → do not implement.
3. **Do not batch ineligible findings into the same remediation pass** as eligible findings.
4. **Record the classification in the campaign result** before proceeding.

Contract conflicts, ambiguous interpretations, future-scope items, and unverified observations
must remain unresolved or trigger the appropriate verification/human gate rather than being
implemented speculatively.

---

## 8. Reporting Quality

Parity and verification reports must not make compliance claims stronger than the evidence supports.

**Prohibited phrasings without authoritative current-scope evidence:**
- "The application is not compliant because..."
- "Without X the application cannot be accepted"
- "This must be fixed before release"

**Required structure for finding sections:**

| Section | Contents |
|---|---|
| Confirmed defects | `CONFIRMED_REQUIREMENT_VIOLATION` findings with evidence and authority chain |
| Contract/design conflicts | `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK` findings; action = DECISION_REQUIRED |
| Parity differences | Observable differences not yet resolved to authority |
| Verification outstanding | `VERIFICATION_OUTSTANDING` items; action = complete verification |
| Future/planned scope | `INFORMATIONAL_COVERAGE_GAP` items; informational only |
| Coverage limitations | Dimensions or scenarios not yet covered |

Priority recommendations must respect these categories. Do not merge categories in a single
ordered list without explicit classification labels.

---

## 8a. Fixture-Gated Findings

Not all findings can be evaluated without a valid representative fixture.
When a finding depends on scope-dependent behavior, the validity of the fixture
must be assessed before the finding is classified.

### FIXTURE_BLOCKED

A finding is classified as FIXTURE_BLOCKED when:
- The finding concerns a role with a scope requirement (`required_scope` non-null / non-`app`), AND
- `representative_scope_present: false` OR `fixture_contract_complete: false` in role coverage
  for that role, AND
- The finding's specific claim depends on scope-dependent behavior.

**FIXTURE_BLOCKED is not a defect classification.** It is a finding-validity gate.

A FIXTURE_BLOCKED finding MUST NOT be:
- Reported as `CONFIRMED_REQUIREMENT_VIOLATION`
- Reported as `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK`
- Used to trigger remediation

**Allowed actions for FIXTURE_BLOCKED:**
- Document the finding as FIXTURE_BLOCKED with the specific FIXTURE_GAP that caused it.
- Continue the campaign — FIXTURE_BLOCKED findings do not halt the entire campaign.
- On fixture resolution: re-execute the specific proof points, classify findings normally.

### Scope-Independence Rule

FIXTURE_BLOCKED applies only to findings that depend on the scope-specific behavior.

**NOT affected by FIXTURE_BLOCKED:**
- Visual / layout findings for scope-independent pages
- Navigation findings for global-role behavior
- Authentication / role routing findings
- Findings for other roles with complete fixtures
- Scope-independent interaction findings on the same page

**Affected by FIXTURE_BLOCKED:**
- "Role X sees only own data" — depends on representative data in scope
- "Navigation item absent for out-of-scope resources" — requires scope context + data
- "Empty data grid" observed — could be scope restriction OR empty fixture (ambiguous without data)

### Evidence from Invalid Fixture

Evidence produced from an invalid fixture (FIXTURE_GAP present) is classified as
`VALID_FOR_ROLE_ONLY_NOT_SCOPE` for non-scope-dependent dimensions and
`TEST_FIXTURE_INVALID` for scope-dependent dimensions.

See `policies/representative-fixture-contract.md` § Evidence Validity Rules.

Such evidence is NOT discarded. It is preserved with its limitation classification.
When a valid fixture becomes available and scope-dependent proof is completed, the
new evidence SUPERSEDES the prior evidence for scope-dependent dimensions only.

### Completion Gate: No Blocker from Absence

A parity or MVP completion report MUST NOT claim full representative role coverage
if required scoped fixtures are incomplete.

However, avoid over-blocking:
- Unrelated visual findings may remain CONFIRMED or PASS.
- Scope-independent role behavior may remain CONFIRMED or PASS.
- Only scope-dependent conclusions for the affected role are blocked.

Reports must use explicit status values:
- `CONFIRMED` — fully evidenced, fixture complete
- `NOT_VERIFIED` — not yet checked
- `FIXTURE_BLOCKED` — fixture incomplete for this claim
- `CONTRACT_CHECK` — authority conflict requires DECISION_REQUIRED
- `ACCEPTED_VARIANT` — difference is accepted per DEC-NNN or design-system authority
- `SUPERSEDED` — prior evidence replaced by newer valid proof

**"No blocker found" MUST NOT be inferred from absence of executable scope-dependent scenarios.**
The absence of a representative fixture is itself a blocker for scope-dependent claims.

---

## 9. Lifecycle Integration

This policy integrates with `policies/observe-before-mutate.md` as a distinct stage between
parity analysis and discovery reconciliation:

```
1. BASELINE CAPTURE               (baseline_captured)
2. COMPLETE PARITY ANALYSIS       (analysis_complete)
3. FINDING RECONCILIATION         (finding_reconciliation_complete)  ← this policy
4. DISCOVERY RECONCILIATION       (reconciliation_complete)
5. REFINEMENT ACCEPTED            (refinement_accepted)
6. IMPLEMENTATION MUTATION        (mutation_allowed)
7. POST-MUTATION RE-VERIFICATION  (complete)
```

`finding_reconciliation_complete` is reached when all findings from step 2 have been classified
and the required actions have been dispatched:
- All `CONFIRMED_REQUIREMENT_VIOLATION` findings reviewed for remediation eligibility.
- All `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK` findings have DECISION_REQUIRED raised.
- All `VERIFICATION_OUTSTANDING` findings documented for follow-up.
- All `INFORMATIONAL_COVERAGE_GAP` findings recorded as informational.

After interruption and re-sync, re-read current `process-state.yaml` to determine the current
stage. A prior report calling something a defect does NOT automatically mean
`finding_reconciliation_complete` has been reached — the stage must be explicitly set based
on current evidence.

---

## 10. Autonomous Resolution Path

This policy does not introduce unnecessary human gates for unambiguous findings.

When authoritative evidence is complete and unambiguous, an agent may:
1. Classify findings (§ 3) without human input.
2. Proceed to remediation for `CONFIRMED_REQUIREMENT_VIOLATION` findings per
   `policies/autonomous-remediation.md`.
3. Record classification in the campaign result and continue.

A human gate is required only when:
- Authoritative contract sources conflict (`policies/source-priority.md`).
- Canonical identifier sources cannot be located or do not support the claim.
- The scope status of a capability is ambiguous.
- A finding is `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK`.
- The remediation state is `UNSPECIFIED_BUT_AVAILABLE` or `BUSINESS_EXPECTATION_UNKNOWN`.

The purpose of this policy is to prevent speculative remediation, not to slow down
well-evidenced work.
