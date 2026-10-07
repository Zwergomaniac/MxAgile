# MxAgile Knowledge Graph

## What the Knowledge Graph Is

The MxAgile Knowledge Graph is a derived, rebuildable index of all cross-artifact
relationships in a project. It is built from canonical YAML artifacts — requirements,
specs, tasks, test contracts, verification plans, decisions, and revisions — and is
separate from those artifacts.

Key invariant:
  YAML canonical artifacts = CANONICAL TRUTH
  The Knowledge Graph is derived, non-authoritative, and disposable.

Deleting and rebuilding the graph changes nothing about project semantics.
No lifecycle gate may pass solely because the graph says so.

A graph is a query acceleration tool. Its absence never blocks correct MxAgile workflow.

---

## Provider-Neutral Contract

The Knowledge Graph is accessed through a provider-neutral contract. The underlying
provider (artifact-index, graphify, or other) is transparent to consumers.

Operations:
  build()     — rebuild from canonical YAML; safe and idempotent at any time
  refresh()   — incremental update after specific artifact changes
  status()    — staleness check: current | stale | unknown
  query()     — traverse from a node to related nodes up to N hops
  neighbors() — single-hop: upstream (towards source) or downstream (towards evidence)
  paths()     — all paths between two nodes (traceability chains)
  affected()  — all artifacts transitively downstream of a changed artifact
  explain()   — human-readable summary of an artifact's full graph context

Do not couple to Graphify-specific behavior. All graph calls go through this contract.

---

## Edge Types and Their Meaning

Standard CANONICAL edges in the graph:

  DERIVED_FROM      Page → Requirement (via REQ.derivedFrom)
  APPLIES_TO        Requirement → Page (via REQ.screens[])
  IMPLEMENTED_BY    Requirement → Spec → Task
  DEPENDS_ON        Task → Task (dependency)
  TRACES_TO         Task → Requirement (supplementary direct ref)
  COVERS            Test Contract → Requirement
  PLANS             Verification Plan → Test Contract
  GOVERNS           Decision → Requirement / Screen
  SUPERSEDED_BY     Decision → Decision
  AUTHORIZED_BY     Revision → Decision
  IMPACTS           Revision → Requirement
  AFFECTS_SCREEN    Revision → Page
  VERIFIED_BY       Page → Verification Scenario
  COVERS_SPEC       Scenario → Spec

Business Flow edges (present when structured flows are in the Design Contract):
  PARTICIPATES_IN   Requirement → Business Flow (via step.req_refs[])
  SHOWN_ON          Business Flow → Page (via step.screen_ref)
  DECIDED_BY        Business Flow → Decision (via step.decision_refs[])

---

## Edge Provenance Classes

Every edge has a provenance class that determines its authority:

CANONICAL
  Derived deterministically from explicit YAML reference fields.
  These are the only edges that may authorize downstream action.
  Source: dedicated ref fields in canonical YAML (derivedFrom, requirements[], spec,
  requirement_ids[], test_contract_id, acceptance_decisions[], req_refs[], etc.)

EXTRACTED
  Explicitly found in repository artifacts but not in dedicated CANONICAL ref fields.
  Example: a requirement ID mentioned in story spec narrative text.
  Valid for surfacing candidates and generating reports.
  Must NOT trigger automatic artifact mutation or lifecycle advancement.

INFERRED
  Semantic provider suggestions (embedding similarity, NLP proximity).
  Always labeled provenance: INFERRED.
  Must NEVER silently override canonical artifact state.
  When INFERRED contradicts CANONICAL: CANONICAL wins; conflict is surfaced to developer.

Precedence: CANONICAL > EXTRACTED > INFERRED

---

## How MxMocketeer Feeds the Graph

MxMocketeer produces the Design Contract, which is the upstream input for graph construction.
Every structured element in the Design Contract with a stable ID becomes a potential graph node
or edge source when the downstream MxAgile pipeline processes the handoff.

What the graph can resolve from a well-structured Design Contract:

From requirements[]:
  REQ-NNN nodes, linked to role_refs, screen_refs, decision_refs.
  Consumed downstream via TC.requirement_ids[], SPEC.requirements[].

From decisions[]:
  DEC-NNN nodes, linked to affected_requirements, affected_screens.
  Consumed downstream via GOVERNS edges.

From screens[]:
  PAGE-NNN nodes, linked to flows and requirements.
  Consumed downstream via APPLIES_TO, SHOWN_ON edges.

