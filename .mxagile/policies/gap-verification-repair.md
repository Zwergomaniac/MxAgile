# GAP Verification & Repair

Policy for classifying, verifying, and repairing deviations between the active target mockup
(the fachliches Soll) and the actual Mendix implementation.

A GAP is a verified deviation from the confirmed design contract.
A GAP is NOT a new requirement. A GAP is NOT grounds for changing the fachliches Soll.

## Central Distinction

| Situation | Process |
|---|---|
| Mendix implementation deviates from confirmed target mockup | GAP Verification & Repair |
| Stakeholder requests a change to the fachliches Soll | Mockup Refinement → new REV-NNN + DEC-NNN |
| Agent proposes relaxing the target to match the implementation | FORBIDDEN without explicit developer + stakeholder acceptance |

An agent MUST NOT reclassify an implementation shortfall as a new requirement.
An agent MUST NOT silently adopt the implementation as the new target.
An agent MUST present the gap clearly and wait for a human DECISION.

## GAP Classification

Every identified deviation must be classified before repair is authorised:

| GAP Type | Description | Example |
|---|---|---|
| `VISUAL_GAP` | Visual deviation that does not affect semantics or function | Wrong spacing, wrong colour shade |
| `CONTENT_GAP` | Label, heading, or text differs from target mockup | Button says "Sichern" instead of "Speichern" |
| `INTERACTION_GAP` | An interaction defined in the target is missing or broken | Expand/collapse on Abteilungsbereiche missing |
| `STRUCTURE_GAP` | Section, component, or navigation element missing or wrong | Two-column layout implemented as one-column |
| `ROLE_GAP` | A role has incorrect access, missing controls, or is unrepresentable | E4 cannot be tested because role is absent |
| `STATE_GAP` | An interaction state is not reachable or renders incorrectly | Empty state not shown, loading spinner missing |
| `SCOPE_GAP` | A screen is present in the implementation but not in the target | Platform module page (e.g. a company authentication module) appears as app page |
| `PLATFORM_BOUNDARY_GAP` | Platform boundary incorrectly represented in the application UI | Login page treated as app page instead of platform module boundary |

## GAP Severity

| Severity | Definition |
|---|---|
| `CRITICAL` | Functionality or role access is blocked; acceptance gate cannot pass |
| `MATERIAL` | Clear deviation that must be repaired before acceptance |
| `COSMETIC` | Minor visual difference within project's visual tolerance; may be deferred |

## GAP Lifecycle

```
DETECTED → CLASSIFIED → REPAIR_PROPOSED → REPAIR_ACCEPTED → REPAIRED → VERIFIED
                                        ↘ REPAIR_REJECTED → DECISION_REQUIRED
```

1. **DETECTED** — GAP identified during parity verification or acceptance campaign.
2. **CLASSIFIED** — GAP type and severity assigned. Required before any repair action.
3. **REPAIR_PROPOSED** — Agent proposes a repair (code or config change).
   - For CRITICAL and MATERIAL gaps: developer must confirm before repair is applied.
   - For COSMETIC gaps: agent may apply with developer awareness (not unilaterally).
4. **REPAIR_ACCEPTED** — Developer confirms the repair is correct and aligned with the target.
5. **REPAIRED** — Repair applied in the Mendix model.
6. **VERIFIED** — Parity verification re-run against active target; result: PASS.

If a repair reveals that the correct implementation requires changing the fachliches Soll:
→ Stop the repair workflow.
→ Raise a DECISION_REQUIRED with the specific conflict.
→ Route to Mockup Refinement.
→ Repair only after a new REV-NNN is accepted.

## External Change Reconciliation

`planning/findings/FIND-*.yml` validated by `.mxagile/schemas/finding.schema.json`
is the canonical Finding authority. `FINDINGS.md` is human-readable campaign or
historical narrative only; it is not parsed as lifecycle state and is never the
only source for Project Status.

The existing GAP lifecycle remains authoritative. `VERIFIED` is the resolved
state and requires completed verification. `SUPERSEDED` requires `superseded_by`
to identify the replacing Finding. `RETIRED` requires a durable reason, including
when a Finding is no longer applicable. Do not invent a parallel ACTIVE/RESOLVED
state machine.

External-change reports compare changed paths with canonical Finding
`source_artifacts` and explicit related artifact IDs. An unrelated delta leaves
the Finding unchanged. A match produces the read-only projection
`REASSESS_REQUIRED`; it does not change `lifecycle_status` or mark a Finding
resolved. Persist an assessment only in the canonical Finding's `reconciliation`
record, bound to the exact affected-path/blob fingerprint and evidence or
decision references. The Watermark gate remains blocked until every affected
active or terminal Finding has a current assessment.

