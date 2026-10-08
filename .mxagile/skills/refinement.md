# Refinement

Klaerung von Mehrdeutigkeiten, Widerspruechen und fehlenden Geschaeftsregeln
vor der Implementierung.

## Trigger

Nach Discovery, wenn offene `DECISION REQUIRED` oder `ASSUMPTION` existieren.

## Ablauf

1. **Offene Punkte sammeln** — Alle `DECISION REQUIRED` und `ASSUMPTION` aus
   der Story-Spezifikation und verwandten Artefakten auflisten.
2. **Widersprueche identifizieren** — Quellen (Mockup, Board-Story als Rang-3-Kontext
   wenn Board konfiguriert, bestehendes Modell, Plattformmodul-Regeln) gegeneinander
   pruefen. Board-Aenderungen autorisieren keinen neuen Scope.
3. **Strukturierte Rueckfragen formulieren** — Fuer jeden offenen Punkt:
   - Frage klar formulieren
   - Kontext geben (welche Quellen sich widersprechen oder was fehlt)
   - Empfehlung aussprechen
   - Blockade-Bewertung: blockiert dieser Punkt die Implementierung?
4. **Rueckfragen gebuendelt stellen** — Nicht einzeln, sondern gesammelt dem
   Entwickler vorlegen.
5. **Antworten einarbeiten** — Entscheidungen in `planning/decisions/DEC-NNN.md`
   dokumentieren. Annahmen in der Story-Spezifikation aktualisieren.
6. **Design Contract Mapping vervollstaendigen** (falls `design_contract_provenance.id_map`
   vorhanden) — Alle PENDING- und COLLISION-Eintraege reconcilieren. Bestaettigte
   Quell-Entscheidungen canonisieren (DIRECT / MAPPED / EXCLUDED). Quell-Beziehungen
   in kanonische Felder uebersetzen. Vollstaendiger Vertrag:
   `agents/refinement-agent.md` — Design Contract Source-to-Canonical Mapping.
7. **Iterieren** — Wenn neue Fragen entstehen, erneut Rueckfragen formulieren.
   Erst weiter wenn alle Blocker aufgeloest sind.

## Output

- Aktualisierte Story-Spezifikation ohne offene Blocker
- Neue Eintraege in `planning/decisions/DEC-NNN.md`
- Akzeptanzkriterien in der Story-Spezifikation
