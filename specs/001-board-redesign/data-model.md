# Data Model: MxAgile Dev Board Redesign

Alle Entitäten außer **Abschnitt 6 (CS-0)** sind **abgeleitet** (Projektion) und werden nie ins Projekt geschrieben.
Kanonische Bestandsentitäten (Mission, Wave, Task, Requirement, Finding, Decision, Revision, Page, Parity-Report,
Evidence-Manifest, Change-Set) bleiben unverändert, mit Ausnahme der additiven Gate-Felder in CS-0.

## 1. ProjectionSnapshot (CS-2) — Feldname `projection_state` (umgesetzt); zusätzlich `validated_age_seconds`, `rebuilding`

| Feld | Typ | Regel |
|---|---|---|
| `source_fingerprint` | `sha256:…` | unverändert (Inhaltshash kanonischer Quellen) |
| `projection_state.state` | `FRESH \| STALE \| BUILDING \| PROJECTION_ERROR` | STALE, wenn ausgelieferter Stand älter als die erkannte Quelländerung ist |
| `projection_state.age_seconds` | number ≥ 0 | Alter seit Aufbau |
| `projection_state.reason` | string \| null | z. B. `SOURCES_CHURNING`, `CACHE_UNAVAILABLE` |
| `projection_state.built_at_head` | git-oid \| null | HEAD beim Aufbau |

Zustandsübergänge: `BUILDING → FRESH`; `FRESH → STALE` (Quelländerung erkannt) `→ BUILDING`; `BUILDING → STALE` (3 Retries erschöpft, letzter Stand vorhanden) | `PROJECTION_ERROR` (kein letzter Stand).

## 2. ObservationState & DiagnosticGroup (CS-3)

`observation_state` ∈ { `AVAILABLE`, `EMPTY`, `NOT_RECORDED`, `NOT_LOADED`, `LOADING`, `STALE`, `INVALID`, `UNSUPPORTED`, `NOT_OBSERVABLE`, `NOT_APPLICABLE`, `AMBIGUOUS`, `PROJECTION_ERROR` } — genau einer je projiziertem Bereich (`mission`, `context`, `delivery.waves`, `delivery.tasks`, `requirements`, `decisions`, `findings`, `verification.*`, `project.active_targets`, `reconciliation`, `runtime`, `capabilities`).

Regeln: `NOT_LOADED`/`LOADING` nur transient (nie aus dem Server-Snapshot für gecachte Bereiche); `NOT_OBSERVABLE` erscheint nie in `project_attention`.

`diagnostic_group` je Diagnose ∈ { `project_attention`, `projection_health`, `framework_compat`, `optional_metadata` }:

| Kategorie (heute) | Gruppe |
|---|---|
| `AUTHORITY_CONFLICT`, `REFERENCE_AMBIGUOUS`, `DUPLICATE_ID` (blockierend) | project_attention |
| `SYNTAX_ERROR`, `SCHEMA_ERROR`, `ID_MISMATCH`, `MISSING`, `STALE`, `FRESHNESS_UNKNOWN` | projection_health |
| `LEGACY_VARIANT`, `UNSUPPORTED_VARIANT` | framework_compat |
| `UNASSIGNED` (workpackage), `WAVE_ASSIGNMENT_MISSING` ohne Blocking | optional_metadata |

## 3. CurrentWork (CS-4)

| Feld | Typ | Regel |
|---|---|---|
| `state` | `ACTIVE \| BLOCKED \| NOT_STARTED \| NONE \| CONFLICT` | Kaskade (Plan C.3) |
| `source` | `mission_state \| process_state \| none` | Herkunft |
| `mission` | `{id, objective, status, progress{…}}` \| null | nur aus mission-state |
| `wave` | `{wave_id, phase, gates}` \| null | nur registrierte Waves |
| `tasks_in_progress` | `[TASK-…]` | Tasks der Wave mit `in_progress` |
| `blockers` | `[{type, description, blast_radius, work_that_can_continue}]` | mission-state |
| `next_action` | `{description, safe_to_run, prerequisites}` \| null | context-epoch |
| `unattributed_activity` | `{observed: bool, since_commit, commit_count, observation_state}` | R-10; nie mit Wave-Bezug |
| `derived` | `true` (const) | Kennzeichnung |

