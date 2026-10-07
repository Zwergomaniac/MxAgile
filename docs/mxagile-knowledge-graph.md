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
