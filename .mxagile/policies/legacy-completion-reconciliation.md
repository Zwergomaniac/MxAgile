# Policy: Legacy Completion Reconciliation

Defines how MxAgile evaluates historical Waves, requirements, and delivery artifacts whose
lifecycle metadata predates the current completion protocol.

A project that has passed through multiple MxAgile generations may reach the
Project/Release Completion Checkpoint with Waves whose canonical `phase` is not yet
`done` but whose repository evidence demonstrates that the underlying work was implemented
and verified under older protocols. This policy ensures such scope is correctly classified
without requiring expensive implementation or verification replay.

Referenced by: `policies/project-release-checkpoint.md` § Feature-Scope Completeness Check.
Authority order: `policies/lifecycle-resync.md` § Autoritaetsreihenfolge (extended here).

---

## Legacy Completion Classification Model

When a Wave, requirement, or delivery item cannot be resolved by stored lifecycle phase alone,
classify it using the following vocabulary before drawing any completeness conclusion.

| Classification | Meaning |
|---|---|
| `CURRENT_REQUIRED_SCOPE` | Accepted, authorized, not yet fully implemented/verified under current protocol — genuine remaining work |
| `VERIFIED_LEGACY_STATE` | Implementation and verification occurred under a prior MxAgile generation; sufficient repository evidence supports completion without protocol-metadata replay |
| `DEFERRED_OUTSIDE_FEATURE_SCOPE` | Explicitly deferred scope that belongs to a later release, NFR, go-live, or compliance activity — does not block FEATURE_SCOPE_COMPLETE |
| `SUPERSEDED` | Requirement, revision, Design Contract, or plan that has been replaced by a later accepted artifact; retained for traceability but no longer current scope |
| `GENUINE_DECISION_BLOCKER` | An open business decision, unresolved DECISION_REQUIRED, or human-authority gate that cannot be satisfied without stakeholder input |
| `UNKNOWN_REQUIRES_RECONCILIATION` | Authority or provenance cannot be established from available evidence — a legitimate reconciliation blocker; do not fabricate authorization |

**"phase != done" MUST NOT by itself mean `CURRENT_REQUIRED_SCOPE`.**

**Implementation evidence alone (implementation artifact exists, checklist ticked) MUST NOT
by itself mean `VERIFIED_LEGACY_STATE`.** Evidence must include acceptance or equivalence.

---

## Evidence-Based Reconciliation

Before classifying historical scope, evaluate the authoritative evidence available in the
repository. The following evidence types may support `VERIFIED_LEGACY_STATE`:

| Evidence type | Example artifacts |
|---|---|
| Accepted requirements | `requirements/REQ-NNN.yml` with `status: accepted`; accepted story spec |
| Decisions | `planning/decisions/DEC-NNN.yaml` resolving DECISION_REQUIRED items for this scope |
| Revisions accepted | revision record with accepted scope confirmed by developer |
| Implementation state | completed checklist; implementation report; committed implementation artifacts |
| Quality gates | passing `mxcli check`, `mxcli lint`, `mxcli docker check` at time of delivery |
| Verification evidence | wave report, parity report, acceptance campaign results (any era) |
| Runtime/browser evidence | screenshots, Playwright results, acceptance campaign output |
| Acceptance records | wave report with `acceptance_gate: passed`; delivery report confirming completion |
| Supersession record | later revision absorbs earlier scope — earlier scope no longer active |
| Explicit deferral authority | developer-confirmed deferral entry in decisions or mission-state |
| Later revision absorption | a later accepted wave absorbs the open items from an earlier wave |

### VERIFIED_LEGACY_STATE Promotion Criteria

Classify as `VERIFIED_LEGACY_STATE` when ALL of the following hold:

1. The scope was authorized (accepted requirement, accepted revision, or developer-confirmed scope)
2. Implementation artifacts exist in the repository consistent with that scope
3. At least one of the following is present:
   - A wave report or acceptance record (any MxAgile era) for this scope
   - An acceptance campaign result confirming the scope was verified
   - Runtime/browser evidence consistent with acceptance of this scope
   - A developer-recorded decision confirming completion/acceptance
   - A later revision that absorbed and superseded this scope with acceptance evidence
