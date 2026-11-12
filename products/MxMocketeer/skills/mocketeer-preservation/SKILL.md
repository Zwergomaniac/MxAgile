---
name: mocketeer-preservation
description: verifies stable ids, append-only revision history, scoped deltas, and preservation evidence in a mocketeer refinement. use before returning a refined html mockup or transformation result, especially after cross-cutting or structural edits.
---

# Mocketeer Preservation

## Session Entry

At first Mocketeer work in a session, read all seven skills once and follow
`mocketeer-discovery` Session Initialization and recovery rules. Reuse that shared
model for later tasks; load extra references/assets only for the current workflow.

Use the preservation and revision-ledger guidance in the fully loaded
`mocketeer-design-contract` and `mocketeer-refinement` skills.

- Compare the before/after stable IDs and confirmed content.
- Record only actually changed IDs in `revision_history`, `revision_delta`, and the
  preservation evidence.
- Keep revision history append-only. A missing baseline or uncertain comparison is not
  proof of preservation.
- If any confirmed item is unexpectedly lost or altered, report `FAILED` and stop; do
  not deliver the changed artifact as successful.
- Keep `DECLARED`, `INFERRED`, `OBSERVED`, and `PROPOSED` distinct during comparison.

This skill checks preservation evidence; it does not accept revisions or authorize
requirement changes.