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
- [ ] Plattformmodule beruecksichtigt (MB_UI Layouts, MB_SSO Auth-Schema, MB_NoAccess)
- [ ] Keine offenen Blocker

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
  - id: Customer.Name
    type: entity_attribute
    req: [{STORYPREFIX}-001]
    source: ui-inventory + story-spec
    spec: "String(200), NOT NULL, Pflichtfeld"
    suggested_mendix_type: "String(200) NOT NULL"
    standard_widget: true
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

## Pruefung

Fuer jede Vorbedingung: existiert das Artefakt und enthaelt es die geforderten Inhalte?

## Ergebnis

- **Bestanden:** Checkliste unter `planning/checklists/W*-implementation-checklist.yaml` abgelegt.
  Phase wechselt zu Ready; Entwickler wird um Implementierungsfreigabe gebeten.
- **Nicht bestanden:** Offene Punkte auflisten, in Refinement-Phase bleiben.
