# Reconciliation

Canonical contract for how MxAgile handles Core UPDATE, Discovery reconciliation,
Refinement reconciliation, project structure convergence, and legacy artifact classification.

## Primary Principle

**An MxAgile Core UPDATE must not make an existing mature project behave like a new project.**

```
PRESERVE KNOWLEDGE
    ->
RECONCILE STRUCTURE
    ->
RECONCILE SEMANTICS
    ->
IDENTIFY GAPS / STALE / CONFLICTS
    ->
REOPEN ONLY AFFECTED SCOPE
    ->
CONTINUE LIFECYCLE
```

Do not perform unnecessary rediscovery, refinement or verification.

---

## Post-Core-Update Lifecycle

The canonical existing-project flow after a Core UPDATE:

```
1. mxagile-setup.ps1 (or mxagile-setup-mercedes.ps1) → Core UPDATE
2. Lifecycle re-sync (policies/lifecycle-resync.md)
3. Project structure inventory
4. Schema/state reconciliation
5. Discovery reconciliation
6. Refinement reconciliation
7. Evidence reconciliation
8. Canonical structure convergence
9. Identify remaining gaps / stale / conflicts
10. Targeted verification / Discovery / Refinement (only what is needed)
11. Continue current lifecycle
```

The existing project does NOT automatically return to initial Discovery.
The existing project does NOT reset lifecycle progress.

---

## Lifecycle Position Must Survive Update

A Core UPDATE must preserve the concept of where the project currently is.

The reconciled lifecycle state must reflect:
- Completed valid work (implementation-complete items remain complete)
- Current implementation state
- Verification gaps (new dimensions requiring evidence)
- Stale evidence (target/requirement changed since `verified_at`)
- Unresolved conflicts
- Reopened scope (only affected scope, not everything)

---

## Discovery Reconciliation Contract

**Does existing Discovery rerun from scratch? NO.**

### What Discovery Reconciliation Is

```
DISCOVERY RECONCILIATION
    =
INVENTORY EXISTING DISCOVERY
    ->
MAP TO CURRENT CANONICAL CONTRACTS
    ->
PRESERVE VALID FINDINGS
    ->
UPGRADE RECONSTRUCTABLE FIELDS WITH PROVENANCE
    ->
IDENTIFY MISSING / CURRENT-CONTRACT INFORMATION
    ->
REOPEN ONLY AFFECTED DISCOVERY SCOPE
```

### What Discovery Reconciliation Is NOT

- Delete existing Discovery
- Regenerate all Discovery
- Rediscover the entire application
- Recreate Requirements
- Re-run browser analysis unconditionally

### Discovery Claim Classification

For each relevant Discovery artifact or claim, classify as:

| Classification | Meaning | Action |
|---|---|---|
| `REUSABLE` | Current, authoritative, valid under new contract | Preserve and reference |
| `RECONSTRUCTABLE` | Can be derived from existing artifacts with provenance | Upgrade with provenance |
| `INCOMPLETE` | Exists but missing information required by new contract | Supplement only missing fields |
| `STALE` | Was valid but target/requirement has changed | Rediscover affected scope only |
| `CONFLICTING` | Evidence contradicts requirements or other claims | Resolve through authoritative source analysis |
| `MISSING` | No Discovery exists for this scope | Discover only required missing scope |

### When Discovery IS Reopened

Reopen only the affected portion of Discovery when:
- A specific finding is `STALE` (target or source changed)
- A specific finding is `CONFLICTING` (stronger authoritative evidence contradicts it)
- A specific finding is `INCOMPLETE` for the new contract (e.g., new content dimension requires DOM text evidence not in original Discovery)
- A structural change to the application makes an existing finding invalid

### No Duplicate Discovery Truth

After reconciliation there must be ONE identifiable current canonical representation.
Historical evidence is preserved. There must not be three competing active truths:
old Discovery + new Discovery + migration Discovery.

---

## Refinement Reconciliation Contract

**Does existing Refinement rerun from scratch? NO.**

### What Refinement Reconciliation Is

```
REFINEMENT RECONCILIATION
    =
PRESERVE VALID ACCEPTED DECISIONS
    ->
MAP TO CURRENT SCHEMA / CONTRACT
    ->
IDENTIFY AFFECTED DECISIONS
    ->
REOPEN ONLY AFFECTED REFINEMENT SCOPE
```

### Accepted Refinement Decisions That Must Be Preserved

- Accepted decisions (product/design intent)
- Requirement interpretations
- Spec decisions
- UI intent and pattern choices
- Widget selection rationale
- Source-priority resolutions
- Current target mockups
- Task decomposition
- Acceptance criteria

### A New Evidence Schema Does Not Invalidate Accepted Decisions

Example:
- Previous Refinement established UI intent as `responsive_record_list`
- New parity contract requires richer content evidence

Result: preserve the design decision, collect missing content evidence.
Do NOT repeat the design decision.

### When Refinement IS Reopened

Reopen only the affected decision scope when:
- Stronger authoritative evidence conflicts with the current decision
- The active target changed and the decision was based on the old target
- A Requirement changed that the decision depended on
- Discovery found an actual contradiction to the accepted decision
- A widget choice fails runtime fit (see policies/ui-element-selection.md)
- Source priority does not resolve a conflict that the decision assumed was resolved
- The existing decision lacks enough information to determine the current target

### Target Mockup Reconciliation

Preserve:
- Immutable source mockups (never moved or changed)
- Accepted refined/current targets and their history
- Historical target versions in `planning/target-mockups/_history/`

If existing Refinement already established the current target:
- Migrate/reference it canonically
- Do NOT recreate the target because the artifact location changed

