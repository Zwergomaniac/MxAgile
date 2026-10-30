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

### Parity Evidence Gallery

The read-only `#gallery` view and `#page/PAGE-...` detail consume only schema-valid
Evidence Manifests, capture groups, BOUND comparison identities and matching
canonical parity reports. No PNG directory crawling, filename pairing or inferred
roles is performed. Mock and application captures stay separate, including their
run IDs, timestamps, clean state, recorded evidence status and target freshness.

Six statuses are copied from the report's evidence_matrix: CONTRACT, MODEL,
STRUCTURAL_DOM, BEHAVIORAL, ROLE and VISUAL_WHOLE_SCREEN. The gallery does not
compute an overall PASS. Missing visual captures remain VISUAL PARITY NOT VERIFIED.
Current-target promoted groups precede historical/superseded groups. Historical
images are created/loaded only when their disclosure is opened. Revisions and
fingerprints remain visible; an old capture is never promoted by board access.

`/capture/` serves only explicit screenshot paths from this projection, restricted
to canonical screenshots, PNG/JPEG/WebP signatures, size limits, repo-root and
no-symlink checks. DOM/YAML snapshots, storage dumps, secret files and unbound
images are not served. Runtime URL userinfo, queries and fragments are removed;
session IDs are omitted. Full-size images and valid current/historical mockup
references open separately with noopener/noreferrer; the board stays open.
Historical DEC-NNN.md records are listed as uninterpreted identities, separate
from current Decision lifecycle counts. Compatibility diagnostics retain their
own authority; the board introduces no repair buttons or repair semantics.

| Board concern | Canonical source | Machine-readable | Deterministic | Semantic interpretation | Freshness determinable |
|---|---|---:|---:|---:|---:|
| Project identity | `mxagile-project.yaml`; project `.mpr` name as an optional display fallback | Partial | Yes | No | No; no stable Core project ID |
| Core version | `.mxagile/version.yaml` | Yes | Yes | No | Yes, for the checked-out version only |
| Active target/revision | `planning/target-mockups/<mockup>/_history/REV-*/revision.yaml`; exactly one `active_target: true` per bundle | Yes | Yes independently for each bundle; missing/conflicting revisions are unknown/ambiguous | No | Accepted revision/hash and inventory target drift are determinable; model freshness is not |
| Lifecycle phase and gates | `planning/lifecycle/process-state.yaml`; `waves.*.phase` and gate results | Yes | Yes for recorded wave state | No | No; no canonical update timestamp |
| Mission and blockers | `planning/mission/mission-state.yaml`; mission status, active wave, progress, blockers | Yes | Yes for recorded mission state | No | No; no canonical update timestamp |
| Wave inventory | Process-state wave keys; `planning/execution-waves.md` for scope and narrative | Partial | Phase is deterministic; planned scope is not | Yes for Markdown scope | Partial |
| Workpackages/checklists | Canonical `planning/tasks/TASK-NNN.yml` with optional `wave_id`, `workpackage_id`, `req`; canonicalized checklist provenance in `migrated_from` | Yes for canonical tasks; partial for legacy checklists | Yes only for explicit IDs and exact `migrated_from` source match | No | Current file hashes are determinable; whether legacy checklist was canonicalized is explicit |
| Requirements | `requirements/REQ-NNN.yml`; status `draft`, `accepted`, `deferred`, `superseded` | Yes | Yes | No | Yes for current file contents, not downstream impact |
| Decisions | `planning/decisions/DEC-NNN.yml`; status `PROPOSED`, `CONFIRMED`, `REJECTED`, `SUPERSEDED` | Yes | Yes | No | Yes for current file contents |
| Decision-linked requirements | `DEC.affected_requirements[]` | Yes | Yes when explicitly linked | No | Partial; missing links are not inferred |
| GAP Findings | `planning/findings/FIND-*.yml`; `.mxagile/schemas/finding.schema.json` lifecycle and severity | Yes | Yes for recorded GAP lifecycle | No | File hash only; evidence/model freshness is separate |
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
  `blocked`, and `deferred`. `wave_id` and `workpackage_id` are optional explicit
  links. The checklist canonicalizer derives only `wave_id` from the exact
  `W*-implementation-checklist.yaml` filename and preserves an explicitly
  declared workpackage ID; the board does not infer a workpackage.
