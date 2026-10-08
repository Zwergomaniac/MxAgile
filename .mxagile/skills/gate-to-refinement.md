# Gate: Discovery -> Refinement

Prueft ob die Discovery-Phase vollstaendig abgeschlossen ist bevor Refinement beginnt.

## Vorbedingungen

- [ ] Story-Spezifikation existiert unter `planning/stories/{STORYPREFIX}-*.md`
- [ ] Story-Spezifikation enthaelt Source-Fingerprint und Quellen-Referenzen
- [ ] Relevante Input-Resources identifiziert und referenziert
- [ ] **Fachliche Grundlage vorhanden:** Mindestens eine dieser Quellen muss existieren:
      (a) Requirements-Dokument unter `input-resources/requirements/`,
      (b) Eingebettete Spec im Mockup (`mocketeer-spec` JSON), oder
      (c) Explizite Entwicklerfreigabe zum Fortfahren ohne Requirements.
      Ohne fachliche Grundlage: **STOP** — Rueckfragen an den Entwickler stellen.
- [ ] UI-Inventar vorhanden unter `planning/ui-inventory/` (wenn Mockups unter `input-resources/ui-ux/` existieren)
- [ ] **Coverage-Gap-Check abgeschlossen:** Fuer jede inventarisierte Page wurde geprueft ob
  Requirements-Traceability vorhanden ist. Pages ohne Traceability sind als `COVERAGE_GAP`
  in der Story-Spec dokumentiert. (Coverage-Gaps sind kein Gate-Blocker, aber sie muessen sichtbar sein.)
- [ ] Falls generiertes Mockup: `"approved": true` im mocketeer-spec (Entwicklerfreigabe erteilt)
- [ ] Bestehendes Modell im betroffenen Modul gelesen
- [ ] Company Layer Platform-Constraints evaluiert: falls Layer installiert (.mxagile/layers/) → platform-modules.yml gelesen; falls keine Layer → NOT_APPLICABLE
- [ ] Board-Sync ist aktuell (wenn Board konfiguriert — optional, D52).
      Board-Sync ist Kontextanreicherung; ein fehlender oder veralteter Board-Sync
      blockiert das Gate NICHT. Neue Board-Stories autorisieren keinen Scope.
- [ ] **Concern-Reconciliation abgeschlossen (wenn `development.ui_driven = true`):**
      UI-Inventar und Story-Specs auf Widersprueche geprueft.
      Jeder Widerspruch nach konfigurierter `source_authority` aufgeloest oder als
      `DECISION REQUIRED` markiert.
      Kein DECISION REQUIRED aus reiner Concern-Trennung: Mockup bestimmt Layout,
      Requirements bestimmen Pflichtfeld-Logik — das ist kein Widerspruch.

## Mockup Revision Checks (WP-21)

Wenn ein Mockup (`input-resources/ui-ux/`) im Wave-Scope vorhanden ist, sind diese Checks
**zusätzliche Gate-Bedingungen** — Failure ist ein Gate-Blocker:

- [ ] **Aktives Target eindeutig:** Genau eine Revision hat `lifecycle_status: REFINED_TARGET` und
  `active_target: true`. Kein doppeltes `active_target: true` zulässig. Bei Fehlen eines
  akzeptierten Targets: WORKING_TARGET_UNACCEPTED_DEVIATION — `create_revision.py` ausführen.
- [ ] **Revision gültig:** `revision.yaml` der aktiven Revision validiert gegen
  `revision.schema.json` (kein Schema-Fehler).
- [ ] **Contract gültig:** `mocketeer-spec` JSON-Block im aktiven Target-HTML ist valides JSON
  und enthält `schema_version` sowie alle Pflichtfelder (`mockup.id`, `mockup.revision`,
  `mockup.lifecycle_status`).
