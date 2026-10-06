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
| `SCOPE_GAP` | A screen is present in the implementation but not in the target | Platform module page (MB_SSO) appears as app page |
| `PLATFORM_BOUNDARY_GAP` | Platform boundary incorrectly represented in the application UI | Login page treated as app page instead of MB_SSO boundary |

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

## GAP Record Format

Each identified GAP is recorded as an entry in the parity report or a standalone GAP record:

```yaml
gap_id: GAP-CAPTRACK-ABTEILUNG-EXPAND
gap_type: INTERACTION_GAP
severity: MATERIAL
page_id: PAGE-GESAMTUEBERSICHT
description: "Ausklappbare Abteilungsbereiche reagieren nicht auf Klick — Expand-Effekt fehlt."
target_state_ref: "STATE-ABTEILUNG-EXPANDED"
target_effect_ref: "EFF-ABTEILUNG-EXPAND"
implementation_actual: "Abteilungsbereiche are rendered as static sections without expand control."
lifecycle_status: REPAIR_PROPOSED
repair_description: "Add expand/collapse toggle to Abteilung section header."
decision_required: false
decision_ref: null
```

## Platform Boundary GAPs

When a GAP involves a screen that should NOT be in the application UI (platform boundary):

1. Classify as `PLATFORM_BOUNDARY_GAP`.
2. Do NOT create a repair task to implement the screen.
3. Create a DEC-NNN with `decision_type: platform_boundary` confirming the boundary.
4. Remove or redirect the screen per the platform module contract.

**CapTrack example:** If the CapTrack Mendix application has an app-level login page instead of delegating to MB_SSO, this is a `PLATFORM_BOUNDARY_GAP`. The repair is to remove the app-level login page and configure MB_SSO — not to align the app-level login with the mockup.

## Role Coverage GAPs

When a fachliche role defined in the Design Contract or role model cannot be represented or tested:

1. Classify as `ROLE_GAP`.
2. Record the missing role and its required scope context:
   - Scoped roles (E2, CeKo): require a representative Center context.
   - E3 roles: require an Abteilungs context.
   - E4 roles: require a Team context.
3. A missing E4 test identity is a ROLE_GAP, not an infrastructure gap.
4. Role Coverage GAPs block the ROLE campaign gate.

## Agent Authority Limits for GAP Repair

| Action | Agent Authority |
|---|---|
| Detect and classify a GAP | Autonomous |
| Record a GAP in the parity report | Autonomous |
| Propose a repair | Autonomous (REPAIR_PROPOSED) |
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

### Step 2 — Feedback klassifizieren

Jedes Feedback einer primären Klassifikation zuordnen (Sekundärklassifikationen zulässig):

| Klassifikation | Bedeutung |
|---|---|
| `IMPLEMENTATION_GAP` | Bestätigtes Verhalten bekannt, Mendix-Implementierung verhält sich anders |
| `UI_PARITY_GAP` | Layout, Komponente, Sichtbarkeit oder Struktur weicht vom aktiven Target ab |
| `INTERACTION_GAP` | Trigger, Zustand, Feedback, Expand/Collapse, Modal, Fokus oder Tastatur weicht ab |
| `ROLE_COVERAGE_GAP` | Bestätigte Rolle nicht testbar oder nicht korrekt umgesetzt |
| `PLATFORM_BOUNDARY_VIOLATION` | Plattformfunktion fälschlich als App-Funktion implementiert |
| `REQUIREMENT_CHANGE` | Stakeholder ändert das fachliche Soll → in Refinement, nicht Repair |
| `DECISION_REQUIRED` | Soll unklar oder widersprüchlich → betroffenen Scope blockieren |
| `NOT_REPRODUCIBLE` | Zustand mit dokumentierter Umgebung und Rolle nicht reproduzierbar |

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

## Relation to Acceptance Gate

A GAP repair does NOT generate a new wave. It is part of the current wave's verification cycle.

The acceptance gate may pass when:
- All CRITICAL and MATERIAL GAPs are in state VERIFIED.
- All ROLE_GAP items affecting the active role campaign scope are resolved.
- COSMETIC GAPs are either VERIFIED or explicitly DEFERRED with a DEC-NNN.
- No unresolved DECISION_REQUIRED items remain.

## Interaction GAPs and Effects

When an `INTERACTION_GAP` is found, reference the specific `effects` entries from the UI inventory:
- The expected effect is the `EFF-*` entry in the `interaction_states` of the affected page.
- The repair must restore the specific `effect_type` (e.g. `expand`, `collapse`, `modal_open`).
- After repair, re-trigger the state and verify the effect is observable in the browser.