- Proposed decisions are explicitly `PROPOSED`. A requirement is reported as
  decision-blocked only when an explicit canonical relationship supports that
  claim; a pending decision is not automatically a blocker for every requirement.
- `FAIL` evidence remains a failed verification result. It is not automatically
  converted to a Finding. Only explicit `planning/findings/FIND-*.yml` GAP
  records contribute to Finding counts; legacy narrative reports remain unmapped.
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
| Legacy checklists may not have canonicalized TASK records | Their done/total progress remains unavailable until canonicalization; explicit raw checklist status formats are not guessed | Run the existing artifact-canonicalization lifecycle; canonical task statuses and `migrated_from` preserve deterministic progress |
| Legacy findings may exist only in reports | Only canonical GAP records have open/blocking/closed counts; narrative reports remain unavailable | Migrate/record relevant current GAPs into `planning/findings/FIND-*.yml`; do not infer closure from report prose |
| No current Mendix model fingerprint on evidence | Target freshness can be compared, but current model freshness and end-to-end VERIFIED remain unknown | Add an authoritative model fingerprint to verification evidence and define invalidation rules before promoting PASS to VERIFIED |
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

MxAgile V1 uses an on-demand JSON projection and a local graphical consumer; it
does not need persistence or a database. The UI shows unknown/partial gaps rather
than compensating for them. No reference implementation code or lifecycle
vocabulary is imported.

## Contract and Builder

The v2 contract is `.mxagile/schemas/project-status.schema.json`. It is a
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

## Gap Closure and UI-Spike Gate

The contract now supports an honest single-project UI without claiming missing
state:

- **Checklist to wave:** canonical tasks accept optional `wave_id` and
  `workpackage_id`. Checklist canonicalization derives `wave_id` only from a
  `W*-implementation-checklist.yaml` source filename and preserves an explicitly
  supplied workpackage ID. The builder counts checklist progress only for tasks
  whose `migrated_from` exactly matches that canonical checklist path. Legacy
  checklists without canonicalized task records remain `unknown`/`unavailable`.
- **Finding lifecycle:** `planning/findings/FIND-*.yml` now has a canonical
  schema with GAP type, severity, lifecycle, wave/workpackage, requirement and
  decision links, source artifacts, evidence refs, and timestamps. The board
  treats only `VERIFIED` as closed; `CRITICAL` and `DECISION_REQUIRED` are
  blocking. It does not repair or close findings.
- **Evidence freshness:** target identity is compared by accepted revision,
  bundle hash, and explicit target path where recorded. `target_freshness` can
  therefore be determinable. `model_freshness` remains `unknown` because
  manifests do not contain a current Mendix model fingerprint. A recorded PASS
  is never promoted to end-to-end `verified` from mockup freshness alone.

This is sufficient for a **local read-only UI spike**: checklist and finding
sections must render unknown/partial states plainly, and verification must show
target freshness separately from unknown model freshness. It is not sufficient
to claim complete project readiness. Missing multi-harness session registry,
stable portfolio-wide project IDs, and live Context Mode state do not block a
single-project local spike.

## V1 UI Information Architecture

### Portfolio

V1 starts with the locally selected project as one compact project row/card:
project name and Core version, lifecycle phase, active wave and mission status,
blocker count, proposed decisions, and verification attention (stale, failed,
unverified, model-freshness unknown). Selecting it opens Project Overview.
Multi-project registration is explicitly out of scope until a stable project
registry exists; no synthetic portfolio is assembled from nearby directories.

### Project Overview

The header shows project identity, lifecycle phase, mission status, and active
wave. The first content band shows every ACTIVE_TARGET bundle with mockup name,
revision, canonical filename, authority state, abbreviated bundle fingerprint,
availability, and `Mockup öffnen` action. Single-file targets show the explicit
UI-inventory path and content fingerprint.

