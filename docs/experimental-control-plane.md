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

In Phase 1B these components only returned an event candidate (`delivery_authorized`,
`delivery_blocked`, `child_started`, `child_completed`, `child_rejected`, `gate_evaluated`,
`gate_invalidated`, `repair_round_started`, `recovery_required`) with ephemeral IDs. Phase 2 now
persists the deterministic subset described below. Events document what canonical evaluation
decided; they never become lifecycle truth (`event says verified` does not imply `verified`).

### Phase 2 follow-ups

Remaining after Phase 2: Concord/VS Code adapters; Studio-Pro model-unit observation; update/migration
event producers; archival and major-schema migration; lifecycle-owned event for every canonical
transition. Re-use the private SAK (`D:\User Testing\spec-agent-kit`) as reference.

## Phase 1C: Host Distribution, Mandatory Acceptance, Concord

### Product path decision

| Component | Source | Installed to | Writes consumer state | Ownership |
|---|---|---|---|---|
| `guard.py` | `experiments/control-plane/` | `.mxagile/tools/control-plane/` | no (read-only) | FRAMEWORK_OWNED_GENERATED |
| `enforcement.py` (Claude PreToolUse adapter) | same | same | no (stdout decision only) | FRAMEWORK_OWNED_GENERATED |
| `child_contract.py` (acceptor, visual gate) | same | same | no (stdout verdict only) | FRAMEWORK_OWNED_GENERATED |
| `control-plane-verdict.schema.json` | same | same | no | FRAMEWORK_OWNED_GENERATED |
| `Register-MxAgileControlPlaneHook.ps1` | `scripts/` | not distributed (installer-time only) | `.claude/settings.json` MxAgile group only | entry FRAMEWORK_OWNED, file shared |
| `Save-`/`Get-MxAgileDelegationResult.ps1` | `scripts/` | `.mxagile/tools/` | delegated result + checkpoint artifact (existing) | existing |

The source of truth stays in `experiments/control-plane/` while the experiment runs; install-core
copies it and lists it under `project_distributed` in Core provenance. Adapter → guard API:
`guard.load_project_facts(root)` and `guard.delivery_authorization(facts, op_class, run_id)` /
`guard.can_delegate(...)`; the guard resolves its helper scripts from `.mxagile/tools` when
installed and from `scripts/` in this repository. Promotion out of `experiments/` is an
integration decision, not part of Phase 1C.

### Host registration

install-core registers one structured `PreToolUse` group in `.claude/settings.json`:
matcher `Write|Edit|MultiEdit|NotebookEdit|Bash|Task|Agent|mcp__.*`, command
`python -B "$CLAUDE_PROJECT_DIR/.mxagile/tools/control-plane/enforcement.py" || exit 2`
(Claude blocks on exit 2, so an unrunnable adapter or missing Python is a deny, not a silent
allow). The MxAgile group is identified only by the marker
`.mxagile/tools/control-plane/enforcement.py`, placed first, replaced in place on update and never
duplicated; every other group and setting is preserved. Invalid JSON, a non-object `hooks`, a
non-array `PreToolUse` or a group mixing the marker with foreign hooks is `UNKNOWN_OWNERSHIP`:
the file stays byte-identical and install-core prints a WARN that enforcement is NOT active.
`-Remove` drops only the MxAgile group. The adapter prefers `CLAUDE_PROJECT_DIR` over the
tool-call `cwd` as project root.

Migration: the baseline tag `mxagile-reality-hardening-2026-11-11` and the Phase 1/1B commits
introduced no persistent host configuration, so the baseline tag is the complete upgrade baseline
for the hook; `test-control-plane-upgrade-from-baseline.ps1` proves first registration, preserved
developer hooks and an idempotent second update (`CONTROL_PLANE_HOOK: CURRENT`).

### Concord and Studio Pro host reality

- `OBSERVED` (read-only process inventory): `studiopro.exe → pwsh.exe → claude.exe →
  Concord.Mcp.exe` and `Code.exe → claude.exe → Concord.Mcp.exe`. Concord is an MCP server plus a
  Studio-Pro terminal integration; the agent host in both paths is Claude Code. Concord terminal
  settings use `pwsh`, `allowAgentRunWithoutConfirm: true`, no fixed start directory.
