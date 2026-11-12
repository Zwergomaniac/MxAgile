# MxMocketeer v3 Preservation Acceptance Test

## Goal
Verify that MxMocketeer iteratively modifies a non-trivial HTML file without losing unaffected confirmed content or contract knowledge.

## Preparation
Upload `skills/mocketeer-mockup-generation/assets/golden-mockup.html` and use the suggested prompt "Refine an existing mockup".

## Session Loading Host Matrix

Run separately in Microsoft Copilot and Claude/Concord with the same canonical skills
and asset. Record the host/version, skill revision or hashes, prompts and observable
resource-read trace. A statement that the agent read files is not sufficient evidence.
If the host exposes no read trace, record NOT_VERIFIABLE rather than PASS. These checks
have not been executed by the static test suite.

| Case | Expected observable resource behavior |
|---|---|
| New session, first Discovery request | All seven SKILL.md read once before execution; shared process and authorities understood; no Golden asset or automatic technical references |
| Second Discovery task, same session | Retained model reused; no full seven-skill/knowledge reload |
| Task switch needing a specific reference/schema | Only that workflow's missing required resources loaded; no general reference sweep |
| Generation with sufficient confirmed inputs | Golden HTML not automatically loaded merely because generation was selected |
| Explicit visual calibration or Golden check | Generation's Golden asset read; source bytes and semantics unchanged |
| Relevant skill/product update notified | Bootstrap invalidated and all seven updated entries read before further execution |
| Context Compaction with missing baseline | No blind reuse of a flag; entries reread or missing authoritative baseline demonstrably reconstructed |
| Cross-host comparison | Same terminology, authority boundaries, handoffs, gates and lazy-load rules; missing access blocks affected work rather than simplifying semantics |

Keep test traces as verification evidence, not a new persistent business bootstrap state.

## Microsoft Copilot Session Smoke

Current evidence status: **NOT_VERIFIED**; no live Agent Builder retrieval trace was
available in this framework environment. Record host/version and source revision.

1. Configure the seven canonical skills, identical optional Golden asset and main
  prompt. Start a fresh session and verify all seven named entries are retrievable.
2. Ask: "Describe Mocketeer's complete product process and the responsibility of each
  of its seven skills." Expect Discovery -> Design Contract/Flows -> Generation ->
  Refinement/Preservation -> Handoff, correct authorities and gates. The trace must
  show one seven-skill bootstrap, not an isolated task-based skill selection.
3. Ask a second Discovery question in the same session. Expect reuse of the shared
  model, no complete seven-skill reread and no Golden asset retrieval.
4. Switch to generation with sufficient confirmed inputs, then request an explicit
  Golden verification/calibration. The asset is loaded only when actually relevant;
  generation alone does not require it. Additional references are demand-driven.
5. Record observable reads and outputs. Without an actual read trace, keep load-once
  and lazy-resource claims NOT_VERIFIED rather than trusting the agent's self-report.

## Test Sequence

### Iteration 1 — Add a new display field
Change: "Show a previous-year value on the dashboard, read-only."
Expected: new requirement/decision added if needed; all existing IDs and content preserved; revision incremented to 2.

### Iteration 2 — Add a negative permission
Change: "The Site Manager must not be able to edit the previous-year value."
Expected: negative permission / cannot[] updated; read-only UI applied to that field; all other roles and requirements unchanged.

### Iteration 3 — Change one label only
Change: "Change only the button label from 'Add Site' to 'New Site'."
Expected: only the button text and affected traceability updated; no screens, requirements, decisions, or roles lost.

### Iteration 4 — Supersede a decision
Feedback: "A separate detail page was reconsidered and rejected; the modal dialog stays confirmed."
Expected: DEC-001 decision_status remains CONFIRMED; the rejected alternative documented more explicitly; rationale updated; no unrelated data lost.

### Iteration 5 — Readiness review (no change)
Request: "Is this mockup ready for development?"
Expected: Readiness report only; no modifications to HTML or Design Contract unless explicitly confirmed.

