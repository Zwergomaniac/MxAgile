# Spike: Knowledge Graph + Business Flow Architecture

**Status:** PROPOSED  
**Date:** 2026-10-07  
**Scope:** Part A — Provider-Neutral Knowledge Graph · Part B — Structured Business Flow Contracts  

---

## Executive Summary

Both capabilities are architecturally grounded and warranted by existing evidence. Neither requires
a mandatory new dependency. The safest path is:

- **Part A**: Extend the existing artifact-index graph (already schema'd in
  `docs/ARTIFACT_GRAPH_SCHEMA.json`) with missing edge types and a thin provider-neutral query
  contract. Graphify enters as an optional `provider: graphify` when developers opt in.
- **Part B**: Add a structured, schema-validated `flows[]` contract to MxMocketeer — currently
  informal prose — and generate Mermaid diagrams from it. Mermaid is a view, not canonical truth.

---

## Part A — Knowledge Graph

### A.1 Re-Sync: Current Cross-Artifact Reference Map

The following edges are already **explicit in canonical YAML** and are the ground truth for any
graph. Where noted, they are already indexed by `build_artifact_index.py`.

#### Currently indexed (artifact-index.json, produced by build_artifact_index.py)

| Source artifact | Edge type | Target artifact | YAML field |
|---|---|---|---|
| `pages/PAGE-NNN.yml` | `DERIVED_FROM` | `requirements/REQ-NNN.yml` | `REQ.derivedFrom` |
| `requirements/REQ-NNN.yml` | `APPLIES_TO` | `pages/PAGE-NNN.yml` | `REQ.screens[]` |
| `requirements/REQ-NNN.yml` | `IMPLEMENTED_BY` | `specs/SPEC-NNN.yml` | `SPEC.requirements[]` |
| `specs/SPEC-NNN.yml` | `IMPLEMENTED_BY` | `planning/tasks/TASK-NNN.yml` | `TASK.spec` |
| `pages/PAGE-NNN.yml` | `VERIFIED_BY` | `planning/scenarios/SCN-NNN.yaml` | `SCN.screen_id` |
| `planning/scenarios/SCN-NNN.yaml` | `COVERS` | `requirements/REQ-NNN.yml` | `SCN.traceability.requirements[]` |

#### Present in canonical YAML but **not yet indexed**

| Source | Edge type | Target | Field |
|---|---|---|---|
| `planning/tasks/TASK-NNN.yml` | `DEPENDS_ON` | `planning/tasks/TASK-NNN.yml` | `TASK.depends_on[]` |
| `planning/tasks/TASK-NNN.yml` | `TRACES_TO` | `requirements/REQ-NNN.yml` | `TASK.req[]` |
| `planning/test-contracts/TC-NNN.yaml` | `COVERS` | `requirements/REQ-NNN.yml` | `TC.requirement_ids[]` |
| `planning/test-contracts/TC-NNN.yaml` | `DERIVED_FROM_DC` | Design Contract (HTML) | `TC.design_contract_ref` |
| `planning/verification-plans/VPL-NNN.yaml` | `PLANS` | `planning/test-contracts/TC-NNN.yaml` | `VPL.test_contract_id` |
| `planning/decisions/DEC-NNN.yml` | `GOVERNS` | `requirements/REQ-NNN.yml` | `DEC.affected_requirements[]` |
| `planning/decisions/DEC-NNN.yml` | `GOVERNS_SCREEN` | `pages/PAGE-NNN.yml` | `DEC.affected_screens[]` |
| `planning/decisions/DEC-NNN.yml` | `SUPERSEDED_BY` | `planning/decisions/DEC-NNN.yml` | `DEC.superseded_by` |
| `planning/target-mockups/*/REV-NNN/revision.yaml` | `AUTHORIZED_BY` | `planning/decisions/DEC-NNN.yml` | `REV.acceptance_decisions[]` |
| `planning/target-mockups/*/REV-NNN/revision.yaml` | `IMPACTS` | `requirements/REQ-NNN.yml` | `REV.requirements[]` |
| `planning/target-mockups/*/REV-NNN/revision.yaml` | `AFFECTS_SCREEN` | `pages/PAGE-NNN.yml` | `REV.affected_screens[]` |
| `planning/scenarios/SCN-NNN.yaml` | `COVERS_SPEC` | `specs/SPEC-NNN.yml` | `SCN.traceability.specs[]` |
| `planning/scenarios/SCN-NNN.yaml` | `DEPENDS_ON_SCN` | `planning/scenarios/SCN-NNN.yaml` | `SCN.prerequisites.depends_on_scenarios[]` |