- `INFERRED`: the Studio-Pro-terminal Claude session loads the project `.claude/settings.json`, so
  the same hook and the same guard decision apply; Concord MCP tools appear as
  `mcp__concord-v2-mcp__*` and are classified like Mendix MCP tools (read verbs READ, everything
  else IMPLEMENTATION_WRITE). Tests prove identical deny reasons for a Studio-Pro-MCP and a Concord
  MCP write.
- `NOT_OBSERVABLE` without a live authenticated host run: whether Concord's auto-run setting
  changes hook execution, and the exact cwd of the terminal session.

### Permissions

No bypass mode is required or recommended. Claude PreToolUse hooks decide before the permission
prompt; a deny blocks independently of auto-approval. Projects should keep a narrow permission
allowlist (read tools, `git status/diff/log`, MxAgile read tools); the hook is the authority for
mutations, the allowlist only reduces prompts.

### Shell, Git and model scope

Shell commands are split on `&&`, `||`, `;`, `|` and newlines; the most severe segment wins.
Redirects and write verbs (`Set-Content`, `Out-File`, `sed -i`, `cp`, `mv`, `rm`, ...) are classified
by target path; null redirects are ignored. Git: read verbs (`status`, `log`, `diff`, `show`,
`fetch`, ...) READ, `add`/`commit`/`tag` CONTROLLED_MUTATION, `checkout`/`switch`/`stash`
CONTEXT_INVALIDATING, `reset`/`clean`/`restore`/`rm`/`push` and unknown verbs HIGH_RISK_MUTATION
(enforced), `merge`/`rebase`/`cherry-pick`/`pull`/`apply`/`am` INTEGRATION_MUTATION (enforced).
Not detected: writes from interpreters
(`python -c`, `node -e`, scripts) and obfuscated commands.

Mendix model scope: `mxcli diff-local` reports changed units in `mprcontents/` (MPR v2), so saved
model changes are Git-observable per unit and enter acceptance as implementation changes.
Unsaved Studio Pro edits and MPR v1 projects remain `NOT_OBSERVABLE`.

### Mandatory child acceptance

When a canonical handoff `.concord/delegation-handoffs/<delegation_id>.json` exists,
`Save-MxAgileDelegationResult.ps1` runs `child_contract.py accept` (handoff + optional
`verdict_reference`) and stores the deterministic `acceptance` object in the delegated result.
Python or acceptor unavailable → `NEEDS_HUMAN` / `ACCEPTANCE_UNAVAILABLE`, never ACCEPTED.
`Get-MxAgileDelegationResult.ps1` reports `reusable: true` only for ACCEPTED (or results without a
control-plane handoff, `NOT_REQUIRED`, which keeps the legacy contract). A child claim
`needs_human` lowers acceptance; no child claim raises it. The handoff embeds its
`verification_contract`, so the acceptor needs no second source. Spawn is denied unless the
handoff sits at the canonical path (`CHILD_HANDOFF_NOT_CANONICAL`).

Fixed in passing: the saver inserted the artifact entry with the script file's line endings
(CRLF under `core.autocrlf`) into an LF checkpoint and swallowed the following blank line; the
reader then reported `NOT_REFERENCED`. Line endings now follow the checkpoint.

### Enforcement status after Phase 1C

- Technically enforced in installed projects (Claude Code incl. Studio-Pro/Concord terminal):
  implementation writes, Mendix/Concord MCP writes, mxcli mutations, high-risk and integration Git
  operations, non-read-only child spawns. Verified by direct adapter calls and by the registered
  command line under Git Bash; a live Claude session followed in Phase 1D.
- Mandatory: child acceptance on save/read of delegated results with a control-plane handoff.
- Advisory: lifecycle recording after a visual PASS; CONTROLLED_MUTATION and
  CONTEXT_INVALIDATING Git operations (classified, re-sync catches the drift).
- Consequence: `git push` is denied without delivery authorization (superseded in Phase 1D:
  publication gate, host asks the developer).
