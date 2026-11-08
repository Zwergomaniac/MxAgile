# Contract: Lifecycle-Klärung CS-0 (OD-3)

Quelle: [docs/board-redesign-plan.md](../../../docs/board-redesign-plan.md) Abschnitt K.4. **Kanonisch**, ändert Agentenverhalten → eigene Freigabe vor Distribution.

## Vorbedingung

`lifecycle-resync.md` und `implementation-control.md` tragen fremde uncommittete Änderungen (Re-Sync-Statusmodell, „Mission Decomposition and Wave Execution"). Sie müssen **vor** CS-0 vom Eigentümer committet sein. CS-0 setzt danach auf dem committeten Stand auf.

## Regeln → Zielorte

| Regel | Inhalt | Zieldatei(en) |
|---|---|---|
| R1 | DONE-Wave wird nicht wiedereröffnet; widerlegte DONE-Aussagen scoped per `completion_override`/Finding | `lifecycle-resync.md` (Abschnitt Zustandsvalidierung), Querverweis `legacy-completion-reconciliation.md` |
| R2 | Arbeit nach DONE → neue Wave (auch LOCAL); „GAP-Repair erzeugt keine neue Wave" gilt nur, solange die betroffene Wave nicht `done` ist; Verknüpfung Finding.wave_id (alt) → repair_task_id → Task.wave_id (neu) | `gap-verification-repair.md` § Relation to Acceptance Gate; `implementation-control.md` |
| R3 | Wave bei Autorisierung in `process-state.yaml` registrieren (`phase: discovery`, Gates `not_recorded`) | `implementation-control.md` § Mission Decomposition; `lifecycle-resync.md` (NOT_STARTED) |
| R4 | optionale Gates `testability_gate`, `acceptance_gate` (inkl. `pending`, `pending_decisions`) | `process-state.schema.json`; `lifecycle.yaml` required_gate_keys konsistent |
| R5 | Glossar: Mission, Workpackage, Acceptance Campaign, GAP, Repair Task, Change-Set; `lifecycle.yaml` state_tracking → `planning/lifecycle/process-state.yaml` | `GLOSSARY.yaml`, `lifecycle.yaml` |
| R6 | Doctor-Hinweise (nicht blockierend, kein Repair) | `project_compatibility.py` |

## Neue Doctor-Diagnosen (R6)

| Kategorie | Severity | blocking | repairability | Gruppe (ab CS-3) | Auslöser |
|---|---|---|---|---|---|
| `CHANGE_SET_SCHEMA_INVALID` | WARNING | false | DECISION_REQUIRED | projection_health | Change-Set verletzt `change-set.schema.json` |
| `DONE_BASIS_NOT_RECORDED` | INFO | false | UNSUPPORTED | framework_compat | Wave `phase: done` ohne `gates.acceptance_gate` |
| `ACTIVE_REVISION_UNBOUND` | WARNING | false | DECISION_REQUIRED | project_attention | Revision `active_target: true` ohne Page-Bindung |

Doctor-Exit-Code-Vertrag 0/1/2 unverändert; neue Diagnosen ändern `compatibility` nicht auf BLOCKED.

## Ausgeschlossen

Neue Entität; Markdown-Parsing von `execution-waves.md`; automatische Projektmigration; Board-Änderung; Repair.
