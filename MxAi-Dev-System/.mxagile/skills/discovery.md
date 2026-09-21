# Discovery

Systematische Analyse aller verfuegbaren Quellen bevor Refinement oder
Implementierung beginnt.

## Trigger

Aufruf vor der ersten Implementierungsarbeit an einer neuen Story oder einem
neuen Arbeitspaket.

## Ablauf

1. **Projektkonfiguration lesen** — `mxagile-project.yaml` im Projektstamm pruefen.
   Falls vorhanden: `development.ui_driven`, `source_authority` und `ui.fidelity` lesen.
   Falls nicht vorhanden: Standardverhalten — `ui_driven: false`, alle anderen Defaults.

2. **Board-Sync pruefen** — `sprints/generated/` muss aktuell sein.
   Falls nicht: `scripts/sync-epics-stories.ps1` ausfuehren.

3. **Story lesen** — Board-Snapshot fuer die betreffende Story lesen.
   Akzeptanzkriterien, Beschreibung und Abhaengigkeiten erfassen.

4. **Input-Resources systematisch inventarisieren** — Vollstaendige Bestandsaufnahme
   BEVOR Discovery-Ergebnisse dokumentiert werden:

   a. `input-resources/` Verzeichnis-Baum vollstaendig auflisten (nicht nur die Wurzel)
   b. `input-resources/ui-ux/` explizit pruefen:
      - alle `*.html` Dateien inkl. `index.html` sofern vorhanden
      - alle `*.png`, `*.jpg`, `*.jpeg`, `*.svg` Dateien
      - Unterordner auflisten; `_archive/` ignorieren
   c. `input-resources/requirements/` auf Anforderungsdokumente pruefen
   d. `input-resources/processes/` und weitere Unterordner auf relevante Artefakte pruefen
   e. Jeden gefundenen Artefakt-Typen explizit benennen und als Input fuer diese Story registrieren

   Wenn `development.ui_driven = true` und mindestens ein HTML-Mockup in
   `input-resources/ui-ux/` gefunden wurde:
   **UI-Agent Analyze MUSS ausgefuehrt werden** — kein Weiterfahren ohne UI-Inventar.
   Der Entwickler wird nicht erwartet, den Agenten an das Mockup zu erinnern.

5. **Mockup analysieren** (falls vorhanden) — gemaess `.mxagile/policies/mockup-analysis.md`.
   UI-Agent Analyze laeuft parallel — diese Pruefung haelt nur fest ob ein Mockup vorliegt.

6. **Bestehendes Modell lesen** — Welche Entities, Microflows, Pages existieren
   bereits im betroffenen Modul? Falls eine Company Layer installiert ist (.mxagile/layers/),
   in `.mxagile/layers/<layer-id>/platform-modules.yml` pruefen welche Plattformmodule
   relevant sind. Ohne Layer: kein company-spezifischer Modul-Constraint.

7. **Entscheidungen pruefen** — `sprints/decisions.md` auf relevante Vorarbeiten
   durchsehen.

8. **Luecken markieren** — Fehlende Informationen als `DECISION REQUIRED` oder
   `ASSUMPTION` markieren.
   Concern-spezifische Aufloesung gemaess `mxagile-project.yaml` anwenden (falls konfiguriert):
   kein DECISION REQUIRED erzeugen wenn die Quellen zu verschiedenen Concerns sprechen.

9. **Story-Spezifikation erstellen** — Unter `planning/stories/{STORYPREFIX}-*.md` mit
   Requirement-ID, Wave-Zuordnung, Quellenangabe und — sofern gemappt — Board-Story-ID.

## Output

- Story-Spezifikation unter `planning/stories/`
- Liste der offenen `DECISION REQUIRED` und `ASSUMPTION`
- Identifizierte Abhaengigkeiten zu anderen Stories oder Modulen
