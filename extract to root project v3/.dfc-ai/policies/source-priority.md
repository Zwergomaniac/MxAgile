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

## Konfliktregeln

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
