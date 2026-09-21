# UI/UX Input Resources

Dieser Ordner enthaelt visuelle und interaktive Eingabeartefakte fuer die Mendix-Implementierung.

## Was hier abgelegt wird

- **HTML-Mockups** (`*.html`) — interaktive Wireframes und Prototypen
- **Wireframes / Screenshots** — statische visuelle Referenzen
- **UX-Ablaufe** — Navigationsdokumentation, User Flows

## Was hier NICHT abgelegt wird

Generierte Analyseergebnisse, Planungsartefakte und Laufzeit-Evidenz gehoeren NICHT hierher:

| Artefakt | Richter Ort |
|---|---|
| Screenshots der laufenden App | `.concord/screenshots/app/` |
| Mockup-Analyse-Screenshots | `.concord/screenshots/mockup/` |
| UI-Inventar YAML | `planning/ui-inventory/` |
| Soll-Ist-Berichte | `planning/ui-inventory/*_comparison.yaml` |
| Story-Spezifikationen | `planning/stories/` |

## HTML-Mockups — Hinweise fuer Agenten

HTML-Mockups werden von einem AI-Agenten mit Playwright in einem echten Browser ausgefuehrt.
Der Code wird nicht direkt analysiert.

Relevante Aspekte:
- sichtbare Seitenstruktur und Navigation
- Formulare, Felder und Validierungen
- Dialoge und Zustandswechsel
- erkennbare fachliche Ablaeufe

## Archiv

Aeltere generierte Mockup-Versionen werden nach `_archive/` verschoben.
Der Ordner `_archive/` wird vom UI-Agent ignoriert.

## Schreibschutz

Dateien in diesem Ordner sind Eingabeartefakte und duerfen vom Agenten nicht veraendert werden,
sofern dies nicht ausdruecklich beauftragt wurde.
