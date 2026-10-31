# External Change Reconciliation

Defines read-only discovery and explicit watermark handling for Git changes not
verified as MxAgile-attributed work. `EXTERNAL_CHANGE` means missing or
insufficient MxAgile provenance; it does not claim that a person made the change.

## Authority and Storage

- `.mxagile/schemas/change-set.schema.json` defines tracked commit provenance.
- `.mxagile/schemas/project-reconciliation-state.schema.json` defines the
  worktree-local runtime watermark under `.mxagile/state/reconciliation/`.
- A watermark is bound to repository identity, worktree identity, branch ref,
  commit and project fingerprint. It is not shared across worktrees or clones.
- `planning/reconciliation/change-sets/CS-<id>.json` is a tracked provenance
  record. `MxAgile-Change-Set` and `MxAgile-Mission` commit trailers are discovery
  hints; neither trailer nor manifest alone establishes attribution.
- The board and project-status output are read-only projections, never authority.

## Attribution

Verify the change-set schema, trailer IDs, exact parent list, declared paths and
before/after Git blob IDs against the commit. Only verified manifest paths are
`MXAGILE_ATTRIBUTED_CHANGE`. Additional paths are `EXTERNAL_CHANGE`. A trailer
without a matching manifest is external; a manifest that claims the commit but
has no matching trailer, conflicting IDs, parent mismatch, or blob mismatch is
`AMBIGUOUS`. Never infer attribution from author name, message wording, patch
similarity, branch name, or a Git Note.

Merge commits are analyzed parent-aware. Changes inherited unchanged from any
parent are attributed to the contributing parent commit, not re-attributed to
the merge. Merge-resolution deltas require their own verified path binding;
otherwise they are ambiguous. Rewritten history is not silently reconciled.

## Baseline and Watermark

No watermark means `BASELINE_REQUIRED`; historical commits are not scanned.
Baseline adoption is an explicit command, requires a valid Git integrity result,
a committed HEAD, a named branch and a clean working tree, and records the
current project/artifact fingerprint. It never writes lifecycle state.

The report command is read-only. Watermark advancement is a separate operation
and requires a complete classified range, no unresolved ambiguous history,
persisted impact outcomes, and unchanged HEAD, branch, worktree and Git integrity.
State writes use a same-directory temporary file and atomic replacement. An
interrupted run or changed HEAD leaves the previous watermark intact.

## Working Tree and Impact

Committed, staged, unstaged and untracked paths are reported separately. Dirty
changes are not stable project truth. Git integrity failure, active Git
operation, detached HEAD, branch/worktree mismatch or unavailable history blocks
range reconciliation.

Path classification is deterministic. The existing Artifact Index provides
impact candidates only when its source fingerprint matches; stale or missing
indexes are not silently rebuilt by the report. Semantic analysis is bounded to
those candidates. No requirement, decision, task, wave, evidence or mockup
authority is mutated by this workflow.

Mendix model changes use only a capability-verified project-local `mxcli`.
Without reliable semantic evidence, report `SEMANTIC_REVIEW_REQUIRED`; do not
diff MPR-v2 internals with a new engine or feed raw binary diffs to an LLM.