4. No open DECISION_REQUIRED item for this scope remains unresolved by current evidence
5. No stronger contradicting evidence asserts the scope was not completed

### Provenance Preservation

When reconciling a Wave to `VERIFIED_LEGACY_STATE`:
- Record the classification and the evidence basis in the wave report or reconciliation note
- Do NOT remove or overwrite the original historical artifacts
- Update `process-state.yaml` wave entry to reflect reconciled completion with a
  `reconciliation_basis` field pointing to the evidence

**A `VERIFIED_LEGACY_STATE` classification permits the Wave to be counted as `done`
for all FEATURE_SCOPE_COMPLETE checks without repeating implementation or verification
under the current protocol.**

---

## Canonical State Authority Order

When multiple representations of the same state exist, apply this deterministic authority
order. A higher-authority source ALWAYS wins over a lower-authority source.

| Rank | Source | Path | Notes |
|---|---|---|---|
| 1 | **Canonical lifecycle/mission state** | `planning/lifecycle/process-state.yaml`, `planning/mission/mission-state.yaml` | Git-tracked, durable — primary authority |
| 2 | **Canonical delivery evidence** | `planning/wave-reports/`, `planning/acceptance-campaigns/`, `planning/decisions/` | Authoritative delivery record |
| 3 | **Historical evidence artifacts** | Older wave reports, acceptance campaigns, parity reports | Support reconciliation but do not override canonical state |
| 4 | **Scratch/session cache** | `.concord/scratch/process-state.yaml` | Session-local; fallback only when canonical absent |
| 5 | **Historical reports** | `planning/project-release/`, generated delivery reports, migration-era reports | Reference only; stale markers in these do not reopen canonical completion |
| 6 | **Checklists** | `planning/checklists/` | Implementation detail; completion requires higher-authority confirmation |
| 7 | **Narrative notes** | Story specs, wave notes, checklist text | Context; do not override canonical state |
| 8 | **Generated/supporting artifacts** | Board stories, generated manifests | Least authority; never override acceptance evidence |

### Canonical State Wins on Conflict

On conflict: canonical state → reconstruct session/cache — not vice versa.

```
canonical state (Rank 1-2)
→ reconstruct session/cache state (Rank 4)

NOT:

stale cache (Rank 4)
→ reinterpret or downgrade canonical state
```

On resume or re-sync: if `process-state.yaml` (canonical) shows a Wave as `done` but
`.concord/scratch/process-state.yaml` (session cache) shows it as `verifying`, the
canonical state wins. Session cache is reconstructed from canonical state — not vice versa.

If canonical state and session cache conflict:
- Reconcile or regenerate the cache
- Do NOT downgrade canonical completion
- Do NOT treat the stale cache phase as current truth

---

## Stale Historical Metadata

Historical artifacts may retain migration-era status markers that have since been
superseded by stronger evidence. These markers MUST NOT automatically become current work.

### Known Stale Marker Patterns

| Stale marker | Where found | Do NOT automatically... |
|---|---|---|
| `Review required` | Historical report, parity report note | Reopen the Wave or create a new review task |
| `phase: verifying` | Old process-state cache | Treat as current phase when canonical state shows `done` |
| `partial` | Old checklist, old report | Interpret as currently incomplete without checking canonical evidence |
| `status: unresolved` | Old decision log note | Open as a new DECISION_REQUIRED without verifying current decisions |
| `missing package warning` | Installation log, snapshot | Treat as current missing package without checking current model |
| Open checklist entry | Historical checklist | Count as currently open without checking acceptance evidence |

### Verification-Before-Action Rule

Before acting on any stale historical marker:

1. Read the current canonical evidence (`process-state.yaml`, `planning/decisions/`,
   `planning/wave-reports/`, `requirements/`)
2. Determine if a newer canonical or delivery evidence artifact resolves, supersedes,
   defers, or invalidates the marker
