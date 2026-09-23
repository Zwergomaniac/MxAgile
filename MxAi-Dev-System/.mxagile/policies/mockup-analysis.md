# Mockup-Analyse

Diese Regeln werden primaer vom **UI-Agent** (`agents/ui-agent.md`) ausgefuehrt.
In Discovery generiert oder analysiert der UI-Agent Mockups und erzeugt das YAML-Feldinventar.
In Verifying vergleicht er das Inventar gegen die laufende App.

## Verzeichnis-Konventionen

- `input-resources/ui-ux/` — aktuelle Mockups (Kunden-Artefakte oder freigegebene generierte)
- `input-resources/ui-ux/_archive/` — vorherige Versionen generierter Mockups (wird ignoriert)
- Der Analyze-Modus verarbeitet alle `*.html` Dateien im Hauptordner, NICHT in `_archive/`

## Generierte Mockups erkennen

Generierte Mockups enthalten `"source": "generated"` im eingebetteten `mocketeer-spec` JSON.
Sie haben Rang 1.5 (siehe `source-priority.md`) — unterhalb Requirements, oberhalb Mendix-Modell.
Ein generiertes Mockup ist nur gueltig wenn `"approved": true` im Spec steht.

Wenn spaeter ein Kunden-Mockup geliefert wird, ersetzt es das generierte Mockup.
Das generierte Mockup wird nach `_archive/` verschoben.

## Regeln fuer HTML-Mockups

Fuer HTML-Mockups unter `input-resources/ui-ux/`:

1. Zuerst `input-resources/README.md` lesen
2. Mockup in einem echten Browser mit Playwright ausfuehren
3. Nicht nur HTML-, CSS- oder JavaScript-Code analysieren
4. Relevante Seiten, Zustaende und Interaktionen mit Playwright untersuchen
5. Bei zustandsabhaengigen Controls alle fachlich relevanten Varianten aktiv ausloesen
   und Labels, sichtbare Felder, Eingabequelle, Validierungen und Datenwirkung vergleichen
6. Beobachtete Varianten als fachliche Regel oder `DECISION REQUIRED` dokumentieren
7. Screenshots der relevanten Zustaende erzeugen
8. UI, UX, Navigation, Validierungen und erkennbare fachliche Ablaeufe als Referenz
   fuer die Mendix-Implementierung verwenden
9. Unklare oder widerspruechliche Ablaeufe als `DECISION REQUIRED` markieren
10. Das Mockup nicht veraendern, sofern dies nicht ausdruecklich beauftragt wurde
11. **Typ klassifizieren:** Das Mockup als `static`, `executable` oder `unknown` klassifizieren
    und in der page YAML als `mockup_type` eintragen (siehe `policies/mockup-materialization.md`)
12. **Below-the-Fold:** Inhalte unterhalb des sichtbaren Viewport-Bereichs sind NICHT abwesend
    nur weil der Screenshot sie nicht zeigt. Fuer Navigation, Sidebar-Gruppen und scrollbare
    Bereiche: DOM-Queries (`innerText()`, Selektoren) verwenden die das gesamte Dokument abdecken,
    nicht nur den sichtbaren Bereich. Relevante Inhalte unterhalb des Viewports explizit erfassen.
    **NICHT SICHTBAR IM SCREENSHOT ≠ EXISTIERT NICHT.**

## Mockup-Materialisierung fuer ausfuehrbare Mockups

Wenn `mockup_type = executable`: vor der Parity-Auswertung gemaess
`policies/mockup-materialization.md` materialisieren. Quellcode-Inspektion allein reicht nicht.

## Nach der Mendix-Umsetzung

Dieselben Nutzerwege gegen die laufende App pruefen.
Der mxcli `test-app` Skill und die vorhandene Playwright-Konfiguration sind fuer
Browser-Automation und die Verifikation der laufenden Mendix-App zu verwenden.

## Interpretation

Die Interpretation des Mockups richtet sich nach den Regeln in
`input-resources/README.md`. Relevante Eingabeartefakte haben Vorrang vor
Annahmen des Agenten.