## Verification Checklist
After each iteration verify:
- [ ] HTML opens locally without errors
- [ ] `#mocketeer-spec` is valid JSON
- [ ] mockup.revision increments monotonically; previous_revision matches predecessor
- [ ] All unaffected IDs from the previous version still exist
- [ ] No confirmed decisions disappear without explicit request
- [ ] change_scope lists only affected IDs
- [ ] No secrets or real personal data present
- [ ] Visible flows still function (search, create dialog, role switch)
- [ ] Requirements, decisions, roles, and screens remain traceable

## Abort Criterion
Do not release to broad use if MxMocketeer, without explicit instruction:
- removes confirmed information
- reassigns stable IDs
- modifies unaffected screens or flows
- ignores an existing embedded Design Contract

---

## Professional Discovery Sequence Test

Validates the new assessment, guided interview, and readiness workflow.

### Preparation
Start a fresh conversation. No HTML file uploaded.

### Discovery Iteration 1 — First idea
Input: "I need an app to track annual leave requests. Employees submit requests; their manager approves or rejects them."

Expected:
- First mockup generated with at least 2 screens or a core flow
- `assessment` block present: `prototype_readiness: PROTOTYPE_READY`
- `development_handoff_readiness` is NOT `HANDOFF_READY` (too early)
- Open questions or assumptions explicitly listed
- MxMocketeer does NOT invent a calculation or approval rule not stated

### Discovery Iteration 2 — Assessment detects gaps
Request: "What is missing before this could go to development?"

Expected:
- Maturity summary in plain language (strong/needs clarification/blockers)
- At least one blocking gap identified (e.g., approval data scope, overlap rule)
- MxMocketeer asks focused questions about the highest-priority gaps — not a questionnaire
- Questions are in business language (not XPath or microflow names)

### Discovery Iteration 3 — Mixed answers including "I don't know"
Respond to questions. For one question, answer: "I don't know."

Expected:
- Answered questions integrated — corresponding gap status changes to RESOLVED
- "I don't know" answer recorded as OPEN/UNKNOWN — NOT replaced with an invented answer
- Unaffected content preserved; revision incremented
- `assessment` updated to reflect reduced gaps

### Discovery Iteration 4 — Business rule clarified
Provide: "An employee may not have more than 20 days leave per year. Overlapping requests with the same dates are not allowed."

Expected:
- Business rules added with correct status
- Corresponding gaps resolved in assessment
- `development_handoff_readiness` may still be REFINEMENT_REQUIRED if other blockers remain
- Traceability preserved for previously confirmed content

### Discovery Iteration 5 — Readiness verdict
Request: "Are we ready for development?"

Expected:
- Clear verdict: HANDOFF_READY only if all handoff readiness requirements are met
- If REFINEMENT_REQUIRED: remaining blockers explicitly listed
- Maturity summary shows which dimensions are strong and which need work
- No modifications to contract unless explicitly confirmed
- MxMocketeer does NOT claim HANDOFF_READY merely because the mockup looks complete

## Verification Checklist for Discovery Sequence
After each iteration verify:
- [ ] `assessment.prototype_readiness` present from iteration 1
- [ ] `development_handoff_readiness` not prematurely HANDOFF_READY
- [ ] Unknown answer remains OPEN/UNKNOWN — not silently resolved
- [ ] Resolved gaps reflected in updated `assessment.gaps` resolution_state
- [ ] `assessment.blocking_gaps` contains only gaps with `blocks_handoff: true`
- [ ] READ and UPDATE operations treated independently for roles
- [ ] No overall percentage score used as the authoritative maturity measure
- [ ] Detailed assessment lives in knowledge file, not duplicated in system prompt

---

## Targeted Transformation Sequence Test (Sequence 3)

Validates safe large-artifact refinement via the CROSS_CUTTING_EDIT / LOCAL_EDIT path.
This sequence requires a Revision 11+ mockup with multiple StickyHeader components.

### Preparation
Upload a multi-screen mockup (Revision 11+) where StickyHeader components display "2024".
Use the suggested prompt "Refine an existing mockup".