#### Artifact types and stable ID prefixes

| Type | ID prefix | Canonical path |
|---|---|---|
| Page | `PAGE-` | `pages/PAGE-NNN.yml` |
| Requirement | `REQ-` | `requirements/REQ-NNN.yml` |
| Spec | `SPEC-` | `specs/SPEC-NNN.yml` |
| Task | `TASK-` | `planning/tasks/TASK-NNN.yml` |
| Decision | `DEC-` | `planning/decisions/DEC-NNN.yml` |
| Test Contract | `TC-` | `planning/test-contracts/TC-NNN.yaml` |
| Proof Point | `PP-` | within TC |
| Verification Plan | `VPL-` | `planning/verification-plans/VPL-NNN.yaml` |
| Revision | `REV-` | `planning/target-mockups/*/REV-NNN/revision.yaml` |
| Mockup Bundle | name | `planning/target-mockups/<name>/` |
| Story/Spec (legacy) | story file | `planning/stories/` |
| Evidence Manifest | wave-scoped | `planning/evidence/manifests/` |
| Acceptance Campaign | wave-scoped | `planning/acceptance-campaigns/` |
| UI Inventory | wave-scoped | `planning/ui-inventory/` |
| Repair Task | project | `planning/repair-tasks/` |
| Process State | wave-scoped | `.concord/scratch/process-state.yaml` |

---

### A.2 Architectural Invariant

```
YAML / structured MxAgile artifacts = CANONICAL TRUTH

A Knowledge Graph is:
  derived          — built deterministically from canonical YAML
  rebuildable      — deleting and rebuilding changes nothing
  disposable       — can be discarded; project semantics intact
  non-authoritative — no lifecycle gate may pass solely on graph output
```

The artifact-index.json produced by `build_artifact_index.py` is already this: a
derived, rebuildable index. The graph capability is an extension of the same pattern,
not a replacement.

The process-state gate values in `.concord/scratch/process-state.yaml` are the authoritative
source for lifecycle gate results. A query to the graph may **surface** candidates for review;
it must never **authorize** state transitions.

---

### A.3 Existing Graph Seed

`docs/ARTIFACT_GRAPH_SCHEMA.json` already defines a `nodes[]`/`edges[]` structure with
a provenance model using `DECLARED | DERIVED | INFERRED`. This maps directly to the
spike's required provenance classes:

| Existing schema term | Spike term | Meaning |
|---|---|---|
| `DECLARED` | `CANONICAL` | Explicit ref field in canonical YAML |
| `DERIVED` | `EXTRACTED` | Observed in repo artifacts, not a canonical ref field |
| `INFERRED` | `INFERRED` | Semantic/provider suggestion |

**Recommendation**: Align terminology. Rename `DECLARED → CANONICAL` and `DERIVED → EXTRACTED`
in `ARTIFACT_GRAPH_SCHEMA.json` when extending the schema. The existing `build_artifact_index.py`
outputs CANONICAL edges; this is the right default.

---

### A.4 Provider-Neutral Graph Contract

Design a thin abstraction that works over **any** underlying provider. The default provider
is the MxAgile-native artifact-index. Graphify is an optional second provider.

#### Configuration

Add to `.mxagile/config.yaml` (new framework-managed file, project-owned values):

```yaml
knowledge_graph:
  provider: artifact-index   # artifact-index | graphify | none
  options:
    # provider: artifact-index
    index_path: .mxagile/state/artifact-index.json

    # provider: graphify (when opted in)
    # graphify_version: "0.x.y"   # pinned
    # local_only: true             # never upload to hosted service
    # graph_dir: .mxagile/state/graph/
```

