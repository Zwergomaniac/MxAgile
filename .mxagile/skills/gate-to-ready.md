# Gate: Refinement -> Ready

Prueft ob alle Blocker aufgeloest sind und erzeugt die Implementation-Checkliste
bevor die Implementierung freigegeben wird.

## Vorbedingungen

- [ ] Alle `DECISION REQUIRED` beantwortet oder als bewusste `ASSUMPTION` markiert
- [ ] Entscheidungen in `planning/decisions/DEC-NNN.md` dokumentiert
- [ ] Widersprueche zwischen Quellen aufgeloest (gemaess `policies/source-priority.md`)
- [ ] Akzeptanzkriterien in der Story-Spezifikation vorhanden
- [ ] Wave-Planung in `planning/execution-waves.md` aktualisiert
- [ ] Marketplace-Widgets identifiziert fuer `standard_widget: false` Items (D49)
- [ ] Company Layer Platform-Constraints beruecksichtigt: falls Layer installiert (.mxagile/layers/) → Layer-spezifische Modul- und UI-Vorgaben eingehalten; falls keine Layer → NOT_APPLICABLE
- [ ] **UI Element Selection Gate:** Fuer jede Component im UI-Inventar mit `widget_candidate` gilt:
  - `candidate_confidence` ist `assessed` oder `validated` — NICHT `preliminary`
  - `fit_rationale` ist dokumentiert wenn `candidate_confidence: assessed` oder `validated`
  - Data Grid 2-Kandidaten haben die 10-Punkte-Fit-Pruefung abgeschlossen
    (siehe `policies/ui-element-selection.md — Data Grid 2 Fit Check`)
  - `display_mode: display` Components verwenden kein Eingabe-Widget ohne explizite Begruendung
  - Company Layer Komponenten wurden als erste Option geprueft
  - `preliminary` confidence ist ein Blocker fuer gate-to-ready wenn das Inventar UI-Driven ist
- [ ] **Testability Gate:** Test Contract present for each requirement in scope OR testability explicitly justified as NOT_APPLICABLE / MANUAL_ONLY (see Testability Gate section below)
- [ ] Keine offenen Blocker
- [ ] **SPA-Bundle Revision Check (wenn `mockup_name` in Page YAML gesetzt):**
  Fuer jede Page mit `mockup_name`: Working-Target-Hash == `bundle_hash` im Page YAML?
  Wenn NEIN: WORKING_TARGET_UNACCEPTED_DEVIATION — Gate blockiert bis `create_revision.py` ausgefuehrt wurde.
  Das Gate darf diese Abweichung NICHT selbst auflösen. Nur `scripts/create_revision.py` darf Revisionen erstellen.
- [ ] **Coverage-Gap-Sichtbarkeit:** Alle Pages ohne Requirements-Traceability als `COVERAGE_GAP` in der
  Implementation-Checkliste dokumentiert (nicht blockierend, aber sichtbar als offener Punkt)
- [ ] **Wenn `development.ui_driven = true`:** Fuer jede Seite im UI-Inventar sind
      `source_mockup`, `ui_inventory` und `layout_reference` verfuegbar und werden
      als bindende Referenz-Felder in die Checkliste uebernommen

## Pflichtausgabe: implementation-checklist.yaml (D37)

Dieses Gate erzeugt die konsolidierte Checkliste aus zwei Quellen:

1. **UI-Inventar** (`planning/ui-inventory/*.yaml`) — Felder, Buttons, Navigation, Widgets
2. **Story-Spezifikation** (`planning/stories/{STORYPREFIX}-*.md`) — Geschaeftsregeln, Microflows, Validierungen

Die Checkliste ist **wave-bezogen**, nicht story-bezogen: eine Datei deckt alle Requirements
einer Wave ab, jedes Item nennt die betroffenen Requirements im Feld `req`.

### Checklisten-Format

```yaml
wave: W1
scope: {STORYPREFIX}-001, {STORYPREFIX}-002
generated_by: gate-to-ready
sources:
  ui_inventory: planning/ui-inventory/
  story_specs: [planning/stories/{STORYPREFIX}-001.md, planning/stories/{STORYPREFIX}-002.md]
  requirements: input-resources/requirements/...

items:
  - id: Customer_NewEdit
    type: page
    req: [{STORYPREFIX}-001]
    source: ui-inventory
    source_mockup: input-resources/ui-ux/customer-newedit.html
    ui_inventory: planning/ui-inventory/Customer_NewEdit.yaml
    layout_reference: .concord/screenshots/mockup/Customer_NewEdit_default.png
    fidelity: high
    status: pending

  - id: Customer.Name
    type: entity_attribute
    req: [{STORYPREFIX}-001]
    source: ui-inventory + story-spec
    spec: "String(200), NOT NULL, Pflichtfeld"
    suggested_mendix_type: "String(200) NOT NULL"
    standard_widget: true
    status: pending

  - id: COMP-CUSTOMER-LIST
    type: page_component
    req: [{STORYPREFIX}-001]
    source: ui-inventory
    ui_pattern: responsive_record_list
    display_mode: display
    widget_candidate: ListView
    candidate_confidence: assessed
    fit_rationale: "Mockup shows card-like rows without column headers; responsive mobile layout required; no sorting/filtering requirements; List View with custom content satisfies all visual and responsive contract requirements."
    status: pending
    test:
      steps:
        - open: Customer_NewEdit
        - fill: { Name: "" }
        - click: Speichern
      expected: "Validation: 'Name is required'"

  - id: ACT_CalculateTotal
    type: microflow
    req: [{STORYPREFIX}-002]
    source: story-spec
    spec: "Berechnet Gesamtbetrag"
    status: pending
    test:
      steps:
        - open: Order_NewEdit
        - fill: { Quantity: "3", UnitPrice: "10.00" }
        - click: Berechnen
      expected: "Total = 30.00"
    inspect:
      microflow: OrderModule.ACT_CalculateTotal
      expect: "RETRIEVE OrderLine, Aggregation SUM, SET Total"
```

