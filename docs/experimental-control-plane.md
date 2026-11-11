# Experimental Control Plane: SAK Analysis and Transfer

Status: analysis and experiment contract; no SAK source files were changed.
Branch: `experiment/control-plane-sak-principles`.
Baseline: `mxagile-reality-hardening-2026-11-11` at `53bf7d63ef4a3de8aa10564edbf09dd03a94b91c`.
Full Release Gate: intentionally not run at this checkpoint.

## Decision Summary

MxAgile already has canonical Mission/Wave state, context re-sync, update blocking, bounded
delegation records, capability evidence, source fingerprints, and derived status projections.
The experiment must not add another mission, wave, run, or board store. Its narrow gap is a
single deterministic evaluator that consumes those existing facts plus explicit host observations
and returns a structured decision for transition, mutation, or delegation.

Phase 1 is a dry, host-neutral evaluator. It does not execute writes, spawn agents, change the
Mendix model, merge, push, deploy, or treat a caller's claim as host evidence. Missing or stale
facts produce `BLOCK` or `NEEDS_HUMAN`, never an inferred allow. Host enforcement and live
Studio-Pro/Concord validation remain later work.

## Reference Provenance

The supplied SAK tree is `D:\User Testing\spec-agent-kit`. Its README reports Kit `0.8.0`; the
provided tree has no `.git`, `LICENSE`, or `LICENSE.md`, and no `graphify-out/graph.json`. Therefore
this report cannot verify its commit, history, dirty state, exact license, or claims against a
remote revision. No SAK code, prompt, or schema was copied. The analysis is a read-only inspection
of the supplied files; SAK tests were not run because doing so could create caches or other files.

Labels used below:

- `SAK_FACT`: directly present in the supplied source, schema, documentation, or tests.
- `SAK_INFERENCE`: a control-boundary conclusion derived from those facts.
- `MXAGILE_TRANSFER_CANDIDATE`: a mechanism to evaluate for this experiment.
- `NOT_TRANSFERABLE`: a mechanism whose assumptions conflict with MxAgile's delivery model.
- `OPEN_QUESTION`: evidence is absent or not observable in this source snapshot.

## Private SAK Findings

### Architecture and authority

| Area | Finding and evidence |
|---|---|
| Product shape | `SAK_FACT`: mixed repository: `packages/contracts`, Python `packages/engine`, agent blueprints, and a TypeScript dashboard. `README.md`, `docs/architecture.md`. |
| Contract authority | `SAK_FACT`: `packages/contracts/schema` is declared the source for event and board contracts; generated Python/TypeScript representations are checked. `AGENTS.md`, `.specify/memory/constitution.md`. |
| State machine | `SAK_FACT`: `pipeline/states.py::TRANSITIONS` and `plan_transition` allow only listed run-state edges, reject invalid edges without mutation, and enforce run kind and round limits. Tests: `tests/pipeline/test_states.py`. |
| Persisted run state | `SAK_FACT`: each run is a `run.json` under `.spec-agent/state/runs/<run_id>/`; `runs.write_run` uses temp-file replacement. Paused runs release the active-run lock; stale takeover requires a reason. `pipeline/runs.py`, `pipeline/commands.py::cmd_preflight`, tests `test_preflight.py` and `test_pause_resume_takeover.py`. |
| Event stream | `SAK_FACT`: validated `sak.event/1` events append to `.spec-agent/state/events.jsonl`; malformed lines are skipped when read. `pipeline/events.py`, `packages/contracts/schema/event.schema.json`. `_event` records an invalid-event warning rather than undoing the already-written run state. `pipeline/commands.py`. |
| Status projection | `SAK_FACT`: the local board is rebuilt from specs, Git, runs, and events; the dashboard receives metadata snapshots/events, not code or prompts. `README.md`, `docs/architecture.md`. The board is a projection, not lifecycle authority. |

### Gates, roles, and recovery

