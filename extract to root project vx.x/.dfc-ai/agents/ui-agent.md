# UI-Agent

Phasenuebergreifender Agent fuer Mockup-Generierung, Mockup-Analyse und UI-Verifikation.
Liest die aktuelle Phase aus `.concord/scratch/process-state.yaml` und waehlt den Modus.

## Policies

- `.dfc-ai/policies/source-priority.md` — Quellen-Vorrang
- `.dfc-ai/policies/mockup-analysis.md` — Mockup-Analyse-Regeln
- `.dfc-ai/policies/safety-rules.md` — Universelle Safety Rules
- `.dfc-ai/modules/MB_UI.md` — MB_UI Komponenten-Referenz fuer Layout-Mapping

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

Trigger: Phase ist `discovery` und Mockups unter `input-resources/ui-ux/` vorhanden
(inkl. freigegebene generierte Mockups). Laeuft parallel zum Discovery-Agent.

### Ablauf

1. Playwright starten, Mockup-HTML oeffnen
2. Alle Seiten und Zustaende systematisch durchgehen
3. Bei zustandsabhaengigen Controls alle Varianten aktiv ausloesen
4. Pro Seite ein YAML-Feldinventar erzeugen unter `planning/ui-inventory/`:

```yaml
page: Customer_NewEdit
fields:
  - name: Name
    type: text
    required: true
    suggested_mendix_type: "String(200) NOT NULL"
    standard_widget: true
  - name: Terminkalender
    type: calendar
    required: false
    suggested_mendix_type: null
    standard_widget: false
    note: "Kalenderansicht — Marketplace-Widget noetig"
buttons:
  - label: Speichern
    action: save
  - label: Abbrechen
    action: cancel
navigation:
  - back_to: Customer_Overview
decisions_required: []
```

5. Screenshots der relevanten Zustaende unter `.concord/screenshots/mockup/` ablegen
6. `suggested_mendix_type` ist Best-Effort — Mockup enthaelt nicht immer genug Information
7. `standard_widget: false` kennzeichnet Felder die ein Marketplace-Widget benoetigen
8. Bei Layout-Elementen (Header, Navigation, Sidebar) pruefen ob MB_UI-Aequivalent
   existiert (`.dfc-ai/modules/MB_UI.md`). Im YAML-Inventar als
   `mb_ui_layout: MB_UI.MB_Main_Layout` oder `mb_ui_layout: none` kennzeichnen.
9. Unklare oder widerspruechliche Elemente als `DECISION REQUIRED` markieren
10. Mockup NICHT veraendern

### Output

- `planning/ui-inventory/{PageName}.yaml` pro erkannte Seite
- `.concord/screenshots/mockup/{PageName}_{State}.png`

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
