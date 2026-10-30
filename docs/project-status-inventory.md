# Deterministic Project Status: State Inventory

## Authority

The board is a read-only projection of MxAgile-owned project artifacts. It does
not create lifecycle state, reconcile conflicts, promote evidence, or infer
meaning from reports. Missing or conflicting sources remain `UNKNOWN` or
`UNAVAILABLE`; they are not converted into empty or successful states.

The inventory below describes the Core contracts. This framework repository is
not a consumer project: it has no active `planning/lifecycle/process-state.yaml`,
`planning/mission/mission-state.yaml`, or CapTrack project artifacts. CapTrack
reality results therefore require a separate, authorized CapTrack checkout.

## Canonical State Map

| Board concern | Canonical source | Machine-readable | Deterministic | Semantic interpretation | Freshness determinable |
|---|---|---:|---:|---:|---:|
| Project identity | `mxagile-project.yaml`; project `.mpr` name as an optional display fallback | Partial | Yes | No | No; no stable Core project ID |
| Core version | `.mxagile/version.yaml` | Yes | Yes | No | Yes, for the checked-out version only |
| Active target/revision | `planning/target-mockups/*/_history/REV-*/revision.yaml`; `active_target`, `revision_id`, `bundle_hash` | Yes | Yes when zero or one target is active | No | Partial; revision/hash can be compared when recorded |
| Lifecycle phase and gates | `planning/lifecycle/process-state.yaml`; `waves.*.phase` and gate results | Yes | Yes for recorded wave state | No | No; no canonical update timestamp |
| Mission and blockers | `planning/mission/mission-state.yaml`; mission status, active wave, progress, blockers | Yes | Yes for recorded mission state | No | No; no canonical update timestamp |
| Wave inventory | Process-state wave keys; `planning/execution-waves.md` for scope and narrative | Partial | Phase is deterministic; planned scope is not | Yes for Markdown scope | Partial |
| Workpackages/checklists | Canonical `planning/tasks/TASK-NNN.yml`; legacy `planning/checklists/W*-implementation-checklist.yaml` | Partial | Task status is deterministic; legacy shapes vary and have no schema | No for canonical tasks; Yes for legacy text | No |
| Requirements | `requirements/REQ-NNN.yml`; status `draft`, `accepted`, `deferred`, `superseded` | Yes | Yes | No | Yes for current file contents, not downstream impact |
| Decisions | `planning/decisions/DEC-NNN.yml`; status `PROPOSED`, `CONFIRMED`, `REJECTED`, `SUPERSEDED` | Yes | Yes | No | Yes for current file contents |
| Decision-linked requirements | `DEC.affected_requirements[]` | Yes | Yes when explicitly linked | No | Partial; missing links are not inferred |
| Generic findings | No canonical finding schema or lifecycle artifact | No | No | Yes in narrative reports | No |
| Test contracts/proof points | `planning/test-contracts/TC-NNN.yaml`; statuses on contracts and proof points | Yes | Yes | No | Explicit `stale`/`impacted` only |
| Verification plans | `planning/verification-plans/VPL-NNN.yaml`; status and layer assignments | Yes | Yes | No | Partial; plan status does not establish evidence freshness |
| Verification/evidence | `planning/evidence/manifests/*-evidence-manifest.yaml` and parity reports; `parity_result` includes `PASS`, `FAIL`, `PARTIAL`, `NOT_VERIFIED`, `STALE`, `LEGACY_EVIDENCE` | Yes | Yes for recorded results | No | Partial; target revision/hash may be compared |
| Model-fresh verification | Acceptance-campaign output is described in policy but has no checked-in campaign-result schema; current model identity is not recorded on evidence | Partial | No | Yes | No |
| Runtime readiness | Canonical process-state `prerequisite_state` fields, when present | Yes | Yes for recorded values | No | No; several fields describe session/last-achieved state |
| Operating mode | Live Studio Pro detector output; process-state may hold a session observation | Yes at observation time | Yes at observation time | No | Not from repository artifacts; must not be presented as current by a board read |
| Capabilities | `.mxagile/capabilities.yaml` registry and `.mxagile/config.yaml`; resolver adds environment/session evidence | Partial | Static configuration is deterministic; active state is contextual | No | No for current-session capability health |
| Context / Context Mode | `planning/lifecycle/context-epoch.yaml` handoff; `.concord/context-epoch.yaml` operational state; Context Mode evidence is session-local | Partial | Recorded fields are deterministic | No | No for current session or pressure without an attested measurement |
| Sources/sessions | No canonical source/session registry | No | No | Yes | No |

### State authority notes

- `.mxagile/schemas/process-state.schema.json`, lifecycle re-sync policy, project
  knowledge policy, and lifecycle ownership tests identify
  `planning/lifecycle/process-state.yaml` as durable canonical state. The local
  `.concord/scratch/process-state.yaml` is a cache and is not read as board
  authority.
- `.mxagile/lifecycle.yaml` still names `.concord/scratch/process-state.yaml` in
  its `state_tracking.file` field. This is documentation/configuration drift;
  the status builder follows the schema and ownership policy, not the stale
  field. Do not repair lifecycle state as part of this board task.