- [ ] **Ledger vorhanden oder Migration dokumentiert:** `revision_history` im Contract enthält
  mindestens einen Eintrag ODER ein Migration-Dokument (`planning/migrations/`) belegt explizit,
  warum der Ledger für diesen Contract leer ist.
- [ ] **Revision Delta vorhanden:** `revision_delta` Objekt mit `from_revision` und `to_revision`
  ist im Contract vorhanden. Fehlt es bei einer Revision ≥ 2: Gate-Blocker.
- [ ] **Effects referenziell gültig:** Alle `effect_id`-Einträge (EFF-*) im `revision_delta.effects`
  referenzieren existierende Einträge in den `interaction_states` der betroffenen Page-YAMLs.
  Verwaiste EFF-*-IDs sind ein Gate-Blocker.
- [ ] **Rollen-Coverage bewertet:** `planning/role-coverage/<wave-id>-role-coverage.yaml` existiert
  ODER alle fehlenden Rollen sind als `ROLE_GAP` in der Story-Spec dokumentiert.
  Unbewertet mit fehlendem Nachweis ist ein Gate-Blocker.
- [ ] **Interaction-Coverage bewertet:** Alle `interaction_states` im UI-Inventar mit
  `status: CONFIRMED` haben mindestens einen Effect-Eintrag. Bestätigte States ohne Effects
  sind `INTERACTION_GAP` — müssen dokumentiert sein (blockierend wenn Severity CRITICAL/MATERIAL).
- [ ] **Plattformgrenzen bekannt:** `planning/platform-boundaries.yaml` existiert ODER
  `platform_boundaries: []` im Contract ist explizit und korrekt leer (keine unerkannten
  Plattformfunktionen). Fehlt die Datei ohne Begründung: Gate-Blocker.
- [ ] **Offene Entscheidungen scoped:** Alle offenen `DECISION_REQUIRED`-Items (in Story-Spec oder
  Contract) haben `affected_screens` oder `affected_requirements` gesetzt — kein unscoped
  DECISION_REQUIRED darf verbleiben. Unscoped Items blockieren das Gate.

Diese Checks werden im selben Arbeitsschritt wie die Vorbedingungen ausgeführt und unter
`waves.<Wave>.gates.gate_to_refinement_revision_checks` in `process-state.yaml` protokolliert.

## Pruefung

Fuer jede Vorbedingung: existiert das Artefakt und ist es inhaltlich plausibel?

Die UI-Inventar-Pruefung stellt sicher dass der UI-Agent (parallel zu Discovery) seine
Arbeit abgeschlossen hat. Wenn keine Mockups vorhanden sind, entfaellt diese Bedingung.

Wenn `development.ui_driven = true`: UI-Agent Analyze ist keine optionale Ergaenzung
sondern ein Pflicht-Schritt. Der Gate MUSS pruefen ob das UI-Inventar fuer alle
gefundenen Mockups erstellt wurde.

Die Pruefung auf fachliche Grundlage verhindert, dass der Agent Geschaeftsregeln,
Validierungen oder Akzeptanzkriterien antizipiert. Nur explizit dokumentierte oder
vom Entwickler bestaetigte Anforderungen duerfen in die Story-Spec uebernommen werden.

## Ergebnis

Dieser Gate hat **keinen eigenen Agenten** (siehe Orchestrator-Phasentabelle). Wer die
Discovery-Arbeit fuer eine Wave abschliesst, fuehrt diese Pruefung selbst aus und
schreibt das Ergebnis **im selben Arbeitsschritt** unter `waves.<Wave>.gates.gate_to_refinement`
in `.concord/scratch/process-state.yaml` — `not_recorded` darf danach nicht stehen bleiben.

- **Bestanden:** `gate_to_refinement: passed` eintragen, Phasenwechsel zu Refinement
- **Nicht bestanden:** `gate_to_refinement: failed` eintragen mit kurzer Begruendung,
  fehlende Artefakte dem Entwickler auflisten, in Discovery-Phase bleiben