`none` = capability disabled; agents use direct YAML traversal (current default behaviour).  
`artifact-index` = thin query wrapper over the existing index.  
`graphify` = full Graphify MCP provider; requires install.

#### Operations contract

```
build(scope?: 'incremental' | 'full') → { status: 'ok' | 'error', edges_added, nodes_added }
  Rebuild from canonical YAML. Full rebuild: idempotent, safe to run at any time.
  Incremental: only process changed files (detected by hash or mtime).

refresh(changed_ids: string[]) → { updated_edges, invalidated_edges }
  Update only the nodes and edges reachable from changed_ids. Used after single-artifact mutations.

status() → { provider, last_built, schema_version, node_count, edge_count, staleness: 'current' | 'stale' | 'unknown' }
  Never blocks; returns unknown when graph has not been built.

query(from_id: string, edge_types?: string[], max_depth?: number) → GraphResult
  Traverse from a node. Returns nodes and edges up to max_depth hops.

neighbors(id: string, direction: 'upstream' | 'downstream' | 'both', edge_types?: string[]) → Node[]
  Single-hop. Upstream = towards source (PAGE/DC); downstream = towards evidence.

paths(from_id: string, to_id: string, max_hops?: number) → Path[]
  All paths between two nodes. Used for traceability chains and impact scoping.

affected(changed_id: string, direction: 'downstream') → AffectedSet
  Returns all artifacts transitively downstream of changed_id. Used for change propagation.
  Results are CANDIDATES for review, not authoritative staleness declarations.

explain(id: string) → HumanSummary
  Human-readable summary of an artifact's full graph context (upstream + downstream, open effects).
```

Provider isolation: **no agent or policy imports a Graphify-specific symbol**. All graph
calls go through the operations contract above. The provider is resolved from config at call time.

---

### A.5 Edge Provenance

Three classes with strict precedence:

#### CANONICAL (formerly DECLARED)
Derived **deterministically** from explicit YAML reference fields. These are the only edges
allowed to authorize downstream action.

Sources: `derivedFrom`, `requirements[]`, `spec`, `depends_on[]`, `req[]`,
`requirement_ids[]`, `test_contract_id`, `design_contract_ref`,
`acceptance_decisions[]`, `affected_screens[]`.

#### EXTRACTED (formerly DERIVED)
Explicitly observed in repository artifacts that are **not** canonical ref fields. Examples:
- A requirement ID mentioned in a story spec narrative (`.md` text)
- A REQ reference in an acceptance campaign result YAML
- A proof point ID referenced across waves via `regression_scope`

EXTRACTED edges are valid for surfacing change candidates and generating reports.
They **must not** trigger automatic artifact mutation or lifecycle advancement.

#### INFERRED
Semantic suggestions: embedding similarity, text proximity, Graphify's community detection,
or any provider-specific NLP analysis. Always labelled `provenance.type: INFERRED`.

Invariant: **an INFERRED edge must never silently override canonical artifact state**. When
an INFERRED edge contradicts a CANONICAL edge, the CANONICAL edge wins; the conflict is
surfaced to the developer for review.

#### Precedence rule

```
CANONICAL > EXTRACTED > INFERRED

When two edges of different provenance connect the same pair of nodes,
the higher-precedence edge is canonical for all lifecycle decisions.
The lower-precedence edge is preserved in the graph as supplemental evidence only.
```

---

### A.6 Managed Graphify Installation

The existing managed tool pattern in MxAgile is `scripts/install-mxcli.ps1`:
- Version-pinned in a config file
- Idempotent (detects existing version, skips if current)
- Managed by `install-core.ps1`
- Distributed to projects

The same pattern applies to Graphify. The managed flow:

```
install-core.ps1
  reads .mxagile/config.yaml
  if knowledge_graph.provider == 'graphify':
    scripts/install-graphify.ps1 -Version $config.knowledge_graph.options.graphify_version
      - uses uvx/pipx to install graphify==<pinned_version> in isolated environment
      - validates: graphify --version
      - writes .mxagile/state/graphify-state.yaml { version, installed_at, graph_dir }
    scripts/init-graph.ps1
      - builds initial graph from canonical YAML
      - writes graph-state metadata to .mxagile/state/graph-state.yaml
```