From flows[] (when structured — see "Business Flows" knowledge file):
  FLOW-NNN nodes with PARTICIPATES_IN, SHOWN_ON, DECIDED_BY edges.
  step.req_refs[] creates PARTICIPATES_IN edges: REQ-NNN → FLOW-NNN.
  step.screen_ref creates SHOWN_ON edges: FLOW-NNN → PAGE-NNN.
  step.decision_refs[] creates DECIDED_BY edges: FLOW-NNN → DEC-NNN.

From effects[]:
  Effect downstream_artifacts[] creates INFERRED candidate edges to REQ-NNN, SPEC-NNN,
  TASK-NNN identifiers referenced in the effect. These become EXTRACTED edges in the graph.

Implication: stable IDs matter. An element without a stable ID cannot be a graph node.
Renaming IDs silently breaks graph edges. Use SUPERSEDED status instead of renaming.

---

## Graph-Assisted Orientation

When a developer first opens a project with a graph available:

1. Call status() to confirm the graph is current.
2. Call query(REQ-NNN) to see the full traceability chain for any requirement.
3. Call explain(REQ-NNN) to get a human-readable context summary.
4. Call neighbors(SPEC-NNN, upstream) to see all requirements a spec implements.
5. Call neighbors(TC-NNN, downstream) to see all verification plans for a test contract.

This replaces a manual file-by-file scan. Always validate graph findings against
canonical YAML before acting on them. The graph is an index; the files are truth.

---

## Graph-Assisted Lifecycle Re-Sync

The lifecycle re-sync policy defines the authoritative re-sync algorithm.
The graph assists but does not replace process-state.yaml gate values.

  1. Check process-state.yaml for the authoritative gate result of each wave.
  2. Use graph status() to detect a stale index before querying.
  3. Use affected(changed_id) to surface downstream candidates after a change.
  4. Verify each candidate against its canonical YAML before marking anything STALE.
  5. Never use the graph alone to advance or fail a lifecycle gate.

The process-state gate values in planning/lifecycle/process-state.yaml are always
authoritative. The graph surfaces candidates for the developer to review.

---

## Graph-Assisted Impact Candidate Discovery

When a canonical artifact changes:

  1. Call affected(changed_id, downstream) to get transitively downstream candidates.
  2. Review each candidate's canonical YAML file before declaring it impacted.
  3. Classify impact per lifecycle.yaml change_propagation vocabulary:
     CURRENT / CHANGED / IMPACT_REVIEW_REQUIRED / STALE / REOPENED / VERIFIED
  4. Do not automatically mark candidates STALE — surface them for developer review.
  5. Check for CANONICAL edge presence before relying on EXTRACTED or INFERRED edges.

CRITICAL: Absence of a graph edge is NOT proof of absence of impact.
A missing edge may mean: the graph is stale, the relationship is not yet indexed,
or the relationship is EXTRACTED/INFERRED and not yet emitted to the graph.
Always supplement graph results with direct YAML file checks for high-stakes decisions.

---

## Graph Freshness and Staleness

The graph carries a status: current | stale | unknown.

A graph is stale when canonical YAML has changed since the last build.
A graph is unknown when it has never been built.

Always check freshness before relying on results:
  current  → results are reliable for candidate discovery and orientation
  stale    → rebuild or treat results as indicative only
  unknown  → fall back to direct YAML traversal

Staleness of the graph does NOT mean canonical artifacts are stale.
Canonical artifacts are always the truth. The graph is a query index over them.

---

## Canonical Artifact Validation After Graph Lookup

The graph is a query index. Before acting on a graph result, always confirm:

  1. The referenced artifact file exists at its canonical path.
  2. The artifact's status field is not superseded or draft-only.
  3. The edge's provenance is CANONICAL or EXTRACTED, not only INFERRED.
  4. For lifecycle decisions: re-read the canonical YAML — do not trust the cached graph value.

A graph node may reflect a state that was current at the last build but has since changed.

---

## Fallback Behavior (Graph Unavailable / Stale / Failed)