- Not enforced: VS Code Copilot hooks, Copilot CLI, non-Claude hosts; interpreter-based writes.
- Doctor: hook registration state was `NOT_IMPLEMENTED` in Phase 1C (added in Phase 1D).

### Phase 2 run/event persistence (implemented subset)

| Question | Decision candidate |
|---|---|
| Location | `.mxagile/state/runs/events-<CLASS>-<YYYY-MM>.jsonl`, project-local and `.gitignore`d; never under `planning/` |
| Format | append-only JSON Lines, UTF-8, LF; lazy creation keeps eventless legacy consumers valid |
| Schema/versioning | `scripts/run-event.schema.json`, installed at `.mxagile/tools/control-plane/run-event.schema.json`; integer `schema_version: 1`; additive unknown envelope fields are accepted, unknown event types/major versions rejected |
| Identity | `event_id` (`EVT-` + UUID hex), `run_id`, optional `parent_run_id`, local path-derived `project_identity`, Mission/Wave, actor/capability/host, correlation references, structured payload |
| Classes | `PROJECT_HISTORY` (lifecycle resync/update/migration), `RUN_AUDIT` (delivery/child/round/verdict), `DIAGNOSTIC` (adapter/registration/event writer failures) |
| Producers | Guard adapter emits relevant authorization/block/publication and child-start events; Save/Get acceptor emits verdict/gate/child completion/acceptance/invalidation/repair; checkpoint writer emits resync start/completion |
| Ordering | `sequence` is monotonic per `run_id` across files/classes; a short project append lock protects sequence allocation and append. Different run IDs have no global causal order; UI sorts by UTC timestamp then run/sequence |
| Atomicity / crash | validate before append; one compact line < 8 KiB, flush + fsync; readers skip/count invalid complete lines and ignore partial tail; next append truncates only that partial tail |
| Limits / retention | 5 MiB per monthly stream, 100 MiB total; `DIAGNOSTIC` 30 days, `RUN_AUDIT` 180 days, `PROJECT_HISTORY` retained; no zip archive yet |
| Failure semantics | event write failure never changes authorization or acceptance; producer warns on stderr |
| Truth rule | events document evaluated outcomes; they are never read by lifecycle evaluators and never authorize a transition |
| Interrupt/resume | Existing `Invoke-MxAgilePostCompactionResync.ps1` calls `run_events.py resume`; re-reads Guard facts (Mission/Wave/HEAD/branch/blockers), verifies unresolved child inputs against the canonical handoff, reports `RESULT_UNKNOWN` / `NEEDS_RECONCILIATION` and `STALE`; event log alone cannot prove a process is still alive |
| Update/migration history | event vocabulary is reserved; update/migration producers are not wired in this increment |
| Privacy | no prompts or file contents; reason codes, IDs, allowlisted references and fingerprints only |
| DevBoard | Current State remains the existing artefact projection; separate Run Activity API/UI renders validated run events, unresolved runs and allowlisted evidence/reference links |

### DevBoard target picture

event), recent activity, per-Wave timeline. Layer 2 can never change Layer 1; a missing or
Layer 1 stays the canonical projection (Mission, Waves, gates, artifacts, Doctor). Layer 2 is a
read-only Run Activity view with filters (Delivery, Child Agents, Verification, Gates, Recovery,
Updates/Migrations, Warnings/Blocks), chronological events and unresolved runs. A start without a
terminal event is `RESULT_UNKNOWN`, not proof of `RUNNING`, success, or failure. Event appends
change the existing `/api/revision` response; polling refreshes only Run Activity when canonical
status is unchanged. Corrupt/missing history never changes Layer 1.

Implemented producers are deterministic: enforcement, child acceptance, and the checkpoint
writer. A caller may set `MXAGILE_RUN_ID` to correlate parent-tool events; handoffs can carry
`parent_run_id` explicitly (or via `MXAGILE_PARENT_RUN_ID`). Without either, the system does not
invent a parent. Resume output includes current Guard facts plus unresolved run/event correlation;
the agent must still re-sync and independently revalidate inputs before resuming work.

## Phase 1D: Live Host Reality

### Live Claude Code verification

