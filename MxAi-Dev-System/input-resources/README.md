# Input Resources

Dieser Ordner enthält Eingabeartefakte für die Umsetzung des Mendix-Projekts.

## Verbindlichkeit

Relevante Artefakte in diesem Ordner müssen vor Planung und Implementierung
einer Story berücksichtigt werden.

Die Mendix Platform bleibt die Source of Truth für User Stories und Sprintstatus.
Dieser Ordner ergänzt die Stories um fachliche, visuelle und interaktive Referenzen.

## Struktur

- `ui-ux/`
  - interaktive HTML-Mockups
  - Screenshots
  - visuelle Referenzen
  - UX-Abläufe

- `requirements/`
  - ergänzende Anforderungsdokumente
  - fachliche Regeln
  - Spezifikationen
  - `_TEMPLATE.md` — Vorlage fuer neue Anforderungsdokumente (5 Completeness-Kriterien)

- `processes/`
  - Prozessdarstellungen
  - Abläufe
  - Zustandsmodelle

## HTML-Mockups

HTML-Mockups sind nicht nur als Quellcode zu analysieren.

Sie müssen nach Möglichkeit in einem echten Browser ausgeführt werden, damit
auch folgende Informationen berücksichtigt werden:

- sichtbare Seitenstruktur
- Navigation
- Benutzerinteraktionen
- Formulare und Validierungen
- Dialoge
- Zustandswechsel
- ein- und ausgeblendete Inhalte
- erkennbare fachliche Abläufe
- responsive Verhalten, sofern vorhanden

### Vorgehen

1. Relevantes Mockup zur Story identifizieren.
2. Mockup mit Playwright in einem Browser öffnen.
3. Relevante Nutzerwege ausführen.
4. Wichtige Zustände als Screenshot erfassen.
5. Bei zustandsabhängigen UI-Elementen alle fachlich relevanten Varianten aktiv auslösen,
  zum Beispiel Auswahlwerte, Tabs, Rollen, Filter und Dialogzustände.
6. Je Variante Labels, sichtbare Felder, Eingabequelle, Pflichtfelder, Validierungen und
  erkennbare Datenwirkung beobachten und als fachliche Regel oder `⚠️ DECISION REQUIRED`
  festhalten.
7. Beobachtetes Verhalten mit der User Story abgleichen.
8. Mendix-Artefakte auf Basis von Story und Mockup planen.
9. Nach der Implementierung die laufende Mendix-App mit denselben Nutzerwegen prüfen.
10. Abweichungen im Review-/Done-Log dokumentieren.

## Priorität bei Widersprüchen

Bei Widersprüchen gilt:

1. explizite User Story und Akzeptanzkriterien
2. ausdrücklich bestätigte fachliche Entscheidungen
3. interaktives Verhalten des Mockups
4. visuelle Darstellung des Mockups
5. Annahmen des Agenten

Widersprüche dürfen nicht stillschweigend aufgelöst werden.

Sie sind als `⚠️ DECISION REQUIRED` zu dokumentieren.

## Schreibschutz

Dateien in `input-resources/` gelten als Eingabe.

Der Agent darf sie analysieren, ausführen und für Screenshots verwenden,
aber nicht verändern, sofern dies nicht ausdrücklich beauftragt wurde.

Generierte Screenshots und andere temporäre Analyseergebnisse dürfen nicht
ungefragt zwischen den ursprünglichen Eingabeartefakten gespeichert werden.