If the graph is unavailable, stale, unknown, or errors:

  1. Fall back to direct YAML traversal of canonical artifacts:
       requirements/*.yml      — derivedFrom, screens[]
       specs/*.yml             — requirements[]
       planning/tasks/*.yml    — spec, req[], depends_on[]
       planning/test-contracts/*.yaml  — requirement_ids[]
       planning/verification-plans/*.yaml — test_contract_id
       planning/decisions/*.yml — affected_requirements[], affected_screens[]
  2. Use scripts/resolve_impact.py for programmatic traversal when available.
  3. Do not block lifecycle actions on graph unavailability.
  4. Report graph status to the developer so they can rebuild if needed.

The graph capability is an acceleration tool. Its absence never blocks correct workflow.

---

## What MxMocketeer Must Generate to Support the Graph

To maximize graph quality, MxMocketeer must:

1. Assign stable IDs to all graph-visible elements:
   REQ-NNN, DEC-NNN, ROLE-NNN, SCREEN-NNN, PAGE-NNN, FLOW-NNN, FLOWSTEP-NNN.
   IDs are never renamed — use status: SUPERSEDED instead.

2. Include cross-references in structured fields (not only in narrative text):
   - requirements[].screen_refs, requirements[].decision_refs
   - flows[].steps[].req_refs, steps[].screen_ref, steps[].decision_refs
   - effects[].downstream_artifacts, effects[].source_ids

3. Mark platform boundary elements so they are excluded from canonical graph nodes:
   screens with platform_boundary: true are excluded from application-level graph nodes.

4. Generate structured flows (see Business Flows knowledge file) so that
   FLOW-NNN nodes and PARTICIPATES_IN/SHOWN_ON/DECIDED_BY edges are available.

5. Never invent or modify IDs from existing MxAgile canonical artifacts.
   The id_map in design_contract_provenance tracks source-to-canonical mapping.
   Source IDs and canonical IDs are different namespaces.

---

## Graphify Optional Enrichment Provider (Phase 3)

### What Graphify Is (and Is Not)

Graphify is an OPTIONAL enrichment overlay for the MxAgile Knowledge Graph.
It adds code-structural relationships discovered via AST analysis.

Graphify MUST NOT:
  - Replace the native artifact-index provider
  - Become canonical project truth
  - Become a mandatory dependency
  - Be added to the M365 MxMocketeer package
  - Block any lifecycle operation

Graphify MAY:
  - Surface code dependencies not present in canonical artifact refs
  - Identify code functions that reference canonical artifact IDs in docstrings
  - Detect import cycles and code centrality (architectural hot spots)
  - Provide function-level call graphs as enrichment candidates

### Provider Hierarchy

When Graphify enrichment is enabled, the authority hierarchy is:

  CANONICAL (artifact-index) > EXTRACTED (Graphify AST) > INFERRED (Graphify LLM)

Enrichment results from Graphify are always tagged `enrichment_only: true` and carry
a `provenance` field. They appear in a separate `enrichment` or `enrichment_affected`
key in operation results — never mixed into canonical results.

### Graphify Architecture

Graphify is a separate CLI tool (`graphify` command, PyPI package `graphifyy`).
It produces `graphify-out/graph.json` in NetworkX node-link format.

Key edge types in the Graphify code graph:
  EXTRACTED (AST-derived, local, deterministic, zero token cost):
    calls        — function A calls function B
    imports      — module A imports from module B
    imports_from — module A uses `from X import Y`
    contains     — module contains function/class
    rationale_for — docstring/comment belongs to function

  INFERRED (LLM-based, requires opt-in, may cost tokens):
    semantic / similarity edges (requires GEMINI_API_KEY or similar)
    Not produced in local-only mode

### Installation

Install via the managed installer:

  pwsh scripts/install-graphify.ps1

Requirements:
  - uv must be available (https://docs.astral.sh/uv/getting-started/installation/)
  - Python 3.8+
  - Package: graphifyy >= 0.9.28 (note double-y in package name; CLI is `graphify`)

The installer:
  1. Checks uv availability
  2. Verifies existing graphify version vs constraint
  3. Installs/upgrades via: uv tool install graphifyy>=0.9.28
  4. Runs smoke test: graphify --version
  5. Writes .mxagile/state/graphify-state.yaml

On failure (uv not found, install error, network unavailable): the installer
exits 0 with a warning. MxAgile core operations are NEVER blocked.

### Enabling Graphify Enrichment

After installation, enable in .mxagile/config.yaml:

  enrichment_provider: graphify
  graphify:
    enabled: true
    output_dir: graphify-out
    local_only: true      # strips external API keys — enforces local-first
    incremental: true     # uses 'graphify update' (AST-only, no LLM)
    version_constraint: ">=0.9.28"

The default configuration has `enrichment_provider: none`. No Graphify calls
are ever made unless both `enrichment_provider: graphify` AND `enabled: true`.

### Building the Graph

Initial build (AST extraction, no LLM):

  graphify update <project-root>

Incremental rebuild after code changes (no LLM, no API cost):

  graphify update <project-root>

Full rebuild (may use LLM for community labeling if API key is set):

  graphify <project-root>

From scripts/graphify_provider.py:

  from scripts.graphify_provider import GraphifyProvider
  provider = GraphifyProvider(project_root='.')
  result = provider.build(incremental=True)

The MxAgile integration uses incremental mode (`graphify update`) by default.
This is 100% local, deterministic, and zero token cost for code files.

### Security Model

local_only: true (default) enforces the following:
  - GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_API_KEY, COHERE_API_KEY
    are stripped from the subprocess environment before running graphify
  - No data leaves the developer's machine during graph builds
  - LLM-based semantic extraction is disabled

When local_only is false: semantic extraction may make external API calls if
an API key is present in the environment. This must be explicitly opted into.

The Graphify output directory (graphify-out/) must not overlap with any canonical
artifact directory (requirements/, specs/, planning/, .mxagile/).
The conflict check in verify_no_canonical_conflict() enforces this at runtime.

### Enrichment Overlay API

After enabling, enrichment results appear automatically in:

  kg.neighbors(node_id)
    → result['enrichment']  list of enrichment-only neighbors (code context)

  kg.affected(changed_ids)
    → result['enrichment_affected']  list of code-level affected candidates

Direct GraphifyProvider API (scripts/graphify_provider.py):

  provider.neighbors_overlay(node_id, canonical_neighbors=set())
    → enrichment-only neighbors not already in canonical graph

  provider.affected_candidates(changed_ids, canonical_affected=set())
    → BFS from changed IDs through code graph; returns enrichment candidates

  provider.find_unlinked_artifacts(canonical_node_ids)
    → artifact IDs (REQ-NNN, SPEC-NNN, etc.) referenced in code/docs but
      not present in the canonical artifact index

  provider.classify_edges(canonical_edge_pairs=set())
    → extracted[], inferred[], duplicate[], enrichment_count

  provider.verify_no_canonical_conflict(canonical_nodes, canonical_edges)
    → safe flag, conflicts list — run after major graph updates

### Pilot Findings (tests/fixtures/graphify-pilot)

The pilot fixture contains a representative mini-project:
  - 3 Python modules (auth.py, session.py, validators.py)
  - 3 canonical requirements (REQ-001, REQ-002, REQ-003)
  - Supporting SPEC, TASK, DEC, PAGE, SCN, TC, VPP, revision
  - Non-indexed planning artifacts (GAP, PP, VPL)

Results from `graphify update tests/fixtures/graphify-pilot` (v0.9.28):
  - 31 nodes, 36 edges, 6 communities
  - 100% EXTRACTED (zero token cost, zero external API calls)
  - Import cycle detection: none found

Key relationships discovered (absent from native artifact graph):
  - auth.py --imports_from--> validators.py
  - authenticate() --calls--> check_password_rules(), sanitize_input(), _create_jwt_token()
  - refresh_session() --calls--> _create_jwt_token() (cross-file call, session.py→auth.py)
  - invalidate_session() --calls--> validate_session()
  - Docstring rationale nodes that mention REQ-001, REQ-002, REQ-003 (code-to-requirement bridge)

Adoption status: ADOPT_EXPERIMENTAL
Rationale: Extracted relationships are genuinely useful and zero-cost; integration is
opt-in; the node-ID scheme is pre-#1504 (known limitation in v0.9.28); pilot scope is
small. Upgrade path exists. Promotion to ADOPT when node-ID scheme stabilizes and
integration has run on a real project for one sprint.

### Refreshing the Graphify Graph

Graphify staleness is detected by comparing source file modification times to
the graph.json modification time. The provider considers the graph stale if any
.py, .ts, .js file in src/, scripts/, or docs/ is newer than graph.json.

Auto-refresh policy: Graphify does NOT auto-refresh during lifecycle operations.
The native artifact-index may auto-refresh (auto_refresh_on_resync: true) but
the Graphify overlay is always refresh-on-demand.

To refresh: run `graphify update <project-root>` or call `provider.build(incremental=True)`.

### Failure and Fallback

When Graphify is unavailable (not installed, graph missing, build failed):
  - All provider methods return empty results
  - neighbors() and affected() return only canonical results (no enrichment key)
  - status() returns enrichment.status: DISABLED or MISSING
  - No exception is raised
  - No lifecycle operation is blocked

The enrichment overlay is strictly additive. Removing or disabling Graphify
has zero effect on canonical workflow correctness.

### Graphify Operating Contract

**Mode: TARGETED TECHNICAL STRUCTURAL ENRICHMENT**

Only code-structural surfaces (Python modules, test files) are indexed.
Framework management surfaces (schemas, agents, skills, policies, docs) are
excluded via `.graphifyignore` committed at the repo root.

This operating contract was derived from an A/B test comparing FULL_REPO
(317 files, 5793 nodes) against TARGETED scope (code-only, ~929 nodes):

  FULL_REPO problems:
    - 18 JSON Schema files → 1,695 keyword-only noise nodes (29.3% of graph)
    - Top god node: `enum` with 38 edges — a schema keyword, not code
    - 30+ communities named "properties" — schema fragmentation
    - Code-structure queries degraded by noise hub centrality

  TARGETED advantages:
    - Code-structure queries (call graphs, import chains) are materially better
    - God-node analysis reflects real code centrality
    - Zero schema-keyword community pollution

**Surface classification:**

| Surface                  | Index?  | Why                                              |
|--------------------------|---------|--------------------------------------------------|
| scripts/*.py             | YES     | Core implementation — call/import graph          |
| tests/*.py               | YES     | Test logic — call graph, fixture refs            |
| tests/fixtures/**/*.py   | YES     | Fixture code — structural relationships          |
| .mxagile/schemas/        | NO      | JSON Schema → keyword noise, no call edges       |
| .mxagile/agents/skills/  | NO      | Markdown, no AST                                 |
| .mxagile/policies/       | NO      | Markdown, no AST                                 |
| docs/                    | NO      | Narrative markdown, no code relationships        |
| planning/                | NO      | Canonical YAML → native Artifact Graph only      |
| *.ps1 (root)             | NO      | PowerShell AST near-zero relationships in v0.9.28|
| graphify-out*/           | NEVER   | Fail-closed contamination guard                  |
| .claude/, .agents/       | NO      | Agent instructions markdown                      |