### Transformation Iteration 1 — Cross-cutting year change
Input: "Apply the year change consistently to all StickyHeaders — change 2024 to 2025."

Expected:
- Change classified as CROSS_CUTTING_EDIT (NOT FULL_REGENERATION)
- MxMocketeer identifies all StickyHeader targets via component selector
- One of two paths (both valid):
  a. **In-context execution**: complete modified HTML output with transformation applied; embedded `transformation_spec` in Design Contract for audit trail.
  b. **Handoff**: machine-readable `mocketeer-transformation-spec` JSON block output; MxMocketeer does NOT attempt unsafe full reconstruction; handoff contains complete transformation intent.
- `change_class: CROSS_CUTTING_EDIT` stated in output summary
- `business_flow_impact: NONE` — year in header is presentation-only
- `revision_delta.effects[]` contains UI entries for affected screens only; NO FLOW/STORY/IMPLEMENTATION entries
- Unrelated screens, requirements, decisions, roles, flows remain unchanged

### Transformation Iteration 2 — Local edit (single element)
Input: "Change the 'Submit' button label to 'Save & Submit' on the Registration screen only."

Expected:
- Change classified as LOCAL_EDIT
- Only Registration screen's Submit button label changed
- All other screens and elements preserved
- `revision_delta.effects[]` has one UI entry for the Registration screen
- `preservation.result: VERIFIED`

### Transformation Iteration 3 — Fail-closed: missing target
Input: "Change the year in all TopBar navigation components."

Expected (when no TopBar components exist):
- MxMocketeer reports: target selector matched 0 elements (fail-closed)
- No revision created
- No content modified
- Clear message about which target was not found

### Transformation Iteration 4 — Fail-closed: precondition mismatch
Input: "Change all StickyHeaders from 2023 to 2024."

Expected (when StickyHeaders already show 2025, not 2023):
- MxMocketeer reports: precondition "2023" not found at target elements
- No revision created
- No content modified

### Transformation Iteration 5 — Explicit FULL_REGENERATION (justified)
Input: "Redesign the entire mockup to add a multi-step wizard flow replacing all current screens."

Expected:
- Change classified as FULL_REGENERATION (complete structural change)
- If file size is manageable: complete HTML output with all existing IDs superseded/updated
- If file too large: MxMocketeer explicitly states FULL_REGENERATION is unsafe and explains why — does NOT silently produce a CROSS_CUTTING_EDIT or partial output
- Classification and reasoning stated in output

## Verification Checklist for Targeted Transformation Sequence
After each iteration verify:
- [ ] Change classification (LOCAL_EDIT / CROSS_CUTTING_EDIT / STRUCTURAL_REFACTOR / FULL_REGENERATION) explicitly stated in output
- [ ] CROSS_CUTTING_EDIT: multiple targets identified via selector, not one-by-one
- [ ] CROSS_CUTTING_EDIT: revision_delta has no FLOW/STORY/IMPLEMENTATION effects for presentation-only changes
- [ ] In-context execution: complete HTML output with transformation_spec embedded
- [ ] Handoff path: mocketeer-transformation-spec JSON block present; HTML not output; handoff includes source_revision, target_revision, intent, operations[]
- [ ] Fail-closed: no revision created when target not found or precondition mismatches
- [ ] Fail-closed: explicit error message with specific reason (which target, which precondition)
- [ ] Preservation: non-target content byte-identical to previous revision
- [ ] Revision metadata correct: revision incremented, previous_revision set, lifecycle_status: REFINED_TARGET, refinement_status: PROPOSED, active_target: false
- [ ] Business flow preservation: unrelated FLOW-NNN/FLOWSTEP-NNN IDs remain unchanged

## Abort Criterion for Targeted Transformation Sequence
Do not release to broad use if MxMocketeer, when processing a CROSS_CUTTING_EDIT:
- attempts full file reconstruction of a large existing mockup without explicit justification
- produces output where non-targeted content is changed or missing
- claims FULL_REGENERATION on a change that is clearly deterministic and bounded
- produces a handoff that loses the original refinement intent (user must re-explain)
- silently applies a global find-replace without verifying scope constraints
