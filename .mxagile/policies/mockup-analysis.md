# Mockup-Analyse

Diese Regeln werden primaer vom **UI-Agent** (`agents/ui-agent.md`) ausgefuehrt.
In Discovery generiert oder analysiert der UI-Agent Mockups und erzeugt das YAML-Feldinventar.
In Verifying vergleicht er das Inventar gegen die laufende App.

## Reference Preflight and Evidence Reuse

Run this preflight for every Analyze or Verify invocation, including a direct or ad-hoc
request outside the Discovery orchestration:

1. Identify the accepted scope and the active reference for that scope. Keep source mockup
  (scope intent) distinct from active target mockup (visual/interaction verification).
2. Locate existing UI inventories, scenarios, parity evidence, and embedded Design Contract
  intake for that exact reference and revision. Reuse them only after checking their provenance.
3. For an SPA bundle, verify `target_revision` and `bundle_hash` against the active bundle using
  `scripts/artifact_hashing.py`. A mismatch is stale evidence. For a single-file mockup, verify
  the recorded source/target paths and accepted version; if freshness cannot be established,
  mark it UNASSESSED and inspect the active original rather than assuming it is current.
4. Compare the Design Contract's declared screens, interaction states, effects, and flows with
  the UI inventory and requested scope. List missing or ambiguous coverage explicitly. An
  empty or partial Contract section is not proof that the corresponding source has no content.
5. Reopen original HTML, bundle files, screenshots, or the running app whenever provenance,
  freshness, or coverage is incomplete, stale, ambiguous, or insufficient for the requested
  verification. Existing inventories guide targeted inspection; they never replace required
  visual or functional evidence.

### Bounded Context Handoff

For a bounded UI analysis or parity assignment, provide the agent a context package containing
the task and accepted scope, active source and target paths, revision, relevant inventories and
scenarios, known gaps, evidence paths, and expected result format. Do not pass complete
conversation history by default. Use inherited history only when a specific unresolved decision
or constraint cannot be represented in that package, and state why it is needed. Original
evidence must remain accessible to the agent for independent inspection.

Return a concise result with findings, uncovered or stale items, and source/evidence paths.
Do not return the full source material as a substitute for findings, and do not claim complete
coverage when any required reference or verification dimension remains unassessed.

## Verzeichnis-Konventionen

- `input-resources/ui-ux/` — aktuelle Mockups (Kunden-Artefakte oder freigegebene generierte)
- `input-resources/ui-ux/_archive/` — vorherige Versionen generierter Mockups (wird ignoriert)
- Der Analyze-Modus verarbeitet alle `*.html` Dateien im Hauptordner, NICHT in `_archive/`

## Generierte Mockups erkennen

Generierte Mockups enthalten `"source": "generated"` im eingebetteten `mocketeer-spec` JSON.
Sie haben Rang 1.5 (siehe `source-priority.md`) — unterhalb Requirements, oberhalb Mendix-Modell.
Ein generiertes Mockup ist nur gueltig wenn `"approved": true` im Spec steht.

Wenn spaeter ein Kunden-Mockup geliefert wird, ersetzt es das generierte Mockup.
Das generierte Mockup wird nach `_archive/` verschoben.

## Regeln fuer HTML-Mockups

Fuer HTML-Mockups unter `input-resources/ui-ux/`:

1. Zuerst `input-resources/README.md` lesen
2. Mockup in einem echten Browser mit Playwright ausfuehren
3. Nicht nur HTML-, CSS- oder JavaScript-Code analysieren
4. Relevante Seiten, Zustaende und Interaktionen mit Playwright untersuchen
5. Bei zustandsabhaengigen Controls alle fachlich relevanten Varianten aktiv ausloesen
   und Labels, sichtbare Felder, Eingabequelle, Validierungen und Datenwirkung vergleichen
6. Beobachtete Varianten als fachliche Regel oder `DECISION REQUIRED` dokumentieren
7. Screenshots der relevanten Zustaende erzeugen
8. UI, UX, Navigation, Validierungen und erkennbare fachliche Ablaeufe als Referenz
   fuer die Mendix-Implementierung verwenden