3. If newer evidence resolves it: do not reopen; record the resolution basis
4. If no newer evidence exists: the marker may be a legitimate current gap — classify it
   using the Legacy Completion Classification Model above
5. Never create new implementation work based solely on a stale marker without first
   completing steps 1–3

**New repository evidence can invalidate stale historical notes.
Current evidence always outranks the note.**

---

## Deferred Scope

Explicitly deferred scope MUST be classified before it can block FEATURE_SCOPE_COMPLETE.

### Feature Scope vs Deferred NFR / Go-Live / Compliance Scope

| Scope type | Classification | Effect on FEATURE_SCOPE_COMPLETE | Effect on RELEASE_READY |
|---|---|---|---|
| Accepted authorized Feature scope (not implemented) | `CURRENT_REQUIRED_SCOPE` | BLOCKS | BLOCKS |
| Explicitly deferred Go-Live / NFR / compliance scope | `DEFERRED_OUTSIDE_FEATURE_SCOPE` | Does NOT block | May block |
| Explicitly deferred later-release feature scope | `DEFERRED_OUTSIDE_FEATURE_SCOPE` | Does NOT block | Depends on scope |
| Unclassified deferral | `UNKNOWN_REQUIRES_RECONCILIATION` | BLOCKS until classified | BLOCKS |

### Circular Semantics Prohibition

FEATURE_SCOPE_COMPLETE must not require completion of scope that is, by definition,
supposed to occur AFTER feature completion:

- NFR validation (performance, security, load)
- Go-live deployment configuration
- External governance approvals
- Compliance sign-off activities

These activities may appropriately block RELEASE_READY. They MUST NOT block FEATURE_SCOPE_COMPLETE.

### Deferral Authority

A deferral of Feature Scope items is only `DEFERRED_OUTSIDE_FEATURE_SCOPE` when:
- It is explicitly recorded in `planning/decisions/` as developer/PO-confirmed deferral, OR
- It appears in `mission-state.yaml` as explicitly scoped out of the current mission, OR
- A later revision explicitly absorbs the scope into a future authorized wave

Undocumented deferrals remain `UNKNOWN_REQUIRES_RECONCILIATION` until authority is established.

---

## Supersession

Historical requirements, revisions, Design Contracts, UI baselines, and implementation plans
that have been replaced by a later accepted artifact are `SUPERSEDED`.

### Supersession Criteria

An artifact is `SUPERSEDED` when:
- A later accepted artifact (requirement, revision, Design Contract) explicitly replaces it, OR
- A developer decision in `planning/decisions/` records supersession, OR
- The artifact's scope has been fully absorbed by a later accepted wave with delivery evidence

### Supersession Semantics

| What supersession means | What supersession does NOT mean |
|---|---|
| Artifact retained for traceability | Scope reactivation in current Feature Scope |
| Historical lineage preserved | The superseding artifact inherits unverified gaps from the superseded artifact |
| Earlier artifact no longer drives implementation | A DECISION_REQUIRED on the superseded artifact is current work |
| Reconciliation note recorded | The superseded artifact is deleted |

Superseded artifact existence is NOT evidence of incomplete current scope.

- Is NOT current scope authorization
- Is NOT evidence of incomplete current scope
- Is NOT a trigger for next implementation work

Do NOT create work items from superseded artifacts unless a current decision explicitly
re-authorizes the scope.

---

## Requirement Migration Gaps

Gaps in requirement numbering or legacy requirement artifacts that predate canonical
numbering MUST NOT automatically be interpreted as missing authorized scope.

### Authority Classification for Legacy/Migration Requirements

For each numbered gap or legacy artifact, determine authority from provenance:

