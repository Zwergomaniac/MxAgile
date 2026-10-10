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
| Prioritaet, Reihenfolge | Board-Stories (wenn konfiguriert) |

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

## Board-Scope-Abgrenzung

Board-Stories liefern **Kontext** (Prioritaet, Reihenfolge), aber keine **Scope-Autoritaet**.
Scope wird ausschliesslich durch MxAgile-Lifecycle autorisiert: Requirements, Decisions,
Developer-Freigabe, mission-state.yaml.

Die blosse Existenz einer Board-Story autorisiert KEINE Implementierung, keinen
Wave-Eintritt und keine Mission-Erweiterung. Board-Stories werden nur dann zu
autorisiertem Scope, wenn der Entwickler oder eine autorisierte Produktautoritaet
sie explizit als neuen Scope auswaehlt.

Vollstaendiger Board Authority Contract: `policies/backlog-sync.md`.

---

## Design-System- und Company-Layer-Autoritaet fuer Styling-Dimensionen

### Parity Authority Matrix

Die Aspekt-Zuordnung oben beschreibt generische Quellpraeferenzen. Fuer Parity-Auswertungen
gelten zusaetzlich dimensionale Autoritaetsregeln, die Mockup-Werte NICHT automatisch
als autoritativ fuer Styling behandeln.

**Grundregel:** Ein Mockup ist eine visuelle Referenz, kein Design-Token-Vertrag.

Wenn ein Projekt ein Company Layer oder ein dediziertes Design-System installiert hat,
gelten fuer die **visuelle Parity-Dimension** (Farben, Abstands-Token, Typografie, Komponenten-Stil)
folgende Regeln:

| Parity-Dimension | Autoritaet: kein Design-System | Autoritaet: Design-System vorhanden |
|---|---|---|
| Farben / Color-Tokens | Mockup (ui_visual) | Design-System / Company Layer |
| Abstands-Token / Spacing | Mockup (ui_visual) | Design-System / Company Layer |
| Typografie | Mockup (ui_visual) | Design-System / Company Layer |
| Komponenten-Wahl | Company Layer First → Mockup | Company Layer First |
| Layout / Seitenstruktur | Mockup (ui_visual) | Mockup (ui_visual) |
| Interaktionsverhalten | Mockup (ui_interaction) | Mockup (ui_interaction) |
| Navigation | Mockup (navigation) | Mockup (navigation) |

**Design-System-Autoritaet erkennen:**
Ein Design-System oder Company Layer ist autoritaetsgegeben wenn:
- Ein Company Layer unter `.mxagile/layers/` installiert ist, ODER
- `mxagile-project.yaml` einen `company_layer`-Eintrag enthaelt, ODER
- Das Projekt eigene SCSS/Atlas-Design-Token-Dateien deklariert (company-layer-Konvention)

### Farbwerte aus Mockups

Wenn ein Design-System/Company Layer autoritaetsgegeben ist:

**Verboten:**
- Einen Hex-/RGB-Farbwert direkt aus dem Mockup extrahieren und als autoritative
  Implementierungsanforderung klassifizieren.
- Eine Abweichung zwischen Mockup-Farbe und implementierter Farbe als
  `CONFIRMED_REQUIREMENT_VIOLATION` klassifizieren, wenn kein Design-System-Token
  die spezifische Farbe verbindlich vorschreibt.

**Erlaubt:**
- Die visuelle Dimension als `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK`
  klassifizieren und DECISION_REQUIRED stellen, wenn der Mockup-Farbton
  sichtbar abweicht und kein Token die Erwartung erklaert.
- Eine Abweichung als `CONFIRMED_REQUIREMENT_VIOLATION` klassifizieren, wenn das
  Design-System explizit einen spezifischen Token-Wert vorschreibt und die Implementierung
  diesen nicht verwendet.

### Explizite Projekt-Entscheidung ueberschreibt alles

Eine explizite Entwickler-Entscheidung (Rang 4 / DEC-NNN) ueberschreibt sowohl die
Design-System-Autoritaet als auch die Mockup-Autoritaet fuer den entschiedenen Aspekt.

Wenn ein DEC-NNN besagt "Farbe X wird verwendet statt Design-Token Y", gilt diese
Entscheidung als autoritative Quelle und darf nicht durch spaetere Mockup-Parity-Laeufe
ueberschrieben werden.

### Fehlende Design-System-Definitionen

Wenn eine visuelle Abweichung besteht, kein Mockup-Wert autoritativ ist (Design-System
vorhanden) und kein Design-Token die Erwartung erklaert:

→ `CONFIRMED_PARITY_DIFFERENCE_REQUIRING_CONTRACT_CHECK`
→ DECISION_REQUIRED: Welcher Wert ist korrekt — Design-System-Token oder Mockup-Variante?

Einen Wert durch Extraktion aus dem Mockup zu "erfinden" ist verboten.
