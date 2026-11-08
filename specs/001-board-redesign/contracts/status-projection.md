# Contract: Status-Projektion — additive Änderungen je Changeset

`project-status.schema.json` hat `additionalProperties: false` auf Root-Ebene; jede Ergänzung erfolgt **im selben Commit** wie der Code (plan.md A2). Alle Änderungen sind additiv; `schema_version` bleibt 2 bis CS-3 und wird mit CS-3 auf 3 gesetzt. v2-Felder bleiben einen Release lang erhalten.

| Changeset | Schemaänderung | Konsumenten |
|---|---|---|
| CS-1 | keine (`parity_report` existiert als `source_type`) | board.js |
| CS-2 | Root: `projection_state{state, age_seconds, validated_age_seconds, reason, built_at_head, rebuilding}` (Name geändert: das Root-Feld `projection` existiert bereits als Boolean-Konstante) | board.js (Health-Alter), Smoke |
| CS-3 | `schema_version: 3`; je Bereich `observation_state`; `compatibility.diagnostics[].diagnostic_group`; Root `health{…}` | board.js, Smoke S6, Doctor-Ausgabe unverändert |
| CS-4 | Root: `current_work`, `waves_trust[]`; `requirements.items[].delivery_assessment`; `decisions.items[]` + `created_at, confirmed_at, rationale_excerpt, affected_screens, affected_mockup_revisions`; `project.active_targets.items[]` + `authority_source: revision_ledger`; `verification.parity_reports[]` (inkl. `REPORTED_UNBOUND`); Page-Implementierung `intent/fact`; `mission` + Detailfelder; `context` + `next_action` | board.js |
| CS-5 | keine im Status (eigenes Schema `project-timeline.schema.json`) | board.js |
| CS-6 | keine; Teil-Endpunkte sind Ausschnitte | board.js |

Validierung: `tests/test_board_performance.py::test_combined_server_snapshot_matches_status_schema` sowie neue Schema-Snapshot-Tests je Changeset; `tests/test-negative-schema.ps1`.