**Privacy and hosting constraints:**
- `local_only: true` is the **default** config value.
- `install-graphify.ps1` must fail with an explicit error if `local_only: false` is not confirmed
  by the developer. Silent data upload to hosted services is prohibited.
- The graph directory (`.mxagile/state/graph/`) is **gitignored** — same as `artifact-index.json`.

**Version compatibility:**
- `graphify_version` is pinned in `.mxagile/config.yaml`, not floating.
- `install-core.ps1` detects version mismatch during Core sync and triggers reinstall.
- Version compatibility metadata: `.mxagile/state/graphify-state.yaml { version, min_compatible }`.

**MCP/client projection:**
When Graphify is installed, `install-graphify.ps1` optionally writes a local MCP server entry
to `.mcp.json` (project-level) pointing to the local Graphify instance. This is conditional:
only when the developer has an MCP-capable client configured. No MCP entry is written by default.

---

### A.7 Dependency Ownership

Graphify follows the same ownership model as mxcli:

| Dimension | mxcli | Graphify |
|---|---|---|
| Owner | MxAgile Core | MxAgile Core (when opted in) |
| Installer script | `scripts/install-mxcli.ps1` | `scripts/install-graphify.ps1` (to create) |
| Version pin location | distributed `update-mxcli.ps1` | `.mxagile/config.yaml` |
| State file | implicit | `.mxagile/state/graphify-state.yaml` |
| Gitignored state | n/a | `.mxagile/state/graph/` |
| Opt-in required | no (always installed) | yes (`provider: graphify` in config) |
| Project receives | `update-mxcli.ps1` | no separate distributed script needed |
| Default | mandatory | opt-in only |

**Key constraint**: Graphify must remain optional. Projects that do not set
`knowledge_graph.provider: graphify` must not have Graphify installed or invoked.

---

### A.7b Existing Partial Implementation

The operations contract is **not starting from zero**. Two scripts already implement its core:

| Operation | Existing implementation |
|---|---|
| `affected(id, downstream)` | `scripts/resolve_impact.py` — resolves any canonical ID to related artifacts via `artifact-index.json`; checks `source_fingerprint` and rebuilds if stale |
| downstream staleness propagation | `scripts/propagate_stale.py` — traverses `IMPLEMENTED_BY` and `COVERS` edges downstream using BFS, marks nodes `STALE` |
| `build()` | `scripts/build_artifact_index.py` — full rebuild from canonical YAML |

Phase 1 work is therefore: (a) fill missing edge types in `build_artifact_index.py`, (b) thin the
`resolve_impact.py` / `propagate_stale.py` interface into the declared operations contract shape,
(c) add `status()` and `explain()` as new capabilities. Nothing requires a rewrite.

---

### A.8 What to Build vs. Evaluate

The spike establishes:

| Capability | Verdict | Evidence |
|---|---|---|
| Provider-neutral graph operations contract | **BUILD** | artifact-index.json already provides half; ARTIFACT_GRAPH_SCHEMA.json seeds the schema |
| Extend artifact-index with missing edge types | **BUILD** | TC/VPL/Revision edges are declared in YAML schemas but not yet indexed |
| `artifact-index` provider wrapping existing index | **BUILD** | Zero new dependencies; makes graph queries available to agents now |
| Edge provenance 3-class model (CANONICAL/EXTRACTED/INFERRED) | **BUILD** | Existing ARTIFACT_GRAPH_SCHEMA.json already has the 3-class model (rename only) |
| `.mxagile/config.yaml` with provider selection | **BUILD** | Needed regardless of Graphify; governs all future graph-adjacent settings |
| `scripts/install-graphify.ps1` managed installer | **DESIGN only** | Pattern is established (mxcli); no evidence of developer opt-in yet |
| Graphify MCP projection | **DEFER** | Requires real developer workflow data; evaluate at pilot project stage |
| `provider: mxagile-native` (richer native graph) | **DEFER** | artifact-index provider covers 90% of use cases; evaluate after pilot |