`FRAMEWORK_FOLLOWUP` is an origin classification, not a lifecycle state. A Core
update alone never resolves it. Resolution requires the framework change, a
current Doctor result, reality/verification evidence, and a canonical Finding
update to `VERIFIED` with framework/resolution commit and evidence references.

## Finding Projection and Compaction

Project Status keeps non-terminal Findings in the active `items` projection and
emits `VERIFIED`, `SUPERSEDED`, and `RETIRED` records as compact `history`
references. The history preserves ID, terminal state, category, severity, wave /
workpackage, Requirement / Decision IDs, source and Evidence references, terminal
resolution or supersession reference, commits when known, and canonical path.
Board history is collapsed by default; no Markdown is scraped in the browser.

Phase 2 does not move, delete, or bulk-migrate Finding files. A later explicit
compaction may move only schema-valid terminal records into
`planning/findings/archive/`; it must retain the fields above, preserve each
original Finding ID, and leave an active projection/reference. `FINDINGS.md` and
unstructured historical reports remain intact unless a separately approved
migration establishes their authority and mappings.

Reconcile Findings at mission/campaign completion, after Framework update plus
Doctor, after external-change review, before a major Wave/Mission, or during an
explicit compaction. Do not run a Finding migration or reconciliation after
every agent turn. New sessions load active structured Findings and only relevant
terminal references, not the complete historical `FINDINGS.md`.

## Canonical GAP Record

`planning/findings/FIND-*.yml` is the canonical durable GAP record per
`.mxagile/schemas/finding.schema.json`. A parity report is evidence, not a second lifecycle
store. Before a later implementation, consume the Finding's persisted `authority_disposition`
through the current Project Status projection; a `CLASSIFIED` lifecycle status alone does not
authorize an app change. See `policies/parity-finding-reconciliation.md` for currentness and
the action boundary.

## Platform Boundary GAPs

When a GAP involves a screen that should NOT be in the application UI (platform boundary):

1. Classify as `PLATFORM_BOUNDARY_GAP`.
2. Do NOT create a repair task to implement the screen.
3. Create a DEC-NNN with `decision_type: platform_boundary` confirming the boundary.
4. Remove or redirect the screen per the platform module contract.

**Example:** If a Mendix application has an app-level login page instead of delegating to the platform SSO provider, this is a `PLATFORM_BOUNDARY_GAP`. The repair is to remove the app-level login page and configure the SSO provider — not to align the app-level login with the mockup.

## Role Coverage GAPs

When a fachliche role defined in the Design Contract or role model cannot be represented or tested:

1. Classify as `ROLE_GAP`.
2. Record the missing role and its required scope context (e.g. organisational unit, department, or team scope required to represent the role in testing).
3. A missing scoped test identity is a ROLE_GAP, not an infrastructure gap.
4. Role Coverage GAPs block the ROLE campaign gate.

## Agent Authority Limits for GAP Repair

The classification and allowed action for later implementation are not reconstructed from this
workflow. Consume the current `authority_disposition` from the canonical Finding through Project
Status; act only when `status: RESOLVED` and `consumable: true`. Classification-to-action mapping,
fingerprint currentness, and `REFERENCE_GAP` / `AUTHORITY_CONFLICT` prohibitions are owned by
`policies/parity-finding-reconciliation.md`, the Finding schema, and its resolver projection.

| Action | Agent Authority |
|---|---|
| Apply a COSMETIC repair | With developer awareness |
| Apply a MATERIAL or CRITICAL repair | Requires developer REPAIR_ACCEPTED |
| Change the fachliches Soll (target mockup) | FORBIDDEN without full Mockup Refinement + DEC-NNN |
| Invent a new requirement to explain a GAP | FORBIDDEN |
| Promote the implementation as the new target | FORBIDDEN |

## Repair Report

After completing a repair cycle, produce a GAP Repair Report:

```yaml
repair_cycle_id: REPAIR-W01-2026-10
wave_id: W01
page_id: PAGE-GESAMTUEBERSICHT
gaps_detected: 3
gaps_repaired: 2
gaps_deferred: 1
gaps_escalated: 0
decision_required_items: []
verified_at: "2026-10-06"
target_revision_used: REV-002
overall_result: PARTIAL
notes: "Cosmetic gap GAP-003 deferred per PO request. All MATERIAL gaps repaired and verified."
```

## Complete GAP Verification & Repair Workflow (14 Steps)

### Step 1 — Baseline bestimmen

- Aktives Target Mockup und Revision aus `planning/ui-inventory/<PageName>.yaml` lesen.
- `target_revision` und `bundle_hash` verifizieren.
- Design Contract laden (`mocketeer-spec` aus aktivem Target-HTML).
- Alle relevanten Requirements, Decisions, Interaction States, Roles, Platform Boundaries laden.