**Fresh-clone behavior:**

On a fresh clone, Graphify is absent and `graphify-out/` does not exist.
This is normal — MxAgile operates fully without it.

  1. Clone → all MxAgile lifecycle operations work immediately (graph: native only)
  2. If code-structure enrichment is needed:
     a. pwsh scripts/install-graphify.ps1
     b. Enable in .mxagile/config.yaml (enrichment_provider: graphify, enabled: true)
     c. graphify update <project-root>   (or: python scripts/graphify_provider.py build)
  3. graphify-out/ is gitignored — it is never committed

**Scope change safety (scope fingerprint mechanism):**

The `scope_fingerprint` field in `.mxagile/state/graphify-state.yaml` stores a
SHA-256 hash of `.graphifyignore` at the last successful build.

When `provider.build()` is called and the current `.graphifyignore` hash differs
from the stored fingerprint:
  1. `graphify-out/` is deleted entirely (prevents fail-closed contamination)
  2. A full rebuild is run (not incremental)
  3. The new fingerprint is written to state on success

This ensures a stale broad graph cannot silently masquerade as a targeted graph
after the scope definition changes.

### Troubleshooting

graphify command not found:
  → Run: scripts/install-graphify.ps1
  → Or: uv tool install graphifyy>=0.9.28
  → Then: uv tool update-shell (if not in PATH)

Graph not built (status: MISSING):
  → Run: graphify update <project-root>
  → Check .mxagile/state/graphify-state.yaml for error

"pre-#1504 node-ID scheme" warning:
  → Known issue in graphify v0.9.28. IDs may collide for same-name files in
    different directories. Upgrade graphify or use rebuild with --force when
    the warning appears.

Enrichment results are empty even though Graphify is installed:
  → Verify .mxagile/config.yaml: enrichment_provider must be 'graphify' AND
    graphify.enabled must be true
  → Verify graph.json exists in output_dir (default: graphify-out/graph.json)
  → Run provider.status() to inspect the current state
