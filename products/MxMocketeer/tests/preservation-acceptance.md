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