### Step 2 — GAP-Typ und Authority-Disposition

`gap_type` und `severity` beschreiben die Abweichung. Die separate, persistierte
`authority_disposition.classification` steuert den Folgeweg. Verwende ausschließlich die
Klassifikation und Aktion aus `policies/parity-finding-reconciliation.md`; keine zweite
Feedback-Klassifikation aus Report-Prosa ableiten. Ohne aktuelle, konsumierbare Disposition
keine Modell-/App-Änderung beginnen.

### Step 3 — Soll und Ist dokumentieren

- `expected`: aus aktivem Target Mockup, Requirement AC, oder Design Contract ableiten.
- `actual`: aus Mendix-Modell, Runtime, oder Browser belegen.
- KEINE Sollwerte aus Annahmen erfinden.

### Step 4 — Repair-Task-Entscheidung

**Task erforderlich, wenn mindestens eines gilt:**
- Mendix-Modell-, UI- oder Interaktionsänderung notwendig
- Navigation betroffen
- Rollen- oder Security-Mapping betroffen
- Mehrere zusammenhängende GAPs
- Regression muss dokumentiert werden
- Browser-Verifikation erforderlich
- Evidenz oder Audit-Trail erforderlich

**Keine neue Task wenn:**
- Kein Code oder Modell geändert wird
- Bestehende Task den Scope vollständig enthält
- Nur Analyse ohne Reparatur
- Reine Dokumentationskorrektur in offenem Artefakt

Empfohlener Task-Name: `repair-from-user-feedback-YYYY-MM-DD`

### Step 5 — Impact bestimmen

Per `scripts/resolve_impact.py` oder manuellem Trace:
- Betroffene Requirements, Decisions, Screens, Interactions, Roles, Mendix-Artefakte, Tests, Regressionen

### Step 6 — Reparatur planen

- Technische Aktion beschreiben.
- Plattformgrenzen berücksichtigen (keine Plattformmodule verändern).
- Company Layer prüfen (vorhandene Module nicht duplizieren).
- Keine fachliche Änderung durchführen.

### Step 7 — Reparatur ausführen

- Relevante Mendix-Artefakte ändern.
- Vorhandene Implementation-Control-Regeln nutzen.
- Checkliste aktualisieren.
- Fehler dokumentieren.

### Step 8 — Technische Prüfung

Mindestens: Syntax/Schema, mxcli Check, Mendix Consistency, Security- und Rollen-Mapping, referenzielle Integrität.

### Step 9 — Runtime-Verifikation (wenn runtime-relevant)

- Anwendung starten, repräsentative Daten bereitstellen.
- Betroffene Rollen testen, Zustand reproduzieren, Repair prüfen.

### Step 10 — UI-Parity gegen aktives Target

- Aktives Target verwenden (REFINED_TARGET, active_target: true).
- Relevanten Viewport und Rollenmodus verwenden.
- Interaction State prüfen.
- Screenshot oder strukturierte Browser-Evidenz erzeugen.

### Step 11 — Acceptance

- Betroffene Journeys prüfen.
- Expected Outcome prüfen.
- Modell- und Browser-Resultat dokumentieren.

### Step 12 — Regression

Mindestens: direkt betroffene Journeys, kritische Nachbarfunktion, relevante Rolle, wichtige Preservation-Journey.

### Step 13 — Konsistenzprüfung

Vergleiche: Task, Requirement, Decision, Spec, UI-Inventar, Parity Report, Acceptance Report, aktive Target-Revision auf Konsistenz.

### Step 14 — Abschluss

**Nur wenn alles erfolgreich:**
- Task auf `done`, Evidenz verlinken, GAP als `VERIFIED_REPAIRED` markieren.

**Bei Fehler:**
- Task auf `failed` oder `blocked`, Failure Reason, Expected vs. Actual, konkrete nächste Aktion.

**Eine Repair Task darf erst `done` werden, wenn ALLE für den Scope relevanten Verifikationsschritte (Steps 8–13) erfüllt sind. Eine reine Codeänderung ohne Nachverifikation ist nicht abgeschlossen.**

### Parent Parity Workstream Re-Sync

`VERIFIED` closes the repaired Finding, not the active parent parity workstream. After current
runtime/visual evidence for a repaired GAP, perform a targeted delta re-check against the active
target for that same parent scope before leaving the workstream. Reuse the current parity
contract and inspect only the affected scope plus its referenced findings; do not rescan all
pages, roles, or project verification.

