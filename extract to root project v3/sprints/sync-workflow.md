# Mendix Epics Synchronisierung

## Source of Truth

Wenn das Mendix Epics Board als Backlog-Quelle festgelegt ist, ist es verbindlich
fuer User Stories, Akzeptanzkriterien, Sprintzuordnung, Priorisierung und
Workflow-Status. Lokale Dateien ersetzen oder aktualisieren diese Informationen nicht.

## Vor Jeder Story-Arbeit

1. `.env.mendix.example` nach `.env.mendix` kopieren und den PAT mit Scope
   `mx:epics:read` sowie die Mendix App-ID hinterlegen.
2. `scripts/sync-epics-stories.ps1` ausfuehren.
3. `scripts/reconcile-derived-artifacts.ps1` ausfuehren und den Bericht unter
   `planning/generated/` auf Abweichungen pruefen.
4. `scripts/generate-board-action-report.ps1` ausfuehren und nur bei vorhandenen
   Eintraegen die benoetigten Board-Aktionen pruefen.
5. `sprints/generated/epics-stories.md` mit Storys und zugehoerigen Tasks sowie bei
   Bedarf `sprints/generated/epics-snapshot.json` lesen.
6. Die passende Story-ID, Akzeptanzkriterien und relevanten Input-Resources pruefen.
7. Erst danach planen oder implementieren.

## Regeln

- Der Sync ist strikt read-only und verwendet ausschliesslich GET-Anfragen.
- `sprints/generated/` ist generiert und darf nicht manuell bearbeitet werden.
- Aenderungen an Storys, Sprintzuordnung oder Status erfolgen ausschliesslich im
  Mendix Epics Board.
- Versionierte Artefakte unter `planning/` referenzieren Board-ID und Source Fingerprint.
   Der Bericht unter `planning/generated/` ist nur ein Hinweis und veraendert sie nicht.
- Implementation Waves sind lokale technische Reihenfolge, kein zweiter Sprintplan.
- Der Board-Aktionsbericht ist nur eine Checkliste. Status- und Taskaenderungen werden
   ausschliesslich manuell im Mendix Epics Board vorgenommen.
- Architektur- und Fachentscheidungen, die nicht in die Story gehoeren, werden in
  `sprints/decisions.md` festgehalten.