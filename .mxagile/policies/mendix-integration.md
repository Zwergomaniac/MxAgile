# Policy: Mendix Branch Integration

Decides how a Mendix model integration is performed and when it counts as finished. Evidence base:
`docs/mendix-merge-safety-baseline.md`. The Git index guard is not part of this problem
(`GIT_INDEX_GUARD_NOT_CAUSAL`); this policy covers model identity, serialization noise and integrity.

## Roles (explicit contract)

| Component | Role | Not |
|---|---|---|
| **Studio Pro** | Mendix-aware merge engine (`Merge Changes Here`) | not replaced by Git CLI merges on model artifacts |
| **Concord** | Conflict Resolution / Investigation consumer of the conflicts Studio Pro reports | not a cause of conflicts; no evidence says otherwise |
| `mendix_merge_preflight.py` | read-only risk decision before, integrity gate after | does not merge, restore, delete or write the index |
| MDL replay | fallback when native reconciliation is insufficient | not the default for parallel model changes |

`CLOSED-AUTONOM` (Studio Pro closed) may use another Mendix-aware path only after it is technically validated as
equivalent and safe for the project (validation evidence recorded). Never `git merge -X ours|theirs`, `checkout --ours|--theirs`
or hand-copied files on `*.mpr` / `mprcontents/**` as an integration shortcut. `.gitattributes` or merge drivers for the
model are out of scope until a validated Mendix-aware merge wrapper exists.

## Entry points (existing tool contract; no new CLI name)

Distributed to projects as `.mxagile/tools/mendix_merge_preflight.py` (framework development: `scripts/mendix_merge_preflight.py`):

```text
python .mxagile/tools/mendix_merge_preflight.py preflight --target <rev> --source <rev> [--base <rev>] [--protected-marker <text>]... [--output <file>]
python .mxagile/tools/mendix_merge_preflight.py postcheck [--rev <rev>] --preflight <file> [--stage studio-pro-merge|concord-resolution|final] [--protected-marker <text>]...
python .mxagile/tools/mendix_merge_preflight.py classify-changes --base <rev>
```

All three are read-only and resolve the repository through Git (subdirectories and linked worktrees are supported; each
worktree reports its own `HEAD` and index). Exit codes: `0` ok / PASS, `4` BLOCKED or postcheck not PASS, `5` postcheck at the `studio-pro-merge` stage with open scope only, `3` analysis unavailable.
Unavailable analysis is not a pass.

**Consume the preflight before any risky Mendix model integration** (merging a branch that changed the model, cherry-picking
model commits, restoring units, replaying MDL onto a model with parallel history). Record the report path in the mission.

## Strategy resolver

Exactly one `strategy` per report (`strategy_alias` keeps the earlier vocabulary):

| Strategy (alias) | When |
|---|---|
| `STUDIO_PRO_MERGE` (`MERGE_NATIVE`) | both heads MPR/mxunit-consistent, same MPR format and Mendix major.minor, no real shared semantic unit, no delete/modify, no real identity divergence, no security-critical conflict |
| `STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW` (`MERGE_NATIVE_WITH_CONFLICT_REVIEW`) | real shared semantic units, delete/modify, real identity divergence or security-critical competing semantics exist. Studio Pro merges; only the listed conflicts are reviewed (Concord for analysis and resolution). Required actions list identity reconciliation and security decisions |
| `SEMANTIC_RECONCILIATION` | an artifact was rebuilt under a new UUID on one side while its previous line was semantically modified on the other (`REBUILD_CONFLICT`): the modification must be ported deliberately |
| `REPLAY_REQUIRED` | MPR format change, Mendix major.minor mismatch, no common ancestor, more than 100 real shared semantic units (complex shared mutation), or recorded evidence that native reconciliation was insufficient (`--native-reconciliation-failed`) |
| `BLOCKED` | a head's `.mpr` registry and `mprcontents` disagree (missing units, orphan mxunits, hash mismatch) or the Git index guard blocks |

The report's `concord_scope` is the targeted conflict scope for Studio Pro conflict resolution and Concord: shared semantic units,
delete/modify conflicts, real identity divergences and every item that needs a security decision (`decision_required`). Serialization
noise, one-sided changes and deterministic identity replacements are explicitly out of scope; Concord is not asked to review them.

Rules that are not negotiable:

- `.mpr` changed on both sides is **not** a risk signal. In MPRv2 every write changes the registry (`ContentsHash`, global
  transaction row). Only semantic overlap decides.
- A **criss-cross history** (several merge bases) is reported explicitly. A unit's outcome (`TARGET`, `SOURCE`, `BOTH`) is evaluated
  against every base; if it differs, the result is `BASE_DEPENDENT` and no single merge base may decide it.
- **Competing security semantics** (`GUARD_COLLAPSE`: a boolean literal against a guard expression such as a role/permission
  path, `PROTECTED_MARKER`, `Security$*` units) require an explicit recorded decision. They are never won or lost by merge base or merge order.
- **IDENTITY_DIVERGENCE**: the same artifact (`$Type`, module, name) with different UnitIDs on target and source. Effect per base:
  `DUPLICATE_AFTER_MERGE`, `REBUILD_CONFLICT`, `MUTUAL_DELETE`, `BASE_DEPENDENT` are real; `TARGET_LINE_WINS` /
  `SOURCE_LINE_WINS` are deterministic and harmless. Real divergences need explicit identity reconciliation (keep one UUID line,
  port content, re-point references) so that no duplicate artifact names remain.
- A historically damaged merge base (orphans, missing units) is a warning, not a blocker, as long as target and source are consistent.

## Serialization noise