Classify each remaining in-scope delta using the existing canonical authority disposition:
`CLOSED` (no actionable difference), `REFERENCE_GAP`, `AUTHORITY_CONFLICT`, an actionable
implementation/verification gap, or `UNKNOWN`/`NOT_VERIFIED`. Any actionable, UNKNOWN, or
NOT_VERIFIED delta keeps the parent active. If only CLOSED, REFERENCE_GAP, and AUTHORITY_CONFLICT remain, the parity workstream may be terminal as
`NO_AUTHORIZED_ACTIONABLE_GAP`; preserve unresolved reference/authority findings and their
prohibitions. `AUTHORITY_CONFLICT` is never resolved by this re-check. This terminal workstream
status is not a parity PASS or acceptance result. On interruption, resume by reading the
canonical parent scope and child Findings again; never infer parent completion from the most
recent child result or conversation history.

## Relation to Acceptance Gate

While the affected wave is not `done`, a GAP repair does NOT generate a new wave. It is part of
that wave's verification cycle.

After the affected wave is `done`, it is never reopened for remediation: the repair Task belongs
to a new wave (`Significance: LOCAL` is sufficient). Provenance stays in the existing records
instead of rewritten history: `Finding.wave_id` names the affected (original) wave,
`Finding.repair_task_id` names the repair Task, and `Task.wave_id` names the executing (new) wave.
If new evidence contradicts a single DONE claim, record only that scoped override
(`policies/legacy-completion-reconciliation.md`); do not reopen the wave or alter its lifecycle state.

The acceptance gate may pass when:
- All CRITICAL and MATERIAL GAPs are in state VERIFIED.
- All ROLE_GAP items affecting the active role campaign scope are resolved.
- COSMETIC GAPs are either VERIFIED or explicitly DEFERRED with a DEC-NNN.
- No unresolved DECISION_REQUIRED items remain.

## Reverse Parity GAPs

Standard GAP verification compares: **target → application** (is the target correctly implemented?).

Reverse parity GAPs arise from comparing: **application → target** (does everything in the
application belong to the current accepted design?).

### Reverse Parity GAP Types

| GAP Type | Description | Example |
|---|---|---|
| `REVERSE_SCOPE_GAP` | Application contains a page, section, or navigation item not present in the current accepted design | A legacy admin page remains after the design was simplified |
| `REVERSE_CONTENT_GAP` | Application displays text, labels, or menu items not in the current design | Old navigation group name persists alongside new structure |
| `REVERSE_INTERACTION_GAP` | Application provides an interaction (button, link, control) not in the current design | A deprecated export button remains functional |
| `REVERSE_ROLE_GAP` | Application grants a role access or visibility not specified in the current design | A removed role still has navigation access |

### Reverse Parity Reconciliation Protocol

When a reverse parity GAP is detected:

1. **Do NOT auto-delete or auto-hide** the element. Removal without reconciliation
   risks destroying intentionally retained functionality.

2. **Classify the element** against authoritative scope:
   - Is it part of a superseded design that was explicitly replaced? → Check `planning/decisions/`
   - Is it part of deferred scope retained for a later wave? → Check `planning/execution-waves.md`
   - Is it a platform boundary element? → Classify per PLATFORM_BOUNDARY_GAP above
   - Is it completely unknown? → `ORPHANED_IMPLEMENTATION` → DECISION_REQUIRED

3. **Apply existing finding reconciliation** per `policies/parity-finding-reconciliation.md`:
   - Resolve requirement ID authority for the element
   - Classify as CONFIRMED_REQUIREMENT_VIOLATION (element should not exist per current scope),
     CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK (authority unclear), or
     INFORMATIONAL_COVERAGE_GAP (deferred/future scope)

4. **Record the finding** in the parity report with `direction: reverse`.

5. **Remediation follows standard eligibility** — only CONFIRMED_REQUIREMENT_VIOLATION
   findings (where the current design explicitly excludes the element) are eligible for
   autonomous remediation. Ambiguous cases require DECISION_REQUIRED.

### Reverse Parity Economy

Reverse parity detection does NOT require a full application-surface audit on every
verification run. The efficient approach:

- **During forward parity:** When an agent encounters an application element not present
  in the UI inventory or target, it records a reverse parity observation. This is
  opportunistic, not exhaustive.
- **During full reconciliation:** Reverse parity is evaluated as part of full scope
  accounting (per `policies/ui-parity.md` § Full Reconciliation).
- **At Project/Release Checkpoint:** Reverse parity audit of the application navigation
  and page inventory against the accepted design.

---

## Interaction GAPs and Effects

When an `INTERACTION_GAP` is found, reference the specific `effects` entries from the UI inventory:
- The expected effect is the `EFF-*` entry in the `interaction_states` of the affected page.
- The repair must restore the specific `effect_type` (e.g. `expand`, `collapse`, `modal_open`).
- After repair, re-trigger the state and verify the effect is observable in the browser.