| Classification | Meaning | Action |
|---|---|---|
| `authorized_current` | Accepted, active, within current Feature Scope | Include in FEATURE_SCOPE_COMPLETE check |
| `migrated_renumbered` | Requirement renumbered during migration; canonical number is authoritative | Trace to canonical; do not count gap as missing scope |
| `absorbed` | Scope absorbed by a later revision or accepted requirement | Trace to absorbing artifact; no independent scope |
| `superseded` | Replaced by a later accepted requirement | See Supersession above |
| `deferred` | Explicitly deferred by documented developer/PO decision | Classify per Deferred Scope above |
| `draft_never_authorized` | Artifact created but never formally accepted or authorized | Not scope; discard as planning artifact |
| `external_source_not_authorized` | Came from external source (Board story import, migration placeholder) not independently authorized | Not scope until explicitly authorized |
| `orphaned` | No provenance traceable — artifact exists without traceable origin or authorization | Preserve; classify as `UNKNOWN_REQUIRES_RECONCILIATION` |
| `unknown` | Authority cannot be established from available evidence | `UNKNOWN_REQUIRES_RECONCILIATION` — legitimate blocker |

**Do NOT create canonical requirements merely to make numbering continuous.**

An `unknown` legacy artifact is a legitimate reconciliation blocker until authority can be
established. It blocks FEATURE_SCOPE_COMPLETE only if it might represent unimplemented
authorized scope. Orphaned artifacts with no traceability to any accepted scope may be
classified as `draft_never_authorized` when there is positive evidence of their non-authorization.

---

## Feature-Scope Completeness Integration

The Feature-Scope Completeness Check in `policies/project-release-checkpoint.md` is extended
with a mandatory legacy reconciliation step.

### Extended Algorithm

```
historical Wave records found with phase != done
     OR
legacy requirement artifacts found with unclear status
     OR
canonical state disagrees with session cache
     ↓
LEGACY RECONCILIATION REQUIRED
     ↓
For each historical item:
  1. Read current canonical evidence (Rank 1-2)
  2. Apply Legacy Completion Classification
        → VERIFIED_LEGACY_STATE     → count as done; record reconciliation basis
        → CURRENT_REQUIRED_SCOPE    → genuine remaining work; route to earliest phase
        → DEFERRED_OUTSIDE_FEATURE_SCOPE → exclude from FEATURE_SCOPE_COMPLETE check
        → SUPERSEDED                → exclude; trace to successor
        → GENUINE_DECISION_BLOCKER  → surface to developer; block until resolved
        → UNKNOWN_REQUIRES_RECONCILIATION → surface to developer; block until classified
  3. Do NOT create implementation work for VERIFIED_LEGACY_STATE items
  4. Do NOT start DEFERRED or SUPERSEDED scope
     ↓
After all items classified:
  recompute FEATURE_SCOPE_COMPLETE
  using only CURRENT_REQUIRED_SCOPE items as remaining work
```

### What Does NOT Trigger Historical Re-work

The following MUST NOT cause historical implementation to be repeated:

- A Wave whose `phase` is stored as `verifying` but has a wave report with `acceptance_gate: passed`
- A historical checklist with an open item that was resolved by a later delivery
- A stale historical report containing "Review required" where current evidence confirms completion
- A requirement whose phase is stored as `verifying` when a later revision absorbed and accepted that scope
- A numbering gap in the requirement sequence
- A migration-era artifact that was never independently authorized

---

## Current Evidence Override of Historical Completion

A historical `COMPLETED` or `VERIFIED_LEGACY_STATE` classification is NOT permanent.
Current executable evidence that contradicts a historical completion claim overrides it.

### The Principle

```
HISTORICAL_COMPLETION + CURRENT_RUNTIME_CONTRADICTION → COMPLETION_INVALIDATED
```

A Completed state is a claim that the accepted behavior was verified at a point in time.
If current runtime verification demonstrates that accepted behavior is now broken,
the historical completion claim is no longer valid for that specific behavior.

### When Current Evidence Overrides

Current evidence overrides a historical completion claim when ALL of the following hold:

1. The current evidence was collected from the running application (RUNTIME or FRONTEND layer)
   against the current accepted scope.
2. The contradicted behavior is part of accepted current scope (not deferred or superseded).
3. The contradiction is a `CONFIRMED_REQUIREMENT_VIOLATION` per
   `policies/parity-finding-reconciliation.md` — not merely `VERIFICATION_OUTSTANDING`.
