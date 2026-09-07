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
2. **Story-Spezifikation** (`planning/stories/CAP-*.md`) — Geschaeftsregeln, Microflows, Validierungen

### Checklisten-Format

```yaml
story: CAP-123
generated_by: gate-to-ready
sources:
  ui_inventory: planning/ui-inventory/
  story_spec: planning/stories/CAP-123.md
  requirements: input-resources/requirements/...

items:
  - id: Customer.Name
    type: entity_attribute
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
- `test:` Block ist Pflicht fuer jedes Item das testbar ist
- `inspect:` Block ist optional — fuer Berechnungen/Bedingungen empfohlen, fuer komplexe Workflows Pflicht (D51)
- Items aus dem UI-Inventar bekommen `suggested_mendix_type` und `standard_widget` uebernommen
- Items aus der Story-Spec die nicht im UI-Inventar vorkommen (z.B. reine Backend-Logik) werden separat aufgefuehrt
- Security-Items am Ende: Entity Access Rules pro Entity, dann gesammelter Security-Pass (D48)

## Pruefung

Fuer jede Vorbedingung: existiert das Artefakt und enthaelt es die geforderten Inhalte?

## Ergebnis

- **Bestanden:** `implementation-checklist.yaml` unter `planning/stories/CAP-*/` abgelegt.
  Phase wechselt zu Ready; Entwickler wird um Implementierungsfreigabe gebeten.
- **Nicht bestanden:** Offene Punkte auflisten, in Refinement-Phase bleiben.
