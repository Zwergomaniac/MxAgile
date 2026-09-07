# Backlog-Synchronisierung und abgeleitete Artefakte

## Mendix Epics Board (optional, D52)

Das Mendix Epics Board ist ein Management-Instrument fuer Tracking und Priorisierung.
Es ist NICHT die primaere fachliche Quelle — Mockup + Requirements-Dokument haben
Vorrang (siehe `policies/source-priority.md`).

Nicht jedes Projekt hat ein Board. Wenn kein Board konfiguriert ist, entfallen die
folgenden Sync-Schritte ohne den Prozess zu blockieren.

Wenn ein Board vorhanden ist, vor Planung oder Umsetzung einer Board-Story:

1. `scripts/sync-epics-stories.ps1` ausfuehren
2. Passenden generierten Snapshot unter `sprints/generated/` lesen
3. Snapshots sind read-only; Story- und Statusaenderungen werden ausschliesslich
   im Mendix Epics Board vorgenommen

## Abgeleitete Arbeitsartefakte

Technische Spezifikationen, Testmatrizen, Traceability- und Abhaengigkeitsmatrizen
unter `planning/` muessen enthalten:

- Board-Story-ID
- `Source fingerprint` aus dem aktuellen Snapshot

Nach jedem Board-Sync `scripts/reconcile-derived-artifacts.ps1` ausfuehren.
Bei abweichendem oder fehlendem Board-Input das Artefakt nicht als aktuell behandeln;
das Board bleibt verbindlich.

## Wave-Reports und Board-Traceability

Nach Abschluss einer Wave erstellt der Agent einen versionierten Bericht unter
`planning/wave-reports/`. Er nennt:

- Betroffene Board-Story-IDs
- Erledigten Umfang
- Testnachweise
- Offene Gates
- Manuelle Board-Aktionen

Wave-relevante Commits nennen die Story-IDs explizit:
`feat: implement foundation [CAP-123] [CAP-124]`

Das ist Traceability und aendert keinen Board-Status. Das manuelle Abhaken erfolgt
erst nach Pruefung des Berichts und ueber `scripts/generate-board-action-report.ps1`.
