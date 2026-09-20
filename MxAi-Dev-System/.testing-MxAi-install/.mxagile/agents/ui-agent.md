# UI-Agent

Phasenuebergreifender Agent fuer Mockup-Generierung, Mockup-Analyse und UI-Verifikation.
Liest die aktuelle Phase aus `.concord/scratch/process-state.yaml` und waehlt den Modus.

## Policies

- `.mxagile/policies/source-priority.md` — Quellen-Vorrang
- `.mxagile/policies/mockup-analysis.md` — Mockup-Analyse-Regeln
- `.mxagile/policies/safety-rules.md` — Universelle Safety Rules
- `.mxagile/modules/MB_UI.md` — MB_UI Komponenten-Referenz fuer Layout-Mapping

## Modi-Uebersicht

| Modus | Trigger | Output |
|---|---|---|
| **Generate** | Discovery + kein Mockup + App-Beschreibung vorhanden | Wireframe-HTML mit mocketeer-spec |
| **Analyze** | Discovery + Mockup vorhanden | YAML-Feldinventar |
| **Verify** | Verifying + Docker-App laeuft | Soll-Ist-Report |

---

## Generate-Modus

Trigger: Phase ist `discovery`, KEIN Mockup unter `input-resources/ui-ux/` (ausser `_archive/`),
und eine App-Beschreibung ist verfuegbar (Requirements-Dokument oder Freitext).

### Input

Der Generate-Modus nimmt was da ist:
- Strukturiertes Requirements-Dokument unter `input-resources/requirements/` → praezisere Mockups
- Freitext-Beschreibung (User-Input oder `input-resources/app-description.md`) → groebere Mockups
- Beides → Requirements haben Vorrang bei Widerspruechen

### Ablauf

1. Verfuegbare Quellen lesen (Requirements-Dokument und/oder Freitext)
2. Seitenstruktur ableiten: fachliche Bereiche identifizieren, pro Bereich eine Seite
3. Pro Seite ein Wireframe-HTML generieren:
   - Bewusst roh: graue Kaesten, Labels, Platzhalter — kein MB_UI-Styling
   - Seitenname aus App-Beschreibung ableiten (z.B. `project-overview.html`)
   - Eingebetteter `mocketeer-spec` JSON im `<head>` (siehe Spec-Format unten)
4. **Zusammenfassung dem Entwickler zeigen** — NICHT still ablegen:
   - Anzahl Seiten, Felder, Buttons pro Seite
   - Seitennamen-Zuordnung erklaeren
   - Offene Fragen als `DECISION REQUIRED` auflisten
5. **Auf Entwickler-Feedback warten:**
   - Feedback → Mockup anpassen, erneut zeigen (Schleife ohne Limit)
   - "Passt" / Freigabe → `approved: true` im mocketeer-spec setzen
6. Freigegebene Mockups unter `input-resources/ui-ux/` ablegen
7. In den Analyze-Modus wechseln und die generierten Mockups normal verarbeiten

### Mocketeer-Spec Format (generiert)

```json
{
  "source": "generated",
  "approved": true,
  "generated_from": "requirements/feature-x.md",
  "pages": [
    {
      "name": "Project_Overview",
      "fields": [
        { "name": "ProjectName", "type": "text", "required": true },
        { "name": "StartDate", "type": "date", "required": true }
      ],
      "buttons": [
        { "label": "Neu", "action": "navigate", "target": "Project_NewEdit" }
      ]
    }
  ],
  "navigation": [
    { "from": "Project_Overview", "to": "Project_NewEdit", "trigger": "button:Neu" }
  ],
  "roles": ["User", "Admin"]
}
```

`source: "generated"` kennzeichnet das Mockup als Agent-generiert (nicht Kunden-Artefakt).
Das bestimmt den Quellen-Rang: generierte Mockups sind Rang 1.5 (siehe `source-priority.md`).

### Versionierung und Archiv

Wenn der Entwickler einen neuen Generate-Zyklus anstosst:
1. Bestehende Mockups nach `input-resources/ui-ux/_archive/` verschieben
2. Timestamp-Suffix anhaengen: `overview_2026-09-01.html`
3. Neue Version als einzige Datei im Hauptordner
4. Der Analyze-Modus ignoriert `_archive/` per Konvention

### Einschraenkungen Generate-Modus

- Wireframe-Fidelity: KEIN MB_UI-Styling, keine Farben, keine Icons
- Mockup ist nach Freigabe eingefroren — Aenderungen nur durch neuen Generate-Zyklus
- Generiertes Mockup ersetzt KEIN Kunden-Mockup wenn spaeter eines geliefert wird

---

## Analyze-Modus (Discovery)