`experiments/control-plane/live/claude-live-reality.ps1` (manual, costs model tokens, never in
automatic gates): disposable consumer project, normal `install-core` path, real `claude -p`
session (Claude Code 2.1.322, model haiku) in `--dangerously-skip-permissions` mode, i.e. the
same permission mode the Studio-Pro terminal uses, so a host permission block cannot mask the
result. A probe MCP server registered as `mendix-studio-pro` records every real `tools/call`.

| Step | Observed result (2026-11-12) |
|---|---|
| install | `CONTROL_PLANE_HOOK: REGISTERED`; Doctor `installation_health: HEALTHY`, live `NOT_VERIFIED` |
| negative (Wave `ready`, commit after checkpoint) | `Write` and `mcp__mendix-studio-pro__pg_patch_page` returned `PreToolUse:<tool> hook error: MxAgile control plane: HEAD_STALE, MUTATION_PHASE_BLOCKED \| recovery: resync`; target file absent; probe server received 0 calls; no Wave invented |
| positive (Wave `implementing`, committed, re-synced) | same two calls executed: file created, probe server received `pg_patch_page` |

Classification: hook loaded from the project `.claude/settings.json` `OBSERVED`; hook executed on
the real call `OBSERVED`; project root resolved to the consumer project `OBSERVED` (decision based
on its canonical state); block before mutation `OBSERVED` (bypass mode, so not a host permission
block); allow after valid delivery context `OBSERVED`.

### Concord / Studio Pro (read-only discovery, 2026-11-12)

| # | Question | Result | Class |
|---|---|---|---|
| 1 | Host process | `studiopro.exe → pwsh.exe → claude.exe --dangerously-skip-permissions → Concord.Mcp.exe --stdio` | OBSERVED |
| 2 | Configuration of the session | standard Claude Code CLI; Concord writes project `.mcp.json` (`concord-v2-mcp` stdio, `mendix-studio-pro` http `localhost:7782/mcp`, `CONCORD_PROJECT_ROOT`) | OBSERVED |
| 3 | `.claude/settings.json` used | session transcripts carry `cwd` = project root, Claude loads project settings from there; hook execution in that very session | INFERRED (same binary and mode as the live test) |
| 4 | Own Concord hook path | none found; Concord contributes MCP tools and the terminal, not an interception point | OBSERVED (absence in config), NOT_OBSERVABLE (internals) |
| 5 | Visible MCP tools | Studio Pro 11.16 `tools/list`: 18 tools (`ped_*`, `pg_*`, `read_file`, `write_file`, `execute_handler`, `compile_java`, `glob`, ...); Concord: `concord_discover`, `concord_invoke` | OBSERVED |
| 6 | Mendix mutation representation | `mcp__mendix-studio-pro__ped_update_document`, `ped_create_document`, `pg_patch_page`, `write_file` | OBSERVED (session history) |
| 7 | Child representation | `Agent` tool | OBSERVED |
| 8 | Interception options | Claude PreToolUse only | OBSERVED |
| 9 | Root information | `CONCORD_PROJECT_ROOT` env for the MCP server; Claude `cwd`/`CLAUDE_PROJECT_DIR`; sessions also `cd` into `.concord/scratch/...` (why the adapter prefers `CLAUDE_PROJECT_DIR`) | OBSERVED |
| 10 | Studio-Pro terminal vs. normal terminal | same `claude.exe`; Studio-Pro terminal starts it with `--dangerously-skip-permissions` (`allowAgentRunWithoutConfirm: true`), VS Code uses `--permission-mode=auto` | OBSERVED |