Attention indicators summarize mission blockers, blocking Findings,
`PROPOSED` Decisions, stale/failed/unverified evidence, plus model freshness
`UNKNOWN`. No aggregate progress percentage is calculated.

Tabs: **Waves / Workpackages**, **Requirements**, **Verification / Evidence**,
**Findings**, **Decisions**. Sources/Sessions is omitted until canonical source
data exists.

### Waves / Workpackages

Each wave row shows lifecycle phase, gate states, task counts by canonical
status, checklist done/total only when checklist provenance is explicit, linked
Requirements, and relevant Findings/Decisions/Evidence by canonical IDs. Tasks
without `wave_id` appear in an unmapped count. Workpackages appear only when
`workpackage_id` is explicit; no task ordering or title is used to invent one.

### Requirements

The table lists requirement ID, title, and canonical status, with a detail
drilldown to explicit task-derived wave/workpackage links, Test Contracts and
Proof Points, linked decisions/findings, plus source references. Missing links
stay absent rather than being inferred from neighboring artifacts.

### Verification / Evidence

Recorded results and current-target comparison are separate. UI labels use
`PASS vs ACTIVE_TARGET`, `STALE`, `FAILED`, `NOT_VERIFIED`, or `UNKNOWN`; it only
uses `VERIFIED` when a future model-freshness contract supports that assertion.
For this V1 contract, show `Model freshness: UNKNOWN` next to target freshness.

### Findings / Decisions

Open Findings are grouped by lifecycle status and severity. `CRITICAL` and
`DECISION_REQUIRED` are visually blocking; `VERIFIED` is closed. Decisions show
`PROPOSED`, `CONFIRMED`, `REJECTED`, or `SUPERSEDED`, affected Requirements, and
canonical links. All controls are navigation only.

### Navigation and Deep Links

Board routes: project overview, wave/workpackage detail, Requirement detail,
Finding detail, and Decision detail. Contract source references carry source
type, repo-relative canonical path, optional artifact ID/anchor, availability,
and content hash. The UI constructs local URLs; no browser URL is stored in
lifecycle data. Read-only source links and mockup links use a new tab with
`target="_blank"` and `rel="noopener noreferrer"`.

## Local Reference Serving

The spike uses a Python standard-library HTTP server bound only to
`127.0.0.1`. `/api/status` rebuilds the projection on demand. The board page is
served from the Core-owned `.mxagile/board/` payload. Mockup requests are
accepted only when their path is authorized by an available ACTIVE_TARGET in
the current generated Contract:

- SPA assets must resolve under that target's `reference_root`, which is the
  immutable accepted revision directory.
- A single-file target serves only its exact canonical file path.
- All decoded path components are validated; `..`, absolute paths, backslashes,
  encoded traversal, symlinks, directories, `revision.yaml`, and files outside
  the authorized root are rejected.
- The handler never provides directory listings or a general filesystem API.

The mockup anchor is a normal neighbor-tab link; the board remains open. No
`file://` dependency is required. V1 has no write routes, commands, agent
launch, evidence promotion, or lifecycle controls.

## Implemented UI Spike

The local V1 spike is delivered as static HTML/CSS/JavaScript under
`.mxagile/board/`; the Core distributes `scripts/serve_project_board.py` to
`.mxagile/tools/`. Start it from the consumer project with:

```powershell
python .mxagile/tools/serve_project_board.py --project-root .
```

It binds only `127.0.0.1` (default port 8765). The start screen is Portfolio;
because there is no canonical project registry, V1 shows the one explicitly
selected project rather than scanning sibling directories. Project Overview
has the ACTIVE_TARGET strip, attention indicators and tabs for Waves / Work-
packages, Requirements, Verification / Evidence, Findings, and Decisions.

The browser reads only `/api/status`. `/reference/<path>` is allow-listed from
available ACTIVE_TARGET records and confines SPA assets to `reference_root`;
single-file targets permit only their exact canonical path. `/source/<path>`
permits only exact available Contract source references. The server rejects
traversal, symlinks, directories, revision manifests, and paths outside those
authorities. All links are read-only and open in a neighboring tab.