Comparison is structural on BSON, never a text diff. Classes: `BYTE_IDENTICAL`; `SERIALIZATION_ONLY` (key order, int32/int64, list
markers, regenerated `$ID`s, order of the order-free graph containers `Objects` and `Flows`); `DEFAULTS_ONLY` (explicit default values);
`PRESENTATION_ONLY` (geometry: size, position, flow curves); `SEMANTIC`; `UNPARSEABLE` (treated as semantic). Only semantic
changes create overlap. The weaker classes are always reported separately and never hidden. Ordered arrays (widgets, parameters,
enumeration values) are compared in order. Known limit: structurally identical sibling nodes can tie when sorting graph containers;
that fails toward `SEMANTIC` (conservative).

## Post-merge integrity gate

After every Mendix model merge run `postcheck`, at the point of the workflow it belongs to (`--stage`):

| Stage | Run | Open Concord scope |
|---|---|---|
| `studio-pro-merge` | right after Studio Pro merged | tolerated and reported as `OPEN` (`state: OPEN_ITEMS`, exit `5`); structural damage (inconsistent registry, lost units, missing features) is already a hard `FAIL` |
| `concord-resolution` | after the listed conflicts were resolved | not tolerated: duplicates, unresolved security decisions or lost guards are `FAIL` |
| `final` | before the merge commit or on the committed merge revision | same strictness as `concord-resolution`; the only stage that sets `final_integrity_gate: PASS` |

A merge is not complete until the `final` stage reports `PASS`; `INCOMPLETE` (a check could not run) and `OPEN_ITEMS` are not `PASS`. Presence, registry consistency, identity and guard retention are machine-verified; the semantic correctness of manually resolved shared units is not (`scope.shared_semantic_content_machine_verified: false`). Checks: unresolved Git conflicts; every registered unit has its mxunit and no orphan mxunits remain, hashes match (a state
like 2132 registry entries against 2243 mxunit files is `BLOCKING`); no duplicate artifact names; no lost units (reported with
`restore_from` and `restore_path`); expected features of both branches present; protected markers and guard expressions preserved;
security decisions resolved. Giving up a protected guard requires `--accept-security-decision <identity>`, which is recorded in the report.

## Identity preservation

Restoring an existing unit with a stable identity beats recreating an equivalent artifact, whenever the historical unit can be
reconstructed from Git (`restore_from` names the revision). Recreating a lost microflow under the same name creates a new UUID
and future delete/add conflicts. Restore through Studio Pro or Concord, never by copying an mxunit file by hand (the `.mpr`
registry and hash must stay consistent).

## Mutation guidance (measured, not assumed)

Prefer an identity-preserving mutation: `ALTER` whenever the change can be expressed that way. There is no blanket ban on
`CREATE OR MODIFY` or `DROP` + `CREATE`, but their behavior is not a no-op. Measured with mxcli v0.20.0 on a public MPRv2
reference project (one microflow, 26 `$ID`s): applying the unchanged `DESCRIBE` output with `CREATE OR MODIFY` regenerated 10 of 26
`$ID`s, reordered `Objects`/`Flows`, reset layout and lost two activity captions; `DROP` + `CREATE` regenerated 24 of 26 `$ID`s and
a new `StableId`. The unit file name (UnitID) stayed the same in all cases. Use `DROP` + `CREATE` only with a stated reason. Do
not claim ID stability for `CREATE OR MODIFY`.

## Normalization

No permanent workflow may require a large Studio Pro formatting commit after every mxcli change. A bounded normalization pass
(open and save in Studio Pro, committed separately from semantic work, before fanning out parallel branches) is an explicit
**WORKAROUND**, labeled as such in the mission record. The long-term fix is upstream: mxcli must write units compatible with Studio
Pro serialization (`docs/upstream/mxcli-serialization-stability.md`). Do not mask that finding with additional policy text.

## Cross-Tool Model Freshness

Freshness is a transient property of a tool's model view, not a second lifecycle state machine.
After a mutation, mark every other verification view that may lag as `SYNC_REQUIRED` until the
tool's documented synchronization boundary completes. Use `SYNC_IN_PROGRESS` only while that
required sync is actually running; then establish `FRESH` from readback or a successful
post-sync validation. Use `NOT_OBSERVABLE` when freshness cannot be established.

In particular, assess `Concord -> Studio Pro`, `mxcli -> Studio Pro`,
`filesystem/mprcontents -> Studio Pro`, `Studio Pro -> mxcli diff`, and runtime evidence after a
model change. For Concord, use `concord.sync_files` only when the current tool contract identifies
it as the required boundary. Require a sync only where the concrete path does not synchronize automatically.
A verification result from a known stale view cannot produce `PASS`; do not infer freshness from
tool success or event order alone.

## Mutation Timeout and Unknown Outcome

A timeout or lost response after a state-changing request is `RESULT_UNKNOWN`, not failure and
not success. Mark the mutation unresolved, then use an authoritative readback to compare the
current state with the requested change before proceeding. Do not blindly retry an identical
mutation before that readback. If available, record the recovery need with the existing
`recovery_required` run event; the event is audit evidence, not lifecycle authority.

## Orchestration

- `implementation-agent` consumes the preflight before a risky model integration and the postcheck before claiming it finished.
- `commit-authority.md`: a Mendix model merge commit needs a `PASS` postcheck as evidence.
- `operating-mode.md`: route selection (`LIVE-SP-CURRENT` Studio Pro, `CLOSED-AUTONOM` validated alternative) is unchanged; this policy only adds
  the decision and the gate.
- Consumer repositories are never modified by this tooling.