---

## Part B — Business Flow Contracts

### B.1 Current State

MxMocketeer's design contract (`products/MxMocketeer/knowledge/design-contract.txt`) specifies
`flows[]` as:

> "Flows contain: start, steps, alternatives, result, and error paths."

This is narrative prose. The current contract is valid and being used, but:
- No step types (decision node, UI action, system action, integration call)
- No stable step IDs — effects cannot point to individual steps
- No cross-artifact refs within step entries (a step may affect a REQ but this is not
  machine-readable)
- No Mermaid generation
- No schema validation

### B.2 Structured Business Flow Contract (Schema Extension)

The flows array is extended with a typed, step-level schema. This is **backward-compatible**:
existing contracts with narrative-only flows remain valid; the structured schema is used when
the structured fields are present.

#### Flow entry schema

```json
{
  "id": "FLOW-ORDER-SUBMIT",
  "name": "Order Submission",
  "description": "End-to-end flow from cart review to order confirmation.",
  "trigger": "Customer clicks 'Place Order' button on SCREEN-CART.",
  "role_refs": ["ROLE-CUSTOMER"],
  "req_refs": ["REQ-007", "REQ-008"],
  "steps": [
    {
      "step_id": "STEP-001",
      "type": "user_action",
      "actor_role": "ROLE-CUSTOMER",
      "description": "Customer reviews cart and clicks submit",
      "screen_ref": "SCREEN-CART",
      "req_refs": ["REQ-007"],
      "decision_refs": [],
      "transitions": [
        { "condition": "cart_not_empty", "label": "Cart has items", "to": "STEP-002" },
        { "condition": "cart_empty", "label": "Cart empty", "to": "STEP-ERR-001" }
      ]
    },
    {
      "step_id": "STEP-002",
      "type": "system_action",
      "description": "System validates payment method",
      "transitions": [
        { "condition": "payment_valid", "label": "Valid", "to": "STEP-003" },
        { "condition": "payment_invalid", "label": "Invalid", "to": "STEP-ERR-002" }
      ]
    },
    {
      "step_id": "STEP-003",
      "type": "ui_state",
      "description": "Confirmation screen shown",
      "screen_ref": "SCREEN-CONFIRM",
      "req_refs": ["REQ-008"],
      "transitions": [
        { "condition": "always", "to": "STEP-END" }
      ]
    },
    { "step_id": "STEP-END",    "type": "end_node",   "description": "Order placed successfully." },
    { "step_id": "STEP-ERR-001","type": "error_node",  "description": "Show empty cart error." },
    { "step_id": "STEP-ERR-002","type": "error_node",  "description": "Show payment error." }
  ],
  "result": "STEP-END",
  "error_paths": ["STEP-ERR-001", "STEP-ERR-002"]
}
```

#### Step types

| Type | Meaning |
|---|---|
| `user_action` | A user interaction (click, input, submit). Requires `actor_role`. |
| `system_action` | A system operation triggered without direct user input (validation, save, send). |
| `decision_node` | A branching point. Two or more transitions with conditions. |
| `integration_call` | An external system call (API, service, platform module). |
| `ui_state` | A stable visible screen state (loading, confirmation, error view). |
| `end_node` | Terminal success state. |
| `error_node` | Terminal error state. |

#### Stability rules
- `flows[*].id` is stable once assigned (FLOW-DOMAIN-NAME or FLOW-NNN).
- `steps[*].step_id` is stable within its parent flow.
- Steps and flows are never renumbered on refinement — use SUPERSEDED status instead.
- Step IDs may appear in effect `source_ids`, `affected_screens` analogously.

### B.3 Mermaid as a View

Mermaid text is **never stored** in the design contract. It is generated on demand from the
structured `steps[]` and `transitions[]` data. This enforces the contract as the single source
of truth.

Generation algorithm (deterministic):

```
for each flow in flows[]:
  emit: flowchart TD
  for each step in steps[]:
    emit: step_id["description (type)"]
    style step_id according to type (user_action=blue, system_action=grey, error_node=red, end_node=green)
  for each step in steps[]:
    for each transition in step.transitions[]:
      emit: step_id -->|condition_label| transition.to
```

