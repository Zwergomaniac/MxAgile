# UI-Inventory

Ein YAML-Feldinventar je Mockup-Screen, benannt nach der Seite oder dem Screen,
zum Beispiel `Customer_Overview.yaml`.

Erzeugt vom UI-Agent im Analyze-Modus (`.MxAgile/orchestrator.md`, Phase Discovery),
sobald unter `input-resources/ui-ux/` ein Mockup vorliegt. Der Agent analysiert das
Mockup per Playwright und listet Felder, Buttons, Navigation und Widgets auf.

## Inhalt je Eintrag

- Feldname und Mockup-Bezeichnung
- `suggested_mendix_type` — Vorschlag fuer den Mendix-Datentyp
- `standard_widget` — `true`/`false`, ob ein Standard-Widget ausreicht oder
  Marketplace-Recherche in der Refinement-Phase noetig ist (D49)

## Verwendung

Pflichtvorbedingung fuer `mxagile-gate-to-refinement` (Gate 1), wenn Mockups
vorhanden sind. Fliesst zusammen mit den Story-Spezifikationen in die
wave-bezogene Implementierungscheckliste unter `planning/checklists/` ein.