### Regeln fuer die Checkliste

- Jedes fachliche Artefakt wird ein Item (Entity, Attribut, Association, Microflow, Page, Widget, Security-Rule)
- `req:` nennt die Requirements, die das Item abdeckt — Grundlage der Traceability
- `test:` Block ist Pflicht fuer jedes Item das testbar ist
- `inspect:` Block ist optional — fuer Berechnungen/Bedingungen empfohlen, fuer komplexe Workflows Pflicht (D51)
- Items aus dem UI-Inventar bekommen `suggested_mendix_type` und `standard_widget` uebernommen
- Items aus der Story-Spec die nicht im UI-Inventar vorkommen (z.B. reine Backend-Logik) werden separat aufgefuehrt
- Security-Items am Ende: Entity Access Rules pro Entity, dann gesammelter Security-Pass (D48)
- **Wenn `development.ui_driven = true`:** Page-Items (type: page) bekommen zusaetzliche Pflichtfelder:
  - `source_mockup` — Pfad zum HTML-Mockup (aus `source_mockup` im Page YAML)
  - `ui_inventory` — Pfad zum YAML-Inventar dieser Seite
  - `layout_reference` — Pfad zum Referenz-Screenshot (aus `layout_reference` im Page YAML)
  - `fidelity` — Fidelity-Anforderung aus `mxagile-project.yaml` (`standard` oder `high`)
  - Diese Felder machen Mockup-Treue zur **Implementierungspflicht** — nicht zu optionalem Kontext

## Testability Gate (WP2 Extension)

This gate checks that every requirement in scope has a derivable or existing Test Contract.

### Preconditions

- [ ] **Test Contract present:** For each REQ-NNN in the wave scope, one of the following is true:
  - `planning/test-contracts/TC-NNN.yaml` exists with `status: draft` or `active`
  - OR: The checklist item for this requirement has `testability: NOT_APPLICABLE`
    with an explicit `testability_justification` field (e.g. "Pure UI layout, no business rule to automate")
  - OR: The checklist item has `testability: MANUAL_ONLY` with `testability_justification`
    (e.g. "Requires physical device — no Playwright support for this scenario")
  - Undocumented absence is a GATE BLOCKER.

- [ ] **No STALE test contracts in scope:** All TC-NNN in scope must have `status: draft` or `active`.
  A `stale` contract must be updated before gate-to-ready passes.

- [ ] **Verification Plan is NOT required here:** VPL is produced at Verifying phase entry, after
  implementation, when infrastructure availability and model state are known. Do not block gate-to-ready
  on VPL existence. A checklist item may record a preliminary `expected_layers:` hint for planning,
  but this is not the authoritative Verification Plan.

### Testability Fields in Checklist Items

Extend the implementation checklist format with optional testability fields:

```yaml
  - id: COMP-SITE-CREATE
    type: page_component
    req: [REQ-001]
    ...
    test_contract: TC-001
    testability: TESTABLE_AUTO | TESTABLE_MANUAL | NOT_APPLICABLE | INFRASTRUCTURE_GAP | MANUAL_ONLY
    testability_justification: ""  # Required when NOT_APPLICABLE or MANUAL_ONLY
```

### Result Recording

Write to `.concord/scratch/process-state.yaml` under the wave's gate:

```yaml
waves.W01.gates.testability_gate: passed | failed
waves.W01.gates.testability_gate_note: ""
```

A failed Testability Gate blocks gate-to-ready. Record which requirements lack test contracts.

## Pruefung

Fuer jede Vorbedingung: existiert das Artefakt und enthaelt es die geforderten Inhalte?

## Ergebnis

Dieser Gate hat **keinen eigenen Agenten** (siehe Orchestrator-Phasentabelle). Wer die
Refinement-Arbeit fuer eine Wave abschliesst, fuehrt diese Pruefung selbst aus und
schreibt das Ergebnis **im selben Arbeitsschritt** unter `waves.<Wave>.gates.gate_to_ready`
in `.concord/scratch/process-state.yaml` — `not_recorded` darf danach nicht stehen bleiben.

- **Bestanden:** `gate_to_ready: passed` eintragen, Checkliste unter
  `planning/checklists/W*-implementation-checklist.yaml` abgelegt. Phase wechselt zu
  Ready; Entwickler wird um Implementierungsfreigabe gebeten.
- **Nicht bestanden:** `gate_to_ready: failed` eintragen mit kurzer Begruendung,
  offene Punkte auflisten, in Refinement-Phase bleiben.
