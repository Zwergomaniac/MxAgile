# Refinement

Klaerung von Mehrdeutigkeiten, Widerspruechen und fehlenden Geschaeftsregeln
vor der Implementierung.

## Trigger

Nach Discovery, wenn offene `DECISION REQUIRED` oder `ASSUMPTION` existieren.

## Ablauf

1. **Offene Punkte sammeln** — Alle `DECISION REQUIRED` und `ASSUMPTION` aus
   der Story-Spezifikation und verwandten Artefakten auflisten.
2. **Widersprueche identifizieren** — Quellen (Mockup, Board-Story, bestehendes
   Modell, Plattformmodul-Regeln) gegeneinander pruefen.
3. **Strukturierte Rueckfragen formulieren** — Fuer jeden offenen Punkt:
   - Frage klar formulieren
   - Kontext geben (welche Quellen sich widersprechen oder was fehlt)
   - Empfehlung aussprechen
   - Blockade-Bewertung: blockiert dieser Punkt die Implementierung?
4. **Rueckfragen gebuendelt stellen** — Nicht einzeln, sondern gesammelt dem
   Entwickler vorlegen.
5. **Antworten einarbeiten** — Entscheidungen in `sprints/decisions.md`
   dokumentieren. Annahmen in der Story-Spezifikation aktualisieren.
6. **Iterieren** — Wenn neue Fragen entstehen, erneut Rueckfragen formulieren.
   Erst weiter wenn alle Blocker aufgeloest sind.

## Output

- Aktualisierte Story-Spezifikation ohne offene Blocker
- Neue Eintraege in `sprints/decisions.md`
- Akzeptanzkriterien in der Story-Spezifikation
