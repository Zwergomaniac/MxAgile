# MxMocketeer v3 Preservation Acceptance Test

## Goal
Verify that MxMocketeer iteratively modifies a non-trivial HTML file without losing unaffected confirmed content or contract knowledge.

## Preparation
Upload `source/knowledge/golden-mockup.html` and use the suggested prompt "Refine an existing mockup".

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