The generator lives in `products/MxMocketeer/` as a utility function in the system prompt
(JavaScript, inline in the generated HTML), not as a server-side script. This keeps
the mockup self-contained and executable locally.

### B.4 Knowledge Graph Integration (Part A ↔ Part B synergy)

When structured flows are present, the artifact graph gains a new node type and edge:

| Node type | ID | Source |
|---|---|---|
| `BusinessFlow` | `FLOW-NNN` | `flows[*].id` in design contract |

| Edge | From | To | Provenance |
|---|---|---|---|
| `PARTICIPATES_IN` | `REQ-NNN` | `FLOW-NNN` | CANONICAL (step.req_refs[]) |
| `SHOWN_ON` | `FLOW-NNN` | `PAGE-NNN` | CANONICAL (step.screen_ref) |
| `DECIDED_BY` | `FLOW-NNN` | `DEC-NNN` | CANONICAL (step.decision_refs[]) |

This enables:
- `affected(REQ-007)` → returns `FLOW-ORDER-SUBMIT` as a downstream candidate
- `neighbors(FLOW-ORDER-SUBMIT, upstream)` → surfaces all REQ and DEC governing the flow
- Impact assessment: if REQ-007 changes, which flows and screens are transitively affected?

### B.5 What to Build vs. Evaluate

| Capability | Verdict | Evidence |
|---|---|---|
| Structured `flows[]` schema (step types, stable IDs, transitions) | **BUILD** | Directly addresses current gap; backward-compatible additive extension |
| Mermaid generator (inline JS in HTML output) | **BUILD** | Trivial once structured steps exist; no external dependency |
| Step cross-refs to `req_refs`, `screen_ref`, `decision_refs` | **BUILD** | Closes the traceability gap; enables Part A graph edges |
| Graph edges for FLOW nodes (PARTICIPATES_IN, SHOWN_ON, DECIDED_BY) | **BUILD alongside Part A** | Only meaningful once structured flows exist |
| Flow-level maturity dimension `DIM-BUSINESS_FLOWS` | **BUILD** | Assessment framework already has dimension registry; add one dimension |
| Mermaid stored in design contract | **DO NOT BUILD** | Breaks canonical truth; creates round-trip problem |
| Mermaid stored in canonical YAML artifacts | **DO NOT BUILD** | Not canonical; not part of MxAgile artifact schemas |

---

## Shared Implementation Sequence

**Phase 1 — Foundation (no new dependency)**
1. Update `docs/ARTIFACT_GRAPH_SCHEMA.json`: rename DECLARED→CANONICAL, DERIVED→EXTRACTED.
2. Extend `scripts/build_artifact_index.py` to emit the missing CANONICAL edges
   (TASK.depends_on, TASK.req[], TC.requirement_ids[], TC.design_contract_ref, VPL.test_contract_id,
   REV.acceptance_decisions[], REV.requirements[], REV.affected_screens[]).
3. Add `.mxagile/config.yaml` with `knowledge_graph.provider: artifact-index` as default.
4. Implement artifact-index provider: a thin Python/PowerShell wrapper exposing the operations
   contract (`query`, `neighbors`, `paths`, `affected`, `explain`, `status`).

**Phase 2 — Business Flows (MxMocketeer, no new dependency)**
1. Add structured `flows[]` schema to `products/MxMocketeer/knowledge/design-contract.txt`.
2. Update MxMocketeer system prompt: generate Mermaid from structured steps (inline JS).
3. Register FLOW node type and PARTICIPATES_IN/SHOWN_ON/DECIDED_BY edges in
   `docs/ARTIFACT_GRAPH_SCHEMA.json`.
4. Add `DIM-BUSINESS_FLOWS` dimension to assessment framework.

**Phase 3 — Graphify provider (opt-in, requires pilot evidence)**
1. Create `scripts/install-graphify.ps1` following mxcli installer pattern.
2. Wire into `install-core.ps1` conditional on `knowledge_graph.provider: graphify`.
3. Implement graphify provider shim exposing the same operations contract.
4. Evaluate MCP projection at pilot project stage.

