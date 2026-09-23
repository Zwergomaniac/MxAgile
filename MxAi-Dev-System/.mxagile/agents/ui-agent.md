# UI-Agent

Phasenuebergreifender Agent fuer Mockup-Generierung, Mockup-Analyse und UI-Verifikation.
Liest die aktuelle Phase aus `.concord/scratch/process-state.yaml` und waehlt den Modus.

## Projektkonfiguration

Lies `mxagile-project.yaml` im Projektstamm sofern vorhanden.
Relevante Felder: `development.ui_driven`, `ui.fidelity`.
Falls die Datei nicht existiert: `ui_driven: false`, `fidelity: standard`.

## Policies

- `.mxagile/policies/source-priority.md` — Quellen-Vorrang und concern-spezifische Autoritaet
- `.mxagile/policies/mockup-analysis.md` — Mockup-Analyse-Regeln
- `.mxagile/policies/runtime-strategy.md` — Runtime-Strategie: Local First, Docker by Need
- `.mxagile/policies/safety-rules.md` — Universelle Safety Rules
- Company Layer UI documentation (if installed): `.mxagile/layers/*/modules/` fuer UI-Komponenten-Referenzen

## Modi-Uebersicht

| Modus | Trigger | Output |
|---|---|---|
| **Generate** | Discovery + kein Mockup + App-Beschreibung vorhanden | Wireframe-HTML mit mocketeer-spec |
| **Analyze** | Discovery + Mockup vorhanden | YAML-Feldinventar inkl. Navigation und Interaction-States |
| **Verify** | Verifying + Applikation laeuft (lokal oder Docker per Runtime-Strategie) | Soll-Ist-Report inkl. Fidelity-Ergebnis |

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
   - Bewusst roh: graue Kaesten, Labels, Platzhalter — kein company-spezifisches Styling
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

- Wireframe-Fidelity: KEIN company-spezifisches Styling, keine Farben, keine Icons
- Mockup ist nach Freigabe eingefroren — Aenderungen nur durch neuen Generate-Zyklus
- Generiertes Mockup ersetzt KEIN Kunden-Mockup wenn spaeter eines geliefert wird

---

## Analyze-Modus (Discovery)

Trigger: Phase ist `discovery` und Mockups unter `input-resources/ui-ux/` vorhanden.
Laeuft parallel zum Discovery-Agent.

Wenn `development.ui_driven = true`: Dieser Modus ist PFLICHT wenn ein HTML-Mockup
vorhanden ist. Der Discovery-Agent darf gate-to-refinement nicht passieren ohne abgeschlossenes Inventar.

### Ablauf

1.  **Schema laden:** Lade das Ziels-Schema aus `.mxagile/schemas/page.schema.json`.
2.  **Mockups analysieren:** Starte Playwright, oeffne jedes Mockup-HTML aus `input-resources/ui-ux/`
    (alle `*.html` inkl. `index.html`; `_archive/` ignorieren).
3.  **Seiten-Struktur erfassen:** Gehe alle Seiten und sichtbaren Zustaende systematisch durch.
    Identifiziere logische Bereiche (Sections) und UI-Gruppen (Components wie Forms, Tables).
4.  **Pro Seite ein Page YAML erzeugen:** Erzeuge fuer jede Seite eine `.yaml`-Datei unter
    `planning/ui-inventory/`. Das Format MUSS dem `page.schema.json` entsprechen.
    *   **IDs generieren:** Erzeuge stabile, lesbare IDs fuer alle Elemente
        (z.B. `PAGE-CUSTOMER-EDIT`, `FIELD-CUSTOMER-NAME`, `ACT-CUSTOMER-SAVE`).
    *   **Semantik extrahieren:** Fuehre die Felder `purpose`, `roles`, `sections`,
        `components`, `fields` und `actions` aus der visuellen Analyse.
    *   **`visual_priority` fuer Aktionen:** Primaere Aktionen (z.B. Speichern-Schaltflaeche)
        als `primary`, sekundaere (Abbrechen) als `secondary` markieren.
    *   **Best-Effort-Typisierung:** `suggested_mendix_type` ist weiterhin ein Best-Effort-Versuch.
5.  **Typisierte Navigation erfassen:** Fuer jede identifizierte Seiten-Navigation einen
    Eintrag im `navigation` Array des Page YAML erstellen:
    ```yaml
    navigation:
      - action_id: ACT-CUSTOMER-SAVE
        leads_to_page: Customer_Overview
        condition: null
      - action_id: ACT-CUSTOMER-CANCEL
        leads_to_page: Customer_Overview
        condition: null
    ```
    Nur direkt beobachtbare Navigation aufnehmen. Bedingungen als `condition` notieren
    wenn erkennbar. Nicht spekulative Navigationspfade erfinden.