| Area | Finding and evidence |
|---|---|
| Preflight | `SAK_FACT`: validates config/spec/tasks, requires a clean tree, checks the active/stale run, resolves a base branch, then persists a run ID, branch/base commit, roles, commands, and events. `pipeline/commands.py::cmd_preflight`; `tests/pipeline/test_preflight.py`. |
| Builder gate | `SAK_FACT`: `run built` calls `guard`, then moves to review or escalates. Protected paths are detected after the builder has worked; they are not blocked at each file write. `pipeline/commands.py::cmd_built/cmd_guard`; `tests/pipeline/test_built.py`. |
| Reviewer integrity | `SAK_FACT`: a SHA-256 snapshot includes HEAD, dirty-file contents, Git diff, and new top-level directories. A later snapshot mismatch escalates `review_integrity`. It is post-agent detection. `pipeline/commands.py::snapshot_hash/cmd_reviewer_check`; `tests/pipeline/test_guard_snapshot.py`. |
| Roles and spawn | `SAK_FACT`: the Orchestrator Skill starts Builder, optional Docs, then active review agents; it requires one parallel dispatch of active review roles. The engine returns configured role names, models, effort, and commands. `templates/claude/skills/sak-pipeline/SKILL.md`, `pipeline/commands.py::_roles_info/cmd_preflight`. |
| Child input | `SAK_FACT`: the prompt supplies Spec, round, base commit, role-specific commands, prior `[must]` findings and, to reviewers, the builder report and snapshot; worktree mode explicitly supplies the worktree path. No conversation transcript is a formal engine input. `sak-pipeline/SKILL.md`. |
| Child output | `SAK_FACT`: reviewers return a constrained Markdown verdict with `Verdict`, `Reason`, and `[must]`/`[may]` findings. `pipeline/verdict.py::parse_verdict` validates syntax and converts `approve` plus a must-finding to effective `changes_requested`. `tests/pipeline/test_verdict.py`. |
| Verdict combine | `SAK_FACT`: every active reviewer must have a valid verdict; missing verdicts reject. The strongest verdict wins; changes begin another round below the limit, otherwise escalate; `needs_human` escalates. `pipeline/commands.py::cmd_verdict/cmd_combine`; `tests/pipeline/test_combine.py`. |
| Review loop | `SAK_FACT`: `max_rounds` is persisted in the run; at the limit the engine escalates with `round_limit` and reports operator options. Tests cover max-round and no-return-at-limit behavior. `pipeline/states.py`, `pipeline/commands.py::_round_limit_hints`, `test_combine.py`. |
| Human decisions | `SAK_FACT`: the Orchestrator Skill requires explicit approval for each Spec start, release of an escalation, and deploy. Engine transitions validate state, reason, and evidence, but do not authenticate which human issued a CLI command. `sak-pipeline/SKILL.md`, `pipeline/commands.py::cmd_release`. |
| Pause/resume/abort | `SAK_FACT`: state and `paused_from` persist in `run.json`; resume requires the requested run paused, a free active-run slot, a valid prior state, and a clean tree before switching branches. Abort is terminal; it does not delete the worktree. `pipeline/commands.py`, `test_pause_resume_takeover.py`, `test_worktree_mode.py`. |
| Worktree isolation | `SAK_FACT`: opt-in Git worktrees isolate the working tree while run state/events remain in the main checkout. `built` and `reviewer-check` detect overlap after work. Cleanup refuses to remove a dirty managed worktree. `pipeline/commands.py`, `pipeline/runs.py`, `test_worktree_mode.py`. |
| Slots | `SAK_FACT`: `{slot}`/`{run}` are deterministic substitutions in configured test/setup/teardown commands by role. This does not itself provision or verify a database/runtime. `pipeline/slots.py`, `sak-pipeline/SKILL.md`. |
| Hooks | `SAK_FACT`: `SubagentStart/Stop` record role/duration, use a short lock, and always return silently with exit 0 on error. Claude templates install these hooks; Copilot uses native tasks as an approximation. `pipeline/hooks.py`, `settings.fragment.json`, `tests/pipeline/test_hooks.py`, `README.md`. |
| Merge/push/deploy | `SAK_FACT`: merge is CLI-gated on `approved` and clean trees; push is a separate, policy-configured operation; deploy is Orchestrator-only and requires explicit approval. The engine never pushes tags or force-pushes. `pipeline/commands.py::cmd_merge/cmd_push`, `sak-pipeline/SKILL.md`, Constitution IV. |

### Control-boundary interpretation

- `SAK_INFERENCE`: the engine is authoritative for persisted run-state transitions and verdict
  combination when its CLI is used. It is not a universal host pre-tool authorization layer.
