# Gate: Refinement -> Ready

Prueft ob alle Blocker aufgeloest sind und erzeugt die Implementation-Checkliste
bevor die Implementierung freigegeben wird.

## Vorbedingungen

- [ ] Alle `DECISION REQUIRED` beantwortet oder als bewusste `ASSUMPTION` markiert
- [ ] Entscheidungen in `sprints/decisions.md` dokumentiert
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
- [ ] Keine offenen Blocker
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
