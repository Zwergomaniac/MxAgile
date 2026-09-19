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
- [ ] Falls generiertes Mockup: `"approved": true` im mocketeer-spec (Entwicklerfreigabe erteilt)
- [ ] Bestehendes Modell im betroffenen Modul gelesen
- [ ] Plattformmodule geprueft (`.dfc-ai/modules/platform-modules.md`)
- [ ] Board-Sync ist aktuell (wenn Board konfiguriert — optional, D52)

## Pruefung

Fuer jede Vorbedingung: existiert das Artefakt und ist es inhaltlich plausibel?

Die UI-Inventar-Pruefung stellt sicher dass der UI-Agent (parallel zu Discovery) seine
Arbeit abgeschlossen hat. Wenn keine Mockups vorhanden sind, entfaellt diese Bedingung.

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