---

## Open Questions

| # | Question | Owner | Blocking |
|---|---|---|---|
| OQ-001 | ~~Decisions format unknown~~  **Resolved**: `planning/decisions/DEC-NNN.yml` with `decision.schema.json`. REV→DEC edges can be indexed from `REV.acceptance_decisions[]` using the same pattern as other YAML refs. | — | Closed |
| OQ-002 | Should `flows[*].id` follow `FLOW-NNN` numeric pattern or `FLOW-DOMAIN-VERB` slug? Numeric is consistent with REQ/SPEC; slug is more readable. | Product Owner / MxMocketeer author | Phase 2 schema |
| OQ-003 | What Graphify version is currently deployed in the team environment? Determines version pinning baseline. | Developer | Phase 3 only |
| OQ-004 | Should the Mermaid view be generated server-side (generator script) or client-side (inline JS in mockup HTML)? Inline JS is self-contained; server-side enables standalone diagrams. | Framework developer | Phase 2 |

---

---

## M365 Copilot Agent Impact

### Current Package

The M365 agent is **MxMocketeer v3**, packaged at `products/MxMocketeer/`.

| Component | File | M365 Upload method |
|---|---|---|
| System Prompt | `system-prompt.md` | Paste into Instructions field |
| Knowledge 1 | `knowledge/design-contract.txt` | Upload as knowledge file |
| Knowledge 2 | `knowledge/discovery-assessment.txt` | Upload as knowledge file |
| Knowledge 3 | `knowledge/golden-mockuphtml.txt` | Upload as knowledge file |
| Knowledge 4 | `knowledge/mendix-design-guide.txt` | Upload as knowledge file |
| Knowledge 5 | `knowledge/mxagile-handoff.txt` | Upload as knowledge file |
| Setup guide | `agent-builder-setup.md` | Reference for configurator only |
| Prompts | `suggested-prompts.md` | Configure as Suggested Prompts |

Package structure pre-Phase 2: 1 system prompt + 5 knowledge files.

---

### System Prompt Changes

Added two new sections at the end of `system-prompt.md`:

**## Business Flows** (new)
Behavioral rules for structured flow authoring: stable FLOW-NNN / FLOWSTEP-NNN IDs,
step types, transitions, cross-refs (screen_ref, req_refs[], decision_refs[]),
Mermaid generation (on demand, never stored), DIM-BUSINESS_FLOWS assessment guidance.

**## Knowledge Graph Context** (new)
Rules for generating KG-compatible output: stable ID invariants, cross-ref field discipline,
effects downstream_artifacts refs, source vs canonical ID separation, provenance model summary.

No existing sections removed or altered.

---

### Existing Knowledge Files Updated

| File | Change summary |
|---|---|
| `knowledge/design-contract.txt` | `## Screens, Flows, and States` section updated: added structured flows schema (id, steps[], step types, FLOW-NNN/FLOWSTEP-NNN IDs, screen_ref/req_refs/decision_refs graph edges, Mermaid-as-view rule, backward compatibility note) |
| `knowledge/discovery-assessment.txt` | Handoff readiness section updated: added DIM-BUSINESS_FLOWS to the "may be PARTIAL" list. Prioritization updated: business flow structural gaps elevated to HIGH when they drive authorization or multi-role handoff. |
| `knowledge/mxagile-handoff.txt` | Added `## Business Flow Handoff` section (flow → TC/VPL traceability, revision impact, Mermaid canonicity rule) and `## Knowledge Graph Handoff` section (build/refresh steps, design_contract_ref format, affected() usage) |

---

### New Knowledge Files

| File | Content |
|---|---|
| `knowledge/knowledge-graph.txt` | Provider-neutral KG contract, edge types (all 17 standard + 3 Business Flow), provenance classes (CANONICAL/EXTRACTED/INFERRED with precedence), graph-assisted orientation/resync/impact discovery, freshness/staleness handling, canonical validation after lookup, fallback to YAML traversal, what MxMocketeer must generate to feed the graph |
| `knowledge/business-flows.txt` | Complete flow entry schema (FLOW-NNN), step entry schema (FLOWSTEP-NNN), 7 step types, transition schema, stability rules, Mermaid generation algorithm + inline JS, flow revision impact in revision_delta.effects[], flow-to-verification traceability chain (FLOW → REQ → TC → VPL → Campaign), DIM-BUSINESS_FLOWS assessment dimension + gap categories, what NOT to include in business flows, complete worked example |

