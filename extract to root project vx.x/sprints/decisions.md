# Architektur- und Fachentscheidungen

Dokumentiere hier verbindliche Architektur- und Fachentscheidungen, die nicht als
Akzeptanzkriterium einer einzelnen User Story gepflegt werden.

## Abgeleitete Arbeitsartefakte

Wenn Mendix Epics als Backlog-Quelle festgelegt ist, sind lokale technische
Spezifikationen, Testmatrizen, Traceability- und Abhaengigkeitsmatrizen unter `planning/`
versionierte Ableitungen, kein zweites Backlog und kein zweiter Sprintplan. Jedes
storybezogene Artefakt referenziert Board-Story-ID und Source Fingerprint. Nach jedem
Board-Sync prueft `scripts/reconcile-derived-artifacts.ps1` die Referenzen; das Board
gewinnt bei Abweichungen.

## Implementation Waves und Board-Aktionen

Implementation Waves unter `planning/execution-waves.md` beschreiben nur technische
Reihenfolge innerhalb eines Board-Sprints und sind keine lokalen Sprints. Der Bericht
`planning/generated/board-action-report.md` ist eine manuelle Checkliste. Nur erhebliche
fachliche Abweichungen erfordern Board-Aenderungen; technische Verfeinerung bleibt lokal.