- `SAK_INFERENCE`: reviewer immutability and builder path restrictions are prompt/tool-policy
  instructions backed by post-agent diff/snapshot checks; they detect many violations after the
  fact rather than making every write impossible.
- `SAK_INFERENCE`: hook failure is intentionally fail-open for telemetry availability. Hooks are
  not the state machine or the gate authority.
- `SAK_INFERENCE`: human approval is an orchestration contract, not an authenticated principal
  bound cryptographically to `run.release` or `run.merge`.
- `OPEN_QUESTION`: the supplied snapshot does not establish exact source commit, license text,
  real-project pilot results, CI execution on a remote, or the remaining operator acceptances
  called out in `README.md` (including Specs 013, 016, 017 and 018).

## Public Secondary Reference

The public [GitHub Spec Kit Agentic SDD reference](https://github.github.io/spec-kit/reference/agentic-sdd.html)
documents a command-led sequence from constitution/specification through plan, tasks, implement,
and converge. It says clarify, checklist, and analyze are optional quality gates; only specify is
strictly required before plan. Its [customization guide](https://github.github.io/spec-kit/how-to/customization.html)
emphasizes integrations, extensions, presets, workflows, workflow steps, bundles, and project-local
overrides.

- Public advantage: broad process composition and host integrations; teams can add or adapt
  workflows without replacing the core process.
- Private SAK advantage: a dedicated engine with persistent run IDs/state, enforced transition
  edges, gate combination, pause/resume, and post-agent integrity checks.
- Public source reviewed here does not establish a cross-host delivery state machine, tool-level
  mutation authorization, or post-agent scope fingerprint contract. Treat those as
  `OPEN_QUESTION`, not as proof that no implementation exists elsewhere in the public project.
- MxAgile fit: borrow composition and explicit step outputs; keep its authoritative Mission/Wave,
  Requirements, Decisions, Findings, Context Epochs, update state, evidence, and parity model.
  Mendix model writes, Studio Pro identity, runtime evidence, HTML-first materialization, and
  long-lived artifact reconciliation cannot be reduced to a code-only Git diff.

## MxAgile Baseline

Existing authority and evidence:

- `.mxagile/lifecycle.yaml` defines phase `next`, `returns_to`, entry/exit conditions, and gates.
- `planning/lifecycle/process-state.yaml` is the canonical per-Wave phase/gate state; its
  contract is `.mxagile/schemas/process-state.schema.json`.
- `planning/mission/mission-state.yaml` carries mission identity, active Wave, scope, blockers,
  completion criteria, and progress; its contract is `.mxagile/schemas/mission-state.schema.json`.
- `.mxagile/policies/lifecycle-resync.md` requires branch/HEAD, Mission, registered Wave, gates,
  operating mode, and parallel-work observations before write/delegation; unknown/conflicting
  context blocks those operations.
- `.mxagile/policies/update-contract.md` blocks delivery for active/partial update states and
  requires same-target recovery/re-sync.
- `.mxagile/policies/agent-delegation.md`, `Save-MxAgileRoutingDecision.ps1`, and
  `routing-decision.schema.json` persist route, actual spawn outcome, source fingerprints,
  result consumption, and stale-result rejection. The handoff/result contracts bind a child to
  the parent's `delivery_context` and bounded scope.
- `scripts/Read-MxAgileEpochCheckpoint.ps1` performs bounded field extraction, not full JSON
  Schema validation; downstream scripts add mission and reference checks. This is not a general
  transition evaluator.
- `scripts/build_project_status.py` derives Mission/Wave status and reports missing, stale, or
  conflicting sources. Its Board output is a projection and must not become a new authority.

The gap hypothesis is intentionally narrow: transition graph and preconditions are distributed
across declarative lifecycle data, schema, Re-Sync policy, and operational procedures; there is no
single executable `can_transition`/`can_mutate`/`can_delegate` evaluator. The existing delegation
path is already comparatively strong, so Phase 1 must reuse it rather than replace it.

## Transfer Matrix

Classes: A = already equivalent/better; B = direct low-risk transfer; C = transfer only after
MxAgile-specific adaptation; D = likely harmful; E = later candidate.

| Mechanism | Class | Expected benefit | Main risk / second source of truth | Host and Mendix constraint | Test and rollback |
|---|---:|---|---|---|---|
| Central state machine | A | One deterministic lifecycle vocabulary. | A second Mission/Wave/run state would conflict with `lifecycle.yaml` and canonical state. | Preserve semantic lifecycle and per-Wave granularity. | Assert evaluator reads canonical files; remove evaluator without data migration. |
| Technical transition validation | C | Reject illegal edges and missing gates before a phase change. | Duplicating natural-language entry conditions as a second workflow. | Derive edges from `lifecycle.yaml`; unknown gate semantics return `unavailable`. | Table-driven positive/negative transitions; evaluator is removable. |
| Mutation authorization | C | Block stale, unscoped, update-blocked or unauthorized writes. | Treating a caller's boolean as proof of user authorization. | Include file, Mendix model, and runtime operations; mode/tool route must be observed. | Negative fixtures for stale HEAD, unknown mode, partial update, scope escape; no default enforcement claim. |
| Delegation authorization | A/C | Keep child scope and capability tied to parent's context. | Duplicate routing/handoff/result artifacts. | Reuse existing route writer, handoff schema, actual host spawn evidence; child never receives lifecycle authority. | Existing delegation tests plus guard mismatch/unknown cases; can disable evaluator. |
| Structured verdicts | B/C | Machine-readable pass/fail/needs-human/partial/unavailable with evidence references. | A new verdict becoming competing gate truth. | Verdict evidence must bind model/runtime/browser scope, not only Git. | Schema and contract tests; keep verdict as evidence, not state mutation. |
| Combine/gate evaluation | C | Deterministic aggregation without an agent self-approving. | Flattening quality, UI, security, acceptance, or human gates into one score. | Keep dimensions separate; only combine explicitly required predicates. | Pairwise truth-table tests; revert to existing gate owners. |
| Protected paths | A | Preserve existing path ownership checks. | Git paths alone miss generated config, model elements, and runtime state. | Retain company/project-layer ownership and Studio Pro route rules. | Existing installer/ownership tests; no new protected list unless owned by canonical policy. |
| Protected Mendix Model Units | C | Detect writes outside authorized entity/page/flow scope. | Unit identity/version may be unavailable or unstable. | Require mxcli/Studio-Pro evidence; unknown unit identity blocks model mutation. | Synthetic model-unit fixtures then live adapter tests; remain advisory until measured. |
| Post-agent scope check | C | Detect child edits outside bounded write scope. | After-the-fact detection does not prevent damage and Git diff misses model/runtime changes. | Compare Git paths plus model-unit and runtime evidence where observable. | Positive/negative file and model fixtures; label gaps `not_observable`. |
| Run IDs | E | Correlate a bounded operation across handoffs. | A second lifecycle/run registry beside Mission, Wave, delegation, and Context Epoch IDs. | Prefer existing mission/wave/delegation IDs; add correlation ID only if justified. | No persistent registry in Phase 1; remove correlation field without migration. |
| Event stream | E | Durable event audit and resume. | Duplicates timeline, Context Epoch, artifact provenance, and Git history. | Never send source, prompt, secret, or Mendix model content to a generic event sink. | Later candidate only after ownership/retention design; no stream in Phase 1. |
| Round limits | A/C | Bound retries and force escalation instead of loops. | Fixed review rounds can be wrong for Discovery, reconciliation, or iterative visual work. | Keep existing gate-specific retries and human decisions; no global numeric limit. | Test stop condition per gate; avoid global loop config. |
| Human escalation | A | Preserve decisions that require developer meaning/approval. | Convert every unknown into a blocking question, degrading safe progress. | Scope escalation to mutation, authorization, security, and lifecycle boundaries. | Test unknown vs known-safe paths; report `NEEDS_HUMAN` with reason. |
| Pause/resume | A | Reliable continuation after interruption. | New pause state conflicts with Context Epoch and mission resume semantics. | Re-sync current Git, update, runtime, and Mendix state before reusing evidence. | Existing lifecycle-resync tests; no new durable pause record. |
| Worktree slots | C | Isolate independent high-code tasks and reviewer diffs. | Worktrees do not isolate Studio Pro, `.mpr`, shared DB, or shared runtime. | Only opt in where Git isolation is real; coordinate model/runtime ownership separately. | Git overlap tests plus model-sharing negatives; no automatic worktree creation in Phase 1. |
| Runtime slots | E/C | Avoid shared database/port collisions. | Port substitution is not a runtime lease or ownership proof. | Use existing C1 runtime recipe, ownership, and process recovery; never infer safe termination. | Runtime fixture/lease tests before any adapter; defer. |
| Merge automation | D | Faster completion in a code-only pipeline. | Contradicts explicit commit/release authority and can bypass Mendix verification. | No automatic merge/push into the stable framework or consumer projects. | Not implemented; requires a separate explicit authorization design. |
| Deployment gates | A/D | Explicit deploy readiness and operator approval. | Reusing SAK autonomy could weaken MxAgile release/security evidence. | Keep project release checkpoint and explicit user approval; no deployment automation. | Existing release/checkpoint tests; no implementation in this experiment. |
| Gate fingerprints | C | Invalidate verdicts when relevant inputs change. | Whole-repo hashes create false staleness; partial hashes miss source changes. | Fingerprint only referenced REQ/Decision/Mockup/Page/model/runtime inputs. | Mutation tests per referenced input; reuse existing fingerprint schemes. |
| Evidence binding | A/C | Preserve evidence source, identity, and freshness. | Duplicate evidence manifests or claim fresh evidence from a changed model/runtime. | Reuse TC/VPL/campaign/evidence-manifest and provenance references. | Existing schema and stale-evidence tests; verdict adds references only. |
| Board projection | A | Make status visible without another database. | SAK's Board model is not a substitute for MxAgile Mission/Artifact graph. | Extend derived project status only when a clear consumer exists. | Existing projection parity tests; no persisted Board state. |

## Phase 1 Contract

The prototype has three pure, read-only operations:

```text
can_transition(current_facts, requested_transition) -> GateVerdict
can_mutate(current_facts, requested_scope, operation) -> GateVerdict
can_delegate(current_facts, persisted_route, handoff) -> GateVerdict
```

- Canonical facts come from existing Mission/Wave/process-state, lifecycle, update transaction,
  Context Epoch, routing decision, and handoff artifacts. Host observations (active tool, operating
  mode, project identity, explicit authorization signal) are separate inputs and carry provenance.
- Current branch/HEAD and referenced artifact hashes are rechecked at evaluation time. A stale or
  mismatched reference cannot pass.
- `can_transition` derives allowed edges from `lifecycle.yaml`; it does not create a transition
  registry. It checks machine-readable gate results and refuses to infer unstructured conditions.
- `can_mutate` requires the active Mission/Wave, implementing eligibility, an explicit bounded
  scope, current Context Epoch, no blocking update transaction, and a mode-compatible observed
  tool route. Missing user authorization is `needs_human`; unknown technical facts are
  `unavailable` or `needs_human`, never `pass`.
- `can_delegate` reuses a persisted routing decision and the existing handoff contract. A write-capable
  child cannot receive more authority than its parent. Unknown spawn capability or invisible spawn
  tool means no write-capable delegation.
- The evaluator does not write state. The returned verdict is evidence only; existing lifecycle
  gates remain authoritative until host adapters and operational tests prove enforcement.

### Gate Verdict Contract

The experimental schema will carry `gate_id`, `gate_type`, `verdict` (`pass`, `fail`,
`needs_human`, `partial`, `unavailable`), optional SAK `run_id`, MxAgile `mission_id`/`wave_id`,
producer, input/evidence references with fingerprints, must/should findings, scope, checked roles
and states, and `created_at`. The verdict cannot set Mission/Wave state, accept a requirement,
complete a gate, or authorize a later mutation by itself.

### Phase 1 Exit Criteria

- Every API has deterministic table-driven pass and refusal cases.
- Unknown/stale facts never produce `pass`; update blockers and scope escape always refuse writes.
- A write-capable child can never pass when its parent context or observed spawn capability is
  absent.
- Verdict schema rejects extra fields, invalid enums, missing provenance, and malformed evidence
  fingerprints.
- No changes to the SAK tree, CapTrack/consumer projects, generated projections, remote branches,
  merge/deploy behavior, or existing lifecycle state stores.
- Unit/contract checks do not claim host-level enforcement. Live adapter verification is a later
  integration gate.

## Update and Migration Contract

Binding rule for this experiment: every persistent structure or new invariant needs an explicit
upgrade path through the existing Core update, Doctor, provenance and recovery mechanisms. No
separate `control-plane-migrate` path is introduced.

### Phase 1 persistent footprint

| Change | Persistent in consumer projects? | Upgrade answer |
|---|---|---|
| `experiments/control-plane/guard.py` | No. Not distributed by `install-core.ps1`; never writes. | Nothing to migrate. Removing the experiment leaves no consumer state. |
| `control-plane-verdict.schema.json` 1.0 | No. Transient stdout only. | A future persisted form must bump `schema_version`, ship via `install-core.ps1`, and get a Doctor compatibility projection before any reader requires it. |
| New invariants (transition/mutation/delegation checks) | No new field is required. | Every input already exists canonically or is derived; optional legacy keys stay optional (see below). |

### Existing mechanisms the guard consumes instead of re-implementing

- Version detection: `.mxagile/state/core-provenance.json` (Core commit/version) and the
  persisted `update-transaction.json`; PREVIOUS -> CURRENT is recorded in `last-update-result.json`.
- Schema compatibility: the existing Doctor (`build_project_status.build_status` ->
  `project_compatibility`, including its legacy `compatibility_projection`). The guard does not
  run its own strict schema validation of Mission/Wave/Epoch artifacts.
- Partial states: `update-transaction.json` (`UPDATE_IN_PROGRESS`, `PARTIAL_UPDATE`,
  `UPDATE_FAILED_ROLLED_BACK`, `BLOCKED_BEFORE_MUTATION`, `UPDATE_INSTALLED_RESTART_REQUIRED`,
  `COMPATIBILITY_NOT_VERIFIED`) and `.mxagile/migration/state.yaml` (`status`,
  `artifact_canonicalization`). These are the existing equivalents of `MIGRATION_IN_PROGRESS`,
  `MIGRATION_PARTIAL`, `MIGRATION_FAILED` and `MIGRATION_NEEDS_HUMAN`.
- Context invalidation: a Core update newer than the Context Epoch `checkpoint_time` yields
  `CONTEXT_STALE_AFTER_UPDATE` until `Write-MxAgileEpochCheckpoint.ps1` records a re-sync.
  `READY` stays session-derived and is never read from a stored file.

### Guard behavior on old or partially migrated projects

| Observed state | Verdict | Allowed recovery |
|---|---|---|
| Migration `in_progress` / canonicalization `in_progress` | `fail` | `resume` |
| Migration status other than `complete` | `needs_human` | `inspect` |
| `artifact_canonicalization: pending` (hybrid) | no block, advisory | none required |
| `UPDATE_IN_PROGRESS` / `PARTIAL_UPDATE` | `fail` | `resume` (same target) |
| `UPDATE_FAILED_ROLLED_BACK` / `BLOCKED_BEFORE_MUTATION` | `needs_human` | `inspect` |
| Update newer than last re-sync | `unavailable` | `resync` |
| Doctor `BLOCKED` | `fail` | `doctor` (existing repair plan) |
| Missing Mission/process-state/wave plan (not derivable user intent) | `needs_human` | `human_resolution` |
| Missing Context Epoch | `unavailable` | `resync` |
| Older Wave without optional `testability_gate` | no block, advisory | none (gate_to_ready is authoritative) |
| Missing optional `mutation_eligibility` | no block | none; only `blocked`/`violation_detected` refuse |

Normal delivery (transition, mutation, write-capable delegation) is never `pass` in a migration,
update or stale-context state. Only the listed recovery actions remain valid.

### Answers to the migration questions (Phase 1)

1-3. Source is the tagged baseline `mxagile-reality-hardening-2026-11-11`; target is the current
branch; version is detected from Core provenance and the update result. 4. Backward compatible:
no new persisted structure. 5. Responsible step: the existing `install-core.ps1 -IsUpdate`,
followed by its Doctor. 6-8. Idempotent/resumable/recovery state are those of the existing
update transaction; the guard adds no state. 9. No derived artifact is introduced; projections are
regenerated by the existing installer. 10. A new session sees `update-transaction.json`,
`migration/state.yaml` or a stale Context Epoch. 11. Transition, mutation and write delegation are
refused while any of these is active. 12. `READY` after a clean update, non-BLOCKED Doctor and a
Context Epoch re-sync newer than the update.

### Baseline upgrade acceptance

`tests/test-control-plane-upgrade-from-baseline.ps1` builds the baseline tag via `git archive`,
installs it into a GUID project, adds legacy lifecycle state, updates to the current branch,
checks provenance PREVIOUS -> CURRENT, Doctor, project-owned file preservation and absence of an
active transaction, proves the guard refuses before re-sync, then re-syncs and uses the guard. It
returns UNAVAILABLE (exit 2) without a cached mxcli or when HEAD equals the baseline commit.

## Phase 1B: Mandatory Enforcement

### Enforcement point inventory

MxAgile has no framework-owned mutation chokepoint today: agents mutate through host tools.
`scripts/mxcli-exec-guarded.ps1` is referenced nowhere and is not a real path.

| Path | Host mechanism | Class | Phase 1B |
|---|---|---|---|
| Studio-Pro-MCP / Concord MCP write tools | `mcp__mendix-studio-pro__*`, `mcp__concord__*` | IMPLEMENTATION_WRITE (read verbs: READ) | enforced by adapter |
| mxcli model mutation | Bash `mxcli exec/create/alter/...` | IMPLEMENTATION_WRITE | enforced by adapter |
| Direct file edit | Write/Edit/MultiEdit/NotebookEdit | by path: IMPLEMENTATION / EVIDENCE / LIFECYCLE / FRAMEWORK / DERIVED | IMPLEMENTATION enforced |
| Shell file edit outside known patterns | Bash | READ (not detectable) | **not enforced** |
| Git mutation | Bash `git commit/push/...` | EXTERNAL_SIDE_EFFECT | classified only |
| Child spawn | Agent/Task tool | CHILD_SPAWN | enforced by adapter (handoff + `can_delegate`) |
| Core / Company / Project Layer update, migration | `mxagile-setup*`, `install-core`, `update-layer`, `canonicalize_artifacts` | FRAMEWORK_WRITE | intentionally open (recovery path) |
| Lifecycle transition | write to `planning/lifecycle/`, `planning/mission/` | LIFECYCLE_WRITE | main agent only; never delegable |
| Evidence / verification write | `planning/evidence/`, `.concord/evidence/`, parity, campaigns | EVIDENCE_WRITE | lightweight; bounded for children |
| Derived projection rebuild | `.mxagile/state/`, routing/result records, `requirements/`, `specs/` | DERIVED_PROJECTION_WRITE | lightweight |
| Unknown host tool | any | IMPLEMENTATION_WRITE | fail-closed |

### Architecture choice

Option D (hybrid), Phase 1B subset: `guard.py` stays the read-only authority;
`enforcement.py` is a host PreToolUse adapter that classifies each call, skips the guard for
lightweight classes and turns guard verdicts into allow/deny for IMPLEMENTATION_WRITE and
CHILD_SPAWN; `child_contract.py` accepts or rejects a finished child deterministically. Host hooks
alone (A) are not the authority because of the known SessionStart/hook reality gaps; a central
wrapper (B) cannot intercept host-native tools; tool-specific adapters (C) would duplicate the
decision. A guard exception or unclassifiable call is a deny (`GUARD_UNAVAILABLE`).

Mutation authorization is derived from canonical state only: active Mission and registered active
Wave in `implementing` (the canonical record of developer approval), fresh Context Epoch, no
update/migration blocker, non-BLOCKED Doctor. Missing Mission/Wave yields `MISSION_WAVE_REQUIRED`
with `human_resolution`; no Wave is inferred.

### Visual verification gate and child contract

- Routing: a mockup-vs-app request with gaps/dynamics/visual terms resolves to
  `runtime_visual_verification`, never static analysis.
- Handoff: the existing delegation handoff is extended to 1.4 (`run_id`, `capability`,
  `route_decision_reference`, `write_classes`, `evidence_destination`, `required_tools`,
  `input_sources`, `output_contract`, `parent_observations`, `authorization_reference`). 1.3
  handoffs stay valid; handoffs are not persisted consumer artifacts.
- A verifier is `read_only` with `EVIDENCE_WRITE` bounded to its evidence destination;
  `LIFECYCLE_WRITE` can never be delegated.
- Acceptance (`ACCEPTED`/`PARTIAL`/`REJECTED`/`STALE`/`NEEDS_HUMAN`): output contract, run_id
  correlation, forbidden writes (Git-observed; implementation/page changes always surfaced),
  update/migration state, base HEAD, input fingerprints. Model scope outside `CLOSED-AUTONOM`
  is `MODEL_SCOPE_NOT_OBSERVABLE` and caps the result at `PARTIAL`.
- Gate: schema, input fingerprint (`identity@digest` per mockup revision, REQ, decision, page
  implementation, role/state set, contract; no directory hashes, no timestamps), must findings
  (round < 2: `FAIL` + repair round; round 2: `NEEDS_HUMAN`), evidence existence/hash/destination,
  per role/state coverage. Static-only or incomplete runtime coverage is at most `PARTIAL`; none
  is `UNAVAILABLE`. A child claim can lower, never raise the result. `PASS` only permits the
  lifecycle owner to record `ui_verification`; it never sets a Wave state.

### Enforcement status

- Technically enforced (when the adapter is wired as Claude Code PreToolUse hook): implementation
  file writes, Mendix MCP write tools, mxcli mutations and non-read-only child spawns are denied
  without valid derived delivery authorization or a validated handoff.
- Advisory: child result acceptance and the visual gate are deterministic but must be invoked by
  the main agent; recording lifecycle consequences stays with existing gates; shell writes outside
  the known patterns; Git mutations.
- Host-dependent: the adapter speaks the Claude Code PreToolUse format. It is not installed into
  consumer projects in Phase 1B. Concord, VS Code Copilot hooks and Copilot CLI need adapters.
- Not observable: per-unit Mendix model scope, unsaved Studio Pro edits, tool-route project
  identity at the hook boundary, actual child tool calls beyond Git-visible changes.

### Event readiness (audit only)

Guard, adapter, gate and acceptance results carry an `event` candidate (`delivery_authorized`,
`delivery_blocked`, `child_started`, `child_completed`, `child_rejected`, `gate_evaluated`,
`gate_invalidated`, `repair_round_started`, `recovery_required`) with an ephemeral `run_id`
(`RUN-<12 hex>`) and `parent_run_id`. Nothing is persisted. Events document what canonical
evaluation decided; they never become lifecycle truth (`event says verified` does not imply
`verified`). No event taxonomy is fixed yet.

### Phase 2 follow-ups

Wire and migrate the adapter into generated host settings via the existing settings merge;
Concord/VS Code adapters; Studio-Pro model-unit observation; mandatory acceptance in the delegated
result reader; append-only run/event log with schema/versioning, size limits, parent/child
correlation, review rounds, interrupt/resume, compaction recovery, update/migration history,
retention/archival; DevBoard timeline, recent activity and current runs as projections. Re-use the
private SAK (`D:\User Testing\spec-agent-kit`) as reference for these.

## Open Findings and Limits

- `OPEN_QUESTION`: the supplied SAK snapshot has no Git metadata or license file; exact revision,
  history, licensing, and ownership remain unverified. No code reuse is planned.
- `OPEN_QUESTION`: SAK README reports several unaccepted real-project/Cloud trials; no tests were
  executed in that read-only tree.
- `OPEN_QUESTION`: public Spec Kit documentation describes workflows, extensions and hooks, but
  this comparison did not audit its full source for every possible engine or hook implementation.
- `OPEN_QUESTION`: current MxAgile host adapters do not provide equally observable authorization,
  active-tool, model-unit identity, and runtime ownership signals on every host.
- `NOT_IMPLEMENTED`: universal pre-tool enforcement across Claude Code, VS Code Claude, Concord,
  Copilot, Studio-Pro-MCP, and mxcli; the prototype alone cannot prevent a host from bypassing it.
- `NOT_IMPLEMENTED`: model-unit write scoping, runtime leases, automatic repair/resume, event
  stream, merge, push, or deployment automation.
- `MEASUREMENT_REQUIRED`: compare blocked unauthorized/stale operations, missed scope violations,
  false-positive blocks, and safe-work throughput before proposing promotion from the experiment.