Validierung: `state=CONFLICT`, wenn `mission.active_wave` nicht registriert oder `done` ist, oder zwei Quellen unterschiedliche aktive Waves nennen.

## 4. DeliveryAssessment (CS-4, OD-1)

| Feld | Typ |
|---|---|
| `requirement_id` | REQ-… |
| `rule_version` | `delivery-assessment/v1` |
| `label` | `NOT_STARTED \| IN_PROGRESS \| IMPLEMENTED \| VERIFIED \| BLOCKED` |
| `levels[]` | `{level: implementation\|verification\|freshness\|blocker, state: MET\|PARTIAL\|NOT_MET\|NOT_OBSERVABLE, evidence_refs[], reasons[]}` |
| `derived` | `true` |

Validierung: jeder Level hat ≥ 1 `evidence_ref` oder ≥ 1 `reason`; `REPORTED_UNBOUND` erfüllt Verification nie.

## 5. DoneBasis / WaveTrust (CS-4)

| Feld | Typ | Regel |
|---|---|---|
| `wave_id` | W… | |
| `done_basis.state` | `RECORDED \| NOT_RECORDED \| LEGACY` | aus `gates.acceptance_gate` (CS-0) bzw. Legacy-Klassifikation |
| `done_basis.evidence` | refs | aus Gate-Evidence |
| `open_tasks_superseded` | `[TASK-…]` | nur wenn `done_basis` RECORDED/LEGACY; sonst `open_tasks_unexplained` |
| `later_findings` | `[FIND-…]` | `Finding.wave_id == wave_id`, erstellt nach DONE |
| `changes_after_done` | `{commit_count, observation_state}` | Commits nach DONE-Übergang, die Wave-Artefakte (Tasks/Checkliste) berühren |

## 6. Kanonische Ergänzungen (nur CS-0)

`process-state.schema.json` → `definitions.wave.properties.gates.properties`:

| Feld | Typ | Pflicht |
|---|---|---|
| `testability_gate` | `gate_result` | optional |
| `acceptance_gate` | `acceptance_gate_result` = `gate_result` + `result ∈ {not_recorded, passed, failed, pending}` + optional `pending_decisions: [{id, text}]` | optional |

`gates.required` bleibt `[gate_to_refinement, gate_to_ready]`. Alte Dateien bleiben valide.

## 7. TimelineEvent (CS-5)

Siehe [contracts/timeline-event.md](contracts/timeline-event.md). Kernfelder: `event_id`, `type`, `authority_class ∈ {CANONICAL_RECORD, GIT_DERIVED, COMMIT_TRAILER, GIT_MENTION}`, `occurred_at`, `time_basis`, `title`, `entities[{type,id,derivation}]`, `commit`, `source`, `change_set_id`, `mission_id`, `lane ∈ {attributed, unattributed}`.

Regeln: `lane=unattributed`, wenn `entities` leer ist oder nur `GIT_MENTION`-Bezüge hat; nie Zuordnung über Zeitnähe.

## 8. PageHubEntry (CS-6)

| Feld | Inhalt |
|---|---|
| `page` | `page_id`, Name, Mendix-Bindung, Requirements (abgeleitet über `requirement.screens`, gekennzeichnet) |
| `implementation` | `intent` (Settings + Override), `fact` (HTML-Quelle auflösbar), `mismatch: bool` |
| `authority` | Referenzpfad, Revision, Fingerprint, Quelle (Ledger/Inventory/Bundle), Konflikte |
| `parity[]` | `{report_path, reported_result, computed_result, state: COMPUTED\|REPORTED_UNBOUND\|STALE\|NOT_VERIFIED, reasons[], verified_at}` |
| `captures` | aktueller Run (Soll/Ist), vorheriger Run, Overlay nur wenn referenziert |
| `evidence_state` | `commit`, `model`, `runtime` je mit `observation_state` (bis CX-A meist NOT_RECORDED/NOT_OBSERVABLE) |
| `links` | Referenz, Design Preview, HTML-Quelle, Inventory-Quelle, Parity-Quelle, Runtime „aus Evidenz vom …" |
| `history` | Page-bezogene Timeline-Ereignisse |

## 9. BoardSmokeResult (CS-7)

Siehe [contracts/board-smoke-result.md](contracts/board-smoke-result.md).