- Canonical tasks have status values `pending`, `in_progress`, `done`, `failed`,
  `blocked`, and `deferred`, but the task schema has no wave/workpackage field.
  A checklist filename or free-text reference is not promoted into a canonical
  task-to-wave relationship.
- Proposed decisions are explicitly `PROPOSED`. A requirement is reported as
  decision-blocked only when an explicit canonical relationship supports that
  claim; a pending decision is not automatically a blocker for every requirement.
- `FAIL` evidence remains a failed verification result. It is not automatically
  converted to an open finding, because the Core has no general finding
  identity, closure, or resolution contract.
- Runtime configuration is not runtime health. Capabilities that require active
  harness/session observations are unavailable to a repository-only projection.

## Parallel Branch Boundary

The feature worktree is based on `origin/main` commit `9c3745b`. While this work
was in progress, `origin/main` advanced to `32e72eb` (`feat: harden runtime
verification tool and evidence routing`). That commit adds a separately
distributed mxcli resolver and evidence-cleanliness policy. The project-status
builder does not depend on either change, and none of that branch's code was
copied. It also touches `scripts/install-core.ps1`,
`tests/test-capability-discovery-routing.ps1`, and `tests/test-inventory.json`,
which overlap this work's ownership surface. Reconcile those shared files during
integration; do not merge, rebase, or cherry-pick as part of this mission.

## Determinism Gaps

| Gap | Board impact | Smallest source-level resolution |
|---|---|---|
| No stable project identifier | Portfolio identity is only a display name/path fallback | Add an optional stable, non-secret project ID to project configuration |
| No canonical checklist schema or task-to-wave relation | Cannot safely aggregate checklist progress by wave/workpackage across legacy and canonical projects | Define a versioned checklist/workpackage mapping or add an explicit wave reference to canonical tasks |
| No generic finding lifecycle | Open, blocking, closed, and resolved finding counts cannot be derived | Define a canonical finding artifact and status vocabulary only if existing reports cannot satisfy the use case |
| No current model/evidence fingerprint | A passing campaign or evidence record cannot be proven fresh against the current Mendix model | Record a deterministic model/source fingerprint on verification results and define invalidation rules |
| No canonical `updated_at` for mission/process state | The board cannot truthfully show when a status was last updated | Add an explicit timestamp to the owning artifacts or omit the timestamp |
| Operating mode and capability health are session/machine observations | A local repository snapshot cannot claim current Studio Pro or harness health | Keep these values unavailable unless an attested observation is supplied separately |
| No canonical source/session registry | Multi-worktree agent/session attribution is unavailable | Add a source contract only when ownership, lifecycle, and privacy rules are defined |
| Lifecycle path declaration drift | One machine-readable lifecycle field points to the local cache while the schema and policies name the tracked file | Align the lifecycle definition in a separate lifecycle-owned change |
| CapTrack project artifacts not present in this checkout | No real-project counts or behavioral assertions can be reported here | Run the generic builder against an explicitly supplied CapTrack checkout |

## Reference Architecture Findings

The local Spec Agent Kit reference demonstrates useful boundaries, not reusable
MxAgile lifecycle semantics:

- A collector derives a JSON board on demand from project sources; the API/UI
  consumes the contract instead of owning status.
- Contracts centralize enums, validation, labels, and deep links.
- Local collector, dashboard API, persistence, and React UI are separated.
- Its multi-source design identifies a source by branch and merges snapshots,
  but depends on events, run records, and dashboard persistence that MxAgile does
  not canonically provide.
- Portfolio-to-project drilldown, direct links, compact attention states, and
  read-only presentation are relevant UX patterns.

For MxAgile V1, prefer an on-demand JSON projection and no database. A local UI
is a later consumer of the contract; it must not compensate for the gaps above.
No reference implementation code or lifecycle vocabulary is imported.

## Contract and Builder

The v1 contract is `.mxagile/schemas/project-status.schema.json`. It is a
projection (`projection: true`) whose authority is
`mxagile_canonical_artifacts`. It contains no generated timestamp, so unchanged
sources produce byte-identical JSON. `source_fingerprint` hashes the fixed set of
canonical files read, including explicit missing-source markers; it does not
claim that model/runtime verification is fresh.

Build on demand from an installed project:

```powershell
python .mxagile/tools/build_project_status.py --project-root .
```

The builder has no LLM, app, network, or agent dependency and writes no files.
It reads only the known MxAgile source paths; its output can be discarded and
regenerated at any time. Persisting `project-status.json` is unnecessary for V1.

The output reports recorded `PASS` separately from current verification. Current
`verified` remains null without a model-freshness contract; target-revision
mismatches and recorded `STALE` results are counted as stale, never verified.
Checklist, finding, workpackage, current operating-mode, active-capability, and
source/session fields remain unavailable where canonical sources do not exist.

On this Windows framework checkout, the in-process build took 50.6 ms. A full
CLI process took 3.8 s in the same environment, including process and shell
overhead. This is a local framework-repository measurement, not a CapTrack or
large-project benchmark.