6.  **Interaction-States erfassen:** Relevante UI-Zustaende dokumentieren:
    ```yaml
    interaction_states:
      - state_id: STATE-CUSTOMER-EMPTY
        description: "Formular initial leer, alle Felder ohne Eingabe"
        trigger: "Seite wird geoeffnet"
        screenshot: .concord/screenshots/mockup/Customer_NewEdit_empty.png
      - state_id: STATE-CUSTOMER-VALIDATION-ERROR
        description: "Pflichtfeld-Fehler nach Speichern ohne Name"
        trigger: "Speichern-Button geklickt, Name leer"
        screenshot: .concord/screenshots/mockup/Customer_NewEdit_validation.png
    ```
    Alle fachlich relevanten Varianten (Tabs, Rollen, Filter, Dialogzustaende) aktiv ausloesen.
7.  **Reference Screenshot:** Hauptzustand jeder Seite als `layout_reference` Screenshot
    unter `.concord/screenshots/mockup/{PageName}_default.png` speichern.
    Diesen Pfad im Page YAML als `layout_reference` eintragen.
8.  **Screenshots erstellen:** Alle relevanten Zustaende unter `.concord/screenshots/mockup/`
    ablegen (Format: `{PageName}_{State}.png`).
9.  **Company Layer UI-Mapping:** Bei Layout-Elementen pruefen ob ein Aequivalent aus der
    installierten Company Layer UI-Bibliothek existiert (`.mxagile/layers/*/modules/` falls Layer vorhanden).
10. **Luecken dokumentieren:** Unklare oder widerspruechliche Elemente als `DECISION REQUIRED`
    markieren. Das Mockup selbst wird NICHT veraendert.

### Output Example (`planning/ui-inventory/Customer_NewEdit.yaml`)

```yaml
page_id: PAGE-CUSTOMER-NEWEDIT
source_mockup: input-resources/ui-ux/customer-newedit.html
layout_reference: .concord/screenshots/mockup/Customer_NewEdit_default.png
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
            visual_priority: primary
            triggers: "calls a microflow"
          - id: ACT-CUSTOMER-CANCEL
            label: "Abbrechen"
            visual_priority: secondary
            triggers: "closes page"
navigation:
  - action_id: ACT-CUSTOMER-SAVE
    leads_to_page: Customer_Overview
    condition: null
  - action_id: ACT-CUSTOMER-CANCEL
    leads_to_page: Customer_Overview
    condition: null
interaction_states:
  - state_id: STATE-CUSTOMER-EMPTY
    description: "Formular initial leer"
    trigger: "Seite wird geoeffnet"
    screenshot: .concord/screenshots/mockup/Customer_NewEdit_empty.png
  - state_id: STATE-CUSTOMER-VALIDATION
    description: "Name-Pflichtfeld-Fehler sichtbar"
    trigger: "Speichern ohne Name"
    screenshot: .concord/screenshots/mockup/Customer_NewEdit_validation.png
```

### Output Files

-   `planning/ui-inventory/{PageName}.yaml` (pro erkannter Seite, gemaeß Schema)
-   `.concord/screenshots/mockup/{PageName}_default.png` (Referenz-Screenshot)
-   `.concord/screenshots/mockup/{PageName}_{State}.png` (Zustand-Screenshots)

---

## Verifying-Modus

Trigger: Phase ist `verifying` und Applikation laeuft und per Browser erreichbar.

Die Applikation laeuft bevorzugt als warmer lokaler Runtime (`mxcli run --local --watch`,
Level 3). Docker (Level 4) wird nur verwendet wenn Container-Paritaet benoetigt oder
der lokale Runtime keine valide Verifikationsevidenz liefern kann.
Vollstaendige Eskalationsregeln: `.mxagile/policies/runtime-strategy.md`.

### Ablauf

1. `mxagile-project.yaml` lesen (falls vorhanden): `ui.fidelity` ermitteln.
   Standard: `fidelity: standard`.
