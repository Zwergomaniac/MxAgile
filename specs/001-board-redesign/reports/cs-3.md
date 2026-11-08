# CS-3 Report - Beobachtungszustaende und Trennung Attention / Health / Diagnostik

Commit: `64e8c65` (Autor/Committer Zwergomaniac). 12 Dateien, +696/-47. Voraussetzungen: CS-0 `6094ab3`, BRD-F-48 `9e7ac33`.

## Umgesetzt
- Status `schema_version: 3` (additiv): `observation_state` je Bereich (12-Werte-Vokabular), Root `health`, `diagnostics[].diagnostic_group`; v2-`availability` bleibt.
- Doctor: `diagnostic_group`; `DONE_BASIS_NOT_RECORDED`, `CHANGE_SET_SCHEMA_INVALID`, `EXPECTATION_MISSING` -> framework_compat; `ACTIVE_REVISION_UNBOUND` -> project_attention.
- BRD-F-45 an der Quelle: `proposed_repair_type`-Enum um alle vom Doctor emittierten Werte (TASK_INSPECT_TYPED_TARGET_V1 + 8 Projektionsregeln); Kategorie `EXPECTATION_MISSING` (BRD-F-51).
- `GET /api/health`; Board: Health-Chip, Health-&-Diagnostics-Ansicht, Gruppen, Kontextblock nur Overview/Health, Modellfrische nur in Health.
- Smoke Route-Liste v2 (+ `health`), Chip-Konsistenzpruefung.

## Abweichungen von der Spezifikation
- Tests in `tests/test_project_status.py` statt neuer `tests/test_board_states.py` (T073-T075): eine neue Datei waere unmapped und haette das Full Release Gate erzwungen; Tests liegen als Klasse `ObservationStateTests`.
- `partial` (einzelne ungueltige Artefakte) bleibt `AVAILABLE` mit unveraendertem `availability: partial` + Diagnosen; kein eigener Zustand im Vokabular.
- Blockierende Diagnosen bleiben in ihrer Kategorie-Gruppe (Tabelle Datenmodell 2), werden aber ueber `health.blocking_diagnostics`, Chip und Attention-Chip immer sichtbar gemacht.
- `EXPECTATION_MISSING` -> framework_compat ist eine Entscheidung dieses Changesets (nicht im Datenmodell), PO-Pruefung empfohlen.

## Validierung
Fast Gate PASS (1,05 s); Impact Regression Tier 2 PASS (516 s, 9 Suites); nach UI-Fixes gezielt wiederholt: test_board_smoke, test_parity_gallery, ObservationStateTests, test_board_http = 70/70 PASS. Full Release Gate nicht erforderlich (keine unmapped Pfade, keine zentralen Installer-/Runner-Aenderungen). CapTrack read-only: 38 -> 0 Schema-Verletzungen, Fingerprint gleich, CapTrack unveraendert.

## CapTrack vorher/nachher
Vorher: v2, 213 Diagnosen (5 blockierend), 38 Schema-Verletzungen, eine Compatibility-Karte. Nachher: v3, 213 Diagnosen: project_attention 0, projection_health 9 (5 blockierend), framework_compat 57, optional_metadata 147; 0 Schema-Verletzungen. Beobachtungszustaende: mission/findings/context/runtime/active_targets/lifecycle NOT_RECORDED; verification.evidence EMPTY; capabilities/sources/operating_mode/model_freshness NOT_OBSERVABLE.

## Status
STOP CS-3. CS-4 nicht gestartet; Freigabe durch PO ausstehend.
