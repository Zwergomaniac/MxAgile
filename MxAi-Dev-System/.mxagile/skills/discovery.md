# Discovery

Systematische Analyse aller verfuegbaren Quellen bevor Refinement oder
Implementierung beginnt.

## Trigger

Aufruf vor der ersten Implementierungsarbeit an einer neuen Story oder einem
neuen Arbeitspaket.

## Ablauf

1. **Board-Sync pruefen** — `sprints/generated/` muss aktuell sein.
   Falls nicht: `scripts/sync-epics-stories.ps1` ausfuehren.
2. **Story lesen** — Board-Snapshot fuer die betreffende Story lesen.
   Akzeptanzkriterien, Beschreibung und Abhaengigkeiten erfassen.
3. **Input-Resources pruefen** — Gibt es unter `input-resources/` relevante
   Mockups, UI-Referenzen, Anforderungsdokumente oder Prozessdarstellungen?
4. **Mockup analysieren** (falls vorhanden) — Gemaess `.mxagile/policies/mockup-analysis.md`.
5. **Bestehendes Modell lesen** — Welche Entities, Microflows, Pages existieren
   bereits im betroffenen Modul? Falls eine Company Layer installiert ist (.mxagile/layers/),
   in `.mxagile/layers/<layer-id>/platform-modules.yml` pruefen welche Plattformmodule
   relevant sind. Ohne Layer: kein company-spezifischer Modul-Constraint.
6. **Entscheidungen pruefen** — `sprints/decisions.md` auf relevante Vorarbeiten
   durchsehen.
7. **Luecken markieren** — Fehlende Informationen als `DECISION REQUIRED` oder
   `ASSUMPTION` markieren.
8. **Story-Spezifikation erstellen** — Unter `planning/stories/{STORYPREFIX}-*.md` mit
   Requirement-ID, Wave-Zuordnung, Quellenangabe und — sofern gemappt — Board-Story-ID.

## Output

- Story-Spezifikation unter `planning/stories/`
- Liste der offenen `DECISION REQUIRED` und `ASSUMPTION`
- Identifizierte Abhaengigkeiten zu anderen Stories oder Modulen


