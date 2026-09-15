# _maintenance

Dieser Ordner liegt im Framework-Root, nicht im Payload
(`extract to root project vx.x/`). Er sammelt Sitzungsnotizen und
Evaluationsprotokolle, die bei der Weiterentwicklung des Templates entstanden
sind, aber keine generischen, projektunabhaengigen Anleitungen sind.

## Warum diese Dateien nicht im Payload liegen

Das Payload ist ein auslieferbares Produkt (siehe
`.github/copilot-instructions.md`, Abschnitt "Working rules"). Es darf keine
Sitzungszustaende, falsifizierten Hypothesen oder Formulierungen eines
konkreten Konsumentenprojekts enthalten.

- `ce0066-automation-todo.md` — Sitzungsnotiz mit Datumsstempel und
  falsifizierten Hypothesen einer konkreten CE0066-Untersuchung. Enthielt
  zusaetzlich die Zeile "No git write operations in this project workflow",
  die der Versionskontrollregel in `AGENT.md` (Commits vorbereiten, dann
  bestaetigen lassen; Autopilot moeglich) widerspricht.
- `mendix-extension-evaluation-todo.md` — Evaluationsnotiz, die sich
  durchgehend auf "in this project" bezieht statt auf generische
  Templatenutzung.

Beide Dateien wurden am 2026-09-15 aus
`extract to root project vx.x/planning/` hierher verschoben, nicht geloescht.
Sie bleiben als Referenz fuer die Framework-Maintainer erhalten, falls die
darin dokumentierten Experimente (CE0066-Automatisierung,
Extension-Evaluation) fortgesetzt werden.