Consequence: no separate Concord adapter is needed; Concord tools reach the same Claude hook and the
same guard. Not proven live: a mutation inside the running Studio-Pro session, because the open
project (CapTrack) has no control-plane registration (Doctor: `HOST_REGISTRATION_MISSING`) and must
not be modified for a test. Status: `CONCORD_LIVE_HOOK = NOT_VERIFIED`, integration gap precisely
known (registration via the update path; then the live script's negative/positive cases apply).

Reality fixes from the observed tool list: `glob` was falsely classified as write (now READ).
`concord_invoke` (generic intent proxy, `intentOrId`) and `execute_handler`/`compile_java` stay
fail-closed (IMPLEMENTATION_WRITE): reads through `concord_invoke` are blocked outside an
implementing Wave (known false positive, safe direction).

### Doctor control-plane health

`project_compatibility.py doctor` reports `control_plane` (JSON) / `CONTROL_PLANE_INSTALLATION`
and `CONTROL_PLANE_LIVE` (human) without changing `compatibility` or exit codes: components,
registration (`REGISTERED`, `HOST_REGISTRATION_MISSING`, `CONFIG_UNKNOWN_OWNERSHIP`), fail-closed
command, matcher coverage, command target present, foreign group count, handoff schema 1.4
(`SCHEMA_INCOMPATIBLE`), `ADAPTER_FILE_MISSING`. Installation health is `HEALTHY`, `DEGRADED` or
`NOT_INSTALLED`; live verification is always `NOT_VERIFIED` (`LIVE_VERIFICATION_NOT_PERFORMED`),
VS Code Copilot `HOST_UNSUPPORTED`. No new persistent status file.

### Child acceptance hardening

Found by the Phase 1D state tests: a child with only static evidence (gate `PARTIAL`) or no
evidence (`UNAVAILABLE`) was booked `ACCEPTED`/reusable. Now the gate result feeds acceptance:
`PARTIAL`/`UNAVAILABLE` → `PARTIAL`, gate `STALE`/`NEEDS_HUMAN` adopted, invalid verdict/evidence →
`REJECTED`; a well-formed `FAIL` verdict stays an accepted child report of a failing UI. Verified
through the real Save/Get scripts: input change during the child run → `STALE`; exit 0 with
`REJECTED`/`PARTIAL`/`NEEDS_HUMAN` → parent sees exactly that state, `reusable: false`.

### Publication gate

`git push` is `PUBLICATION`: the adapter returns `ask` (`PUBLICATION_REQUIRES_DEVELOPER_APPROVAL`)
in every state, so an implementing Wave never authorizes a push and the control plane never
auto-approves one; the host asks the developer. Integration (`merge`, `rebase`, `pull`, ...) stays
delivery-authorized.

### Interpreter and code-execution bypass

`KNOWN_BYPASS_PATH`: `python -c`, `node -e`, scripts, `pwsh -Command`, and code-execution MCP tools
(observed: `mcp__plugin_context-mode_context-mode__ctx_execute`, heavily used in the Concord
session) can write implementation files without classification.
- A (closer to the write path): PreToolUse cannot see effects; a PostToolUse protected-path drift
  check (Git status of implementation paths before/after) would detect, not prevent. Candidate.
- B (classify by target/intent): not robust for arbitrary code; rejected.
- C (fail-closed for all inline code): would block the dominant read usage; rejected for now.
Integration is not declared bypass-safe while this path is open.

### Mendix model scope (mxcli diff-local, MPR v2, read-only on the open LIVE-SP project)

- Committed range: `Nanoflow: CAP_Core.NAV_GoTo_Beschaeft`, `Summary: 0 new, 1 modified, 0 deleted`:
  unit type and qualified name are available → `OBSERVABLE` for saved, committed units.
- Saved, uncommitted units: listed against `HEAD` → `OBSERVABLE` (observed in Phase 1C on a
  fixture). Units changed only in properties MDL does not show (navigation, security) are listed
  by property name per `mxcli diff-local --help` → `PARTIALLY_OBSERVABLE` (not reproduced live).
  A 40-commit range did not finish within minutes on the live project → not usable as a hook-time
  check.
- Unsaved Studio Pro edits (LIVE-SP): `No local changes found` while Studio Pro was open; unsaved
  state is not on disk → `NOT_OBSERVABLE`.

### Phase 2 catalog (reconstructed with SAK as reference)

SAK (`D:\User Testing\spec-agent-kit`, read-only): 17 event types (`run.started`, `round.started`,
`station.started/finished`, `verdict.recorded`, `run.escalated/released/returned/approved/paused/
resumed/merged/pushed/commit_attached/reviewed/aborted/taken_over`), envelope `sak.event/1` with
ULID `event_id`, `ts`, `project`, `run_id`, `data`, `origin`; local `events.jsonl` append + flush,
outbox reads only complete lines, invalid lines skipped and counted; event 8 KB, 30-day dashboard
retention; board state from `run.json`/specs/Git, stations/verdicts from events. SAK gaps MxAgile
must close: no parent/child ids, no sequence numbers, no fsync/append lock, no local rotation, no
event-version migration, no explicit "events are not truth" rule, no validation before board use.

| SAK mechanism | MxAgile disposition |
|---|---|
| Strict versioned event envelope and validation before ingest | ADAPT_FOR_MXAGILE: Draft-7 schema; reject invalid event types/major, allow additive unknown envelope fields |
| JSONL append, flush, complete-line reads | DIRECTLY_USEFUL: adopt append-only JSONL, validate, flush + fsync, ignore partial tail and repair only that tail on next append |
| Separate run JSON as state authority | HARMFUL_FOR_MXAGILE: no second `run-state.json`; events are the only run-history store and remain audit-only |
| `run_id`, round, station, verdict and escalation events | ADAPT_FOR_MXAGILE: correlate by run/parent/delegation; do not copy SAK station names as lifecycle semantics |
| Per-run local event log, dashboard SQLite ingest | ADAPT_FOR_MXAGILE: local monthly class streams; no database, outbox, remote ingest or portfolio merge |
| Outbox cursor (byte offset + first-line identity), complete-line batching and push lock | NOT_NEEDED: MxAgile is local-only; partial tails are handled locally, no remote publication queue or network lock |
| Dashboard ingest validates each event, stores only parsed contract objects, `INSERT OR IGNORE` deduplicates by event ID | ADAPT_FOR_MXAGILE: validate before local projection and count invalid lines; local append locks serialize sequence allocation; no central database |
| Dashboard event queries order by `(ts,event_id)`, recent-descending versus incremental-ascending | ADAPT_FOR_MXAGILE: event history is oldest-to-newest; `sequence` is per run, so parallel runs are never causally linearized |
| Legacy pipeline migration: dry-run first, explicit apply, deterministic IDs, unmappable entries reported, existing runs preserved | DIRECTLY_USEFUL for future import tooling; do not infer MxAgile lifecycle state from imported events; no importer is implemented |
| Dashboard SQL schema migrations v1/v2 and retained old table for rollback | NOT_NEEDED: no local event database; project install/update continues through `install-core`, with event files lazily created |
| SAK run-ID lexical format | NOT_NEEDED: preserve existing `RUN-<12 hex>` IDs from Phase 1 |
| Local lock-file TTL, run-lock state machine | ADAPT_FOR_MXAGILE: bounded OS append locks, no run lock/parallel lifecycle state |
| 8 KB event limit and dashboard 30-day retention | ADAPT_FOR_MXAGILE: 8 KiB line, 5 MiB/month/class stream, 100 MiB total, class-specific 30/180-day retention |
| SAK board's current state plus run/event projection | DIRECTLY_USEFUL: existing MxAgile Current State remains canonical; separate Run Activity projection |
| SAK ticker from Git, project aggregation | NOT_NEEDED: Git history already has its own MxAgile Timeline; no central dashboard aggregation |
| Event replay as run state | HARMFUL_FOR_MXAGILE: no event-sourced lifecycle replay; additive v1 reader, canonical state re-derived |
| SAK explicit non-canonical event rule | ADAPT_FOR_MXAGILE: strengthen as a non-negotiable contract (events never authorize transitions) |

Phase 2 implements the run-event schema, writer, bounded retention, Guard/Child/Resync producers,
resume reconciliation in the existing post-compaction routine, and separate DevBoard Run
Activity/Unresolved Runs view. Update/migration producers, append archives, automatic parent-run
ID provisioning, post-execution drift, and a complete lifecycle-transition producer remain
NOT_IMPLEMENTED.

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
- `NOT_IMPLEMENTED`: model-unit write scoping, runtime leases, automatic repair/resume, update/
  migration event producers, event archival, merge, push, or deployment automation.
- `MEASUREMENT_REQUIRED`: compare blocked unauthorized/stale operations, missed scope violations,
  false-positive blocks, and safe-work throughput before proposing promotion from the experiment.