---

### Unchanged Knowledge Files

| File | Reason unchanged |
|---|---|
| `knowledge/golden-mockuphtml.txt` | Phase 2 implementation task: the golden reference mockup will be updated to include a structured flow example. Not changed in this spike. |
| `knowledge/mendix-design-guide.txt` | No overlap with Knowledge Graph or Business Flow capabilities. |

---

### Package / Export Instructions

After Phase 2 implementation, produce a new M365 package:

1. **System Prompt** — copy complete content of updated `system-prompt.md`.
2. **Knowledge files to re-upload** (replace existing):
   - `knowledge/design-contract.txt` (updated)
   - `knowledge/discovery-assessment.txt` (updated)
   - `knowledge/mxagile-handoff.txt` (updated)
3. **New knowledge files to upload** (first time):
   - `knowledge/knowledge-graph.txt`
   - `knowledge/business-flows.txt`
4. **Unchanged — no action required**:
   - `knowledge/golden-mockuphtml.txt` (re-upload only when golden mockup is updated in Phase 2)
   - `knowledge/mendix-design-guide.txt`
5. **Suggested Prompts** — unchanged; no action required.
6. **Agent name** — unchanged: MxMocketeer v3.

Total knowledge files after update: **7** (was 5).

---

### M365-Specific Validation

Before broad rollout of the updated package:

1. Run the existing Tier 0 validation:
   ```powershell
   pwsh products/MxMocketeer/tests/test-mocketeer-validation.ps1
   ```
   This validates: system prompt character count, required knowledge files (will fail
   if it does not list the two new files — update the validation test to expect 7 files).

2. Check system prompt character count after additions. If the M365 Copilot Agent Builder
   imposes a character limit and the count is exceeded, move less-critical behavioral
   detail from system-prompt.md to the knowledge files without loss of coverage.

3. Manual acceptance test for Business Flows:
   - Prompt: "Create a flow for submitting an expense report — manager must approve."
   - Verify output: structured steps[] with FLOW-NNN and FLOWSTEP-NNN IDs, transitions,
     screen_ref and req_refs populated, Mermaid rendered in the HTML (not stored in JSON).

4. Manual acceptance test for Knowledge Graph awareness:
   - Prompt: "What should a developer do with the flows after accepting this mockup?"
   - Verify: response mentions stable IDs, affected(), PARTICIPATES_IN edges, TC traceability.

5. Update `tests/test-mocketeer-validation.ps1` to:
   - Assert 7 knowledge files are listed in `agent-builder-setup.md`
   - Assert `system-prompt.md` contains the "## Business Flows" section
   - Assert `system-prompt.md` contains the "## Knowledge Graph Context" section

---

### Files to Replace / Upload in Copilot Studio

When deploying the updated package, the configurator must:

| Action | File |
|---|---|
| Replace Instructions | Paste new `system-prompt.md` content |
| Replace knowledge file | `knowledge/design-contract.txt` |
| Replace knowledge file | `knowledge/discovery-assessment.txt` |
| Replace knowledge file | `knowledge/mxagile-handoff.txt` |
| Upload new knowledge file | `knowledge/business-flows.txt` |
| Upload new knowledge file | `knowledge/knowledge-graph.txt` |
| No action | `knowledge/golden-mockuphtml.txt` (until Phase 2 golden mockup update) |
| No action | `knowledge/mendix-design-guide.txt` |

---

## Constraints Confirmed

- YAML canonical artifacts are not replaced by any graph format.
- Graphify is not a mandatory dependency. Default provider: `artifact-index`.
- Mermaid text is never stored in the contract or canonical artifacts.
- No hosted graph service without explicit developer opt-in and `local_only: false` confirmation.
- CapTrack application code: not modified.
- Company Layer: not modified.
