# CS-0 Report - Lifecycle-Klarstellung (OD-3)

Commit: `6094ab3` (Autor/Committer Zwergomaniac). 9 Dateien, +508/-11.

## Aenderungen
- Policy/Lifecycle: DONE-Semantik, DONE-Wave nie wieder geoeffnet, Nacharbeit = neue Wave, Registrierung in `planning/lifecycle/process-state.yaml` bei Autorisierung (lifecycle.yaml, GLOSSARY, gap-verification-repair, implementation-control, lifecycle-resync).
- Schema: `process-state.schema.json` optional `testability_gate`, `acceptance_gate` (`acceptance_gate_result`); `gates.required` unveraendert. `project-status.schema.json`: Kategorie-Enum +3.
- Doctor: `DONE_BASIS_NOT_RECORDED` (INFO), `CHANGE_SET_SCHEMA_INVALID` (WARNING), `ACTIVE_REVISION_UNBOUND` (WARNING); read-only, kein Auto-Migrate, keine Auto-Erzeugung von Wave/Finding/Task.
- Kompatibilitaet: bestehende process-state-Dokumente bleiben gueltig; keine Migration; Fingerprint unveraendert.

## Validierung
Fast Gate PASS; Impact Tier 2 PASS (238.6 s); lifecycle-resync- und drift-prevention-Suite PASS; `LifecycleClarityTests` (14) PASS; CapTrack read-only Doctor-Vergleich: 0 neue Blocker, +6 nicht-blockierend, Fingerprint gleich, keine Laufzeitregression, CapTrack unveraendert. Full Release Gate nicht wiederholt (Impact-Regeln erfordern es nicht).

## Neue Findings
BRD-F-48 (weitere Policies inkonsistent, unmapped), BRD-F-49 (CapTrack-Realitaet), BRD-F-50 (Fremd-Edits im Arbeitsbaum). Zurueckgenommen: acceptance-campaign.md, autonomous-remediation.md (ausserhalb Vertrag).

## Offen/Einordnung
- BRD-F-45: nicht Teil des Lifecycle-Vertrags, nicht normalisiert; Empfehlung CS-3 (Diagnostik/Kompatibilitaet) oder eigener kleiner Fix.
- CS-7-Gate-Ausnahme und python-Prozess-Verschwinden bleiben separat dokumentiert/ungeklaert; BRD-F-44 deferred.
- CS-3-Annahmen bleiben gueltig.
- STOP: CS-3 nicht gestartet.

## Folge-Closure BRD-F-48 (Voraussetzung/Follow-up zu CS-0, nicht CS-3)
Commit `9e7ac33` (3 Policy-Dateien, +16/-5): acceptance-campaign (strukturiertes `acceptance_gate_result` in `planning/lifecycle/process-state.yaml`), autonomous-remediation (`pending_decisions` kanonisch), impact-resolution (Scratch-Eintrag als nicht autoritativ markiert). operating-mode unveraendert (bereits Session-Cache; Top-Level-Schema erlaubt nur `waves`).
Gate: Full Release Gate (unmapped, Tier 3) mit `MXCLI_TEST_BINARY`: Tier 0 PASS, Tier 2 PASS, Tier 1 FAIL (1): `test-context-mode-harness.ps1` (Test 12/14, `harness=unknown`) = umgebungsabhaengig (laeuft in Claude-Code-Sitzung); isolierte Wiederholung mit entfernten Agent-Umgebungsvariablen: 102 passed / 0 failed. **Kein sauberes Full-PASS**, dokumentierte Ausnahme wie CS-7.
BRD-F-45: Wert gueltig, Schema-Enum veraltet (ff78c99); Doctor emittiert zusaetzlich 8 Projektionsregelnamen, die ebenfalls im Enum fehlen. Empfehlung: in CS-3 (T078/T079) additiv beheben.
