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
  record. `MxAgile-Origin`, `MxAgile-Mission` and `MxAgile-Change-Set` commit
  trailers are discovery hints; neither trailer nor manifest alone establishes attribution.
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

## Optional Commit Producer

Only after the MxAgile change and impact outcome are complete, an agent may run
`reconcile_external_changes.py prepare-change-set` with explicit mission, change-set,
reconciliation-outcome and persisted-reference arguments. The helper requires a
valid Git integrity result, a named branch, no in-progress Git operation, a staged
path set with no unstaged/untracked paths, and an outcome fingerprint. It writes
the manifest under `planning/reconciliation/change-sets/` and prints the three
trailers; it never stages the manifest, creates a commit, installs a hook, or
rewrites history. The caller reviews and stages the manifest and commit message
through the normal Git client. Studio Pro commits are not rewritten.

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

## Reference Authority

`mockup_id` identifies an upstream Design Contract; `mockup_name` identifies the
SPA bundle directory used by accepted revisions and UI inventory. They are not
aliases. The current UI-Agent and revision producer use `mockup_name`; the Page
schema requires it whenever `target_revision` is present. Legacy pages with only
`mockup_id` are not projected to a bundle identity because that mapping is not
deterministic.

New or changed `input-resources/ui-ux/` and `planning/target-mockups/` paths are
reference candidates only. The report keeps the current canonical ACTIVE_TARGET
unchanged and marks the candidate `REFERENCE_RECONCILIATION_REQUIRED` (dirty
files remain `DIRTY_REFERENCE_UNRECONCILED`). No recency or filename heuristic
promotes a candidate.

Reference identity is derived from reference type, canonical path, bundle/revision
identity, bundle fingerprint and authority-source identities. Identical identity
projections may be deduplicated; the same physical path with a different authority
or reference type remains separately visible and must be labeled as such.

## Board Projection Cache

The loopback board keeps an in-memory, single-flight status snapshot. Its cheap
invalidation signature covers repository HEAD/branch/index/porcelain state,
file identity, size, mode, mtime, ctime and (on Windows) NTFS ChangeTime across
`planning/`, canonical collections, UI references, installed schemas/tools and
worktree reconciliation state. A missing/unreadable metadata field disables
reuse. The signature is only a cache invalidator, never project authority; the
builder still computes canonical SHA-256 fingerprints on rebuild. The signature
is checked before and after a build, and a changing source snapshot is not cached.

Within a build, Collection and Compatibility share the same parsed artifact
snapshot. Checklist parsing is reused per path; contract matching and validators
are cached only for the process/build and keyed by exact path/schema metadata.
Subrequests use the same snapshot. No database, worker, persistent status cache or
file watcher is introduced. If a browser disconnects during a response, only
`ConnectionAbortedError`, `ConnectionResetError` and `BrokenPipeError` are logged
as `CLIENT_DISCONNECT`; build/serialization failures remain visible as HTTP 503.