4. The finding has been classified through the standard observation → interpretation →
   contract resolution protocol.

### Override Actions

When a current evidence override is confirmed:

1. **Invalidate the specific completion claim** — update the affected verification record
   (parity dimension, proof point, campaign result) to reflect the new evidence.
   Set the affected dimension or proof point to `FAIL` with current evidence reference.

2. **Preserve traceability** — record WHY the completion was previously claimed and WHAT
   new evidence contradicts it:
   ```yaml
   completion_override:
     previous_status: VERIFIED_LEGACY_STATE  # or PASS, or ACCEPTANCE_COMPLETE
     previous_basis: "Wave report W01 acceptance_gate: passed (2026-08-15)"
     override_evidence: "Runtime verification 2026-10-09: expand/collapse non-functional"
     override_classification: CONFIRMED_REQUIREMENT_VIOLATION
     affected_dimensions: [interaction, state]
   ```

3. **Scope the invalidation** — only invalidate the specific behavior contradicted by
   current evidence. Do NOT reopen the entire Wave, requirement, or acceptance campaign
   when only a specific dimension or proof point is affected.

4. **Route to remediation** — the invalidated finding follows the standard remediation
   eligibility flow per `policies/autonomous-remediation.md`.

### What Override Does NOT Do

| Override means | Override does NOT mean |
|---|---|
| Specific behavior no longer verified | Entire Wave reopened |
| Targeted re-verification required | Full acceptance campaign re-run |
| Finding enters standard remediation flow | Historical acceptance invalidated wholesale |
| Completion claim for this behavior is paused | Unrelated completed work is affected |
| Traceability preserved | Historical evidence destroyed |

### Integration with Lifecycle Re-Sync

When a current evidence override occurs during lifecycle re-sync or verification:

- If the Wave is currently in `done` phase: the override creates a targeted verification
  gap that routes to the Verifying sub-phase for the affected proof points only.
  The Wave does not return to Implementing unless the fix requires model changes.
- If the Wave is currently in `verifying` phase: the override is absorbed into the
  current verification run as a new finding.
- Process-state is updated to reflect the override with the `completion_override` record.

---

## Observe-Before-Mutate in Reconciliation

Reconciliation of historical state is a READ-THEN-DECIDE sequence. The observe-before-mutate
principle (`policies/observe-before-mutate.md`) applies to reconciliation repairs.

### Reconciliation Repair Protocol

Before executing a prepared reconciliation action (updating process-state.yaml,
reclassifying a Wave, closing a DECISION_REQUIRED):

1. Re-read the relevant current canonical evidence
2. Verify the prepared mutation remains necessary and valid
3. If newer evidence has invalidated the premise: abandon the prepared mutation
4. Only execute the mutation when current evidence still supports it

### Staleness After Intervening Events

A previously prepared repair loses its authorization after any of:
- Lifecycle re-sync that changed phase or wave state
- Runtime verification that produced new evidence
- Repository reconciliation that reclassified scope
- User interruption with new information
- Discovery of evidence not seen when the repair was prepared

**A previously prepared repair is NOT authority to execute it.** Re-verify always.

---

## Agent Orientation

This policy is referenced by the orchestrator and the Feature-Scope Completeness Check.
Individual agents do not need to reproduce this policy in full. The following agents
are discovery points for this behavior:

| Agent | Orientation |
|---|---|
| Orchestrator (`orchestrator.md`) | Startup re-sync applies legacy reconciliation before concluding historical incompleteness; Feature-Scope Completion references this policy |
| Acceptance agent (`agents/acceptance-agent.md`) | Evidence-based completion promotes historical acceptance to VERIFIED_LEGACY_STATE |
| Maintainer/migration agent (`agents/maintainer.md`, `agents/migration-agent.md`) | Reconciliation of legacy artifacts uses the classification model here; does not rerun historical work |

The complete reconciliation algorithm lives here and in `policies/project-release-checkpoint.md`.
Agents reference, not duplicate, this policy.