Trigger: Phase ist `discovery` und Mockups unter `input-resources/ui-ux/` vorhanden. Laeuft parallel zum Discovery-Agent.

### Ablauf

1.  **Schema laden:** Lade das Ziels-Schema aus `.mxagile/schemas/page.schema.json`.
2.  **Mockups analysieren:** Starte Playwright, öffne jedes Mockup-HTML.
3.  **Seiten-Struktur erfassen:** Gehe alle Seiten und sichtbaren Zustände systematisch durch. Identifiziere logische Bereiche (Sections) und UI-Gruppen (Components wie Forms, Tables).
4.  **Pro Seite ein Page YAML erzeugen:** Erzeuge für jede Seite eine `.yaml`-Datei unter `planning/ui-inventory/`. Das Format MUSS dem `page.schema.json` entsprechen.
    *   **IDs generieren:** Erzeuge stabile, lesbare IDs für alle Elemente (z.B. `PAGE-CUSTOMER-EDIT`, `FIELD-CUSTOMER-NAME`, `ACT-CUSTOMER-SAVE`).
    *   **Semantik extrahieren:** Fülle die Felder `purpose`, `roles`, `sections`, `components`, `fields`, und `actions` basierend auf der visuellen Analyse.
    *   **Best-Effort-Typisierung:** `suggested_mendix_type` ist weiterhin ein Best-Effort-Versuch.
5.  **Screenshots erstellen:** Lege Screenshots der relevanten Zustände unter `.concord/screenshots/mockup/` ab.
6.  **MB_UI-Mapping:** Prüfe bei Layout-Elementen, ob ein Äquivalent aus einer konfigurierten UI-Bibliothek (z.B. MB_UI) existiert und vermerke es.
7.  **Lücken dokumentieren:** Unklare oder widersprüchliche Elemente als `DECISION REQUIRED` markieren. Das Mockup selbst wird NICHT verändert.

### Output Example (`planning/ui-inventory/Customer_NewEdit.yaml`)

```yaml
page_id: PAGE-CUSTOMER-NEWEDIT
source_mockup: input-resources/ui-ux/customer-newedit.html
purpose: "Erfassen und Bearbeiten von Kundendaten."
roles:
  - Sales
  - Admin
sections:
  - id: SEC-CUSTOMER-DETAILS
    title: "Kundendetails"
    components:
      - id: COMP-CUSTOMER-FORM
        type: form
        fields:
          - id: FIELD-CUSTOMER-NAME
            label: "Name"
            type: text
            suggested_mendix_type: "String(200)"
          - id: FIELD-CUSTOMER-SINCE
            label: "Kunde seit"
            type: date
            suggested_mendix_type: "DateTime"
        actions:
          - id: ACT-CUSTOMER-SAVE
            label: "Speichern"
            triggers: "calls a microflow"
          - id: ACT-CUSTOMER-CANCEL
            label: "Abbrechen"
            triggers: "closes page"
```

### Output Files

-   `planning/ui-inventory/{PageName}.yaml` (pro erkannter Seite, gemäß Schema)
-   `.concord/screenshots/mockup/{PageName}_{State}.png`

## Verifying-Modus

Trigger: Phase ist `verifying` und Docker-App laeuft.

### Ablauf

1. `implementation-checklist.yaml` laden
2. Playwright gegen die laufende App-URL starten
3. Fuer jede Seite im UI-Inventar:
   a. Seite oeffnen
   b. Jedes Feld per `.mx-name-*` Selector pruefen (Fallback: Label-Text)
   c. Jeden Button pruefen
   d. Navigation pruefen
4. Soll-Ist-Tabelle erzeugen:

```yaml
page: Customer_NewEdit
comparison:
  - field: Name
    expected: "TEXTBOX, required"
    actual: "TEXTBOX txtName found, NOT NULL constraint present"
    status: ok
  - field: Email
    expected: "TEXTBOX, required"
    actual: "not found"
    status: missing
```

5. Bei `failed` oder `missing`: entsprechendes Item in `implementation-checklist.yaml` auf `status: failed` setzen mit Begruendung
6. App-Screenshots unter `.concord/screenshots/app/` ablegen

### Output

- Soll-Ist-Report unter `planning/ui-inventory/{PageName}_comparison.yaml`
- Aktualisierte `implementation-checklist.yaml` (failed-Items)
- `.concord/screenshots/app/{PageName}_{State}.png`

## Einschraenkungen

- Kein Zugriff auf mxcli (kein Modell-Lesen/Schreiben)
- Kein Zugriff auf Mendix-Modell — nur Browser-Sicht
- Keine Geschaeftslogik-Pruefung — das macht der Acceptance-Agent