---

## Full Reconciliation Definition (Preserved)

```
FULL RECONCILIATION
    =
FULL SCOPE ACCOUNTING
+ CONSERVATIVE EVIDENCE REUSE
+ TARGETED RE-VERIFICATION
```

Full reconciliation does NOT mean:
- Repeat Discovery
- Repeat Refinement
- Repeat every browser test
- Regenerate all Requirements/Specs/Tasks

See `policies/ui-parity.md — Full Reconciliation` for the evidence classification table.

---

## Legacy Process-State Reconciliation

Existing projects may have their lifecycle state only in `.concord/scratch/process-state.yaml`
(gitignored). On first reconciliation after a Core UPDATE:

```
1. Inventory .concord/scratch/process-state.yaml
2. Classify each field:
   DURABLE  — phase, gates, completed_scripts, parity_reconciliation, coverage_matrix_state,
               mutation_eligibility, paused_at, pause_reason, evidence_upgrade state
   EPHEMERAL — runtime_pipeline_stage, database readiness, runtime_config (session-specific)
3. Migrate DURABLE fields to planning/lifecycle/process-state.yaml (Git-tracked)
4. Validate the canonical file against process-state.schema.json
5. After successful migration: .concord/scratch/process-state.yaml is demoted to session cache
```

Do NOT delete `.concord/scratch/process-state.yaml` before migration is complete and validated.

---

## Project Structure Reconciliation

### Inventory Before Cleanup

Before deleting, moving or replacing legacy/non-canonical artifacts:

**INVENTORY FIRST.** The framework must not assume: legacy path = obsolete content.
Existing projects may contain durable project knowledge in historical locations.

### Legacy Artifact Classification

| Classification | Meaning | Action |
|---|---|---|
| `DURABLE_PROJECT_KNOWLEDGE` | Unique non-secret knowledge still needed | Migrate to canonical location; preserve provenance; update references |
| `HISTORICAL_EVIDENCE` | Supports existing parity/Discovery/Refinement claim | Preserve in canonical historical/evidence structure; maintain traceability |
| `DUPLICATE` | Identical canonical copy exists | Prove equivalence; retain canonical; remove redundant after validation |
| `OBSOLETE_GENERATED` | Generated artifact from old framework version | Regenerate from current canonical source; remove obsolete |
| `TEMPORARY` | Ephemeral scratch or tool output | Remove when no longer required |
| `SECRET_LOCAL` | Local credential/secret file | Do not migrate; preserve correct gitignored behavior |
| `UNKNOWN` | Unclear classification | Preserve; classify before cleanup |

### Cleanup Is NOT Deletion-First

```
INVENTORY -> CLASSIFY -> MIGRATE/PROMOTE -> UPDATE REFERENCES -> VALIDATE -> CLEAN
```

Never: `CLEAN -> hope useful information was not deleted`

Do not delete `UNKNOWN` artifacts automatically.
Do not delete legacy screenshots without first classifying them as HISTORICAL_EVIDENCE, DUPLICATE, or TEMPORARY.

### Canonical Structure Convergence

After successful reconciliation, an active project converges toward ONE current MxAgile structure.
Parallel active locations for Requirements, Specs, Tasks, Decisions, Discovery, Refinement, source
mockups, target mockups, parity reports, evidence manifests, screenshots are resolved.

Historical preservation is retained where required; historical paths must not remain
ambiguous active sources.

---

## Screenshot/Evidence Cleanup Behavior

Do not delete legacy screenshots merely because they exist outside the new canonical evidence structure.

Classify first:
- Useful historical evidence supporting an existing parity/Discovery/Refinement claim → `HISTORICAL_EVIDENCE`: promote/migrate with provenance to `planning/evidence/screenshots/legacy/`
- Duplicate evidence with canonical copy → `DUPLICATE`: deduplicate after proving equivalence
- Debug/transient screenshot with no durable value → `TEMPORARY`: remove if safe

If an old screenshot supports an existing parity/Discovery/Refinement claim, preserve that connection in the evidence manifest.

---

## Cleanup Safety Contract

### No Silent Data Loss

Cleanup must never silently remove unique project knowledge.

Before deleting any potentially durable artifact, prove:
- Equivalent canonical content exists, OR
- Artifact is intentionally temporary/obsolete (with explicit classification)

### Preserve Provenance

When moving knowledge from a legacy location:
- Preserve the origin path
- Preserve the identifier where applicable
- Record migration in provenance field or decision log

### Idempotency

Running project reconciliation again after successful reconciliation must NOT:
- Move files that were already moved
- Duplicate artifacts that were already migrated
- Recreate decisions already recorded
- Rewrite stable evidence that remains valid
- Reopen completed lifecycle scope

An idempotent reconciliation detects that reconciliation already occurred and confirms
current state without re-executing work.

---

## Fresh Agent Re-Sync Behavior

A fresh agent session must:

```
1. Read planning/lifecycle/process-state.yaml (canonical, Git-tracked)
   Fallback: .concord/scratch/process-state.yaml if canonical not yet created
2. Detect that prior Discovery/Refinement exists
3. Reconcile rather than restart
4. Identify only current gaps
5. Continue from correct lifecycle position
```

Deleting `.concord/scratch/` must NOT destroy canonical lifecycle knowledge. The canonical
state in `planning/lifecycle/process-state.yaml` survives a fresh clone.

The fresh agent must NOT:
- Assume no Discovery exists
- Re-run Discovery if acceptable Discovery is present
- Ask the developer to re-enter decisions already in `planning/decisions/`
- Recreate Requirements/Specs/Tasks that already exist with valid content
