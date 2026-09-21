# Quellen-Vorrang

Alle Agents folgen dieser Hierarchie wenn mehrere Quellen zu einer Anforderung existieren.

## Rang-Ordnung

| Rang | Quelle | Pfad | Charakter |
|---|---|---|---|
| 1 | **Kunden-Mockup + Requirements-Dokument** | `input-resources/ui-ux/`, `input-resources/requirements/` | Primaere Kundenartefakte (gleichrangig) |
| 1.5 | **Generiertes Mockup** | `input-resources/ui-ux/` (mit `"source": "generated"`) | Vom UI-Agent erzeugt und vom Entwickler freigegeben |
| 2 | **Bestehendes Mendix-Modell** | via mxcli SHOW/DESCRIBE | Ist-Zustand, technische Constraints |
| 3 | **Board-Stories** | `sprints/generated/` | Management-Tracking, Priorisierung |
| 4 | **Klaerungen aus Refinement** | `sprints/decisions.md` | Ergaenzungen, Entscheidungen |

Generierte Mockups erkennt man am `"source": "generated"` im eingebetteten `mocketeer-spec` JSON.
Sie sind nur gueltig wenn `"approved": true` gesetzt ist (Entwicklerfreigabe).

## Konfliktregeln (Default — ohne concern-spezifische Konfiguration)

- **Rang 1 intern (Kunden-Mockup vs. Requirements):** Kein automatischer Gewinner. Bei Widerspruch → `DECISION REQUIRED`.
- **Rang 1 vs. Rang 1.5 (Kunden-Mockup vs. generiertes Mockup):** Kunden-Mockup gewinnt immer — es ersetzt das generierte Mockup.
- **Rang 1.5 vs. Rang 1 (generiertes Mockup vs. Requirements):** Requirements gewinnen stillschweigend. Das generierte Mockup wurde aus den Requirements abgeleitet; bei Widerspruch ist das Requirements-Dokument autoritativ.
- **Rang 1 vs. Rang 2 (Kundenartefakt vs. Modell):** Kundenartefakt gewinnt, es sei denn eine technische Constraint (z.B. bestehende Generalisierung, Plattformmodul-Restriktion) macht die Anforderung unumsetzbar → `DECISION REQUIRED` mit Erklaerung.
- **Rang 1 vs. Rang 3 (Kundenartefakt vs. Board):** Kundenartefakt gewinnt immer. Board-Story wird angepasst, nicht umgekehrt.
- **Rang 4 ueberschreibt alles** wenn eine explizite Entwickler-Entscheidung vorliegt — das ist der Sinn von Refinement-Klaerungen.

## Aspekt-Zuordnung

Nicht jede Quelle ist fuer jeden Aspekt gleich aussagekraeftig:

| Aspekt | Primaere Quelle |
|---|---|
| UI-Layout, Felder, Navigation | Mockup |
| Geschaeftsregeln, Validierungen, Berechnungen | Requirements-Dokument |
| Technische Constraints, bestehende Entitaeten | Mendix-Modell |
| Prioritaet, Reihenfolge, Scope | Board-Stories |

## Concern-spezifische Autoritaet (mxagile-project.yaml)

Wenn `mxagile-project.yaml` im Projektstamm `source_authority` konfiguriert, wird jeder
Concern separat aufgeloest. Eine Quelle ueberschreibt NICHT global eine andere Quelle.

```yaml
source_authority:
  ui_visual: mockup          # visuelle Darstellung / Layout
  ui_interaction: mockup     # Interaktionsverhalten: Zustaende, Sichtbarkeit, Enablement
  navigation: mockup         # Navigationsfluss zwischen Seiten
  business_logic: requirements   # Geschaeftsregeln, Pflichtfelder, Berechnungen
  data_rules: requirements       # Datentypen, Constraints, Validierungsregeln
```

**Aufloesung:**

1. Pruefen welchem Concern die Frage angehoert (z.B. "Ist das Feld Pflichtfeld?" → business_logic)
2. Die konfigurierte authoritative Quelle fuer diesen Concern liest man — nicht die andere
3. Erst wenn BEIDE Rang-1-Quellen zum GLEICHEN Concern widerspruechen und kein Gewinner
   konfiguriert ist: `DECISION REQUIRED`

**Beispiele:**

| Situation | Concern | Konfigurierter Gewinner | Ergebnis |
|---|---|---|---|
| Mockup zeigt Feld als Dropdown, Requirements schweigen | ui_visual | mockup | Dropdown implementieren — kein Konflikt |
| Mockup zeigt Feld, Requirements sagen es ist optional | business_logic | requirements | Feld optional — Requirements gewinnen |
| Mockup navigiert A→B, Requirements sagen A→C | navigation | mockup | Navigation A→B — Mockup gewinnt |
| Mockup zeigt Pflichtfeld, Requirements auch, aber unterschiedliche Fehlermeldung | business_logic | requirements | Requirements-Fehlermeldung — kein echter Widerspruch zur Pflichtfeldigkeit |
| Beide Quellen beschreiben Berechnungsformel widerspruchlich | business_logic | requirements | Requirements-Formel — wenn eindeutig; sonst DECISION REQUIRED |

Kein DECISION REQUIRED wegen reiner Concern-Trennung. Dass das Mockup bestimmt WIE ein Feld
aussieht, waehrend Requirements bestimmen OB es Pflicht ist, ist kein Widerspruch — das sind
verschiedene Concerns.

**Default ohne Konfiguration:** ohne `mxagile-project.yaml` oder ohne `source_authority`
Eintrag gelten die Standard-Konfliktregeln oben — beide Rang-1-Quellen sind gleichrangig.

## Fehlende Primaerquelle

Wenn die primaere Quelle fuer einen Aspekt fehlt, darf der Agent den Aspekt NICHT
aus einer anderen Quelle ableiten oder selbst antizipieren. Stattdessen:
- Aspekt als `DECISION REQUIRED` markieren
- Dem Entwickler eine strukturierte Rueckfrage stellen
- Erst nach expliziter Antwort in die Story-Spec uebernehmen

Beispiel: Ein Mockup zeigt ein Formular, aber kein Requirements-Dokument beschreibt die
Geschaeftsregeln dahinter. Der Agent darf Felder und Layout dokumentieren (Mockup-Aspekt),
aber Pflichtfelder, Validierungen und Berechnungen NICHT vermuten (Requirements-Aspekt).

## Board-Sync ist optional (D52)

Nicht jedes Projekt hat ein Board. Die primaeren Quellen (Mockup + Requirements) kommen immer.
Wenn ein Board konfiguriert ist, wird es in Discovery als Kontext gelesen und in Verifying
als Reporting aktualisiert. Fehlendes Board blockiert keinen Gate-Uebergang.