2. `implementation-checklist.yaml` laden.
3. Playwright gegen die laufende App-URL starten.
4. Fuer jede Seite im UI-Inventar:
   a. Seite oeffnen
   b. **Strukturelle Pruefung** (immer, unabhaengig von fidelity):
      - Jedes Feld per `.mx-name-*` Selector pruefen (Fallback: Label-Text)
      - Jeden Button pruefen
      - App-Screenshot unter `.concord/screenshots/app/{PageName}_default.png` speichern
   c. **Navigations-Pruefung** (immer, wenn `navigation` im Inventar vorhanden):
      - Jede typisierte Navigation aus dem Inventar ausfuehren:
        action ausloesen → pruefen ob erwartete Zielseite geladen wird
   d. **Interaction-State-Pruefung** (immer, wenn `interaction_states` im Inventar vorhanden):
      - Jeden dokumentierten State ausloesen und pruefen ob er eintritt
      - Screenshot unter `.concord/screenshots/app/{PageName}_{State}.png`
   e. **Semantische Fidelity-Pruefung** (nur wenn `ui.fidelity = high`):
      Ausfuehrlicher Vergleich gegen `layout_reference` und `ui-inventory`:

      1. **Seitenstruktur:** Stimmt die Section-Anzahl und -Reihenfolge ueberein?
      2. **Gruppen-Treue:** Sind zusammengehoerige Felder (gleiche Section im Inventar)
         noch zusammen, oder auf verschiedene Bereiche verteilt?
      3. **Element-Reihenfolge:** Stimmt die Feld- und Button-Reihenfolge innerhalb
         von Sections ueberein?
      4. **Komponenten-Typen:** Werden vergleichbare Mendix-Kontrolltypen verwendet?
         (z.B. Dropdown erwartet per Inventar, TextBox implementiert — ist eine Deviation)
      5. **Visuelle Hierarchie:** Ist eine als `visual_priority: primary` markierte Aktion
         noch visuell prominenter als sekundaere Aktionen?

      Nur faktisch beobachtbare Unterschiede dokumentieren — keine Pixel-Arithmetik.
      Signifikante Abweichungen in `deviations` eintragen.

5. Soll-Ist-Tabelle erzeugen und `ui_fidelity` Block befuellen:

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
navigation:
  - action_id: ACT-CUSTOMER-SAVE
    leads_to_page: Customer_Overview
    status: ok
  - action_id: ACT-CUSTOMER-CANCEL
    leads_to_page: Customer_Overview
    status: ok
interaction_states:
  - state_id: STATE-CUSTOMER-VALIDATION
    status: ok
ui_fidelity:
  configured: high
  result: FAIL
  reference: .concord/screenshots/mockup/Customer_NewEdit_default.png
  evidence: .concord/screenshots/app/Customer_NewEdit_default.png
  deviations:
    - concern: section_grouping
      description: "Name und Email-Felder in getrennten Sections implementiert; Mockup zeigt sie in einer Section"
      severity: material
    - concern: action_ordering
      description: "Abbrechen-Button links von Speichern; Mockup zeigt Speichern links"
      severity: minor
```

`ui_fidelity.result`:
- `PASS` — keine materiellen Abweichungen (minor-only Deviations sind erlaubt)
- `WARNING` — geringe material deviations, keine funktionalen Auswirkungen
- `FAIL` — materielle Abweichungen die das UI-Konzept verletzt

6. Bei `failed` oder `missing` (strukturell) oder `ui_fidelity.result: FAIL` (fidelity):
   Betroffenes Item in `implementation-checklist.yaml` auf `status: failed` setzen.
7. App-Screenshots unter `.concord/screenshots/app/` ablegen.

### Wann ist eine Abweichung "material"?

Material (resultiert in WARNING oder FAIL):
- Erwartetes zwei-Spalten-Layout implementiert als ein-spaltig
- Erwartete Tabs implementiert als ungeordnete flache Sections
- Primaere Aktion (primary) nicht visuell hervorgehoben
- Navigationsfluss weicht vom Inventar ab
- Wichtige Interaction-State fehlt komplett
- Felder-Gruppierung grundlegend anders als im Inventar

Nicht material (ignorieren bei PASS-Bewertung):
- Geringfuegig andere Abstands- oder Proportionsunterschiede
- Gleichwertige Mendix-Standard-Widgets mit aehnlicher UX
- Reihenfolge von optionalen Metadaten-Feldern

### Output

- Soll-Ist-Report unter `planning/ui-inventory/{PageName}_comparison.yaml`
- Aktualisierte `implementation-checklist.yaml` (failed-Items)
- `.concord/screenshots/app/{PageName}_{State}.png`

## Einschraenkungen

- Kein Zugriff auf mxcli (kein Modell-Lesen/Schreiben)
- Kein Zugriff auf Mendix-Modell — nur Browser-Sicht
- Keine Geschaeftslogik-Pruefung — das macht der Acceptance-Agent