9. Unklare oder widerspruechliche Ablaeufe als `DECISION REQUIRED` markieren
10. Das Mockup nicht veraendern, sofern dies nicht ausdruecklich beauftragt wurde
11. **Typ klassifizieren:** Das Mockup als `static`, `executable` oder `unknown` klassifizieren
    und in der page YAML als `mockup_type` eintragen (siehe `policies/mockup-materialization.md`)
12. **Below-the-Fold:** Inhalte unterhalb des sichtbaren Viewport-Bereichs sind NICHT abwesend
    nur weil der Screenshot sie nicht zeigt. Fuer Navigation, Sidebar-Gruppen und scrollbare
    Bereiche: DOM-Queries (`innerText()`, Selektoren) verwenden die das gesamte Dokument abdecken,
    nicht nur den sichtbaren Bereich. Relevante Inhalte unterhalb des Viewports explizit erfassen.
    **NICHT SICHTBAR IM SCREENSHOT ≠ EXISTIERT NICHT.**

## Mockup-Materialisierung fuer ausfuehrbare Mockups

Wenn `mockup_type = executable`: vor der Parity-Auswertung gemaess
`policies/mockup-materialization.md` materialisieren. Quellcode-Inspektion allein reicht nicht.

## Nach der Mendix-Umsetzung

Dieselben Nutzerwege gegen die laufende App pruefen.
Der mxcli `test-app` Skill und die vorhandene Playwright-Konfiguration sind fuer
Browser-Automation und die Verifikation der laufenden Mendix-App zu verwenden.

## Szenario-Semantik-Extraktion

Die Mockup-Analyse darf NICHT bei PAGE / CONTROL / VISUAL STATE enden, wenn das
Mockup Rollen- oder Scope-Semantiken enthaelt.

**Erkennungsregel:** Szenario-Semantiken liegen vor wenn das Mockup eines der
folgenden zeigt oder impliziert:

- Rolle X sieht nur eigene Daten (scope-abhaengige Filterung)
- Verschiedene Rollen sehen unterschiedliche Teilmengen von Daten oder Navigation
- Eine Interaktion ist nur in einem bestimmten Zustand oder einer bestimmten Rolle verfuegbar
- Ein Label, Wert oder Datensatz bezieht sich erkennbar auf eine Demo-Organisation,
  ein Demo-Team oder eine Demo-Einheit (scopebezogenes Mock-Data-Beispiel)

**Was bei Szenario-Semantiken zusaetzlich zu dokumentieren ist:**

Fuer jede identifizierte Szenario-Semantik:

```yaml
scenario_semantic:
  mockup_evidence: "<was im Mockup beobachtet wurde>"
  role: "<betroffene Rolle oder ALL>"
  capability: "<attributierte Faehigkeit / Verhaltensbeschreibung>"
  scope_dependency: true|false
  fixture_precondition: "<welche Fixture-Komponente fuer Verifikation benoetigt wird>"
  positive_scenario: "<was bewiesen werden muss>"
  negative_scenario: "<was ausgeschlossen werden muss, wenn Scope-Isolation relevant>"
  verification_implication: "<Voraussetzung fuer den Verifikationsplan>"
```

**Pflicht-Weitergabe:** Erkannte Szenario-Semantiken muessen in die Story-Spec als
`scenario_semantics[]`-Liste uebernommen werden. Sie sind Eingabe fuer:
- Fixture-Anforderungen (policies/representative-fixture-contract.md)
- Testbarkeits-Gate (skills/gate-to-ready.md)
- Test-Vertrag-Ableitung (skills/test-contract.md)

**Die Mockup-Analyse erzeugt keine konkreten Fixture-Objekte.** Sie stellt fest,
dass Fixture-Voraussetzungen existieren — welche konkreten Datensaetze oder
Organisationsobjekte erstellt werden, ist Sache des Projekts.

**Scope-Semantik ohne konkretes Fixture ist dennoch wertvolle Information.** Ein
Mockup das zeigt "Rolle X sieht nur eigene Abteilung" beweist, dass scope-abhaengige
Verifikation erforderlich ist, ohne den Namen der Demo-Abteilung zu definieren.

## Interpretation

Die Interpretation des Mockups richtet sich nach den Regeln in
`input-resources/README.md`. Relevante Eingabeartefakte haben Vorrang vor
Annahmen des Agenten.
